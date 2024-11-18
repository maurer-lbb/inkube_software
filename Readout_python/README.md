# Readout_python
This folder contains the Python code run on the PC connected to the SoC via Ethernet. Main functionality is data readout and spike detection. This is visualised in the GUI. Furthermore, there are functions for segementing the recording into sections, reading out only the spikes of the initial period after stimulus and sending a stimulus for the next period. Details are provided in the inkube publication.

## Files
Client_config.py:                   Contains all constants for data processing, communication and stimulation
Electrode_mapping.py:               Class for mapping of receive channels of FPGA to circuit structure
GUI.py:                             GUI class for spike data plots, environment plots, status and raster
icon.png:                           GUI icon
inkubeSpike.pyx:                    cython file with fir filter, median and spike detection implementation in c. Needs to be compiled first.
main.py:                            main script controlling all subprocesses, connects to FPGA port
onsite_Stimulation_processor.py:    Segment recording into periods, readout early response and stimulate when input is received
requirements.txt:                   Required Python packages, tested with python3.10
Plot_stream.py:                     Contains all update functions for GUI
Send_commands.py:                   Contains all stimulation and prepare commands functions
setup_filter.py:                    compile c functions to python module, call with terminal 'python setup_filter.py build_ext --inplace'
USB_communication.py:               Contains all functions to send commands to the SoC via USB

## Connect
UDP: address (of inkube) 192.168.10.1 Netmask 255.255.255.0 Gateway (if required) 192.168.10.255
USB: 
    lsusb  (with MACOS first brew install usbutils)
    - find FPGA
    ls -l /dev/bus/usb/00x/00y
    - replace 00x with bus ID and 00y with device ID
    if no access rights add the rules file 01-inkube_usb_permissions.rules with content:
    SUBSYSTEM=="usb", ATTR{idVendor}=="33ff", ATTR{idProduct}=="1234", MODE="0666", GROUP="plugdev"
    to /etc/udev/rules.d
    sudo nano /etc/udev/rules.d/01-inkube_usb_permissions.rules

## Running
Adjust settings in Client_config.py
Data readout in cython has to be compiled first (setup_filter.py)
execute main.py to receive data

Start experiment jupyter notebook:
Example scripts in folder Experiments
