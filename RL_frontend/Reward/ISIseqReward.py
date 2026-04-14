import numpy as np

class ISIseqReward:
    """
    Reward based on the longest valid circular sequence.
    More robust to spontaneous activity than counting all pairs.
    """
    def __init__(self, min_ms = 0.5, max_ms = 5.0):        
        self.min_isi = int(min_ms * 17.361)  # 0.5ms in samples
        self.max_isi = int(max_ms * 17.361)  # 5ms in samples
    
    def reward(self, response):
        """
        Find the longest circular sequence starting from any electrode.
        """
        if response.shape[0] == 0:
            return 0
        
        # Get first spike on each electrode (vectorised)
        unique_elecs = np.unique(response[:, 1])
        first_spike_indices = {}
        first_spike_times = {}
        
        for elec in unique_elecs:
            idx = np.where(response[:, 1] == elec)[0][0]
            first_spike_indices[elec] = idx
            first_spike_times[elec] = response[idx, 0]
        
        # Try each electrode as start
        max_length = 0
        
        for start_elec in unique_elecs:
            length = self._find_sequence_length(response, start_elec, 
                                               first_spike_times[start_elec])
            max_length = max(max_length, length)
        
        return max_length
    
    def _find_sequence_length(self, response, start_elec, start_time):
        """
        Find sequence length starting from given electrode and time.
        Continues until no valid next spike is found.
        """
        current_elec = start_elec
        current_time = start_time
        length = 1
        
        # Pre-compute masks for each electrode
        elec_masks = [response[:, 1] == i for i in range(4)]
        elec_times = [response[mask, 0] for mask in elec_masks]
        
        while True:  # Continue until we can't find a valid next spike
            next_elec = (current_elec + 1) % 4
            
            # Vectorised search for valid next spike
            next_times = elec_times[next_elec]
            time_diffs = next_times - current_time
            
            valid_mask = (time_diffs >= self.min_isi) & (time_diffs <= self.max_isi)
            
            if not np.any(valid_mask):
                break
            
            # Take first valid spike
            valid_times = next_times[valid_mask]
            current_time = valid_times[0]
            current_elec = next_elec
            length += 1
        
        return length