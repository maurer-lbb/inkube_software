import gymnasium as gym
import numpy as np
import time

# Add parent directory to path
import sys
from pathlib import Path
import os
current_dir = Path().resolve()
root_dir = current_dir.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0,str(root_dir))
root_dir = root_dir.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0,str(root_dir)+"/Readout_python")    

from HelperFunctions.ControlSocket import initialize_control_socket, send_frequency_command, send_saving_command, send_stim_amp_command
from HelperFunctions.date_prefix import generate_date_prefix
date_prefix = generate_date_prefix()

from RL_gyms.RealNetworkContinuous import RealNetworkContinuous
from StateReduction.StaticStateDownsampled import StaticStateDownsampled

import multiprocessing as mp

def run_agent(circuit_id, run_signal, rep_id, num_patterns=500):
    # Define size of state and action spaces, as well as stimulation period
    state_dim    = 4      # Dimension of reduced state space
    action_dim   = 4      # Number of stimuli in action space
    
    num_stim     = num_patterns*10 # 50 h at 4 Hz
    
    # Create state
    state_object = StaticStateDownsampled(state_dim=state_dim,bin_size=180)          # 20 ms at 1 ms bin size (20 bin per elec)
    
    # Create environment and initialize it
    length_in_samples = int(5*17.361)
    env      = RealNetworkContinuous(stim_length=length_in_samples, state_dim=state_dim, circuit_id=circuit_id,state_object=state_object) 
    state, _ = env.reset()
    
    np.random.seed(circuit_id)
        
    ####################################################################
    # Random multi pairing
    ####################################################################
    
    
    actions         = np.zeros(num_patterns,dtype=object)
    states          = np.zeros(num_patterns,dtype=object)
    rewards         = np.zeros(num_patterns)
    
    if not rep_id:
        patterns        = np.array([env.action_space.sample() for _ in range(num_patterns)])
        for p_id in range(num_patterns):
            while np.sum(patterns[p_id]<0) == 4:
                patterns[p_id] = env.action_space.sample()

        pattern_ids = np.random.randint(0,num_patterns,size=num_stim*10) # Randomly shuffle patterns for each run
        np.save(f"{save_folder}/circuit_{circuit_id}_patterns.npy", patterns)
        np.save(f"{save_folder}/circuit_{circuit_id}_pattern_ids.npy", pattern_ids)
    else:
        loaded = False
        time.sleep(circuit_id/4)  # Stagger loading to avoid conflicts
        while not loaded:
            try:
                patterns        = np.load(f"{save_folder}/circuit_{circuit_id}_patterns.npy", allow_pickle=True)
                pattern_ids     = np.load(f"{save_folder}/circuit_{circuit_id}_pattern_ids.npy", allow_pickle=True)
                loaded = True
            except:
                time.sleep(1)
        print(f'Loaded patterns for circuit {circuit_id} with shape {patterns.shape}')

    
    for run in range(num_stim): 
        if not run_signal.is_set():
            break
        pattern_id = pattern_ids[run+rep_id*num_stim]
        action = np.copy(patterns[pattern_id])
        state, reward, terminated, truncated, info = env.step(action)
        
        actions[run % num_patterns] = info['action']
        states[run % num_patterns]  = (info['spikes'],info['elecs'])
        rewards[run % num_patterns] = reward
        
        if run % num_patterns == (num_patterns-1):
            data = np.zeros(3,dtype=object)
            data[0] = actions
            data[1] = states
            data[2] = rewards

            filename = f"{save_folder}/circuit_{circuit_id}_run_{run//num_patterns}_{rep_id}.npy"
            np.save(filename,data)

    return patterns

# Main execution
if __name__ == "__main__":
    # Create shared signal
    max_num_circuits = 15
    process_list = []
    signals = []
    command_push_socket = initialize_control_socket()

    date_prefix = generate_date_prefix()
    save_folder = f"../Data/{date_prefix}_random_sequence_rand"
    if not os.path.exists(save_folder):
        os.makedirs(save_folder)

    time.sleep(2)
    send_saving_command(0, command_push_socket)
    time.sleep(62)
    send_saving_command(2, command_push_socket)
    time.sleep(5*60)
    send_saving_command(0, command_push_socket)

    time.sleep(2)
    send_stim_amp_command(5, command_push_socket)  # Example command, changed from 5
    time.sleep(2)
    send_frequency_command(4., command_push_socket)  # Example command to set frequency to
    time.sleep(2)

    selected_nw = np.concatenate([np.array([3,4,5,13,14]), np.array([1,2,5,8,10,11,13])+30]) # MEA2


    try:        
        for rep in range(10): # for 10*10 periods
            print(f'Iteration {rep} of 20')
            # if not (rep % 2):
            #     send_saving_command(2, command_push_socket)  # Enable saving
            # else:
            #     send_saving_command(0, command_push_socket)

            time.sleep(1.5)
            for circuit_id in selected_nw:
                run_signal = mp.Event()
                run_signal.set()  # Start with signal active
                process = mp.Process(target=run_agent, args=(circuit_id, run_signal, rep, 500))
                process.start()
                process_list.append(process)
                signals.append(run_signal)
            
            # Wait for processes or user interrupt
            for process in process_list:
                process.join()
            
    except KeyboardInterrupt:
        print("Keyboard interrupt received")
        for r in signals:
            r.clear()
        
    finally:
        # Clean shutdown
        for p in process_list:
            p.join(timeout=.5)  # Wait up to .5 seconds
            if p.is_alive():
                p.terminate()  # Force kill if still running

    time.sleep(5*60)


