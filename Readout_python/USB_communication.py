from Client_config import (
    VENDOR_ID, 
    PRODUCT_ID, 
    USB_PREAMBLE, 
    TEST_SERVER, 
    WORD_LENGTH_IN_BYTES, 
    MAX_PKG_ID,
    
    ZMQ_USBCOM_ENDPOINT, 
    connect_to_zmq, 
    drain_zmq_queue, 

)

import usb.core
import usb.util
import time
import numpy as np
import multiprocessing as mp
import multiprocessing.connection as con
import os
import zmq

"""
Before you use USB communication make sure your device is reachable:
lsusb  
- find FPGA
ls -l /dev/bus/usb/00x/00y
- replace 00x with bus ID and 00y with device ID
if no access rights add the rules file 01-inkube_usb_permissions.rules with content:
SUBSYSTEM=="usb", ATTR{idVendor}=="33ff", ATTR{idProduct}=="1234", MODE="0666", GROUP="plugdev"
to /etc/udev/rules.d
sudo nano /etc/udev/rules.d/01-inkube_usb_permissions.rules

"""

class USB_com:
    """Class for the USB communication from the host PC to the FPGA/SoC. This uses USB bulk communication on a single port."""
    def __init__(self):
        self.dev = usb.core.find(idVendor=VENDOR_ID,idProduct=PRODUCT_ID)
        print(f'Connected USB device.')
        try:
            self.dev.detach_kernel_driver(0)
        except usb.core.USBError as e:
            if e.errno == 2:
                pass
        except Exception as e:
            print(f'Error: failed to connect USB device with {e}')
        self.bulk_port = 1
        self.command_id = {'port': 1, 'intan': 2, 'fpga': 3, 'recv_reset': 4, 'intan_dyn': 5}
        self.command_preamble = {
            'port': self.prepare_preamble('port'), 
            'intan': self.prepare_preamble('intan'), 
            'fpga': self.prepare_preamble('fpga'), 
            'recv_reset': self.prepare_preamble('recv_reset'), 
            'intan_dyn': self.prepare_preamble('intan_dyn'), 
        }

    def write_data(self, data: bytearray):
        """send data to the USB device."""
        try:
            self.dev.write(self.bulk_port, data)
            # print(f'Send USB data: {[hex(int(d)) for d in data[12:min(len(data),32)]]}')
            # print(f'Just sent {len(data)} bytes: {data}')
        except Exception as e:
            print(f'Warning: Failed to send USB data with {e}. Trying to detach kernel...')
            self.dev.detach_kernel_driver(0)
            self.write_data(data)

    def prepare_preamble(self, command_key):
        """Prepare the preamble for the USB communication."""
        hex_preamble = USB_PREAMBLE + self.command_id[command_key]
        send_data = bytearray(hex_preamble.to_bytes(8, byteorder='big'))
        return send_data

    def send_recv_port_single(self, port_id):
        """Send a command to the USB device to set the port for USB communication."""
        ignore_recv_word = bytearray(np.array([0, 1, 0, 0], dtype=np.uint8).tobytes())
        recv_package_word = bytearray(np.array([1, 1, 0, 0], dtype=np.uint8).tobytes())
        send_package_tuple = (
            (
                self.command_preamble['recv_reset'] 
                + ignore_recv_word
            ), 
            (
                self.command_preamble['port']
                + recv_package_word
                + b'\x08' # special case to set all ports at once
                + port_id.to_bytes(2, byteorder='little')
            )
        )
        self.write_data(send_package_tuple[0])
        self.write_data(send_package_tuple[1])

        # ignore_recv_word = bytearray(np.array([0, 1, 0, 0], dtype=np.uint8).tobytes())
        # recv_package_word = bytearray(np.array([1, 1, 0, 0], dtype=np.uint8).tobytes())

        # # set the receive counter on the SoC to 0
        # self.write_data(
        #     self.command_preamble['recv_reset']
        #     + ignore_recv_word
        # )
        # # send the port for the USB communication
        # self.write_data(
        #     self.command_preamble['port']
        #     + recv_package_word
        #     + b'\x08' # special case to set all ports at once
        #     + port_id.to_bytes(2, byteorder='little')
        # )
        print(f'Sent UDP port to USB: {port_id}')

    def send_recv_port(self, port_id, recv_pkg_id, retry=1, retry_timeout=500e-3):
        """Send a command to the USB device to set the port for USB communication."""
        ignore_recv_word = bytearray(np.array([0, 1, 0, 0], dtype=np.uint8).tobytes())
        recv_package_word = bytearray(np.array([1, 1, 0, 0], dtype=np.uint8).tobytes())
        while recv_pkg_id[0] != 1:
            # set the receive counter on the SoC to 0
            self.write_data(
                self.command_preamble['recv_reset']
                + ignore_recv_word
            )
            # send the port for the USB communication
            self.write_data(
                self.command_preamble['port']
                + recv_package_word
                + b'\x08' # special case to set all ports at once
                + port_id.to_bytes(2, byteorder='little')
            )
            print(f'Sent UDP port to USB: {port_id}')
            time.sleep(retry_timeout)

    def close(self):
        """Close the USB communication."""
        try:
            self.dev.close()
        except Exception as e:
            pass
        self.dev.finalize()

def send_commands_process_USB(
    com: USB_com, 
    command_to_send_pipe: con.Connection,
    retry_timeout=500e-4,
):
    """Process to send commands to the USB device.
    Args:
        com (USB_com): USB communication object.
        command_to_send_pipe (multiprocessing.connection.Connection): Pipe to receive commands to send to the USB device.
        recv_pkg_id (multiprocessing.connection.Connection): Pipe to receive the incrementing counter of received data on the SoC which makes sure no data is dropped.
        retry_timeout (float, optional): Timeout for the retry. Defaults to 500e-4.
    """
    print(f'PID:{os.getpid()} - Started USB command transmit process.')
    expected_rcv_pkg = 0 # increase to one because port has been send as 1
    is_rcv_pkg = 0

    recv_pkg_socket = connect_to_zmq(ZMQ_USBCOM_ENDPOINT)
    zmq_poller = zmq.Poller()
    zmq_poller.register(recv_pkg_socket, zmq.POLLIN)

    # print(f"USB-process: getting ZMQ data: Recv pkg id {is_rcv_pkg}")

    send_package_tuple = ()
    if not TEST_SERVER:
        print("USB-process: Waiting for first recv pkg")
        is_rcv_pkg = int.from_bytes(recv_pkg_socket.recv(), 'little')
        expected_rcv_pkg = is_rcv_pkg
        while True:
            # Receive prepared commands from Pipe
            command_id, command_to_send = command_to_send_pipe.recv()
            start_time = time.time()
            # print(f"USB-process: Received command {command_id}")
            # command id indicates the type of command
            # 1: send port, no recv package id, not via pipe
            # 2: send intan commands, with recv package id (handshake), directly forwarded to ASIC by the FPGA
            # 3: send fpga commands, with recv package id (handshake), these are register writes directly on the SoC for for example pumping
            # 4: send reset command, with recv package id (handshake), not via pipe

            # if command_id == 1: # send port, no recv package id, not via pipe
            #     ignore_recv_word = bytearray(np.array([0, 1, 0, 0], dtype=np.uint8).tobytes())
            #     recv_package_word = bytearray(np.array([1, 1, 0, 0], dtype=np.uint8).tobytes())
            #     send_package_tuple = (
            #         (
            #             com.command_preamble['recv_reset'] 
            #             + ignore_recv_word
            #         ), 
            #         (
            #             com.command_preamble['port']
            #             + recv_package_word
            #             + b'\x08' # special case to set all ports at once
            #             + command_to_send.to_bytes(2, byteorder='little')
            #         )
            #     )
            #     expected_rcv_pkg = 1 # expect reset + 1 port

            if command_id == 2: # this is a command for the intan
                # check number of commands
                num_commands_in_frame = len(command_to_send) // WORD_LENGTH_IN_BYTES
                
                # send commands separately
                for i in range(num_commands_in_frame):
                    command_to_send[i * WORD_LENGTH_IN_BYTES] = (
                        is_rcv_pkg + 1 + i
                    ) % 256
                    # for non zero in byte 2 the receive id is checked
                    command_to_send[i * WORD_LENGTH_IN_BYTES + 1] = 0xFF
                                
                expected_rcv_pkg = (expected_rcv_pkg + num_commands_in_frame) % 256
                # Reset counter how often package has been sent
                
                send_package_tuple = ()
                for i in range(num_commands_in_frame):
                    send_package_tuple += (
                        com.command_preamble['intan']+command_to_send[i*WORD_LENGTH_IN_BYTES:(i+1)*WORD_LENGTH_IN_BYTES], 
                    )

            elif command_id == 3:
                if len(command_to_send) > 500:
                    print('WARNING: Too many register writes in command')
                    continue
                else:
                    expected_rcv_pkg = (expected_rcv_pkg + 1) % 256
                    
                    recv_package_word = bytearray(np.array([expected_rcv_pkg, 255, 0, 0], dtype=np.uint8).tobytes())
                    send_package_tuple = (
                            com.command_preamble['fpga']
                            + recv_package_word 
                            + command_to_send, 
                        )
                    
            if command_id == 5: # this is a dynamic size command for the intan
                # check number of commands
                num_commands_in_frame = len(command_to_send) # send tuple of packages already
                print(f"USB process: Received {num_commands_in_frame} commands of len {[len(c) for c in command_to_send]}")
                # send commands separately
                for i in range(num_commands_in_frame):
                    command_to_send[i][0] = (
                        is_rcv_pkg + 1 + i
                    ) % 256
                    # for non zero in byte 2 the receive id is checked
                    command_to_send[i][1] = 0xFF
                                
                expected_rcv_pkg = (expected_rcv_pkg + num_commands_in_frame) % 256
                # Reset counter how often package has been sent
                
                send_package_tuple = ()
                for i in range(num_commands_in_frame):
                    send_package_tuple += (
                        com.command_preamble['intan_dyn']+command_to_send[i], 
                    )

            last_recv_pkg = is_rcv_pkg  
            # print(f"Now sending {len(send_package_tuple)} packages with {is_rcv_pkg}")

            for send_package in send_package_tuple:
            #     print(f'================= USB package ======================')
            #     hex_representation = ' '.join(f"{byte:02x} " for byte in send_package)  # Print first few bytes for sanity check
            #     print(f'{hex_representation}')
            #     print(f'----------------- USB package ----------------------')

                repeat_flag = True
                # print(f'Sending Command ID {send_package[7]}')
                last_recv_pkg = (last_recv_pkg + 1) % 256
                while repeat_flag:
                    com.write_data(send_package)
                    if send_package[7] == 4: # for reset command
                        repeat_flag = False
                        last_recv_pkg = 0
                        break
                    # print("Before recv")
                    socks = zmq_poller.poll(timeout=10)
                    if not socks:
                        print("WARNING: No data received from ZMQ - resending")
                    else:
                        is_rcv_pkg = int.from_bytes(recv_pkg_socket.recv(), 'little')

                    # print(f"From USB process getting ZMQ data: Recv pkg id {is_rcv_pkg}")                   
                    if (last_recv_pkg != is_rcv_pkg):
                        print(f"WARNING: Recv wrong package id does not match with {is_rcv_pkg} and {last_recv_pkg}")
                    else:
                        repeat_flag = False
                        # print("Sent package, moving on")

            if expected_rcv_pkg == is_rcv_pkg:
                print(f'{is_rcv_pkg} coms {len(send_package_tuple)} frames took {(time.time()-start_time)*1000:.3f} ms')
            else:
                print(f"WARNING: End Recv package id does not match with {is_rcv_pkg} and {expected_rcv_pkg}")

    else:
        # when debugging with test server, just print the commands in hex that would be sent via USB
        while True:
            command_id, received_bytes = command_to_send_pipe.recv()

            if command_id == 1:
                received_bytes = received_bytes.to_bytes(2, byteorder='little')
            # Convert the received bytes to a numpy array of uint8
            np_array = np.frombuffer(received_bytes, dtype=np.uint8)
            # Calculate the number of uint32 values
            num_uint32_values = len(np_array) // 4
            # Use numpy's view to interpret the array as uint32
            uint32_array = np_array[:num_uint32_values * 4].view(dtype=np.uint32)
            # Convert the uint32 values to hex representation
            hex_representation = [format(val, '08x') for val in uint32_array]

            if False:
                print(f'Received command {command_id} with {len(received_bytes)} Bytes, first 4 commands: {hex_representation[:4]}')
                print(f'---------------------------')
                if command_id == 2:
                    for n in range(len(hex_representation)//(WORD_LENGTH_IN_BYTES//4)):
                        print(f'Time point: {int(hex_representation[n*WORD_LENGTH_IN_BYTES//4+1], 16)}')
                        for i in range(((WORD_LENGTH_IN_BYTES)//4-2)//4): # go through chips
                            for c in range(4):
                                if int(hex_representation[n*WORD_LENGTH_IN_BYTES//4+2+i*4+c][2:4], 16) < 254:
                                    print(f'MEA {i//4} Chip {i%4} Command_ID: {c} Register: {int(hex_representation[n*WORD_LENGTH_IN_BYTES//4+2+i*4+c][2:4], 16):02d} Data: {int(hex_representation[n*WORD_LENGTH_IN_BYTES//4+2+i*4+c][4:], 16):016b}')
            
            if True:
                """Prints structured debug information for received command frames"""
                
                np_array = np.frombuffer(received_bytes, dtype=np.uint8)  # Convert bytes to NumPy array
                hex_representation = ' '.join(f"{byte:02x}" for byte in received_bytes[:16])  # Print first few bytes for sanity check
                
                print(f"Received command {command_id} with {len(received_bytes)} Bytes, first 16 bytes: {hex_representation}")
                print(f"---------------------------")
                
                if command_id == 5:
                    print(f"recv_placeholder: {format(np_array[:4].view(dtype=np.uint32)[0], '08x')}")  # First 4 bytes as uint32
                    reader = 4  # Start after recv_placeholder
                    
                    while reader < np_array.size:
                        # Read package ID
                        pkg_id = np_array[reader:reader+4].view(dtype=np.uint32)[0]
                        print(f"PKG ID: {format(pkg_id, '08x')}")
                        reader += 4  # Move reader forward
                        
                        # Read number of chips in this sub-frame
                        chip_count = np_array[reader]
                        print(f"Chip count: {chip_count:02x}")
                        reader += 1  # Move reader forward
                        
                        # **Iterate through chips and commands**
                        for _ in range(chip_count):
                            chip_info = np_array[reader]
                            chip_id = (chip_info & 0xF0) >> 4  # Extract upper 4 bits
                            command_count = chip_info & 0x0F  # Extract lower 4 bits
                            print(f"  Chip ID: {chip_id}, Command Count: {command_count}")
                            reader += 1  # Move reader forward

                            # **Iterate through commands for this chip**
                            for cmd in range(command_count):
                                value = np_array[reader:reader+2].view(dtype=np.dtype('<u2'))[0]  # Register (2 bytes)
                                reg = np_array[reader+2:reader+4].view(dtype=np.dtype('<u2'))[0]  # Value (2 bytes)
                                print(f"    Command {cmd+1}: Register {format(reg, '04x')} → Value {format(value, '04x')}")
                                reader += 4  # Move reader to next command

                print(f"--------------------------- End of Command Debug ---------------------------")

                        
            

def relay_fpga_commands_process(
    env_commands_pipe: con.Connection,
    command_to_send_pipe: con.Connection,  
):
    """Process to receive register writes to the FPGA from the ControlPort Jupyter Client and send them to the USB communication process.
    Args:
        env_commands_pipe (multiprocessing.connection.Connection): Pipe to receive commands from the ControlPort JupyterClient through a network socket.
        command_to_send_pipe (multiprocessing.connection.Connection): Pipe to send commands to the USB communication process.
    """
    while True:
        commands_to_send = env_commands_pipe.recv() # only register writes as 32 bit words
        # put bare commands on send pipe together with command id
        command_to_send_pipe.send((3, commands_to_send))

# main function to test USB communication
# connect USB and send LED blink commands
if __name__ == '__main__':
    com = USB_com()
    # com.write_data(
    #     com.command_preamble['recv_reset']
    #     + (0x00000100).to_bytes(4, 'little') # this command should reset the recv_package counter on the FPGA
    # )
    com.write_data(
        com.command_preamble['intan_dyn']
        + (0x000000ff).to_bytes(4, 'little') # ignore counting
        + (0x00000000).to_bytes(4, 'little') # pkg_id for execution is 0   
        + (0x00).to_bytes(1, 'little') # chip count is 0
        # + (0x0000000F).to_bytes(4, 'little')
    )

    for _ in range(5):
        # send LED blink command with 16 flashes
        com.write_data(
            com.command_preamble['fpga']
            + (0x0000ff02).to_bytes(4, 'little')
            + (0x41200000).to_bytes(4, 'little')
            + (0x0000000F).to_bytes(4, 'little')
        )
    com.close()