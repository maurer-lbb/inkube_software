import time
import numpy as np
import multiprocessing as mp
import sys
from PyQt6 import QtWidgets, QtGui
from PyQt6.QtWidgets import QApplication, QWidget
from pyqtgraph.Qt import QtCore
from datetime import datetime
import os
from GUI import App
import zmq

import struct
import socket

from ctypes import *
from Client_config import (
    CHANNELS,
    PLOT_CHANNEL_NUM,
    PLOT_VOLT_UPDATE, 
    STATUS_LEN,
    FS,
    TEMP_STREAM_SIZE,
    DO_SEND_MEDIUM_LVL,
    DO_SEND_ENV, 
    SPIKE_WAVELET_LEN, 
    DO_PLOT_SPIKE_WAVELETS, 
    DO_SAVE_ENV, 
    DO_SAVE_LVL, 
    DO_FLIP_INKULEVEL, 
    ELECTRODE_MAPPING, 
    DATA_FOLDER,
    PLOT_BUF_LEN, 

    ZMQ_PLOT_SOCKET, 
    ZMQ_SPIKE_SOCKET, 
    ZMQ_ENV_ENDPOINT, 

    PLOT_UPDATE_STEP,
    connect_to_zmq, 
)

from h5_saver import parse_spike_times
# Tab IDs in the GUI
SIGNAL_TAB_ID = 0
STATUS_TAB_ID = 1
ENV_TAB_ID    = 2
RASTER_TAB_ID = 3
WAVELET_TAB_ID = 4

EXTERNAL_PLOT_CHUNK_LENGTH = 128

def plot_process(
    plot_voltage_bool,
    plot_channels,
):
    """process to start the plot GUI and update the data

    """

    print(f'PID:{os.getpid()} - Started plot process.')

    env_socket = connect_to_zmq(ZMQ_ENV_ENDPOINT)
    data_socket = connect_to_zmq(ZMQ_PLOT_SOCKET)
    spike_socket = connect_to_zmq(ZMQ_SPIKE_SOCKET)
    # create app object
    app = QtWidgets.QApplication(sys.argv)

    # initialise and start threads that update data
    thread = UpdateData(
        plot_voltage_bool,
        np.arange(PLOT_CHANNEL_NUM),
        PLOT_VOLT_UPDATE, 
        data_socket, 
        spike_socket, 
    )

    # thread_raster = UpdateRaster(raster_plot_pipe_recv, update_t=248)
    thread_temp = UpdateTemp(env_socket, update_t=.5)

    # if DO_PLOT_SPIKE_WAVELETS:
    #     thread_wavelet = UpdateWavelet(spike_wavelet_stream, np.arange(PLOT_CHANNEL_NUM), update_t=502)
    # else:
    thread_wavelet = None

    # start GUI app with function callbacks for data update
    thisapp = App(
        update_thread=thread, 
        update_thread_wavelet=thread_wavelet, 
        plot_network=plot_channels, 
        channel_num=PLOT_CHANNEL_NUM
    )

    time.sleep(.1)
    thread.set_app(thisapp)
    thread.dataChanged.connect(thisapp.update_data_osc)
    thread.start()

    # thread_raster.set_app(thisapp)
    # thread_raster.dataRasterChanged.connect(thisapp.update_raster)
    # thread_raster.start()

    thread_temp.set_app(thisapp)
    thread_temp.dataChanged.connect(thisapp.update_temp)
    thread_temp.start()

    if DO_PLOT_SPIKE_WAVELETS:
        thread_wavelet.set_app(thisapp)
        thread_wavelet.dataWaveletChanged.connect(thisapp.update_wavelet)
        thread_wavelet.start()

    thisapp.show()

    sys.exit(app.exec())

class UpdateTemp(QtCore.QThread):
    """Thread updating environment and level plot data. This also sends and or saves the env and level data to the ControlPort Client"""

    dataChanged = QtCore.pyqtSignal(tuple)

    def __init__(self, env_socket, update_t):
        super().__init__()
        self.env_socket = env_socket
        self.poller = zmq.Poller()
        self.poller.register(self.env_socket, zmq.POLLIN)
        print(f'Poller registered for env data')

        self.update_t = update_t
        self.convert_factor_temp = 175 / 65535
        self.temp_offset = 45
        self.convert_factor_hum = 100 / 65535
        self.convert_factor_co2 = 100 / 32768
        self.co2_offset = 16384
        self.last_med_counter = np.zeros(4, dtype=int)

        # RTD constants
        self.rtd_a = 3.9083e-3
        self.rtd_b = -5.775e-7
        self.rtd_c = -4.183e-12 
        self.rtd0 = 1000
        self.rtd_ref = 4.02e3

    def set_app(self, app_current):
        self.app_current = app_current

    def rtd_conv(self, adc_val):
        """Convert the sensor value to a tem perature in °C"""
        # restrict to 0 to 100 °C
        rtd_val = np.clip((adc_val*self.rtd_ref)/(2**15), self.rtd0, 1385)

        return ((-self.rtd_a+np.sqrt(self.rtd_a**2-4*self.rtd_b*(1-rtd_val/self.rtd0)))/(2*self.rtd_b))

    def run(self):
        t_start = time.time()
        if DO_SAVE_ENV:
            subfolder_env = 'env'
            if not os.path.exists(f'{DATA_FOLDER}/{subfolder_env}'):
                os.makedirs(f'{DATA_FOLDER}/{subfolder_env}')
            store_env = np.zeros((60*5, 8)) # time, 4x mea T, res T, hum, CO2
            store_env_counter = 0
            chunk_env_counter = 1
            new_env = np.zeros(7)
        else:
            store_env = np.zeros((20, 8))
            
        if DO_SEND_MEDIUM_LVL or DO_SAVE_LVL:            
            if DO_SAVE_LVL:
                subfolder_lvl = 'medium_level'
                if not os.path.exists(f'{DATA_FOLDER}/{subfolder_lvl}'):
                    os.makedirs(f'{DATA_FOLDER}/{subfolder_lvl}')
                store_lvl = np.zeros((60*5, 9))
            else:
                store_lvl = np.zeros((20, 9))
            store_lvl_counter = 0
            chunk_lvl_counter = 1
            new_lvl = np.zeros(8)
        
        if DO_SAVE_ENV or DO_SAVE_LVL:
            # save start time
            timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            # Specify the file path where you want to store the timestamp
            file_path = f'{DATA_FOLDER}/start_time_env.txt'

            # Open the file in write mode and write the timestamp
            with open(file_path, 'w') as file:
                file.write(timestamp)
            print(f"Timestamp '{timestamp}' has been written to '{file_path}'.")

        while True:            
            # this reads out medium and environment from UDP package

            # # this thread also saves data in the background so keep this one running even when on different tab
            # print('Polling for env data')
            # socks = dict(self.poller.poll(10))
            # print(socks)

            # Receive raw data from ZeroMQ
            if True:
                try:
                    # print('Polling for env data')
                    raw_data = self.env_socket.recv()
                    # print(f"Received env data with shape {len(raw_data)}")

                    stream_data = np.frombuffer(raw_data, dtype=np.uint32).reshape(-1, TEMP_STREAM_SIZE)
                    
                    mean_temp = np.zeros(5)
                    mean_temp[4] = (
                        np.mean(stream_data[:, 4], axis=0) * self.convert_factor_temp
                        - self.temp_offset
                    )
                    # MEA temperatures
                    mean_temp[:4] = (
                        self.rtd_conv(np.mean(stream_data[:, :4], axis=0))
                    )

                    mean_hum = np.mean(stream_data[:, 5], axis=0) * self.convert_factor_hum
                    mean_co2 = (
                        np.mean(stream_data[:, 6], axis=0) - self.co2_offset
                    ) * self.convert_factor_co2
                    if DO_FLIP_INKULEVEL:
                        med_level = DO_FLIP_INKULEVEL-np.copy(stream_data[0, 7:11])
                    else:
                        med_level = np.copy(stream_data[0, 7:11])
                    med_counter = np.copy(stream_data[0, 11:15])
                    self.dataChanged.emit(
                        (mean_temp, mean_hum, mean_co2, med_level, med_counter)
                    )

                    # this is for sending to the control port Qs or saving locally

                    if DO_SEND_ENV or DO_SAVE_ENV or DO_SEND_MEDIUM_LVL or DO_SAVE_LVL:
                        time_passed = time.time() - t_start
                        if DO_SEND_ENV or DO_SAVE_ENV:
                            new_env[:5] = mean_temp
                            new_env[5] = mean_hum
                            new_env[6] = mean_co2
                            if np.any(np.not_equal(new_env, store_env[store_env_counter-1, 1:])):                        
                                if store_env_counter == store_env.shape[0]:
                                    if DO_SAVE_ENV:                            
                                        np.save(f'{DATA_FOLDER}/{subfolder_env}/temperature_data_{chunk_env_counter}', store_env)
                                        chunk_env_counter += 1
                                    store_env_counter = 0

                                store_env[store_env_counter, 0] = time_passed
                                store_env[store_env_counter, 1:] = new_env 

                                if DO_SEND_ENV:                                            
                                    if not store_env_counter%10:
                                        if not self.env_q.full():
                                            if not store_env_counter:
                                                self.env_q.put(store_env[store_env_counter-10:])
                                            else:
                                                self.env_q.put(store_env[store_env_counter-10:store_env_counter])
                                store_env_counter += 1

                        if DO_SEND_MEDIUM_LVL or DO_SAVE_LVL:
                            new_lvl[:4] = med_level
                            new_lvl[4:] = med_counter
                            if np.any(np.not_equal(new_lvl, store_lvl[store_lvl_counter-1, 1:])):                       
                                if store_lvl_counter == store_lvl.shape[0]:
                                    if DO_SAVE_LVL:
                                        np.save(f'{DATA_FOLDER}/{subfolder_lvl}/medium_data_{chunk_lvl_counter}', store_lvl)
                                        chunk_lvl_counter += 1
                                    store_lvl_counter = 0
                                        
                                store_lvl[store_lvl_counter, 0] = time_passed
                                store_lvl[store_lvl_counter, 1:] = new_lvl
                                                                            
                                if DO_SEND_MEDIUM_LVL: 
                                    if not store_lvl_counter%10:
                                        if not self.level_q.full():
                                            if not store_lvl_counter:
                                                self.level_q.put(store_lvl[store_lvl_counter-10:])
                                            else:
                                                self.level_q.put(store_lvl[store_lvl_counter-10:store_lvl_counter])
                                store_lvl_counter += 1

                except Exception as e:
                    print(f'Raw env data receive failed: {e}')
            else: 
                time.sleep(self.update_t)


class UpdateData(QtCore.QThread):
    """Update the electrophysiology signal data from ZeroMQ"""

    dataChanged = QtCore.pyqtSignal(tuple)

    def __init__(
        self,
        plot_voltage_bool,
        channel_num,
        update_step,
        data_socket,  # Use ZMQ instead of UNIX socket
        spike_socket, 
    ):
        super().__init__()
        self.plot_position_in_array = 0
        self.ch_num = channel_num
        self.voltage_stream = np.zeros((CHANNELS, PLOT_BUF_LEN), dtype=np.float32)
        self.signal_stream = np.zeros((CHANNELS, PLOT_BUF_LEN), dtype=np.float32)
        self.thresh_stream = np.zeros(CHANNELS, dtype=np.float32)
        
        self.step = update_step
        self.plot_voltage_bool = plot_voltage_bool

        self.data_socket = data_socket  # ZMQ data socket
        self.spike_socket = spike_socket  # ZMQ spike socket
        self.poller = zmq.Poller()
        self.poller.register(self.data_socket, zmq.POLLIN)
        self.poller.register(self.spike_socket, zmq.POLLIN)

    def set_app(self, app_current):
        self.app_current = app_current

    def run(self):
        current_loc = 0
        last_package_id = 0  # Used for spike alignment
        
        # Define a reasonable max spike buffer size (adjust as needed)
        MAX_SPIKES = 240*100  # Preallocate space for up to 10k spikes
        spike_channel_buffer = np.empty(MAX_SPIKES, dtype=np.uint8)
        spike_package_buffer = np.empty(MAX_SPIKES, dtype=np.uint32)
        spike_index = 0  # Tracks the current insert position


        time.sleep(.5)
        # **Drain any old messages from the buffers**
        print("Draining ZeroMQ buffers before starting...")
        while True:
            try:
                self.data_socket.recv(zmq.NOBLOCK)  # Non-blocking receive
            except zmq.Again:  # No more messages left in the buffer
                break
        
        while True:
            try:
                self.spike_socket.recv(zmq.NOBLOCK)  # Non-blocking receive
            except zmq.Again:  # No more messages left in the buffer
                break

        print("Buffers cleared. Now starting processing.")


        while True:
            try:
                # Poll both data and spike sockets with a 10ms timeout
                socks = dict(self.poller.poll(10))

                # Receive raw data from ZeroMQ
                if self.data_socket in socks:
                    try:
                        raw_data = self.data_socket.recv()
                        data_array = np.frombuffer(raw_data, dtype=np.float32)

                        # Directly slice without redundant conversions
                        voltage_chunk = data_array[:CHANNELS * EXTERNAL_PLOT_CHUNK_LENGTH].reshape(CHANNELS, EXTERNAL_PLOT_CHUNK_LENGTH)
                        signal_chunk = data_array[CHANNELS * EXTERNAL_PLOT_CHUNK_LENGTH:2 * CHANNELS * EXTERNAL_PLOT_CHUNK_LENGTH].reshape(CHANNELS, EXTERNAL_PLOT_CHUNK_LENGTH)
                        thresh_chunk = data_array[2 * CHANNELS * EXTERNAL_PLOT_CHUNK_LENGTH : -1]  # Last value is package ID

                        # Assign slices directly
                        self.voltage_stream[self.ch_num, self.plot_position_in_array : self.plot_position_in_array + EXTERNAL_PLOT_CHUNK_LENGTH] = voltage_chunk[self.ch_num,:]
                        self.signal_stream[self.ch_num, self.plot_position_in_array : self.plot_position_in_array + EXTERNAL_PLOT_CHUNK_LENGTH] = signal_chunk[self.ch_num,:]
                        self.thresh_stream[self.ch_num] = thresh_chunk[self.ch_num]

                        last_package_id = int(data_array[-1]+.5)

                        self.plot_position_in_array = (self.plot_position_in_array+EXTERNAL_PLOT_CHUNK_LENGTH)
                    except Exception as e:
                        # print(f'Raw data receive failed: {e}')
                        pass
                # Receive spikes from ZeroMQ
                if self.spike_socket in socks:
                    try:
                        spike_data = self.spike_socket.recv()
                        if len(spike_data) > 3:
                            spike_count = struct.unpack("I", spike_data[:4])[0]
                            # print(f"Received spikes {spike_count}")
                            if spike_count:
                                # Get separate channel & package arrays
                                channels, packages = parse_spike_times(spike_data)

                                # Efficiently insert into preallocated buffer
                                num_insert = min(spike_count, MAX_SPIKES - spike_index)
                                spike_channel_buffer[spike_index:spike_index + num_insert] = channels[:num_insert]
                                spike_package_buffer[spike_index:spike_index + num_insert] = packages[:num_insert]
                                spike_index += num_insert
                        else:
                            print("No spikes")
                    except Exception as e:
                        print(f"Spike data receive failed: {e}")


                if self.plot_position_in_array == PLOT_BUF_LEN:  # Emit every quarter
                    try:
                        if (self.app_current.currentIndex() in [SIGNAL_TAB_ID, STATUS_TAB_ID]) and not self.app_current.freeze:
                            # Slice only the filled part of the spike buffer
                            channels_to_emit = spike_channel_buffer[:spike_index].copy()
                            packages_to_emit = (spike_package_buffer[:spike_index].copy()).astype(int)                        

                            self.emit_plot_data(channels_to_emit, packages_to_emit, last_package_id)
                        spike_index = 0  # Reset buffer index for next batch
                        self.plot_position_in_array = 0

                    except Exception as e:
                        print(f'Emitting data failed with {e}')


            except Exception as e:
                # print(f"ZMQ receive error: {e}")
                continue  # Keep retrying



    def emit_plot_data(self, channel_ids, package_ids, last_package_id):
        """Emit the updated data including spike positions."""
        if self.app_current.currentIndex() == SIGNAL_TAB_ID:                                    
            # print("Emitting now")

            # Align spikes with the plot buffer using package IDs
            spike_x_values = [[] for _ in range(self.ch_num.shape[0])]

            for ch_order, ch in enumerate(self.ch_num):
                spike_ids = np.where(channel_ids == ch)[0]
                spike_x_values[ch_order] = package_ids[spike_ids]-last_package_id - 2 # shift is necessary because of subtraction?
            # print(f"Example pkg {package_ids[spike_ids]}, and {last_package_id}")
            # print("Done with spikes")
            # print(f'Spikes are for example: {spike_x_values[0]} and {spike_x_values[1]}')

            # voltage = [self.voltage_stream[ch, :self.plot_position_in_array] for ch in self.ch_num]

            if self.plot_voltage_bool:
                    
                self.dataChanged.emit(
                    (
                        spike_x_values,  # X-Y spike data
                        self.voltage_stream[self.ch_num, :self.plot_position_in_array],
                        self.signal_stream[self.ch_num, :self.plot_position_in_array],
                        self.thresh_stream[self.ch_num],
                    )
                )
            else:
                self.dataChanged.emit(
                    (
                        spike_x_values,  # X-Y spike data
                        self.voltage_stream[self.ch_num, :self.plot_position_in_array],
                    )
                )                
        


class UpdateWavelet(QtCore.QThread):
    """Update the spike shapes data"""
    dataWaveletChanged = QtCore.pyqtSignal(tuple)

    def __init__(self, spike_wavelet_stream, channel_num, update_t):
        super().__init__()
        self.spike_stream = np.frombuffer(spike_wavelet_stream.get_obj(), dtype=np.float32) #.reshape(SPIKE_WAVELET_SHAPE)
        self.ch_num = channel_num
        self.update_t = update_t

    def set_app(self, app_current):
        self.app_current = app_current

    def run(self):
        pass

class UpdateRaster(QtCore.QThread):
    """Update the raster plot data"""
    dataRasterChanged = QtCore.pyqtSignal(tuple)

    def __init__(self, raster_plot_pipe_recv, update_t):
        super().__init__()
        self.pipe = raster_plot_pipe_recv
        self.update_t = update_t

    def set_app(self, app_current):
        self.app_current = app_current

    def run(self):
        pass