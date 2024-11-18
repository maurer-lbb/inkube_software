"""
This code performs data receive and processing for an inkube system.
It includes functions for setting constants, connecting to a client, and performing a full readout.
The `receive_process` function receives UDP data, initializes the readout process, and calls the `full_readout` function.
The `connect_client` function creates a socket for UDP receive and sends an empty package to whitelist the firewall.
The `full_readout` function performs the full readout process, including data filtering, spike detection
"""
from cpython.mem cimport PyMem_Malloc

import os
import numpy as pnp # this is the Python library
cimport numpy as np
import time
import cython
import multiprocessing as mp
import threading
np.import_array()
# from cython.cimports.cpython import array
from cpython.buffer cimport Py_buffer
from cpython.buffer cimport PyObject_GetBuffer
from cpython.buffer cimport PyBuffer_Release
from cython.view cimport array as cvarray

from cython.parallel cimport prange
cimport openmp

import array
from cython cimport *

import _socket
from _socket import *

DEF FS = 17_361
DEF CHANNELS = 240
DEF CHIP_NUM = 16
DEF BUFF_LEN = 4096
DEF FILT_LEN = 4
DEF ARTEFACT_FILT_LEN = 3
DEF ARTEFACT_LEN = 4 # 4 samples past max subtract
DEF OUT_BUFF_LEN = 2*4340 # Changed 221111 SI from 8680
DEF STATUS_LEN = 2
DEF TEMP_DATA_LEN = 15

DEF K_SNEO = 4 # 3
DEF N_LEN = 170 # 72 #  34 # 4*K_SNEO+1 # 20+17+1 # 4*K_SNEO+1 , must be bigger than detect duration + WAVELET_DELAY
DEF BW_LEN = 4*K_SNEO+1

DEF TOT_LEN = K_SNEO+N_LEN

DEF SPIKE_WAVELET_DELAY = 18 # 25 for sneo, 12 for HP
DEF SPIKE_WAVELET_LEN = 40 # make sure this is less than N_LEN because of buffer
# LEN - DELAY must be smaller than DETECT Duration, currently 7 Samples
DEF SPIKE_WAVELET_NUM = 2*25
DEF SPIKE_WAVELET_BUF = SPIKE_WAVELET_LEN*SPIKE_WAVELET_NUM

DEF MAX_LIST_LEN = 128*240

DEF SAVE_SPIKE_SHAPES = 0 # also for plotting activate this

DEF USE_SNEO = 0 # use the smoothed non-linear energy operator for spike detection
DEF ONLY_STIM = 0 # skip the readout and spike detection

ctypedef np.uint16_t BUFF_TYPE

cdef np.float32_t[FILT_LEN] coeff_a
cdef np.float32_t[FILT_LEN] coeff_b
cdef np.int32_t MAX_PKG_ID = 0
cdef np.int8_t BLIND_DURATION
cdef np.int8_t DETECT_DURATION
cdef np.float32_t THRESH_FACTOR
cdef np.float32_t MIN_THRESH
cdef np.float32_t FS = 20_000
cdef np.int16_t MAX_VAL = 1000
cdef np.uint8_t[STATUS_LEN] STATUS_POS

cdef extern from "math.h" nogil:
    cdef np.float32_t exp(np.float32_t x)
    cdef np.float32_t abs(np.float32_t x)
    cdef np.float32_t log(np.float32_t x)
    cdef np.float32_t cos(np.float32_t x)
    cdef np.float32_t pow(np.float32_t x, np.float32_t y)

cdef ch_id_to_mea(np.uint8_t id):
    cdef np.uint8_t[3] loc
    loc[0] = <np.uint8_t>(id % 16) // 4
    loc[1] = <np.uint8_t>(id % 4)
    loc[2] = <np.uint8_t>id // 16
    return loc

def set_constants(
        temp_filt_b, 
        temp_filt_a, 
        fs, 
        max_pkg, 
        blind_dur, 
        detect_dur, 
        th, 
        status_pos_set, 
        min_spike_thresh):
    global MAX_PKG_ID
    if MAX_PKG_ID == 0:
        global coeff_a
        global coeff_b
        for pos in range(FILT_LEN):
            coeff_a[pos] = temp_filt_a[pos]
            coeff_b[pos] = temp_filt_b[pos]

        global MAX_PKG_ID
        MAX_PKG_ID = max_pkg
        global BLIND_DURATION
        BLIND_DURATION = <np.int8_t> blind_dur
        global DETECT_DURATION
        DETECT_DURATION = <np.int8_t> detect_dur
        global THRESH_FACTOR
        THRESH_FACTOR = <np.float32_t>th
        global STATUS_POS

        for i in range(STATUS_LEN):
            STATUS_POS[i] = <np.uint8_t>status_pos_set[i]

        global MIN_THRESH
        MIN_THRESH = <np.float32_t>min_spike_thresh
        # print("Initialised constants")
        # print(f"Constant blind: {BLIND_DURATION}, detect: {DETECT_DURATION}, filt_a {coeff_a}, filt_a {coeff_b} and max_pkg {MAX_PKG_ID}")

# cdef short temperatures_stream[1024*(1+4)]

def receive_process(
        UDP_recv_port, 
        PC_IP, 
        CLIENT_RECV_PORT, 
        spike_pipe_a_write: mp.connection.Connection, 
        plot_shared, 
        plot_signal, 
        plot_spike_wavelet, 
        plot_spike_wavelet_id, 
        plot_spikes, 
        plot_loc, 
        recv_command_counter, 
        spike_thresh, 
        status_stream, 
        temp_stream, 
        current_pkg_id, 
        plot_raw=0):

    print(f'PID:{os.getpid()} - Started UDP data receive and process process.')

    cdef np.uint8_t do_plot_raw = plot_raw
    sckt = connect_client(UDP_recv_port, PC_IP, CLIENT_RECV_PORT, 5)
    # try to receive first package
    sckt.recvfrom(2048)
    # once this is done readout is started
    UDP_recv_port.value = 65535

    print("First package received. Start readout process.")
    full_readout(
        sckt, 
        2048, 
        spike_pipe_a_write,
        plot_shared, 
        plot_signal, 
        plot_spike_wavelet, 
        plot_spike_wavelet_id, 
        plot_spikes, 
        plot_loc, 
        recv_command_counter, 
        spike_thresh, 
        status_stream, 
        temp_stream, 
        current_pkg_id, 
        do_plot_raw)

cdef connect_client(UDP_recv_port, PC_IP, CLIENT_RECV_PORT, timeout):
    new_socket = _socket.socket(family=AF_INET, type=SOCK_DGRAM)
    new_socket.bind((PC_IP, 0))

    # Update port variable set by bind, is then sent via USB
    print(new_socket.getsockname()[:2])
    UDP_recv_port.value = new_socket.getsockname()[1]

    new_socket.settimeout(timeout)
    new_socket.setblocking(True)

    # Send an empty package to whitelist firewall
    new_socket.sendto(b'', CLIENT_RECV_PORT)
    print("Created Socket for UDP receive")

    return new_socket

@cython.boundscheck(False)
@cython.initializedcheck(False)
cdef full_readout(
        sckt, 
        int bufferSize, 
        spike_pipe_a_write: mp.connection.Connection, 
        plot_shared: mp.sharedctypes.synchronized, 
        plot_signal: mp.sharedctypes.synchronized, 
        plot_spike_wavelet: mp.sharedctypes.synchronized, 
        plot_spike_wavelet_id: mp.sharedctypes.synchronized, 
        plot_spikes: mp.sharedctypes.synchronized, 
        shared_plot_loc: mp.sharedctypes.synchronized, 
        recv_command_counter: mp.connection.Connection, # mp.sharedctypes.synchronized, 
        spike_thresh: mp.sharedctypes.synchronized, 
        status_stream: mp.sharedctypes.synchronized, 
        temp_stream: mp.sharedctypes.synchronized, 
        current_pkg_id: mp.sharedctypes.synchronized, 
        np.uint8_t do_plot_raw):

    cdef np.float32_t[:] plot_shared_view = plot_shared.get_obj()
    cdef np.float32_t* plot_shared_ptr = <np.float32_t*> &plot_shared_view[0]
    cdef np.float32_t[:] plot_signal_view = plot_signal.get_obj()
    cdef np.float32_t* plot_signal_ptr = <np.float32_t*> &plot_signal_view[0]
    
    cdef np.float32_t[:] plot_spike_wavelet_view
    cdef np.uint32_t[:] plot_spike_wavelet_id_view

    if SAVE_SPIKE_SHAPES:
        plot_spike_wavelet_view = plot_spike_wavelet.get_obj()
        plot_spike_wavelet_id_view = plot_spike_wavelet_id.get_obj()

    cdef np.float32_t* plot_spike_wavelet_ptr
    cdef np.uint32_t* plot_spike_wavelet_id_ptr

    if SAVE_SPIKE_SHAPES: 
        plot_spike_wavelet_ptr = <np.float32_t*> &plot_spike_wavelet_view[0]
        plot_spike_wavelet_id_ptr = <np.uint32_t*> &plot_spike_wavelet_id_view[0]
        print('Initialised with:')

        print(plot_spike_wavelet_id[0])
        plot_spike_wavelet_id_ptr[0] = 1
        print(plot_spike_wavelet_id_view[0])

    else:
        plot_spike_wavelet_ptr = <np.float32_t*> 0
        plot_spike_wavelet_id_ptr = <np.uint32_t*> 0
        

    cdef np.uint8_t[:] plot_spikes_view = plot_spikes.get_obj()
    cdef np.uint8_t* plot_spikes_ptr = <np.uint8_t*> &plot_spikes_view[0]

    cdef np.uint16_t[:] shared_plot_loc_view = shared_plot_loc.get_obj()
    
    cdef np.uint8_t recv_command_counter_num = 0

    cdef np.float32_t[:] spike_thresh_view = spike_thresh.get_obj()
    cdef np.float32_t* spike_thresh_ptr = <np.float32_t*> &spike_thresh_view[0]

    cdef np.uint32_t[:] status_stream_view  = status_stream.get_obj()
    cdef np.uint32_t* status_stream_ptr = <np.uint32_t*> &status_stream_view[0]
    
    cdef np.uint32_t[:] temp_stream_view = temp_stream.get_obj()
    cdef np.uint32_t[:] current_pkg_id_view = current_pkg_id.get_obj()
    cdef np.uint32_t expected_pkg_id = 4194304 # init high value

    cdef np.uint8_t ch = 0
    cdef np.uint8_t n = 0

    cdef np.uint16_t s = 0
    cdef np.uint16_t i = 0

    global coeff_a
    global coeff_b
    global MAX_PKG_ID
    global BLIND_DURATION
    global DETECT_DURATION
    global MAX_VAL
 
    cdef np.float32_t volt_LSB = <np.float32_t>0.195 # in uV

    cdef np.float32_t[CHANNELS] local_thresh 

    for ch in range(CHANNELS):
        local_thresh[ch] = 1e30


    cdef np.uint16_t loc = 0
    cdef np.uint16_t plot_loc = 0
    cdef bytearray server_message = bytearray(2048)

    cdef np.uint32_t EMPTY_VAL = 4194304 # this is 2**22, above MAX_PKG_ID and place-holder which is not 0

    cdef Py_buffer* buff_ptr 
    cdef Py_buffer empty_buff # assign for initialisation
    buff_ptr = &empty_buff
    PyObject_GetBuffer(server_message, buff_ptr, 0)
    cdef char* char_ptr = <char*>buff_ptr.buf
    cdef BUFF_TYPE* int_ptr = <BUFF_TYPE*>buff_ptr.buf
    cdef BUFF_TYPE[:] int_view = <BUFF_TYPE[:1024]>int_ptr

    cdef np.uint32_t* status_ptr = <np.uint32_t*> &int_view[1]
    cdef np.uint16_t* command_ptr = <np.uint16_t*> &int_view[41]
    cdef np.uint8_t TEMP_BUF_LEN = 4*8
    cdef np.uint8_t temp_loc = 0
    cdef np.uint8_t* recv_command_counter_ptr = <np.uint8_t*> &char_ptr[1]

    cdef np.float32_t[5] SG = [-0.08571429, 0.34285714, 0.48571429, 0.34285714, -0.08571429] 

    assert N_LEN >= FILT_LEN
    assert N_LEN >= len(SG)

    cdef np.float32_t[N_LEN][CHANNELS] filtered_out 
    cdef np.float32_t[N_LEN][CHANNELS] filtered_hp

    cdef np.float32_t[N_LEN+K_SNEO][CHANNELS] kNEO 
    cdef np.float32_t[N_LEN+K_SNEO][CHANNELS] SNEO 

    cdef np.float32_t[BW_LEN] BW 


    cdef np.uint8_t[CHANNELS] spike_wavelet_pos
    cdef np.uint8_t[CHANNELS] spike_wavelet_id

    cdef np.uint16_t[CHIP_NUM] stim_command_el

    cdef np.uint8_t pos_sneo_loc = 0

    cdef np.uint8_t out_loc = 0
    cdef np.uint8_t sneo_loc = 0

    cdef np.uint32_t pkg_id = 0
    cdef np.uint8_t[CHANNELS] spike_detect
    cdef np.uint8_t[:] spike_detect_view = spike_detect

    cdef np.int16_t data_stream[BUFF_LEN][(CHANNELS+2)]
    cdef np.int16_t [:,:] stream_view = data_stream

    cdef np.uint8_t[4] send_spike
    cdef np.uint8_t[:] send_spike_view = send_spike
    send_spike_view[:] = 0
    cdef np.int8_t[CHANNELS] blind_electrodes_array
    cdef np.float32_t[CHANNELS] max_peak

    for ch in range(CHANNELS):
        spike_detect[ch] = 0
        blind_electrodes_array[ch] = BLIND_DURATION
        max_peak[ch] = 0.
        spike_wavelet_id[ch] = 0
        spike_wavelet_pos[ch] = SPIKE_WAVELET_LEN

        for n in range(N_LEN):
            filtered_out[n][ch] = 0.
            filtered_hp[n][ch] = 0.

        for n in range(N_LEN+K_SNEO):
            kNEO[n][ch] = 0.
            SNEO[n][ch] = 0.
    
    for n in range(CHIP_NUM):
        stim_command_el[n] = 0

    for n in range(CHIP_NUM):
        stim_command_el[n] = 0

    for n in range(BW_LEN):
        if n <= BW_LEN/2:
            BW[n] = 2*n/BW_LEN
        else:
            BW[n] = 2-2*n/BW_LEN
    cdef np.float32_t[:, :] filtered_hp_view = filtered_hp

    cdef np.float32_t[:, :] filtered_out_view = filtered_out

    cdef np.float32_t[:] BW_view = BW
    cdef np.float32_t* SNEO_ptr = <np.float32_t*>PyMem_Malloc(CHANNELS*4*(N_LEN+K_SNEO))
    cdef np.float32_t[:,:] SNEO_view = <np.float32_t[:(N_LEN+K_SNEO),:CHANNELS]>SNEO_ptr
    cdef np.float32_t* kNEO_ptr = <np.float32_t*>PyMem_Malloc(CHANNELS*4*(N_LEN+K_SNEO))
    cdef np.float32_t[:,:] kNEO_view = <np.float32_t[:(N_LEN+K_SNEO),:CHANNELS]>kNEO_ptr

    for n in range(N_LEN+K_SNEO):    
        SNEO[n] = SNEO_ptr+n*CHANNELS
        kNEO[n] = kNEO_ptr+n*CHANNELS
        # SNEO_view[n] = <np.float32_t[:CHANNELS]> SNEO_ptr # <np.float32_t[:CHANNELS]>
        # SNEO_ptr = <np.float32_t*> SNEO_ptr
    for ch in range(CHANNELS):
        for n in range(N_LEN+K_SNEO):
            kNEO[n][ch] = 0.
            SNEO[n][ch] = 0.

    for i in range(1024):
        server_message[i*2] = i % 256
        server_message[i*2+1] = i // 256
    for i in range(1024):
        assert int_view[i] == i
    # print(f"Constant blind: {BLIND_DURATION}, detect: {DETECT_DURATION}, filt_a {coeff_a}, filt_a {coeff_b} and max_pkg {MAX_PKG_ID}")

    # ---------------------------------Loop----------------------------------------------------------------------------------------------
    while True:
        # sneo is always delayed
        pos_sneo_loc = (sneo_loc-K_SNEO) % (N_LEN+K_SNEO)
    
        # receive data
        sckt.recvfrom_into(server_message)
    
        # update shared current package id
        current_pkg_id[0] = status_ptr[0]
        pkg_id = <np.uint32_t> ((status_ptr[0] - DETECT_DURATION - K_SNEO) % MAX_PKG_ID) # for negative ID

        # update status bytes
        for s in range(STATUS_LEN):
            # with status_stream:
            status_stream[plot_loc*STATUS_LEN+s] = status_ptr[STATUS_POS[s]]       

        IF ONLY_STIM:
            if status_ptr[0] > expected_pkg_id:
                print(f'Warning: Dropped {status_ptr[0] - expected_pkg_id} packages')
            expected_pkg_id = status_ptr[0]+1

            # update package and receive counters
            if recv_command_counter_num != recv_command_counter_ptr[0]:
                # print('Sending recv counter', <np.uint8_t>char_ptr[1])
                recv_command_counter.send_bytes(char_ptr[1:2])
                recv_command_counter_num = recv_command_counter_ptr[0]

            plot_loc = (plot_loc+1) % OUT_BUFF_LEN
            shared_plot_loc[0] = plot_loc

            continue



        if not char_ptr[2]: # every 255 samples
            with spike_thresh:
                if (local_thresh[0] != spike_thresh[0]) and spike_thresh[0]:
                    for ch in range(CHANNELS):
                        local_thresh[ch] = spike_thresh[ch]
        
        if SAVE_SPIKE_SHAPES:
            plot_spike_wavelet.acquire()

        # iterate over channels, parallelised
        for ch in prange(
                CHANNELS, 
                nogil=True, 
                num_threads=5, # one uses around 80% of one CPU core
                schedule='static', 
                chunksize=48
            ): 
            # from 466 on took last 2 bytes, so 468 continuous and skip 1 # range(CHANNELS): #
            # convert value
            spike_detect[ch] = 0
            stream_view[loc][2+ch] = int_view[234+2*ch] - 2**15

            # here is standard filtering ----------------------------------------------------------------------------------------
            # apply IIR high pass

            filtered_hp_view[out_loc,ch] = coeff_b[0] * stream_view[loc,2+ch]
            for n in range(1,FILT_LEN):
                filtered_hp_view[out_loc,ch] = (
                    filtered_hp_view[out_loc,ch] 
                    + coeff_b[n] * stream_view[loc-n,2+ch] 
                    - coeff_a[n] * filtered_hp_view[out_loc-n,ch]) 

            # convolve with SG
            filtered_out_view[out_loc,ch] = 0.
            for n in range(5):
                filtered_out_view[out_loc,ch] = (
                    filtered_out_view[out_loc,ch] 
                    + filtered_hp_view[out_loc+n-(5-1),ch] * SG[5-1-n]) 

            IF USE_SNEO:
                # get kSNEO
                # signal goes from -k to +k
                kNEO_view[pos_sneo_loc, ch] = (
                    filtered_out_view[out_loc-K_SNEO, ch] * filtered_out_view[out_loc-K_SNEO, ch] 
                    - filtered_out_view[out_loc, ch] * filtered_out_view[out_loc-2*K_SNEO, ch])

                # sig.windows.bartlett(k)
                # conv(kNEO[sneo_loc-(5*K_SNEO):sneo_loc-K_SNEO+1], BW, <np.float32_t*>SNEO[sneo_loc-K_SNEO], 4*K_SNEO+1)
                SNEO_view[pos_sneo_loc, ch] = 0.
                for n in range(BW_LEN):
                    SNEO_view[pos_sneo_loc, ch] = (
                        SNEO_view[pos_sneo_loc, ch]
                        + kNEO_view[pos_sneo_loc-(BW_LEN-1)+n, ch] * BW_view[BW_LEN-1-n])
                # no smooting
                # SNEO_view[pos_sneo_loc, ch] = kNEO_view[sneo_loc-K_SNEO, ch]

            ## Spike Detection --------------------------------------------------------------------------------
            # if channel is still blinded ignore
            if blind_electrodes_array[ch] > 0:
                # reduce blind duration sample counter
                blind_electrodes_array[ch] = blind_electrodes_array[ch] - 1
            else:
                # if currently in onset
                if blind_electrodes_array[ch] < 0:
                    # when max is surpassed new onset
                    IF USE_SNEO:
                        if SNEO_view[pos_sneo_loc,ch] > max_peak[ch]:
                            # new onset here
                            blind_electrodes_array[ch] = -DETECT_DURATION
                            max_peak[ch] = SNEO_view[pos_sneo_loc,ch]   

                            # reset wavelet position to after delay
                            spike_wavelet_pos[ch] = 0
                        else:
                            blind_electrodes_array[ch] = blind_electrodes_array[ch] + 1  

                            # copy value 
                            if SAVE_SPIKE_SHAPES:                  
                                if spike_wavelet_pos[ch] < SPIKE_WAVELET_LEN: 
                                    plot_spike_wavelet_ptr[ch*SPIKE_WAVELET_BUF+spike_wavelet_id[ch]*SPIKE_WAVELET_LEN+spike_wavelet_pos[ch]] = (
                                        filtered_out_view[out_loc-SPIKE_WAVELET_DELAY,ch]) # filtered_out_view[out_loc-K_SNEO,ch]) # SNEO_view[pos_sneo_loc, ch]) # 
                                    spike_wavelet_pos[ch] = spike_wavelet_pos[ch] + 1

                            if blind_electrodes_array[ch] == 0:
                                # blind electrodes carries number of samples on which electrode is blinded and cannot detect spikes
                                blind_electrodes_array[ch] = BLIND_DURATION - DETECT_DURATION # ensure that positive?
                                spike_detect[ch] = 1

                                # fill in front and increase wavelet id number
                                if SAVE_SPIKE_SHAPES:                                    
                                    while spike_wavelet_pos[ch] < SPIKE_WAVELET_LEN:
                                        plot_spike_wavelet_ptr[ch*SPIKE_WAVELET_BUF+spike_wavelet_id[ch]*SPIKE_WAVELET_LEN+spike_wavelet_pos[ch]] = (
                                            filtered_out_view[out_loc-SPIKE_WAVELET_DELAY+spike_wavelet_pos[ch]-(DETECT_DURATION-1),ch]) # filtered_out_view[out_loc-K_SNEO,ch]) # SNEO_view[pos_sneo_loc, ch]) # 
                                        spike_wavelet_pos[ch] = spike_wavelet_pos[ch] + 1
                                    plot_spike_wavelet_id_ptr[ch*SPIKE_WAVELET_NUM + spike_wavelet_id[ch]] = pkg_id
                                    spike_wavelet_id[ch] = (spike_wavelet_id[ch]+1) % SPIKE_WAVELET_NUM
                    ELSE:
                        if abs(filtered_out_view[out_loc,ch]) > max_peak[ch]:
                            # new onset here
                            blind_electrodes_array[ch] = -DETECT_DURATION
                            max_peak[ch] = abs(filtered_out_view[out_loc,ch])

                        # reset wavelet position to after delay
                        spike_wavelet_pos[ch] = 0
                else:
                    blind_electrodes_array[ch] = blind_electrodes_array[ch] + 1  

                    # copy value 
                    if SAVE_SPIKE_SHAPES:                  
                        if spike_wavelet_pos[ch] < SPIKE_WAVELET_LEN: 
                            plot_spike_wavelet_ptr[ch*SPIKE_WAVELET_BUF+spike_wavelet_id[ch]*SPIKE_WAVELET_LEN+spike_wavelet_pos[ch]] = (
                                filtered_out_view[out_loc-SPIKE_WAVELET_DELAY,ch]) # filtered_out_view[out_loc-K_SNEO,ch]) # SNEO_view[pos_sneo_loc, ch]) # 
                            spike_wavelet_pos[ch] = spike_wavelet_pos[ch] + 1

                    if blind_electrodes_array[ch] == 0:
                        # blind electrodes carries number of samples on which electrode is blinded and cannot detect spikes
                        blind_electrodes_array[ch] = BLIND_DURATION - DETECT_DURATION # ensure that positive?
                        spike_detect[ch] = 1

                        # fill in front and increase wavelet id number
                        if SAVE_SPIKE_SHAPES:                                    
                            while spike_wavelet_pos[ch] < SPIKE_WAVELET_LEN:
                                plot_spike_wavelet_ptr[ch*SPIKE_WAVELET_BUF+spike_wavelet_id[ch]*SPIKE_WAVELET_LEN+spike_wavelet_pos[ch]] = (
                                    filtered_out_view[out_loc-SPIKE_WAVELET_DELAY+spike_wavelet_pos[ch]-(DETECT_DURATION-1),ch]) # filtered_out_view[out_loc-K_SNEO,ch]) # SNEO_view[pos_sneo_loc, ch]) # 
                                spike_wavelet_pos[ch] = spike_wavelet_pos[ch] + 1
                            plot_spike_wavelet_id_ptr[ch*SPIKE_WAVELET_NUM + spike_wavelet_id[ch]] = pkg_id
                            spike_wavelet_id[ch] = (spike_wavelet_id[ch]+1) % SPIKE_WAVELET_NUM                                
                    # if channel threshold is crossed and electrode not blinded
                    else:
                        IF USE_SNEO:
                            if SNEO_view[pos_sneo_loc,ch] > (local_thresh[ch]):
                                # onset here
                                blind_electrodes_array[ch] = -DETECT_DURATION
                                max_peak[ch] = SNEO_view[pos_sneo_loc,ch] 
                        ELSE:
                            if abs(filtered_out_view[out_loc,ch]) > local_thresh[ch]:
                                # onset here
                                blind_electrodes_array[ch] = -DETECT_DURATION
                                max_peak[ch] = abs(filtered_out_view[out_loc,ch])
                # copy to plot
            
                # with plot_signal:
                IF USE_SNEO:
                    plot_signal_ptr[plot_loc*CHANNELS+ch] = SNEO_view[pos_sneo_loc, ch] # filtered_out[out_loc][ch] # 
                ELSE:
                    plot_signal_ptr[plot_loc*CHANNELS+ch] = filtered_out[out_loc][ch]
                # with plot_shared:
                if do_plot_raw:            
                    plot_shared_ptr[plot_loc*CHANNELS+ch] = <np.float32_t>data_stream[loc][2+ch]*volt_LSB
                else:
                    plot_shared_ptr[plot_loc*CHANNELS+ch] = filtered_out[out_loc][ch]*volt_LSB
                
                # with plot_spikes:
                plot_spikes_ptr[plot_loc*CHANNELS+ch] = spike_detect[ch]


        for ch in range(7):
            temp_stream_view[ch + TEMP_DATA_LEN*temp_loc] = status_ptr[5+ch]

        for ch in range(4):
            temp_stream_view[7+ch + TEMP_DATA_LEN*temp_loc] = <np.uint32_t> int_view[27 + 2*ch]

        for ch in range(4):
            temp_stream_view[11+ch + TEMP_DATA_LEN*temp_loc] = <np.uint32_t> int_view[28 + 2*ch]

        # send out spikes to pipe
        
        send_spike[1] = pkg_id % 256 # char_ptr[2]
        send_spike[2] = pkg_id >> 8 % 256 # char_ptr[3]
        send_spike[3] = pkg_id >> 16 % 256 # char_ptr[4]

        for ch in range(CHANNELS): # needs gil
            if spike_detect[ch] == 1:
                send_spike[0] = ch
                spike_pipe_a_write.send_bytes(send_spike_view[:4])
                spike_detect[ch] = 0

        if status_ptr[0] > expected_pkg_id:
            print(f'Warning: Dropped {status_ptr[0] - expected_pkg_id} packages')
        expected_pkg_id = status_ptr[0]+1

        # update package and receive counters
        if recv_command_counter_num != recv_command_counter_ptr[0]:
            # print('Sending recv counter', <np.uint8_t>char_ptr[1])
            recv_command_counter.send_bytes(char_ptr[1:2])
            recv_command_counter_num = recv_command_counter_ptr[0]

        # move readouts
        out_loc = (out_loc+1) % (N_LEN) # FILT_LEN
        sneo_loc = (sneo_loc+1) % (N_LEN+K_SNEO)
        loc = (loc+1) % BUFF_LEN
        plot_loc = (plot_loc+1) % OUT_BUFF_LEN
        shared_plot_loc[0] = plot_loc
        temp_loc = (temp_loc+1) % TEMP_BUF_LEN




def update_MAD(
        sneo_shared, 
        filtered_shared, 
        update_time, 
        spike_thresh, 
        update_thresh_bool, 
        shared_noise, 
        mea_mapping, 
        noise_bins, 
        noise_max
    ): 
    import pickle
    ''' Update median of signal on all electrodes, {CHANNELS} elements vector '''
    cdef np.float32_t[CHANNELS] thresh
    global THRESH_FACTOR
    global MIN_THRESH
    cdef np.uint8_t ch = 0
    cdef np.uint8_t i = 0
    with spike_thresh:
        thresh[ch] = spike_thresh[ch]
    if THRESH_FACTOR == 0:
        THRESH_FACTOR = 1
    cdef np.float32_t lower_lim = MIN_THRESH/THRESH_FACTOR # uV
    median_array = 2 * lower_lim * pnp.ones((1,CHANNELS))
    std_vector = pnp.zeros((CHANNELS))
    cdef np.uint8_t init_counter = 5

    for ch in range(CHANNELS):
        thresh[ch] = THRESH_FACTOR*lower_lim

    while True:
        if init_counter:
            time.sleep(.5)
            init_counter -= 1
        else: 
            time.sleep(update_time)

        if update_thresh_bool.value:
            if init_counter:
                median_array = median_array*0.75 + 0.25 * pnp.median(
                    pnp.abs(
                        pnp.asarray(sneo_shared[:OUT_BUFF_LEN//4*CHANNELS], dtype=pnp.float32)).reshape(-1,CHANNELS), 
                    axis=0)
            else:
                median_array = median_array*0.75 + 0.25 * pnp.median(
                    pnp.abs(
                        pnp.asarray(sneo_shared, dtype=pnp.float32)).reshape(-1,CHANNELS), 
                    axis=0)
            median_array[0,median_array[0,:]<lower_lim] = lower_lim
            with spike_thresh:
                for ch in range(CHANNELS):
                    spike_thresh[ch] = THRESH_FACTOR * median_array[0,ch]
        std_vector = pnp.std(pnp.asarray(filtered_shared[:OUT_BUFF_LEN//16*CHANNELS], dtype=pnp.float32).reshape(-1,CHANNELS), axis=0)
        std_vector[std_vector>noise_max] = noise_max

        with shared_noise:
            for mea_id in range(mea_mapping.shape[0]):
                shared_noise[mea_id*noise_bins:(mea_id+1)*noise_bins] = pnp.histogram(
                    std_vector[mea_mapping[mea_id]], bins=noise_bins, range=(0,noise_max))[0]


def c_spike_poll_process(
    spike_pipe: mp.connection.Connection,   
    segment_ids: mp.sharedctypes.synchronized, 
    detected_spike_share_send: mp.connection.Connection,   
    map_matrix, 
    NETWORK_NUM, 
    ELECTRODES, 
    store_event, 
    period_over_event, 
    spont_event, 
):
    print(f'PID:{os.getpid()} - Started spike poll process.')
    # store mode 0: discard all, 1: save all, 2: segment, segment_ids [start, end]
    cdef bytearray spike_buffer_bytes = bytearray(5)
    spike_buffer_bytes[4] = 0

    global MAX_PKG_ID
    cdef np.int32_t MAX_PKG_ID_half = MAX_PKG_ID//2

    cdef Py_buffer* buff_ptr 
    cdef Py_buffer empty_buff # assign for initialisation
    buff_ptr = &empty_buff
    PyObject_GetBuffer(spike_buffer_bytes, buff_ptr, 0)
    cdef char* char_ptr = <char*>buff_ptr.buf
    cdef np.uint32_t* pkg_ptr = <np.uint32_t*>&char_ptr[1]

    cdef np.uint32_t spont_lim = 0
    cdef np.uint8_t low_lim = 0

    cdef np.uint32_t[:] segment_ids_view = segment_ids.get_obj()
    cdef np.uint32_t* segment_ids_ptr = <np.uint32_t*>&segment_ids_view[0]

    cdef np.uint8_t i = 0
    cdef np.uint8_t j = 0

    cdef np.uint16_t n = 0
    cdef np.float32_t pkg_in_ms = 1e3/FS

    networks_spike_mat = pnp.empty((NETWORK_NUM, ELECTRODES), dtype=object)
    for i in range(NETWORK_NUM):
        for j in range(ELECTRODES):
            networks_spike_mat[i,j] = tuple()
    cdef np.uint32_t list_len = 0 # delete every 240*

    cdef np.uint32_t[MAX_LIST_LEN] spike_store_pkg_a
    cdef np.uint8_t[MAX_LIST_LEN] spike_store_ch_a

    cdef np.uint8_t* current_ch_ptr = &spike_store_ch_a[0]
    cdef np.uint32_t* current_pkg_ptr = &spike_store_pkg_a[0]

    cdef np.uint32_t local_segment_id = 0

    for list_len in range(MAX_LIST_LEN):
        spike_store_ch_a[list_len] = 0
        spike_store_pkg_a[list_len] = 0

    list_len = 0

    cdef np.uint32_t[:] spike_store_pkg_view = spike_store_pkg_a
    cdef np.uint8_t[:] spike_store_ch_view = spike_store_ch_a

    cdef np.uint32_t max_spont_list_delay = 50_000 # 26_000 # 1.5 sec and fits uint16


    while True:
        if store_event.is_set(): 
            if spike_pipe.poll():
                spike_pipe.recv_bytes_into(spike_buffer_bytes)
                       
                if pkg_ptr[0] > segment_ids[1]: # this is the case for stimulation/relevant period
                    if not period_over_event.is_set():
                        local_segment_id = segment_ids[0]

                        list_len = min(list_len, MAX_LIST_LEN)
                        for n in range(list_len):
                            networks_spike_mat[map_matrix[spike_store_ch_a[n]][0], map_matrix[spike_store_ch_a[n]][1]] += (
                                <np.float32_t> (spike_store_pkg_a[n] - local_segment_id) * pkg_in_ms, )
                        print(pkg_ptr[0])
                        print(segment_ids[1])
                        print('In stim phase')
                        detected_spike_share_send.send(networks_spike_mat)
                        
                        for i in range(NETWORK_NUM):
                            for j in range(ELECTRODES):
                                networks_spike_mat[i,j] = tuple()
                        list_len = 0     

                        period_over_event.set()
                    
                elif pkg_ptr[0] < segment_ids[0]: # if smaller                            
                    pass
                else: # for spontaneous spike readout or inside period case
                    current_ch_ptr[list_len] = char_ptr[0]
                    current_pkg_ptr[list_len] = pkg_ptr[0]

                    if spont_event.is_set():
                        if not list_len:
                            spont_lim = (pkg_ptr[0] + max_spont_list_delay)
                            if spont_lim > MAX_PKG_ID:
                                low_lim = 1
                                spont_lim = spont_lim - MAX_PKG_ID
                            else:
                                low_lim = 0

                        list_len += 1
                        if (
                                list_len >= MAX_LIST_LEN 
                                or ((not (low_lim)) and pkg_ptr[0] > spont_lim) # past limit
                                or (low_lim and (pkg_ptr[0] < spont_lim)) # or reset to start number if limit past max_pkg_id
                        ):
                            # copy_thread = threading.Thread(
                            #     target = copy_data_to_pipe, 
                            #     args = (
                            #         detected_spike_share_send, 
                            #         spike_store_pkg_view[:list_len], 
                            #         spike_store_ch_view[:list_len]
                            #     )
                            # )
                            # copy_thread.start()
                            print(list_len)
                            for n in range(list_len):
                                print(spike_store_ch_a[n])
                                print(spike_store_ch_view[n])

                            detected_spike_share_send.send(
                                (
                                    pnp.array(spike_store_ch_view[:list_len], copy=True, dtype=pnp.uint8), 
                                    pnp.array(spike_store_pkg_view[:list_len], copy=True, dtype=pnp.uint32)
                                )
                            )
                            
                            current_ch_ptr = &spike_store_ch_a[0]
                            current_pkg_ptr = &spike_store_pkg_a[0]      

                            spike_store_pkg_view = spike_store_pkg_a
                            spike_store_ch_view = spike_store_ch_a

                            list_len = 0  
                    else:
                        list_len += 1
        else:
            if spike_pipe.poll():
                spike_pipe.recv_bytes_into(spike_buffer_bytes)

                list_len = 0


cpdef copy_data_to_pipe(
        detected_spike_share_send: mp.connection.Connection, 
        np.uint32_t[:] spike_store_pkg_view, 
        np.uint8_t[:] spike_store_ch_view,
    ):

    detected_spike_share_send.send(
        (
            pnp.array(spike_store_ch_view, copy=True, dtype=pnp.uint8), 
            pnp.array(spike_store_pkg_view, copy=True, dtype=pnp.uint32)
        )
    )


cpdef c_map_spikes_to_matrix_tuple(
        spike_store_ch,
        spike_store_pkg, 
        np.uint32_t start_id, 
        networks_spike_mat_empty, 
        map_matrix, 
        np.uint32_t list_len
    ):
    cdef np.uint16_t n = 0
    cdef np.float32_t pkg_in_ms = 1e3/FS

    print(spike_store_ch[:list_len])
    print(type(spike_store_ch))
    network_elecs = map_matrix[spike_store_ch[:list_len]]
    
    # TODO: if assembling from two alternating packages do here 
    list_len = min(list_len, MAX_LIST_LEN)
    for n in range(list_len):
        networks_spike_mat_empty[network_elecs[n][0], network_elecs[n][1]] += (
            <np.float32_t> (spike_store_pkg[n] - start_id) * pkg_in_ms, )
    return networks_spike_mat_empty


