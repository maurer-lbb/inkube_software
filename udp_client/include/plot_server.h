#ifndef PLOT_SERVER_H
#define PLOT_SERVER_H

#include "fpga_constants.h"
#include "inkube_package.h"
#include "helper_functions.h"

#include <string>
#include <vector>
#include <thread>
#include <sys/socket.h>
#include <sys/un.h>
#include <array>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <unistd.h>
#include <atomic>
#include <zmq.hpp>  // Include ZeroMQ
#include <poll.h>

class PlotServer {
public:
    PlotServer();
    ~PlotServer();

    void start();
    void stop();
    bool is_ready() const { return ready_; }
    
    void accept_connections();
    void connect_to_sockets();   // Step 2: Establish UNIX socket connections    

private:
    std::atomic<bool> ready_{false};  // Synchronization flag
    std::thread connection_thread_;

    std::unique_ptr<PlotPackage> plot_package_;
    std::vector<float> raw_recv_;
    std::vector<float> filtered_recv_;
    std::vector<float> threshold_recv_;
    std::vector<float> recv_data_;
    float package_id_;

    std::vector<int> internal_clients_;
    std::vector<std::string> internal_socket_paths_;
    std::vector<int> internal_socket_fds_;
    
    std::thread server_thread_;
    bool running_;

    int env_fd_;  // File descriptor for the receiver package socket
    int env_internal_client_; 

    std::unique_ptr<EnvPackage> env_pkg_;  // Environment package for temperature data

    // **New Methods for Proper Initialization Order**
    void setup_sockets();        // Step 1: Create and bind UNIX sockets
    void setup_internal_sockets();  // Step 3: Prepare internal communication sockets

    void run();

    // ZeroMQ Context and Publishers
    zmq::context_t zmq_context_;
    zmq::socket_t zmq_pub_socket1_;
    zmq::socket_t zmq_pub_socket2_;
    zmq::socket_t zmq_pub_socket3_;
    zmq::socket_t zmq_pub_socket4_;
    zmq::socket_t zmq_env_pub_;  // ZeroMQ Publisher for environment data
};

#endif // PLOT_SERVER_H
