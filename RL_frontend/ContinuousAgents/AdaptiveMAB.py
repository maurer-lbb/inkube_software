import numpy as np
from .BaseAgent import BaseAgent
from typing import Dict, Any, Optional

class AdaptiveMAB(BaseAgent):
    """
    Adaptive Joint Multi-Armed Bandit for continuous action spaces.

    Starts with 625 joint arms identical to discrete PureMAB (5 levels per
    electrode encoded as continuous values).  After every refine_interval
    steps the worst arms are replaced by samples drawn from a Gaussian
    fitted to the elite arms (CEM-style refinement), gradually moving
    from discrete to continuous resolution.
    """

    def __init__(self, 
                 state_dim:       int, 
                 action_dim:      int,
                 num_elec:        int = 4, 
                 discrete_levels: int = 5,
                 n_elite:         int = 125, 
                 n_replace:       int = 250,
                 refine_interval: int = 2_500):
                     
        super().__init__(state_dim, action_dim)
        
        self.num_elec        = num_elec
        self.discrete_levels = discrete_levels
        self.n_elite         = n_elite
        self.n_replace       = n_replace
        self.refine_interval = refine_interval
        self.alpha           = 0.5
        self.total_pulls     = 0
        self.n_refines       = 0

        # Initialize arms from discrete grid
        self.arm_actions     = self._init_discrete_grid(discrete_levels)
        self.n_arms          = len(self.arm_actions)
        self.arm_counts      = np.zeros(self.n_arms)
        self.arm_rewards_sum = np.random.random(self.n_arms) * 1e-20

        self._last_arm_idx = 0

    # ------------------------------------------------------------------
    # Initialisation
    # ------------------------------------------------------------------
    def _init_discrete_grid(self, levels):
        """Generate all joint actions from the discrete grid encoded as
        continuous values that produce the same latencies.

        Discrete level k:
            k = 0  ->  no stim  ->  a = -1
            k > 0  ->  a = (k-1)/(levels-2)   (clamped above 0.01)
        """
        arms = []
        for idx in range(levels ** self.num_elec):
            action    = np.zeros(self.num_elec)
            remaining = idx
            for i in range(self.num_elec):
                k = remaining % levels
                remaining //= levels
                if k == 0:
                    action[i] = -1.0
                else:
                    action[i] = max((k - 1) / (levels - 2), 0.01)
            arms.append(action)
        return np.array(arms)

    # ------------------------------------------------------------------
    # Action selection  (identical logic to discrete PureMAB)
    # ------------------------------------------------------------------
    def get_action(self, state: np.ndarray) -> np.ndarray:
        q                  = self.arm_rewards_sum / (self.arm_counts + 1e-5)
        explore            = self.alpha * np.sqrt(np.log(self.total_pulls + 1) / (self.arm_counts + 1e-10))
        total              =  q + explore
        self._last_arm_idx = int(np.argmax(total))
        return self.arm_actions[self._last_arm_idx].copy()

    def get_action_deterministic(self, state: np.ndarray) -> np.ndarray:
        q = self.arm_rewards_sum / (self.arm_counts + 1e-5)
        return self.arm_actions[int(np.argmax(q))].copy()

    # ------------------------------------------------------------------
    # Update  (identical logic to discrete PureMAB + periodic refinement)
    # ------------------------------------------------------------------
    def update(self, state: np.ndarray, action: np.ndarray, reward: float,
               next_state: Optional[np.ndarray] = None) -> None:
        self.iteration   += 1
        self.total_pulls += 1

        self.arm_rewards_sum[self._last_arm_idx] += reward
        self.arm_counts[self._last_arm_idx]      += 1

        if self.iteration % self.refine_interval == 0:
            self._refine()

    def _refine(self):
        """Replace worst arms with samples from the elite distribution."""
        q       = self.arm_rewards_sum / (self.arm_counts + 1e-5)
        ranking = np.argsort(q)

        # Fit Gaussian to elite arms
        elite_actions = self.arm_actions[ranking[-self.n_elite:]]
        mu            = np.mean(elite_actions, axis=0)
        C             = np.cov(elite_actions.T) + 1e-3 * np.eye(self.num_elec)

        # Sample new arms and clip to valid range
        new_actions = np.random.multivariate_normal(mu, C, size=self.n_replace)
        new_actions = np.clip(new_actions, -1.0, 1.0)

        # Replace worst arms (reset their statistics)
        worst_idx                       = ranking[:self.n_replace]
        self.arm_actions[worst_idx]     = new_actions
        self.arm_counts[worst_idx]      = 0
        self.arm_rewards_sum[worst_idx] = np.random.random(self.n_replace) * 1e-20

        # Remove phantom pulls from deleted arms
        self.total_pulls = int(np.sum(self.arm_counts))
        self.n_refines  += 1

    # ------------------------------------------------------------------
    # BaseAgent interface
    # ------------------------------------------------------------------
    def end_episode(self) -> None:
        pass

    def get_param_count(self) -> int:
        return self.n_arms

    def reset_params(self) -> None:
        self.arm_actions     = self._init_discrete_grid(self.discrete_levels)
        self.n_arms          = len(self.arm_actions)
        self.arm_counts      = np.zeros(self.n_arms)
        self.arm_rewards_sum = np.random.random(self.n_arms) * 1e-20
        self.total_pulls     = 0
        self.n_refines       = 0

    def get_params(self) -> np.ndarray:
        return self.arm_rewards_sum / (self.arm_counts + 1e-5)

    def set_params(self, params: np.ndarray) -> None:
        pass

    def should_update(self) -> bool:
        return True

    def get_stats(self) -> Dict[str, Any]:
        return {
            "iteration": self.iteration,
            "total_pulls": self.total_pulls,
            "n_refines": self.n_refines,
            "q-values": self.get_params(),
        }

    def is_converged(self) -> bool:
        min_pulls_per_arm = 10
        return np.min(self.arm_counts) >= min_pulls_per_arm

    def save(self, filepath: str) -> None:
        np.savez(filepath,
                 arm_actions=self.arm_actions,
                 arm_counts=self.arm_counts,
                 arm_rewards_sum=self.arm_rewards_sum,
                 total_pulls=self.total_pulls,
                 n_refines=self.n_refines,
                 iteration=self.iteration,
                 generation=self.generation)

    def load(self, filepath: str) -> None:
        data = np.load(filepath + '.npz')
        self.arm_actions     = data['arm_actions']
        self.arm_counts      = data['arm_counts']
        self.arm_rewards_sum = data['arm_rewards_sum']
        self.total_pulls     = int(data['total_pulls'])
        self.n_refines       = int(data['n_refines'])
        self.iteration       = int(data['iteration'])
        self.generation      = int(data['generation'])
        self.n_arms          = len(self.arm_actions)
