#include "udp_client.h"
#include "udp_receiver.h"
#include "spike_detector.h"
#include "plot_server.h"
#include "spike_collector.h"

#include <iostream>
#include <unistd.h>    
#include <sys/wait.h>  
#include <sys/socket.h>
#include <sys/un.h>
#include <vector>
#include <memory>
#include <chrono>
#include <thread>
#include <functional>

// Define the test server flag (uncomment to enable test mode)
// #define DO_TEST_SERVER 

#ifdef DO_TEST_SERVER
    #define HOST_PORT 12345
    #define HOST_IP "127.0.0.1"
#else
    #define HOST_PORT 0  
    #define HOST_IP "192.168.10.10"
#endif

void wait_for_ready(const std::vector<std::function<bool()>>& components) {
    while (true) {
        bool all_ready = true;
        for (const auto& is_ready_func : components) {
            if (!is_ready_func()) {  // Call the function
                all_ready = false;
                break;
            }
        }
        if (all_ready) break;
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
}


int main() {
    std::cout << "System initialization started..." << std::endl;

    // Set up UDP Client
    UDPClient udp_client(HOST_IP, HOST_PORT);
    int assigned_port = udp_client.get_port();
    std::cout << "UDP Client initialized on port: " << assigned_port << std::endl;

    // Send UDP port to FPGA through UNIX socket
    std::string udp_port_path = "/tmp/udp_port_for_fpga";
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, udp_port_path.c_str(), sizeof(addr.sun_path) - 1);

    int udp_port_socket_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (udp_port_socket_fd < 0) {
        throw std::runtime_error("Failed to create UNIX socket for UDP port sharing");
    }

    unlink(udp_port_path.c_str());
    if (bind(udp_port_socket_fd, (sockaddr*)&addr, sizeof(addr)) < 0) {
        throw std::runtime_error("Failed to bind UNIX socket for UDP port sharing");
    }

    listen(udp_port_socket_fd, 5);
    int client_fd = accept(udp_port_socket_fd, nullptr, nullptr);
    if (client_fd >= 0) {
        send(client_fd, &assigned_port, sizeof(assigned_port), 0);
        close(client_fd);
    }
    unlink(udp_port_path.c_str());

    // Create components
    UDPReceiver udp_receiver(udp_client);
    PlotServer plot_server;
    SpikeCollector spike_collector;

    // Create SpikeDetectors
    std::vector<std::unique_ptr<SpikeDetector>> spike_detectors;
    for (uint8_t chunk = 0; chunk < NUM_CHANNEL_CHUNKS; ++chunk) {
        spike_detectors.push_back(std::make_unique<SpikeDetector>(chunk));
    }

    // Connect
    plot_server.connect_to_sockets();
    spike_collector.connect_to_sockets();
    // UDP Receiver has no clients    
    // udp_receiver.connect_to_sockets();
    for (const auto& detector : spike_detectors) { 
        detector->connect_to_sockets();
    }    

    plot_server.accept_connections();
    udp_receiver.accept_connections();
    // detector has no servers
    // for (const auto& detector : spike_detectors) { 
    //     detector->accept_connections();
    // }
    spike_collector.accept_connections();



    // Wait for all components to be ready
    wait_for_ready({
        [&udp_receiver]() { return udp_receiver.is_ready(); },
        [&spike_collector]() { return spike_collector.is_ready(); },
        [&plot_server]() { return plot_server.is_ready(); }
    });

    std::cout << "UDPReceiver, SpikeCollector, and PlotServer are ready." << std::endl;
    for (const auto& detector : spike_detectors) {
        while (!detector->is_ready()) std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    std::cout << "SpikeDetectors are ready." << std::endl;

    // Fork for `UDPReceiver`
    if (fork() == 0) {
        udp_receiver.setup_zmq();
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
        udp_receiver.start_receiving();
        exit(0);
    }

    // Sleep for 1 second
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    // Start main processes
    std::cout << "Starting PlotServer..." << std::endl;
    plot_server.start();
    std::cout << "PlotServer started!" << std::endl;

    std::cout << "Starting SpikeCollector..." << std::endl;
    spike_collector.start();
    std::cout << "SpikeCollector started!" << std::endl;

    // Fork for `SpikeDetectors`
    for (uint8_t chunk = 0; chunk < NUM_CHANNEL_CHUNKS; ++chunk) {
        if (fork() == 0) {
            spike_detectors[chunk]->start_processing();
            exit(0);
        }
    }

    // Wait for all child processes
    while (wait(nullptr) > 0);

    return 0;
}
