import numpy as np

class Electrode_mapping:
    """
    Class representing the mapping between electrodes, MEAs, networks and the channels in the UDP package.
    """
    def __init__(
            self,
            mea_layouts,
            mask_layouts,
            n=4,
            elec=60
        ):
        """__init__(mea_layouts, mask_layouts, n=4, elec=60): Initializes the Electrode_mapping object.  """
        if len(mea_layouts) != n:
            raise RuntimeError(f"Number of mea layouts ({len(mea_layouts)}) is not the same as the number of MEAs ({n}) that was set")
        if len(mask_layouts) != n:
            raise RuntimeError(f"Number of mask layouts ({len(mask_layouts)}) is not the same as the number of MEAs ({n}) that was set")
        
        self.n                = n
        self.elec             = elec
        self.mea_layouts      = mea_layouts
        self.mask_layouts     = mask_layouts
        
        self.circuit_sizes       = []
        self.circuit_elec_ids    = []
        
        # Get mapping from mea 2 fpga
        self.mapping_mea2fpga    = np.zeros(self.n*self.elec,dtype=int)
        self.transform           = []
        self.mea_elec_ids        = []
        for i in range(self.n):
            # Set the correct MEA layout
            if mea_layouts[i] == "10x6":
                self.transform.append(lambda x: (x//10)+(x%10)*6)
                self.mea_elec_ids.append([ 7, 9,12,46,49,51,
                                           6,10,11,47,48,52,
                                           4, 8,13,45,50,54,
                                           2, 3, 5,53,55,56,
                                          14, 0, 1,57,58,59,
                                          29,28,27,32,31,30,
                                          26,25,23,36,34,33,
                                          24,20,15,44,39,35,
                                          22,18,17,42,41,37,
                                          21,19,16,43,40,38])
                assert self.elec == len(self.mea_elec_ids[-1]) # If this throws an error, then the number of elec per MEA does not fit the mea layout
                for j in range(self.elec):
                    mea   = i
                    index = self.mea_elec_ids[-1][j]
                    self.mapping_mea2fpga[i*self.elec+j] = mea*60+index
                
            elif mea_layouts[i] == "6x10":
                raise RuntimeError(f"MEA layout 6x10 is not implemented yet")
            
            elif mea_layouts[i] == "channels":
                self.transform.append(lambda x: x)
                self.mea_elec_ids.append(np.arange(60))
                for j in range(self.elec):
                    mea   = i
                    index = self.mea_elec_ids[-1][j]
                    self.mapping_mea2fpga[i*self.elec+j] = mea*60+index

            elif mea_layouts[i] == "8x8":
                self.transform.append(lambda x: x)
                self.mea_elec_ids.append([12, 46, 49, 51,  6, 10,  7, 56, 
                                           8, 13, 45, 50,  1, 47, 48,  4, 
                                           9, 14,  0, 11, 54,  3,  5, 55, 
                                           53, 52,  2, 58, 57, 59, 29, 27, 
                                           28, 33, 22, 23, 25, 36, 34, 24, 
                                           42, 31, 30, 40, 35, 18, 17, 32, 
                                           20, 15, 44, 39, 26, 38, 41, 37, 
                                           21, 19, 16, 43])
                assert self.elec == len(self.mea_elec_ids[-1]) # If this throws an error, then the number of elec per MEA does not fit the mea layout
                for j in range(self.elec):
                    mea   = i
                    index = self.mea_elec_ids[-1][j]
                    self.mapping_mea2fpga[i*self.elec+j] = mea*60+index
                
                
            else:
                raise RuntimeError(f"MEA layout ({mea_layouts[i]}) is unknown")
        
        # Get inverted mapping
        self.mapping_fpga2mea    = np.argsort(self.mapping_mea2fpga)
        
        # Mapping from mea to network
        self.mapping_mea2network = np.zeros((self.n*self.elec,2),dtype=int)
        self.mapping_network2mea = []
        for i in range(self.n):
            offset = len(self.circuit_sizes)
            
            # Set the correct mask layout
            if mask_layouts[i] == "5x3 o circle":
                net = [[ 1,11,10, 0],
                       [21,31,30,20],
                       [41,51,50,40],
                       [ 3,13,12, 2],
                       [23,33,32,22],
                       [43,53,52,42],
                       [ 5,15,14, 4],
                       [25,35,34,24],
                       [45,55,54,44],
                       [ 7,17,16, 6],
                       [27,37,36,26],
                       [47,57,56,46],
                       [ 9,19,18, 8],
                       [29,39,38,28],
                       [49,59,58,48]]
                for j in range(15):
                    self.mapping_network2mea.append([self.transform[i](k)+self.elec*i for k in net[j]])
                    self.circuit_sizes.append(4)
                    for k in range(4):
                        index = self.transform[i](net[j][k])+self.elec*i
                        self.mapping_mea2network[index,0] = j + offset
                        self.mapping_mea2network[index,1] = k
                        
            elif mask_layouts[i] == "No structure":
                net = [[0,10,20,30,40,50,
                        1,11,21,31,41,51,
                        2,12,22,32,42,52,
                        3,13,23,33,43,53,
                        4,14,24,34,44,54,
                        5,15,25,35,45,55,
                        6,16,26,36,46,56,
                        7,17,27,37,47,57,
                        8,18,28,38,48,58,
                        9,19,29,39,49,59]]
                self.circuit_sizes.append(60)
                self.mapping_network2mea.append([self.transform[i](k)+self.elec*i for k in net[0]])
                for k in range(60):
                    index = self.transform[i](net[0][k])+self.elec*i
                    self.mapping_mea2network[index,0] = 0 + offset
                    self.mapping_mea2network[index,1] = k
                
            elif mask_layouts[i] == "By chip":
                net = np.reshape(np.arange(60), (4,15))
                for j in range(4):
                    self.mapping_network2mea.append([self.transform[i](k)+self.elec*i for k in net[j]])
                    self.circuit_sizes.append(15)
                    for k in range(15):
                        index = self.transform[i](net[j][k])+self.elec*i
                        self.mapping_mea2network[index,0] = j + offset
                        self.mapping_mea2network[index,1] = k

            else:
                raise RuntimeError(f"MEA layout ({mea_layouts[i]}) is unknown")
                
        self.mapping_mea2recv = self.get_id_from_source(self.mapping_mea2fpga//60,(self.mapping_mea2fpga%60)//15,self.mapping_mea2fpga%15)
        self.mapping_recv2mea = np.argsort(self.mapping_mea2recv)
        self.mapping_recv2network = self.mapping_mea2network[self.mapping_recv2mea]

    def mea2recv(self,ids=None):
        """mea2recv(ids=None): Returns the mapping from MCS MEA layout to the received UDP package."""
        if np.isscalar(ids):
            ids = [ids]
        if ids is None:
            return self.mapping_mea2recv
        else:
            return self.mapping_mea2recv[ids]

    def recv2mea(self,ids=None):
        """recv2mea(ids=None): inverse of mea2recv."""

        if np.isscalar(ids):
            ids = [ids]
        if ids is None:
            return self.mapping_recv2mea
        else:
            return self.mapping_recv2mea[ids]
        
    def mea2stim(self,ids=None):
        """ mea2stim(ids=None): Returns the mapping from MCS MEA layout to the chips for stimulation. """

        if np.isscalar(ids):
            ids = [ids]
        if ids is None:
            return self.mapping_mea2fpga
        else:
            return self.mapping_mea2fpga[ids]

    def stim2mea(self,ids=None):
        """stim2mea(ids=None): inverse of mea2stim."""


        if np.isscalar(ids):
            ids = [ids]
        if ids is None:
            return self.mapping_fpga2mea
        else:
            return self.mapping_fpga2mea[ids]
        
    def mea2network(self,ids=None):
        """mea2network(ids=None): Returns the mapping from MEAs to networks."""


        if np.isscalar(ids):
            ids = [ids]
        if ids is None:
            return self.mapping_mea2network[:,0],self.mapping_mea2network[:,1]
        else:
            return self.mapping_mea2network[ids,0],self.mapping_mea2network[ids,1]
    
    def network2mea(self,mapping):
        """network2mea(mapping): Returns the mapping from networks with microstructure to MCS MEA layout."""


        return [self.mapping_network2mea[mapping[ele,0]][mapping[ele,1]] for ele in range(mapping.shape[0])]
        
    
    def get_id_from_source(self,mea,chip,el):
        """
        get_id_from_source(mea, chip, el): Returns the ID in the stimulation package sent via USB based on the given MEA, chip, and electrode.
        """
        return mea*4 + (el%15)*16 + chip
    
    
if __name__ == '__main__':
    mea_layouts       = ["8x8", "8x8","8x8", "8x8"]
    mask_layouts      = ["No structure", "No structure","No structure", "No structure"]
    ELECTRODE_MAPPING = Electrode_mapping(mea_layouts,mask_layouts)
    SI_id = 0
    print(ELECTRODE_MAPPING.mapping_mea2fpga[SI_id])
    print(ELECTRODE_MAPPING.mapping_mea2fpga[:60])
    mea_mapping = np.array([ELECTRODE_MAPPING.mea2recv(range(i*60, (i+1)*60)) for i in range(4)])
    print(mea_mapping.shape)