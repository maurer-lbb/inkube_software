
import numpy as np
from scipy.stats import qmc

def generate_latin_hypercube_stimuli(n_samples=7200, n_electrodes=4, 
                                     require_stimulation=True, seed=42):
    """
    Generate Latin Hypercube sampling of stimulus space for PCA training
    
    Parameters:
    -----------
    n_samples : int
        Total number of stimuli to generate (default 7200 for ~30min at 4Hz)
    n_electrodes : int
        Number of electrodes (default 4)
    require_stimulation : bool
        If True, ensure at least one electrode is stimulated (>0)
    seed : int
        Random seed for reproducibility
    
    Returns:
    --------
    stimuli : array of shape (n_samples, n_electrodes)
        Each row is one stimulus, values in [-1, 1]
        -1 to 0: no stimulation
        0 to 1: stimulation with latency (1=0ms, 0=5ms)
    """
    
    np.random.seed(seed)
    
    if require_stimulation:
        # Generate extra samples to account for filtering
        sampler = qmc.LatinHypercube(d=n_electrodes, seed=seed)
        n_generate = int(n_samples * 1.5)  # Generate 50% extra
        sample = sampler.random(n=n_generate)
        stimuli = sample * 2 - 1  # Scale from [0,1] to [-1, 1]
        
        # Filter: keep only samples with at least one electrode > 0
        valid_mask = np.any(stimuli > 0, axis=1)
        stimuli = stimuli[valid_mask]
        
        # If we don't have enough, generate more
        iteration = 1
        while len(stimuli) < n_samples:
            extra_needed = n_samples - len(stimuli)
            sampler = qmc.LatinHypercube(d=n_electrodes, seed=seed + iteration)
            extra_sample = sampler.random(n=extra_needed * 2)
            extra_stimuli = extra_sample * 2 - 1
            extra_valid = extra_stimuli[np.any(extra_stimuli > 0, axis=1)]
            stimuli = np.vstack([stimuli, extra_valid])
            iteration += 1
        
        # Trim to exact size
        stimuli = stimuli[:n_samples]
    else:
        sampler = qmc.LatinHypercube(d=n_electrodes, seed=seed)
        sample = sampler.random(n=n_samples)
        stimuli = sample * 2 - 1
    
    # Shuffle to avoid any remaining structure
    np.random.shuffle(stimuli)
    
    return stimuli


# Example usage
# stimuli = generate_latin_hypercube_stimuli(n_samples=7200, require_stimulation=True)

import numpy as np

def generate_latin_hypercube_discrete_stimuli(n_samples=7200, n_electrodes=4, 
                                               action_dim=5, require_stimulation=True, 
                                               seed=42):
    """
    Generate Latin Hypercube sampling for discrete action space
    
    Parameters:
    -----------
    n_samples : int
        Total number of stimuli to generate (default 7200 for ~30min at 4Hz)
    n_electrodes : int
        Number of electrodes (default 4)
    action_dim : int
        Number of discrete latency levels (e.g., 5 means levels 0,1,2,3,4,5)
        0 = no stimulation
        1 = highest latency (e.g., 5ms)
        action_dim = lowest latency (e.g., 0ms)
    require_stimulation : bool
        If True, ensure at least one electrode is stimulated (value > 0)
    seed : int
        Random seed for reproducibility
    
    Returns:
    --------
    stimuli : array of shape (n_samples, n_electrodes)
        Each row is one stimulus, integer values in [0, action_dim]
        0 = no stimulation
        1 to action_dim = stimulation with decreasing latency
    """
    from scipy.stats import qmc
    
    np.random.seed(seed)
    
    if require_stimulation:
        # Generate extra samples to account for filtering
        sampler = qmc.LatinHypercube(d=n_electrodes, seed=seed)
        n_generate = int(n_samples * 1.5)
        sample = sampler.random(n=n_generate)
        
        # Map [0,1] to [0, action_dim] discrete levels
        # Scale [0,1) to [0, action_dim+1) then floor to get [0, action_dim]
        stimuli = np.floor(sample * (action_dim + 1)).astype(int)
        
        # Ensure we don't exceed action_dim due to floating point
        stimuli = np.clip(stimuli, 0, action_dim)
        
        # Filter: keep only samples with at least one electrode > 0
        valid_mask = np.any(stimuli > 0, axis=1)
        stimuli = stimuli[valid_mask]
        
        # If we don't have enough, generate more
        iteration = 1
        while len(stimuli) < n_samples:
            extra_needed = n_samples - len(stimuli)
            sampler = qmc.LatinHypercube(d=n_electrodes, seed=seed + iteration)
            extra_sample = sampler.random(n=extra_needed * 2)
            extra_stimuli = np.floor(extra_sample * (action_dim + 1)).astype(int)
            extra_stimuli = np.clip(extra_stimuli, 0, action_dim)
            extra_valid = extra_stimuli[np.any(extra_stimuli > 0, axis=1)]
            stimuli = np.vstack([stimuli, extra_valid])
            iteration += 1
        
        # Trim to exact size
        stimuli = stimuli[:n_samples]
    else:
        sampler = qmc.LatinHypercube(d=n_electrodes, seed=seed)
        sample = sampler.random(n=n_samples)
        stimuli = np.floor(sample * (action_dim + 1)).astype(int)
        stimuli = np.clip(stimuli, 0, action_dim)
    
    # Shuffle to avoid any remaining structure
    np.random.shuffle(stimuli)
    
    return stimuli
