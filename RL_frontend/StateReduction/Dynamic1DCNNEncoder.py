import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
import torch.nn.functional as F


class Temporal1DCNN(nn.Module):
    """
    Ultra-lightweight 1D CNN for temporal spike pattern recognition.
    Uses dilated convolutions and depthwise separable convolutions to 
    minimize parameters while capturing multi-scale temporal patterns.
    """
    def __init__(self, input_dim, output_dim):
        super().__init__()
        
        self.input_dim = input_dim
        self.output_dim = output_dim
        
        # Extremely parameter-efficient architecture
        # Input: (batch_size, max_spikes, 5) -> (batch_size, 5, max_spikes) for 1D conv
        
        # Depthwise separable conv layer 1: captures local temporal patterns
        self.depthwise1 = nn.Conv1d(5, 5, kernel_size=3, padding=1, groups=5)  # 5*3 = 15 params
        self.pointwise1 = nn.Conv1d(5, 4, kernel_size=1)  # 5*4 = 20 params
        
        # Dilated conv layer: captures longer-range temporal dependencies  
        self.dilated_conv = nn.Conv1d(4, 4, kernel_size=3, padding=2, dilation=2, groups=4)  # 4*3 = 12 params
        
        # Final pointwise conv to compress features
        self.pointwise2 = nn.Conv1d(4, 2, kernel_size=1)  # 4*2 = 8 params
        
        # Global pooling (no parameters)
        self.global_pool = nn.AdaptiveAvgPool1d(1)
        
        # Final linear layer to target dimension
        self.fc_out = nn.Linear(2, output_dim)  # 2*output_dim + output_dim params
        
        # Batch normalization for stability (minimal params)
        self.bn1 = nn.BatchNorm1d(4)  # 4*2 = 8 params
        self.bn2 = nn.BatchNorm1d(2)  # 2*2 = 4 params
        
        # Count total parameters
        total_params = sum(p.numel() for p in self.parameters() if p.requires_grad)
        print(f"Total trainable parameters: {total_params}")
        
    def forward(self, x, lengths):
        """
        x: (batch_size, max_spikes, 5)
        lengths: (batch_size,) - actual sequence lengths
        """
        batch_size, max_spikes, _ = x.shape
        
        # Transpose for 1D conv: (batch_size, 5, max_spikes)
        x = x.transpose(1, 2)
        
        # Create mask for padding positions
        device = x.device
        mask = torch.arange(max_spikes, device=device).expand(batch_size, max_spikes) < lengths.unsqueeze(1)
        mask = mask.unsqueeze(1).float()  # (batch_size, 1, max_spikes)
        
        # Apply mask to input
        x = x * mask
        
        # Depthwise separable conv block 1
        x = self.depthwise1(x)
        x = self.pointwise1(x)
        x = self.bn1(x)
        x = F.relu(x)
        
        # Apply mask after conv
        x = x * mask[:, :1, :]  # Broadcast to 4 channels
        
        # Dilated conv for long-range dependencies
        x = self.dilated_conv(x)
        x = F.relu(x)
        
        # Final compression
        x = self.pointwise2(x)
        x = self.bn2(x)
        x = F.relu(x)
        
        # Apply final mask
        x = x * mask[:, :1, :]  # Broadcast to 2 channels
        
        # Global average pooling
        x = self.global_pool(x)  # (batch_size, 2, 1)
        x = x.squeeze(-1)  # (batch_size, 2)
        
        # Final linear transformation
        x = self.fc_out(x)
        x = torch.tanh(x)  # Normalize to [-1, 1]
        
        return x


class PairwiseRepulsionLoss(nn.Module):
    """
    Loss function that maximizes pairwise distances between state representations
    to ensure distinct states for different spike patterns.
    """
    def __init__(self, eps=1e-8):
        super().__init__()
        self.eps = eps
        
    def forward(self, X):
        """X: (batch_size, state_dim)"""
        # Compute pairwise L2 distances
        D = torch.cdist(X, X, p=2)
        
        # Mask diagonal (self-distances)
        batch_size = X.size(0)
        mask = ~torch.eye(batch_size, dtype=bool, device=X.device)
        
        if mask.sum() > 0:
            mean_dist = D[mask].mean()
        else:
            mean_dist = torch.tensor(0.0, device=X.device)
            
        # Negative because we want to maximize distance
        return -mean_dist


class Dynamic1DCNNEncoder:
    """
    1D Temporal Convolutional Neural Network for neural spike data state reduction.
    
    Uses ultra-lightweight 1D convolutions with dilated kernels to capture
    temporal patterns in spike sequences while maintaining <300 parameters.
    """
    
    def __init__(self, state_dim):
        """
        Initialize the 1D CNN encoder.
        
        Args:
            state_dim (int): Dimension of the target state space
        """
        self.state_dim = state_dim
        self.max_spikes = 30  # Maximum number of spikes to consider
        
        # Create the network
        self.net = Temporal1DCNN(input_dim=self.max_spikes, output_dim=self.state_dim)
        
        # Print parameter count
        total_params = sum(p.numel() for p in self.net.parameters() if p.requires_grad)
        print(f"Dynamic1DCNNEncoder initialized with {total_params} trainable parameters")
        
    def response2torch(self, response):
        """
        Convert response data to torch format.
        
        Args:
            response: numpy array of shape (n_spikes, 2) where 
                     col 0 = spike times, col 1 = electrode IDs (0-3)
                     
        Returns:
            tuple: (tensor, length) where tensor is (1, max_spikes, 5) and
                   length is actual number of spikes
        """
        # Initialize tensor: (1, max_spikes, 5)
        # Columns 0-3: one-hot electrode encoding
        # Column 4: sqrt(spike_time)
        t = torch.zeros((1, self.max_spikes, 5))
        
        k = min(self.max_spikes, response.shape[0])
        
        for i in range(k):
            # One-hot encoding for electrode (columns 0-3)
            electrode_id = int(response[i, 1])
            if 0 <= electrode_id <= 3:
                t[0, i, electrode_id] = 1
            
            # Square root of spike time (column 4)
            t[0, i, 4] = np.sqrt(max(0, response[i, 0]))
        
        # Convert to float tensor
        t = t.float()
        k = torch.tensor([k], dtype=torch.long)
        
        return t, k
        
    def fit(self, responses, flag=False, actions=None):
        """
        Train the 1D CNN encoder on spike response data.
        
        Args:
            responses: Array of response data, where responses[i] is numpy array
                      of shape (n_spikes, 2)
            flag: If True, also train to predict actions (not implemented)
            actions: Action labels (not used in this version)
        """
        # Convert all responses to torch format
        data = torch.zeros((len(responses), self.max_spikes, 5)).float()
        lengths = torch.zeros(len(responses), dtype=torch.long)
        
        for i in range(len(responses)):
            t, k = self.response2torch(responses[i])
            data[i] = t[0]
            lengths[i] = k[0]
        
        # Training setup
        criterion = PairwiseRepulsionLoss()
        optimizer = optim.Adam(self.net.parameters(), lr=0.001)
        
        # Training parameters
        max_epochs = 200
        target_loss_threshold = -1.0  # Adjust based on state_dim if needed
        
        self.net.train()
        
        for epoch in range(max_epochs):
            optimizer.zero_grad()
            
            # Forward pass
            states = self.net(data, lengths)
            loss = criterion(states)
            
            # Backward pass
            loss.backward()
            optimizer.step()
            
            # Check convergence
            loss_val = loss.item()
            if epoch % 50 == 0:
                print(f"Epoch {epoch}, Loss: {loss_val:.4f}")
                
            if loss_val < target_loss_threshold:
                print(f"Converged at epoch {epoch} with loss {loss_val:.4f}")
                break
        
        print(f"Training completed. Final loss: {loss_val:.4f}")
        
    def get_state(self, response):
        """
        Get state representation for a single response.
        
        Args:
            response: numpy array of shape (n_spikes, 2) where
                     col 0 = spike times, col 1 = electrode IDs (0-3)
                     
        Returns:
            numpy array: State representation of shape (state_dim,)
        """
        self.net.eval()
        
        with torch.no_grad():
            t, k = self.response2torch(response)
            state = self.net(t, k)
            
        return state.numpy().flatten()