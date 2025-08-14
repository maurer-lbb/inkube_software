"""
This script is the main entry point for the Readout_python application. It sets up various processes and threads for data readout, spike processing, stimulation, and plotting.
Functions:
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
import multiprocessing.connection as con
import datetime
import zmq
import struct

from Client_config import (
    FS, 
    DO_PLOT,
    CHANNELS,
    LINUX,
    CONTROL_CLIENT_IP, 
    CONTROL_CLIENT_PORT, 
    ELECTRODE_MAPPING, 
    MEA_NUM,  
    ENV_CONTROL_PORT, 
    TEST_SERVER, 
    ZMQ_STIMDATA_SOCKET, 
    ZMQ_PKG_SOCKET,
    THRESH_SOCKET_PATH,
    connect_to_zmq,
    INIT_THRESH_FACTOR,
    STIMULUS_CYCLE, 
    MIN_PKG_DELAY, 
    RESPONSE_IMPORTANT_PERIOD,
)

from Plot_stream import (
    plot_process,)
from onsite_Stimulation_processor import (
    closed_loop_stim,
    control_connection_process, 
    spike_triggered_stim, 
)

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

from h5_saver import saver_process

if __name__ == "__main__":
    """
    The main function that starts all the processes and threads.
    """
    print(f'PID:{os.getpid()} - This is the main process.')

    # initialise pipes to exchange data between processes
    command_pipe_recv, command_pipe_send = mp.Pipe(duplex=False)
    send_pipe_recv, send_pipe_send = mp.Pipe(duplex=False)
    raster_plot_pipe_recv, raster_plot_pipe_send = mp.Pipe(duplex=False)
    detected_spike_share_recv, detected_spike_share_send = mp.Pipe(duplex=False)

    # shared variables, streams for plot data
    plot_channels = mp.Value("i", 0)
    plot_voltage_bool = mp.Value("i", True)
    update_thresh_bool = mp.Value("B", 1)
    stim_cycle = mp.Value("i", STIMULUS_CYCLE)

    plot_shared = mp_shared.synchronized(mp_shared.RawArray(c_float, 4096 * CHANNELS))
    plot_sig = mp_shared.synchronized(mp_shared.RawArray(c_float, 4096 * CHANNELS))

    # shared variables for UDP communication
    UDP_rcv_port = mp_shared.Value(c_uint16, 0)

    # Initialize ZMQ context
    context = zmq.Context()
    
    # Publisher socket for stimulation data
    stimdata_pub_socket = context.socket(zmq.PUB)
    stimdata_pub_socket.bind(ZMQ_STIMDATA_SOCKET)

    thresh_factor = mp.Value("f", INIT_THRESH_FACTOR)
        
    period_over_event = mp.Event()
    stim_event = mp.Event()
    triggered_stim_event = mp.Event()

    spont_event = mp.Event()
    save_event = mp.Event()

    if not TEST_SERVER:
        com = USB_com()
    else:
        com = None
        
    # control_connection_process call
    control_recv, level_q, env_q, spont_spike_q, env_reg_write_recv = control_connection_process(
        ip=CONTROL_CLIENT_IP, 
        port=CONTROL_CLIENT_PORT, 
        medium_port=ENV_CONTROL_PORT
    )
      
    time.sleep(0.1)

    if DO_PLOT:
        p_plot = mp.Process(
            target=plot_process,
            name='plot_process',
            args=(
                plot_voltage_bool,
                plot_channels,
            ),
        )
    mea_mapping = np.array([ELECTRODE_MAPPING.mea2recv(range(i*60, (i+1)*60)) for i in range(MEA_NUM)])
          
    # process for stimulation command preparation

    p_stimulator = mp.Process(
        target=prepare_commands_process,
        name="prepare_stimulation_commands",
        args=(
            command_pipe_recv, 
            send_pipe_send, 
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
        args=(com, send_pipe_recv, 2e-3),
    )

    # start processess ------------------------------------------------------------------------

    # Define the path to the Unix domain socket
    udp_socket_path = "/tmp/udp_port_for_fpga"

    # Create a Unix domain socket
    client_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)

    # Connect to the socket
    client_socket.connect(udp_socket_path)

    data = client_socket.recv(4)
    port_for_fpga = int.from_bytes(data, byteorder='little', signed=False)
    print(f'Sending out port {int(port_for_fpga)}')
    # send_pipe_send.send((1, port_for_fpga))
    if not TEST_SERVER:
        com.send_recv_port_single(port_for_fpga)


    # port is set, start readout now -----------------------------------------------------------

    # In your main() function, before starting threads
    # Set up Unix socket for threshold control
    if os.path.exists(THRESH_SOCKET_PATH):
        os.unlink(THRESH_SOCKET_PATH)  # Remove existing socket file

    thresh_socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    thresh_socket.bind(THRESH_SOCKET_PATH)
    thresh_socket.listen(5)
    print(f"Listening for threshold connections on {THRESH_SOCKET_PATH}")

    # Accept connections in a separate thread
    thresh_client_connections = []
    def accept_thresh_connections():
        while True:
            client, _ = thresh_socket.accept()
            thresh_client_connections.append(client)
            print(f"New threshold control connection accepted, total: {len(thresh_client_connections)}")

    thresh_accept_thread = threading.Thread(target=accept_thresh_connections, daemon=True)
    thresh_accept_thread.start()


    # When threshold is updated, send to all clients
    def send_thresh_update(thresh_factor, update_enabled):
        print(f"Sending threshold update: {thresh_factor}, update_enabled: {update_enabled}")
        data = struct.pack("fB", thresh_factor, 1 if update_enabled else 0)
        disconnected = []
        
        for i, client in enumerate(thresh_client_connections):
            try:
                client.sendall(data)
            except Exception as e:
                print(f"Failed to send to threshold client {i}: {e}")
                disconnected.append(i)
        
        # Remove disconnected clients
        for i in sorted(disconnected, reverse=True):
            thresh_client_connections.pop(i)


    time.sleep(.05)
    p_command_transmit.start()

    send_thresh_update(INIT_THRESH_FACTOR, update_thresh_bool.value)

    package_socket = connect_to_zmq(ZMQ_PKG_SOCKET)
    current_pkg_id = int.from_bytes(package_socket.recv(), 'little')
    package_socket.close()
    started_pkg = (
        datetime.datetime.now() 
        - datetime.timedelta(seconds=current_pkg_id/FS)
    ).strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]

    # process for segmenting into time periods and stimulating, closed loop stimulation
    p_segment_stimulation = mp.Process(
        target=closed_loop_stim,
        name="stim_segmentation",
        args=(
            command_pipe_send,
            stim_event, 
            started_pkg, 
            stim_cycle, 
        ),
    )

    # process for triggered stimulation
    p_triggered_stimulation = mp.Process(
        target=spike_triggered_stim,
        name="triggered send",
        args=(
            command_pipe_send,         
            triggered_stim_event,
        ),
    )


    # process for saving data
    p_save_data = mp.Process(
        target=saver_process,
        name="data_saver",
        args=(save_event, started_pkg), 
    )

    if DO_PLOT:
        p_plot.start()

    send_write_to_register(send_pipe_send)
    # make sure init commands arrive first        
    print("Start sending")
    p_stimulator.start()
        
    t_env_commands.start()

    stim_event.clear()
    triggered_stim_event.clear()
    spont_event.clear()
    save_event.clear()

    p_save_data.start()

    time.sleep(2)
    
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


                        if new_value == 0:                            
                            stim_event.clear()
                            triggered_stim_event.clear()
                            spont_event.clear()

                            while detected_spike_share_recv.poll():
                                detected_spike_share_recv.recv()
                            while not spont_spike_q.empty():
                                spont_spike_q.get_nowait()
                            print("Emptied queues")
 
                        if new_value == 2:
                            print(f"Segment stimulation state {p_segment_stimulation.is_alive()}")                        

                            time.sleep(1)
                            period_over_event.set()
                            time.sleep(.5)
                            
                            stim_event.set()
                            if not p_segment_stimulation.is_alive():    
                                p_segment_stimulation.start()   
                        else:
                            if p_segment_stimulation.is_alive():
                                stim_event.clear()
                                print("Killed segment stimulation")

                        if new_value == 3:
                            print(f"Triggered stimulation state {p_triggered_stimulation.is_alive()}")                        
                            
                            triggered_stim_event.set()
                            if not p_triggered_stimulation.is_alive():    
                                p_triggered_stimulation.start()   
                        else:
                            if p_triggered_stimulation.is_alive():
                                triggered_stim_event.clear()
                                print("Killed segment stimulation")

                        if new_value == 1:
                            pass
                                                                             

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
                            print(f'Setting amplitude to {new_value}')
                            send_write_to_register(send_pipe_send, set_amplitude(new_value))      
                            # **Publish the stimulation data**
                            stimdata_pub_socket.send(new_value.to_bytes(1, byteorder='little', signed=False))  

                        elif command_key == 'stim_freq':
                            if new_value < 1./90:
                                new_value = 1./90
                                print("Warning: low frequency set, setting to every 90s because of package ID")
                            if new_value > (FS/(MIN_PKG_DELAY+RESPONSE_IMPORTANT_PERIOD)):
                                new_value = (FS/(MIN_PKG_DELAY+RESPONSE_IMPORTANT_PERIOD))//1
                                print("Warning: high frequency set, clipping to maximum frequency")
                            print(f'Setting frequency to {new_value}')
                            stim_cycle.value = int(FS/new_value+.5)

                    elif 'digaux' in command_key:
                        ''' Set digital auxilary outputs '''
                        if command_key == 'digaux_off':
                            digaux_val = 0
                        elif command_key == 'digaux_on':
                            digaux_val = 1
                        else: 
                            print("Warning: Invalid digaux key")
                        set_digaux(send_pipe_send, value=digaux_val, pkg_id=new_value)

                    elif 'saving' in command_key:
                        if new_value == 1:
                            # only restart if not already running
                            if not save_event.is_set():
                                save_event.set()
                            print("Saving started")
                        if new_value == 2:
                            # always restart
                            save_event.clear()
                            time.sleep(1)
                            save_event.set()
                            print("Saving restarted")
                        if new_value == 0:
                            # stop saving
                            save_event.clear()
                            print("Saving stopped")

                    # In your command handling section
                    elif command_key == 'thresh_factor':
                        thresh_factor.value = new_value
                        # Update threshold factor
                        send_thresh_update(thresh_factor.value, update_thresh_bool.value)
                    elif command_key == 'thresh_update':
                        update_thresh_bool.value = new_value
                        # Update threshold enabled flag
                        send_thresh_update(thresh_factor.value, update_thresh_bool.value)


                    else:
                        print("Warning: Invalid command key")
    except KeyboardInterrupt:
        print("interrupted!")
        save_event.clear()
    
    p_stimulator.terminate()
    p_command_transmit.terminate()

    if DO_PLOT:
        p_plot.terminate()

    p_save_data.join()

    try:
        com.close()
    except:
        pass
    print("All processes terminated")