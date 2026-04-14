#include "plot_server.h"
#include <chrono>

PlotServer::PlotServer()
    : running_(false), 
      plot_package_(std::make_unique<PlotPackage>()),
      zmq_context_(1), 
      zmq_pub_socket1_(zmq_context_, ZMQ_PUB),
      zmq_pub_socket2_(zmq_context_, ZMQ_PUB),
      zmq_pub_socket3_(zmq_context_, ZMQ_PUB),
      zmq_pub_socket4_(zmq_context_, ZMQ_PUB), 
      zmq_env_pub_(zmq_context_, ZMQ_PUB), 
      env_pkg_(std::make_unique<EnvPackage>()) {

    ready_ = false;  // Mark as not ready initially
    package_id_ = 0.0;

    raw_recv_.resize(CHUNKED_CHANNELS * INTERNAL_PLOT_CHUNK_LENGTH);
    filtered_recv_.resize(CHUNKED_CHANNELS * INTERNAL_PLOT_CHUNK_LENGTH);
    threshold_recv_.resize(CHUNKED_CHANNELS);
    recv_data_.resize(CHUNKED_CHANNELS * INTERNAL_PLOT_CHUNK_LENGTH, 0.0f);

    // Step 1: Create and bind sockets
    setup_sockets();
    setup_internal_sockets();
}

PlotServer::~PlotServer() {
    stop();
}

void PlotServer::setup_sockets() {
    try {
        // **Set up ZeroMQ publishers for external connections**
        zmq_pub_socket1_.bind(ZMQ_DATA_ENDPOINT1);
        zmq_pub_socket2_.bind(ZMQ_DATA_ENDPOINT2);
        zmq_pub_socket3_.bind(ZMQ_DATA_ENDPOINT3);
        zmq_pub_socket4_.bind(ZMQ_DATA_ENDPOINT4);
        zmq_env_pub_.bind(ZMQ_ENV_ENDPOINT);

        std::cout << "ZeroMQ sockets bound on ports 6001-6004 for plotting." << std::endl;
    } catch (const std::exception& ex) {
        std::cerr << "Error in PlotServer setup: " << ex.what() << std::endl;
    }
}

void PlotServer::setup_internal_sockets() {
    try {
        // **Set up internal Unix socket paths**
        for (uint8_t chunk = 0; chunk < NUM_CHANNEL_CHUNKS; ++chunk) {
            internal_socket_paths_.push_back(PLOT_SOCKET_INTERNAL_BASE_PATH + std::to_string(chunk));
        }

        for (const auto& path : internal_socket_paths_) {
            int fd = 0;
            bind_and_listen_unix_socket(fd, path, 5);
            internal_socket_fds_.push_back(fd);
        }

        std::cout << "Internal plot UNIX sockets are ready." << std::endl;
    } catch (const std::exception& ex) {
        std::cerr << "Error in setting up internal sockets: " << ex.what() << std::endl;
    }
}


void PlotServer::accept_connections() {

    std::cout << "Waiting for connections on internal plot sockets..." << std::endl;
    internal_clients_.clear();

    for (size_t i = 0; i < internal_socket_fds_.size(); ++i) {
        std::cout << "Waiting for connection on internal socket " << i << "..." << std::endl;
        int client_fd = accept(internal_socket_fds_[i], nullptr, nullptr);
        if (client_fd < 0) {
            std::cerr << "Failed to accept internal connection on socket " << i << std::endl;
            continue;
        }
        std::cout << "✅ Accepted connection on internal socket " << i << std::endl;
        internal_clients_.push_back(client_fd);
    }

    ready_ = true;

    std::cout << "PlotServer internal connections established." << std::endl;
}


void PlotServer::connect_to_sockets() {
    try {
        connect_unix_socket(env_fd_, ENV_SOCKET_PATH, 5, 100);
        std::cout << "PlotServer connected to ENV socket" << std::endl;
    } catch (const std::exception& ex) {
        std::cerr << "Error connecting sockets in PlotServer: " << ex.what() << std::endl;
    }
}

void PlotServer::start() {
    running_ = true;
    server_thread_ = std::thread(&PlotServer::run, this);
}

void PlotServer::stop() {
    running_ = false;
    if (server_thread_.joinable()) {
        server_thread_.join();
    }

    for (int fd : internal_socket_fds_) {
        close(fd);
    }
    close(env_fd_);
}

void debugPrintVectorSizes(const std::vector<float>& vec1D, size_t rows, size_t cols, const std::string& name) {
    std::cout << name << " size: " << rows << " x " << cols << std::endl;
}

// Main server loop
void PlotServer::run() {
    // Poll structure setup
    struct pollfd fds;
    fds.fd = env_fd_;  // The UNIX socket file descriptor
    fds.events = POLLIN;  // Check for incoming data
    int poll_result = 0;
    
    struct iovec iov[4];

    iov[0].iov_base = raw_recv_.data();
    iov[0].iov_len = raw_recv_.size() * sizeof(float);

    iov[1].iov_base = filtered_recv_.data();
    iov[1].iov_len = filtered_recv_.size() * sizeof(float);

    iov[2].iov_base = threshold_recv_.data();
    iov[2].iov_len = threshold_recv_.size() * sizeof(float);

    iov[3].iov_base = &package_id_;
    iov[3].iov_len = sizeof(float);

    struct msghdr msg = {0};
    msg.msg_iov = iov;
    msg.msg_iovlen = 4;

    std::cout << "Debugging PlotPackage sizes:" << std::endl;
    debugPrintVectorSizes(plot_package_->buffer, plot_package_->get_total_elements(), 1, "buffer");

    std::vector<float> recv_data(CHUNKED_CHANNELS * INTERNAL_PLOT_CHUNK_LENGTH, 0.0f);
    uint16_t internal_buff_loc = 0;
    uint8_t send_env_counter = 0;

    // Main data forwarding loop
    while (running_) {
        for (uint8_t internal_recv_loc = 0; internal_recv_loc < EXTERNAL_PLOT_CHUNK_LENGTH / INTERNAL_PLOT_CHUNK_LENGTH; ++internal_recv_loc) {
            for (size_t i = 0; i < internal_clients_.size(); ++i) {
                // std::cout << "PlotServer waiting for data on internal socket " << i << std::endl;

                ssize_t bytes_received = recvmsg(internal_clients_[i], &msg, 0);
                if (bytes_received <= 0) {
                    std::cerr << "Failed to receive data from internal socket " << i
                              << " (bytes received: " << bytes_received << ")" << std::endl;
                    if (bytes_received == 0) {
                        std::cerr << "Client on internal socket " << i << " disconnected. Removing..." << std::endl;
                        close(internal_clients_[i]);
                        internal_clients_.erase(internal_clients_.begin() + i);
                        --i;
                    }
                    continue;
                }

                // std::cout << "PlotServer received " << bytes_received << " bytes from internal socket " << i << std::endl;

                // Store received data into plot package
                for (size_t ch = 0; ch < CHUNKED_CHANNELS; ++ch) {
                    for (size_t j = 0; j < INTERNAL_PLOT_CHUNK_LENGTH; ++j) {
                        size_t internal_buff_loc = j + internal_recv_loc * INTERNAL_PLOT_CHUNK_LENGTH;
                        size_t signal_channel_index = ch + CHUNKED_CHANNELS * i;
                        size_t index = signal_channel_index * EXTERNAL_PLOT_CHUNK_LENGTH + internal_buff_loc;

                        plot_package_->detection_data[index] = raw_recv_[ch * INTERNAL_PLOT_CHUNK_LENGTH + j];
                        plot_package_->signal_data[index] = filtered_recv_[ch * INTERNAL_PLOT_CHUNK_LENGTH + j];
                    }
                }

                std::copy(threshold_recv_.begin(), threshold_recv_.end(), &plot_package_->threshold_data[CHUNKED_CHANNELS * i]);
                *plot_package_->package_id = package_id_;
            }
        }


        // Distribute channels across 4 ZeroMQ sockets, start with 1
        int zmq_index = 0; // (ch / 4) % 4; // Distribute channels cyclically across 4 sockets

        // Prepare data package
        // std::cout <<"Current package: " << *plot_package_->package_id << std::endl;

        // Send data via ZeroMQ
        zmq::message_t zmq_msg(plot_package_->get_raw_data(), plot_package_->get_total_size());
        switch (zmq_index) {
            case 0:
                zmq_pub_socket1_.send(zmq_msg, zmq::send_flags::none);
                break;
            case 1:
                zmq_pub_socket2_.send(zmq_msg, zmq::send_flags::none);
                break;
            case 2:
                zmq_pub_socket3_.send(zmq_msg, zmq::send_flags::none);
                break;
            case 3:
                zmq_pub_socket4_.send(zmq_msg, zmq::send_flags::none);
                break;
        }

        // poll here, then receive data

        // Poll without blocking
        poll_result = poll(&fds, 1, 0); // Timeout = 0 -> Non-blocking check

        if (poll_result > 0) {
            if (fds.revents & POLLIN) {
                // Data is available, read into temp_data buffer
                ssize_t bytes_received = recv(env_fd_, env_pkg_->temp_data, TEMP_DATA_LEN * sizeof(uint32_t), 0);
                if (bytes_received < 0) {
                    std::cerr << "Error reading from env socket: " << strerror(errno) << std::endl;
                }
                zmq::message_t zmq_msg_env(env_pkg_->temp_data, TEMP_DATA_LEN * sizeof(uint32_t));
                try {
                    zmq_env_pub_.send(zmq_msg_env, zmq::send_flags::none);
                } catch (const zmq::error_t& e) {
                    std::cerr << "ZMQ send failed: " << e.what() << std::endl;
                }
                // std::cout << "Sent environment data" << std::endl;
            }

        }
    }
}