#include "udp_client.h"
#include <iostream>
#include <cstring>
#include <arpa/inet.h>
#include <unistd.h>  // For close()

UDPClient::UDPClient(const std::string& ip_address, int port) : udp_socket_(-1), assigned_port_(port) {
    // Create the UDP socket
    udp_socket_ = socket(AF_INET, SOCK_DGRAM, 0);
    if (udp_socket_ < 0) {
        throw std::runtime_error("Socket creation failed");
    }

    // Initialize the local address structure
    std::memset(&local_addr_, 0, sizeof(local_addr_));
    local_addr_.sin_family = AF_INET;
    local_addr_.sin_port = htons(port);
    local_addr_.sin_addr.s_addr = INADDR_ANY;

    // Bind the socket
    if (bind(udp_socket_, (struct sockaddr*)&local_addr_, sizeof(local_addr_)) < 0) {
        close(udp_socket_);
        throw std::runtime_error("Bind failed");
    }

    if (!port) {
        whitelistPort();
    }

    // Retrieve the assigned port (in case of auto-assign)
    if (port == 0) {
        socklen_t addr_len = sizeof(local_addr_);
        if (getsockname(udp_socket_, (struct sockaddr*)&local_addr_, &addr_len) < 0) {
            close(udp_socket_);
            throw std::runtime_error("Failed to retrieve assigned port");
        }
        assigned_port_ = ntohs(local_addr_.sin_port);
    }

    // Initialize the remote server address (IP address of the server)
    std::memset(&server_addr_, 0, sizeof(server_addr_));
    server_addr_.sin_family = AF_INET;
    server_addr_.sin_port = htons(assigned_port_); // You can set a fixed or dynamic port here
    if (inet_pton(AF_INET, ip_address.c_str(), &server_addr_.sin_addr) <= 0) {
        throw std::runtime_error("Invalid server IP address");
    }

    std::cout << "Listening for UDP packets on port " << assigned_port_ << "..." << std::endl;
}

UDPClient::~UDPClient() {
    if (udp_socket_ >= 0) {
        close(udp_socket_);
    }
}


void UDPClient::whitelistPort() {
    const char *msg = "Whitelist this port";

    struct sockaddr_in fpga_addr;
    memset(&fpga_addr, 0, sizeof(fpga_addr));
    fpga_addr.sin_family = AF_INET;
    fpga_addr.sin_port = htons(45615);  // FPGA's source port from Wireshark
    if (inet_pton(AF_INET, "192.168.10.10", &fpga_addr.sin_addr) <= 0) {
        std::cerr << "[ERROR] Invalid FPGA IP address" << std::endl;
        return;
    }

    ssize_t bytes_sent = sendto(udp_socket_, msg, strlen(msg), 0, 
                                (struct sockaddr*)&fpga_addr, sizeof(fpga_addr));

    if (bytes_sent < 0) {
        perror("[ERROR] sendto failed");
    } else {
        std::cout << "[DEBUG] Sent whitelist request to 192.168.10.10:45615 ("
                  << bytes_sent << " bytes)" << std::endl;
    }
}

int UDPClient::get_port() const {
    return assigned_port_;
}

ssize_t UDPClient::receive(void* buffer, size_t buffer_size, sockaddr_in* sender_addr) {
    sockaddr_in temp_sender_addr {};
    socklen_t addr_len = sizeof(temp_sender_addr);

    // std::cout << "Waiting for data in UDP client" << std::endl;
    ssize_t bytes_received = recvfrom(
        udp_socket_, buffer, buffer_size, 0,
        sender_addr ? (struct sockaddr*)sender_addr : (struct sockaddr*)&temp_sender_addr,
        &addr_len);

    if (bytes_received < 0) {
        perror("Receive failed");
    }

    return bytes_received;
}
