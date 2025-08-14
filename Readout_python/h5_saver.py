import zmq
import h5py
import numpy as np
import struct
import json
import time
from datetime import datetime

from Client_config import (
    SPIKE_WAVELET_LEN, 
    ZMQ_SPIKE_SOCKET,
    # ZMQ_META_SOCKET,
    SPIKE_EVENT_SIZE, 
    connect_to_zmq, 
    FS, 
    ELECTRODE_MAPPING, 
    STIMULATION_DURATION, 
    STIMULATOR_STEP_SETTING, 
    STIM_AMPLITUDE, 
    DISCHARGE_TIME, 
    ZMQ_STIMCOM_ENDPOINT,
    ZMQ_STIMDATA_ENDPOINT, 
    ZMQ_ENV_ENDPOINT, 
    MAX_PKG_ID, 
    DISCHARGE_LIMIT_SETTING, 
    TEMP_STREAM_SIZE, 
    INIT_THRESH_FACTOR, 
)

# Constants
MAX_SPIKES = 240*10  # Adjust buffer size if needed

import h5py
import numpy as np
import struct
import zmq
from datetime import datetime

def saver_process(saver_event, started_pkg):
    h5_saver = H5Saver(saver_event, started_pkg)
    h5_saver.start_saving()


class H5Saver:
    def __init__(self, save_event, started_pkg):
        self.fs = FS
        self.stim_params = {
            "duration": STIMULATION_DURATION,
            "step_setting": STIMULATOR_STEP_SETTING,
            "discharge_time": DISCHARGE_TIME,
            "discharge_limit": DISCHARGE_LIMIT_SETTING, 
        }
        self.started_pkg = started_pkg
        self.creation_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
        self.amplitude = STIM_AMPLITUDE
        self.electrode_mapping = ELECTRODE_MAPPING.mapping_recv2network
        self.max_spikes = MAX_SPIKES

        self.save_event = save_event
        # self.running = False  # Flag to control data saving

        # Initialize buffer
        self.spike_index = 0  # Tracks buffer fill level
        self.spike_buffer = {
            "channels": np.empty(self.max_spikes, dtype=np.uint8),
            "times": np.empty(self.max_spikes, dtype=np.uint32),
            "waveforms": np.empty((self.max_spikes, SPIKE_WAVELET_LEN), dtype=np.float32),
            "cycles": np.empty(self.max_spikes, dtype=np.uint16),
        }

        # for env conversion:
        self.convert_factor_temp = 175 / 65535
        self.temp_offset = 45
        self.convert_factor_hum = 100 / 65535
        self.convert_factor_co2 = 100 / 32768
        self.co2_offset = 16384
        
        self.rtd_a = 3.9083e-3
        self.rtd_b = -5.775e-7
        self.rtd_c = -4.183e-12 
        self.rtd0 = 1000
        self.rtd_ref = 4.02e3
        
        self.last_pkg_t = 0
        # Create HDF5 file and structure

        self.env_socket = connect_to_zmq(ZMQ_ENV_ENDPOINT)
        self.spike_socket = connect_to_zmq(ZMQ_SPIKE_SOCKET)  # Replace with your actual socket
        self.stimcom_socket = connect_to_zmq(ZMQ_STIMCOM_ENDPOINT)  # Replace with your actual socket
        self.stimdata_socket = connect_to_zmq(ZMQ_STIMDATA_ENDPOINT)  # Replace with your actual socket

    def _initialize_h5_file(self):
        """Initialize HDF5 file structure."""
        # Generate filename
        self.h5_filename = f"../Data/{datetime.now().strftime('%Y%m%d')[2:]}_spike_data_{datetime.now().strftime('%H%M%S')}.h5"

        with h5py.File(self.h5_filename, "w") as h5file:
            # Metadata group
            metadata_group = h5file.create_group("metadata")
            metadata_group.attrs["creation_time"] = self.creation_time
            metadata_group.attrs["filestart_time"] = datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]
            metadata_group.attrs["description"] = "Spike data file for testing"
            metadata_group.attrs["fs"] = self.fs
            metadata_group.attrs["threshold"] = INIT_THRESH_FACTOR
            metadata_group.attrs["time_started_pkg_0"] = self.started_pkg

            # Stimulation parameters group
            stim_group = h5file.create_group("stimulation_parameters")
            stim_group.attrs["one_phase_pulse_duration"] = self.stim_params["duration"]
            stim_group.attrs["amp_step_setting"] = self.stim_params["step_setting"]
            stim_group.attrs["discharge_time"] = self.stim_params["discharge_time"]

            stim_data_group = h5file.create_group("stimulation_data")
            stim_data_group.create_dataset("stim_times", (0,), dtype=np.uint64, maxshape=(None,)) # for one iteration/package, repeat for matrix entries
            # stim_data_group.create_dataset("stim_cycles", (0,), dtype=np.uint16, maxshape=(None,))
            stim_data_group.create_dataset("stim_triggers", (0,), dtype=np.uint64, maxshape=(None,))
            stim_data_group.create_dataset("stim_amplitudes", (0,), dtype=np.uint8, maxshape=(None,))
            stim_data_group.create_dataset("stim_matrix", (0,2), dtype=np.uint8, maxshape=(None,2))

            # Spike data group
            spike_group = h5file.create_group("spike_data")
            spike_group.create_dataset("spike_channels", (0,), dtype=np.uint8, maxshape=(None,))
            spike_group.create_dataset("spike_times", (0,), dtype=np.uint64, maxshape=(None,))
            spike_group.create_dataset("spike_waveforms", (0, SPIKE_WAVELET_LEN), dtype=np.float32, maxshape=(None, SPIKE_WAVELET_LEN))

            # Environment data group
            env_group = h5file.create_group("env_data")
            env_group.create_dataset("env_mea_data", (0, 4), dtype=np.float32, maxshape=(None, 4))
            env_group.create_dataset("env_reservoir_data", (0, 3), dtype=np.float32, maxshape=(None, 3))
            env_group.create_dataset("env_times", (0,), dtype=type(time.time()), maxshape=(None,))
            env_group.create_dataset("env_last_pkg", (0,), dtype=np.uint64, maxshape=(None,))
            env_group.attrs["Environment data keys"] = "MEA T A-D, Reservoir T, ..."

            # Electrode mapping group
            mapping_group = h5file.create_group("electrode_mapping")
            mapping_group.create_dataset("spike_ch_to_network_electrode_mapping_matrix", data=self.electrode_mapping)

        print(f"HDF5 file initialized: {self.h5_filename}")

    def flush_to_h5(self):
        """Write buffered spike data to HDF5 file."""
        if self.spike_index == 0:
            return  # Nothing to write

        with h5py.File(self.h5_filename, "a") as h5file:
            spike_group = h5file["spike_data"]

            # Resize datasets
            new_size = spike_group["spike_channels"].shape[0] + self.spike_index
            spike_group["spike_channels"].resize((new_size,))
            spike_group["spike_times"].resize((new_size,))
            spike_group["spike_waveforms"].resize((new_size, SPIKE_WAVELET_LEN))

            # Append buffered data
            spike_group["spike_channels"][-self.spike_index:] = self.spike_buffer["channels"][:self.spike_index]
            spike_group["spike_times"][-self.spike_index:] = (
                self.spike_buffer["times"][:self.spike_index] 
                + self.spike_buffer["cycles"][:self.spike_index]*MAX_PKG_ID
            )
            spike_group["spike_waveforms"][-self.spike_index:] = self.spike_buffer["waveforms"][:self.spike_index]

            h5file.flush()  # Ensure data is written to disk

        # Reset buffer index
        self.spike_index = 0  


    def save_stimulation_data(self, raw_data):
        """Processes incoming stimulation data and writes it to HDF5."""
        
        # **Unpack header**
        header_size = struct.calcsize("!IHH")
        start_id, cycles, num_pulses = struct.unpack("!IHH", raw_data[:header_size])

        # **Unpack stimulation matrix**
        stim_matrix = np.array(struct.unpack(f"!{num_pulses*3}B", raw_data[header_size:]), dtype=np.uint8).reshape(num_pulses, 3)

        # **Create repeated entries**
        stim_times = np.full((num_pulses,), start_id, dtype=np.uint32)  # Repeat start_id
        stim_cycles = np.full((num_pulses,), cycles, dtype=np.uint32)   # Repeat cycles
        stim_amplitudes = np.full((num_pulses,), self.amplitude, dtype=np.uint16)  # Repeat amplitude

        # **Write to HDF5**
        with h5py.File(self.h5_filename, "a") as h5file:  # Open in append mode
            stim_data_group = h5file["stimulation_data"]

            # **Resize datasets**
            new_size = stim_data_group["stim_times"].shape[0] + num_pulses
            stim_data_group["stim_times"].resize((new_size,))
            # stim_data_group["stim_cycles"].resize((new_size,))
            stim_data_group["stim_triggers"].resize((new_size,))
            stim_data_group["stim_amplitudes"].resize((new_size,))
            stim_data_group["stim_matrix"].resize((new_size, 2))

            # **Append data**
            stim_data_group["stim_times"][-num_pulses:] = stim_times-stim_matrix[:,0] + stim_cycles*MAX_PKG_ID # subtract delay
            # stim_data_group["stim_cycles"][-num_pulses:] = stim_cycles
            stim_data_group["stim_triggers"][-num_pulses:] = stim_times + stim_cycles*MAX_PKG_ID
            stim_data_group["stim_amplitudes"][-num_pulses:] = stim_amplitudes
            stim_data_group["stim_matrix"][-num_pulses:, :] = stim_matrix[:,1:]

            h5file.flush()  # **Flush immediately**

        # print(f"Stim Data Saved - Time: {start_id}, Cycles: {cycles}, Pulses: {num_pulses}")

    def rtd_conv(self, adc_val):
        """Convert the sensor value to a tem perature in °C"""
        # restrict to 0 to 100 °C
        rtd_val = np.clip((adc_val*self.rtd_ref)/(2**15), self.rtd0, 1385)
        return ((-self.rtd_a+np.sqrt(self.rtd_a**2-4*self.rtd_b*(1-rtd_val/self.rtd0)))/(2*self.rtd_b))

    def save_env_data(self, raw_data):
        stream_data = np.frombuffer(raw_data, dtype=np.uint32).reshape(-1, TEMP_STREAM_SIZE) # always averaging

        res_temp = (
            np.mean(stream_data[:, 4], axis=0) * self.convert_factor_temp
            - self.temp_offset
        )
        # MEA temperatures
        mean_temp = (
            self.rtd_conv(np.mean(stream_data[:, :4], axis=0))
        )

        mean_hum = np.mean(stream_data[:, 5], axis=0) * self.convert_factor_hum
        mean_co2 = (
            np.mean(stream_data[:, 6], axis=0) - self.co2_offset
        ) * self.convert_factor_co2

        # (mean_temp, mean_hum, mean_co2)
        with h5py.File(self.h5_filename, "a") as h5file:  # Open in append mode
            env_data_group = h5file["env_data"]

            # **Resize datasets**
            new_size = env_data_group["env_times"].shape[0] + 1

            env_data_group["env_mea_data"].resize((new_size, 4))
            env_data_group["env_reservoir_data"].resize((new_size, 3))
            env_data_group["env_times"].resize((new_size,))
            env_data_group["env_last_pkg"].resize((new_size,))

            # **Append data**
            env_data_group["env_mea_data"][-1, :] = mean_temp
            env_data_group["env_reservoir_data"][-1, 0] = res_temp
            env_data_group["env_reservoir_data"][-1, 1] = mean_hum
            env_data_group["env_reservoir_data"][-1, 2] = mean_co2

            env_data_group["env_times"][-1] = time.time()
            env_data_group["env_last_pkg"][-1] = self.last_pkg_t

            h5file.flush()  # **Flush immediately**


    def start_saving(self):
        """Start listening and saving spike data."""
        # self.running = True
        zmq_poller = zmq.Poller()
        zmq_poller.register(self.spike_socket, zmq.POLLIN)
        zmq_poller.register(self.stimcom_socket, zmq.POLLIN)
        zmq_poller.register(self.stimdata_socket, zmq.POLLIN)
        zmq_poller.register(self.env_socket, zmq.POLLIN)

        init_state = False

        print("Listening for spikes...")
        while True:
            while self.save_event.is_set():
                if not init_state:
                    self._initialize_h5_file()
                    init_state = True
                socks = dict(zmq_poller.poll(10))  # 10ms timeout

                if self.spike_socket in socks:
                    spike_data = self.spike_socket.recv()
                    spike_count = struct.unpack("I", spike_data[:4])[0]

                    if spike_count:
                        parsed_spikes = parse_spike_events(spike_data)

                        # Determine available space in buffer
                        available_space = self.max_spikes - self.spike_index
                        num_insert = min(spike_count, available_space)

                        # Store directly into NumPy buffer at spike_index
                        self.spike_buffer["channels"][self.spike_index:self.spike_index + num_insert] = parsed_spikes["channel_id"][:num_insert]
                        self.spike_buffer["times"][self.spike_index:self.spike_index + num_insert] = parsed_spikes["package_id"][:num_insert]
                        self.spike_buffer["waveforms"][self.spike_index:self.spike_index + num_insert] = parsed_spikes["waveform"][:num_insert]
                        self.spike_buffer["cycles"][self.spike_index:self.spike_index + num_insert] = parsed_spikes["cycles"][:num_insert]

                        self.spike_index += num_insert

                        # Auto-flush when buffer is full
                        if self.spike_index >= self.max_spikes:
                            self.flush_to_h5()

                        self.last_pkg_t = parsed_spikes["package_id"][-1] + parsed_spikes["cycles"][-1]*MAX_PKG_ID

                if self.stimdata_socket in socks:
                    raw_data = self.stimdata_socket.recv()
                    self.amplitude = int(raw_data[0])

                if self.stimcom_socket in socks:
                    raw_data = self.stimcom_socket.recv()
                    self.save_stimulation_data(raw_data)

                if self.env_socket in socks:
                    raw_data = self.env_socket.recv()
                    self.save_env_data(raw_data)

            while not self.save_event.is_set():
                init_state = False
                time.sleep(0.1)


def parse_spike_events(data):
    """Parse multiple spike events from binary data."""

    if len(data) < 4:
        return np.empty((0,), dtype=np.dtype([
            ("channel_id", np.uint8),
            ("package_id", np.uint32),
            ("cycles", np.uint16),
            ("waveform", np.float32, SPIKE_WAVELET_LEN)
        ]))  # Return empty structured array

    spike_count = struct.unpack("I", data[:4])[0]

    expected_size = 4 + spike_count * SPIKE_EVENT_SIZE
    if len(data) != expected_size:
        return np.empty((0,), dtype=np.dtype([
            ("channel_id", np.uint8),
            ("package_id", np.uint32),
            ("cycles", np.uint16),
            ("waveform", np.float32, SPIKE_WAVELET_LEN)
        ]))  # Return empty structured array

    # Extract spike events
    spike_data = data[4:]
    spikes = np.frombuffer(spike_data, dtype=np.dtype([
        ("channel_id", np.uint8),
        ("package_id", np.uint32),
        ("cycles", np.uint16),
        ("waveform", np.float32, SPIKE_WAVELET_LEN)
    ]))

    return spikes


def parse_spike_times(data):
    """Parse multiple spike events, extracting channel ID and package ID separately."""
    if len(data) < 4:
        raise ValueError(f"Received data too small: {len(data)} bytes")

    # Extract number of spikes
    spike_count = struct.unpack("I", data[:4])[0]
    if spike_count == 0:
        return np.empty(0, dtype=np.uint8), np.empty(0, dtype=np.uint32)  # Empty arrays for consistency

    expected_size = 4 + spike_count * SPIKE_EVENT_SIZE  # Original format
    if len(data) != expected_size:
        raise ValueError(f"Data length mismatch: expected {expected_size} bytes, got {len(data)} bytes")

    # Extract the raw spike data (skip first 4 bytes for spike count)
    spike_data = np.frombuffer(data[4:], dtype=np.uint8).reshape(-1, SPIKE_EVENT_SIZE)

    # Extract channel IDs (first byte of each spike)
    channel_ids = spike_data[:, 0].astype(np.uint8)

    # Extract package IDs (next 4 bytes of each spike)
    package_ids = np.frombuffer(spike_data[:, 1:5].flatten(), dtype=np.uint32)

    return channel_ids, package_ids

