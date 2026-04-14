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
from HelperFunctions.generate_stimuli import generate_latin_hypercube_stimuli, generate_latin_hypercube_discrete_stimuli

from RL_gyms.RealNetworkDiscrete   import RealNetworkDiscrete
from RL_gyms.RealNetworkContinuous import RealNetworkContinuous
from StateReduction.DynamicStatePCA import DynamicStatePCA

from DiscreteAgents.PureMAB                        import PureMAB as PureMAB_D
from DiscreteAgents.LinearContextualBandits        import LinearContextualBandits as LinearContextualBandits_D
from DiscreteAgents.DynamicLinearContextualBandits import DynamicLinearContextualBandits as DynamicLinearContextualBandits_D

from ContinuousAgents.BaseAgent               import BaseAgent as BaseAgent_C
from ContinuousAgents.DummyAgent              import DummyAgent as DummyAgent_C
from ContinuousAgents.LinearContextualBandits import LinearContextualBandits as LinearContextualBandits_C
from ContinuousAgents.AdaptiveMAB             import AdaptiveMAB as AdaptiveMAB_C

import multiprocessing as mp
from Reward.ISIseqReward import ISIseqReward

def run_agent(circuit_id, run_signal, freq_run,discrete=False):
    # Define size of state and action spaces, as well as stimulation period
    state_dim      = 5   # Dimension of reduced state space
    if discrete:
        action_dim = 4   # Number of stimuli in action space
    else:
        action_dim = 4
    num_elec       = 4   # Number of electrodes in the circuit

    state_length_ms = 20 # Length of state in ms

    # Create state
    state_object  = DynamicStatePCA(state_dim=state_dim,data_length=int(17.3*state_length_ms),bin_size=8)  # 10 ms at 0.5 ms bin size
    # state_object  = Dynamic1DCNNEncoder(state_dim=state_dim)
    np.random.seed(circuit_id)

    # Create environment and initialize it
    length_in_samples = int(5*17.361)
    if discrete:
        env      = RealNetworkDiscrete(action_dim=action_dim,
                                       stim_length=length_in_samples,
                                       state_dim=state_dim,
                                       circuit_id=circuit_id,
                                       reward_object=ISIseqReward(),
                                       state_object=state_object)
        agent_ids = np.array([1,2,3])[np.random.permutation(3)]
    else:
        env      = RealNetworkContinuous(stim_length=length_in_samples,
                                         state_dim=state_dim, 
                                         circuit_id=circuit_id,
                                         reward_object=ISIseqReward(),
                                         state_object=state_object) 
        agent_ids = np.array([4,7])[np.random.permutation(2)]
    state, _ = env.reset()
    
    def train_pca(num_samples=7200):
        spikes    = []
        elecs     = []

        if not discrete:
            stimuli = generate_latin_hypercube_stimuli(
            n_samples=num_samples, 
            n_electrodes=action_dim, 
            require_stimulation=True, 
            seed=circuit_id
        )
        else:
            stimuli = generate_latin_hypercube_discrete_stimuli(
                n_samples=num_samples, 
                n_electrodes=num_elec, 
                action_dim=action_dim,
                require_stimulation=True, 
                seed=circuit_id
            )

        for i in range(num_samples):
            if not run_signal.is_set():
                break
            action = stimuli[i]
            state, reward, terminated, truncated, info = env.step(action)
            
            spikes.append(info['spikes'])
            elecs.append(info['elecs'])
    
        print("Fitting state...")
        t0 = time.time()
        # responses = np.array([np.column_stack([s, e]) for s, e in zip(spikes, elecs)], dtype=object)
        # env.state_object.fit(responses)
        env.state_object.fit(spikes,elecs)
        print(f"Fitting done in {time.time()-t0:.2f} s")

    def get_agent(agent_id):
        if discrete:
            # if   agent_id == 0:
            #     agent = ...(state_dim,action_dim)
            if agent_id == 1:
                agent = LinearContextualBandits_D(state_dim,action_dim)
            elif agent_id == 2:
                agent = PureMAB_D(state_dim,action_dim)
            elif agent_id == 3:
                agent = DynamicLinearContextualBandits_D(state_dim,action_dim)
            # elif agent_id == 4:
            #     agent = ...(state_dim,action_dim)
        else:
            # if agent_id == 0:
            #     agent = ...(state_dim,action_dim)
            # if agent_id == 1:
            #     agent = ...(state_dim,action_dim)
            # elif agent_id == 2:
            #     agent = ...(state_dim,action_dim)
            # elif agent_id == 3:
            #     agent = ...(state_dim,action_dim)
            if agent_id == 4:
                agent = DummyAgent_C(state_dim,action_dim)
            # elif agent_id == 5:
            #     agent = ...(state_dim,action_dim)
            # elif agent_id == 6:
            #     agent = ...(state_dim,action_dim)
            elif agent_id == 7:
                agent = LinearContextualBandits_C(state_dim,action_dim)
            # elif agent_id == 8:
            #     agent = ...(state_dim,action_dim)
            # elif agent_id == 9:
            #     agent = ...(state_dim,action_dim)
            # elif agent_id == 10:
            #     agent = ...(state_dim,action_dim)
        return agent

    for run_id in range(agent_ids.shape[0]):
        if not run_signal.is_set():
            break
        agent_id = agent_ids[run_id]

        if discrete:
            if agent_id == 2: # PureMAB
                train_steps = int(10_000) 
            elif agent_id == 1: # LinCB
                train_steps = int(28_800 * 3)
            else:
                train_steps =  int(28_800 * 2.5)
            test_steps  =   4_800
        else:    
            if agent_id == 4: # Dummy
                test_steps  =   0    
            else:
                test_steps  =   4_800
            train_steps =  int(28_800 * 4)
        
        pca_steps   =   7_200

        agent    = get_agent(agent_id)

        if run_id == 0:
            train_pca(num_samples=pca_steps)

        train_vec = np.zeros(train_steps)
        test_vec  = np.zeros(test_steps)

        train_actions = np.zeros((train_steps,num_elec))
        test_actions  = np.zeros((test_steps,num_elec))
        
        train_states = np.zeros((train_steps,state_dim))
        test_states  = np.zeros((test_steps,state_dim))

        test_spikes =  np.empty((test_steps),dtype=object)
        train_spikes = np.empty((train_steps),dtype=object)

        state, _ = env.reset()

        if (agent_id == 3) and discrete:
            agent.set_flags([1,0])
        if (agent_id == 4) and discrete:
            agent.set_flags([1,0])

        # Training
        for step in range(train_steps):
            if not run_signal.is_set():
                break
            # Get action from agent
            action = agent.get_action(state)
            
            # Take step in environment
            next_state, reward, terminated, truncated, info = env.step(action)

            train_actions[step] = action
            train_states[step]  = next_state
            
            if (step == int(train_steps*.33)):
                if (agent_id == 3) and discrete:
                    agent.set_flags([0,1])
                if (agent_id == 4) and discrete:
                    agent.set_flags([0,0])                    

            # Update agent (removed terminated/truncated since they're always False)
            agent.update(state, action, reward, next_state)
            
            state = next_state
            train_spikes[step] = np.stack([info["spikes"],info["elecs"]],1)
            train_vec[step] = reward        

        # Testing
        for step in range(test_steps):
            if not run_signal.is_set():
                break
            # Get action from agent
            action = agent.get_action_deterministic(state) 
            
            # Take step in environment
            state, reward, terminated, truncated, info = env.step(action)
            
            test_vec[step] = reward
            test_actions[step] = action
            test_states[step]  = state

            test_spikes[step] = np.stack([info["spikes"],info["elecs"]],1)

        data = np.zeros(8,dtype=object)
        data[0] = train_states
        data[1] = train_actions
        data[2] = train_vec
        data[3] = test_states
        data[4] = test_actions
        data[5] = test_vec
        data[6] = test_spikes
        data[7] = train_spikes

        if discrete:
            filename = f"{save_folder}/circuit_{circuit_id}_agent_{agent_id}_run_{freq_run}_discrete.npy"
        else:
            filename = f"{save_folder}/circuit_{circuit_id}_agent_{agent_id}_run_{freq_run}_continuous.npy"
        np.save(filename,data)

        # save agent stats
        if discrete:
            agent.save(f"{save_folder}/circuit_{circuit_id}_agent_{agent_id}_run_{freq_run}_discrete_stats")
        else:   
            agent.save(f"{save_folder}/circuit_{circuit_id}_agent_{agent_id}_run_{freq_run}_continuous_stats")
        
        print(agent_id,np.mean(train_vec),np.mean(test_vec))
        time.sleep(10*60) # Wait 10 minutes between agents

# Main execution
if __name__ == "__main__":
    command_push_socket = initialize_control_socket()
    time.sleep(2)
    # Spontaneous recording
    for _ in range(1):
        time.sleep(0*60)
        send_saving_command(2, command_push_socket)
        time.sleep(5*60)
        send_saving_command(0, command_push_socket)

    time.sleep(2)

    selected_nw = np.array([...]) # List of selected network IDs to run agents on
    frequencies = [4.]
    try:        
        for rep in range(len(frequencies)):
            send_stim_amp_command(5, command_push_socket)  # Example command to set stim amplitude to 1
            time.sleep(2)
            send_frequency_command(frequencies[rep], command_push_socket)
            time.sleep(2)
            # send_saving_command(0, command_push_socket)
            # time.sleep(2)
            date_prefix = generate_date_prefix()
            save_folder = f"../Data/{date_prefix}_agent_selected_sweep"
            if not os.path.exists(save_folder):
                os.makedirs(save_folder)
            process_list = []
            signals = []
            
            # Run discrete case
            time.sleep(1.5)
            for circuit_id in selected_nw:
                run_signal = mp.Event()
                run_signal.set()  # Start with signal active
                process = mp.Process(target=run_agent, args=(circuit_id, run_signal, rep, True))
                process.start()
                process_list.append(process)
                signals.append(run_signal)
            
            # Wait for processes or user interrupt
            for process in process_list:
                process.join()
            
            # Run continuous case
            time.sleep(1.5)
            for circuit_id in selected_nw:
                run_signal = mp.Event()
                run_signal.set()  # Start with signal active
                process = mp.Process(target=run_agent, args=(circuit_id, run_signal, rep, False))
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
