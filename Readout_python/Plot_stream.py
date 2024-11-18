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

from ctypes import *
from Client_config import (
    CHANNELS,
    PLOT_CHANNEL_NUM,
    PLOT_VOLT_UPDATE, 
    SPIKE_WAVELET_LEN,
    STATUS_LEN,
    FS,
    TEMP_STREAM_SIZE,
    DO_SEND_MEDIUM_LVL,
    DO_SEND_ENV, 
    SPIKE_WAVELET_BUF, 
    SPIKE_WAVELET_LEN, 
    SPIKE_WAVELET_NUM, 
    DO_PLOT_SPIKE_WAVELETS, 
    DO_SAVE_ENV, 
    DO_SAVE_LVL, 
    DO_FLIP_INKULEVEL, 
    ELECTRODE_MAPPING, 
    DATA_FOLDER,
)
# Tab IDs in the GUI
SIGNAL_TAB_ID = 0
STATUS_TAB_ID = 1
ENV_TAB_ID    = 2
RASTER_TAB_ID = 3
WAVELET_TAB_ID = 4

def save_shapes_process(
        spike_wavelet_stream, 
        spike_wavelet_stream_id, 
        active_channels=np.arange(CHANNELS), 
        update_t=1., 
        event = None
    ):
    """function to save spike shapes
    Args:
        spike_wavelet_stream: shared memory array for spike shapes
        spike_wavelet_stream_id: shared memory array for spike ids
        active_channels: channels to save
        update_t: time between saving
        event: event to stop saving
    """
    spike_stream = np.frombuffer(spike_wavelet_stream.get_obj(), dtype=np.float32).reshape((-1,SPIKE_WAVELET_LEN))
    spike_stream_id = np.frombuffer(spike_wavelet_stream_id.get_obj(), dtype=np.uint32) #.reshape(SPIKE_WAVELET_SHAPE)

    save_channels = np.array(ELECTRODE_MAPPING.mea2recv(active_channels.astype(int)))
    print(f'Saving spikes of receive positions: {save_channels}')
    
    store_chunks = max(int(1*60./update_t), 8*SPIKE_WAVELET_NUM) # every minute because of pkg_id
    # store_shapes = np.zeros((store_chunks, active_channels.shape[0], SPIKE_WAVELET_BUF),dtype=np.float32) # SPIKE_WAVELET_NUM, SPIKE_WAVELET_LEN
    # store_ids = np.zeros((store_chunks, active_channels.shape[0], SPIKE_WAVELET_NUM),dtype=np.uint32)
    save_chunk_ids = np.zeros(active_channels.shape[0], dtype=int)
    store_shapes = np.zeros((active_channels.shape[0], store_chunks, SPIKE_WAVELET_LEN),dtype=float) # SPIKE_WAVELET_NUM, SPIKE_WAVELET_LEN
    store_ids = np.full((active_channels.shape[0], store_chunks), -1, dtype=int)
    save_flag = False

    id = 0
    date_for_filename = datetime.today().strftime('%Y%m%d')[2:]

    subfolder = 'spike_shapes'
    if not os.path.exists(f'{DATA_FOLDER}/{subfolder}'):
        os.makedirs(f'{DATA_FOLDER}/{subfolder}')

    repetitions = 0
    shape_start_ids = np.full(spike_stream_id.shape, 2**22, dtype=np.uint32)
    print('starting spike shapes')
    while True:        
        if event.is_set(): 
            for ch_id, ch in enumerate(save_channels):
                save_ids = np.where(
                    np.not_equal(
                        shape_start_ids[ch*SPIKE_WAVELET_NUM:(ch+1)*SPIKE_WAVELET_NUM], 
                        spike_stream_id[ch*SPIKE_WAVELET_NUM:(ch+1)*SPIKE_WAVELET_NUM]
                    )
                )[0]

                # dynamic
                store_shapes[ch_id][save_chunk_ids[ch_id]:save_chunk_ids[ch_id]+save_ids.shape[0]] = np.copy(
                    spike_stream[ch*SPIKE_WAVELET_NUM+save_ids]) 
                store_ids[ch_id][save_chunk_ids[ch_id]:save_chunk_ids[ch_id]+save_ids.shape[0]] = np.copy(
                    spike_stream_id[ch*SPIKE_WAVELET_NUM+save_ids])
                
                shape_start_ids[ch*SPIKE_WAVELET_NUM+save_ids] = np.copy(spike_stream_id[ch*SPIKE_WAVELET_NUM+save_ids])

                # update the individual electrode counter
                save_chunk_ids[ch_id] = save_chunk_ids[ch_id]+save_ids.shape[0]
                save_flag = save_flag or save_chunk_ids[ch_id] > (store_chunks-SPIKE_WAVELET_NUM)

            if save_flag:
                trimmed_shapes = []
                trimmed_ids = []
                for ch_id in range(len(save_channels)):
                    if save_chunk_ids[ch_id]:
                        trimmed_shapes.append(store_shapes[ch_id][:save_chunk_ids[ch_id]])
                        trimmed_ids.append(store_ids[ch_id][:save_chunk_ids[ch_id]])
                    else:
                        trimmed_shapes.append([])
                        trimmed_ids.append([])
                
                np.savez(
                    f"{DATA_FOLDER}/{subfolder}/spike_shapes_{repetitions}.npz", 
                    shapes=np.array(trimmed_shapes, dtype=object), 
                    ids=np.array(trimmed_ids, dtype=object), 
                    timestamp=datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3], 
                    channels=active_channels, 
                )

                # np.savez(
                #     f"{data_folder}/spike_shapes_{repetitions}.npz", 
                #     shapes=store_shapes, 
                #     ids=store_ids, 
                #     timestamp=datetime.now().strftime('%Y-%m-%d %H:%M:%S.%f')[:-3], 
                #     channels=active_channels, 
                #     save_chunk_ids=save_chunk_ids, 
                # )
                print("Saved_spikes")
                save_flag = False
                save_chunk_ids = np.zeros(active_channels.shape[0], dtype=int)

                repetitions += 1
                # need to reset
                
            
        time.sleep(update_t)

def plot_process(
    plot_loc,
    voltage_plot_stream: mp.Array,
    signal_plot_stream: mp.Array,
    spike_wavelet_stream, #: mp.sharedctypes.synchronized,
    status_plot_stream: mp.Array,
    temp_stream: mp.Array,
    spike_plot_stream: mp.Array,
    spike_thresh_stream, # : mp.sharedctypes.synchronized
    plot_voltage_bool: mp.Value,
    update_thresh_bool: mp.Value,
    plot_channels: mp.Value,
    raster_plot_pipe_recv,
    level_q = None, 
    env_q = None, 
    shared_noise_array = np.zeros(4), 
):
    """process to start the plot GUI and update the data
    Args:
        plot_loc: shared memory array for position to which data streams are aligned (time information)
        voltage_plot_stream: shared memory array for voltage data which is the processed data stream with threshold for spike detection
        signal_plot_stream: shared memory array for signal data which is processed data
        spike_wavelet_stream: shared memory array for spike shapes
        status_plot_stream: shared memory array for status data
        temp_stream: shared memory array for temperature, environment and level data
        spike_plot_stream: shared memory array for spike data
        spike_thresh_stream: shared memory array for spike detection thresholds
        plot_voltage_bool: shared memory boolean whether to plot the voltage_plot_stream data
        update_thresh_bool: shared memory boolean for updating thresholds
        plot_channels: shared memory array for channels to plot
        raster_plot_pipe_recv: pipe for raster data
        level_q: queue for medium level data
        env_q: queue for environment data
        shared_noise_array: shared memory array for noise data    
    """
    print(f'PID:{os.getpid()} - Started plot process.')

    # create app object
    app = QtWidgets.QApplication(sys.argv)

    # initialise and start threads that update data
    thread = UpdateData(
        plot_loc,
        voltage_plot_stream,
        signal_plot_stream, 
        status_plot_stream,
        spike_plot_stream,
        spike_thresh_stream,
        plot_voltage_bool,
        np.arange(PLOT_CHANNEL_NUM),
        update_step=PLOT_VOLT_UPDATE, 
    )

    thread_raster = UpdateRaster(raster_plot_pipe_recv, update_t=248)
    thread_temp = UpdateTemp(temp_stream, update_t=721, level_q=level_q, env_q=env_q, shared_noise=shared_noise_array)

    if DO_PLOT_SPIKE_WAVELETS:
        thread_wavelet = UpdateWavelet(spike_wavelet_stream, np.arange(PLOT_CHANNEL_NUM), update_t=502)
    else:
        thread_wavelet = None

    # start GUI app with function callbacks for data update
    thisapp = App(
        update_thread=thread, 
        update_thread_wavelet=thread_wavelet, 
        update_thresh_bool=update_thresh_bool,
        plot_network=plot_channels, 
        channel_num=PLOT_CHANNEL_NUM
    )

    time.sleep(0.1)
    thread.set_app(thisapp)
    thread.dataChanged.connect(thisapp.update_data_osc)
    thread.start()

    thread_raster.set_app(thisapp)
    thread_raster.dataRasterChanged.connect(thisapp.update_raster)
    thread_raster.start()

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

    def __init__(self, temp_stream, update_t, level_q, env_q, shared_noise):
        super().__init__()
        self.temp_stream = np.frombuffer(temp_stream.get_obj(), dtype=np.uint32)
        self.update_t = update_t
        self.convert_factor_temp = 175 / 65535
        self.temp_offset = 45
        self.convert_factor_hum = 100 / 65535
        self.convert_factor_co2 = 100 / 32768
        self.co2_offset = 16384
        self.last_med_counter = np.zeros(4, dtype=int)
        self.shared_noise_stream = np.frombuffer(shared_noise.get_obj(), dtype=np.float32)
        if DO_SEND_MEDIUM_LVL:
            self.level_q = level_q
        if DO_SEND_ENV:
            self.env_q = env_q

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
        if DO_SEND_ENV or DO_SAVE_ENV:
            if DO_SAVE_ENV:
                subfolder_env = 'env'
                if not os.path.exists(f'{DATA_FOLDER}/{subfolder_env}'):
                    os.makedirs(f'{DATA_FOLDER}/{subfolder_env}')
                store_env = np.zeros((60*5, 8)) # time, 4x mea T, res T, hum, CO2
            else:
                store_env = np.zeros((20, 8))
            store_env_counter = 0
            chunk_env_counter = 1
            new_env = np.zeros(7)

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

            # this thread also saves data in the background so keep this one running even when on different tab
            stream_data = self.temp_stream.reshape(-1, TEMP_STREAM_SIZE)
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
                (mean_temp, mean_hum, mean_co2, med_level, med_counter, self.shared_noise_stream)
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

            # sleep
            QtCore.QThread.msleep(self.update_t)


class UpdateData(QtCore.QThread):
    """Update the electrophysiology signal data"""

    dataChanged = QtCore.pyqtSignal(tuple)

    def __init__(
        self,
        plot_loc,
        voltage_plot_stream, 
        signal_plot_stream,         
        status_plot_stream,
        spike_plot_stream,
        spike_thresh_stream,
        plot_voltage_bool: mp.Value,
        channel_num,
        update_step,
    ):
        super().__init__()
        self.plot_position_in_array = plot_loc
        self.ch_num = channel_num
        self.voltage_stream = np.frombuffer(voltage_plot_stream.get_obj(), dtype=np.float32)
        self.signal_stream = np.frombuffer(signal_plot_stream.get_obj(), dtype=np.float32)
        self.status_stream = np.frombuffer(status_plot_stream.get_obj(), dtype=np.uint32)
        self.spike_stream = np.frombuffer(spike_plot_stream.get_obj(), dtype=np.uint8)
        self.thresh_stream = np.frombuffer(spike_thresh_stream.get_obj(), dtype=np.float32)
        
        self.step = update_step
        self.plot_voltage_bool = plot_voltage_bool

    def set_app(self, app_current):
        self.app_current = app_current

    def run(self):
        while True:
            if self.app_current.currentIndex() == SIGNAL_TAB_ID or self.app_current.currentIndex() == STATUS_TAB_ID:
                while self.plot_position_in_array[0] % self.step < 0.9 * self.step:
                    time.sleep(0.05 * self.step / FS)
                current_loc = int(self.plot_position_in_array[0]) * CHANNELS
                if self.app_current.currentIndex() == SIGNAL_TAB_ID:                                    
                    thresh_channels = np.ones(self.ch_num.shape[0])
                    spikes = np.argwhere(
                        [
                            np.hstack(
                                (
                                    np.equal(
                                        self.spike_stream[current_loc + ch :: -CHANNELS], 1
                                    ),
                                    np.equal(
                                        self.spike_stream[
                                            -CHANNELS + ch : current_loc + ch + 1 : -CHANNELS
                                        ],
                                        1,
                                    ),
                                )
                            )
                            for ch in self.ch_num
                        ]
                    )
                    voltage = [
                        np.hstack(
                            (
                                self.voltage_stream[current_loc + ch :: CHANNELS],
                                self.voltage_stream[ch : current_loc + ch : CHANNELS],
                            )
                        )
                        for ch in self.ch_num
                    ]
                    if self.plot_voltage_bool:
                        signal = [
                            np.hstack(
                                (
                                    self.signal_stream[current_loc + ch :: CHANNELS],
                                    self.signal_stream[ch : current_loc + ch : CHANNELS],
                                )
                            )
                            for ch in self.ch_num
                        ]

                        for ch_id, ch_thresh in enumerate(self.ch_num):
                            thresh_channels[ch_id] = self.thresh_stream[ch_thresh]
                        self.dataChanged.emit(
                            (
                                spikes,
                                voltage,
                                signal,
                                thresh_channels,
                            )
                        )
                    else:
                        self.dataChanged.emit((spikes, voltage))
                else:                     
                    current_status_loc = int(current_loc / CHANNELS * STATUS_LEN)
                    status = [
                        np.hstack(
                            (
                                self.status_stream[current_status_loc + j :: STATUS_LEN],
                                self.status_stream[j : current_status_loc + j : STATUS_LEN],
                            )
                        )
                        for j in range(STATUS_LEN)
                    ]
                    self.dataChanged.emit((status, ))
                time.sleep(0.1 * self.step / FS)
            else:
                QtCore.QThread.msleep(2000)

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
        while True:
            if self.app_current.currentIndex() == WAVELET_TAB_ID:
                spike_template = [
                    [self.spike_stream[ch*SPIKE_WAVELET_BUF+id*SPIKE_WAVELET_LEN:ch*SPIKE_WAVELET_BUF+(id+1)*SPIKE_WAVELET_LEN] for id in range(SPIKE_WAVELET_NUM)]
                    for ch in self.ch_num
                ]

                self.dataWaveletChanged.emit((spike_template, ))
                QtCore.QThread.msleep(self.update_t)
            else:
                QtCore.QThread.msleep(2000)

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
        while True:
            if self.pipe.poll():
                if self.app_current.currentIndex() == RASTER_TAB_ID:
                    self.dataRasterChanged.emit((self.pipe.recv()))
                else:
                    self.pipe.recv()
            QtCore.QThread.msleep(self.update_t)
