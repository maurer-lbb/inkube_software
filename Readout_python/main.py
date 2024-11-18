"""
This script is the main entry point for the Readout_python application. It sets up various processes and threads for data readout, spike processing, stimulation, and plotting.
Functions:
    clear_spikes: Continuously clears spikes from the spike pipes.
    transmit_spontaneous: Transmits spontaneous spikes to the spike queue and/or raster plot.
    main: The main function that starts all the processes and threads.
"""

import socket
import time
import numpy as np
import multiprocessing as mp
import multiprocessing.sharedctypes as mp_shared
from multiprocessing.managers import BaseManager
import threading
from ctypes import *
import os
import copy
import multiprocessing.connection as con
import datetime

from inkubeSpike import (
    receive_process, 
    update_MAD, 
    c_spike_poll_process, 
    c_map_spikes_to_matrix_tuple)

from Client_config import (
    FS, 
    CONTROL_NETWORKS,
    DO_PLOT,
    DO_STIMULATE,
    PLOT_BUF_LEN,
    DO_PLOT_RAW,
    CHANNELS,
    STATUS_LEN,
    TEMP_BUF_LEN,
    CLIENT_RECV_PORT,
    LINUX,
    TEMP_STREAM_SIZE, 
    CONTROL_CLIENT_IP, 
    CONTROL_CLIENT_PORT, 
    INIT_MODE, 
    ELECTRODE_MAPPING, 
    NETWORK_NUM,
    ELECTRODES,
    MEA_NUM, 
    SPIKE_WAVELET_SHAPE, 
    TRANSMIT_SPONT_SPIKES, 
    ENV_CONTROL_PORT, 
    DO_STORE_SPIKE_SHAPES,
    SHARED_NOISE_BINS, 
    SHARED_NOISE_MAX, 
    PC_IP, 
    TEST_SERVER, 
    NETWORK_SAVE_SPIKES, 
)

from Plot_stream import (
    plot_process, 
    save_shapes_process)
from onsite_Stimulation_processor import (
    control_connection_process, 
    stim_segmentation, 
    blind_send)
from Send_commands import (
    prepare_commands_process,
    send_write_to_register, 
    set_amplitude, 
    set_digaux, 
)

from USB_communication import (
    USB_com, 
    send_commands_process_USB, 
    relay_fpga_commands_process, 
)

if not LINUX:
    from asyncio.windows_utils import BUFSIZE
else:
    import fcntl

def clear_spikes(pipe_a, sleep_duration=0.01):
    """
    Continuously clears spikes from the spike pipes.
    Args:
        pipe_a: The spike pipe.
        sleep_duration: The duration to sleep between checks for spikes.
    """
    while True:
        while pipe_a.poll():
            _ = np.frombuffer(pipe_a.recv_bytes(4), dtype=np.uint8)
        time.sleep(sleep_duration)

def transmit_spontaneous(
        pipe_in, 
        spont_spike_q, 
        transmit, 
        spont_event, 
        started_pkg, 
        process_id = 0,
    ):
    """
    Transmits spontaneous spikes to the spike queue and/or raster plot.
    Args:
        pipe_in: The input spike pipe.
        spont_spike_q: The queue for transmitting spontaneous spikes.
        transmit: Flag indicating whether to transmit spikes.
        spont_event: The event for controlling transmission of spontaneous spikes.
        started_pkg: The timestamp of the started package.
        process_id: The ID of the process.
    """
    spike_mat = []
    networks_spike_mat = np.empty((NETWORK_NUM, ELECTRODES), dtype=object)
    for i in range(NETWORK_NUM):
        for j in range(ELECTRODES):
            networks_spike_mat[i,j] = tuple()
    response = {
        'spontaneous': True, 
        'stim_recv': False, 
        'spontaneous_spikes': spike_mat, 
        'timestamp': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3], 
        'pkg_id': started_pkg, 
        'process_id': process_id, 
    }
    print(f'Start transmitting with shift of {started_pkg}')
    while True:
        while spont_event.is_set():
            while pipe_in.poll():
                spike_mat=pipe_in.recv()
                num_elements = len(spike_mat[0])
                print(f"Read spontaneous chunks of size {num_elements}")

                if (transmit) and spike_mat[0].shape:
                    c_map_spikes_to_matrix_tuple(
                        spike_mat[0], 
                        spike_mat[1], 
                        0, 
                        networks_spike_mat, 
                        ELECTRODE_MAPPING.mapping_recv2network, 
                        num_elements, 
                    )
                    
                    if transmit:
                        if not spont_spike_q.full():
                            response['timestamp'] = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
                            response['spontaneous_spikes'] = np.copy(networks_spike_mat)
                            spont_spike_q.put(response)

                    for i in range(NETWORK_NUM):
                        for j in range(ELECTRODES):
                            networks_spike_mat[i,j] = tuple()
        spont_event.wait()


if __name__ == "__main__":
    """
    The main function that starts all the processes and threads.
    """
    print(f'PID:{os.getpid()} - This is the main process.')

    spike_pipe_a_r, spike_pipe_a_w = mp.Pipe(duplex=False)

    # make sure the buffer for the pipe for spikes is large enough
    if not LINUX:
        con.BUFSIZE = 2**18
    else:
        fcntl.F_SETPIPE_SZ = 16*4194304 # check max under cat /proc/sys/fs/pipe-max-size and if required set with sudo sysctl fs.pipe-max-size=4194304
    # initialise pipes to exchange data between processes
    command_pipe_recv, command_pipe_send = mp.Pipe(duplex=False)
    send_pipe_recv, send_pipe_send = mp.Pipe(duplex=False)
    raster_plot_pipe_recv, raster_plot_pipe_send = mp.Pipe(duplex=False)
    detected_spike_share_recv, detected_spike_share_send = mp.Pipe(duplex=False)

    # shared variables, streams for plot data
    plot_channels = mp.Value("i", 0)
    plot_voltage_bool = mp.Value("i", True)
    update_thresh_bool = mp.Value("i", True)
    plot_shared = mp_shared.synchronized(mp_shared.RawArray(c_float, PLOT_BUF_LEN * CHANNELS))
    plot_sig = mp_shared.synchronized(mp_shared.RawArray(c_float, PLOT_BUF_LEN * CHANNELS))

    # shared variables for UDP communication
    UDP_rcv_port = mp_shared.Value(c_uint16, 0)
    newest_recv_pkg = mp_shared.synchronized(mp_shared.RawArray(c_uint32, 4,))
    # pos 0: current receive package, pos 1: artefact onset, pos 2: stim on
    newest_recv_pkg[0] = 2**22
    newest_recv_pkg[1] = 2**22
    newest_recv_pkg[2] = 2**22
    newest_recv_pkg[3] = 0
    
    plot_spike_wavelet = mp_shared.synchronized(mp_shared.RawArray(c_float, SPIKE_WAVELET_SHAPE[0]*SPIKE_WAVELET_SHAPE[1]*SPIKE_WAVELET_SHAPE[2]))
    plot_spike_wavelet_id = mp_shared.synchronized(mp_shared.RawArray(c_uint32, SPIKE_WAVELET_SHAPE[0]*SPIKE_WAVELET_SHAPE[1]))

    for i in range(SPIKE_WAVELET_SHAPE[0]*SPIKE_WAVELET_SHAPE[1]*SPIKE_WAVELET_SHAPE[2]):
        plot_spike_wavelet[i] = 0

    for i in range(SPIKE_WAVELET_SHAPE[0]*SPIKE_WAVELET_SHAPE[1]):
        plot_spike_wavelet_id[i] = 2**22
        

    spike_thresh_array = mp_shared.synchronized(mp_shared.RawArray(c_float, CHANNELS))
    shared_noise_array = mp_shared.synchronized(mp_shared.RawArray(c_float, MEA_NUM*SHARED_NOISE_BINS))

    plot_spikes = mp_shared.synchronized(mp_shared.RawArray(c_uint8, PLOT_BUF_LEN * CHANNELS))
    plot_status = mp_shared.synchronized(mp_shared.RawArray(c_uint32, PLOT_BUF_LEN * STATUS_LEN))
    plot_temp = mp_shared.synchronized(mp_shared.RawArray(c_uint32, TEMP_STREAM_SIZE * TEMP_BUF_LEN))

    plot_loc = mp_shared.synchronized(mp_shared.RawArray(c_uint16, 1))
    # recv_pkg_id = mp_shared.synchronized(mp_shared.RawArray(c_uint8, 1))  # This variable is set by the readers and contains the current most recent pacakge id that the FPGA received (0-255)
    recv_pkg_recv, recv_pkg_send = mp.Pipe(duplex=False)

    store_mode = np.array([INIT_MODE])
    # detected_spike_array_share = mp_shared.RawArray(c_uint8, 1000000)
    segment_ids = mp_shared.synchronized(mp_shared.RawArray(c_uint32, 6)) # start, end, finished period, 
    segment_ids[0] = 0 # lower pkg border for storing
    segment_ids[1] = 0 # upper pkg border for storing
    segment_ids[2] = 1 # is discard spike, 0 is store

    store_event = mp.Event()
    period_over_event = mp.Event()
    stim_event = mp.Event()
    blind_send_event = mp.Event()
    spont_event = mp.Event()
    if not TEST_SERVER:
        com = USB_com()
    else:
        com = None
        
    stim_pipe_server, control_recv, level_q, env_q, spont_spike_q, env_reg_write_recv = control_connection_process(
        ip=CONTROL_CLIENT_IP, 
        port=CONTROL_CLIENT_PORT, 
        medium_port=ENV_CONTROL_PORT)
      
    time.sleep(0.1)

    if DO_PLOT:
        p_plot = mp.Process(
            target=plot_process,
            name='plot_process',
            args=(
                plot_loc,
                plot_shared,
                plot_sig, 
                plot_spike_wavelet, 
                plot_status, 
                plot_temp,
                plot_spikes,
                spike_thresh_array,
                plot_voltage_bool,
                update_thresh_bool, 
                plot_channels,
                raster_plot_pipe_recv,
                level_q, 
                env_q, 
                shared_noise_array, 
            ),
        )

    p_spikes = mp.Process(
        target=receive_process,
        name='continuous_FPGA_data_readout', 
        args=(
            UDP_rcv_port,
            PC_IP, 
            CLIENT_RECV_PORT, 
            spike_pipe_a_w,
            plot_shared,
            plot_sig,
            plot_spike_wavelet, 
            plot_spike_wavelet_id, 
            plot_spikes,
            plot_loc,
            recv_pkg_send,
            spike_thresh_array,
            plot_status,
            plot_temp,
            newest_recv_pkg,
            int(DO_PLOT_RAW),
        ),
    )

    mea_mapping = np.array([ELECTRODE_MAPPING.mea2recv(range(i*60, (i+1)*60)) for i in range(MEA_NUM)])
    t_update = threading.Thread(
        target=update_MAD, 
        args=(
            plot_sig, 
            plot_shared, 
            2.1, 
            spike_thresh_array, 
            update_thresh_bool, 
            shared_noise_array, 
            mea_mapping, 
            SHARED_NOISE_BINS, 
            SHARED_NOISE_MAX, 
        )
    )

    if DO_STORE_SPIKE_SHAPES:
        network_to_plot = NETWORK_SAVE_SPIKES
        save_network_spike_shapes = []
        for nw in network_to_plot:
            for el in range(4):
                save_network_spike_shapes.append(ELECTRODE_MAPPING.network2mea(np.array([[nw, el]])))
        save_network_spike_shapes = np.array(save_network_spike_shapes).flatten()
        print(f'Saving shapes of electrodes: {save_network_spike_shapes}')
        p_spike_shapes = mp.Process(
            target=save_shapes_process,
            name="spike_shapes",
            args=(
                plot_spike_wavelet, 
                plot_spike_wavelet_id, 
                save_network_spike_shapes, 
                1.8, 
                spont_event, # only save during spontaneous 
            )
        )

    # process for retrieving spikes from the spike detection process
    p_spike_readout_a = mp.Process(
        target=c_spike_poll_process,
        name="spike_processor",
        args=(
            spike_pipe_a_r, 
            segment_ids, 
            detected_spike_share_send, 
            ELECTRODE_MAPPING.mapping_recv2network, 
            NETWORK_NUM,
            ELECTRODES,
            store_event, 
            period_over_event, 
            spont_event, 
        )
    )

    # process for segmenting into time periods and stimulating, closed loop stimulation
    p_segment_stimulation = mp.Process(
        target=stim_segmentation,
        name="stim_segmentation",
        args=(
            command_pipe_send,
            newest_recv_pkg,
            plot_channels,
            raster_plot_pipe_send,
            segment_ids, 
            stim_pipe_server, 
            detected_spike_share_recv,
            period_over_event, 
            stim_event, 
        ),
    )

    # process for blind stimulation, open loop stimulation
    p_blind_send = mp.Process(
        target=blind_send,
        name="blind send",
        args=(
            command_pipe_send,
            newest_recv_pkg,            
            stim_pipe_server,                       
            blind_send_event, 
        ),
    )

    # process for stimulation command preparation
    if DO_STIMULATE:
        p_stimulator = mp.Process(
            target=prepare_commands_process,
            name="prepare_stimulation_commands",
            args=(
                command_pipe_recv, 
                send_pipe_send, 
                newest_recv_pkg, 
            ),
        )

    # process for receiving environmental commands
    t_env_commands = threading.Thread(
        target=relay_fpga_commands_process, 
        name='receive_and_forward_fpga_commands', 
        args=(
            env_reg_write_recv, 
            send_pipe_send, 
        ),
    )            
    
    # process for sending commands to the SoC via USB
    p_command_transmit = mp.Process(
        target=send_commands_process_USB,
        name="send_via_USB",
        args=(com, send_pipe_recv, recv_pkg_recv, 100e-3),
    )

    # start processess ------------------------------------------------------------------------
    p_spikes.start()
    p_command_transmit.start()

    # wait for the UDP port to be set, port to establish uplink communication is sent through USB with downlink
    if not TEST_SERVER:
        while(UDP_rcv_port.value == 0):
            time.sleep(.05)
            # print(f'Still waiting because port is {UDP_rcv_port.value}')
        while(UDP_rcv_port.value == 65535):
            pass            
        send_pipe_send.send((1, UDP_rcv_port.value)) # put port command on pipe
            
    if CONTROL_NETWORKS:
        p_spike_readout_a.start()
    else:
        p_recv = mp.Process(
            target=clear_spikes, args=(spike_pipe_a_r, 0.001))
        p_recv.start()  # no clearing when processing of spikes

    time.sleep(.5)
    t_update.start()

    if DO_PLOT:
        p_plot.start()

    if DO_STIMULATE:
        send_write_to_register(send_pipe_send)
        # make sure init commands arrive first        
        print("Start sending")
        p_stimulator.start()
        time.sleep(3)
        
    t_env_commands.start()

    if DO_STORE_SPIKE_SHAPES:
        p_spike_shapes.start()

    started_pkg = (
        datetime.datetime.now() 
        - datetime.timedelta(seconds=newest_recv_pkg[0]/FS)
    ).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]

    t_transmit_spikes_a = threading.Thread(
        target=transmit_spontaneous, 
        args=(
            detected_spike_share_recv,
            spont_spike_q, 
            TRANSMIT_SPONT_SPIKES, 
            spont_event, 
            started_pkg, 
        )
    )
    store_event.clear()
    stim_event.clear()
    spont_event.clear()
    blind_send_event.clear()

    # while loop with keyboard interrupt, readout command queue and set mode
    try:
        while True:
            time.sleep(.2)        
            # readout command queue

            while control_recv.poll():
                command_dict = control_recv.recv()
                print(f"Just received {command_dict}")
                for command_key in command_dict.keys():
                    new_value = command_dict[command_key]
                    
                    if command_key == 'mode':
                        ''' 
                        mode selection 0: discard, 
                        1: spontaneous recording, 
                        2: segment and stimulate (closed loop), 
                        3: open loop stimulation 
                        4: clear pipes and restart stimulation
                        '''
                        print(f"Changing mode from {store_mode[0]} to {new_value}")
                        store_mode[0] = new_value

                        if new_value == 0:                            
                            store_event.clear()
                            stim_event.clear()
                            spont_event.clear()
                            blind_send_event.clear()
                            segment_ids[0] = 2**22  
                            segment_ids[1] = 2**22
                            while detected_spike_share_recv.poll():
                                detected_spike_share_recv.recv()
                            while not spont_spike_q.empty():
                                spont_spike_q.get_nowait()
                            print("Emptied queues")
 
                        if new_value == 2:
                            print(f"Segment stimulation state {p_segment_stimulation.is_alive()}")                        
                            segment_ids[0] = 2**22  
                            segment_ids[1] = 0
                            time.sleep(1)
                            period_over_event.set()
                            store_event.set()
                            time.sleep(.5)
                            
                            stim_event.set()
                            if not p_segment_stimulation.is_alive():    
                                p_segment_stimulation.start()   
                        else:
                            if p_segment_stimulation.is_alive():
                                stim_event.clear()
                                print("Killed segment stimulation")

                        if new_value == 4:
                            p_segment_stimulation.terminate()
                            time.sleep(5)
                            p_segment_stimulation = mp.Process(
                                target=stim_segmentation,
                                name="stim_segment",
                                args=(
                                    command_pipe_send,
                                    newest_recv_pkg,
                                    plot_channels,
                                    raster_plot_pipe_send,
                                    segment_ids, 
                                    stim_pipe_server, 
                                    detected_spike_share_recv,
                                    period_over_event, 
                                    stim_event, 
                                ),
                            )

                        if new_value == 1:
                            segment_ids[1] = 2**22                                                           
                            segment_ids[0] = 0   
                            spont_event.set()
                            if not t_transmit_spikes_a.is_alive():                                
                                t_transmit_spikes_a.start()
                            
                            time.sleep(2)
                                                                    
                            store_event.set()     
                        else:
                            if t_transmit_spikes_a.is_alive():
                                spont_event.clear()
                                print("Killed spontaneous transmit")        

                        if new_value == 3:                            
                            blind_send_event.set()
                            print("Emptied queues")     
                            if not p_blind_send.is_alive():    
                                p_blind_send.start()   
                        else:
                            if p_blind_send.is_alive():
                                blind_send_event.clear()
                                print("Killed blind send stimulation")                                                                                  

                    elif 'stim' in command_key:
                        ''' Set stimulation parameters, stimulation must be paused'''               
                        # if store_mode[0] == 2:
                        #     print("Warning: Stimulation running, please stop first")

                        if command_key == 'stim_amp':                                 
                            if new_value > 255:
                                new_value = 255
                                print("Warning: high amplitude set, clipping to 10uA")
                            if new_value <= 0:
                                new_value = 1
                                print("Warning: low amplitude set, setting to 1uA")
                            send_write_to_register(send_pipe_send, set_amplitude(new_value))                            

                    elif 'digaux' in command_key:
                        ''' Set digital auxilary outputs '''
                        if command_key == 'digaux_off':
                            digaux_val = 0
                        elif command_key == 'digaux_on':
                            digaux_val = 1
                        else: 
                            print("Warning: Invalid digaux key")
                        set_digaux(send_pipe_send, value=digaux_val, pkg_id=new_value)

                    else:
                        print("Warning: Invalid command key")
    except KeyboardInterrupt:
        print("interrupted!")
    p_spikes.terminate()
    
    if DO_STIMULATE:
        p_stimulator.terminate()
        p_command_transmit.terminate()
    if CONTROL_NETWORKS:
        p_spike_readout_a.terminate()
    if DO_PLOT:
        p_plot.terminate()
    if DO_STORE_SPIKE_SHAPES:
        p_spike_shapes.terminate()
    t_update.terminate()
    com.close()
    print("All processes terminated")