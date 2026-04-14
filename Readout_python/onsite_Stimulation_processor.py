import numpy as np
import multiprocessing as mp
import os
import time
import threading
import datetime
from multiprocessing.managers import BaseManager
import multiprocessing.connection as con
import socket
import zmq
import struct
import json
import time

from h5_saver import parse_spike_events


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
    MAX_LEN_ENV_Q, 
    MAX_LEN_SPONT_Q, 
    MAX_LEN_LVL_Q, 
    CONSTANT_TRIGGERED_STIM_SHIFT, 

    ZMQ_SPIKE_SOCKET, 
    ZMQ_PKG_SOCKET, 
    ZMQ_STIMCOM_SOCKET, 

    connect_to_zmq,
    drain_zmq_queue, 

    ZMQ_RESPONSE_ENDPOINT, 
    ZMQ_STIM_REQUEST_ENDPOINT, 
)

EMPTY_SPIKE_MAT = np.empty((NETWORK_NUM, ELECTRODES), dtype=object)
for j in np.ndindex(EMPTY_SPIKE_MAT.shape):
    EMPTY_SPIKE_MAT[j] = tuple()

from Send_commands import write_to_register

def map_spikes_to_matrix(spike_events, start_id):
    networks_spike_mat = np.copy(EMPTY_SPIKE_MAT)

    channel_ids = spike_events['channel_id']
    package_ids = spike_events['package_id'].astype(int)

    unique_ch = np.unique(channel_ids)
    latencies = package_ids - start_id

    for ch_order, ch in enumerate(unique_ch):
        spike_ids = np.where(channel_ids == ch)[0]
        networks_spike_mat[ELECTRODE_MAPPING.mapping_recv2network[ch][0], ELECTRODE_MAPPING.mapping_recv2network[ch][1]] = tuple(latencies[spike_ids])

    return networks_spike_mat

def get_spike_latency_and_mapping(spike_events, start_id):
    package_ids = spike_events['package_id'].astype(int)

    latencies = [int(l) for l in (package_ids - start_id)]
    networks = [int(n) for n in (ELECTRODE_MAPPING.mapping_recv2network[spike_events['channel_id']][:,0])]
    electrodes = [int(e) for e in (ELECTRODE_MAPPING.mapping_recv2network[spike_events['channel_id']][:,1])]
    return latencies, networks, electrodes

def get_spike_mapping(spike_events):
    # .astype(int)
    networks = [int(n) for n in (ELECTRODE_MAPPING.mapping_recv2network[spike_events['channel_id']][:,0])]
    electrodes = [int(e) for e in (ELECTRODE_MAPPING.mapping_recv2network[spike_events['channel_id']][:,1])]
    return networks, electrodes

# First, let's update the closed_loop_stim function to use ZMQ for publishing
def closed_loop_stim(
        command_pipe: con.Connection,
        stim_event,
        started_pkg, # time of pkg ID 0, to determine current cycle
        stim_cycle, 
):
    spike_socket = connect_to_zmq(ZMQ_SPIKE_SOCKET)
    package_socket = connect_to_zmq(ZMQ_PKG_SOCKET)
    poll_timeout_in_ms = 5

    # Initialize ZMQ context
    context = zmq.Context.instance()   
    
    # Publisher socket for stimulation data
    stimcom_pub_socket = context.socket(zmq.PUB)
    stimcom_pub_socket.bind(ZMQ_STIMCOM_SOCKET)
    
    # New publisher for spike responses
    response_pub_socket = context.socket(zmq.PUB)
    response_pub_socket.bind(ZMQ_RESPONSE_ENDPOINT)

    poller = zmq.Poller()
    poller.register(package_socket, zmq.POLLIN)
    poller.register(spike_socket, zmq.POLLIN)

    spike_poller = zmq.Poller()
    spike_poller.register(spike_socket, zmq.POLLIN)

    spike_events = []
    networks_spike_mat = np.empty((NETWORK_NUM, ELECTRODES), dtype=object)
    for j in np.ndindex(networks_spike_mat.shape):
        networks_spike_mat[j] = tuple()

    stim_id = 0
    index = 0
    recv_flag = False
    stim_matrix = np.array([])

    # Create a new socket for receiving stimuli
    stim_recv_socket = context.socket(zmq.SUB)
    stim_recv_socket.connect(ZMQ_STIM_REQUEST_ENDPOINT)
    stim_recv_socket.setsockopt(zmq.SUBSCRIBE, b"")  # Subscribe to all messages
    
    stim_poller = zmq.Poller()
    stim_poller.register(stim_recv_socket, zmq.POLLIN)

    started_pkg_dt = datetime.datetime.strptime(started_pkg, '%Y-%m-%d %H:%M:%S.%f')

    while True:
        stim_event.wait()
        print(f"Starting closed loop stim")

        s_len = drain_zmq_queue(spike_socket)
        print(f"Retrieved spikes {s_len}")

        pkg_len = drain_zmq_queue(package_socket)
        print(f"Retrieved pkgs {pkg_len}")
        recv_flag = False
        
        stimulus_cycle_dyn = stim_cycle.value
        print(f"Using dynamic stimulus cycle {stimulus_cycle_dyn} samples, which is {stimulus_cycle_dyn/FS*1000:.3f} ms")
        current_pkg_id = int.from_bytes(package_socket.recv(), 'little')
        start_id = ((current_pkg_id//stimulus_cycle_dyn)*stimulus_cycle_dyn + START_ID_INIT) % MAX_PKG_ID

        while stim_event.is_set():
            stim_id = 0
            index = 0

            # retrieve current_pkg_id from zmq, only in the beginning
            current_pkg_id = int.from_bytes(package_socket.recv(), 'little')
            cycle = (datetime.datetime.now() - started_pkg_dt) // datetime.timedelta(seconds=MAX_PKG_ID / FS)

            upper_wait_limit = (start_id+RESPONSE_IMPORTANT_PERIOD) % MAX_PKG_ID

            spike_events = []

            # wait here until recording period is over
            while (
                    MAX_PKG_ID//2 < ((
                        upper_wait_limit - current_pkg_id # When this term is negative break
                        + ((3*MAX_PKG_ID)//2)) % MAX_PKG_ID)):
    
                # Poll both data and spike sockets with a 10ms timeout
                socks = dict(poller.poll(poll_timeout_in_ms))

                # Receive package ID from ZeroMQ
                if package_socket in socks:
                    current_pkg_id = int.from_bytes(package_socket.recv(), 'little')

                # receive spike data, check if in relevant period
                if spike_socket in socks:
                    spike_data = spike_socket.recv()
                    if len(spike_data) > 3:
                        spike_count = struct.unpack("I", spike_data[:4])[0]
                        if spike_count:
                            parsed_spikes = parse_spike_events(spike_data)
                            first_pkg = parsed_spikes[0]['package_id']
                            last_pkg = parsed_spikes[-1]['package_id']
                            in_relevant_period = (
                                (
                                    (MAX_PKG_ID//2 + first_pkg) % MAX_PKG_ID 
                                    < (MAX_PKG_ID//2 + upper_wait_limit) % MAX_PKG_ID 
                                )
                                or (
                                    (MAX_PKG_ID//2 + last_pkg) % MAX_PKG_ID 
                                    > (MAX_PKG_ID//2 + start_id) % MAX_PKG_ID 
                                    )
                                )
                            if in_relevant_period:
                                spike_events.append(parsed_spikes)

            # retrieve rest of spikes, poll once and get next spike package
            while True:
                socks = dict(spike_poller.poll(poll_timeout_in_ms))
                if spike_socket in socks:
                    spike_data = spike_socket.recv()  # get at least one more spike package
                    if len(spike_data) > 3:
                        spike_count = struct.unpack("I", spike_data[:4])[0]
                        if spike_count:
                            parsed_spikes = parse_spike_events(spike_data)
                            spike_events.append(parsed_spikes)
                try:
                    # Drain all available spike messages
                    while True:
                        spike_data = spike_socket.recv(zmq.NOBLOCK)  # Non-blocking receive
                        if len(spike_data) > 3:
                            spike_count = struct.unpack("I", spike_data[:4])[0]
                            if spike_count:
                                parsed_spikes = parse_spike_events(spike_data)
                                spike_events.append(parsed_spikes)
                        else:
                            break
                except zmq.Again:
                    # No more messages left in the queue
                    break

            # get relevant spikes, take care of jump in package ID
            if len(spike_events):
                spike_events = np.concatenate(spike_events)
                first_spike_id_list = np.where(spike_events['package_id'] > start_id)[0]
                if first_spike_id_list.shape[0]:
                    first_spike_id = first_spike_id_list[0]
                else:
                    first_spike_id = -1
                last_spike_id_list = np.where(spike_events['package_id'] > upper_wait_limit)[0]
                if last_spike_id_list.shape[0]:
                    last_spike_id = last_spike_id_list[0]
                else:
                    last_spike_id = -1

                spike_events = spike_events[first_spike_id:last_spike_id]
                if spike_events.shape[0]:
                    latencies, networks, electrodes = get_spike_latency_and_mapping(spike_events, start_id)
                else:
                    latencies = []
                    networks = []
                    electrodes = []
                    print(f"No spikes detected in period {index}")
                # print(f'Length of spikes is {spike_events.shape[0]} in period {index}')
            else:
                latencies = []
                networks = []
                electrodes = []
                print(f"No spikes detected in period {index}")
            
            # Prepare and send out response after recording is over
            # index is the number of period
            
            # move index parameter to next period
            index = start_id // stimulus_cycle_dyn
            
            # Create the response message
            response_data = {
                'index': index,
                'spikes': [],
                'latencies': latencies,
                'networks': networks,
                'electrodes': electrodes,
                'stim_recv': recv_flag
            }
            
            # Convert to JSON and send
            try:
                response_json = json.dumps(response_data)
            except Exception:
                print(type(response_data['index']))
                print(type(response_data['spikes']))
                print(type(response_data['latencies'][0]))
                print(type(response_data['networks'][0]))
                print(type(response_data['electrodes'][0]))
                print(type(response_data['stim_recv']))
            # print(f"Sending out response for period {index}")
            response_pub_socket.send_string(response_json)
            # print(f'Sent response out backend {time.time()*1e3}')

            recv_flag = False 

            # move to next period ---------------------------------------------------------------------------------------------
            start_id = (start_id + stimulus_cycle_dyn) % MAX_PKG_ID

            # check whether send out point can be reached or delay of processing is too big
            current_pkg_id = int.from_bytes(package_socket.recv(), 'little')
            while (
                    MAX_PKG_ID//2 > ((
                        start_id-MIN_PKG_DELAY - current_pkg_id # When this term is negative break
                        + ((3*MAX_PKG_ID)//2)) % MAX_PKG_ID)):
                start_id = (start_id + stimulus_cycle_dyn) % MAX_PKG_ID
                current_pkg_id = int.from_bytes(package_socket.recv(), 'little')
                print(
                    f"Missed period {index}, increased to start_id {start_id} with overhead {(start_id-current_pkg_id)/FS*1000 :.3f}"
                )     

            # Here the wait period ends ----------------------------------------------
            while ((
                        MAX_PKG_ID//2 < ((
                            start_id-MIN_PKG_DELAY - current_pkg_id # When this term is negative break
                            + ((3*MAX_PKG_ID)//2)) % MAX_PKG_ID))):

                # Look for incoming stimulus from the client
                stim_socks = dict(stim_poller.poll(0))
                if stim_recv_socket in stim_socks:
                    # Receive stimulus data
                    stim_json = stim_recv_socket.recv_string()
                    stim_data = json.loads(stim_json)
                    
                    stim_id = stim_data.get('stim_id', 0)
                    stim_matrix = np.array(stim_data.get('stim_matrix', []))
                     
                    if stim_id == 0:
                        print(f"Untimed stim received for period {index+1}")
                        recv_flag = True
                        stim_id = index + 1
                        break
                    elif stim_id != index + 1:
                        stim_matrix = np.array([])
                        print(f"Mismatch received {stim_id} for period {index+1}")     
                    else: 
                        print(f"Stim received for period {index+1}")
                        recv_flag = True
                        break
                
                current_pkg_id = int.from_bytes(package_socket.recv(), 'little')

            # print(f'Not receiving stims anymore {time.time()*1e3}')
            num_pulses = stim_matrix.shape[0] if isinstance(stim_matrix, np.ndarray) else 0
            if num_pulses:
                # print(f"Min Distance for stim: {stimulus_timing_min_dist}")

                stim_delays = -np.unique(-stim_matrix[:, 0])
                stim_matrix = stim_matrix[np.argsort(-stim_matrix[:, 0]),:]

                # use constant for now, later atomatically check whether interleaving is necessary
                all_flags = np.ones(stim_delays.shape[0], dtype=int)*2 # for interleaving stimuli

                # flag is 0, add onset or offset command, just pulses
                all_flags[0] += 1
                all_flags[-1] += 2
            
                for delay_num, stim_delay in enumerate(stim_delays):
                    if stim_delay >= 0:
                        stim_pkg = (start_id-stim_delay)%MAX_PKG_ID
                    else:
                        stim_pkg = 0x80000000-stim_delay # for negative rerlative delay in samples
                    command_pipe.send(
                        (
                            stim_pkg, 
                            ELECTRODE_MAPPING.network2mea(stim_matrix[np.equal(stim_matrix[:, 0], stim_delay),1:]), 
                            all_flags[delay_num]
                        )
                    )     
                    
                # **Flatten the stim_matrix**
                # print(f"Sending out stim with {num_pulses} pulses")

                flat_stim_matrix = stim_matrix.flatten()

                # **Pack the binary message**
                if np.any(flat_stim_matrix > 255) or np.any(flat_stim_matrix < 0):
                    flat_stim_matrix = np.clip(flat_stim_matrix, 0, 255)
                stim_struct = struct.pack(f"!IHH{num_pulses*3}B", start_id, cycle, num_pulses, *flat_stim_matrix)
                # **Send raw binary message**
                try:
                    stimcom_pub_socket.send(stim_struct)
                except Exception as e:
                    print(f"Error sending stim: {e}")
            else:
                stim_delays = (0)
                print(f"Received no stim, moving to next period")
        
            stim_matrix = np.array([])



# First, let's update the closed_loop_stim function to use ZMQ for publishing
def spike_triggered_stim(
        command_pipe: con.Connection,
        triggered_stim_event,
        drop_stim_timeout = 5., 
):
    spike_socket = connect_to_zmq(ZMQ_SPIKE_SOCKET)
    package_socket = connect_to_zmq(ZMQ_PKG_SOCKET)
    poll_timeout_in_ms = 5

    # Initialize ZMQ context
    context = zmq.Context.instance()
    
    # Publisher socket for stimulation data to h5
    stimcom_pub_socket = context.socket(zmq.PUB)
    stimcom_pub_socket.bind(ZMQ_STIMCOM_SOCKET)

    pkg_poller = zmq.Poller()
    pkg_poller.register(package_socket, zmq.POLLIN)

    spike_poller = zmq.Poller()
    spike_poller.register(spike_socket, zmq.POLLIN)

    # Create a new socket for receiving stimuli from the jupyter
    stim_recv_socket = context.socket(zmq.SUB)
    stim_recv_socket.connect(ZMQ_STIM_REQUEST_ENDPOINT)
    stim_recv_socket.setsockopt(zmq.SUBSCRIBE, b"")  # Subscribe to all messages
    
    stim_poller = zmq.Poller()
    stim_poller.register(stim_recv_socket, zmq.POLLIN)

    while True:
        triggered_stim_event.wait()
        print(f"Starting conditional triggered stim")

        s_len = drain_zmq_queue(spike_socket)
        print(f"Retrieved spikes {s_len}")

        while triggered_stim_event.is_set():
            stim_socks = dict(stim_poller.poll(0))
            if stim_recv_socket in stim_socks:
                # Receive stimulus data
                stim_json = stim_recv_socket.recv_string()
                stim_data = json.loads(stim_json)
                
                stim_matrix = np.array(stim_data.get('stim_matrix', []))
                stim_trigger_location = np.array(stim_data.get('trigger_location', []))

                num_pulses = stim_matrix.shape[0] if isinstance(stim_matrix, np.ndarray) else 0
                if num_pulses:
                    # print(f"Min Distance for stim: {stimulus_timing_min_dist}")

                    stim_delays = -np.unique(-stim_matrix[:, 0])
                    stim_matrix = stim_matrix[np.argsort(-stim_matrix[:, 0]),:]

                    # use constant for now, later atomatically check whether interleaving is necessary
                    all_flags = np.ones(stim_delays.shape[0], dtype=int)*2 # for interleaving stimuli

                    # flag is 0, add onset or offset command, just pulses
                    all_flags[0] += 1
                    all_flags[-1] += 2
                    print(f"Triggering stim - waiting for spike at {stim_trigger_location}")
                
                    t0 = time.time()

                    while time.time() - t0 < drop_stim_timeout:
                        socks = dict(spike_poller.poll(poll_timeout_in_ms))
                        # receive spike data, check if in relevant period
                        if spike_socket in socks:
                            spike_data = spike_socket.recv()
                            if len(spike_data) > 3: # this means there are spikes in the data
                                spike_count = struct.unpack("I", spike_data[:4])[0]
                                if spike_count:
                                    parsed_spikes = parse_spike_events(spike_data)
                                    networks, electrodes = get_spike_mapping(parsed_spikes)
                                    
                                    # check if trigger network and electrode are in the spike events
                                    matching_positions = np.where(
                                        (networks == stim_trigger_location[0]) & 
                                        (electrodes == stim_trigger_location[1])
                                    )[0]                                    
    
                                    if matching_positions.shape[0]:   
                                        # Get package IDs at those matching positions
                                        package_ids = parsed_spikes['package_id'].astype(int)
                                        relevant_package_ids = package_ids[matching_positions]  
                                                       
                                        for delay_num, stim_delay in enumerate(stim_delays):
                                            if stim_delay <= 0:
                                                stim_pkg = 0x80000000 - stim_delay # for negative rerlative delay in samples
                                            else:                                                
                                                stim_pkg = relevant_package_ids[-1] + stim_delay + CONSTANT_TRIGGERED_STIM_SHIFT
                                            command_pipe.send(
                                                (
                                                    stim_pkg, 
                                                    ELECTRODE_MAPPING.network2mea(stim_matrix[np.equal(stim_matrix[:, 0], stim_delay),1:]), 
                                                    all_flags[delay_num]
                                                )
                                            )                                                 
                                        print(f"Trigger spike detected at pkg {relevant_package_ids}, sending out stim")  
                                        # this whole block is for h5 saving ------------------------------------------------
                                        # **Flatten the stim_matrix**
                                        # print(f"Sending out stim with {num_pulses} pulses")

                                        flat_stim_matrix = np.abs(stim_matrix.flatten())

                                        # **Pack the binary message**
                                        flat_stim_matrix = np.clip(flat_stim_matrix, 0, 255)
                                        stim_struct = struct.pack(f"!IHH{num_pulses*3}B", 0, 0, num_pulses, *flat_stim_matrix)
                                        # **Send raw binary message**
                                        try:
                                            stimcom_pub_socket.send(stim_struct)
                                        except Exception as e:
                                            print(f"Error sending stim: {e}")
                                        stim_matrix = np.array([])
                                        # --------------------------------------------------------------------------------
                                        print(f"Trigger spike detected, sent out after {time.time() - t0:.3f} seconds")
                                        break
                    if time.time() - t0 > drop_stim_timeout:
                        print(f'No trigger spike detected in {drop_stim_timeout} seconds, dropping stimulus')
                else:
                    print(f"Received no stim, moving on")
            drain_zmq_queue(spike_socket)

# Now let's update the Control_connection_process function to remove the pipe object
def control_connection_process(ip, port, pw="1234", medium_port=None):
    control_recv, control_send = mp.Pipe(duplex=False)

    env_reg_write_recv, env_reg_write_send = mp.Pipe(duplex=False)

    level_q = mp.Queue(MAX_LEN_LVL_Q)
    env_q = mp.Queue(MAX_LEN_ENV_Q)
    spont_spike_q = mp.Queue(MAX_LEN_SPONT_Q)

    # register control objects (but not the stim_pipe anymore)
    base_manager = BaseManager(address=(ip, port), authkey=pw.encode("utf-8"))
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

    return control_recv, level_q, env_q, spont_spike_q, env_reg_write_recv

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