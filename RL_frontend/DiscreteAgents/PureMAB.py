import numpy as np
from .BaseAgent import BaseAgent
from typing import Dict, Any, Optional

# Pure Multi-Armed Bandit: ignores state completely, just learns which actions work best on average

class PureMAB(BaseAgent):
    """
    Pure Multi-Armed Bandit approach that completely ignores state.
    
    Uses Upper Confidence bound sampling to learn which discrete action work best
    on average across all states.
    """
    
    def __init__(self, state_dim: int, action_dim: int, num_elec: int = 4, exploration_noise: float = 0.5):
        super().__init__(state_dim, action_dim)
        self.num_elec          = num_elec
        
        # MAB parameters
        self.n_arms            = (action_dim + 1)**self.num_elec
        self.exploration_noise = exploration_noise
        self.total_pulls       = 0
        
        # For each action dimension, maintain statistics for each arm
        # Using Gaussian-Gamma conjugate prior for reward modeling
        self.arm_counts         = np.zeros(self.n_arms)  # Number of times each arm pulled
        self.arm_rewards_sum    = np.random.random(self.n_arms)*1e-20 # To give random order

        self.alpha              = .5 # The higher this value, the more exploration there is
    
    def get_action(self, state: np.ndarray) -> np.ndarray:
        q       = self.get_params()
        explore = self.alpha * np.sqrt(np.log(self.total_pulls+1)/(self.arm_counts+1e-10))
        total   = q + explore
        action_ = np.argmax(total)

        action  = np.zeros(self.num_elec,dtype=int)
        for i in range(self.num_elec):
            action[i] = action_  % (self.action_dim + 1)
            action_   = action_ // (self.action_dim + 1)
        
        return action
    
    def get_action_deterministic(self, state: np.ndarray) -> np.ndarray:
        """Get deterministic action using current best arms"""
        q       = self.get_params()
        total   = q
        action_ = np.argmax(total)

        action  = np.zeros(self.num_elec,dtype=int)
        for i in range(self.num_elec):
            action[i] = action_  % (self.action_dim + 1)
            action_   = action_ // (self.action_dim + 1)

        return action
    
    def update(self, state: np.ndarray, action: np.ndarray, reward: float, 
               next_state: Optional[np.ndarray] = None) -> None:
        """Update bandit statistics based on action and reward (ignore states)"""
        self.iteration   += 1
        self.total_pulls += 1

        action_ = 0
        for i in range(self.num_elec):
            action_ = action_ * (self.action_dim + 1) + action[self.num_elec-1-i]

        self.arm_rewards_sum[action_] += reward
        self.arm_counts[action_]      += 1
        
    
    def end_episode(self) -> None:
        """Called at episode end"""
        pass
    
    def get_param_count(self) -> int:
        """Return number of parameters (arm statistics)"""
        return self.n_arms
    
    def reset_params(self) -> None:
        """Reset all bandit statistics"""
        self.arm_counts      = np.zeros(self.n_arms)  # Number of times each arm pulled
        self.arm_rewards_sum = np.random.random(self.n_arms)*1e-20 # To give random order
        self.total_pulls     = 0
    
    def get_params(self) -> np.ndarray:
        """Get parameters as flat array"""
        return self.arm_rewards_sum/(self.arm_counts+1e-5) # q-value
    
    def set_params(self, params: np.ndarray) -> None:
        """Set parameters from flat array"""
        pass
    
    def should_update(self) -> bool:
        """Always update"""
        return True
    
    def get_stats(self) -> Dict[str, Any]:
        """Get training statistics"""        
        return {
            "iteration": self.iteration,
            "total_pulls": self.total_pulls,
            "q-values": self.get_params(),
        }
    
    def is_converged(self) -> bool:
        """Check if MAB has converged (all arms well-explored)"""
        min_pulls_per_arm = 10  # Minimum pulls required per arm
        if np.min(self.arm_counts) < min_pulls_per_arm:
            return False
        return True
    
    def save(self, filepath: str) -> None:
        """Save MAB state"""
        data = {
            'arm_counts':      self.arm_counts,
            'arm_rewards_sum': self.arm_rewards_sum,
            'total_pulls':     self.total_pulls,
        }
        np.savez(filepath, **data)
    
    def load(self, filepath: str) -> None:
        """Load MAB state"""
        data                 = np.load(filepath + '.npz')
        self.arm_counts      = data['arm_counts']
        self.arm_rewards_sum = data['arm_rewards_sum']
        self.total_pulls     = int(data['total_pulls'])
