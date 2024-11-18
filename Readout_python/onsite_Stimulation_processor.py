import numpy as np
import multiprocessing as mp
import os
import time
import threading
from datetime import date
from datetime import datetime
from multiprocessing.managers import BaseManager
import multiprocessing.connection as con
import socket

# Get current date
today = date.today()
d1 = today.strftime("%Y_%m_%d")

from Client_config import (
    FS,
    MIN_PKG_DELAY,
    MIN_STIM_COMMAND_DELAY, 
    STIMULUS_CYCLE,
    START_ID_INIT,
    RESPONSE_IMPORTANT_PERIOD,
    MAX_PKG_ID,
    ELECTRODE_MAPPING,
    NETWORK_NUM,
    ELECTRODES,
    MAX_SPIKE_DETECT_DELAY, 
    MAX_LEN_ENV_Q, 
    MAX_LEN_SPONT_Q, 
    MAX_LEN_LVL_Q, 
    ARTEFACT_CANCELLATION, 
)

from Send_commands import write_to_register

def blind_send(
    command_pipe: con.Connection,
    newest_receive_pkg_id,          
    stim_pipe_server,                         
    blind_send_event, 
):
    print(f'PID:{os.getpid()} - Started blind stim process.')
    stim_id = 0
    index = 0
    recv_flag = False
    last_index_rec = 0
    stim_matrix = np.array([])

    response = {
        'spikes': None, 
        'index': index, 
        'stim': stim_matrix, 
        'stim_recv': recv_flag,
        'spontaneous': False, 
    }

    PRINT_STEP = 1    

    
    while True:
        start_id = ((newest_receive_pkg_id[0]//STIMULUS_CYCLE)*STIMULUS_CYCLE + START_ID_INIT) % MAX_PKG_ID

        while blind_send_event.is_set():         
            current_receive_id = newest_receive_pkg_id[0]
            while (
                    MAX_PKG_ID//2 < ((
                        start_id - current_receive_id # When this term is negative break
                        + ((3*MAX_PKG_ID)//2)) % MAX_PKG_ID)):
                time.sleep(1e-3)
                # print("Waiting for end of segment")
                current_receive_id = newest_receive_pkg_id[0]        

            # index is the number of period
            index = start_id // STIMULUS_CYCLE

            # send out data and index
            response['index'] = index
            response['stim_recv'] = recv_flag

            stim_pipe_server.send(response)

            recv_flag = False
            
            # move to next period ---------------------------------------------------------------------------------------------
            start_id = (start_id + STIMULUS_CYCLE) % MAX_PKG_ID

            # check whether send out point can be reached or delay of processing is too big ?, otherwise skipo period
            current_receive_id = newest_receive_pkg_id[0]
            while (
                    MAX_PKG_ID//2 > ((
                        start_id-MIN_PKG_DELAY - current_receive_id # When this term is positive break
                        + ((3*MAX_PKG_ID)//2)) % MAX_PKG_ID)):
                start_id = (start_id + STIMULUS_CYCLE) % MAX_PKG_ID
                current_receive_id = newest_receive_pkg_id[0]
                print(
                    f"Missed period {index}, increased to start_id {start_id} with overhead {(start_id-newest_receive_pkg_id[0])/FS*1000 :.3f}"
                )     

            # Here the wait period ends ----------------------------------------------
            current_receive_id = newest_receive_pkg_id[0]
            while ((
                        MAX_PKG_ID//2 < ((
                            start_id-MIN_PKG_DELAY - current_receive_id # When this term is negative break
                            + ((3*MAX_PKG_ID)//2)) % MAX_PKG_ID))):
                time.sleep(1e-3)
                current_receive_id = newest_receive_pkg_id[0]
                # print(f"Waiting for commands at {start_id} at current receive {current_receive_id}")
                if stim_pipe_server.poll():
                    # set amplitude or delays here
                    stimulus = stim_pipe_server.recv()
                    stim_id, stim_matrix = stimulus
                    if stim_id != index + 1:
                        stim_matrix = np.array([])
                        print(f"Mismatch received {stim_id} for period {index+1}")                    
                    else:
                        recv_flag = True
                        break

            if stim_matrix.shape[0]:
                
                # print(f"Min Distance for stim: {stimulus_timing_min_dist}")
                stim_delays = -np.unique(-stim_matrix[:, 0])
                stim_matrix = stim_matrix[np.argsort(-stim_matrix[:, 0]),:]

                # flag is 0, no onset or offset command, just pulses
                all_flags = np.zeros(stim_delays.shape[0], dtype=int)              

                if stim_delays.shape[0] > 7: # as the fifo is too small send the packages delayed
                    stim_pkgs = (start_id-stim_delays)%MAX_PKG_ID
                    for delay_num, stim_pkg in enumerate(stim_pkgs):
                        # block until just before stim command
                        current_receive_id = newest_receive_pkg_id[0]
                        while ((
                                MAX_PKG_ID//2 < ((
                                    stim_pkg-MIN_STIM_COMMAND_DELAY - current_receive_id # When this term is negative break
                                    + ((3*MAX_PKG_ID)//2)) % MAX_PKG_ID))):
                            time.sleep(1e-3)
                            current_receive_id = newest_receive_pkg_id[0]

                        command_pipe.send(
                            (
                                stim_pkg, 
                                ELECTRODE_MAPPING.network2mea(stim_matrix[np.equal(stim_matrix[:, 0], stim_delays[delay_num]),1:]), 
                                all_flags[delay_num]
                            )
                        )
                    if not index % PRINT_STEP:
                        print(
                            f"stimulate commands sent out stepwise: {(start_id-newest_receive_pkg_id[0])/FS*1000 :.3f} ms before stim with points {stim_pkgs} - {start_id}"
                        )
                elif stim_delays.shape[0]: # this is the standard case where all commands are sent at once ahead of time
                    for delay_num, stim_delay in enumerate(stim_delays):
                        if stim_delay >= 0:
                            stim_pkg = (start_id-stim_delay)%MAX_PKG_ID
                        else:
                            stim_pkg = 0x80000000 - stim_delay # for negative rerlative delay in samples
                        command_pipe.send(
                            (
                                stim_pkg, 
                                ELECTRODE_MAPPING.network2mea(stim_matrix[np.equal(stim_matrix[:, 0], stim_delay),1:]), 
                                all_flags[delay_num]
                            )
                        )  
                    if not index % PRINT_STEP:
                        print(
                            f"stimulate commands sent out: {(start_id-newest_receive_pkg_id[0])/FS*1000 :.3f} ms before stim with points {stim_delays} - {start_id}"
                        )

                response['stim'] = stim_matrix
                
                stim_matrix = np.array([])
        blind_send_event.wait()

def stim_segmentation(
    command_pipe: con.Connection,
    newest_receive_pkg_id,
    plot_channels,
    raster_plot_pipe,
    segment_ids,
    stim_pipe_server,
    detected_spike_share_recv,  
    period_over_event, 
    stim_event, 
):
    """readout recorded spikes and send out stimulation"""

    print(f'PID:{os.getpid()} - Started stim segmentation process.')
    # print("Emptying pipes")
    # while stim_pipe_server.poll():
    #     print("Somehow stim detected")
    #     stim_pipe_server.recv()
    # if detected_spike_share_recv.poll():
    #     print("Somehow spikes detected")
    #     # detected_spike_share_recv.recv()

    stim_id = 0
    # STIMULUS_CYCLE roughly 250 ms
    # RESPONSE_IMPORTANT_PERIOD roughly  20 ms

    networks_spike_mat = np.empty((NETWORK_NUM, ELECTRODES), dtype=object)
    for j in np.ndindex(networks_spike_mat.shape):
        networks_spike_mat[j] = tuple()

    empty_spike_mat = np.copy(networks_spike_mat)

    index = 0
    recv_flag = False
    last_index_rec = 0
    stim_matrix = np.array([])

    response = {
        'spikes': networks_spike_mat, 
        'index': index, 
        'stim': stim_matrix, 
        'stim_recv': recv_flag,
        'spontaneous': False, 
    }

    PRINT_STEP = 10

    # block until readout processing begins
    while newest_receive_pkg_id[0] == 2**22:
        time.sleep(1e-3)

    print(f"Start Spike Processor")
    
    while True:
        start_id = ((newest_receive_pkg_id[0]//STIMULUS_CYCLE)*STIMULUS_CYCLE + START_ID_INIT) % MAX_PKG_ID
        # with segment_ids:
        segment_ids[0] = start_id
        if ((start_id+RESPONSE_IMPORTANT_PERIOD) % MAX_PKG_ID) < segment_ids[0]:
            segment_ids[1] = MAX_PKG_ID-1
        else:
            segment_ids[1] = (start_id+RESPONSE_IMPORTANT_PERIOD) % MAX_PKG_ID
        period_over_event.clear()

        print(f"Starting segmentation with {segment_ids[0]} to {segment_ids[1]} at {newest_receive_pkg_id[0]}")
        while stim_event.is_set():
            # Wait here depending on index
            with segment_ids:
                upper_wait_limit = (segment_ids[1]+MAX_SPIKE_DETECT_DELAY) % MAX_PKG_ID
            current_receive_id = newest_receive_pkg_id[0]
            while (not period_over_event.is_set() and (
                    MAX_PKG_ID//2 < ((
                        upper_wait_limit - current_receive_id # When this term is negative break
                        + ((3*MAX_PKG_ID)//2)) % MAX_PKG_ID))):
                time.sleep(1e-3)
                # print("Waiting for end of segment")
                current_receive_id = newest_receive_pkg_id[0]

            if period_over_event.is_set(): 
                while detected_spike_share_recv.poll():
                    networks_spike_mat = detected_spike_share_recv.recv()
            else:
                while detected_spike_share_recv.poll():
                    detected_spike_share_recv.recv()
                period_over_event.set()
                networks_spike_mat = np.copy(empty_spike_mat)           

            # index is the number of period
            last_index_rec = index
            index = start_id // STIMULUS_CYCLE

            # send out data and index
            response['spikes'] = networks_spike_mat

            response['index'] = index
            response['stim_recv'] = recv_flag

            stim_pipe_server.send(response)


            if not index % PRINT_STEP:
                print(
                    f"{(current_receive_id-start_id)/FS*1000 :.3f} ms:: Finished for period {index}"
                )
            recv_flag = False
            
            # move to next period ---------------------------------------------------------------------------------------------
            start_id = (start_id + STIMULUS_CYCLE) % MAX_PKG_ID

            # ? check whether send out point can be reached or delay of processing is too big ?
            current_receive_id = newest_receive_pkg_id[0]
            while (
                    MAX_PKG_ID//2 > ((
                        start_id-MIN_PKG_DELAY - current_receive_id # When this term is negative break
                        + ((3*MAX_PKG_ID)//2)) % MAX_PKG_ID)):
                start_id = (start_id + STIMULUS_CYCLE) % MAX_PKG_ID
                current_receive_id = newest_receive_pkg_id[0]
                print(
                    f"Missed period {index}, increased to start_id {start_id} with overhead {(start_id-newest_receive_pkg_id[0])/FS*1000 :.3f}"
                )     

            segment_ids[0] = start_id
            if ((start_id+RESPONSE_IMPORTANT_PERIOD) % MAX_PKG_ID) < segment_ids[0]:
                segment_ids[1] = MAX_PKG_ID-1
            else:
                segment_ids[1] = (start_id+RESPONSE_IMPORTANT_PERIOD) % MAX_PKG_ID

            # Here the wait period ends ----------------------------------------------
            current_receive_id = newest_receive_pkg_id[0]
            while ((
                        MAX_PKG_ID//2 < ((
                            start_id-MIN_PKG_DELAY - current_receive_id # When this term is negative break
                            + ((3*MAX_PKG_ID)//2)) % MAX_PKG_ID))):
                time.sleep(1e-3)
                current_receive_id = newest_receive_pkg_id[0]
                # print(f"Waiting for commands at {start_id} at current receive {current_receive_id}")
                if stim_pipe_server.poll():
                    # set amplitude or delays here
                    stimulus = stim_pipe_server.recv()
                    stim_id, stim_matrix = stimulus
                    if stim_id != index + 1:
                        stim_matrix = np.array([])
                        print(f"Mismatch received {stim_id} for period {index+1}")                    
                    else:
                        recv_flag = True
                        break

            if stim_matrix.shape[0]:
                
                # print(f"Min Distance for stim: {stimulus_timing_min_dist}")

                stim_delays = -np.unique(-stim_matrix[:, 0])
                stim_matrix = stim_matrix[np.argsort(-stim_matrix[:, 0]),:]

                all_flags = np.zeros(stim_delays.shape[0], dtype=int)                

                # flag is 0, add onset or offset command, just pulses
                if ARTEFACT_CANCELLATION:
                    all_flags[0] += 1
                    all_flags[-1] += 2
            
                for delay_num, stim_delay in enumerate(stim_delays):
                    if stim_delay >= 0:
                        stim_pkg = (start_id-stim_delay)%MAX_PKG_ID
                    else:
                        stim_pkg = 0x80000000 - stim_delay # for negative rerlative delay in samples
                    command_pipe.send(
                        (
                            stim_pkg, 
                            ELECTRODE_MAPPING.network2mea(stim_matrix[np.equal(stim_matrix[:, 0], stim_delay),1:]), 
                            all_flags[delay_num]
                        )
                    )     
                    # print(f'Received stim electrodes are {ELECTRODE_MAPPING.network2mea(stim_matrix[np.equal(stim_matrix[:, 0], stim_delay),1:])}, because mapping is {ELECTRODE_MAPPING.network2mea(np.array([[n//15, n%15] for n in range(60)]))} and received is {stim_matrix} at {stim_delay}')           
                    # print(f"Sending out with {stim_delay}, and flags {all_flags[delay_num]}, shape is {len(ELECTRODE_MAPPING.network2mea(stim_matrix[np.equal(stim_matrix[:, 0], stim_delay),1:]))}")
            else:
                stim_delays = (0)
            

            # start readout again
            period_over_event.clear()

            if not index % PRINT_STEP:
                print(
                    f"stimulate commands sent out: {(start_id-newest_receive_pkg_id[0])/FS*1000 :.3f} ms before stim with points {stim_delays} - {start_id}"
                )
                # print(f"Timing: Wait for period {t1*1e3:.3f} plus poll total {t2*1e3:.3f} Spike conversion {t3*1e3:.3f} put on q {t4*1e3:.3f} wait for stim {t5*1e3:.3f} receive commands {t6*1e3:.3f}  send {t7*1e3:.3f}")

            # emit for plotting here
            if stim_matrix is not None:
                if stim_matrix.shape[0]:
                    raster_plot_pipe.send(
                        (
                            last_index_rec,
                            networks_spike_mat[plot_channels.value],
                            stim_matrix[np.equal(stim_matrix[:, 1], plot_channels.value)], # adapt how raster reads slot id
                        )
                    )
                else:
                    raster_plot_pipe.send(
                        (last_index_rec, networks_spike_mat[plot_channels.value], [])
                    )
            else:
                raster_plot_pipe.send(
                    (last_index_rec, networks_spike_mat[plot_channels.value], [])
                )

            response['spikes'] = networks_spike_mat
            response['stim'] = stim_matrix
            
            stim_matrix = np.array([])
            skipped_period = False
        stim_event.wait()


def control_connection_process(ip, port, pw="1234", medium_port = None):
    stim_pipe_server, stim_pipe_client = mp.Pipe(duplex=True)
    control_recv, control_send = mp.Pipe(duplex=False)

    env_reg_write_recv, env_reg_write_send = mp.Pipe(duplex=False)

    level_q = mp.Queue(MAX_LEN_LVL_Q)
    env_q = mp.Queue(MAX_LEN_ENV_Q)
    spont_spike_q = mp.Queue(MAX_LEN_SPONT_Q)

    # register pipe object for connection
    base_manager = BaseManager(address=(ip, port), authkey=pw.encode("utf-8"))
    base_manager.register("stim_pipe_client", callable=lambda: stim_pipe_client)
    base_manager.register("control_send", callable=lambda: control_send)
    base_manager.register("spont_spike_q", callable=lambda: spont_spike_q)

    # start managers (should be in subrocesses)
    server_thread = threading.Thread(
        target=start_bm_server, args=(base_manager, 0), daemon=False
    )
    server_thread.start()

    if medium_port is not None:
        bm_medium = BaseManager(address=(ip, medium_port), authkey=pw.encode("utf-8"))
        bm_medium.register("level_q", callable=lambda: level_q)
        bm_medium.register("env_q", callable=lambda: env_q)
        bm_medium.register("env_reg_write_send", callable=lambda: env_reg_write_send)
        medium_server_thread = threading.Thread(
            target=start_bm_server, args=(bm_medium, 0), daemon=False
        )
        medium_server_thread.start()

    return stim_pipe_server, control_recv, level_q, env_q, spont_spike_q, env_reg_write_recv

def start_bm_server(bm, _):
    s = bm.get_server()
    print(f"Starting server at {s.address[0]}:{hex(s.address[1])[2:]}")
    s.serve_forever()

def win_client(serverAddressPort, timeout):
    msgFromClient       = "Hello UDP Server"
    bytesToSend         = str.encode(msgFromClient)
    # serverAddressPort   = (HOST_IP,RECEIVE_PORT)

    sckt = socket.socket(family=socket.AF_INET, type=socket.SOCK_DGRAM)
    sckt.connect(serverAddressPort)

    # for i in range(8):
    for _ in range(5):
        sckt.sendto(str.encode(chr(8)) + b' ' + bytesToSend, serverAddressPort)
        time.sleep(.3)

    print("Connected")

    return sckt