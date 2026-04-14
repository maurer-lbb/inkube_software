import numpy as np
from .BaseAgent import BaseAgent


class DummyAgent(BaseAgent):
    def __init__(self, state_dim: int, action_dim: int):
        super().__init__(state_dim, action_dim)
        self.params = np.zeros(state_dim * action_dim)
        
    def get_action(self, state: np.ndarray) -> np.ndarray:
        return np.random.uniform(-1, 1, self.action_dim)
    
    def get_action_deterministic(self, state: np.ndarray) -> np.ndarray:
        return np.zeros(self.action_dim)
    
    def update(self, state, action, reward, next_state=None):
        self.iteration += 1
        
    def end_episode(self):
        self.generation += 1
        
    def get_param_count(self):
        return len(self.params)
    
    def reset_params(self):
        self.params = np.random.randn(self.state_dim * self.action_dim)
        
    def get_params(self):
        return self.params.copy()
    
    def set_params(self, params):
        self.params = params.copy()
        
    def should_update(self):
        return True
    
    def get_stats(self):
        return {"iteration": self.iteration, "generation": self.generation}
    
    def is_converged(self):
        return False
    
    def save(self, filepath):
        np.save(filepath, self.params)
        
    def load(self, filepath):
        self.params = np.load(filepath)