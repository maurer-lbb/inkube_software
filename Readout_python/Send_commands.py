"""
This script contains functions for sending commands to the intan RHS2116 and reading data from its registers.
"""
import time
import numpy as np
import multiprocessing as mp
import threading
import copy
from ctypes import *
import os
import multiprocessing.connection as con

from Client_config import (
    CLIENT_ADDRESS_PORT,
    LINUX,
    ELECTRODE_MAPPING,
    STIM_AMPLITUDE,
    MAX_PKG_ID, 
    STIMULATION_DURATION, 
    DISCHARGE_TIME, 
    STIMULATOR_STEP_SETTING, 
    WORD_LENGTH_IN_BYTES, 
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
# 0: essential pulse, 1: start, 2: end, 3: start and end
DELAYS_FLAG_DEPENDENT = [
    [1, 2, 3, 4],
    [0, 1, 2, 3, 4],
    [1, 2, 3, 4, 5],
    [0, 1, 2, 3, 4, 5],
]

# register constants, see RHS2116 datasheet
# stimulate write stim register 42
STIMULATION_ON_REG = 42
STIMULATION_POL = 44  # 1 is pos current, 0 is neg current
LG_POWER = 38

STIMULATOR_SETTINGS = {
    '10nA':  [(34, [1*2**6+1*2**5+(19>>1), 64+1]), (35, [0, 0x66])], 
    '200nA': [(34, [5, 25]), (35, [0, 0x88])], 
    '1uA':   [(34, [0, 98 + 1*2**7]), (35, [0, 0xAA])], 
    '10uA':  [(34, [0, 15]), (35, [0, 0xFF])], 
    'recover1nA': (37, [0x4F,0]), 
    'recover10nA':(37, [7, 1*2**7+50]), 
    'recover100nA':(37, [0, 1*2**7+56]), 
    'recover1uA':(37, [0, 0*2**7+9]), 
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
    return command_list

# initialisation commands for the RHS2116
# format is [MSB LSB]
INIT_COMMAND_LIST = [
    (32, [0x00, 0x00]),  # stimulation disable A
    (33, [0x00, 0x00]),  # stimulation disable B
    # ADC recording settings
    (1, [0x00, 0x00]),  # dig out highZ set to zero - to set digaux1 and 2 high use (1, [0x0a, 0x00]),  # dig out highZ set to zero
    (4, [0x00, 0x16]),  # cutoff f to 7.5 kHz - 22 0
    (5, [0x00, 0x17]),  # cutoff f to 7.5 kHz - 23 0
    (6, [0x00, 0x0A]),  # lower cutoff f to 1 kHz  (10)
    (7, [0x00, 0x12]),  # lower cutoff f to 200 Hz (18)
    (8, [0xFF, 0xFF]),  # power up high gain
    (38, [0xFF, 0xFF]),  # power up high gain because of power
    (10, [0, 0]),  # fast settle off
    (12, [0x00, 0x00]),  # set to register 6 with 1, to 7 with 0
    STIMULATOR_SETTINGS[STIMULATOR_STEP_SETTING][0], 
    STIMULATOR_SETTINGS[STIMULATOR_STEP_SETTING][1],
    (36, [0, 0x80]),  # charge recovery target on GND
    STIMULATOR_SETTINGS['recover1nA'],  # charge recovery current max 1 nA 0,30,2 (0x4F,0) 50,15,0 for 10nA [7, 1*2**7+50]
    (42, [0, 0]),  # stim off
    (STIMULATION_POL, [0xFF, 0xFF]),  # polarity, high is positive pulse, this should be leading
    (46, [0, 0]),  # stim off
    (48, [0, 0]),  # stim off
]

# append commands to set amplitude in initialisation list
set_amplitude(STIM_AMPLITUDE, INIT_COMMAND_LIST)

INIT_COMMAND_LIST.append((32, [0xAA, 0xAA]))  # finally stimulation enable A
INIT_COMMAND_LIST.append((33, [0x00, 0xFF]))  # finally stimulation enable B

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
EMPTY_COMMAND_WORD = HANDSHAKE_INIT + TIMING_INIT + EMPTY_COMMAND * 64

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
    return (mea * 16) + (chip * 4) + command + 1

def prepare_commands_process(
    command_pipe: con.Connection,
    command_to_send_pipe: con.Connection,
    newest_recv_pkg, 
):
    """Send stimulation commands when put on command pipe
    Args:
        command_pipe: connection to receive stimulation commands
        command_to_send_pipe: connection to send commands to the USB process
        newest_recv_pkg: shared array to store the latest received package id from the UDP stream
    """
    commands_in_stim = 3 # maximum number of commands executed at the same timepoint (package id)

    stimulus_timing_local = set_stimulus_timing_local(STIMULATION_DURATION, DISCHARGE_TIME)

    #  empty_command_frame = repeat(copy.copy(EMPTY_COMMAND_WORD), MAX_COMMANDS_IN_SEND)
    while True:
        stim_chips = []
        # receive the start package of the pulse, the active electrodes and the flag whether the on and off pulses should be sent
        pkg_id, electrode_array, position_flag = command_pipe.recv()
        # print(f"Current delays: {[stimulus_timing_shared[i] for i in range(6)]}")
        # print(f"Received command from command pipe via server connection {pkg_id}, {electrode_array}, {position_flag}")
        # if pkg id < 0 set first bit 1 for immediate execution and relative offset
        if pkg_id < 0:
            pkg_id = 0x80000000
            print("Send out package now as negative id")

        commands_in_stim = len(DELAYS_FLAG_DEPENDENT[position_flag]) 
        command_frame = copy.copy(EMPTY_COMMAND_WORD) * (commands_in_stim) # send all commands executed at a certain timepoint simultaneously to send process

        for pos, delay_num in enumerate(DELAYS_FLAG_DEPENDENT[position_flag]):
            send_pkg_id = np.uint32((pkg_id + stimulus_timing_local[delay_num]) % MAX_PKG_ID + (pkg_id & 0x80000000))
            command_frame[
                pos * WORD_LENGTH_IN_BYTES + 4 : pos * WORD_LENGTH_IN_BYTES + 8
            ] = bytearray([(send_pkg_id >> (i * 8)) % 256 for i in range(4)])
            # print(f"Prepared command with pkg_id on pos {pos} at {delay_num}: {send_pkg_id}")
            # print(f"package execution {pos}, {delay_num}, delay {DELAYS_FULL_COMMAND[delay_num]} id {send_pkg_id}")

        # for i in range(commands_in_stim):
        #     print(f"Before command fill in Execute ID {i}: {command_frame[i*WORD_LENGTH_IN_BYTES+4:i*WORD_LENGTH_IN_BYTES+8]}")

        # translate mea positions to stimulation encoding in command word
        electrode_sources = ELECTRODE_MAPPING.mea2stim(electrode_array)
        # print(f'Received electrodes {electrode_array} and translated into {electrode_sources}')

        # add onset and offset commands to first and last stimulus in sequence
        # flag 1 is start, 2 is last, 3 is if only one package
        if position_flag == 1 or position_flag == 3:
            command_frame[8:WORD_LENGTH_IN_BYTES] = ONSET_COMMAND
            start_package = 1
        else:
            start_package = 0

        if position_flag == 2 or position_flag == 3:
            command_frame[-WORD_LENGTH_IN_BYTES + 8 :] = OFFSET_COMMAND
            
            # pass readout the offset
            newest_recv_pkg[1] = send_pkg_id
            # pass stimulus on package, TODO: add for number of stimuli slots 
            newest_recv_pkg[2] = np.uint32((pkg_id+1) % MAX_PKG_ID)
            # print(f"New onset {position_flag}, {send_pkg_id}, {send_pkg_id-pkg_id}, {pos}, {DELAYS_FULL_COMMAND[delay_num]}")

        # for every stimulation electrode activate chip in commands
        for electrode_source in electrode_sources:
            mea = electrode_source // 60
            chip = (electrode_source % 60) // 15
            el = electrode_source % 15
            # print(f'Sending to mea {mea} and chip {chip} with el {el}')
            command_pos = get_command_pos_from_source((mea, chip)) + 1

            stim_el_pos = np.uint16(1 << el)
            d = [(stim_el_pos >> 8) % 256, stim_el_pos % 256]  # MSB, LSB
            # print(d)
            if command_pos not in stim_chips:
                # Package ----------------------------------------------------------------------------------
                # write to on register, goes to all electrode
                package_num = start_package
                command_frame[
                    command_pos * 4
                    + package_num * WORD_LENGTH_IN_BYTES : (command_pos + 1) * 4
                    + package_num * WORD_LENGTH_IN_BYTES
                ] = write_to_register(STIMULATION_ON_REG, d)

                # Package ----------------------------------------------------------------------------------
                package_num = start_package + 1
                # write to switch polarity register
                command_frame[
                    (command_pos) * 4
                    + package_num * WORD_LENGTH_IN_BYTES : (command_pos + 1) * 4
                    + package_num * WORD_LENGTH_IN_BYTES
                ] = write_to_register(STIMULATION_POL, [0x00] * 2)

                # Package ----------------------------------------------------------------------------------
                package_num = start_package + 2
                # write to off register
                command_frame[
                    (command_pos) * 4
                    + package_num * WORD_LENGTH_IN_BYTES : (command_pos + 1) * 4
                    + package_num * WORD_LENGTH_IN_BYTES
                ] = write_to_register(STIMULATION_ON_REG, [0] * 2)
                # start discharge on selected electrodes
                command_frame[
                    (command_pos + 1) * 4
                    + package_num * WORD_LENGTH_IN_BYTES : (command_pos + 2) * 4
                    + package_num * WORD_LENGTH_IN_BYTES
                ] = write_to_register(
                    48, d # [0xFF] * 2
                )  # d for only on stim electrodes and add to bottom else

                # Package ----------------------------------------------------------------------------------
                package_num = start_package + 3
                # stop discharge
                command_frame[
                    (command_pos) * 4
                    + package_num * WORD_LENGTH_IN_BYTES : (command_pos + 1) * 4
                    + package_num * WORD_LENGTH_IN_BYTES
                ] = write_to_register(48, [0] * 2) 
                # write to switch polarity register (switch back)
                command_frame[
                    (command_pos + 1) * 4
                    + package_num * WORD_LENGTH_IN_BYTES : (command_pos + 2) * 4
                    + package_num * WORD_LENGTH_IN_BYTES
                ] = write_to_register(STIMULATION_POL, [0xFF] * 2)

                # add to list of activated chips
                stim_chips.append(command_pos)
            else:
                package_num = start_package
                # if chip is already stimulated add missing electrode to stimulation on word
                d_temp = command_frame[
                    command_pos * 4
                    + package_num * WORD_LENGTH_IN_BYTES : command_pos * 4
                    + 2
                    + package_num * WORD_LENGTH_IN_BYTES
                ]
                d_flipped = [d[1], d[0]]  # now LSB leading
                command_frame[
                    command_pos * 4
                    + package_num * WORD_LENGTH_IN_BYTES : command_pos * 4
                    + 2
                    + package_num * WORD_LENGTH_IN_BYTES
                ] = [d_flipped[i] + d_temp[i] for i in range(2)]

                # # start discharge on selected electrodes
                package_num = start_package + 2
                command_frame[
                    (command_pos + 1) * 4
                    + package_num * WORD_LENGTH_IN_BYTES : (command_pos + 2) * 4
                    + package_num * WORD_LENGTH_IN_BYTES
                ] = write_to_register(
                    48, [d_flipped[i] + d_temp[i] for i in range(2)] # [0xFF] * 2
                )  # d for only on stim electrodes

        # if FPGA takes 3 commands or more at once send all, else split package

        command_to_send_pipe.send((2, command_frame))

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
            command_pos = get_command_pos_from_source(source, command_num) * 4 + 4
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
            command_pos = get_command_pos_from_source(source, command_num) * 4 + 4
            command_frame[command_pos : command_pos + 4] = command_word
        command_num += 1
        if command_num == 2:
            # send
            command_to_send_pipe.send((2, command_frame))
            command_num = 0
            command_frame = copy.copy(EMPTY_COMMAND_WORD)
    if command_frame != EMPTY_COMMAND_WORD:
        command_to_send_pipe.send((2, command_frame))
