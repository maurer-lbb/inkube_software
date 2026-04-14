import numpy as np
from .BaseAgent import BaseAgent
from typing import Dict, Any, Optional

class LinearContextualBandits(BaseAgent):
    """
    Thompson Sampling for Linear Contextual Bandits with continuous actions.

    Models reward as linear in state-action features:
        r ≈ θᵀ φ(s, a)
    where:
        φ(s, a) = [s; a; a²; vec(s ⊗ a); 1]

    The feature design ensures:
    - Quadratic action terms (a²) allow interior optima, not just ±1.
    - State-action interactions (s ⊗ a) make the optimal action state-dependent.
    - State and bias terms improve the regression fit.

    The reward decomposes per action dimension (no aᵢ·aⱼ cross-terms):
        r̂ = const(s) + Σᵢ [(θ_lᵢ + wᵢᵀs)·aᵢ + θ_qᵢ·aᵢ²]
    so each aᵢ can be optimized independently via closed-form solution.

    Posterior: θ | data ~ N(A⁻¹b, σ² A⁻¹)
      where A = λI + Σₜ φₜφₜᵀ   (precision matrix)
            b = Σₜ rₜ φₜ          (reward-weighted feature sum)

    Action selection via Thompson Sampling:
        1. Sample θ̃ ~ N(posterior_mean, σ² · posterior_cov)
        2. For each action dim i, solve analytically:
           a*ᵢ = clip(-(θ̃_lᵢ + w̃ᵢᵀs) / (2θ̃_qᵢ), -1, 1)  when θ̃_qᵢ < 0
    """

    def __init__(self, state_dim: int, action_dim: int,
                 lambda_reg: float = 1.0, noise_var: float = 1.0):
        super().__init__(state_dim, action_dim)

        self.lambda_reg = lambda_reg
        self.noise_var  = noise_var

        # Feature layout: [s; a; a²; vec(s⊗a); 1]
        # Dimensions:      ns  na  na   ns*na    1
        self.feat_dim = state_dim + 2 * action_dim + state_dim * action_dim + 1

        # Index slices for extracting coefficient groups from θ
        ns, na       = state_dim, action_dim
        self._idx_s  = slice(0, ns)
        self._idx_a  = slice(ns, ns + na)
        self._idx_a2 = slice(ns + na, ns + 2 * na)
        self._idx_sa = slice(ns + 2 * na, ns + 2 * na + ns * na)
        # bias is at index feat_dim - 1

        # Sufficient statistics for Bayesian linear regression (This is were we save the data)
        self.A = lambda_reg * np.eye(self.feat_dim)
        self.b = np.zeros(self.feat_dim)

        # Posterior (derived from A, b)
        self.posterior_cov  = (1.0 / lambda_reg) * np.eye(self.feat_dim) # Is A^-1
        self.posterior_mean = np.zeros(self.feat_dim)                    # A^-1 * b (with b=0)

        # Thompson-sampled parameters
        self.current_params = np.zeros(self.feat_dim)
        self._sample_parameters()

        self.total_updates  = 0

    def _build_features(self, state: np.ndarray, action: np.ndarray) -> np.ndarray:
        """Build feature vector φ(s, a) = [s; a; a²; vec(s⊗a); 1]."""
        return np.concatenate([
            state,
            action,
            action ** 2,
            np.outer(state, action).ravel(),
            [1.0]
        ])

    def _sample_parameters(self):
        """Sample parameters from posterior for Thompson Sampling."""
        self.current_params = np.random.multivariate_normal(
            self.posterior_mean,
            self.noise_var * self.posterior_cov
        )

    def _recompute_posterior(self):
        """Recompute posterior_cov and posterior_mean from sufficient statistics."""
        self.posterior_cov = np.linalg.inv(self.A)
        self.posterior_mean = self.posterior_cov @ self.b

    def _optimal_action(self, state: np.ndarray, theta: np.ndarray) -> np.ndarray:
        """
        Find the action maximizing θᵀφ(s, a).

        The reward model decomposes per action dimension:
            r̂ = const(s) + Σᵢ [(θ_lᵢ + wᵢᵀs)·aᵢ + θ_qᵢ·aᵢ²]
        Each aᵢ is optimized independently via calculus.
        """
        theta_l = theta[self._idx_a]   # linear action coefficients
        theta_q = theta[self._idx_a2]  # quadratic action coefficients
        # W[j, i] is the coefficient for sⱼ·aᵢ
        W = theta[self._idx_sa].reshape(self.state_dim, self.action_dim)

        action = np.zeros(self.action_dim)
        for i in range(self.action_dim):
            lin = theta_l[i] + W[:, i] @ state
            quad = theta_q[i]

            if quad < -1e-8:
                # Concave in aᵢ → interior maximum exists
                action[i] = np.clip(-lin / (2.0 * quad), -1.0, 1.0)
            else:
                # Convex or flat → optimum at one of the boundaries
                # f(a) = lin·a + quad·a²  →  f(±1) = ±lin + quad
                action[i] = 1.0 if lin >= 0.0 else -1.0

        return action

    def get_action(self, state: np.ndarray) -> np.ndarray:
        """Thompson Sampling: sample θ̃ from posterior, return optimal action."""
        self._sample_parameters()
        return self._optimal_action(state, self.current_params)

    def get_action_deterministic(self, state: np.ndarray) -> np.ndarray:
        """Deterministic action using posterior mean parameters."""
        return self._optimal_action(state, self.posterior_mean)

    def update(self, state: np.ndarray, action: np.ndarray, reward: float,
               next_state: Optional[np.ndarray] = None) -> None:
        """
        Bayesian update: observe (s, a, r), update sufficient statistics.

            φ = φ(s, a)
            A += φ φᵀ
            b += r · φ
        """
        self.iteration += 1
        self.total_updates += 1

        phi = self._build_features(state, action)
        self.A += np.outer(phi, phi)
        self.b += reward * phi

        self._recompute_posterior()

    def end_episode(self) -> None:
        """Called at episode end."""
        self.generation += 1

    def get_param_count(self) -> int:
        """Number of learnable coefficients in the reward model."""
        return self.feat_dim

    def reset_params(self) -> None:
        """Reset to prior."""
        self.A = self.lambda_reg * np.eye(self.feat_dim)
        self.b = np.zeros(self.feat_dim)
        self.posterior_cov = (1.0 / self.lambda_reg) * np.eye(self.feat_dim)
        self.posterior_mean = np.zeros(self.feat_dim)
        self._sample_parameters()
        self.total_updates = 0

    def get_params(self) -> np.ndarray:
        """Return posterior mean as flat array."""
        return self.posterior_mean.copy()

    def set_params(self, params: np.ndarray) -> None:
        """Set posterior mean from flat array; reset sufficient statistics to prior."""
        self.posterior_mean = params.copy()
        self.A = self.lambda_reg * np.eye(self.feat_dim)
        self.b = np.zeros(self.feat_dim)
        self.posterior_cov = (1.0 / self.lambda_reg) * np.eye(self.feat_dim)
        self._sample_parameters()

    def should_update(self) -> bool:
        """Always update (online learning)."""
        return True

    def get_stats(self) -> Dict[str, Any]:
        """Return training statistics."""
        return {
            "iteration": self.iteration,
            "generation": self.generation,
            "total_updates": self.total_updates,
            "posterior_mean_norm": float(np.linalg.norm(self.posterior_mean)),
            "avg_posterior_var": float(np.trace(self.posterior_cov) / self.feat_dim),
            "feat_dim": self.feat_dim,
        }

    def is_converged(self) -> bool:
        """Check if posterior has converged (low variance)."""
        avg_var = np.trace(self.posterior_cov) / self.feat_dim
        return avg_var < 0.01

    def save(self, filepath: str) -> None:
        """Save agent state (sufficient statistics + derived quantities)."""
        np.savez(filepath,
                 A=self.A,
                 b=self.b,
                 posterior_mean=self.posterior_mean,
                 posterior_cov=self.posterior_cov,
                 current_params=self.current_params,
                 total_updates=self.total_updates,
                 iteration=self.iteration,
                 generation=self.generation)

    def load(self, filepath: str) -> None:
        """Load agent state."""
        data = np.load(filepath + '.npz')
        self.A = data['A']
        self.b = data['b']
        self.posterior_mean = data['posterior_mean']
        self.posterior_cov = data['posterior_cov']
        self.current_params = data['current_params']
        self.total_updates = int(data['total_updates'])
        self.iteration = int(data['iteration'])
        self.generation = int(data['generation'])
