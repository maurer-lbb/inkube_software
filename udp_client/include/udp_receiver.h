#ifndef UDP_RECEIVER_H
#define UDP_RECEIVER_H

#include "udp_client.h"
#include "inkube_package.h"
#include "helper_functions.h"

#include <vector>
#include <string>
#include <thread>
#include <atomic>
#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>
#include <array>
#include <zmq.hpp>
#include <iostream>
#include <iomanip>  // For hex formatting
#include <cstring>  // For memcmp
#include <bitset>  // Needed for binary output

// #define COMMAND_DEBUG_OUTPUT

class UDPReceiver {
public:
    explicit UDPReceiver(UDPClient& udp_client);
    ~UDPReceiver();

    void start_receiving();   // Starts the receiving and processing loop
    void stop_receiving();    // Stops the receiving loop

    void setup_sockets();      // Initializes and binds UNIX sockets
    void setup_zmq();
    void accept_connections(); // Accepts connections from clients in a separate thread

    bool is_ready() const { return ready_; }

private:
    zmq::context_t zmq_context_;
    zmq::socket_t zmq_usbrecv_pub_;    // ZMQ publisher for spike data

    std::atomic<bool> ready_{false};  // Synchronization flag
    std::atomic<bool> running_;  // Control flag for the receiving loop
    std::thread connection_thread_;  // Thread for accepting client connections

    UDPClient& udp_client_;  // Reference to the UDP client

    std::vector<int> socket_fds_;  // File descriptors for the UNIX sockets
    std::vector<std::string> socket_paths_;  // Paths for the UNIX sockets
    std::vector<int> client_fds_;  // Client file descriptors for the accepted connections

    int recv_pkg_fd_ = 0;  // File descriptor for the receiver package socket
    std::string recv_pkg_path_;  // Path for the receiver package socket
    int recv_pkg_client_fd_;  // File descriptor for the receiver package socket

    int env_fd_ = 0;  // File descriptor for the receiver package socket
    std::string env_path_;  // Path for the receiver package socket
    int env_client_fd_;  // File descriptor for the receiver package socket

    EnvPackage* env_pkg_;

    int segmentation_fd_;  // File descriptor for the segmentation socket
    std::string segmentation_path_;  // Path for the segmentation socket

    std::array<InkubePackageChunk, NUM_CHANNEL_CHUNKS> chunked_data_;  // Buffer for chunked data
    uint16_t chunk_data_size_ = sizeof(InkubePackageChunk);  // Size of the chunked data struct
};


#endif // UDP_RECEIVER_H
