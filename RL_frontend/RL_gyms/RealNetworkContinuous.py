import gymnasium as gym
from gymnasium import spaces

from Reward.LinearReward              import LinearReward      as Reward
from StateReduction.StaticStateSimple import StaticStateSimple as State

from HelperFunctions.check_action_continuous import check_action

import multiprocessing

import numpy as np
import time

import pickle
import zmq

from Client_config import (
    RL_INTERFACE_PORT
)

class RealNetworkContinuous(gym.Env):
    """
    Create a time sensitive Simulated network environment, that can be interacted with just like the a real network. You can give this class up to 5 parameters:
    - stim_length      int               The length of the stim interval in sample time. (From ms to this, multiply by 17.361)
    - state_dim        int               State dimension of state/observation space (reduced representation of neuronal activity)
    - circuit_id       int               Here, you choose which of network to use. Must be in {0,1,...,59}
    - reward_function  func  (optional)  Reward function that receives the neuronal activity as an input. If you do not set it, the default is being used.
    - state_function   func  (optional)  This function transforms your neuronal activity into a reduced representation in [-1,1]^n, where [-1,1] are numbers
                                         between -1 and +1 and n is the state_dim defined above.
    
    You can interact with the environment as with any other Gymnasium environment: https://gymnasium.farama.org/index.html
    
    If you do not send an action in time, the default action is being used, which does not stimulate the network at all (all action slots are -1).
    
    Action space: is 4-dimensional (float). Each value needs to be between (and including) -1 and 1. Negative values means no stimulus is applied. Otherwise, the values are scaled with self.stim_length and discretized.
    """
    
    metadata = {"render.modes": ["human"]}

    def __init__(self,stim_length,state_dim,circuit_id,reward_object=None,state_object=None):
        super(RealNetworkContinuous,self).__init__()

        self.stim_length = stim_length
        self.action_dim  =           4 # Hardcoded to 4 electrodes
        self.state_dim   =   state_dim
        
        if reward_object is None:
            reward_object = Reward()
        if state_object is None:
            state_object = State(self.state_dim)
        self.reward_object = reward_object
        self.state_object  =  state_object
        
        self.action_space      = spaces.Box(low=-1,high=1,shape=(self.action_dim,)) 
        self.observation_space = spaces.Box(low=-3,high=3,shape=(self.state_dim,))

        # For initialization
        self.state          = np.zeros((self.state_dim,))
        self.reward         = 0
        self.last_stimulus  = 0    

        # Server access
        self.host           = "127.0.0.1"
        self.port           = RL_INTERFACE_PORT
        circuit_id          = int(circuit_id+0.5)
        self.circuit_id     = circuit_id

        self.context = zmq.Context()
        self.context.setsockopt(zmq.LINGER, 0)
        self.dealer_socket = self.context.socket(zmq.DEALER)
        self.dealer_socket.connect(f"tcp://{self.host}:{self.port}")

        # Wait for response
        self.poller = zmq.Poller()
        self.poller.register(self.dealer_socket, zmq.POLLIN)

    def reset(self,seed=None,options=None):
        """
        Reset the environment state.
        """
        super().reset(seed=seed)
        
        # Initialize the state by setting it to 0.
        self.state          = np.zeros((self.state_dim,))
        self.last_stimulus  = -1
        return self.state,{}

    def step(self,action,ctr=0):
        """
        Apply action and return new state, reward, termination info, and extra info. This process is not time sensitive (i.e. waits for user).
        """

        # Check action:
        action, msg = check_action(action,self.action_dim)

        # Transform the actions to a list:
        list_actions = []
        for i in range(self.action_dim):
            if action[i] <= 0:
                continue
            latency       = int((1-action[i])*self.stim_length)
            list_array    = np.zeros(3,dtype=int)
            list_array[0] = latency # 0 - 86
            list_array[1] = self.circuit_id 
            list_array[2] = i
            list_actions.append(list_array)
        
        # Apply action
        msg_body = pickle.dumps({"action": list_actions, "circuit_id": self.circuit_id})
        self.dealer_socket.send(msg_body)

        socks = dict(self.poller.poll(2000))
        if self.dealer_socket in socks:
            # If the socket is ready, receive the response
            response = pickle.loads(self.dealer_socket.recv())
        else:
            # Handle the timeout scenario (i.e. restart dealer)
            print("Timeout occured, reconnect ... (If this persists, check that inkube is running)")
            self.dealer_socket.setsockopt(zmq.LINGER, 0)
            self.poller.unregister(self.dealer_socket)   # old one, careful
            self.dealer_socket.close()

            self.dealer_socket = self.context.socket(zmq.DEALER)
            self.dealer_socket.connect(f"tcp://{self.host}:{self.port}")
            self.poller = zmq.Poller()
            self.poller.register(self.dealer_socket, zmq.POLLIN)

            if ctr < 30:
                return(self.step(action,ctr=ctr+1))
            else:
                # Server is dead!
                response = np.zeros([0,2])
                
                state  = self.state_object.get_state(response)
                reward = self.reward_object.reward(response)
                
                terminated = True
                truncated  = False

                msg        = "Server is dead!"
                missed_stimuli = 1
                stim_id = 0
                # Extra information to get information for the user
                info = {"spikes":     [], 
                        "elecs":      [], 
                        "action":     action,
                        "missed_cyc": missed_stimuli, 
                        "stim_id":    stim_id, 
                        "comment":    msg}
        
                return state,reward,terminated,truncated,info

        #action   = response["action"]
        if msg == 'none':
            msg  = response["message"] # Only look at message, if the action passed intial test. Otherwise, tell user why it failed
        index    = response["index"]
        elecs    = response["elecs"]
        spikes   = response["spikes"]

        if self.last_stimulus >= 0:
            missed_stimuli = index - 1 - self.last_stimulus
        else:
            missed_stimuli = 0
        self.last_stimulus = index
        stim_id            = index
        if missed_stimuli < 0:
            # This means a cycle is done and a reset occurs
            missed_stimuli = 0
            if msg == 'none':
                msg = "Cycle is over. A new cycle (with a new network has been chosen). Reset your network"

        response           = np.stack([spikes,elecs],1)

        # Define the space
        self.state  = self.state_object.get_state(response)
        
        # Calculate reward
        self.reward = self.reward_object.reward(response)

        # No truncation/termination
        terminated = False
        truncated  = False
        
        # Extra information to get information for the user
        info = {"spikes":     spikes, 
                "elecs":      elecs, 
                "action":     action,
                "missed_cyc": missed_stimuli, 
                "stim_id":    stim_id, 
                "comment":    msg}

        return self.state,self.reward,terminated,truncated,info

    def render(self,mode="human"):
        """
        Rendering the the current state and reward.
        """
        
        print(f"Current state: {self.state}, Reward: {self.reward}")
    
    def close(self):
        """Cleanly close ZMQ resources."""
        try:
            # Make sure socket closes immediately and does NOT linger
            self.dealer_socket.setsockopt(zmq.LINGER, 0)
        except Exception:
            pass

        try:
            self.dealer_socket.close()
        except Exception:
            pass

        # Poller does not have a .close() method in PyZMQ
        # Just drop the reference; it cleans up with context/socket destruction.
        self.poller = None

        try:
            # Terminate context (required!)
            self.context.term()
        except Exception:
            pass
