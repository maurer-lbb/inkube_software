import numpy as np
from .BaseAgent import BaseAgent
from typing import Dict, Any, Optional

# Linear Contextual Bandits: extends PureMAB with linear contextual component W * s + q

class DynamicLinearContextualBandits(BaseAgent):
    """
    Linear Contextual Bandits approach that extends PureMAB with state dependency.
    
    Q-function: Q(s,a) = W * s + q
    where q is the same base value as in PureMAB and W is a learned matrix.
    """
    
    def __init__(self, state_dim: int, action_dim: int, num_elec: int = 4, exploration_noise: float = 0.5):
        super().__init__(state_dim, action_dim)
        self.num_elec          = num_elec
        
        # MAB parameters
        self.n_arms            = (action_dim + 1)**self.num_elec
        self.exploration_noise = exploration_noise
        self.total_pulls       = 0
        
        self.train_flags       = np.zeros(2,dtype=bool)
        
        # Base bandit statistics (same as PureMAB)
        self.arm_counts         = np.zeros(self.n_arms)  # Number of times each arm pulled
        self.arm_rewards_sum    = np.random.random(self.n_arms)*1e-20 # To give random order

        # Linear contextual component: W matrix (n_arms x state_dim)
        self.W = np.zeros((self.n_arms, state_dim))
        
        self.q = np.zeros((self.n_arms))
        
        # Store all state-action-reward history for least squares solution
        self.history_states  = []
        self.history_actions = []
        self.history_rewards = []
        
        self.alpha              = .5 # The higher this value, the more exploration there is
    
    def get_action(self, state: np.ndarray) -> np.ndarray:
        q       = self.get_params()  # Base q-values from bandit
        context = np.dot(self.W, state)  # W * s
        total_q = q + context  # W * s + q
        
        explore = self.alpha * np.sqrt(np.log(self.total_pulls+1)/(self.arm_counts+1e-10))
        total   = total_q + explore
        action_ = np.argmax(total)

        action  = np.zeros(self.num_elec,dtype=int)
        for i in range(self.num_elec):
            action[i] = action_  % (self.action_dim + 1)
            action_   = action_ // (self.action_dim + 1)
        
        return action
    
    def get_action_deterministic(self, state: np.ndarray) -> np.ndarray:
        """Get deterministic action using current best arms"""
        q       = self.get_params()  # Base q-values from bandit
        context = np.dot(self.W, state)  # W * s
        total   = q + context  # W * s + q
        action_ = np.argmax(total)

        action  = np.zeros(self.num_elec,dtype=int)
        for i in range(self.num_elec):
            action[i] = action_  % (self.action_dim + 1)
            action_   = action_ // (self.action_dim + 1)

        return action
    
    def update(self, state: np.ndarray, action: np.ndarray, reward: float, 
               next_state: Optional[np.ndarray] = None) -> None:
        """Update both bandit statistics and W matrix"""
        self.iteration   += 1
        self.total_pulls += 1

        # Convert action to arm index (same as PureMAB)
        action_ = 0
        for i in range(self.num_elec):
            action_ = action_ * (self.action_dim + 1) + action[self.num_elec-1-i]

        # Update bandit statistics (same as PureMAB)
        self.arm_rewards_sum[action_] += reward
        self.arm_counts[action_]      += 1
        
        # Store state-action-reward history
        self.history_states.append(state.copy())
        self.history_actions.append(action_)
        self.history_rewards.append(reward)
        
        # Solve W matrix and q vector from scratch using all data
        if len(self.history_rewards) % 100 == 0:
            self._solve_parameter()
        
    def end_episode(self) -> None:
        """Called at episode end"""
        pass
    
    def get_param_count(self) -> int:
        """Return number of parameters (arm statistics + W matrix)"""
        return self.n_arms + self.n_arms * self.state_dim
    
    def reset_params(self) -> None:
        """Reset all parameters"""
        self.arm_counts      = np.zeros(self.n_arms)
        self.arm_rewards_sum = np.random.random(self.n_arms)*1e-20
        self.W               = np.zeros((self.n_arms, self.state_dim))
        self.total_pulls     = 0
        self.history_states  = []
        self.history_actions = []
        self.history_rewards = []
    
    def get_params(self) -> np.ndarray:
        """Get base q-values (same as PureMAB)"""
        return self.q
    
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
            "W_norm": np.linalg.norm(self.W),
        }
    
    def is_converged(self) -> bool:
        """Check if bandit has converged"""
        min_pulls_per_arm = 10
        if np.min(self.arm_counts) < min_pulls_per_arm:
            return False
        return True
    
    def save(self, filepath: str) -> None:
        """Save bandit state"""
        data = {
            'arm_counts':      self.arm_counts,
            'arm_rewards_sum': self.arm_rewards_sum,
            'W':               self.W,
            'total_pulls':     self.total_pulls,
            'history_states':  np.array(self.history_states) if self.history_states else np.array([]),
            'history_actions': np.array(self.history_actions) if self.history_actions else np.array([]),
            'history_rewards': np.array(self.history_rewards) if self.history_rewards else np.array([]),
        }
        np.savez(filepath, **data)
    
    def load(self, filepath: str) -> None:
        """Load bandit state"""
        data                 = np.load(filepath + '.npz')
        self.arm_counts      = data['arm_counts']
        self.arm_rewards_sum = data['arm_rewards_sum']
        self.W               = data['W']
        self.total_pulls     = int(data['total_pulls'])
        self.history_states  = data['history_states'].tolist() if data['history_states'].size > 0 else []
        self.history_actions = data['history_actions'].tolist() if data['history_actions'].size > 0 else []
        self.history_rewards = data['history_rewards'].tolist() if data['history_rewards'].size > 0 else []
    
    def _solve_parameter(self) -> None:
        """Solve W matrix from scratch using all stored data"""
        if len(self.history_states) == 0:
            return
            
        # Initialize W with zeros
        self.W = np.zeros((self.n_arms, self.state_dim))
        
        # Calculate new q vector
        if self.train_flags[0]:
            self.q = self.arm_rewards_sum/(self.arm_counts+1e-5)
        
        # For each arm, solve W[arm] using least squares if we have enough data
        for arm in range(self.n_arms):
            # Find all instances where this arm was selected
            arm_indices = [i for i, a in enumerate(self.history_actions) if a == arm]
            
            if len(arm_indices) < 2:  # Need at least 2 points for least squares
                continue
                
            # Get states and rewards for this arm
            arm_states = np.array([self.history_states[i] for i in arm_indices])
            arm_rewards = np.array([self.history_rewards[i] for i in arm_indices])
            
            # Get base q-value for this arm
            q_base = self.q[arm]
            
            # Target for least squares: reward - q_base = W[arm] * state
            targets = arm_rewards - q_base
            
            # Solve least squares: W[arm] = (X^T X)^{-1} X^T y
            try:
                # Use pseudoinverse to handle rank-deficient cases
                if self.train_flags[1]:
                    self.W[arm] = np.linalg.pinv(arm_states.T @ arm_states) @ arm_states.T @ targets
            except:
                # If solve fails, keep W[arm] = 0
                print("Warning: Could not adapt the W matrix in Contextual Bandit")

    
    def set_flags(self,flag_vector):
        """
        This vector function decides which parts of the network need to be trained.
        
        flag_vector 2-dim numpy vector. flag_vector[0] is for the vector part of the Q-function, flag_vector[1] is for the matrix part (the context). It gets trained, if the value is larger than 0.
        """
        self.train_flags       = (np.array(flag_vector) > 0)
