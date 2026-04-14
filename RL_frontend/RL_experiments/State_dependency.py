import gymnasium as gym
import numpy as np
import time

# Add parent directory to path
import sys
import os
from pathlib import Path
current_dir = Path().resolve()
root_dir = current_dir.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0,str(root_dir))
root_dir = root_dir.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0,str(root_dir)+"/Readout_python")    

from HelperFunctions.ControlSocket import initialize_control_socket, send_frequency_command, send_saving_command, send_stim_amp_command
from HelperFunctions.date_prefix import generate_date_prefix
from HelperFunctions.generate_stimuli import generate_latin_hypercube_stimuli

from RL_gyms.RealNetworkContinuous import RealNetworkContinuous
from StateReduction.StaticStateDownsampled import StaticStateDownsampled

import multiprocessing as mp

date_prefix = generate_date_prefix()

def run_agent(circuit_id, run_signal):
    # Define size of state and action spaces, as well as stimulation period
    state_dim   = 4*20   # Dimension of reduced state space
    action_dim  = 4      # Number of stimuli in action space

    num_AB_runs       = 50
    num_AB_pairing    = 8*60*4*10    # 8 min at 4 Hz
    pca_samples       = 0

    dropout_prob = 0.75 # probability for no stimulation on an electrode in AB pairing

    state_object = StaticStateDownsampled(state_dim=state_dim,bin_size=18)          # 20 ms at 1 ms bin size (20 bin per elec)
    
    # Create environment and initialize it
    length_in_samples = int(5*17.361)
    env      = RealNetworkContinuous(stim_length=length_in_samples, state_dim=state_dim, circuit_id=circuit_id,state_object=state_object) 
    state, _ = env.reset()
    
    np.random.seed(circuit_id)
        
    ####################################################################
    # Random AB pairing
    ####################################################################
    save_folder_current = f"{save_folder}/random_AB"
    if not os.path.exists(save_folder_current):
        try:
            os.makedirs(save_folder_current)
        except:
            pass

    for pair in range(num_AB_runs):
        if not run_signal.is_set():
            break
            
        actions         = np.zeros((num_AB_pairing,action_dim))
        states          = np.zeros((num_AB_pairing,state_dim))
        spike_responses = np.empty((num_AB_pairing),dtype=object)
        
        A               = env.action_space.sample()
        A[A<0]          = A[A<0]*(-1)
        A[np.random.random(action_dim)<dropout_prob] = -1
        while np.sum(A>0) == 0:
            A               = env.action_space.sample()
            A[A<0]          = A[A<0]*(-1)
            A[np.random.random(action_dim)<dropout_prob] = -1

        B               = env.action_space.sample()
        B[B<0]          = B[B<0]*(-1)
        B[np.random.random(action_dim)<dropout_prob] = -1

        while np.sum(B>0) == 0:
            B               = env.action_space.sample()
            B[B<0]          = B[B<0]*(-1)
            B[np.random.random(action_dim)<dropout_prob] = -1

        for run in range(num_AB_pairing): 
            if not run_signal.is_set():
                break
            
            if np.random.random() > 0.5:
                action = np.copy(A)
            else:
                action = np.copy(B)
            state, reward, terminated, truncated, info = env.step(action)
        
            actions[run,:] = info['action']
            states[run,:]  = state
            
            spike_responses[run] = np.stack([info["spikes"],info["elecs"]],1)   
            
        data = np.zeros(3,dtype=object)
        data[0] = actions
        data[1] = states
        data[2] = spike_responses

        filename = f"{save_folder_current}/circuit_{circuit_id}_AB_run_{pair}.npy"
        np.save(filename,data)      

        time.sleep(2*60)  
    

# Main execution
if __name__ == "__main__":
    # Create shared signal
    max_num_circuits = 15
    try: 
        for freq in [16., 4.]:
            print(f'Starting frequency {freq} Hz')
            date_prefix = generate_date_prefix()
            save_folder = f"../Data/{date_prefix}_state_dependency_{int(freq)}"
            if not os.path.exists(save_folder):
                os.makedirs(save_folder)

            process_list = []
            signals = []
            command_push_socket = initialize_control_socket()
            time.sleep(1)
            send_frequency_command(freq, command_push_socket)  # Example command to set frequency to
            time.sleep(1)
            send_stim_amp_command(5, command_push_socket)  # Example command to set stim amplitude to 1
            time.sleep(1)
            send_saving_command(0, command_push_socket)

            # Create FRESH lists each iteration
            current_processes = []
            current_signals = []
            
            for circuit_id in range(max_num_circuits):
                run_signal = mp.Event()
                run_signal.set()
                process = mp.Process(target=run_agent, args=(circuit_id, run_signal))
                process.start()
                current_processes.append(process)
                current_signals.append(run_signal)

            for process in current_processes:
                process.join()
                process.close() 
            
            # Now they're done, forget about them
            current_processes.clear()
            current_signals.clear()
        
            time.sleep(30*60)
            
    except KeyboardInterrupt:
        print("Keyboard interrupt received")
        for r in current_signals:
            r.clear()
        

    send_saving_command(0, command_push_socket)

