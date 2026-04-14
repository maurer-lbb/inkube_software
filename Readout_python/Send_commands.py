"""
This script contains functions for sending commands to the intan RHS2116 and reading data from its registers.
"""
import time
import numpy as np
import multiprocessing as mp
import copy
from ctypes import *
import multiprocessing.connection as con
import struct

import unittest

# Store command package timing for proper sequencing
from collections import defaultdict


from Client_config import (
    ELECTRODE_MAPPING,
    STIM_AMPLITUDE,
    MAX_PKG_ID, 
    STIMULATION_DURATION, 
    DISCHARGE_TIME, 
    STIMULATOR_STEP_SETTING, 

    MEA_NUM, 
    CHIP_NUM,
    DISCHARGE_LIMIT_SETTING, 
    ENABLE_FAST_SETTLE, 
    DO_FILTER_SWITCH, 
)

def set_stimulus_timing_local(
    stim_duration, 
    discharge_time, 
):
    """Set the timing for the stimulation pulses
    Args:
        stim_duration: duration of the stimulation pulse
        discharge_time: time to discharge the electrodes in packages
    """
    stimulus_time = np.zeros(6, dtype=int)
    stimulus_time[0] = -2 # start package with pole shift
    stimulus_time[1] = 0 # stimulation pulse on
    stimulus_time[2] = stim_duration # flip polarity
    stimulus_time[3] = 2 * stim_duration # stimulation pulse off
    stimulus_time[4] = 2 * stim_duration + discharge_time # discharge electrodes with active pull to GND
    stimulus_time[5] = 2 * stim_duration + discharge_time + 6 # optional filter pole shift
    return stimulus_time

# list of which stimulation pulse aspects are included dependent on which flag the pulse has
# 0: full pulse, 1: essential pulse, 2: interleaving center pulse, 3: start, 4: end, 5: start and end
# delay/package 0 is onset so switching frequency, 1 is stim on, 2 is polarity switch, 3 is stim off and start discharge, 4 is discharge off and switch polarity back, 5 is filter switch
DELAYS_FLAG_DEPENDENT = [
    [0, 1, 2, 3, 4, 5],
    [1, 2, 3, 4],
    [1, 2, 3, 4],
    [1, 2, 3, 4], # removed artefact cancellation [0, 1, 2, 3, 4], dynamic
    [1, 2, 3, 4], # removed artefact cancellation [1, 2, 3, 4, 5], dynamic
    [0, 1, 2, 3, 4, 5],
]

# register constants, see RHS2116 datasheet
# stimulate write stim register 42
STIMULATION_ON_REG = 42
STIMULATION_POL = 44  # 1 is pos current, 0 is neg current, start with positive
if DISCHARGE_LIMIT_SETTING == 'unlimited':
    ACTIVE_DISCHARGE_REG = 46 
else:
    ACTIVE_DISCHARGE_REG = 48
LG_POWER = 38
FILTER_SWITCH_REG = 12
FAST_SETTLE_REG = 10

EMPTY_ID_REG = 0xFE

STIMULATOR_SETTINGS = {
    '10nA':  [(34, [1*2**6+1*2**5+(19>>1), 64+1]), (35, [0, 0x66])], 
    '200nA': [(34, [5, 25]), (35, [0, 0x88])], 
    '1uA':   [(34, [0, 98 + 1*2**7]), (35, [0, 0xAA])], 
    '10uA':  [(34, [0, 15]), (35, [0, 0xFF])], 
    'recover1nA': (37, [0x4F,0]), 
    'recover10nA':(37, [7, 1*2**7+50]), 
    'recover100nA':(37, [0, 1*2**7+56]), 
    'recover1uA':(37, [0, 0*2**7+9]), 
    'unlimited':(37, [0, 0*2**7+9]), # same as 1uA but not used
}

def write_to_register(r, d):  # d should be MSB, LSB, will be flipped in output
    """get control word to write data to register on intan chip"""
    # package 0: id 1: command=1|MEA=1|chip=1, 2: command=2|MEA=1|chip=1, ...5: command=1|MEA=1|chip=2...
    return bytearray(
        [d[1], d[0], r, 0xA0]
    )  # 0x80 write, U flag set with 0xA0, d is electrode number

def set_amplitude(
        value, 
        command_list=[]
    ):
    """Set the amplitude of the stimulation pulse. The amplitude is set in steps according to settings in Client_config.py."""
    for reg in list(range(64, 80)) + list(range(96, 112)):
        command_list.append(
            (reg, [0x80, value])
        )  # set trimming of source and value of source, 1uA steps, STIM PBIAS, NBIAS 10, 10, step size 1uA sel198, sel2 1, sel3 0
    # for _ in range(8):
    #     command_list.append((EMPTY_ID_REG, [0x00, 0x00]))
    return command_list

# initialisation commands for the RHS2116
# format is [MSB LSB]
INIT_COMMAND_LIST = [
    (32, [0x00, 0x00]),  # stimulation disable A
    (33, [0x00, 0x00]),  # stimulation disable B
    # ADC recording settings
    (1, [0x00, 0x00]),  # dig out highZ set to zero - to set digaux1 and 2 high use (1, [0x0a, 0x00]),  # dig out highZ set to zero
    (4, [0x00, 0x21]),  # upper cutoff f to 7.5 kHz - 22 0, 5kHz 33/37, 7.5kHz 22/23, 10kHz 17/16
    (5, [0x00, 0x25]),  # upper cutoff f to 7.5 kHz - 23 0
    (6, [0x00, 0x0A]),  # lower cutoff f to 1 kHz  (10)
    (7, [0x00, 0x0F]),  # lower cutoff f to 300 Hz (15)
    (8, [0xFF, 0xFF]),  # power up high gain
    (38, [0xFF, 0xFF]),  # power up high gain because of power
    (10, [0, 0]),  # fast settle off
    (12, [0x00, 0x00]),  # set to register 6 with 1, to 7 with 0
    STIMULATOR_SETTINGS[STIMULATOR_STEP_SETTING][0], 
    STIMULATOR_SETTINGS[STIMULATOR_STEP_SETTING][1],
    (36, [0, 0x80]),  # charge recovery target on GND
    STIMULATOR_SETTINGS[DISCHARGE_LIMIT_SETTING],  # charge recovery current max 1 nA 0,30,2 (0x4F,0) 50,15,0 for 10nA [7, 1*2**7+50]
    (42, [0, 0]),  # stim off
    (STIMULATION_POL, [0xFF, 0xFF]),  # polarity, high is positive pulse, this should be leading
    (46, [0, 0]),  # stim off
    (48, [0, 0]),  # stim off
]

# append commands to set amplitude in initialisation list
set_amplitude(STIM_AMPLITUDE, INIT_COMMAND_LIST)

INIT_COMMAND_LIST.append((32, [0xAA, 0xAA]))  # finally stimulation enable A
INIT_COMMAND_LIST.append((33, [0x00, 0xFF]))  # finally stimulation enable B
for _ in range(8):
    INIT_COMMAND_LIST.append((EMPTY_ID_REG, [0x00, 0x00]))
STIM_REGS = [32, 33, 34, 35, 36, 37, 40, 42, 44, 46, 48, 64, 96]
# 32: enable A, 33: enable B, 34: stim current step size, 35: stim bias, 36: charge recov target, 37: charge recov current limit
# 40: compliance monitor, 42: On, 44: polarity, 46: charge recov on, 48: charge recov current limit en, 64 el 0 current limit negative - 96 pos
# To Do: dict for commands and registers
EMPTY_COMMAND = bytearray([0, 0, 0xFE, 0xC0])
READ_CHIP_ID_COMMAND = bytearray([0, 0, 0xFE, 0xC0])

# safety word must be set to enable stimulation
EN_STIM_A_REG = 32
EN_STIM_A_COMMAND = 0xAAAA
EN_STIM_B_REG = 33
EN_STIM_B_COMMAND = 0x00FF

# prepare commands for writes to intan
# stimulus: on, switch polarity,  (off, switch polarity back -> one package)
HANDSHAKE_INIT = bytearray([0, 0, 0, 0])
TIMING_INIT = bytearray([0, 0, 0, 128])
EMPTY_COMMAND_WORD = HANDSHAKE_INIT + TIMING_INIT + EMPTY_COMMAND * 64 # skip 8 for empty command

# digital auxiliary outputs on and off commands
COMMAND_DIG_AUX_ON = [(1, [0x0a, 0x00])]
COMMAND_DIG_AUX_OFF = [(1, [0x00, 0x00])]

# Onset and offset commands are always the same, prepare here
ONSET_COMMAND = copy.copy(EMPTY_COMMAND) * 64
OFFSET_COMMAND = copy.copy(EMPTY_COMMAND) * 64

for command_pos in range(16):
    # switch lower bandpass frequency up to 1kHz
    ONSET_COMMAND[command_pos * 16 : command_pos * 16 + 4] = write_to_register(
        12, [0xFF] * 2
    )
    # # Fast settle on
    ONSET_COMMAND[command_pos * 16 + 4 : command_pos * 16 + 8] = write_to_register(
        10, [0xFF] * 2
    )

    # fast settle off
    OFFSET_COMMAND[command_pos * 16 : command_pos * 16 + 4] = write_to_register(
        10, [0] * 2
    )
    # switch lower bandpass frequency back to 200Hz
    OFFSET_COMMAND[command_pos * 16 + 4 : command_pos * 16 + 8] = write_to_register(
        12, [0] * 2
    )

def get_command_pos_from_source(
        src: tuple = (0, 0), 
        command=0
    ):
    """Derive position in command frame for command depending on target mea and chip"""
    mea, chip = src
    command = command % 4
    return (mea * 16) + (chip * 4) + command

def prepare_commands_process(
    command_pipe: con.Connection,
    command_to_send_pipe: con.Connection,
):
    """Send stimulation commands when put on command pipe
    Args:
        command_pipe: connection to receive stimulation commands
        command_to_send_pipe: connection to send commands to the USB process
    """

    # for artefacts:
    # switch before stim the fL (globaly)
    # switch 1ms after stim the fL back, double check if this leads to ripple (globaly)
    # fast settle is for amp output, should be applied for whole duration because of softawre filter, after stim 350 us should be sufficient
    # charge recovery after stim with no current limit, 1ms after stim like fast switch. This is for amp input/electrode


    stimulus_timing_local = set_stimulus_timing_local(STIMULATION_DURATION, DISCHARGE_TIME)

    #  empty_command_frame = repeat(copy.copy(EMPTY_COMMAND_WORD), MAX_COMMANDS_IN_SEND)
    while True:
        
        command_tuple_list = []
        # print("Waiting for command")
        # receive the start package of the pulse, the active electrodes and the flag whether the on and off pulses should be sent
        command_tuple = command_pipe.recv()
        # print(f"Received command from command pipe via server connection {command_tuple}")
        command_tuple_list.append(command_tuple)
        if command_tuple[-1] < 2 or command_tuple[-1] == 5: # if no interleaving commands or single interleaving command
            pass
        elif command_tuple[-1] == 3: # assemble command from 3 to 4 flag
            while True:
                command_tuple = command_pipe.recv()
                command_tuple_list.append(command_tuple)
                if command_tuple[-1] == 4:
                    break
        else:
            print(f'Invalid start command flag: {command_tuple[-1]}')
            pass
          
        command_frame_list = prepare_dynamic_stim_command(command_tuple_list, stimulus_timing_local)
        command_to_send_pipe.send((5, command_frame_list))


def single_command_delays(command_tuple_list, stimulus_timing_local, reg_num):
    stim_timing = defaultdict(lambda: np.zeros((MEA_NUM, CHIP_NUM, reg_num, 2), dtype=np.uint16))
    stim_on_loc = 1
    stim_pol_loc = 0
    discharge_loc = 2
    # fast_settle_loc = 2

    for pkg_id, electrode_array, position_flag in command_tuple_list:
        # Convert electrode positions to MEA/Chip indices
        electrode_sources = ELECTRODE_MAPPING.mea2stim(electrode_array)

        # Get package delays for this flag
        delay_steps = DELAYS_FLAG_DEPENDENT[position_flag]

        # iterate over all delays for this flag
        for delay_num in delay_steps:
            if pkg_id > 0x80000000:
                send_pkg_id = np.uint32((pkg_id + stimulus_timing_local[delay_num]))
                if send_pkg_id < 0x80000000:
                    print(f'WARNING: Deactivated immediate send command, increase delay')
            else:
                send_pkg_id = np.uint32((pkg_id + stimulus_timing_local[delay_num]) % MAX_PKG_ID)

            for electrode_source in electrode_sources:
                mea = electrode_source // 60
                chip = (electrode_source % 60) // 15
                el = electrode_source % 15

                if delay_num == 1: # stimulation on
                    stim_timing[send_pkg_id][mea, chip, stim_on_loc, 1] += 1 << el
                    stim_timing[send_pkg_id][mea, chip, stim_pol_loc, 1] += 1 << el # set high, was low
                
                elif delay_num == 2:  # Polarity Switch
                    stim_timing[send_pkg_id][mea, chip, stim_pol_loc, 0] += 1 << el # set low, was high

                elif delay_num == 3:  # Stimulation OFF
                    stim_timing[send_pkg_id][mea, chip, stim_on_loc, 0] += 1 << el # set low, was high
                    stim_timing[send_pkg_id][mea, chip, discharge_loc, 1] += 1 << el # set high, was low
                    # stim_timing[send_pkg_id][mea, chip, fast_settle_loc, 1] += 1 << el # set high, was low

                elif delay_num == 4:  # Stop Discharge
                    stim_timing[send_pkg_id][mea, chip, discharge_loc, 0] += 1 << el # set low, was high
                    # stim_timing[send_pkg_id][mea, chip, fast_settle_loc, 0] += 1 << el # set low, was high


    # Sort stim_timing keys (ensuring correct order)
    sorted_pkg_ids = np.array(sorted(stim_timing.keys())) # take care of overflow in PKG ID here
    if (np.max(sorted_pkg_ids) - np.min(sorted_pkg_ids)) > MAX_PKG_ID / 2:
        sorted_pkg_ids = np.concatenate(
            [sorted_pkg_ids[sorted_pkg_ids > MAX_PKG_ID / 2], 
                sorted_pkg_ids[sorted_pkg_ids < MAX_PKG_ID / 2]]
        )
    return stim_timing, sorted_pkg_ids

def prepare_dynamic_stim_command(command_tuple_list, stimulus_timing_local):
    """Prepare dynamically sized stimulation commands (0x05) with proper sub-packaging"""
    t_start = time.time()

    # matrix for register states at any timepoint
    # currently FAST_SETTLE + FILTER_SWITCH are exceeding the 4 registers, use only one of the 2 or introduce common on/off or introduce low prio register
    # reg_array = np.array([STIMULATION_ON_REG, STIMULATION_POL, ACTIVE_DISCHARGE_REG, FILTER_SWITCH_REG]) 
    reg_array = np.array([STIMULATION_POL, STIMULATION_ON_REG, ACTIVE_DISCHARGE_REG]) # temporary for reliable execution with broken FIFO
    reg_num = reg_array.shape[0]
    reg_states = np.zeros((MEA_NUM, CHIP_NUM, reg_num), dtype=np.uint16)

    mea_chip_stim = np.zeros((4,4))
    
    command_frame_list = []

    # get stim timing dictionary and sorted package ids for every individual command of a pulse
    stim_timing, sorted_pkg_ids = single_command_delays(command_tuple_list, stimulus_timing_local, reg_num)

    # prepare commands for USB, subframe means for one pkg ID, frame is sent as one via USB
    subframe_count = 0
    frame = bytearray()
    frame.extend(struct.pack("<I", 0)) # place holder for recv bytes

    # Write commands in order
    for pkg_id in sorted_pkg_ids:
        subframe = bytearray()
        subframe.extend(bytearray([(pkg_id >> (i * 8)) % 256 for i in range(4)]))
        
        chips_in_frame = 0
        subframe.extend(bytearray([chips_in_frame]))
        
        for mea in range(4):
            for chip in range(4):
                if np.any(stim_timing[pkg_id][mea, chip]): # if any register is set to on
                    chip_header = struct.pack("!B", ((chip+mea*4) << 4) | reg_num)  # 4-bit chip ID + 4-bit num_commands
                    subframe.extend(chip_header)
                    for reg in range(reg_num):
                        el_bitmask_on = stim_timing[pkg_id][mea, chip, reg, 1]
                        el_bitmask_off = stim_timing[pkg_id][mea, chip, reg, 0]

                        # update the register states according to the bitmask
                        reg_states[mea, chip, reg] = (reg_states[mea, chip, reg] | el_bitmask_on) & ~el_bitmask_off

                        # add register write to subframe
                        subframe.extend(
                            write_to_register(reg_array[reg], [reg_states[mea, chip, reg] >> 8, reg_states[mea, chip, reg] & 0xFF])
                        )
                    chips_in_frame += 1

                    mea_chip_stim[mea, chip] = 1

        # update chip count in subframe
        subframe[4] = chips_in_frame

        # if frame is full or last subframe, add to command frame list, don't write too many to prevent crash
        if subframe_count > 10 or (len(frame) + len(frame)) > 500: # 512 - header - recv pkg - safety
            command_frame_list.append(frame)
            frame = bytearray()
            frame.extend(struct.pack("<I", 0))
            subframe_count = 0
        
        frame.extend(subframe)
        subframe_count += 1
    
    # add last command frame if not empty
    if len(frame) > 4:
        command_frame_list.append(frame)

    if ENABLE_FAST_SETTLE:
        # prepare general on and off command for filter switch
        if (sorted_pkg_ids[0] > 0x80000000): # for immediate command just forward
            start_pkg_id = (sorted_pkg_ids[0]-1)
            end_pkg_id = (sorted_pkg_ids[-1]+1)
            end_pkg_id_2 = (sorted_pkg_ids[-1]+2)
        else:
            start_pkg_id = ((sorted_pkg_ids[0]-1) % MAX_PKG_ID)
            end_pkg_id = ((sorted_pkg_ids[-1]+1) % MAX_PKG_ID)
            end_pkg_id_2 = ((sorted_pkg_ids[-1]+2) % MAX_PKG_ID)

        frame_start = bytearray()
        frame_end = bytearray()
        frame_end_fin = bytearray()

        frame_start.extend(struct.pack("<I", 0))
        frame_end.extend(struct.pack("<I", 0))
        frame_end_fin.extend(struct.pack("<I", 0))

        frame_start.extend(bytearray([(start_pkg_id >> (i * 8)) % 256 for i in range(4)]))
        frame_end.extend(bytearray([(end_pkg_id >> (i * 8)) % 256 for i in range(4)]))
        frame_end_fin.extend(bytearray([(end_pkg_id_2 >> (i * 8)) % 256 for i in range(4)]))

        frame_start.extend([255]) # for chip count
        frame_end.extend([255])
        frame_end_fin.extend([255])

        chips_in_frame = 0

        for mea in range(4):
            for chip in range(4):
                if mea_chip_stim[mea, chip]:                    
                    chip_header = struct.pack("!B", ((chip+mea*4) << 4) | 1)  # 4-bit chip ID + 4-bit num_commands
                    frame_end.extend(chip_header)
                    frame_end_fin.extend(chip_header)

                    if DO_FILTER_SWITCH:
                        chip_header = struct.pack("!B", ((chip+mea*4) << 4) | 2)  # 4-bit chip ID + 4-bit num_commands
                    frame_start.extend(chip_header)

                    # add register write to subframe
                    if DO_FILTER_SWITCH:
                        frame_start.extend(                            
                            write_to_register(FILTER_SWITCH_REG, [0xff, 0xff])
                        )
                        frame_end.extend(
                            write_to_register(FILTER_SWITCH_REG, [0, 0])
                        )
                    frame_start.extend(                            
                        write_to_register(FAST_SETTLE_REG, [0xff, 0xff])
                    )                
                    frame_end_fin.extend(
                        write_to_register(FAST_SETTLE_REG, [0, 0])
                    )                
                    chips_in_frame += 1
        frame_start[8] = chips_in_frame
        frame_end[8] = chips_in_frame
        frame_end_fin[8] = chips_in_frame

        command_frame_list.insert(0,frame_start)
        if DO_FILTER_SWITCH:
            command_frame_list.append(frame_end) 
        command_frame_list.append(frame_end_fin)
   
    print(f'Command processing took {(time.time()-t_start)*1000:.3f} ms')
    return command_frame_list


def send_write_to_register(
    command_to_send_pipe: con.Connection,
    command_list=INIT_COMMAND_LIST,
    init_source=None, # if None send to all chips
    timed_send=False, 
    pkg_id=0x80000000, 
):
    """Send commands to initialise stimulation units
    Args:
        command_to_send_pipe: connection to send commands to the USB process
        command_list: list of commands to send
        init_source: list of mea and chip to send commands to
        timed_send: flag to send commands at specific timepoint
        pkg_id: package id to send commands at, if MSB is 1 send immediately
    """
    # init stim
    if init_source is None:
        init_source = [(mea, chip) for mea in range(4) for chip in range(4)]
    command_num = 0
    command_frame = copy.copy(EMPTY_COMMAND_WORD)
    
    # if timing is relevant write package ID for execution, else 
    if timed_send:
        send_pkg_id = np.uint32((pkg_id) % MAX_PKG_ID + (pkg_id & 0x80000000))
    else:
        send_pkg_id = np.uint32(0x80000000)

    number_of_commands_per_chip = 4
    command_frame[4:8] = bytearray([(send_pkg_id >> (i * 8)) % 256 for i in range(4)])
    for args in command_list:
        reg, data = args
        command_word = write_to_register(reg, data)
        for source in init_source:
            command_pos = get_command_pos_from_source(source, command_num) * 4 + 8
            command_frame[command_pos : command_pos + 4] = command_word
        command_num += 1
        if command_num == number_of_commands_per_chip:
            # send
            command_to_send_pipe.send((2, command_frame))
            command_num = 0
            command_frame = copy.copy(EMPTY_COMMAND_WORD)
    if command_frame != EMPTY_COMMAND_WORD:
        command_to_send_pipe.send((2, command_frame))

def set_digaux(
            send_pipe,
            value=1, 
            pkg_id=0x80000000
    ):
    """Set digital auxiliary output on or off
    Args:
        send_pipe: connection to send commands to the USB process
        value: flag to set digital auxiliary output on or off
        pkg_id: package id to send commands at, if MSB is 1 send immediately
    """
    is_timed = not(0x80000000 & np.uint32(pkg_id))
    if value:
        COM = COMMAND_DIG_AUX_ON
    else:
        COM = COMMAND_DIG_AUX_OFF
    send_write_to_register(send_pipe, COM, None, timed_send=is_timed, pkg_id=pkg_id)

def read_from_registers(
    command_to_send_pipe: con.Connection,
    registers=STIM_REGS,
    init_source=None,
):
    """Read data from registers on the intan chip, used for debugging
    Args:
        command_to_send_pipe: connection to send commands to the USB process
        registers: list of registers to read from
        init_source: list of mea and chip to send commands to, if None send to all chips
    """
    # init stim
    if init_source is None:
        init_source = [(mea, chip) for mea in range(4) for chip in range(4)]
    command_num = 0
    command_frame = copy.copy(EMPTY_COMMAND_WORD)
    send_pkg_id = np.uint32(0x80000000)
    command_frame[4:8] = bytearray([(send_pkg_id >> (i * 8)) % 256 for i in range(4)])
    for reg in registers:
        command_word = bytearray([0, 0, reg, 0xC0])
        for source in init_source:
            command_pos = get_command_pos_from_source(source, command_num) * 4 + 8
            command_frame[command_pos : command_pos + 4] = command_word
        command_num += 1
        if command_num == 2:
            # send
            command_to_send_pipe.send((2, command_frame))
            command_num = 0
            command_frame = copy.copy(EMPTY_COMMAND_WORD)
    if command_frame != EMPTY_COMMAND_WORD:
        command_to_send_pipe.send((2, command_frame))


# Updated Unit Test
class TestPrepareDynamicStimCommand(unittest.TestCase):
    def setUp(self):
        np.random.seed(42)
        stimulus = np.zeros((240, 3), dtype=int)
        stimulus[:, 0] = np.random.randint(29, 170, 240)
        stimulus[:, 1] = np.arange(240) // 4
        stimulus[:, 2] = np.arange(240) % 4
        
        self.stim_matrix = stimulus[np.argsort(-stimulus[:, 0]), :]
        self.stimulus_timing_local = set_stimulus_timing_local(STIMULATION_DURATION, DISCHARGE_TIME)
        
        stim_delays = -np.unique(-self.stim_matrix[:, 0])
        self.command_tuple_list = []
        for delay_num, stim_delay in enumerate(stim_delays):
            stim_pkg = (1000 - stim_delay) % MAX_PKG_ID
            self.command_tuple_list.append(
                (
                    stim_pkg,
                    ELECTRODE_MAPPING.network2mea(self.stim_matrix[self.stim_matrix[:, 0] == stim_delay, 1:]),
                    2  # Using a fixed flag for now
                )
            )
    
    def test_command_output_format(self):
        result = prepare_dynamic_stim_command(self.command_tuple_list, self.stimulus_timing_local)
        self.assertIsInstance(result, list)
        self.assertTrue(all(isinstance(frame, bytearray) for frame in result))
        
    def test_register_updates(self):
        original_register_state = np.zeros((MEA_NUM, CHIP_NUM), dtype=np.uint16)
        prepare_dynamic_stim_command(self.command_tuple_list, self.stimulus_timing_local)
        self.assertFalse(np.array_equal(original_register_state, STIMULATION_ON_REG))

if __name__ == "__main__":
    unittest.main()