#ifndef HELPER_FUNCTIONS_H
#define HELPER_FUNCTIONS_H

#include <string>
#include <sys/socket.h>
#include <sys/un.h>
#include <iostream>
#include <unistd.h>
#include <chrono>
#include <ctime>
#include <sstream>
#include <iomanip>
#include <cstring>
#include <thread>

// Function to get a timestamp
std::string get_timestamp();

// Function to create, bind, and listen on a UNIX socket
bool bind_and_listen_unix_socket(int& server_fd, const std::string& socket_path, int max_connections = 5);

// Function to connect to a UNIX socket
bool connect_unix_socket(int& client_fd, const std::string& socket_path, int max_attempts = 10, int retry_delay_ms = 100);

// Function to accept a connection on a UNIX socket (blocking)
bool accept_unix_socket(int& client_fd, int server_fd);

#endif // HELPER_FUNCTIONS_H
