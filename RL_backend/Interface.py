import zmq
import time
import pickle
import numpy as np
from zmq.auth.thread import ThreadAuthenticator
from zmq import Again
import sys

import matplotlib.pyplot as plt
import time

import multiprocessing

from Communication_for_Hackathon import Communication
sys.path.insert(0,"../Readout_python")
from Client_config import (
    STIMULUS_CYCLE, 
    CONTROL_CLIENT_PORT, 
    RL_INTERFACE_PORT, 
    MIN_PKG_DELAY, 
    FS, 
    RESPONSE_IMPORTANT_PERIOD, 
    STIMULATION_DURATION, 
    DISCHARGE_TIME, 
)

COM_ON    = True
loc_host  = "127.0.0.1"
host      = "127.0.0.1"
tot_circ  = 15
min_time_until_send = 4

ZMQ_CTRL_PUB_SOCKET = f"tcp://*:5521"

POLL_TIME_DELAY_MS   = 2 # ms 
extra_com_delay_from_interface_ms = 10 # from cpp Spike batches + time for sending through port - from 20
constant_stimulation_offset = 2*STIMULATION_DURATION + DISCHARGE_TIME + 4 # + int(5*FS/1000) # samples # 1/2 packages after reconnect 
set_frequency = 4.

time_until_send   = (int(1/set_frequency*FS)-MIN_PKG_DELAY-RESPONSE_IMPORTANT_PERIOD)/FS*1000-POLL_TIME_DELAY_MS-extra_com_delay_from_interface_ms # ms
print(f'Calculated time until send {time_until_send}')
time_until_send   = max(time_until_send, min_time_until_send) # ms
print(f'Time until send {time_until_send}')

context = zmq.Context.instance()

# Set router mode and open socket
router_socket = context.socket(zmq.ROUTER)
router_socket.setsockopt(zmq.RCVTIMEO, POLL_TIME_DELAY_MS)
router_socket.bind(f"tcp://{loc_host}:{RL_INTERFACE_PORT}")

# Add a subscriber socket for receiving commands
# After your socket setup, replace the individual timeout stuff with:
command_pull_socket = context.socket(zmq.PULL)
command_pull_socket.bind(ZMQ_CTRL_PUB_SOCKET)

# Create poller and register sockets
poller = zmq.Poller()
poller.register(router_socket, zmq.POLLIN)

control_poller = zmq.Poller()
control_poller.register(command_pull_socket, zmq.POLLIN)

# Remove the RCVTIMEO from router_socket since poller handles timing
# router_socket.setsockopt(zmq.RCVTIMEO, POLL_TIME_DELAY_MS)  # Comment this out

print(f"Server running on port {RL_INTERFACE_PORT}.")

com = Communication(loc_host,host,CONTROL_CLIENT_PORT)
com.send_control({"mode": 0})
time.sleep(.5)
com.send_control({'thresh_update': 0}) # fix threshold for stimulation
time.sleep(.5)
com.send_control({'stim_freq': set_frequency}) # fix threshold for stimulation
time.sleep(.5)
com.send_control({"mode": 2})
time.sleep(.1)
com.get_response() # Clear any initial messages
print("Connected")

t0               = time.time()
pending_requests = {}
step             = 0
current_index    = 0

# time_until_send = 20 # ms

while True:
    try:
        frames = router_socket.recv_multipart()
    except Again: # This means we timed out (nothing was sent)
        frames = []

    # frames should be [client_identity, message_bytes]
    if len(frames) >= 2:
        client_id, message = frames[0], frames[1]

        # Store the request in a dictionary
        pending_requests[client_id] = message
    else:
        socks = dict(control_poller.poll(0))
        if command_pull_socket in socks:
            print("Command received")
            command_message = command_pull_socket.recv()
            try:
                command_data = pickle.loads(command_message)
            except Exception as e:
                print(f"Error unpickling command message: {e}")
                command_data = ''
            com.send_control({"mode": 0})
            time.sleep(1)
            if "frequency" in command_data:
                frequency = float(command_data["frequency"])
                print(f"Received frequency command: {frequency}")
                com.send_control({'stim_freq': frequency}) # fix threshold for stimulation
                time_until_send   = (int(1/frequency*FS)-MIN_PKG_DELAY-RESPONSE_IMPORTANT_PERIOD)/FS*1000-POLL_TIME_DELAY_MS-extra_com_delay_from_interface_ms # ms
                print(f'Calculated time until send {time_until_send}')
                time_until_send   = max(time_until_send, min_time_until_send) # ms
                print(f'New time until send {time_until_send}')

                time.sleep(1)
            if "saving" in command_data:
                saving = int(command_data["saving"])
                print(f"Received saving command: {saving}")
                com.send_control({'saving': saving})
                time.sleep(1)
            if "stim_amp" in command_data:
                stim_amp = int(command_data["stim_amp"])
                print(f"Received stimulation amplitude command: {stim_amp}")
                com.send_control({'stim_amp': stim_amp})
                time.sleep(1)

            com.send_control({"mode": 2})
            time.sleep(.1)
            com.get_response() # Clear any initial messages

            t0               = time.time()
            pending_requests = {}
            step             = 0
            # time_until_send = 20 # ms

    if (time.time() - t0 > time_until_send/1000) or (len(pending_requests) >= tot_circ): # Every 250 ms, but send after 200 ms
        t1 = time.time()
        
        active         = np.zeros(tot_circ) # Making sure only one client connects to each circuit
        
        sparse_actions = []
        
        for cid, message in pending_requests.items(): # TODO: Move this part in front of the if statement deciding the time cut-off
            try:
                d          = pickle.loads(message)
                actions    = d["action"] # Should be a list of np.array size 3 type int!
                
                circuit_id = np.clip(d["circuit_id"],0,tot_circ-1)
                
                if active[circuit_id] == 0:
                    active[circuit_id] = 1
                    sparse_actions      = sparse_actions+actions # Add current action set to list of actions
                else:
                    print(f"At least two clients try to connect to circuit id: {circuit_id}")
                    active[circuit_id] = 2 # Telling the client something went wrong

            except:
                print("We should never be here")
                # print(cid,d)


        # Get responses from inkube after stimulating it
        response_elecs  = np.zeros(tot_circ,dtype=object)
        response_spikes = np.zeros(tot_circ,dtype=object)
        if len(sparse_actions) == 0:
            sparse_actions = np.zeros((0,3),dtype=int)
            com.send_stimulus(sparse_actions, index=0) #current_index+1)
            t_send = time.time()
            response = com.get_response()
            print(f"No action: send-> recv {int((time.time()-t_send)*1000)} ms")
        else:
            sparse_actions = np.stack(sparse_actions,0,dtype=int)
            sparse_actions[:,0] += constant_stimulation_offset
                
            # Send all actions at once and receive responses from system 
            com.send_stimulus(sparse_actions, current_index+1)
            t_send = time.time()
            response = com.get_response()
            
            if response['stim_recv'] == False:
                response = com.get_response()
                misaligned = 1
                if response['stim_recv'] == False:
                    misaligned = 2
            else:   
                misaligned = 0
            print(f"Action misaligned {misaligned}: send-> recv {int((time.time()-t_send)*1000)} ms")
        current_index = response['index']
        t0 = time.time() # Set time based on when the package was received
        
        for net in range(tot_circ): # TODO: Probably remove this for loop and use np.where instead
            if active[net] == 0:
                continue # We do not care about this network then, as it did not get stimulated
            spikes_circ = response['spikes'][net] # has 4 elements
            
            spikes = []
            elecs  = []
            for i in range(4):
                for s in spikes_circ[i]:
                    if s >= 0 and s < RESPONSE_IMPORTANT_PERIOD:
                        spikes.append(s)
                        elecs.append(i)
            
            if len(spikes) > 0:
                spikes    = np.stack(spikes)
                elecs     = np.stack(elecs)
                order     = np.argsort(spikes)
                spikes    = spikes[order]
                elecs     = elecs[order]
            else:
                spikes    = np.zeros(0)
                elecs     = np.zeros(0,dtype=int)
            
            response_elecs[net]  = elecs
            response_spikes[net] = spikes
        
        for cid, message in pending_requests.items():
            # Run simulation
            data_temp       = pickle.loads(message)
            action          = data_temp["action"]
            recv_circuit_id = data_temp["circuit_id"]
            circuit_id      = np.clip(recv_circuit_id,0,tot_circ-1)

            msg = None
            if recv_circuit_id != circuit_id:
                msg = f"Your circuit ID is not valid: {recv_circuit_id} vs {circuit_id}"
            elif active[circuit_id] != 1:
                msg = "Either none or multiple clients stimulated this network"
            
            response = pickle.dumps({"action": action,
                                    "message": msg,
                                    "index":   step,
                                    "elecs":   response_elecs[circuit_id],     # TODO: Here is probably np.where (plus line below)
                                    "spikes":  response_spikes[circuit_id]})
            router_socket.send_multipart([cid,response])

        print(f"{step}: {int((time.time()-t1)*1000)} ms. {sparse_actions.shape[0]} {active}")
        step += 1

        pending_requests.clear()
    

