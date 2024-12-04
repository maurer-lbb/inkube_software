-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 02/03/2023 02:55:09 PM
-- Design Name: 
-- Module Name: i2c_interface - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity i2c_interface is
    Port ( 
        CLK100MHZ         : in    std_logic;
        
        temperature       : out   std_logic_vector(15 downto 0);
        humidity          : out   std_logic_vector(15 downto 0);
        co2_concentration : out   std_logic_vector(15 downto 0);
        
        sda_out           : out std_logic;
        scl_out           : out std_logic;
        scl_in            : in std_logic;
        sda_in            : in std_logic;
        
        calibrate_co2     : in std_logic;
        running_i2c_init  : in std_logic;
        running_co2_calib : in std_logic;
        
        debug_sig         : out std_logic_vector(1 downto 0)
    );
end i2c_interface;

architecture Behavioral of i2c_interface is
    component i2c_master is
        Generic (clk_freq    : integer := 100000000;
                 bus_freq    : integer :=     20000
                 );
        Port    (CLK100MHZ   : in    std_logic;
                 scl_out     : out std_logic;
                 sda_out     : out std_logic;
                 scl_in      : in std_logic;
                 sda_in      : in std_logic;
                 
                 data_in     : in    std_logic_vector(7 downto 0);
                 data_out    : out   std_logic_vector(7 downto 0);
                 
                 busy        : out  std_logic;
                 error       : out  std_logic;
                 
                 send_ack    : in   std_logic;                     -- Send and ack if 1 and Reading, otherwise, send a nack.
                 data_dir    : in   std_logic;                     -- 0: Write, 1: Read
                 start_type  : in   std_logic_vector(1 downto 0);  -- 0: no start condition, 1: start condition, 2: restart condition, 3: reserved
                 start       : in   std_logic;                     -- Set to 1 in order to start the send sequence
                 is_finished : in   std_logic                      -- 1 iff a stop condition should be sent 
                 );
    end component;
    
    signal data_MOSI   : std_logic_vector(7 downto 0);
    signal data_MISO   : std_logic_vector(7 downto 0);
    signal busy        : std_logic;
    signal error       : std_logic;
    signal send_ack    : std_logic;
    signal data_dir    : std_logic;
    signal start_type  : std_logic_vector(1 downto 0);
    signal start       : std_logic;
    signal is_finished : std_logic;
    
    signal status      : integer range 0 to 127 := 0;
    
    signal counter     : integer range 0 to 2147483647 := 0; -- Every 5000 ms
    
    signal data_8_1    : std_logic_vector(7 downto 0);
    signal data_8_2    : std_logic_vector(7 downto 0);
    
    signal data_co2_buf  : std_logic_vector(7 downto 0);
    signal data_hum_buf  : std_logic_vector(7 downto 0);
    signal data_temp_buf : std_logic_vector(7 downto 0);
    
    signal sda_out_buf : std_logic;
    signal scl_out_buf : std_logic;
    
    signal temperature_buf       : std_logic_vector(15 downto 0) := "0111011111110011"; -- 37 degC
    signal humidity_buf          : std_logic_vector(15 downto 0) := "1000000000000000"; -- 50 %
    signal co2_concentration_buf : std_logic_vector(15 downto 0) := "0100000000000000"; --  0 %
    
    signal temp_for_co2_sensor   : std_logic_vector(15 downto 0);
    signal temp_temp_sensor      : integer;
    
    signal state_i2c_init  : std_logic := '1';
    signal state_co2_cal   : std_logic := '1';
    signal reset_i2c_init  : std_logic := '1';
    signal reset_co2_cal   : std_logic := '1';
    
begin
    scl_out <= scl_out_buf;
    sda_out <= sda_out_buf;

    temperature       <= temperature_buf;
    humidity          <= humidity_buf;
    co2_concentration <= co2_concentration_buf;
    
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            temp_temp_sensor    <= to_integer(unsigned(temperature_buf))*35000;
            temp_for_co2_sensor <= std_logic_vector(to_unsigned(temp_temp_sensor-589820000,32)(31 downto 16)); -- 589820000 =(almost) 45�200�65536. Exact value is based on SHTC3 temp at 0 degC
        end if;
    end process;

    i2c: i2c_master port map(
        CLK100MHZ   => CLK100MHZ,
        scl_out     => scl_out_buf,
        sda_out     => sda_out_buf,
        scl_in      => scl_in,
        sda_in      => sda_in,
        
        data_in     => data_MOSI,
        data_out    => data_MISO,
         
        busy        => busy,
        error       => error,
         
        send_ack    => send_ack,
        data_dir    => data_dir,
        start_type  => start_type,
        start       => start,
        is_finished => is_finished
    );
    
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if counter = 99999999 then -- 2147483647 
                counter <= 0;
            else
                counter <= counter + 1;
            end if;
        end if;
    end process;
    
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if running_i2c_init = '1' then
                state_i2c_init <= '1';
            elsif reset_i2c_init = '1' then
                state_i2c_init <= '0';
            end if;
        end if;
    end process;
    
    debug_sig(0) <= state_i2c_init;
    debug_sig(1) <= state_co2_cal;
    
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if running_co2_calib = '1' then
                state_co2_cal <= '1';
            elsif reset_co2_cal = '1' then
                state_co2_cal <= '0';
            end if;
        end if;
    end process;
    
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            reset_i2c_init <= '0';
            reset_co2_cal  <= '0';
            
            case status is
                when  0 => if calibrate_co2 = '1' then
                               status <= 120; 
                           else
                               status <= 10; 
                           end if;
                           start <= '0';
                          -- Reset the I2C
                when 10 => data_MOSI   <= "11111111";
                           send_ack    <= '0';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if counter = 1000 then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 11  => data_MOSI   <= "11111111";
                           send_ack    <= '0';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '1';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                          
                          -- Init CO2 sensor
                when 12  => data_MOSI   <= "01010010"; -- Disable CRC (1)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "01";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 13  => data_MOSI   <= "00110111"; -- Disable CRC (2)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 14  => data_MOSI   <= "01101000"; -- Disable CRC (3)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '1';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                           
                when 15  => data_MOSI   <= "01010010"; -- Choose CO2 in air @ 100% (1)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "01";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 16  => data_MOSI   <= "00110110"; -- Choose CO2 in air @ 100% (2)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 17  => data_MOSI   <= "00010101"; -- Choose CO2 in air @ 100% (3)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 18  => data_MOSI   <= "00000000"; -- Choose CO2 in air @ 100% (4)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 19  => data_MOSI   <= "00000001"; -- Choose CO2 in air @ 100% (5)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '1';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                          
                when 20 => data_MOSI   <= "01010010"; -- switch off autmatic calibration (1)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "01";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 21 => data_MOSI   <= "00111111"; -- switch off autmatic calibration (2)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 22 => data_MOSI   <= "01101110"; -- switch off autmatic calibration (3)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '1';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                          
                when 23 => data_MOSI   <= "01010010"; -- Set pressure @ 1013 mBar (1)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "01";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 24 => data_MOSI   <= "00110110"; -- Set pressure @ 1013 mBar (2)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 25 => data_MOSI   <= "00101111"; -- Set pressure @ 1013 mBar (3)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 26 => data_MOSI   <= "00000011"; -- Set pressure @ 1013 mBar (4)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 27 => data_MOSI   <= "11110101"; -- Set pressure @ 1013 mBar (5)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '1';
                           if busy = '0' then status <= status + 1; start <= '1'; else start <= '0'; end if;

                          -- Init Temp sensor
                when 28 => data_MOSI   <= "11100000"; -- (1-1)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "01";
                           is_finished <= '0';
                           if counter = 25000000 and busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 29 => data_MOSI   <= "10110000"; -- (1-2)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 30 => data_MOSI   <= "10011000"; -- (1-3)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '1';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                          
                when 31 => data_MOSI   <= "11100000"; -- (2-1)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "01";
                           is_finished <= '0';
                           if counter = 50000000 and busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 32 => data_MOSI   <= "00110101"; -- (2-2)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 33 => data_MOSI   <= "00010111"; -- (2-3)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '1';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                          
                when 34 => data_MOSI   <= "11100000"; -- (3-1)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "01";
                           is_finished <= '0';
                           if counter = 75000000 and busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 35 => data_MOSI   <= "10000000"; -- (3-2)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 36 => data_MOSI   <= "01011101"; -- (3-3)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '1';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                          
                when 37 => data_MOSI   <= "11100000"; -- (4-1)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "01";
                           is_finished <= '0';
                           if counter = 0 and busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 38 => data_MOSI   <= "01111000"; -- (4-2)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 39 => data_MOSI   <= "01100110"; -- (4-3)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '1';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;   
                          -- End of initialization
                          
                          -- Cycle
                when 40 => data_MOSI   <= "11100000"; -- (1-1)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "01";
                           is_finished <= '0';
                           if counter = 0 and busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 41 => data_MOSI   <= "01111000"; -- (1-2)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 42 => data_MOSI   <= "01100110"; -- (1-3)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '1';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                           
                when 43 => data_MOSI   <= "01010010"; -- Do measurement (1)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "01";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 44 => data_MOSI   <= "00110110"; -- Do measurement (2)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 45 => data_MOSI   <= "00111001"; -- Do measurement (3)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '1';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                           
                when 46 => status <= status+1; start <= '1';
                when 47 => status <= status+1; start <= '1';
                when 48 => status <= status+1; start <= '1';
                when 49 => status <= status+1; start <= '1';
                when 50 => status <= status+1; start <= '1';
                when 51 => status <= status+1; start <= '1';   
                
                -- Reading
                when 52 => status <= status+1; start <= '1';
                when 53 => status <= status+1; start <= '1';
                when 54 => status <= status+1; start <= '1';
                when 55 => status <= status+1; start <= '1';
                when 56 => status <= status+1; start <= '1';
                when 57 => status <= status+1; start <= '1';
                when 58 => status <= status+1; start <= '1';
                when 59 => status <= status+1; start <= '1';
               
                -- Reading out CO2 value
                when 60 => data_MOSI   <= "01010011";
                          send_ack    <= '1';
                          data_dir    <= '0';
                          start_type  <= "01";
                          is_finished <= '0';
                          if counter = 60000000 and busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;     
                when 61 => send_ack    <= '1';
                          data_dir    <= '1';
                          start_type  <= "00";
                          is_finished <= '0';
                          if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 62 => send_ack    <= '1';
                          data_dir    <= '1';
                          start_type  <= "00";
                          is_finished <= '0';
                          if busy = '0' then status <= status+1; start <= '1'; data_co2_buf <= data_MISO; else start <= '0'; end if;
                when 63 => send_ack    <= '0';
                          data_dir    <= '1';
                          start_type  <= "00";
                          is_finished <= '1';
                          if busy = '0' then status <= status+1; start <= '1'; co2_concentration_buf(7 downto 0) <= data_MISO; co2_concentration_buf(15 downto 8) <= data_co2_buf; else start <= '0'; end if;
                
                -- Reading out temp and humidity       
                when 64 => data_MOSI   <= "11100001";
                          send_ack    <= '1';
                          data_dir    <= '0';
                          start_type  <= "01";
                          is_finished <= '0';
                          if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;     
                when 65 => send_ack    <= '1';
                          data_dir    <= '1';
                          start_type  <= "00";
                          is_finished <= '0';
                          if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 66 => send_ack    <= '1';
                          data_dir    <= '1';
                          start_type  <= "00";
                          is_finished <= '0';
                          if busy = '0' then status <= status+1; start <= '1'; data_temp_buf <= data_MISO; else start <= '0'; end if;
                when 67 => send_ack    <= '1';
                          data_dir    <= '1';
                          start_type  <= "00";
                          is_finished <= '0';
                          if busy = '0' then status <= status+1; start <= '1'; temperature_buf(7 downto 0) <= data_MISO; temperature_buf(15 downto 8) <= data_temp_buf; else start <= '0'; end if;
                when 68 => send_ack    <= '1';
                          data_dir    <= '1';
                          start_type  <= "00";
                          is_finished <= '0';
                          if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 69 => send_ack    <= '1';
                          data_dir    <= '1';
                          start_type  <= "00";
                          is_finished <= '0';
                          if busy = '0' then status <= status+1; start <= '1'; data_hum_buf <= data_MISO; else start <= '0'; end if;
                when 70 => send_ack    <= '0';
                          data_dir    <= '1';
                          start_type  <= "00";
                          is_finished <= '1';
                          if busy = '0' then status <= status+1; start <= '1'; humidity_buf(7 downto 0) <= data_MISO; humidity_buf(15 downto 8) <= data_hum_buf; else start <= '0'; end if;
                
		        -- Updating temp and hum data on CO2 sensor
                when 71 => data_MOSI   <= "01010010"; -- Set humidity (1)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "01";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 72 => data_MOSI   <= "00110110"; -- Set humidity (2)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 73 => data_MOSI   <= "00100100"; -- Set humidity (3)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 74 => data_MOSI   <= humidity_buf(15 downto 8); -- Set humidity (4)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 75 => data_MOSI   <= humidity_buf(7 downto 0); -- Set humidity (5)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '1';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
		
                when 76 => data_MOSI   <= "01010010"; -- Set temperature (1)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "01";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 77 => data_MOSI   <= "00110110"; -- Set temperature (2)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 78 => data_MOSI   <= "00011110"; -- Set temperature (3)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 79 => data_MOSI   <= temp_for_co2_sensor(15 downto 8); -- Set temperature (4)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '0';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 80 => data_MOSI   <= temp_for_co2_sensor(7 downto 0); -- Set temperature (5)
                           send_ack    <= '1';
                           data_dir    <= '0';
                           start_type  <= "00";
                           is_finished <= '1';
                           if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
               
                when 81 => start  <= '0';  
                           if state_i2c_init = '1' then
                               reset_i2c_init <= '1';
                               status <= 10;
                           elsif state_co2_cal = '1' then
                               reset_co2_cal <= '1';
                               status <= 123;
                           else
                               status <= 40;
                           end if;
                           
                           
                -- CO2 sensor recalibration (setting to 0%; other values also possible)
                -- Potentially run at the very beginning
                when 120 => data_MOSI   <= "01010010"; -- recalibration (1)
                            send_ack    <= '1';
                            data_dir    <= '0';
                            start_type  <= "01";
                            is_finished <= '0';
                            if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 121 => data_MOSI   <= "00110110"; -- recalibration (2)
                            send_ack    <= '1';
                            data_dir    <= '0';
                            start_type  <= "00";
                            is_finished <= '0';
                            if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 122 => data_MOSI   <= "01100001"; -- recalibration (3)
                            send_ack    <= '1';
                            data_dir    <= '0';
                            start_type  <= "00";
                            is_finished <= '1';
                            if busy = '0' then status <= 10; start <= '1'; else start <= '0'; end if;
                            
                           
                -- CO2 sensor recalibration (setting to 0%; other values also possible)
                -- Potentially run in cyle
                when 123 => data_MOSI   <= "01010010"; -- recalibration (1)
                            send_ack    <= '1';
                            data_dir    <= '0';
                            start_type  <= "01";
                            is_finished <= '0';
                            if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 124 => data_MOSI   <= "00110110"; -- recalibration (2)
                            send_ack    <= '1';
                            data_dir    <= '0';
                            start_type  <= "00";
                            is_finished <= '0';
                            if busy = '0' then status <= status+1; start <= '1'; else start <= '0'; end if;
                when 125 => data_MOSI   <= "01100001"; -- recalibration (3)
                            send_ack    <= '1';
                            data_dir    <= '0';
                            start_type  <= "00";
                            is_finished <= '1';
                            if busy = '0' then status <= 40; start <= '1'; else start <= '0'; end if;
                           
                when others => status <= 81; start <= '0';
            end case;
        end if;
    end process;

end Behavioral;
