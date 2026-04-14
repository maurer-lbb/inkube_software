#!/usr/bin/env python3
"""
ZMQ Data Logger - Subscribes to raw neural data and saves to HDF5
Run this in parallel with your main acquisition/plotting code.
"""

import zmq
import numpy as np
import h5py
import time
from pathlib import Path
from datetime import datetime
from Client_config import LSB_HG

# ============================================================================
# CONFIGURATION - Adjust these to match your setup
# ============================================================================
ZMQ_PLOT_SOCKET = "tcp://localhost:6001"
CHANNELS = 240
EXTERNAL_PLOT_CHUNK_LENGTH = 128
FS = 17_361  # Sampling frequency in Hz

# HDF5 settings
BUFFER_SIZE = 100  # Number of chunks to buffer before flushing
H5_CHUNK_SIZE = 1000  # HDF5 chunking for compression
OUTPUT_DIR = Path("./data_recordings")

# ============================================================================
# MAIN LOGGER CLASS
# ============================================================================
class ZMQDataLogger:
    def __init__(self, output_filename=None):
        # Generate filename if not provided
        if output_filename is None:
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            output_filename = OUTPUT_DIR / f"raw_traces_{timestamp}.h5"
        
        OUTPUT_DIR.mkdir(exist_ok=True)
        self.h5_filename = output_filename
        
        # Initialize ZMQ
        self.context = zmq.Context.instance()
        self.socket = self.context.socket(zmq.SUB)
        self.socket.connect(ZMQ_PLOT_SOCKET)
        self.socket.setsockopt(zmq.SUBSCRIBE, b"")
        print(f"✓ Connected to ZMQ at {ZMQ_PLOT_SOCKET}")

        self.poller = zmq.Poller()
        self.poller.register(self.socket, zmq.POLLIN)
        
        # Buffers for efficient batch writing
        self.voltage_buffer = []
        self.signal_buffer = []
        self.package_id_buffer = []
        self.timestamp_buffer = []
        
        # Track recording times
        self.recording_start_time = time.time()
        
        # Initialize HDF5 file
        self._init_h5_file()
        
        print(f"✓ Logging to: {self.h5_filename}")
        print(f"✓ Buffer size: {BUFFER_SIZE} chunks")
        print("✓ Press Ctrl+C to stop\n")
    
    def _init_h5_file(self):
        """Initialize HDF5 file with resizable datasets"""
        with h5py.File(self.h5_filename, "w") as h5file:
            # Create datasets with chunking and compression
            # Shape: (n_samples, CHANNELS) - flattened time dimension
            h5file.create_dataset(
                "voltage_stream",
                shape=(0, CHANNELS),
                maxshape=(None, CHANNELS),
                dtype=np.float32,
                chunks=(H5_CHUNK_SIZE, CHANNELS),
                compression="gzip",
                compression_opts=4
            )
            
            h5file.create_dataset(
                "signal_stream",
                shape=(0, CHANNELS),
                maxshape=(None, CHANNELS),
                dtype=np.float32,
                chunks=(H5_CHUNK_SIZE, CHANNELS),
                compression="gzip",
                compression_opts=4
            )
            
            h5file.create_dataset(
                "package_ids",
                shape=(0,),
                maxshape=(None,),
                dtype=np.int64,
                chunks=(H5_CHUNK_SIZE,)
            )
            
            h5file.create_dataset(
                "timestamps",
                shape=(0,),
                maxshape=(None,),
                dtype=np.float64,
                chunks=(H5_CHUNK_SIZE,)
            )
            
            # Store metadata
            h5file.attrs["channels"] = CHANNELS
            h5file.attrs["chunk_length"] = EXTERNAL_PLOT_CHUNK_LENGTH
            h5file.attrs["sampling_frequency_hz"] = FS
            h5file.attrs["file_creation_time"] = time.time()
            h5file.attrs["file_creation_time_iso"] = datetime.now().isoformat()
            h5file.attrs["recording_start_time"] = self.recording_start_time
            h5file.attrs["recording_start_time_iso"] = datetime.fromtimestamp(self.recording_start_time).isoformat()
    
    def _flush_to_disk(self):
        """Efficiently write buffered data to HDF5"""
        if not self.voltage_buffer:
            return
        
        n_chunks = len(self.voltage_buffer)
        
        # Flatten chunks: from list of (CHANNELS, CHUNK_LEN) to (n_chunks*CHUNK_LEN, CHANNELS)
        # Transpose each chunk from (CHANNELS, CHUNK_LEN) to (CHUNK_LEN, CHANNELS) then stack
        voltage_flat = np.vstack([chunk.T for chunk in self.voltage_buffer])  # Shape: (n_samples, CHANNELS)
        signal_flat = np.vstack([chunk.T for chunk in self.signal_buffer])    # Shape: (n_samples, CHANNELS)
        
        n_samples = voltage_flat.shape[0]
        
        with h5py.File(self.h5_filename, "a") as h5file:
            # Get current size
            current_size = h5file["voltage_stream"].shape[0]
            new_size = current_size + n_samples
            
            # Resize all datasets
            h5file["voltage_stream"].resize((new_size, CHANNELS))
            h5file["signal_stream"].resize((new_size, CHANNELS))
            h5file["package_ids"].resize((current_size + n_chunks,))
            h5file["timestamps"].resize((current_size + n_chunks,))
            
            # Write buffered data in one shot
            h5file["voltage_stream"][current_size:new_size] = voltage_flat*LSB_HG
            h5file["signal_stream"][current_size:new_size] = signal_flat*LSB_HG
            h5file["package_ids"][current_size:current_size + n_chunks] = np.array(self.package_id_buffer)
            h5file["timestamps"][current_size:current_size + n_chunks] = np.array(self.timestamp_buffer)
        
        # Clear buffers
        self.voltage_buffer.clear()
        self.signal_buffer.clear()
        self.package_id_buffer.clear()
        self.timestamp_buffer.clear()
    
    def run(self, duration=None):
        """Main logging loop"""
        chunks_received = 0
        start_time = time.time()
        last_print_time = start_time
        t_start = time.time()
        
        try:
            while (time.time() - t_start) < duration if duration else True:
                try:
                    socks = dict(self.poller.poll(10))
                    # Non-blocking receive with 5ms timeout
                    if self.socket in socks:
                        raw_data = self.socket.recv()
                        timestamp = time.time()
                        
                        # Parse data (same as your code)
                        data_array = np.frombuffer(raw_data, dtype=np.float32)
                        
                        voltage_chunk = data_array[:CHANNELS * EXTERNAL_PLOT_CHUNK_LENGTH].reshape(
                            CHANNELS, EXTERNAL_PLOT_CHUNK_LENGTH
                        )
                        signal_chunk = data_array[CHANNELS * EXTERNAL_PLOT_CHUNK_LENGTH:2 * CHANNELS * EXTERNAL_PLOT_CHUNK_LENGTH].reshape(
                            CHANNELS, EXTERNAL_PLOT_CHUNK_LENGTH
                        )
                        package_id = int(data_array[-1] + 0.5)
                        
                        # Buffer data
                        self.voltage_buffer.append(voltage_chunk)
                        self.signal_buffer.append(signal_chunk)
                        self.package_id_buffer.append(package_id)
                        self.timestamp_buffer.append(timestamp)
                        
                        chunks_received += 1
                        
                        # Flush when buffer is full
                        if len(self.voltage_buffer) >= BUFFER_SIZE:
                            self._flush_to_disk()
                        
                        # Print status every 5 seconds
                        if time.time() - last_print_time > 5.0:
                            elapsed = time.time() - start_time
                            rate = chunks_received / elapsed
                            buffered = len(self.voltage_buffer)
                            samples_logged = chunks_received * EXTERNAL_PLOT_CHUNK_LENGTH
                            duration_s = samples_logged / FS
                            print(f"[{elapsed:.1f}s] Chunks: {chunks_received} | Rate: {rate:.1f}/s | Buffered: {buffered} | Duration: {duration_s:.1f}s")
                            last_print_time = time.time()
                    else:
                        print("No data received, waiting...")
                    
                except zmq.ZMQError as e:
                    print(f"ZMQ Error: {e}")
                    time.sleep(0.1)
                
        except KeyboardInterrupt:
            print("\n\n⚠ Interrupted - flushing remaining data...")
            self._flush_to_disk()
            
            recording_stop_time = time.time()
            
            # Update final metadata
            with h5py.File(self.h5_filename, "a") as h5file:
                h5file.attrs["recording_stopped_time"] = recording_stop_time
                h5file.attrs["recording_stopped_time_iso"] = datetime.fromtimestamp(recording_stop_time).isoformat()
                h5file.attrs["total_chunks"] = chunks_received
                h5file.attrs["total_samples"] = chunks_received * EXTERNAL_PLOT_CHUNK_LENGTH
                h5file.attrs["recording_duration_s"] = (recording_stop_time - self.recording_start_time)
            
            total_samples = chunks_received * EXTERNAL_PLOT_CHUNK_LENGTH
            duration = total_samples / FS
            print(f"✓ Saved {chunks_received} chunks ({total_samples:,} samples, {duration:.1f}s) to {self.h5_filename}")
            print("✓ Cleanup complete")
        
        finally:
            self.socket.close()
            self.context.term()


# ============================================================================
# ENTRY POINT
# ============================================================================
if __name__ == "__main__":
    time.sleep(5*60)
    logger = ZMQDataLogger()
    logger.run(duration=95)
    