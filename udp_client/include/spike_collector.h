#ifndef SPIKE_COLLECTOR_H
#define SPIKE_COLLECTOR_H

#include <vector>
#include <string>
#include <thread>
#include <atomic>
#include <zmq.hpp>
#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>
#include <iostream>
#include <cstring>
#include <unistd.h>
#include <fcntl.h>
#include <chrono>
#include <thread>

#include "helper_functions.h"
#include "spike_event.h"
#include "fpga_constants.h"
#include "inkube_package.h"

class SpikeCollector {
public:
    SpikeCollector();
    ~SpikeCollector();

    void start();
    void stop();

    bool is_ready() const { return ready_; }

    void setup_sockets();        // Step 1: Create and bind sockets
    void connect_to_sockets();   // Step 2: Establish UNIX socket connections
    void accept_connections();   // Step 4: Accept connections from clients

private:
    std::atomic<bool> ready_{false};  // Set to true only when all connections are successful
    std::thread connection_thread_;   // Handles async connections

    std::atomic<bool> running_;
    std::thread collector_thread_;
    std::thread package_thread_;

    std::vector<int> internal_clients_;
    std::vector<int> internal_socket_fds_;  // File descriptors for internal UNIX sockets
    std::vector<std::string> internal_socket_paths_;  // Paths for internal sockets
    int recv_pkg_fd_;  // File descriptor for package reception socket

    zmq::context_t zmq_context_;
    zmq::socket_t zmq_spike_pub_;    // ZMQ publisher for spike data
    zmq::socket_t zmq_package_pub_;  // ZMQ publisher for package data

    // **New Methods for Proper Initialization Order**
    void setup_internal_sockets();  // Step 3: Create and bind internal sockets

    void run();
    void process_spikes();
    void handle_package_stream();
};

#endif // SPIKE_COLLECTOR_H
