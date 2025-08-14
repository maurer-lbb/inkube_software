import numpy as np
from multiprocessing.managers import BaseManager

import zmq
import json
import time
NETWORK_NUM = 60
ELECTRODES = 4

class Communication:
    """
    Communication class for electrophysiology which can switch the mode of operation, send stimuli and receive electrophysiology data
    """
    def __init__(self, host, port, auth_key="1234"):
        """
        Communication class to send stimuli to the simulation and receive responses
        Args:
            host: str, host address, use either localhost or ip address of lab host PC
            port: int, port number
            auth_key: str, authentication key
        Returns:
            None
        """
        self.host = host
        self.port = port
        self.auth_key = auth_key

        # Set limit for reconnection tries
        self.reconnection_tries = 0
        self.max_tries = 3
        self.timeout = 500-3
        self.just_triggered_spontaneous = False
        self.last_stimulus = None

        modes = ['idle', 'spontaneous', 'stimulation_closed', 'stimulation_open']

        # Initialize ZMQ context and sockets
        self.context = zmq.Context()
        
        # Create subscriber for response data
        self.response_sub = self.context.socket(zmq.SUB)
        self.response_sub.connect(f"tcp://{host}:5459")  # Use actual port number in place of ZMQ_RESPONSE_PORT
        self.response_sub.setsockopt(zmq.SUBSCRIBE, b"")  # Subscribe to all messages
        
        # Create publisher for stimulus data
        self.stim_pub = self.context.socket(zmq.PUB)
        self.stim_pub.bind(f"tcp://{host}:5460")  # Use actual port number in place of ZMQ_STIM_REQUEST_PORT

        # Set up poller for non-blocking receive
        self.poller = zmq.Poller()
        self.poller.register(self.response_sub, zmq.POLLIN)
        
        self.new_connection()
            
    def new_connection(self):
        """
        Establishes a new connection with the specified host and port and registers the data exchange pipes and queues.
        Returns:
            int: Returns -1 if the connection could not be established, otherwise returns None.
        """
        print('\nWait for new connection ...')
        flag = True
        class CommunicationManager(BaseManager): pass
        CommunicationManager.register('control_send')
        CommunicationManager.register('spont_spike_q')

        while flag:
            time.sleep(1)
            try:
                m = CommunicationManager(address=(self.host, self.port), authkey=self.auth_key.encode("utf-8"))
                m.connect()

                self.control_pipe = m.control_send()
                self.spont_spike_q = m.spont_spike_q()
                
                flag = False
                self.reconnection_tries = 0
            except Exception as e:
                if self.reconnection_tries > self.max_tries: 
                    flag = False
                else:
                    flag = True
                print("Connection Failed")
                print(e)
                print("Retry connection")
                self.reconnection_tries += 1
        if not self.reconnection_tries:
            print('Connected')
        else:
            print('Connection could not be established')
            return -1
    
    def drain_response(self):
        """Drains all messages from a ZMQ socket queue without blocking."""
        message = None
        try:
            while True:
                message = self.response_sub.recv(zmq.DONTWAIT)  # Non-blocking receive
                # Optional: Process the message if needed
                time.sleep(1e-6)
        except zmq.Again:
            return message

    def get_response(self):
        """
        Get the response when main is in stimulation mode
        Returns:
            dict: Returns the response from the simulation
        """
        counter = 0
        try:
            while counter < 3000:
                # Poll with a timeout
                socks = dict(self.poller.poll(5))  # 5ms timeout
                
                if self.response_sub in socks:
                    # Receive JSON message
                    json_response = self.response_sub.recv_string()
                    
                    # Parse the JSON response
                    response = json.loads(json_response)
                    
                    # Reconstruct the spike matrix from flattened arrays
                    if 'latencies' in response and 'networks' in response and 'electrodes' in response:
                        # Initialize empty spike matrix
                        networks_spike_mat = np.empty((NETWORK_NUM, ELECTRODES), dtype=object)
                        for j in np.ndindex(networks_spike_mat.shape):
                            networks_spike_mat[j] = tuple()
                        
                        # Fill the spike matrix
                        spikes = response['latencies']
                        networks = response['networks']
                        electrodes = response['electrodes']
                        
                        # Group spikes by network and electrode
                        grouped_spikes = {}
                        for i in range(len(spikes)):
                            spike = spikes[i]
                            net_idx = networks[i]
                            elec_idx = electrodes[i]
                            
                            key = (net_idx, elec_idx)
                            if key not in grouped_spikes:
                                grouped_spikes[key] = []
                            grouped_spikes[key].append(spike)
                        
                        # Assign to network matrix
                        for (net_idx, elec_idx), spike_list in grouped_spikes.items():
                            networks_spike_mat[net_idx, elec_idx] = tuple(spike_list)
                        
                        # Add the reconstructed spike matrix to the response
                        response['spikes'] = networks_spike_mat
                    
                    if response['stim_recv']:                        
                        response['stim_matrix'] = self.last_stimulus
                    
                    # If we received a response but stim_recv is False, return it anyway
                    return response
                    
                counter += 1
                time.sleep(5e-3)
            
            # Timeout occurred
            return {'stim_recv': False, 'index': -1}
                
        except Exception as e:
            print(f"Error: Could not access response data with {e}, reconnecting...")
            if self.new_connection() != -1:
                return self.get_response()
        
        # No stimulus received
        return {'stim_recv': False, 'index': -1}

    def empty_spont_q(self):
        """
        Empty the spontaneous spike queue
        Returns:
            int: Returns 1 if the queue is emptied
        """
        while not self.spont_spike_q.empty():
            self.spont_spike_q.get_nowait()
        return 1

    def get_spont(self):
        """
        Get the response when main is in spontaneous mode
        Returns:
            dict: Returns the spontaneous spikes from the simulation
        """
        counter = 0
        try: 
            while not self.spont_spike_q.qsize():
                time.sleep(.05)
                counter+= 1
                if counter > 200: # 10sec
                    return None
            element = self.spont_spike_q.get()
            return element
        except Exception as e:
            print(f"Error: Could not access response pipe with {e}, reconnecting...")
            if self.new_connection() != -1:
                return self.empty_spont_q()
            
    def send_stimulus(self, stim_sequence, index=0):
        """
        Send the stimulus to the main script which then sends it via USB to the SoC
        Args:
            stim_sequence: list, list of stimuli
            index: int, index of the stimulus
        Returns:
            None
        """
        if index is None:
            index = 0
        try:
            # Create the stimulus message
            stim_data = {
                'stim_id': index,
                'stim_matrix': stim_sequence.tolist() if hasattr(stim_sequence, 'tolist') else stim_sequence
            }
            
            # Convert to JSON and send
            stim_json = json.dumps(stim_data)
            self.stim_pub.send_string(stim_json)
            self.last_stimulus = stim_sequence
            
        except Exception as e:
            print(f"Failed to send stimulus with error {e}")
            if self.new_connection() != -1:
                return self.send_stimulus(stim_sequence, index)

    def send_triggered_stimulus(self, stim_sequence, spike_nw, spike_el):
        """
        Send the stimulus to the main script which then sends it via USB to the SoC
        Args:
            stim_sequence: list, list of stimuli
            index: int, index of the stimulus
            trigger_location: tuple, (spike_nw, spike_el) where aspike on this triggers a stimulus
        Returns:
            None
        """

        try:
            # Create the stimulus message
            stim_data = {
                'stim_matrix': stim_sequence.tolist() if hasattr(stim_sequence, 'tolist') else stim_sequence, 
                'trigger_location': (spike_nw, spike_el)
            }
            
            # Convert to JSON and send
            stim_json = json.dumps(stim_data)
            self.stim_pub.send_string(stim_json)
            self.last_stimulus = stim_sequence
            
        except Exception as e:
            print(f"Failed to send stimulus with error {e}")
            if self.new_connection() != -1:
                return self.send_triggered_stimulus(stim_sequence, spike_nw, spike_el)

    def send_control(self, control_dict):
        """
        Send the control dictionary to the main script to change the settings like the mode of operation
        Args:
            control_dict: dict, control dictionary
        """
        try:
            self.control_pipe.send(control_dict)
        except Exception as e:
            print(f"Failed to send control command with error {e}")
            if self.new_connection() != -1:
                return self.send_control(control_dict)
                
    def close(self):
        """
        Close ZMQ sockets and context
        """
        try:
            self.response_sub.close()
            self.stim_pub.close()
            self.context.term()
        except Exception as e:
            print(f"Error closing ZMQ connections: {e}")
