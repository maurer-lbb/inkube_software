import numpy as np
from multiprocessing.managers import BaseManager
import time
import logging
import datetime
import os

class ControlPort:
    """Class to control the inkube device with environment parameters and fluidics"""
    # delay table after which the pump commands are executed
    delay_table = {
        0: "0 ms",
        1: "1 ms",
        2: "2 ms",
        3: "5 ms",
        4: "10 ms",
        5: "20 ms",
        6: "50 ms",
        7: "100 ms",
        8: "200 ms",
        9: "500 ms",
        10: "1 s",
        11: "2 s",
        12: "5 s",
        13: "10 s",
        14: "15 s",
        15: "20 s",
    }

    # command prefixes for SoC
    valve_command_prefix = np.uint32(0)
    pump_command_prefix = np.uint32(1 << 31)

    # RTD constants
    rtd_a = 3.9083e-3
    rtd_b = -5.775e-7
    rtd0 = 1000
    # adjust this according to the resistance on base PCB
    rtd_ref = 4.02e3

    # delays for valve multiplexer (compare with self.delay_table for values in seconds)
    open_delay = 10
    close_delay = 12
    pump_delay = 11
    refill_delay = 15
    retrieve_wait = 30
    wait_mea_close = 5

    pump_wait_per_step = 11/50_000 # multiply with step

    # constants for CO2 sensor
    co2_convert_factor = 100 / 32768
    co2_offset = 16384

    # mea temperature control states
    mea_control_state = [0,0,0,0] # when starting all off, entry 0 is MEA A, 1 MEA B, 2 MEA C, 3 MEA D
    # env control states
    aux_is_humidity = 0
    env_heater_state = 0
    aux_heater_state = 0    
    # co2 control states
    co2_state = 0

    def __init__(
            self, 
            host="127.0.0.1", 
            port=0x1241, 
            auth_key="1234", 
            init_inkulevel=False, 
            init_env=False, 
            do_log=False, 
            MAX_STEPS = 100_000-1, 
        ):
        """ 
        Initialize the control port for inkube device
        Args:
            host: str, IP address of the host PC or localhost
            port: int, port number of the host PC
            auth_key: str, authentication key for the host PC
            init_inkulevel: bool, initialize inkulevel communication, register data exchange and logging
            init_env: bool, initialize environment communication, register data exchange and logging
            do_log: bool, create a log file
            MAX_STEPS: int, endpoint of step motor
        """
        self.do_log = do_log
        if self.do_log:
            self.create_log_file()

        # initial states of valves and pump
        self.valve_states = [0] * 24
        self.MAX_STEPS = MAX_STEPS
        self.pump_position = MAX_STEPS

        self.env_register = 0x43C30000
        self.pump_register = 0x43C4000C
        self.LED_register = 0x41200000
        self.lvl_register = 0x43C50000

        # max number of commands in one package
        self.command_lim = 60 # 60*2*4 is 480, 512 byte is limit for USB bulk package

        self.current_pump_commands = []
        self.current_env_commands = []
        self.current_lvl_commands = []
        
        self.host = host
        self.port = port
        self.auth_key = auth_key
        self.reconnection_tries = 0
        self.max_tries = 5
        self.timeout = 500e-3

        # initialize inkulevel with parameters for data acquisition and procsessing
        self.init_inkulevel = init_inkulevel
              
        self.inkulevel_param_keys = {
            'lower': 0, 
            'upper': 1, 
            'thresh': 2, 
            'exposure': 3, 
            'minpix': 4, 
            'mindist': 5, 
            'peaknum': 6, 
        }
        self.param_factors = [4, 4, 64, 4, 1, 1, 1] # exposure factor 4
        self.inkulvel_param_num = len(self.inkulevel_param_keys)
        self.inkulevel_update_param = [0]*self.inkulvel_param_num 
        self.inkulevel_param = [[0] * 4 for _ in range(self.inkulvel_param_num )]

        # initialize environment control
        self.init_env = init_env

        # start new connection
        self.new_connection()
    
    def create_log_file(self):
        """Create a log file for the control port"""
        # Get the directory where the current script is located
        current_dir = os.path.dirname(os.path.abspath(__file__))

        # Navigate to the 'data' folder in the parent directory
        data_dir = os.path.join(current_dir, '..', 'Data')

        # Normalize the path (remove redundant separators, etc.)
        data_dir = os.path.normpath(data_dir)
        date_for_filename = datetime.datetime.today().strftime('%Y%m%d')[2:]
        id = 0
        data_folder = f'{date_for_filename}_inkube_data'
        if not os.path.isdir(data_dir):
            os.mkdir(data_dir)
        while os.path.isdir(f'{data_dir}/{data_folder}_{id}'):
            id += 1
        os.mkdir(f'{data_dir}/{data_folder}_{id}')
        DATA_FOLDER = f'{data_dir}/{data_folder}_{id}'

        log_id = 0
        subfolder = 'control_data_'
        while os.path.isdir(f'{DATA_FOLDER}/{subfolder}_{log_id}'):
            log_id += 1
        os.mkdir(f'{DATA_FOLDER}/{subfolder}_{log_id}')
        DATA_FOLDER = f'{DATA_FOLDER}/{subfolder}_{log_id}'

        # Configure logging
        self.log_filename = f'{DATA_FOLDER}/inkube_control.log'
        logging.basicConfig(filename=self.log_filename, level=logging.INFO,
                            format='%(asctime)s - %(levelname)s - %(message)s')
        self.logger = logging.getLogger('ControlPort')

    def new_connection(self):
        """Connect to SoC and readout medium level queue"""
        print("\nWait for new connection ...")
        flag = True

        class CommunicationManager(BaseManager):
            pass

        if self.init_inkulevel:
            CommunicationManager.register('level_q')
        if self.init_env:
            CommunicationManager.register('env_q')
        CommunicationManager.register('env_reg_write_send')

        while flag:
            time.sleep(.5*self.reconnection_tries)
            try:
                m = CommunicationManager(
                    address=(self.host, self.port),
                    authkey=self.auth_key.encode("utf-8"),
                )
                m.connect()
                if self.init_inkulevel:
                    self.level_q = m.level_q() 
                # optional for temperature readout
                if self.init_env:
                    self.env_q = m.env_q()

                self.env_command_pipe = m.env_reg_write_send()

                flag = False
                self.reconnection_tries = 0
            except Exception as e:
                if self.reconnection_tries > self.max_tries:
                    flag = False # stop reconnecting
                    print('ERROR: Aborting reconnection, unreachable')
                else:
                    flag = True
                    print(f"Connection Failed with {e}. Retrying...")
                self.reconnection_tries += 1
        if not self.reconnection_tries:
            if self.do_log:
                # Log the command with a timestamp
                timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S.ffff')
                log_entry = f'Successfully connected to Inkube Host'
                self.logger.info(f'{timestamp} - {log_entry}')
            print("Connected")
        else:
            print("Connection could not be established")
            return -1

    def send_commands(self):
        """Transmit commands via network interface to main script"""
        pump_commands = self.current_pump_commands
        env_commands = self.current_env_commands
        lvl_commands = self.current_lvl_commands
        if not isinstance(pump_commands, list):
            pump_commands = [pump_commands]
        if not isinstance(env_commands, list):
            env_commands = [env_commands]
        if not isinstance(lvl_commands, list):
            lvl_commands = [lvl_commands]
        num_commands = len(pump_commands) + len(env_commands) + len(lvl_commands)
        if num_commands > self.command_lim:
            print('Too many writes, please split')
            self.split_commands()

        # create command words
        if num_commands:
            byte_array = b''
            for command in pump_commands:
                byte_array = (
                    byte_array
                    + (self.pump_register).to_bytes(4, "little")
                    + int(command).to_bytes(4, "little")
                )
            for offset, command in env_commands:
                byte_array = (
                    byte_array
                    + (self.env_register + 4 * offset).to_bytes(4, "little")
                    + int(command).to_bytes(4, "little")
                )
                
            for offset, command in lvl_commands:
                byte_array = (
                    byte_array
                    + (self.lvl_register + 4 * offset).to_bytes(4, "little")
                    + int(command).to_bytes(4, "little")
                )
            
            # send commands
            self.env_command_pipe.send(byte_array)
        # enter logging information
        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'Transmitted commands'
            self.logger.info(f'{timestamp} - {log_entry}')
        # reset command lists
        self.current_pump_commands = []
        self.current_env_commands = []
        self.current_lvl_commands = []

    def split_commands(self):
        """Split commands into smaller packages so they don't exceed the maximum number of commands"""
        pump_commands = self.current_pump_commands
        env_commands = self.current_env_commands
        
        self.current_pump_commands = []
        self.current_env_commands = []
        
        end_command_num = 0
        num_split = len(pump_commands)//self.command_lim+1
        for i in range(num_split):
            if i == num_split-1:
                end_command_num = len(pump_commands)
            else:
                end_command_num = (i+1)*self.command_lim

            self.current_pump_commands = pump_commands[i*self.command_lim:end_command_num]
            self.send_commands()

        end_command_num = 0
        num_split = len(env_commands)//self.command_lim+1
        for i in range(num_split):
            if i == num_split-1:
                end_command_num = len(env_commands)
            else:
                end_command_num = (i+1)*self.command_lim

            self.current_env_commands = env_commands[i*self.command_lim:end_command_num]
            self.send_commands()

    # environment control -----------------------------------------------------------------
    def set_mea_temp(self, set_temp=37, mea=[0, 1, 2, 3]):  # start mea at 0
        """
        Set the temperature for the MEA (Microelectrode Array) channels.

        Args:
            set_temp (float): The desired temperature in degrees Celsius.
            mea (list): A list of MEA channel numbers (0-3) to set the temperature for. Defaults to all channels [0, 1, 2, 3].
        """
        encoded_temp = np.uint32(
            2**15
            / self.rtd_ref
            * self.rtd0
            * (1 + self.rtd_a * set_temp + self.rtd_b * set_temp**2)
        )
        if isinstance(mea, list):
            for m in mea:
                if m < 4 and m >= 0:
                    self.current_env_commands.append((m + 4, encoded_temp))
        else:
            if mea < 4 and mea >= 0:
                self.current_env_commands.append((mea + 4, encoded_temp))
        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'SET PARAMETER temperature to VALUE {set_temp} FOR mea {mea}'
            self.logger.info(f'{timestamp} - {log_entry}')

    def set_co2(self, set_co2=5):
        """Set the CO2 concentration in the environment reservoir.
        Args:
            set_co2 (float): The desired CO2 concentration in percentage.
        """
        encoded_co2 = np.uint32(int(set_co2/self.co2_convert_factor + self.co2_offset+.5))
        self.current_env_commands.append((11, encoded_co2))
        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'SET PARAMETER co2 to VALUE {set_co2} FOR reservoir'
            self.logger.info(f'{timestamp} - {log_entry}')
    
    def set_co2_control(self, state=None, calib=0, init=0):
        """Turn the CO2 control on or off and switch the calibration mode.
        Args:
            state (int): The control value. 1 is for on and 0 is for off.
            calib (int): The calibration mode. 1 is for on and 0 is for off.
            init (int): The initialization mode. 1 is for on and 0 is for off.
        """
        control_word = 0x0000_0000
        if state is not None:
            self.co2_state = state
        control_word += self.co2_state
        control_word += calib << 30
        control_word += init << 31

        self.current_env_commands.append((8, np.uint32(control_word)))
        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'SET PARAMETER control_co2 to VALUE {control_word} FOR co2'
            self.logger.info(f'{timestamp} - {log_entry}')

    def set_env_temp(self, set_temp=37):
        """
        Set the temperature for the environment reservoir.

        Args:
            set_temp (float): The desired temperature in degrees Celsius.
        """
        encoded_temp = (45+set_temp)*65535/175
        self.current_env_commands.append((13, encoded_temp))
        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'SET PARAMETER temperature to VALUE {set_temp} FOR reservoir'
            self.logger.info(f'{timestamp} - {log_entry}')

    def set_humidity(self, set_hum=55):
        """
        Set the humidity for the environment reservoir.

        Args:
            set_hum (float): The desired humidity in percentage.
        """
        encoded_hum = np.uint32(set_hum/100*65535)
        self.current_env_commands.append((12, encoded_hum))
        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'SET PARAMETER humidity to VALUE {set_hum} FOR reservoir'
            self.logger.info(f'{timestamp} - {log_entry}')

    def set_mea_control(self, state=1, mea=[0, 1, 2, 3]):
        """
        Turn the MEA tenmperature control on or off.

        Args:
            state (int): The control value. 1 is for on and 0 is for off.
            mea (list): A list of MEA channel numbers (0-3) to set the control for. Defaults to all channels [0, 1, 2, 3].
        """        
        control_word = 0x0000_0000
        # update internal control variable
        if isinstance(mea, list):
            for m in mea:
                if m < 4 and m >= 0:
                    self.mea_control_state[m] = state
        else:
            if mea < 4 and mea >= 0:
                self.mea_control_state[mea] = state

        # derive command word from state
        for pos, state in enumerate(self.mea_control_state):
            control_word += state << (pos * 8)
        # append command
        self.current_env_commands.append((0, np.uint32(control_word)))

        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'SET PARAMETER control_mea to VALUE {state} FOR mea {mea}'
            self.logger.info(f'{timestamp} - {log_entry}')


    def set_env_control(self, temperature=None, aux=None, aux_is_humidity=None):
        """
        Turn the environment temperature control on or off and switch the aux control.
        Args:
            temperature (int): The control value for the environment temperature. 1 is for on and 0 is for off.
            aux (int): The control value for the aux temperature. 1 is for on and 0 is for off.
            aux_is_humidity (int): The control value for the aux temperature. 1 is for humidity and 0 is for temperature.
        """        
        control_word = 0x0000_0000
        # update internal control variable
        if temperature is not None:
            self.env_heater_state = temperature
        if aux is not None: 
            self.aux_heater_state = aux
        if aux_is_humidity is not None:
            self.aux_is_humidity = aux_is_humidity

        # derive command word from state
        control_word += self.env_heater_state << 0
        control_word += self.aux_heater_state << 8
        if self.aux_is_humidity: # set MSB to 0 for separate temperature control register
            control_word += 0x8000_0000
        else:
            control_word += 0x4000_0000

        # append command
        self.current_env_commands.append((1, np.uint32(control_word)))

        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'SET PARAMETER control_env to VALUE {control_word} FOR environment'
            self.logger.info(f'{timestamp} - {log_entry}')  

    def control_write_reg(self, word, offset):
        """create command to write to register on SoC"""
        self.current_env_commands.append((offset, np.uint32(word)))

    def start_init_inkulevel(self):
        """send command for uart daisy chain initialization"""
        self.current_lvl_commands.append((3, np.uint32(0)))
        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'SET PARAMETER init to VALUE 1 FOR inkulevel'
            self.logger.info(f'{timestamp} - {log_entry}')

    def start_inkulevel_send(self, active_lvl = [1,1,1,1]):
        """set the inkulevel to send out measurements via uart"""
        word = 0x0000_0000
        for id, lvl in enumerate(active_lvl):
            word += (1<<id) * int(lvl>0) 
        self.current_lvl_commands.append((1, np.uint32(word)))
        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'SET PARAMETER uart_send to VALUE {active_lvl} FOR inkulevel'
            self.logger.info(f'{timestamp} - {log_entry}')

    def start_inkulevel_debug_bt(self, bt_counter = [0,0,0,0]): 
        """set the counter with which inkulevel sends out pictures via bluetooth"""
        word = 0x0000_0000
        for id, counter in enumerate(bt_counter):
            word += (1<<(id*8)) * (counter % 256) 
        self.current_lvl_commands.append((2, np.uint32(word)))
        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'SET PARAMETER bt_send to VALUE {bt_counter} FOR inkulevel'
            self.logger.info(f'{timestamp} - {log_entry}')

    def get_inkulevel_command(self):
        """create command word which is sent to inkulevel with parameters"""
        for param_id in range(self.inkulvel_param_num ):
            if self.inkulevel_update_param[param_id]:
                word = 0x0000_0000
                for id, value in enumerate(self.inkulevel_param[param_id]):
                    word += (1<<(id*8)) * (value % 256)  
                self.current_lvl_commands.append((param_id+8, np.uint32(word)))       

    def set_inkulevel_param(self, target_inkulevel=[0,1,2,3], param_key='lower', value=[0,0,0,0]): 
        """set parameter for inkulevel"""
        param_id = self.inkulevel_param_keys[param_key]

        for id, n in enumerate(target_inkulevel):
            self.inkulevel_param[param_id][n] = int(value[id]/self.param_factors[param_id] + .5)
        self.inkulevel_update_param[param_id] = 1

        self.get_inkulevel_command()

        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'SET PARAMETER {param_key} to VALUE {value} FOR inkulevel'
            self.logger.info(f'{timestamp} - {log_entry}')

    def send_LED_blink(self, repetitions=1):
        """send command to blink LED"""
        byte_data = b''
        for _ in range(min(self.command_lim, repetitions)):
            byte_data += self.LED_register.to_bytes(4, "little")
            byte_data += (0x0000000F).to_bytes(4, "little")
        self.env_command_pipe.send(byte_data)

    # pump and valve control -----------------------------------------------------------------
    def enable_pump(self):
        """enable actuators (stepper motor and valve driver)"""
        command = (0x43C40010).to_bytes(4, "little") + (0x00000001).to_bytes(4, "little")
        self.env_command_pipe.send(command)
        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'Enabled pump'
            self.logger.info(f'{timestamp} - {log_entry}')

    def get_valve_command(self, delay):
        """create command word which is sent to inkube with pump position, valve settings and delay"""
        valve_command_word = 0
        for valve, state in enumerate(list(self.valve_states)):
            valve_command_word += state << valve
        # print(f"Switch Valves command {bin(valve_command_word)}")
        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'SET PARAMETER on to VALUE {self.valve_states} FOR valves'
            self.logger.info(f'{timestamp} - {log_entry}')
        return self.valve_command_prefix + (delay << 24) + valve_command_word

    def get_pump_command(self, delay):
        """create command word which is sent to inkube with pump position, valve settings and delay"""
        if self.pump_position > self.MAX_STEPS:
            self.pump_position = self.MAX_STEPS
        elif self.pump_position < 0:
            self.pump_position = 0
        if self.do_log:
            # Log the command with a timestamp
            timestamp = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
            log_entry = f'SET PARAMETER position to VALUE {self.pump_position} FOR pump'
            self.logger.info(f'{timestamp} - {log_entry}')
        return self.pump_command_prefix + +(delay << 24) + self.pump_position

    def switch_valve(self, valve, state, delay):
        """SET servo states for valve open/closed, either one element or two lists"""
        if type(valve) == list or type(valve) == np.ndarray:
            if type(valve) == np.ndarray:
                valve = valve.flatten()
                # print(f'Valve state: {valve} of type {type(valve)} and shape {valve.shape}')
            for num_state, v in enumerate(valve):
                self.valve_states[v] = int(np.clip(state[num_state], 0, 1))
        else:
            self.valve_states[valve] = int(np.clip(state, 0, 1))

        self.current_pump_commands.append(self.get_valve_command(delay))

    def pump_rel(self, value, delay):
        """update pump position relative to current"""
        self.pump_position += value
        if self.pump_position > self.MAX_STEPS:
            self.pump_position = self.MAX_STEPS
        elif self.pump_position < 0:
            self.pump_position = 0
        self.current_pump_commands.append(self.get_pump_command(delay))

    def pump_abs(self, value, delay):
        """update pump position as absolute value"""
        self.pump_position = value
        if self.pump_position > self.MAX_STEPS:
            self.pump_position = self.MAX_STEPS
        elif self.pump_position < 0:
            self.pump_position = 0
        self.current_pump_commands.append(self.get_pump_command(delay))
    
    # readout data ----------------------------------------------------------------------

    def get_temperature(self):
        """readout environment data from control port"""
        if not self.init_env:
            print('ERROR: Environment not initialised.')
            return 0
        response = []
        while not self.env_q.empty():
            response.append(self.env_q.get_nowait())
        return response

    def get_level(self):
        """receive element from medium level pipe"""
        if not self.init_inkulevel:
            print('ERROR: Inkulevel not initialised.')
            return 0
        retry_count = 0
        try:
            while (self.level_q.empty()) and retry_count < 600: # wait max 60s for new element
                time.sleep(100e-3)
                retry_count += 1
            if retry_count == 10_000:
                print('Warning: no new element received')
                element = np.full((10, 10), -1)
            while not self.level_q.empty():
                element = self.level_q.get() 
            return element
        except Exception as e:
            print(f"Error: Could not access with {e}, reconnecting")
            if self.new_connection() != -1:
                return self.get_level()

