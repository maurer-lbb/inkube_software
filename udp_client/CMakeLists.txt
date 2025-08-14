cmake_minimum_required(VERSION 3.10)
project(udp_client)

# Specify C++ Standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED True)

# Include Directories
include_directories(${CMAKE_SOURCE_DIR}/include)

# Source Files
set(SOURCES
    src/main.cpp
    src/udp_client.cpp  # Add udp_client.cpp to the sources
    src/udp_receiver.cpp
    src/spike_detector.cpp
    src/plot_server.cpp
    src/spike_collector.cpp
    src/helper_functions.cpp
)

# Define Executable
add_executable(udp_client ${SOURCES})

# Link Libraries
target_link_libraries(udp_client pthread rt zmq)

# make sure to install zmq: sudo apt-get install libzmq3-dev
# build with following commands in terminal:
# mkdir build
# cd build
# mkdir ..
# make

# then execute with 
# ./udp_client