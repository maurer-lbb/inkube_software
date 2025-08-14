#include "spike_collector.h"


// Constructor
SpikeCollector::SpikeCollector()
    : running_(false),
      zmq_context_(1),
      zmq_spike_pub_(zmq_context_, ZMQ_PUB),
      zmq_package_pub_(zmq_context_, ZMQ_PUB) {

    // Step 1: Set up UNIX sockets and ZeroMQ publishers
    setup_internal_sockets();

}

// Destructor
SpikeCollector::~SpikeCollector() {
    running_ = false;

    close(recv_pkg_fd_);
    for (int fd : internal_socket_fds_) {
        close(fd);
    }
    // Clean up connections
    for (int fd : internal_clients_) {
        close(fd);
    }
}

// Step 1: Set up UNIX sockets and ZeroMQ
void SpikeCollector::setup_sockets() {
    try {
        // Set up ZeroMQ publishers
        zmq_spike_pub_.bind(ZMQ_SPIKE_ENDPOINT);
        zmq_package_pub_.bind(ZMQ_PACKAGE_ENDPOINT);
        std::cout << "ZeroMQ publishers bound." << std::endl;

    } catch (const std::exception& ex) {
        std::cerr << "Error in SpikeCollector setup: " << ex.what() << std::endl;
        throw;
    }
}

// Step 2: Connect to UNIX sockets in a separate thread
void SpikeCollector::connect_to_sockets() {
    try {
        connect_unix_socket(recv_pkg_fd_, RECV_PKG_SOCKET_PATH);
        std::cout << "SpikeCollector connected to recv package socket" << std::endl;

    } catch (const std::exception& ex) {
        std::cerr << "Error in SpikeCollector connection setup: " << ex.what() << std::endl;
    }
}

// Step 3: Setup Internal Sockets
void SpikeCollector::setup_internal_sockets() {
    // Define internal socket paths for spike detectors
    for (uint8_t chunk = 0; chunk < NUM_CHANNEL_CHUNKS; ++chunk) {
        internal_socket_paths_.push_back(SPIKE_SOCKET_INTERNAL_BASE_PATH + std::to_string(chunk));
    }

    for (const auto& path : internal_socket_paths_) {
        int fd = 0;
        bind_and_listen_unix_socket(fd, path, 5);
        internal_socket_fds_.push_back(fd);
    }
    std::cout << "Internal UNIX sockets for SpikeCollector are ready." << std::endl;
}

void SpikeCollector::accept_connections() {
    // Accept connections for spike detectors
    for (int fd : internal_socket_fds_) {
        int client_fd = accept(fd, nullptr, nullptr);
        if (client_fd < 0) {
            std::cerr << "Failed to accept internal connection" << std::endl;
            continue;
        }
        internal_clients_.push_back(client_fd);
    }
    ready_ = true;
}

void SpikeCollector::start() {
    running_ = true;
    collector_thread_ = std::thread(&SpikeCollector::run, this);
    package_thread_ = std::thread(&SpikeCollector::handle_package_stream, this);
}

void SpikeCollector::stop() {
    running_ = false;
    if (collector_thread_.joinable()) {
        collector_thread_.join();
    }
    if (package_thread_.joinable()) {
        package_thread_.join();
    }
}

void SpikeCollector::run() {
    setup_sockets();
    
    std::vector<SpikeEvent> spike_batch;
    // TODO: subscribe here to package stream and send according to it
    auto next_send_time = std::chrono::steady_clock::now() + std::chrono::milliseconds(SPIKE_BATCH_INTERVAL_MS);

    while (running_) {
        for (int client_fd : internal_clients_) {
            struct pollfd pfd = { client_fd, POLLIN, 0 };
            int ret = poll(&pfd, 1, 1); // Wait up to 1ms for data, then go to next one

            if (ret > 0) {
                while (true) {
                    SpikeEvent spike;
                    ssize_t bytes_received = recv(client_fd, &spike, sizeof(SpikeEvent), MSG_DONTWAIT);
                    if (bytes_received > 0) {
                        spike_batch.push_back(spike);
                    } else if (bytes_received == 0) {
                        std::cerr << "Client disconnected" << std::endl;
                        running_ = false;
                        break;
                    } else {
                        break; // No more data
                    }
                }
            }
        }
        // Send batch every 5ms
        auto now = std::chrono::steady_clock::now();
        if (now >= next_send_time) {
            if (!spike_batch.empty()) {
                // std::cout << "Sending " << spike_batch.size() << " spikes" << std::endl;
                // New message format: [uint32_t spike_count] + [spike data]
                uint32_t spike_count = spike_batch.size();

                // Allocate buffer: 4 bytes for spike count + actual spikes
                size_t message_size = sizeof(uint32_t) + spike_count * sizeof(SpikeEvent);
                zmq::message_t msg(message_size);

                // std::cout << "Size of SpikeEvent: " << sizeof(SpikeEvent) << " bytes" << std::endl;
                // std::cout << "Sending " << spike_count << " spikes, total size: " 
                //         << (sizeof(uint32_t) + spike_count * sizeof(SpikeEvent)) << " bytes" << std::endl;

                // Copy data: First the count, then the spikes
                std::memcpy(msg.data(), &spike_count, sizeof(uint32_t));
                std::memcpy(static_cast<char*>(msg.data()) + sizeof(uint32_t), spike_batch.data(), spike_batch.size() * sizeof(SpikeEvent));

                // Send through ZMQ
                zmq_spike_pub_.send(msg, zmq::send_flags::none);
                spike_batch.clear();
            }
            next_send_time = now + std::chrono::milliseconds(SPIKE_BATCH_INTERVAL_MS);
        }
    }
}

void SpikeCollector::handle_package_stream() {
    CommPackage comm_pkg;

    while (running_) {
        ssize_t bytes_received = recv(recv_pkg_fd_, &comm_pkg, 4, 0);

        // split into package and usbcom stream
        if (bytes_received > 0) {
            zmq::message_t msg(&comm_pkg.package_id, 4);
            zmq_package_pub_.send(msg, zmq::send_flags::none);

        } else if (bytes_received == 0) {
            std::cerr << "Package stream client disconnected" << std::endl;
            break;
        }
    }
    close(recv_pkg_fd_);
}
