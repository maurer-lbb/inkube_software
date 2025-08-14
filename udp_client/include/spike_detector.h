#ifndef SPIKE_DETECTOR_H
#define SPIKE_DETECTOR_H

#include "spike_event.h"
#include "fpga_constants.h"
#include "inkube_package.h"
#include "helper_functions.h"

#include <thread>
#include <atomic>
#include <string>
#include <vector>
#include <array>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <unistd.h>
#include <stdexcept>
#include <shared_mutex>
#include <cstring>  // Include for std::memcpy
#include <iostream>
#include <chrono>
#include <poll.h>
#include <algorithm>
#include <math.h>

#define FILT_LEN 3 // IIR filter
#define BUFFER_LENGTH 256 // this is for threshold calculation

#define FIR_LEN 1 // 31
#define SG_LEN 7 // savitzky golay (polynominal fit)

#define BLIND_DURATION 25 // blind the electrode after a spike for some samples
#define DETECT_DURATION 20 // 1.2 ms has to be smaller than BLIND, within this window it looks for the maximum, waveshape is shifted by this

#define MIN_THRESH 20.f // make sure this is float!


// #define USE_WAVELET

#define THRESH_SUBSAMPLING 1
#define RAW_ARTEFACT_THRESH 2000

// Define multiple scales
#ifdef USE_WAVELET
#define NUM_SCALES 3
#define WAVELET_SIZE 34
#define THRESH_FACTOR 15. // make sure this is float!
#else
#define THRESH_FACTOR 7.f // make sure this is float!
#endif

#define SAVGOL
// #define TRIGGER_ARTEFACT


class SpikeDetector {
public:
    explicit SpikeDetector(uint8_t chunk_id);
    ~SpikeDetector();

    void start_processing();  // Start receiving and processing data
    void stop_processing();   // Stop receiving data

    void connect_to_sockets();  // Connect to necessary UNIX sockets
    void accept_connections();

    void update_threshold(const float alpha_mov_avg);
    bool is_ready() const { return ready_; }

private:
    int thresh_socket_fd_ = -1;
    bool connect_thresh_socket();
    
    float thresh_factor_ = THRESH_FACTOR;  // Default from your #define
    bool update_threshold_enabled_ = true;

    void check_thresh_messages();  // New helper method

    std::atomic<bool> ready_{false};  // Synchronization flag
    std::atomic<bool> running_;  // Control flag for processing
    std::thread connection_thread_;  // Thread for handling connections

    void process_data(const InkubePackageChunk& chunk);  // Process a single data chunk

    int raw_socket_fd_ = 0;    // File descriptor for the raw UNIX socket
    int plot_socket_fd_ = 0;   // File descriptor for the plotting UNIX socket
    int spike_socket_fd_ = 0;  // File descriptor for internal spike sharing

    uint8_t chunk_id_;  // ID of the chunk this SpikeDetector handles

    // --------------------------------------------------------------
    // Spike detection definitions 

    // gentle bessel filter
    // 1st order, cutoff 500Hz
    // const float coeff_a[2] = {1.0, -0.8337};
    // const float coeff_b[2] = {0.9168, -0.9168};

    // 2nd order 
    // const float coeff_a[3] = {1.0, -1.6046, 0.6703};
    // const float coeff_b[3] = {0.8167, -1.6334, 0.8167};


    // // 2nd Order Butterworth High-Pass Filter Coefficients
    const float coeff_b[3] = { 0.9260957937, -1.8521915873, 0.9260957937 };
    const float coeff_a[3] = { 1.0000000000, -1.8467222773, 0.8576608974 };

    // 3rd Order Butterworth High-Pass Filter Coefficients
    // const float coeff_b[4] = { 0.8970644114, -2.6911932341, 2.6911932341, -0.8970644114 };
    // const float coeff_a[4] = { 1.0000000000, -2.7829573320, 2.5888334215, -0.8047245374 };

    // 3rd Order Butterworth band-Pass Filter Coefficients
    // const float coeff_b[7] = { 0.0540598481, 0.0000000000, -0.1621795444, 0.0000000000, 0.1621795444, 0.0000000000, -0.0540598481 };
    // const float coeff_a[7] = { 1.0000000000, -3.8366812192, 6.2270507587, -5.6477133058, 3.1014242290, -0.9699557904, 0.1266122055 };
         

    const float fir_coeff[1] = {1.};
    // const float fir_coeff[31] = {
    //     0.001533, 0.000408, -0.002925, 0.001212, 0.005836, -0.006741, 
    //     -0.007674, 0.018420, 0.002681, -0.035773, 0.018007, 0.054968, 
    //     -0.072852, -0.070100, 0.305566, 0.574867, 0.305566, -0.070100, 
    //     -0.072852, 0.054968, 0.018007, -0.035773, 0.002681, 0.018420, 
    //     -0.007674, -0.006741, 0.005836, 0.001212, -0.002925, 0.000408, 
    //     0.001533
    // };

    // Savitzky-Golay 2nd order poly, 7 samples
    #ifdef SAVGOL
    const float SG[SG_LEN] = {-0.0952381, 0.14285714, 0.28571429, 0.33333333,0.28571429, 0.14285714, -0.0952381};
    #endif

    uint8_t stim_active[CHUNKED_CHANNELS];
    float artefact_peak[CHUNKED_CHANNELS];

    float max_peak[CHUNKED_CHANNELS];
    float local_threshold[CHUNKED_CHANNELS];
    
    int blind_electrodes_array[CHUNKED_CHANNELS];

    std::vector<float> raw_data;     // Flat buffer
    std::vector<float> movavg_data;     // Flat buffer
    std::vector<float> filtered_out; // Flat buffer
    std::vector<float> filtered_hp;  // Flat buffer
    std::vector<float> thresh_signal; // Flat buffer

    float last_pkg_id_plot; 

    #ifdef USE_WAVELET
    // Energy calculation from wavelet decomposition
    std::vector<float> energy_signal;  // Energy signal for spike detection
    
    // Wavelets for different scales
    std::vector<std::vector<float>> scaled_wavelets;
    
    // Initialize wavelet scales
    void initialize_wavelets();
    void calculate_energy();
    
    // For plotting energy signal
    inline float* get_energy_ptr(size_t index) { return &energy_signal[index * CHUNKED_CHANNELS]; }
    #endif
    
    // For plotting
    inline float* get_raw_ptr(size_t index) { return &raw_data[index * CHUNKED_CHANNELS]; }
    inline float* get_filtered_ptr(size_t index) { return &filtered_out[index * CHUNKED_CHANNELS]; } 

    uint16_t raw_loc = 0;
    uint8_t plot_loc = 0;

    uint8_t out_loc = 0;

    uint32_t current_package_id = 0;
    uint16_t current_cycle = 0;

    SpikeEvent detected_spike;
};

#endif // SPIKE_DETECTOR_H



