import numpy as np

class StaticStateDownsampled():
    """
    This is the state function used per default. For better performance, replace with your own state function
    """
    def __init__(self,state_dim,bin_size=18):
        """
        You can give the object parameters here. 
        state_dim       (int) number of dimensions you want your state space to have
        bin_size        (int) number of samples in each bin (18 is approx. 1ms)
        
        state_dim should be divisible by 4, otherwise the data is being ignored
        """
        self.state_dim  = state_dim
        self.bin_size   = bin_size
        
        # Actual number of bins (is a number divisable by 4)
        self.actual_dim = (state_dim//4)
        
    def fit(self):
        """
        This function is executed when creating a state characterization. Used only in dynamic state functions.
        """
        pass
    
    def get_state(self,response):
        """
        This state function simply encodes the first n spikes and their relative timing.
        """        
        state    = np.zeros(self.state_dim)
        
        if response.shape[0] == 0:
            return state
        
        for i in range(response.shape[0]):
            elec = int(response[i,1]+0.5)
            t    = response[i,0]
            
            if t >= self.bin_size * self.actual_dim or t < 0:
                continue
            
            state[elec*self.actual_dim+int(t/self.bin_size)] += 1
        
        return state
    
