from abc import ABC, abstractmethod
import numpy as np
from typing import Dict, Any, Optional, Tuple


class BaseAgent(ABC):
    def __init__(self, state_dim: int, action_dim: int, **kwargs):
        self.state_dim = state_dim
        self.action_dim = action_dim
        self.generation = 0
        self.iteration = 0
    
    @abstractmethod
    def get_action(self, state: np.ndarray) -> np.ndarray:
        pass
    
    @abstractmethod
    def get_action_deterministic(self, state: np.ndarray) -> np.ndarray:
        pass
    
    @abstractmethod
    def update(self, state: np.ndarray, action: np.ndarray, reward: float, 
               next_state: Optional[np.ndarray] = None) -> None:
        pass
    
    @abstractmethod
    def end_episode(self) -> None:
        pass
    
    @abstractmethod
    def get_param_count(self) -> int:
        pass
    
    @abstractmethod
    def reset_params(self) -> None:
        pass
    
    @abstractmethod
    def get_params(self) -> np.ndarray:
        pass
    
    @abstractmethod
    def set_params(self, params: np.ndarray) -> None:
        pass
    
    @abstractmethod
    def should_update(self) -> bool:
        pass
    
    @abstractmethod
    def get_stats(self) -> Dict[str, Any]:
        pass
    
    @abstractmethod
    def is_converged(self) -> bool:
        pass
    
    @abstractmethod
    def save(self, filepath: str) -> None:
        pass
    
    @abstractmethod
    def load(self, filepath: str) -> None:
        pass
    
    def get_generation(self) -> int:
        return self.generation
    
    def get_iteration(self) -> int:
        return self.iteration