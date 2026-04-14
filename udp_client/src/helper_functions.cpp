#include "helper_functions.h"


// Function to get the current timestamp
std::string get_timestamp() {
    auto now = std::chrono::system_clock::now();
    auto now_time_t = std::chrono::system_clock::to_time_t(now);
    auto now_us = std::chrono::duration_cast<std::chrono::microseconds>(now.time_since_epoch()) % 1000000;

    std::ostringstream timestamp;
    timestamp << std::put_time(std::localtime(&now_time_t), "%H:%M:%S")  // HH:MM:SS
              << "." << std::setw(6) << std::setfill('0') << now_us.count();  // .microseconds
    return timestamp.str();
}

// Function to create, bind, and listen on a UNIX socket
bool bind_and_listen_unix_socket(int& server_fd, const std::string& socket_path, int max_connections) {
    server_fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (server_fd < 0) {
        std::cerr << "Error: Failed to create UNIX socket at " << socket_path << std::endl;
        return false;
    }

    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, socket_path.c_str(), sizeof(addr.sun_path) - 1);

    unlink(socket_path.c_str());  // Ensure previous instance is removed
    if (bind(server_fd, (sockaddr*)&addr, sizeof(addr)) < 0) {
        std::cerr << "Error: Failed to bind UNIX socket at " << socket_path << std::endl;
        close(server_fd);
        return false;
    }

    if (listen(server_fd, max_connections) < 0) {
        std::cerr << "Error: Failed to listen on UNIX socket at " << socket_path << std::endl;
        close(server_fd);
        return false;
    }
    std::cout << "Listening on UNIX socket: " << socket_path << std::endl;
    return true;
}

// Function to connect to a UNIX socket
bool connect_unix_socket(int& client_fd, const std::string& socket_path, int max_attempts, int retry_delay_ms) {
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, socket_path.c_str(), sizeof(addr.sun_path) - 1);

    for (int attempt = 0; attempt < max_attempts; ++attempt) {
        client_fd = socket(AF_UNIX, SOCK_STREAM, 0);
        if (client_fd < 0) {
            std::cerr << "Error: Failed to create UNIX socket for " << socket_path << std::endl;
            return false;
        }

        if (connect(client_fd, (sockaddr*)&addr, sizeof(addr)) == 0) {
            std::cout << "Connected to UNIX socket: " << socket_path << std::endl;
            return true;
        }

        std::cerr << "Retrying connection to UNIX socket: " << socket_path << " (" << attempt + 1 << "/" << max_attempts << ")" << std::endl;
        close(client_fd);
        std::this_thread::sleep_for(std::chrono::milliseconds(retry_delay_ms));
    }

    std::cerr << "Error: Failed to connect to UNIX socket after " << max_attempts << " attempts: " << socket_path << std::endl;
    return false;
}

// Function to accept a connection on a UNIX socket (blocking)
bool accept_unix_socket(int& client_fd, int server_fd) {
    sockaddr_un client_addr{};
    socklen_t client_len = sizeof(client_addr);
    client_fd = accept(server_fd, (sockaddr*)&client_addr, &client_len);

    if (client_fd < 0) {
        std::cerr << "Error: Failed to accept connection on UNIX socket" << std::endl;
        return false;
    }

    std::cout << "Accepted connection on UNIX socket" << std::endl;
    return true;
}
