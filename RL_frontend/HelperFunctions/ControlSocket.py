# Add this after your other imports
import zmq
import pickle

ZMQ_CONTROL_PUB_SOCKET = "tcp://127.0.0.1:5521"

def initialize_control_socket():
    # Create command publisher (add this in main or as global)
    context = zmq.Context.instance()
    command_push_socket = context.socket(zmq.PUSH)
    command_push_socket.connect(ZMQ_CONTROL_PUB_SOCKET)

    return command_push_socket

# Function to send commands
def send_control_command(command_dict, command_push_socket):
    command_push_socket.send(pickle.dumps(command_dict))
    print(f"Command sent: {command_dict}")

# Function to send commands
def send_frequency_command(frequency, command_push_socket):
    send_control_command({"frequency": frequency}, command_push_socket)

def send_stim_amp_command(stim_amp, command_push_socket):
    send_control_command({"stim_amp": stim_amp}, command_push_socket)

def send_saving_command(saving, command_push_socket):
    send_control_command({"saving": saving}, command_push_socket)

def close_socket(command_push_socket):
    """Close the ZeroMQ socket."""
    command_push_socket.close()
    print("Socket closed.")

# Example usage:
# send_frequency_command(25.5, command_push_socket)