#include "spike_detector.h"

// Constructor
SpikeDetector::SpikeDetector(uint8_t chunk_id)
    : raw_data(BUFFER_LENGTH * CHUNKED_CHANNELS, 0.0f), 
      movavg_data(BUFFER_LENGTH * CHUNKED_CHANNELS, 0.0f), 
      filtered_out(BUFFER_LENGTH * CHUNKED_CHANNELS, 0.0f),
      filtered_hp(BUFFER_LENGTH * CHUNKED_CHANNELS, 0.0f),
      thresh_signal(BUFFER_LENGTH * CHUNKED_CHANNELS, MIN_THRESH),
      #ifdef USE_WAVELET
      energy_signal(BUFFER_LENGTH * CHUNKED_CHANNELS, 0.0f),  // Initialize energy buffer
      #endif
      ready_(false),
      running_(false),
      chunk_id_(chunk_id) {

    // Initialize processing variables
    for (uint8_t ch = 0; ch < CHUNKED_CHANNELS; ch++) {
        blind_electrodes_array[ch] = BLIND_DURATION;
        max_peak[ch] = 0.;      
        local_threshold[ch] = 100 * MIN_THRESH;  
        stim_active[ch] = 0;
        artefact_peak[ch] = 0.;

        for (uint16_t n = 0; n < BUFFER_LENGTH; n++) {
            filtered_out[n * CHUNKED_CHANNELS + ch] = 0.;
            filtered_hp[n * CHUNKED_CHANNELS + ch] = 0.;
        }


        for (uint16_t n = 0; n < BUFFER_LENGTH; n++) {
            thresh_signal[n * CHUNKED_CHANNELS + ch] = MIN_THRESH;
            filtered_out[n * CHUNKED_CHANNELS + ch] = 0.;
            filtered_hp[n * CHUNKED_CHANNELS + ch] = 0.;            
        }
    }
    detected_spike.cycles = 0;

    // Initialize scaled wavelets
    #ifdef USE_WAVELET
    initialize_wavelets();
    #endif
}

#ifdef USE_WAVELET
// Initialize wavelets of different scales
void SpikeDetector::initialize_wavelets() {
    // Resize the vector of vectors
    scaled_wavelets.resize(NUM_SCALES);
    
    // Generate wavelets for each scale
    for (int s = 0; s < NUM_SCALES; s++) {
        scaled_wavelets[s].resize(WAVELET_SIZE, 0.0f);
        
        // Scale factor: 0.7, 1.0, and 1.3 times the base period
        float scale_factor = 1.f + 0.5f * s;
        
        // Create cosine wavelet with appropriate scale
        for (int i = 0; i < WAVELET_SIZE; i++) {
            // Scale the index to match the desired period
            float scaled_idx = static_cast<float>(i) / scale_factor;
            // Generate cosine with one complete cycle
            scaled_wavelets[s][i] = std::cos(2.0f * M_PI * scaled_idx / (WAVELET_SIZE-1));
        }
    }
}


// Calculate wavelet energy
void SpikeDetector::calculate_energy() {
    for (uint8_t ch = 0; ch < CHUNKED_CHANNELS; ch++) {
        float max_energy = 0.0f;
        
        // Apply each wavelet scale and keep the maximum response
        for (int s = 0; s < NUM_SCALES; s++) {
            float cwt_coeff = 0.0f;
            
            // Convolve signal with the wavelet
            for (int n = 0; n < WAVELET_SIZE; n++) {
                // Ensure proper circular buffer indexing
                int idx = (out_loc - n + BUFFER_LENGTH) % BUFFER_LENGTH;
                cwt_coeff += filtered_out[idx * CHUNKED_CHANNELS + ch] * scaled_wavelets[s][n];
            }
            
            // Square for energy and keep maximum across scales
            float scale_energy = cwt_coeff * cwt_coeff;
            max_energy = std::max(max_energy, scale_energy);
        }
                
        // Store the smoothed energy
        energy_signal[out_loc * CHUNKED_CHANNELS + ch] = max_energy;
        float smooth_energy = 0.;
        
        for (int i = 0; i < 5; i++) {  // 60% weight distributed over previous 4 points
            int idx = (out_loc - i + BUFFER_LENGTH) % BUFFER_LENGTH;
            smooth_energy += energy_signal[idx * CHUNKED_CHANNELS + ch] * 0.2f;  // 15% each
        }

        
        // Copy to threshold signal for threshold calculation
        thresh_signal[raw_loc * CHUNKED_CHANNELS + ch] = smooth_energy;
    }
}
#endif

// Destructor
SpikeDetector::~SpikeDetector() {
    running_ = false;
    close(raw_socket_fd_);
    close(plot_socket_fd_);
    close(spike_socket_fd_);

    if (thresh_socket_fd_ >= 0) {
        close(thresh_socket_fd_);
    }
}

// Step 2: Connect to UNIX sockets
void SpikeDetector::connect_to_sockets() {
    std::string raw_socket_path = RAW_SOCKET_BASE_PATH + std::to_string(chunk_id_);
    std::string plot_socket_path = PLOT_SOCKET_INTERNAL_BASE_PATH + std::to_string(chunk_id_);
    std::string spike_socket_path = SPIKE_SOCKET_INTERNAL_BASE_PATH + std::to_string(chunk_id_);

    // Connect to raw socket
    connect_unix_socket(raw_socket_fd_, raw_socket_path);

    // Connect to plot socket
    connect_unix_socket(plot_socket_fd_, plot_socket_path);

    // Connect to spike socket
    connect_unix_socket(spike_socket_fd_, spike_socket_path);
  
    // Connect to threshold control socket
    if (!connect_thresh_socket()) {
        std::cerr << "Failed to connect to threshold control socket" << std::endl;
        return;
    }

    std::cout << "Spike detector " << static_cast<int>(chunk_id_) << " is ready." << std::endl;
    ready_ = true;
}

// In SpikeDetector::connect_to_sockets()
bool SpikeDetector::connect_thresh_socket() {
    std::string socket_path = "/tmp/thresh_control_socket";
    
    thresh_socket_fd_ = socket(AF_UNIX, SOCK_STREAM, 0);
    if (thresh_socket_fd_ < 0) {
        std::cerr << "Failed to create threshold socket" << std::endl;
        return false;
    }
    
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, socket_path.c_str(), sizeof(addr.sun_path) - 1);
    
    for (int attempt = 0; attempt < 5; ++attempt) {
        if (connect(thresh_socket_fd_, (sockaddr*)&addr, sizeof(addr)) == 0) {
            std::cout << "Connected to threshold control socket" << std::endl;
            return true;
        }
        std::cerr << "Retrying threshold socket connection..." << std::endl;
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    
    std::cerr << "Failed to connect to threshold socket" << std::endl;
    close(thresh_socket_fd_);
    thresh_socket_fd_ = -1;
    return false;
}


// Replace check_thresh_messages
void SpikeDetector::check_thresh_messages() {
    if (thresh_socket_fd_ < 0) return;
    
    // Set up polling with poll() system call
    struct pollfd pfd;
    pfd.fd = thresh_socket_fd_;
    pfd.events = POLLIN;
    
    int ret = poll(&pfd, 1, 0);  // Non-blocking poll
    
    if (ret > 0 && (pfd.revents & POLLIN)) {
        // Data is available
        float new_thresh_factor;
        uint8_t update_enabled;
        
        char buffer[5];  // float (4) + uint8 (1)
        ssize_t bytes_received = recv(thresh_socket_fd_, buffer, sizeof(buffer), 0);
        
        if (bytes_received == sizeof(buffer)) {
            // Extract values
            memcpy(&new_thresh_factor, buffer, sizeof(float));
            memcpy(&update_enabled, buffer + sizeof(float), 1);
            
            // Update values
            thresh_factor_ = new_thresh_factor;
            update_threshold_enabled_ = (update_enabled != 0);
            
            std::cout << "Received new threshold factor: " << thresh_factor_
                    << ", update enabled: " << update_threshold_enabled_ << std::endl;
        } else if (bytes_received <= 0) {
            // Connection closed or error
            std::cerr << "Threshold socket connection closed or error" << std::endl;
            close(thresh_socket_fd_);
            thresh_socket_fd_ = -1;
        }
    }
}


void SpikeDetector::start_processing() {
    running_ = true;
    float alpha = 1.0;

    std::cout << "Spike detector " << static_cast<int>(chunk_id_) << " started processing" << std::endl;

    struct pollfd pfd;
    pfd.fd = raw_socket_fd_;
    pfd.events = POLLIN;  // Wait for incoming data  

    while (running_) {
        // std::cout << "SpikeDetector " << static_cast<int>(chunk_id_) << " waiting for data..." << std::endl;

        int ret = poll(&pfd, 1, 1000);  // Timeout after 1 second
        if (ret > 0) {
            // std::cout << "SpikeDetector " << static_cast<int>(chunk_id_) << " receiving data..." << std::endl;

            InkubePackageChunk chunk_data{};
            ssize_t bytes_received = recv(raw_socket_fd_, &chunk_data, sizeof(chunk_data), 0);
            
            if (bytes_received > 0) {
                // std::cout << "SpikeDetector " << static_cast<int>(chunk_id_) << " received " 
                //           << bytes_received << " bytes" << std::endl;

                process_data(chunk_data);
                raw_loc = (raw_loc + 1) % BUFFER_LENGTH;
                if (!(current_package_id % FS)) {
                    // Check for threshold control messages before updating
                    check_thresh_messages();
                    if (update_threshold_enabled_) {
                        update_threshold(alpha);
                        alpha = 0.25;
                    }
                }
            } else {
                std::cerr << "SpikeDetector " << static_cast<int>(chunk_id_) << " recv() returned " 
                          << bytes_received << std::endl;
                if (bytes_received < 0) perror("recv failed");
            }
        } else if (ret == 0) {
            std::cerr << "SpikeDetector " << static_cast<int>(chunk_id_) 
                      << " timeout waiting for data!" << std::endl;
        } else {
            perror("poll() failed");
            break;
        }
    }
}

void SpikeDetector::stop_processing() {
    running_ = false;
}

void SpikeDetector::update_threshold(const float alpha_mov_avg) {


    for (uint8_t ch = 0; ch < CHUNKED_CHANNELS; ch++) {
        std::vector<float> abs_values;
        for (uint16_t n = 0; n < BUFFER_LENGTH; n+=THRESH_SUBSAMPLING) {
            abs_values.push_back(std::abs(thresh_signal[n*CHUNKED_CHANNELS+ch]));
        }
        size_t med_loc = abs_values.size() / 2;
        std::nth_element(abs_values.begin(), abs_values.begin()+med_loc, abs_values.end());
        
        local_threshold[ch] = (1-alpha_mov_avg)*local_threshold[ch] + 
                             alpha_mov_avg*(std::max(thresh_factor_*abs_values[med_loc], MIN_THRESH));
    }
}

void SpikeDetector::process_data(const InkubePackageChunk& chunk_data) {
    uint8_t ch = 0;
    uint16_t n = 0;
    plot_loc = out_loc;
    const uint16_t plot_chunk_size_ = INTERNAL_PLOT_CHUNK_LENGTH * CHUNKED_CHANNELS * sizeof(float);

    //-----------Access the ring buffer-----------------//
    // Copy the data into raw_data (overwrite old data at current_index)
    for (uint8_t ch = 0; ch < CHUNKED_CHANNELS; ++ch) {
        raw_data[raw_loc*CHUNKED_CHANNELS+ch] = static_cast<float>(chunk_data.voltage_data[ch]);


        movavg_data[raw_loc*CHUNKED_CHANNELS+ch] = 0.;
        for (n = 0; n < FIR_LEN; ++n) {
            movavg_data[raw_loc*CHUNKED_CHANNELS+ch] += raw_data[((raw_loc - n + BUFFER_LENGTH) % BUFFER_LENGTH)*CHUNKED_CHANNELS+ch] * fir_coeff[n];
        }
        #ifdef TRIGGER_ARTEFACT
        if (stim_active[ch] > 0) {
            stim_active[ch]--;
        } else {
            if (
                    (
                        raw_data[raw_loc*CHUNKED_CHANNELS+ch] 
                        - raw_data[((raw_loc-1+BUFFER_LENGTH) % BUFFER_LENGTH) * CHUNKED_CHANNELS + ch]
                    ) > RAW_ARTEFACT_THRESH) {
                stim_active[ch] = 20;
                artefact_peak[ch] = raw_data[raw_loc*CHUNKED_CHANNELS+ch];
            }
        }
        #endif
    }

    current_package_id = (chunk_data.package_id - DETECT_DURATION) % MAX_PKG_ID;

    detected_spike.package_id = (current_package_id+MAX_PKG_ID-DETECT_DURATION)%MAX_PKG_ID;
    if (current_package_id == 0) {
        current_cycle++;
        detected_spike.cycles = current_cycle; // current_cycle;
    }

    //-----------Filtering and spike detection-----------//
    for (ch = 0; ch < CHUNKED_CHANNELS; ch++) {

        #ifdef TRIGGER_ARTEFACT
        // find peak value and fill in
        if (stim_active[ch] > 0) {
            if (artefact_peak[ch] < raw_data[raw_loc*CHUNKED_CHANNELS+ch]) {
                artefact_peak[ch] = raw_data[raw_loc*CHUNKED_CHANNELS+ch];
            } else {
                for (n = 0; n < FILT_LEN; ++n) {
                    raw_data[((raw_loc - n + BUFFER_LENGTH) % BUFFER_LENGTH) * CHUNKED_CHANNELS + ch] = artefact_peak[ch];
                    filtered_hp[((out_loc - n + BUFFER_LENGTH) % BUFFER_LENGTH) * CHUNKED_CHANNELS + ch] = 0.;
                }
                std::cout << "Artefact detected on channel " << static_cast<int>(ch) << " after " << stim_active[ch] << std::endl;
            }
        }
        #endif

        // apply IIR high pass
        filtered_hp[out_loc*CHUNKED_CHANNELS+ch] = coeff_b[0] * movavg_data[raw_loc*CHUNKED_CHANNELS+ch];
        for (n = 1; n < FILT_LEN; ++n) {
            filtered_hp[out_loc*CHUNKED_CHANNELS+ch] +=
                coeff_b[n] * movavg_data[((raw_loc - n + BUFFER_LENGTH) % BUFFER_LENGTH) * CHUNKED_CHANNELS + ch] 
                - coeff_a[n] * filtered_hp[((out_loc - n + BUFFER_LENGTH) % BUFFER_LENGTH) * CHUNKED_CHANNELS + ch];
        }

        // convolve with SG
        #ifdef SAVGOL
        filtered_out[out_loc*CHUNKED_CHANNELS+ch] = 0.;
        for (n = 0; n < SG_LEN; ++n) {
            filtered_out[out_loc*CHUNKED_CHANNELS+ch] +=
                filtered_hp[((out_loc+n-(SG_LEN-1)+BUFFER_LENGTH)%BUFFER_LENGTH)*CHUNKED_CHANNELS+ch] * SG[SG_LEN-1-n];
        }
        #else
        filtered_out[out_loc*CHUNKED_CHANNELS+ch] = filtered_hp[out_loc*CHUNKED_CHANNELS+ch];
        #endif

        #ifdef USE_WAVELET
        // Copy energy value to threshold signal buffer
        thresh_signal[raw_loc*CHUNKED_CHANNELS+ch] = energy_signal[out_loc*CHUNKED_CHANNELS+ch]; // overwritten in calc energy
        #else
        // Copy filtered signal to threshold signal buffer
        thresh_signal[raw_loc*CHUNKED_CHANNELS+ch] = filtered_out[out_loc*CHUNKED_CHANNELS+ch];
        #endif
        # ifdef USE_WAVELET        
    }
    // Calculate energy using wavelet transform
    calculate_energy();
    // Use energy signal for threshold calculation
    for (ch = 0; ch < CHUNKED_CHANNELS; ch++) {
        # endif // USE_WAVELET
        //----------Spike Detection-------------------------//
        // if channel is still blinded ignore
        if (blind_electrodes_array[ch] > 0) {
            // reduce blind duration sample counter
            --blind_electrodes_array[ch]; 
        } else {
            // if currently in onset
            if (blind_electrodes_array[ch] < 0) {
                // when max is surpassed new onset
                #ifdef USE_WAVELET
                if (energy_signal[out_loc*CHUNKED_CHANNELS+ch] > max_peak[ch]) {
                    // new onset here
                    blind_electrodes_array[ch] = -DETECT_DURATION;
                    max_peak[ch] = energy_signal[out_loc*CHUNKED_CHANNELS+ch];
                #else
                if (-filtered_out[out_loc*CHUNKED_CHANNELS+ch] > max_peak[ch]) {
                    // new onset here
                    blind_electrodes_array[ch] = -DETECT_DURATION;
                    max_peak[ch] = -filtered_out[out_loc*CHUNKED_CHANNELS+ch];
                #endif
                } else {
                    blind_electrodes_array[ch]++;
                
                    if (blind_electrodes_array[ch] == 0) { // here a spike has been detected!
                        // blind electrodes carries number of samples on which electrode is blinded and cannot detect spikes
                        blind_electrodes_array[ch] = BLIND_DURATION - DETECT_DURATION;
                        detected_spike.channel_id = ch+chunk_id_*CHUNKED_CHANNELS;
                        
                        // fill waveform with filtered data for visualization
                        for (n = 0; n < WAVEFORM_LENGTH; n++) {
                            detected_spike.waveform[n] = filtered_out[
                                (
                                    (BUFFER_LENGTH+out_loc-WAVEFORM_LENGTH+n+1)
                                    % BUFFER_LENGTH
                                ) * CHUNKED_CHANNELS
                                + ch
                            ];
                        }

                        // Send the spike event to the collector
                        ssize_t bytes_sent = send(spike_socket_fd_, &detected_spike, sizeof(SpikeEvent), MSG_DONTWAIT);                   
                    }
                }
            } else {
                #ifdef USE_WAVELET
                // if channel threshold is crossed and electrode not blinded
                if (energy_signal[out_loc*CHUNKED_CHANNELS+ch] > local_threshold[ch]) {
                    // onset here
                    blind_electrodes_array[ch] = -DETECT_DURATION;
                    max_peak[ch] = energy_signal[out_loc*CHUNKED_CHANNELS+ch];
                }
                #else
                // if channel threshold is crossed and electrode not blinded
                if (-filtered_out[out_loc*CHUNKED_CHANNELS+ch] > local_threshold[ch]) {
                    // onset here
                    blind_electrodes_array[ch] = -DETECT_DURATION;
                    max_peak[ch] = -filtered_out[out_loc*CHUNKED_CHANNELS+ch];
                }
                #endif
            }
        }
    }

    // Update plotting to use energy signal instead of raw data
    if (!(out_loc % INTERNAL_PLOT_CHUNK_LENGTH)) {
        plot_loc = (out_loc + BUFFER_LENGTH - INTERNAL_PLOT_CHUNK_LENGTH) % BUFFER_LENGTH;
        last_pkg_id_plot = static_cast<float>(current_package_id);

        struct iovec iov[4];

        // Send energy signal for plotting instead of raw data
        iov[0].iov_base = get_filtered_ptr(plot_loc);
        iov[0].iov_len = CHUNKED_CHANNELS * INTERNAL_PLOT_CHUNK_LENGTH * sizeof(float);

        #ifdef USE_WAVELET
        iov[1].iov_base = get_energy_ptr(plot_loc); 
        #else
        iov[1].iov_base = get_raw_ptr(plot_loc);
        #endif
        iov[1].iov_len = CHUNKED_CHANNELS * INTERNAL_PLOT_CHUNK_LENGTH * sizeof(float);

        iov[2].iov_base = &local_threshold[0];
        iov[2].iov_len = CHUNKED_CHANNELS * sizeof(float);  // One threshold per channel

        iov[3].iov_base = &last_pkg_id_plot;
        iov[3].iov_len = sizeof(float);

        struct msghdr msg = {0};
        msg.msg_iov = iov;
        msg.msg_iovlen = 4;

        ssize_t bytes_sent = sendmsg(plot_socket_fd_, &msg, 0);
        if (bytes_sent < 0) {
            perror("Send failed");
        }
    }

    //-----------Update array indexing variables-----------------//
    // Increment the buffer index (wrap around when it reaches buffer_size)
    // plot_loc = (plot_loc + 1) % ;

    out_loc = (out_loc + 1) % (BUFFER_LENGTH); // FILT_LEN
    // If the fixed-size buffer is full, send the data

    if (!(current_package_id % (5*FS)) && !chunk_id_) {
        std::cout << "[" << get_timestamp() << "] PROC: Packet " << current_package_id << std::endl; 
    }
}


