#ifndef INKUBE_PACKAGE_H
#define INKUBE_PACKAGE_H

#include <array>
#include <cstdint>
#include <vector>
#include <cstring>  // For memset
#include <iostream>

#include "fpga_constants.h"

#define CHUNKED_CHANNELS 60
#define NUM_CHANNEL_CHUNKS 4
#define PKG_SEND_OUT 4// 17 
#define SEND_ENV 10

#define RAW_SOCKET_BASE_PATH "/tmp/raw_data_socket"
#define SEGMENTATION_SOCKET_PATH "/tmp/segmentation_socket"
#define RECV_PKG_SOCKET_PATH "/tmp/recv_pkg_socket"
#define ENV_SOCKET_PATH "/tmp/env_socket"

#define SPIKE_SOCKET_INTERNAL_BASE_PATH "/tmp/spike_socket"
#define PLOT_SOCKET_INTERNAL_BASE_PATH "/tmp/plot_socket"
#define PLOT_SOCKET_EXTERNAL_PATH "/tmp/plot_ext_socket"

#define EXTERNAL_PLOT_CHUNK_LENGTH 128
#define INTERNAL_PLOT_CHUNK_LENGTH 1
#define PLOT_SUBSAMPLING 1

// for spike communication
#define ZMQ_SPIKE_ENDPOINT "tcp://*:5556"
#define ZMQ_PACKAGE_ENDPOINT "tcp://*:5557"
#define ZMQ_USBCOM_ENDPOINT "tcp://*:5558"
#define ZMQ_ENV_ENDPOINT "tcp://*:5551"

#define SPIKE_BATCH_INTERVAL_MS 1

#define ZMQ_DATA_ENDPOINT1 "tcp://*:6001"
#define ZMQ_DATA_ENDPOINT2 "tcp://*:6002"
#define ZMQ_DATA_ENDPOINT3 "tcp://*:6003"
#define ZMQ_DATA_ENDPOINT4 "tcp://*:6004"
#define ZMQ_THRESH_ENDPOINT "tcp://localhost:5559"

struct SpikePackage {
    uint32_t header;
};

struct PlotPackageInfo {
    const uint32_t header_pre = 0xff0102ff;
    const uint32_t header_post = 0xff0403ff;
    uint16_t fs;
    uint8_t subsampling;
    uint8_t num_channels;
    uint8_t num_samples;
};

struct PlotPackage {
    std::vector<float> buffer;  // Single contiguous buffer for all data

    float* detection_data;  // Pointer to detection data inside buffer
    float* signal_data;     // Pointer to signal data inside buffer
    float* threshold_data;  // Pointer to threshold data inside buffer
    float* package_id;   // Pointer to package ID inside buffer

    // Constructor: Allocate a single contiguous block and assign pointers
    PlotPackage() : buffer(get_total_elements(), 0.0f) {
        detection_data = buffer.data();
        signal_data = detection_data + NUM_CHANNELS * EXTERNAL_PLOT_CHUNK_LENGTH;
        threshold_data = signal_data + NUM_CHANNELS * EXTERNAL_PLOT_CHUNK_LENGTH;

        // Place package_id at the end of the buffer
        package_id = threshold_data + NUM_CHANNELS;
    }

    // Get total number of elements (floats) required
    static constexpr size_t get_total_elements() {
        return 2 * NUM_CHANNELS * EXTERNAL_PLOT_CHUNK_LENGTH + NUM_CHANNELS + 1;
    }

    // Get total byte size
    size_t get_total_size() const {
        return buffer.size() * sizeof(float);
    }

    // Get raw pointer to contiguous memory for sending
    const void* get_raw_data() const {
        return buffer.data();
    }
};

#pragma pack(push, 1) // Ensure no padding issues
struct EnvPackage {
    std::vector<uint32_t> buffer; 
    uint32_t* temp_data;
    EnvPackage() : buffer(TEMP_DATA_LEN, 0) {
        temp_data = buffer.data();
    }
};
#pragma pack(pop)


#pragma pack(push, 1) // Ensure no padding issues
struct CommPackage {
    uint32_t package_id;  // 4-byte package ID (from UDPReceiver)
};
#pragma pack(pop)

// Define the InkubePackage struct
struct InkubePackage {
    uint32_t package_id;              // Package ID (32-bit unsigned integer)
    uint8_t recv_id;                  // Receiver ID (8-bit unsigned integer) # send this out directly
    std::array<int16_t, NUM_CHANNELS> voltage_data; // Voltage data (240 channels of uint16_t)
};

// Define the InkubePackage struct
struct InkubePackageChunk {
    uint32_t package_id;              // Package ID (32-bit unsigned integer)
    std::array<int16_t, CHUNKED_CHANNELS> voltage_data; // Voltage data (240 channels of uint16_t)
    uint8_t start_ch_id;
} __attribute__((packed));  // Prevent padding and ensure proper memory layout

#endif // INKUBE_PACKAGE_H
