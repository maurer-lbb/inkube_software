import numpy as np
from multiprocessing.managers import BaseManager
import time

class Communication:
    """
    Communication class for electrophysiology which can switch the mode of operation, send stimuli and receive electrophysiology data
    """
    def __init__(self,host,port,auth_key="1234"):
        """
        Communication class to send stimuli to the simulation and receive responses
        Args:
            host: str, host address, use either localhost or ip address of lab host PC
            port: int, port number
            auth_key: str, authentication key
        Returns:
            None
        """
        self.host     = host
        self.port     = port
        self.auth_key = auth_key

        # Set limit for reconnection tries
        self.reconnection_tries = 0
        self.max_tries = 3
        self.timeout  = 500-3
        self.just_triggered_spontaneous = False

        modes = ['idle', 'spontaneous', 'stimulation_closed', 'stimulation_open']

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
        CommunicationManager.register('stim_pipe_client')
        CommunicationManager.register('control_send')
        CommunicationManager.register('spont_spike_q')

        while flag:
            time.sleep(1)
            try:
                m = CommunicationManager(address=(self.host, self.port), authkey=self.auth_key.encode("utf-8"))
                m.connect()

                self.stim_pipe = m.stim_pipe_client()  # Queue to send commands to the simulation
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
    
    def get_response(self):
        """
        Get the resposne when main is in stimulation mode
        Returns:
            dict: Returns the response from the simulation
        """
        counter = 0
        try:
            while not self.stim_pipe.poll():
                if counter < 3000:
                    time.sleep(5e-3)
                    counter += 1
                else:
                    return {'stim_recv': False, 'index': -1}

            while self.stim_pipe.poll():
                element = self.stim_pipe.recv() 
                if element['stim_recv']:
                    return element
                
        except Exception as e:
            print(f"Error: Could not access response pipe with {e}, reconnecting...")
            if self.new_connection() != -1:
                return self.get_response()
        
        # print(f"No stimulus received, index is {element['index']}")
        return element

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
        Get the resposne when main is in spontaneous mode
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
            
    def send_stimulus(self, stim_sequence, index=None):
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
            self.stim_pipe.send((index, stim_sequence))
        except Exception as e:
            print("Failed to put stimulus on pipe with error {e}")
            if self.new_connection() != -1:
                return self.send_stimulus(stim_sequence, index)

    def send_control(self, control_dict):
        """
        Send the control dictionary to the main script to change the settings like the mode of operation
        Args:
            control_dict: dict, control dictionary
        """
        try:
            self.control_pipe.send(control_dict)
        except Exception as e:
            print("Failed to put stimulus on queue with error {e}")
            if self.new_connection() != -1:
                return self.send_control(control_dict)
