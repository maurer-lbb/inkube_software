import numpy as np
from ctypes import *
import scipy.signal as sig
from sys import platform
import os
from datetime import datetime
import struct
import zmq
import json
import time

if platform == "linux" or platform == "linux2":
    LINUX = True
elif platform == "win32":
    # Windows...
    LINUX = False
else:
    print(f"Error: Operating System not supported")

from Electrode_mapping import Electrode_mapping

''' UDP input stream constants '''
CHANNELS = 240 # number of e.-phys channels
LSB_HG: c_double = 0.195 # uV per LSB
FS = 17_361 # sampling frequency in Hz
T_PKG = 1/FS # time per package in seconds
MAX_PKG_ID = 1_562_500 # 90 seconds of data, pkg counter is reset after this

''' ZMQ sockets for c++ backend '''

ZMQ_PLOT_SOCKET     = "tcp://localhost:6001"  # Connect to first ZMQ stream
ZMQ_SPIKE_SOCKET    = "tcp://localhost:5556"
ZMQ_PKG_SOCKET      = "tcp://localhost:5557"

ZMQ_USBCOM_ENDPOINT = "tcp://localhost:5558"
ZMQ_ENV_ENDPOINT    = "tcp://localhost:5551"
THRESH_SOCKET_PATH = "/tmp/thresh_control_socket"

# ZMQ ports 
ZMQ_RESPONSE_PORT = 5459
ZMQ_STIM_REQUEST_PORT = 5460
#STIM_LOC = "10.50.250.65" # ZMQ endpoints for response and stimulus data
STIM_LOC = "127.0.0.1" # ZMQ endpoints for response and stimulus data
#STIM_LOC = "10.150.94.199"
ZMQ_RESPONSE_ENDPOINT = f"tcp://*:{ZMQ_RESPONSE_PORT}"  # Server publishes spike data responses
ZMQ_STIM_REQUEST_ENDPOINT = f"tcp://{STIM_LOC}:{ZMQ_STIM_REQUEST_PORT}"  # Server subscribes to stimulus requests

# Define the ZMQ address for stimulation data
ZMQ_STIMCOM_SOCKET = "tcp://*:5541"
ZMQ_STIMCOM_ENDPOINT = "tcp://127.0.0.1:5541"

ZMQ_STIMDATA_SOCKET = "tcp://*:5542"
ZMQ_STIMDATA_ENDPOINT = "tcp://127.0.0.1:5542"

''' Electrophysiology communication timing and constants '''
ECHO_SHIFT = 80
RESPONSE_SHIFT = 336

STIMULUS_CYCLE = int(500e-3*FS) # for closed loop stimulation, this is the time between two stimulation commands and therefore restricting the frequency
MIN_PKG_DELAY = int(25e-3*FS) # in samples, this is the minimum timing in closed-loop stim for receiving a stimulation command from the Jupyter client and relaying it to the FPGA
RESPONSE_IMPORTANT_PERIOD = int(20e-3*FS) # samples after stimulus that spikes are readout in closed-loop stim
START_ID_INIT = int(1*STIMULUS_CYCLE) # when initiating closed loop stimulation this is the time delay to start segmentation 

MIN_STIM_COMMAND_DELAY = int(60e-3*FS) # in samples, for open loop stimulation, this is the minimum delay between receiving a package and desired execution
CONSTANT_TRIGGERED_STIM_SHIFT = int(5*17.361+.5) # constant offset for fixed delay triggered stimulus

"""Software settings"""
TEST_SERVER       = False # if True the localhost test server for debugging is used
CONTROL_NETWORKS  = True # if True the closed loop stimulation is enabled
DO_OPEN_CONTROL_PORT = True # if True the control port is opened for the Jupyter client to send environment commands
INIT_MODE = 0

"""Plotting settings"""
DO_PLOT_RAW       = False # plot the raw data
DO_PLOT           = True # enable plotting of data stream
PLOT_NETWORKS     = False # plot the activity stream organised by network instead of by MEA
DO_PLOT_SPIKE_WAVELETS = False # plot the cutout spike waveforms
DO_PLOT_NETWORK_GROUPS = False

DO_SEND_MEDIUM_LVL = False # send the medium level to the Jupyter client
DO_SEND_ENV        = False # send the environment data to the Jupyter client

USE_LOCAL_SERVER = True # use localhost for jupyter communication

"""Electrode layout settings"""
MEA_NUM           = 4
CHIP_NUM          = 4 # per MEA
mea_layouts       = ["10x6"]*MEA_NUM # 10x6
mask_layouts      = ["5x3 o circle"]*MEA_NUM # 5x3 o circle
ELECTRODE_MAPPING = Electrode_mapping(mea_layouts,mask_layouts,n=MEA_NUM)
NETWORK_NUM       = 15*MEA_NUM
ELECTRODES        = 4

""" Spike detection settings"""
INIT_THRESH_FACTOR = 6. # initial threshold factor for spike detection
SPIKE_WAVELET_NUM = 2
SPIKE_WAVELET_LEN = 45
SPIKE_EVENT_FORMAT = f"=B I H {SPIKE_WAVELET_LEN}f"  # Force correct alignment (use '=') uint8 channel_id, uint32 package_id, uint16 cycles, 34 float waveform
SPIKE_EVENT_SIZE = struct.calcsize(SPIKE_EVENT_FORMAT)  # Calculate size dynamically

"""Environment and level settings"""
MAX_LEN_ENV_Q = 100
MAX_LEN_SPONT_Q = 4
MAX_LEN_RESPONSE_Q = 20
MAX_LEN_LVL_Q = 100

DO_SAVE_ENV = False # save the environment data
DO_SAVE_LVL = False # save the medium level data

"""Data storage settings"""
if DO_SAVE_ENV or DO_SAVE_LVL:
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
STIMULATION_DURATION = 8 # in packages  x57.8 us, results in 230.4 us per phase
STIMULATOR_STEP_SETTING = '10nA' # '1uA' change to '10nA' or '200nA' for finer setting
STIM_AMPLITUDE = 5 # in 1uA steps (max 255), this can also be adjusted live
DISCHARGE_TIME = 17
DISCHARGE_LIMIT_SETTING = 'recover1uA'
ENABLE_FAST_SETTLE = True
DO_FILTER_SWITCH = True

''' Network interface constants '''
PC_IP = '192.168.10.1'
HOST_IP = "192.168.10.10"
CLIENT_DELAY = .2
CLIENT_TRIES = 5
RECEIVE_PORT = 45615 # 0xb22f

CLIENT_RECV_PORT = (HOST_IP, RECEIVE_PORT)

''' Plot related constants '''
PLOT_BUF_LEN = 8192//2 # length of datastream buffer 
PLOT_UPDATE_STEP = 1 # slicing of the datastream buffer for plotting
PLOT_VOLT_UPDATE = PLOT_BUF_LEN
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

INIT_MODE = 0

''' USB Send constants '''
VENDOR_ID  = 0x33FF
PRODUCT_ID = 0x1234
USB_PREAMBLE = 0x01020304fdfeff00 # in hex, with last byte as command id, check USB_com class for more

''' Communication constants for UDP and network socket '''
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
RL_INTERFACE_PORT      = 5543


# overwrite constants for testing
if TEST_SERVER:
    ''' Network interface constants '''
    HOST_IP = "127.0.0.1"
    CLIENT_DELAY = .2
    # FS = 7500
    PC_IP = '127.0.0.1'

    CLIENT_RECV_PORT = (HOST_IP, RECEIVE_PORT)
    CLIENT_ADDRESS_PORT   = (HOST_IP,SEND_PORT)


def connect_to_zmq(socket_endpoint):
    """Connect to ZeroMQ publisher socket."""
    context = zmq.Context.instance()
    socket = context.socket(zmq.SUB)
    socket.connect(socket_endpoint)
    socket.setsockopt(zmq.SUBSCRIBE, b"")  # Subscribe to all messages
    print(f"Connected to ZeroMQ at {socket_endpoint}")
    return socket

def drain_zmq_queue(socket, delay_t=1e-6):
    """Drains all messages from a ZMQ socket queue without blocking."""
    message = None
    number_of_messages = 0
    try:
        while True:
            message = socket.recv(zmq.DONTWAIT)  # Non-blocking receive
            number_of_messages += 1
            time.sleep(delay_t)
            # print(f"Received message: {message}")
            # Optional: Process the message if needed
    except zmq.Again:
        return number_of_messages

if __name__ == "__main__":
    """Print selected constants"""
    print(np.array(ELECTRODE_MAPPING.mea2recv(np.arange(60))))
    
    print(f"Timing: start {START_ID_INIT} | cycle {STIMULUS_CYCLE} | Important_Period {RESPONSE_IMPORTANT_PERIOD}")
    
    print(sig.savgol_coeffs(5, 2))

    print((FS/(MIN_PKG_DELAY+RESPONSE_IMPORTANT_PERIOD)))