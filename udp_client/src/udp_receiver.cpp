#include "udp_receiver.h"
#include <iostream>
#include <cstring>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <stdexcept>
#include <vector>

UDPReceiver::UDPReceiver(UDPClient& udp_client)
    : udp_client_(udp_client), 
      running_(false), 
      ready_(false),
      recv_pkg_fd_(-1),
      recv_pkg_client_fd_(-1),
      env_fd_(-1),
      env_client_fd_(-1) {
    
    setup_sockets();
}


void UDPReceiver::setup_sockets() {
    try {
        // **Bind and listen on RAW data sockets**
        for (uint8_t i = 0; i < NUM_CHANNEL_CHUNKS; ++i) {
            std::string socket_path = RAW_SOCKET_BASE_PATH + std::to_string(i);
            int socket_fd = 0;
            bind_and_listen_unix_socket(socket_fd, socket_path, 5);
            socket_fds_.push_back(socket_fd);
            socket_paths_.push_back(socket_path);
            std::cout << "Socket created and listening: " << socket_path << std::endl;
        }

        // **Bind and listen on RECV package socket**
        std::string recv_socket_path = RECV_PKG_SOCKET_PATH;
        bind_and_listen_unix_socket(recv_pkg_fd_, recv_socket_path, 5);
        std::cout << "UDPReceiver is now listening on " << recv_socket_path << std::endl;

        // **Bind and listen on ENV socket**
        std::string env_socket_path = ENV_SOCKET_PATH;
        bind_and_listen_unix_socket(env_fd_, env_socket_path, 5);
        std::cout << "UDPReceiver is now listening on " << env_socket_path << std::endl;

    } catch (const std::exception& e) {
        std::cerr << "UDPReceiver setup failed: " << e.what() << std::endl;
    }

}

void UDPReceiver::setup_zmq() {

    zmq_context_ = zmq::context_t(1);
    zmq_usbrecv_pub_ = zmq::socket_t(zmq_context_, ZMQ_PUB);

    zmq_usbrecv_pub_.bind(ZMQ_USBCOM_ENDPOINT);

    // send zmq test message
    // zmq::message_t zmq_msg("Test", 5);
    // zmq_usbrecv_pub_.send(zmq_msg, zmq::send_flags::none);
}

void UDPReceiver::accept_connections() {
    // **Start accepting clients in a separate thread**

    for (uint8_t i = 0; i < NUM_CHANNEL_CHUNKS; ++i) {
        int client_fd;
        do {
            if (accept_unix_socket(client_fd, socket_fds_[i])) {
                client_fds_.push_back(client_fd);
                std::cout << "Client connected on socket " << i << std::endl;
                break;  // Exit retry loop on success
            }
            std::cerr << "UDPReceiver retrying connection on socket " << i << std::endl;
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
        } while (true);
    }

    // **Accept recv package socket connection**
    do {
        if (accept_unix_socket(recv_pkg_client_fd_, recv_pkg_fd_)) {
            std::cout << "SpikeCollector connected to recv package socket" << std::endl;
            break;
        }
        std::cerr << "UDPReceiver retrying recv package connection..." << std::endl;
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    } while (true);

    // **Accept ENV socket connection**
    do {
        if (accept_unix_socket(env_client_fd_, env_fd_)) {
            std::cout << "Plot connected to ENV socket" << std::endl;
            break;
        }
        std::cerr << "UDPReceiver retrying ENV socket connection..." << std::endl;
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    } while (true);

    std::cout << "UDPReceiver is ready" << std::endl;
    ready_ = true;
}

UDPReceiver::~UDPReceiver() {
    stop_receiving();
    for (size_t i = 0; i < socket_fds_.size(); ++i) {
        close(socket_fds_[i]);
        unlink(socket_paths_[i].c_str());
    }
    if (recv_pkg_fd_ >= 0) {
        close(recv_pkg_fd_);
    }

    if (env_fd_ >= 0) {
        close(env_fd_);
    }
}

void UDPReceiver::start_receiving() {
    running_ = true;
    uint16_t raw_buffer_loc = 0;
    uint8_t buffer[UDP_PACKAGE_SIZE];
    uint8_t last_receive_id = 255;

    std::cout << "Receiving data through UDP from FPGA" << std::endl;

    CommPackage comm_pkg;
    EnvPackage env_pkg;

    comm_pkg.package_id = 0;
    uint32_t pkg_id = 0;
    uint8_t init_usb_recv = 1;

    uint32_t chip_com[64];
    for (uint8_t i = 0; i < 64; i++) {
        chip_com[i] = 0;
    }

    const uint32_t READ_CHIP_ID_COMMAND_UINT32 = 0xC0FE0000;

    while (running_) {
        sockaddr_in sender_addr;

        // Receive data from the FPGA through UDP
        // std::cout << "Receiving data from FPGA" << std::endl;
        ssize_t bytes_received = udp_client_.receive(buffer, UDP_PACKAGE_SIZE, &sender_addr);
        // std::cout << "Received data from FPGA" << std::endl;

        if (bytes_received < 0) {
            std::cerr << "Receive failed, bytes_received=" << bytes_received << std::endl;
            continue;
        }

        // If data was received, distribute it to the spike consumer processes
        if (bytes_received == static_cast<ssize_t>(UDP_PACKAGE_SIZE)) {
            pkg_id = *reinterpret_cast<uint32_t*>(&buffer[2]);

            // Process and split data
            for (uint8_t chunk = 0; chunk < NUM_CHANNEL_CHUNKS; ++chunk) {
                chunked_data_[chunk].package_id = pkg_id;

                for (uint8_t channel = 0; channel < CHUNKED_CHANNELS; ++channel) {
                    chunked_data_[chunk].voltage_data[channel] = static_cast<int16_t>(
                        *reinterpret_cast<uint16_t*>(&buffer[SIGNAL_READOUT_OFFSET + ((channel + chunk * CHUNKED_CHANNELS) * 4)]) - 32768);
                }

                // Send data to SpikeDetector via the already connected socket
                ssize_t bytes_sent = send(client_fds_[chunk], &chunked_data_[chunk], sizeof(chunked_data_[chunk]), 0);
                if (bytes_sent < 0) {
                    std::cerr << "Failed to send data on socket " << chunk << std::endl;
                } else if (bytes_sent != sizeof(chunked_data_[chunk])) {
                    std::cerr << "Partial data sent on socket " << chunk << ": " << bytes_sent << " bytes sent." << std::endl;
                // } else {
                //     std::cout << "Sent data to SpikeDetector " << static_cast<int>(chunk) << std::endl;
                }
            }

            // // Send package ID to SpikeCollector only if new package ID
            if ((last_receive_id != buffer[1])) {
                std::cout << "Last receive id: " << static_cast<int>(last_receive_id) << " and new " << static_cast<int>(buffer[1]) << std::endl;
                last_receive_id = buffer[1];

                zmq::message_t msg(&last_receive_id, 1);
                zmq_usbrecv_pub_.send(msg, zmq::send_flags::none);                
            }

            if (!(pkg_id % PKG_SEND_OUT)) {
                comm_pkg.package_id = pkg_id;
                ssize_t bytes_sent = send(recv_pkg_client_fd_, &comm_pkg, 4, 0);
                if (bytes_sent < 0) {
                    std::cerr << "Failed to send to recv package socket" << std::endl;
                }
            }

            // Read temperature data every second
            if (!(pkg_id % (1*FS))) {
                // update temperature stream
                for (uint8_t env_ch = 0; env_ch < 7; env_ch++) {
                    env_pkg.temp_data[env_ch] = *reinterpret_cast<uint32_t*>(&buffer[22 + env_ch * 4]);
                }

                for (uint8_t env_ch = 0; env_ch < 4; env_ch++) {
                    env_pkg.temp_data[env_ch + 7] = static_cast<uint32_t>(*reinterpret_cast<uint16_t*>(&buffer[54 + env_ch * 4]));
                    env_pkg.temp_data[env_ch + 11] = static_cast<uint32_t>(*reinterpret_cast<uint16_t*>(&buffer[56 + env_ch * 4]));
                }

                // std::cout << "Temperature data: ";
                // for (uint8_t env_ch = 0; env_ch < TEMP_DATA_LEN; env_ch++) {
                //     std::cout << env_pkg.temp_data[env_ch] << " ";
                // }
                // std::cout << std::endl;

                // Send to UNIX socket
                if (env_client_fd_ >= 0) {
                    ssize_t bytes_sent_env = send(env_client_fd_, env_pkg.temp_data, TEMP_DATA_LEN*sizeof(uint32_t), 0);
                    if (bytes_sent_env < 0) {
                        std::cerr << "Failed to send to env socket" << std::endl;
                    }
                }
            }

            #ifdef COMMAND_DEBUG_OUTPUT
            uint8_t any_written = 0;
            for (uint8_t i = 0; i < 64; i++) {
                chip_com[i] = *reinterpret_cast<uint32_t*>(&buffer[82 + i * 4]); // 82 for com 0 chip 0
            }

            // Check if chip_1_com is NOT the empty command
            for (uint8_t i = 0; i < 64; i++) {
                if ((((chip_com[i] >> 16) & 0xFF) != 252) && (((chip_com[i] >> 16) & 0xFF) != 254) && (((chip_com[i] >> 16) & 0xFF) != 255) && (((chip_com[i] >> 16) & 0xFF) != 32) && (((chip_com[i] >> 16) & 0xFF) != 33)) { // (chip_com[i] != READ_CHIP_ID_COMMAND_UINT32) {
                    #include <bitset>  // Needed for binary output

                std::cout << pkg_id
                        << " Chip " << std::setw(2) << std::setfill('0') << static_cast<int>(i&0x0f)   // Always 2 digits
                        << " Com: " << static_cast<int>(i>>4) 
                        << " reg " << std::setw(2) << std::setfill('0') << static_cast<int>((chip_com[i] >> 16) & 0xFF)  // Always 2-digit hex
                        << " data " << std::bitset<16>(chip_com[i] & 0xFFFF)  // Print as binary (16-bit)
                        << std::dec << std::endl;

                    any_written = 1;
                }
                // else {
                //     break;
                // }
            }     
            if (any_written) {
                std::cout << std::endl;
            }
            #endif

            // Debug print with timing for receive
            if (!(pkg_id % (5*FS))) {
                std::cout << "[" << get_timestamp() << "] RECV: Packet " << chunked_data_[0].package_id << std::endl;
            }

        } else {
            std::cerr << "Incomplete packet received: " << bytes_received << " bytes." << std::endl;
        }
    }
}


void UDPReceiver::stop_receiving() {
    running_ = false;
    for (int client_fd : client_fds_) {
        close(client_fd);
    }
    client_fds_.clear();
}
