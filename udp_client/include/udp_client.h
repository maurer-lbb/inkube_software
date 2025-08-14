#ifndef UDP_CLIENT_H
#define UDP_CLIENT_H

#include <string>
#include <arpa/inet.h>
#include <stdexcept>
#include <sys/socket.h>

class UDPClient {
public:
    UDPClient(const std::string& ip_address, int port = 0);  // Constructor with IP and port
    ~UDPClient();

    void whitelistPort();

    int get_port() const;
    ssize_t receive(void* buffer, size_t buffer_size, sockaddr_in* sender_addr = nullptr);

private:
    int udp_socket_;
    int assigned_port_;
    sockaddr_in local_addr_;
    sockaddr_in server_addr_;  // Add server address here
};

#endif  // UDP_CLIENT_H
