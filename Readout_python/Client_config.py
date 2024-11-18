import numpy as np
from ctypes import *
import scipy.signal as sig
from sys import platform
import os
from datetime import datetime

if platform == "linux" or platform == "linux2":
    LINUX = True
elif platform == "win32":
    # Windows...
    LINUX = False
else:
    print(f"Error: Operating System not supported")

from Electrode_mapping import Electrode_mapping

if LINUX:
    from inkubeSpike import set_constants

''' UDP input stream constants '''
CHANNELS = 240 # number of e.-phys channels
LSB_HG: c_double = 0.195 # uV per LSB
FS = 17_361 # sampling frequency in Hz
T_PKG = 1/FS # time per package in seconds
MAX_PKG_ID = 1_562_500 # 90 seconds of data, pkg counter is reset after this

''' Electrophysiology communication timing and constants '''
ECHO_SHIFT = 80
RESPONSE_SHIFT = 336

STIMULUS_CYCLE = int(250e-3*FS) # for closed loop stimulation, this is the time between two stimulation commands and therefore restricting the frequency
MIN_PKG_DELAY = int(80e-3*FS) # in samples, this is the minimum timing in closed-loop stim for receiving a stimulation command from the Jupyter client and relaying it to the FPGA
RESPONSE_IMPORTANT_PERIOD = int(25e-3*FS) # samples after stimulus that spikes are readout in closed-loop stim
MAX_SPIKE_DETECT_DELAY = int(10e-3*FS) # in samples, after response important period, this is the maximum delay for spike detection
START_ID_INIT = int(6*STIMULUS_CYCLE) # when initiating closed loop stimulation this is the time delay to start segmentation 

MIN_STIM_COMMAND_DELAY = int(60e-3*FS) # in samples, for open loop stimulation, this is the minimum delay between receiving a package and desired execution

"""Software settings"""
TEST_SERVER       = False # if True the localhost test server for debugging is used
DO_STIMULATE      = True # if True the stimulation is enabled
CONTROL_NETWORKS  = True # if True the closed loop stimulation is enabled
DO_OPEN_CONTROL_PORT = True # if True the control port is opened for the Jupyter client to send environment commands
INIT_MODE = 0

"""Plotting settings"""
DO_PLOT_RAW       = False # plot the raw data
DO_PLOT           = True # enable plotting of data stream
PLOT_NETWORKS     = False # plot the activity stream organised by network instead of by MEA

DO_SEND_MEDIUM_LVL = True # send the medium level to the Jupyter client
DO_SEND_ENV        = False # send the environment data to the Jupyter client

DO_PLOT_SPIKE_WAVELETS = False # plot the cutout spike waveforms
DO_STORE_SPIKE_SHAPES  = False # store the spike waveforms for later analysis
NETWORK_SAVE_SPIKES    = np.arange(15)

TRANSMIT_SPONT_SPIKES = True # transmit the spontaneous spikes to the Jupyter client
USE_LOCAL_SERVER = True # use localhost for jupyter communication

"""Electrode layout settings"""
MEA_NUM           = 4
mea_layouts       = ["10x6"]*MEA_NUM
mask_layouts      = ["5x3 o circle"]*MEA_NUM
ELECTRODE_MAPPING = Electrode_mapping(mea_layouts,mask_layouts,n=MEA_NUM)
NETWORK_NUM       = 60
ELECTRODES        = 4

"""Spike detection and filter settings"""
BLIND_DURATION = np.int8(2e-3*FS) # in samples, careful must be less than 128, blank detection after spike event
DETECT_DURATION = np.int8(1e-3*FS) # time to check for maximum value whe threshold is surpassed

F_CORNER = 300 # corner frequency for FIR high pass
FILT_ORDER = 3 # order of the FIR filter

SPIKE_THRESH = 6 # factor with which the MAD of the signal is multiplied to get the threshold
MAX_LIST_LEN = 128*240
MIN_SPIKE_THRESH = 100 # minimum value in threshed data, should be uV

"""Environment and level settings"""
MAX_LEN_ENV_Q = 100
MAX_LEN_SPONT_Q = 4
MAX_LEN_RESPONSE_Q = 20
MAX_LEN_LVL_Q = 100

DO_SAVE_ENV = False # save the environment data
DO_SAVE_LVL = False # save the medium level data

"""Data storage settings"""
if DO_SAVE_ENV or DO_SAVE_LVL or DO_STORE_SPIKE_SHAPES:
    # Get the directory where the current script is located
    current_dir = os.path.dirname(os.path.abspath(__file__))

    # Navigate to the 'data' folder in the parent directory
    data_dir = os.path.join(current_dir, '..', 'Data')

    # Normalize the path (remove redundant separators, etc.)
    data_dir = os.path.normpath(data_dir)
    date_for_filename = datetime.today().strftime('%Y%m%d')[2:]
    id = 0
    data_folder = f'{date_for_filename}_inkube_data'
    if not os.path.isdir(data_dir):
        os.mkdir(data_dir)
    while os.path.isdir(f'{data_dir}/{data_folder}_{id}'):
        id += 1
    os.mkdir(f'{data_dir}/{data_folder}_{id}')

    DATA_FOLDER = f'{data_dir}/{data_folder}_{id}'
else:
    DATA_FOLDER = ""

# FPGA sends little endian: (i.e. 1025 dec which is 0000 0100 0000 0001 is sent as [0001, 0000, 0100, 0000])

''' Stimulation parameters'''
STIMULATION_DURATION = 6 # in packages  x57.8 us, results in 230.4 us per phase
STIMULATOR_STEP_SETTING = '10nA' # '1uA' change to '10nA' or '200nA' for finer setting
STIM_AMPLITUDE = 2 # in 1uA steps (max 255), this can also be adjusted live
ARTEFACT_CANCELLATION = True # turn the hardware blanking on or off
DISCHARGE_TIME = 17 # you can ignore this

"""Spike Shapes parameters"""
SPIKE_WAVELET_LEN = 40 # roughly 2 ms # peak is with SNEO 25 samples delayed
SPIKE_WAVELET_NUM = 2*25 # length of shape storage per channel
SPIKE_WAVELET_SHAPE = (CHANNELS, SPIKE_WAVELET_NUM, SPIKE_WAVELET_LEN)
SPIKE_WAVELET_BUF = SPIKE_WAVELET_NUM*SPIKE_WAVELET_LEN

''' Network interface constants '''
PC_IP = '192.168.10.1'
HOST_IP = "192.168.10.10"
CLIENT_DELAY = .2
CLIENT_TRIES = 5
RECEIVE_PORT = 45615 # 0xb22f

CLIENT_RECV_PORT = (HOST_IP, RECEIVE_PORT)

''' Plot related constants '''
PLOT_BUF_LEN = 2*4340 # length of datastream buffer 
PLOT_VOLT_UPDATE = PLOT_BUF_LEN//2
STATUS_Y_LIMITS = [(0,MAX_PKG_ID), (16,64)] 
AXIS_Y_LIM = 100 # in uV, max is 2**15 * LSB_HG
WAVELET_Y_LIM = 600
TEMP_BUF_LEN = 16
STATUS_LEN = 2 # number of status words to readout from UDP
TEMP_STREAM_SIZE = 15 # number of temperature/enviornment values to readout from UDP
status_pos = [0,84] # position of the status words in the UDP package that should be read out
if PLOT_NETWORKS:
    PLOT_CHANNEL_NUM = 4 # initialise this number of data stream plots for per network plotting
else:
    PLOT_CHANNEL_NUM = 60 # initialise this number of data stream plots for whole MEA plotting

''' RMS Noise plotting related constants '''
SHARED_NOISE_BINS = 16
SHARED_NOISE_MAX = 50 # 100uV times LSB resolution
DO_FLIP_INKULEVEL = 6_000

''' Spike detection constants '''
BLIND_DURATION = np.int8(2e-3*FS) # in samples, careful must be less than 128
DETECT_DURATION = np.int8(1e-3*FS)

F_CORNER = 500 # can also be set to 300
FILT_ORDER = 3

INIT_MODE = 0

''' Send constants '''
SEND_PORT = 0xb230 
CLIENT_ADDRESS_PORT = (HOST_IP,SEND_PORT)
MAX_COMMANDS_IN_SEND = 1 # used to be 5 for UDP, now we send only one at a time via USB

WORD_LENGTH_IN_BYTES = (64 + 1 + 1) * 4  # 64 commands, 1 timing word, 1 handshake word - this is for the stimulation command

''' USB Send constants '''
VENDOR_ID  = 0x33FF
PRODUCT_ID = 0x1234
USB_PREAMBLE = 0x01020304fdfeff00 # in hex, with last byte as command id, check USB_com class for more

''' Cmmunication constants for UDP and network socket '''
SEND_PORT = 0xb230 
CLIENT_ADDRESS_PORT = (HOST_IP,SEND_PORT)
MAX_COMMANDS_IN_SEND = 1 # used to be 5 for UDP, now we send only one at a time via USB
WORD_LENGTH_IN_BYTES = (64 + 1 + 1) * 4  # 64 commands, 1 timing word, 1 handshake word - this is for the stimulation command

if USE_LOCAL_SERVER:
    CONTROL_CLIENT_IP = '127.0.0.1'
else:
    CONTROL_CLIENT_IP = '129.132.40.135'

CONTROL_CLIENT_PORT = 0x1240
ENV_CONTROL_PORT = 0x1241

''' determine filter coefficients '''
# use bandpass instead
filt_b, filt_a = sig.iirfilter(FILT_ORDER, F_CORNER, btype='highpass', ftype='butter', fs=FS, output='ba')
FILT_LENGTH = len(filt_b)

if LINUX:
    set_constants(
        filt_b, filt_a, 
        FS, 
        MAX_PKG_ID, 
        BLIND_DURATION, 
        DETECT_DURATION, 
        SPIKE_THRESH, 
        status_pos, 
        MIN_SPIKE_THRESH
    )

# overwrite constants for testing
if TEST_SERVER:
    ''' Network interface constants '''
    HOST_IP = "127.0.0.1"
    CLIENT_DELAY = .2
    # FS = 7500
    # DO_STIMULATE = False
    PC_IP = '127.0.0.1'

    CLIENT_RECV_PORT = (HOST_IP, RECEIVE_PORT)
    CLIENT_ADDRESS_PORT   = (HOST_IP,SEND_PORT)

if __name__ == "__main__":
    """Print selected constants"""
    print(np.array(ELECTRODE_MAPPING.mea2recv(np.arange(60))))
    
    print(f'Filt Length {FILT_LENGTH} A: {filt_a} , B: {filt_b}')
    print(f"Timing: start {START_ID_INIT} | cycle {STIMULUS_CYCLE} | Important_Period {RESPONSE_IMPORTANT_PERIOD}")
    
    print(sig.savgol_coeffs(5, 2))