import numpy as np
from sklearn.decomposition import PCA

class DynamicStatePCA():
    """
    This is the state function used per default. For better performance, replace with your own state function
    """
    def __init__(self,state_dim,data_length=360,bin_size=18):
        """
        You can give the object parameters here. 
        state_dim       (int) number of dimensions you want your state space to have
        data_length     (int) data length in sample count of the response
        bin_size        (int) bin size in sample count 
        
        To get from sample count to time in ms, you need to approximately divide by 18
        """
        self.state_dim   = state_dim
        self.PCA         = PCA(n_components=self.state_dim)

        self.data_length = data_length
        self.bin_size    = bin_size
        self.num_bins    = data_length//bin_size + ((data_length%bin_size)>0)
        
        # Fit dummy data to initialize PCA
        self.PCA.fit(np.random.randn(max(4*self.num_bins,self.state_dim),4*self.num_bins))
        
    def fit(self,spikes,elecs):
        """
        This function is executed when creating a state characterization. Used only in dynamic state functions.
        """
        X = np.zeros((len(spikes),4*self.num_bins))
        
        for i in range(X.shape[0]):
            if len(spikes[i]) == 0:
                continue
            for j in range(spikes[i].shape[0]):
                if spikes[i][j] >= 0 and spikes[i][j] < self.data_length:
                    X[i,int(elecs[i][j]*self.num_bins+spikes[i][j]/self.bin_size)] = 1
                
        self.PCA.fit(X)
        
        return X
    
    def get_state(self,response):
        """
        This state function simply encodes the first n spikes and their relative timing.
        """
        X     = np.zeros(4*self.num_bins)
        state = np.zeros((1,4*self.num_bins))
        
        if response.shape[0] == 0:
            return self.PCA.transform(state)[0,:]
        
        # 0 is time 1 is elec
        
        for i in range(response.shape[0]):
                if response[i,0] >= 0 and response[i,0] < self.data_length:
                    state[0,int(response[i,1]*self.num_bins+response[i,0]/self.bin_size)] = 1
        
        return self.PCA.transform(state)[0,:]
    
