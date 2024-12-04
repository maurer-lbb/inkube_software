-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 08/05/2021 10:26:17 AM
-- Design Name: 
-- Module Name: spi_interface - Behavioral
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

entity spi_interface is
    Port (
        clk           : in  std_logic;
        resetn        : in  std_logic;
        
        package_count : out std_logic_vector(31 downto 0);
        word_count    : out std_logic_vector(31 downto 0);
        run           : in  std_logic;
        init          : in  std_logic;
        
        phase_1       : in std_logic_vector(3 downto 0);
        phase_2       : in std_logic_vector(3 downto 0);
        
        fifo_length   : in  std_logic_vector(15 downto 0); 
        write_en      : out std_logic;
        write_data    : out std_logic_vector(31 downto 0);
        
        INTAN_CS      : out std_logic;
        INTAN_CLK     : out std_logic;
        INTAN_MOSI_1  : out std_logic_vector(3 downto 0);
        INTAN_MOSI_2  : out std_logic_vector(3 downto 0);
        INTAN_MOSI_3  : out std_logic_vector(3 downto 0);
        INTAN_MOSI_4  : out std_logic_vector(3 downto 0);
        INTAN_MISO_1  : in  std_logic_vector(3 downto 0);
        INTAN_MISO_2  : in  std_logic_vector(3 downto 0);
        INTAN_MISO_3  : in  std_logic_vector(3 downto 0);
        INTAN_MISO_4  : in  std_logic_vector(3 downto 0);
        
        COUNTER_IN    : in  std_logic_vector(31 downto 0);
            
        command_11    : in  std_logic_vector(31 downto 0);
        command_12    : in  std_logic_vector(31 downto 0);
        command_13    : in  std_logic_vector(31 downto 0);
        command_14    : in  std_logic_vector(31 downto 0);
        command_21    : in  std_logic_vector(31 downto 0);
        command_22    : in  std_logic_vector(31 downto 0);
        command_23    : in  std_logic_vector(31 downto 0);
        command_24    : in  std_logic_vector(31 downto 0);
        command_31    : in  std_logic_vector(31 downto 0);
        command_32    : in  std_logic_vector(31 downto 0);
        command_33    : in  std_logic_vector(31 downto 0);
        command_34    : in  std_logic_vector(31 downto 0);
        command_41    : in  std_logic_vector(31 downto 0);
        command_42    : in  std_logic_vector(31 downto 0);
        command_43    : in  std_logic_vector(31 downto 0);
        command_44    : in  std_logic_vector(31 downto 0);
        
        package_loss  : in std_logic;
        
        temperature_1 : in std_logic_vector(14 downto 0);
        temperature_2 : in std_logic_vector(14 downto 0);
        temperature_3 : in std_logic_vector(14 downto 0);
        temperature_4 : in std_logic_vector(14 downto 0);
		
		level_out_1   : in  std_logic_vector(31 downto 0);
		level_out_2   : in  std_logic_vector(31 downto 0);
		level_out_3   : in  std_logic_vector(31 downto 0);
		level_out_4   : in  std_logic_vector(31 downto 0);
        
        temperature_reservoir : in std_logic_vector(15 downto 0);
        humidity_reservoir : in std_logic_vector(15 downto 0);
        co2_concentration_reservoir : in std_logic_vector(15 downto 0)
    );
end spi_interface;

architecture Behavioral of spi_interface is
    signal init_cs      : std_logic;
    signal init_clk     : std_logic;
    signal init_mosi_1  : std_logic_vector(3 downto 0);
    signal init_mosi_2  : std_logic_vector(3 downto 0);
    signal init_mosi_3  : std_logic_vector(3 downto 0);
    signal init_mosi_4  : std_logic_vector(3 downto 0);
    signal init_phase   : integer range 0 to 8  := 0; 
    signal init_clk_ctr : integer range 0 to 36 := 0;
    signal init_tot_ctr : integer range 0 to 60 := 0;
    
    signal init_send    : std_logic_vector(31 downto 0);
    
    signal run_old      : std_logic;
    signal init_old     : std_logic;
    signal init_running : std_logic;
    signal run_running  : std_logic;
    
    signal run_cs      : std_logic;
    signal run_clk     : std_logic;
    signal run_mosi_1  : std_logic_vector(3 downto 0);
    signal run_mosi_2  : std_logic_vector(3 downto 0);
    signal run_mosi_3  : std_logic_vector(3 downto 0);
    signal run_mosi_4  : std_logic_vector(3 downto 0);
    signal run_phase   : integer range 0 to 8  := 0; 
    signal run_clk_ctr : integer range 0 to 36 := 0;
    signal run_tot_ctr : integer range 0 to 20 := 0;
    signal run_package : integer range 0 to 1562500 := 0;
    
    signal pack_drop          : integer range 0 to 65535 := 0;
    signal pack_drop_old      : integer range 0 to 65535 := 0;
    signal pack_drop_recv     : integer range 0 to 65535 := 0;
    signal pack_drop_recv_old : integer range 0 to 65535 := 0;
    
    signal run_en_send  : std_logic;
    
    signal run_send_11  : std_logic_vector(31 downto 0);
    signal run_send_12  : std_logic_vector(31 downto 0);
    signal run_send_13  : std_logic_vector(31 downto 0);
    signal run_send_14  : std_logic_vector(31 downto 0);
    signal run_send_21  : std_logic_vector(31 downto 0);
    signal run_send_22  : std_logic_vector(31 downto 0);
    signal run_send_23  : std_logic_vector(31 downto 0);
    signal run_send_24  : std_logic_vector(31 downto 0);
    signal run_send_31  : std_logic_vector(31 downto 0);
    signal run_send_32  : std_logic_vector(31 downto 0);
    signal run_send_33  : std_logic_vector(31 downto 0);
    signal run_send_34  : std_logic_vector(31 downto 0);
    signal run_send_41  : std_logic_vector(31 downto 0);
    signal run_send_42  : std_logic_vector(31 downto 0);
    signal run_send_43  : std_logic_vector(31 downto 0);
    signal run_send_44  : std_logic_vector(31 downto 0);
    
    signal run_recv_11  : std_logic_vector(31 downto 0);
    signal run_recv_12  : std_logic_vector(31 downto 0);
    signal run_recv_13  : std_logic_vector(31 downto 0);
    signal run_recv_14  : std_logic_vector(31 downto 0);
    signal run_recv_21  : std_logic_vector(31 downto 0);
    signal run_recv_22  : std_logic_vector(31 downto 0);
    signal run_recv_23  : std_logic_vector(31 downto 0);
    signal run_recv_24  : std_logic_vector(31 downto 0);
    signal run_recv_31  : std_logic_vector(31 downto 0);
    signal run_recv_32  : std_logic_vector(31 downto 0);
    signal run_recv_33  : std_logic_vector(31 downto 0);
    signal run_recv_34  : std_logic_vector(31 downto 0);
    signal run_recv_41  : std_logic_vector(31 downto 0);
    signal run_recv_42  : std_logic_vector(31 downto 0);
    signal run_recv_43  : std_logic_vector(31 downto 0);
    signal run_recv_44  : std_logic_vector(31 downto 0);
    
    signal run_buff_11  : std_logic_vector(31 downto 0);
    signal run_buff_12  : std_logic_vector(31 downto 0);
    signal run_buff_13  : std_logic_vector(31 downto 0);
    signal run_buff_14  : std_logic_vector(31 downto 0);
    signal run_buff_21  : std_logic_vector(31 downto 0);
    signal run_buff_22  : std_logic_vector(31 downto 0);
    signal run_buff_23  : std_logic_vector(31 downto 0);
    signal run_buff_24  : std_logic_vector(31 downto 0);
    signal run_buff_31  : std_logic_vector(31 downto 0);
    signal run_buff_32  : std_logic_vector(31 downto 0);
    signal run_buff_33  : std_logic_vector(31 downto 0);
    signal run_buff_34  : std_logic_vector(31 downto 0);
    signal run_buff_41  : std_logic_vector(31 downto 0);
    signal run_buff_42  : std_logic_vector(31 downto 0);
    signal run_buff_43  : std_logic_vector(31 downto 0);
    signal run_buff_44  : std_logic_vector(31 downto 0);
    
    signal command_1_11 : std_logic_vector(31 downto 0);
    signal command_1_12 : std_logic_vector(31 downto 0);
    signal command_1_13 : std_logic_vector(31 downto 0);
    signal command_1_14 : std_logic_vector(31 downto 0);
    signal command_1_21 : std_logic_vector(31 downto 0);
    signal command_1_22 : std_logic_vector(31 downto 0);
    signal command_1_23 : std_logic_vector(31 downto 0);
    signal command_1_24 : std_logic_vector(31 downto 0);
    signal command_1_31 : std_logic_vector(31 downto 0);
    signal command_1_32 : std_logic_vector(31 downto 0);
    signal command_1_33 : std_logic_vector(31 downto 0);
    signal command_1_34 : std_logic_vector(31 downto 0);
    signal command_1_41 : std_logic_vector(31 downto 0);
    signal command_1_42 : std_logic_vector(31 downto 0);
    signal command_1_43 : std_logic_vector(31 downto 0);
    signal command_1_44 : std_logic_vector(31 downto 0);
    signal command_2_11 : std_logic_vector(31 downto 0);
    signal command_2_12 : std_logic_vector(31 downto 0);
    signal command_2_13 : std_logic_vector(31 downto 0);
    signal command_2_14 : std_logic_vector(31 downto 0);
    signal command_2_21 : std_logic_vector(31 downto 0);
    signal command_2_22 : std_logic_vector(31 downto 0);
    signal command_2_23 : std_logic_vector(31 downto 0);
    signal command_2_24 : std_logic_vector(31 downto 0);
    signal command_2_31 : std_logic_vector(31 downto 0);
    signal command_2_32 : std_logic_vector(31 downto 0);
    signal command_2_33 : std_logic_vector(31 downto 0);
    signal command_2_34 : std_logic_vector(31 downto 0);
    signal command_2_41 : std_logic_vector(31 downto 0);
    signal command_2_42 : std_logic_vector(31 downto 0);
    signal command_2_43 : std_logic_vector(31 downto 0);
    signal command_2_44 : std_logic_vector(31 downto 0);
    signal command_3_11 : std_logic_vector(31 downto 0);
    signal command_3_12 : std_logic_vector(31 downto 0);
    signal command_3_13 : std_logic_vector(31 downto 0);
    signal command_3_14 : std_logic_vector(31 downto 0);
    signal command_3_21 : std_logic_vector(31 downto 0);
    signal command_3_22 : std_logic_vector(31 downto 0);
    signal command_3_23 : std_logic_vector(31 downto 0);
    signal command_3_24 : std_logic_vector(31 downto 0);
    signal command_3_31 : std_logic_vector(31 downto 0);
    signal command_3_32 : std_logic_vector(31 downto 0);
    signal command_3_33 : std_logic_vector(31 downto 0);
    signal command_3_34 : std_logic_vector(31 downto 0);
    signal command_3_41 : std_logic_vector(31 downto 0);
    signal command_3_42 : std_logic_vector(31 downto 0);
    signal command_3_43 : std_logic_vector(31 downto 0);
    signal command_3_44 : std_logic_vector(31 downto 0);
    signal command_4_11 : std_logic_vector(31 downto 0);
    signal command_4_12 : std_logic_vector(31 downto 0);
    signal command_4_13 : std_logic_vector(31 downto 0);
    signal command_4_14 : std_logic_vector(31 downto 0);
    signal command_4_21 : std_logic_vector(31 downto 0);
    signal command_4_22 : std_logic_vector(31 downto 0);
    signal command_4_23 : std_logic_vector(31 downto 0);
    signal command_4_24 : std_logic_vector(31 downto 0);
    signal command_4_31 : std_logic_vector(31 downto 0);
    signal command_4_32 : std_logic_vector(31 downto 0);
    signal command_4_33 : std_logic_vector(31 downto 0);
    signal command_4_34 : std_logic_vector(31 downto 0);
    signal command_4_41 : std_logic_vector(31 downto 0);
    signal command_4_42 : std_logic_vector(31 downto 0);
    signal command_4_43 : std_logic_vector(31 downto 0);
    signal command_4_44 : std_logic_vector(31 downto 0);

begin
    process(clk) is 
    begin
        if(rising_edge(clk)) then
            run_old  <= run;
            init_old <= init;
        end if;
    end process;

    process(clk) is
    begin
        if(rising_edge(clk)) then
            if(resetn='0') then
                init_cs     <= '1';
                init_clk    <= '1';
                init_mosi_1 <= "0000";
                init_mosi_2 <= "0000";
                init_mosi_3 <= "0000";
                init_mosi_4 <= "0000";
                
                init_phase   <= 0;
                init_clk_ctr <= 0;
                init_tot_ctr <= 0;
                
                init_running <= '0';
                
            else
                -- start condition for init
                if (init_old = '0' and init = '1' and run_running = '0') then
                    init_running <= '1';
                    
                    init_cs     <= '1';
                    init_clk    <= '1';
                    init_mosi_1 <= "0000";
                    init_mosi_2 <= "0000";
                    init_mosi_3 <= "0000";
                    init_mosi_4 <= "0000";
                    
                    init_phase   <= 0;
                    init_clk_ctr <= 0;
                    init_tot_ctr <= 0;
                end if;
                
                -- Run the init
                if (init_running = '1') then
                    -- CS signal
                    if init_clk_ctr < 34 then
                        init_CS <= '0';
                    else
                        init_CS <= '1';
                    end if;
                    
                    -- CLK signal
                    if init_clk_ctr >= 1 and init_clk_ctr < 33 and init_phase < 4 then
                        init_CLK <= '1';
                    else
                        init_CLK <= '0';
                    end if;
                    
                    -- Set MOSI's
                    if init_clk_ctr >= 0 and init_clk_ctr < 32 and init_phase = 4 then
                        init_MOSI_1(0) <= init_send(31-init_clk_ctr);
                        init_MOSI_1(1) <= init_send(31-init_clk_ctr);
                        init_MOSI_1(2) <= init_send(31-init_clk_ctr);
                        init_MOSI_1(3) <= init_send(31-init_clk_ctr);
                        init_MOSI_2(0) <= init_send(31-init_clk_ctr);
                        init_MOSI_2(1) <= init_send(31-init_clk_ctr);
                        init_MOSI_2(2) <= init_send(31-init_clk_ctr);
                        init_MOSI_2(3) <= init_send(31-init_clk_ctr);
                        init_MOSI_3(0) <= init_send(31-init_clk_ctr);
                        init_MOSI_3(1) <= init_send(31-init_clk_ctr);
                        init_MOSI_3(2) <= init_send(31-init_clk_ctr);
                        init_MOSI_3(3) <= init_send(31-init_clk_ctr);
                        init_MOSI_4(0) <= init_send(31-init_clk_ctr);
                        init_MOSI_4(1) <= init_send(31-init_clk_ctr);
                        init_MOSI_4(2) <= init_send(31-init_clk_ctr);
                        init_MOSI_4(3) <= init_send(31-init_clk_ctr);
                    end if;
                    
                    -- Get the current word to be send
                    if init_phase = 0 and init_clk_ctr = 0 then
                        case(init_tot_ctr) is
                            when 0      => init_send <= "11000000111111110000000000000000"; -- READ(255)
                            when 1      => init_send <= "10000000001000000000000000000000"; -- WRITE(32,0x0000);
                            when 2      => init_send <= "10000000001000010000000000000000"; -- WRITE(33,0x0000);
                            when 3      => init_send <= "10000000001001101111111111111111"; -- WRITE(38,0xFFFF);
                            when 4      => init_send <= "01101010000000000000000000000000"; -- Clear
                            when 5      => init_send <= "10000000000000000000000100010010"; -- WRITE(0,0x0112); -- This changed from 0x00c7
                            when 6      => init_send <= "10000000000000010000010100011010"; -- WRITE(1,0x051A);
                            when 7      => init_send <= "10000000000000100000000001000000"; -- WRITE(2,0x0040);
                            when 8      => init_send <= "10000000000000110000000010000000"; -- WRITE(3,0x0080); 
                            when 9      => init_send <= "10000000000001000000000000100001"; -- WRITE(4,0x0021); -- This changed from 0x0016
                            when 10     => init_send <= "10000000000001010000000000100101"; -- WRITE(5,0x0025); -- This changed from 0x0017
                            when 11     => init_send <= "10000000000001100000000000010001"; -- WRITE(6,0x0011); -- This changed from 0x00A8
                            when 12     => init_send <= "10000000000001110000000000001010"; -- WRITE(7,0x000A);
                            when 13     => init_send <= "10000000000010001111111111111111"; -- WRITE(8,0xFFFF);
                            when 14     => init_send <= "10100000000010100000000000000000"; -- WRITE(10,0x0000) U;
                            when 15     => init_send <= "10100000000011001111111111111111"; -- WRITE(12,0xFFFF) U;
                            when 16     => init_send <= "10000000001000100000000011100010"; -- WRITE(34,0x00E2);
                            when 17     => init_send <= "10000000001000110000000010101010"; -- WRITE(35,0x00AA);
                            when 18     => init_send <= "10000000001001000000000010000000"; -- WRITE(36,0x0080);
                            when 19     => init_send <= "10000000001001010100111100000000"; -- WRITE(37,0x4F00);
                            when 20     => init_send <= "10100000001010100000000000000000"; -- WRITE(42,0x0000) U;
                            when 21     => init_send <= "10100000001011000000000000000000"; -- WRITE(44,0x0000) U;
                            when 22     => init_send <= "10100000001011100000000000000000"; -- WRITE(46,0x0000) U;
                            when 23     => init_send <= "10100000001100000000000000000000"; -- WRITE(48,0x0000) U;
                            when 24     => init_send <= "10100000010000000000100000000000"; -- WRITE(64,0x0800) U;
                            when 25     => init_send <= "10100000010000010000100000000000"; -- WRITE(65,0x0800) U;
                            when 26     => init_send <= "10100000010000100000100000000000"; -- WRITE(66,0x0800) U;
                            when 27     => init_send <= "10100000010000110000100000000000"; -- WRITE(67,0x0800) U;
                            when 28     => init_send <= "10100000010001000000100000000000"; -- WRITE(68,0x0800) U;
                            when 29     => init_send <= "10100000010001010000100000000000"; -- WRITE(69,0x0800) U;
                            when 30     => init_send <= "10100000010001100000100000000000"; -- WRITE(70,0x0800) U;
                            when 31     => init_send <= "10100000010001110000100000000000"; -- WRITE(71,0x0800) U;
                            when 32     => init_send <= "10100000010010000000100000000000"; -- WRITE(72,0x0800) U;
                            when 33     => init_send <= "10100000010010010000100000000000"; -- WRITE(73,0x0800) U;
                            when 34     => init_send <= "10100000010010100000100000000000"; -- WRITE(74,0x0800) U;
                            when 35     => init_send <= "10100000010010110000100000000000"; -- WRITE(75,0x0800) U;
                            when 36     => init_send <= "10100000010011000000100000000000"; -- WRITE(76,0x0800) U;
                            when 37     => init_send <= "10100000010011010000100000000000"; -- WRITE(77,0x0800) U;
                            when 38     => init_send <= "10100000010011100000100000000000"; -- WRITE(78,0x0800) U;
                            when 39     => init_send <= "10100000010011110000100000000000"; -- WRITE(79,0x0800) U;
                            when 40     => init_send <= "10100000011000000000100000000000"; -- WRITE(96,0x0800) U;
                            when 41     => init_send <= "10100000011000010000100000000000"; -- WRITE(97,0x0800) U;
                            when 42     => init_send <= "10100000011000100000100000000000"; -- WRITE(98,0x0800) U;
                            when 43     => init_send <= "10100000011000110000100000000000"; -- WRITE(99,0x0800) U;
                            when 44     => init_send <= "10100000011001000000100000000000"; -- WRITE(100,0x0800) U;
                            when 45     => init_send <= "10100000011001010000100000000000"; -- WRITE(101,0x0800) U;
                            when 46     => init_send <= "10100000011001100000100000000000"; -- WRITE(102,0x0800) U;
                            when 47     => init_send <= "10100000011001110000100000000000"; -- WRITE(103,0x0800) U;
                            when 48     => init_send <= "10100000011010000000100000000000"; -- WRITE(104,0x0800) U;
                            when 49     => init_send <= "10100000011010010000100000000000"; -- WRITE(105,0x0800) U;
                            when 50     => init_send <= "10100000011010100000100000000000"; -- WRITE(106,0x0800) U;
                            when 51     => init_send <= "10100000011010110000100000000000"; -- WRITE(107,0x0800) U;
                            when 52     => init_send <= "10100000011011000000100000000000"; -- WRITE(108,0x0800) U;
                            when 53     => init_send <= "10100000011011010000100000000000"; -- WRITE(109,0x0800) U;
                            when 54     => init_send <= "10100000011011100000100000000000"; -- WRITE(110,0x0800) U;
                            when 55     => init_send <= "10100000011011110000100000000000"; -- WRITE(111,0x0800) U;
                            when 56     => init_send <= "10000000001000001010101010101010"; -- WRITE(32,0xAAAA);
                            when 57     => init_send <= "10000000001000010000000011111111"; -- WRITE(33,0x00FF);
                            when 58     => init_send <= "11010000111111110000000000000000"; -- READ(255) M;
                            when others => init_send <= "11000000111111110000000000000000"; -- READ(255)
                        end case;
                    end if;
                
                    -- Counting all three counters
                    if init_phase = 7 then
                        init_phase <= 0;
                        if init_clk_ctr = 35 then
                            init_clk_ctr <= 0;
                            if init_tot_ctr = 59 then
                                init_running <= '0';
                            else
                                init_tot_ctr <= init_tot_ctr + 1;
                            end if;
                        else
                            init_clk_ctr <= init_clk_ctr + 1;
                        end if;
                    else
                        init_phase <= init_phase + 1;
                    end if;
                end if;
            end if;
        end if;
	end process;        
	
	
    process(clk) is
    begin
        if(rising_edge(clk)) then
            if(resetn='0') then
                run_cs     <= '1';
                run_clk    <= '1';
                run_mosi_1 <= "0000";
                run_mosi_2 <= "0000";
                run_mosi_3 <= "0000";
                run_mosi_4 <= "0000";
                
                run_send_11 <= (others => '0');
                run_send_12 <= (others => '0');
                run_send_13 <= (others => '0');
                run_send_14 <= (others => '0');
                run_send_21 <= (others => '0');
                run_send_22 <= (others => '0');
                run_send_23 <= (others => '0');
                run_send_24 <= (others => '0');
                run_send_31 <= (others => '0');
                run_send_32 <= (others => '0');
                run_send_33 <= (others => '0');
                run_send_34 <= (others => '0');
                run_send_41 <= (others => '0');
                run_send_42 <= (others => '0');
                run_send_43 <= (others => '0');
                run_send_44 <= (others => '0');
                
                run_phase   <= 0;
                run_clk_ctr <= 0;
                run_tot_ctr <= 0;
                run_package <= 0;
                
                run_running <= '0';
                
            else
                -- start condition for run
                if (run_running = '0' and run = '1' and init_running = '0') then
                    run_running <= '1';
                    
                    run_cs     <= '1';
                    run_clk    <= '1';
                    run_mosi_1 <= "0000";
                    run_mosi_2 <= "0000";
                    run_mosi_3 <= "0000";
                    run_mosi_4 <= "0000";
                    
                    run_phase   <= 0;
                    run_clk_ctr <= 0;
                    run_tot_ctr <= 0;
                    run_package <= 0;
                end if;
                
                -- stop if necessary
                if (run_running = '1' and run = '0' and run_phase = 7 and run_clk_ctr = 35 and run_tot_ctr = 19) then
                    run_running <= '0';
                end if;
                
                -- Run the init
                if (run_running = '1') then
                    -- CS signal
                    if run_clk_ctr < 34 then
                        run_CS <= '0';
                    else
                        run_CS <= '1';
                    end if;
                    
                    -- CLK signal
                    if run_clk_ctr >= 1 and run_clk_ctr < 33 and run_phase < 4 then
                        run_CLK <= '1';
                    else
                        run_CLK <= '0';
                    end if;
                    
                    -- Set MOSI's (This should only be necessary to be correct at run_phase 7 and 0)
                    -- This could for example be as early as run_phase = 1
                    if run_clk_ctr >= 0 and run_clk_ctr < 32 and run_phase = 4 then -- to_integer(unsigned(phase_1)) then
                        run_MOSI_1(0) <= run_send_11(31-run_clk_ctr);
                        run_MOSI_1(1) <= run_send_12(31-run_clk_ctr);
                        run_MOSI_1(2) <= run_send_13(31-run_clk_ctr);
                        run_MOSI_1(3) <= run_send_14(31-run_clk_ctr);
                        run_MOSI_2(0) <= run_send_21(31-run_clk_ctr);
                        run_MOSI_2(1) <= run_send_22(31-run_clk_ctr);
                        run_MOSI_2(2) <= run_send_23(31-run_clk_ctr);
                        run_MOSI_2(3) <= run_send_24(31-run_clk_ctr);
                        run_MOSI_3(0) <= run_send_31(31-run_clk_ctr);
                        run_MOSI_3(1) <= run_send_32(31-run_clk_ctr);
                        run_MOSI_3(2) <= run_send_33(31-run_clk_ctr);
                        run_MOSI_3(3) <= run_send_34(31-run_clk_ctr);
                        run_MOSI_4(0) <= run_send_41(31-run_clk_ctr);
                        run_MOSI_4(1) <= run_send_42(31-run_clk_ctr);
                        run_MOSI_4(2) <= run_send_43(31-run_clk_ctr);
                        run_MOSI_4(3) <= run_send_44(31-run_clk_ctr);
                    end if;
                    
                    -- READ MISO's
                    -- should be on run_phase = 0 but 4 gives more stable results
                    if run_clk_ctr >= 1 and run_clk_ctr < 33 and run_phase = 7 then -- to_integer(unsigned(phase_2)) then 
                        run_recv_11(32 - run_clk_ctr) <= INTAN_MISO_1(0);
                        run_recv_12(32 - run_clk_ctr) <= INTAN_MISO_1(1);
                        run_recv_13(32 - run_clk_ctr) <= INTAN_MISO_1(2);
                        run_recv_14(32 - run_clk_ctr) <= INTAN_MISO_1(3);
                        run_recv_21(32 - run_clk_ctr) <= INTAN_MISO_2(0);
                        run_recv_22(32 - run_clk_ctr) <= INTAN_MISO_2(1);
                        run_recv_23(32 - run_clk_ctr) <= INTAN_MISO_2(2);
                        run_recv_24(32 - run_clk_ctr) <= INTAN_MISO_2(3);
                        run_recv_31(32 - run_clk_ctr) <= INTAN_MISO_3(0);
                        run_recv_32(32 - run_clk_ctr) <= INTAN_MISO_3(1);
                        run_recv_33(32 - run_clk_ctr) <= INTAN_MISO_3(2);
                        run_recv_34(32 - run_clk_ctr) <= INTAN_MISO_3(3);
                        run_recv_41(32 - run_clk_ctr) <= INTAN_MISO_4(0);
                        run_recv_42(32 - run_clk_ctr) <= INTAN_MISO_4(1);
                        run_recv_43(32 - run_clk_ctr) <= INTAN_MISO_4(2);
                        run_recv_44(32 - run_clk_ctr) <= INTAN_MISO_4(3);
                    end if;
                    
                    -- Buffer received signals
                    if run_clk_ctr = 0 and run_phase = 1 then
                        run_buff_11 <= run_recv_11;
                        run_buff_12 <= run_recv_12;
                        run_buff_13 <= run_recv_13;
                        run_buff_14 <= run_recv_14;
                        run_buff_21 <= run_recv_21;
                        run_buff_22 <= run_recv_22;
                        run_buff_23 <= run_recv_23;
                        run_buff_24 <= run_recv_24;
                        run_buff_31 <= run_recv_31;
                        run_buff_32 <= run_recv_32;
                        run_buff_33 <= run_recv_33;
                        run_buff_34 <= run_recv_34;
                        run_buff_41 <= run_recv_41;
                        run_buff_42 <= run_recv_42;
                        run_buff_43 <= run_recv_43;
                        run_buff_44 <= run_recv_44;
                    end if;
                    
                    -- Get the current word to be send
                    if run_phase = 3 and run_clk_ctr = 0 then
                        case(run_tot_ctr) is
                            when 0      => run_send_11 <= command_1_11; -- "11000000111111110000000000000000";
                                           run_send_12 <= command_1_12; -- "11000000111111110000000000000000";
                                           run_send_13 <= command_1_13; -- "11000000111111110000000000000000";
                                           run_send_14 <= command_1_14; -- "11000000111111110000000000000000";
                                           run_send_21 <= command_1_21; -- "11000000111111110000000000000000";
                                           run_send_22 <= command_1_22; -- "11000000111111110000000000000000";
                                           run_send_23 <= command_1_23; -- "11000000111111110000000000000000";
                                           run_send_24 <= command_1_24; -- "11000000111111110000000000000000";
                                           run_send_31 <= command_1_31; -- "11000000111111110000000000000000";
                                           run_send_32 <= command_1_32; -- "11000000111111110000000000000000";
                                           run_send_33 <= command_1_33; -- "11000000111111110000000000000000";
                                           run_send_34 <= command_1_34; -- "11000000111111110000000000000000";
                                           run_send_41 <= command_1_41; -- "11000000111111110000000000000000";
                                           run_send_42 <= command_1_42; -- "11000000111111110000000000000000";
                                           run_send_43 <= command_1_43; -- "11000000111111110000000000000000";
                                           run_send_44 <= command_1_44; -- "11000000111111110000000000000000";
                            when 1      => run_send_11 <= command_2_11; -- "11000000111111110000000000000000";
                                           run_send_12 <= command_2_12; -- "11000000111111110000000000000000";
                                           run_send_13 <= command_2_13; -- "11000000111111110000000000000000";
                                           run_send_14 <= command_2_14; -- "11000000111111110000000000000000";
                                           run_send_21 <= command_2_21; -- "11000000111111110000000000000000";
                                           run_send_22 <= command_2_22; -- "11000000111111110000000000000000";
                                           run_send_23 <= command_2_23; -- "11000000111111110000000000000000";
                                           run_send_24 <= command_2_24; -- "11000000111111110000000000000000";
                                           run_send_31 <= command_2_31; -- "11000000111111110000000000000000";
                                           run_send_32 <= command_2_32; -- "11000000111111110000000000000000";
                                           run_send_33 <= command_2_33; -- "11000000111111110000000000000000";
                                           run_send_34 <= command_2_34; -- "11000000111111110000000000000000";
                                           run_send_41 <= command_2_41; -- "11000000111111110000000000000000";
                                           run_send_42 <= command_2_42; -- "11000000111111110000000000000000";
                                           run_send_43 <= command_2_43; -- "11000000111111110000000000000000";
                                           run_send_44 <= command_2_44; -- "11000000111111110000000000000000";
                            when 18     => run_send_11 <= command_3_11; -- "11000000111111110000000000000000";
                                           run_send_12 <= command_3_12; -- "11000000111111110000000000000000";
                                           run_send_13 <= command_3_13; -- "11000000111111110000000000000000";
                                           run_send_14 <= command_3_14; -- "11000000111111110000000000000000";
                                           run_send_21 <= command_3_21; -- "11000000111111110000000000000000";
                                           run_send_22 <= command_3_22; -- "11000000111111110000000000000000";
                                           run_send_23 <= command_3_23; -- "11000000111111110000000000000000";
                                           run_send_24 <= command_3_24; -- "11000000111111110000000000000000";
                                           run_send_31 <= command_3_31; -- "11000000111111110000000000000000";
                                           run_send_32 <= command_3_32; -- "11000000111111110000000000000000";
                                           run_send_33 <= command_3_33; -- "11000000111111110000000000000000";
                                           run_send_34 <= command_3_34; -- "11000000111111110000000000000000";
                                           run_send_41 <= command_3_41; -- "11000000111111110000000000000000";
                                           run_send_42 <= command_3_42; -- "11000000111111110000000000000000";
                                           run_send_43 <= command_3_43; -- "11000000111111110000000000000000";
                                           run_send_44 <= command_3_44; -- "11000000111111110000000000000000";
                            when 19     => run_send_11 <= command_4_11; -- "11000000111111110000000000000000";
                                           run_send_12 <= command_4_12; -- "11000000111111110000000000000000";
                                           run_send_13 <= command_4_13; -- "11000000111111110000000000000000";
                                           run_send_14 <= command_4_14; -- "11000000111111110000000000000000";
                                           run_send_21 <= command_4_21; -- "11000000111111110000000000000000";
                                           run_send_22 <= command_4_22; -- "11000000111111110000000000000000";
                                           run_send_23 <= command_4_23; -- "11000000111111110000000000000000";
                                           run_send_24 <= command_4_24; -- "11000000111111110000000000000000";
                                           run_send_31 <= command_4_31; -- "11000000111111110000000000000000";
                                           run_send_32 <= command_4_32; -- "11000000111111110000000000000000";
                                           run_send_33 <= command_4_33; -- "11000000111111110000000000000000";
                                           run_send_34 <= command_4_34; -- "11000000111111110000000000000000";
                                           run_send_41 <= command_4_41; -- "11000000111111110000000000000000";
                                           run_send_42 <= command_4_42; -- "11000000111111110000000000000000";
                                           run_send_43 <= command_4_43; -- "11000000111111110000000000000000";
                                           run_send_44 <= command_4_44; -- "11000000111111110000000000000000";
                            when others => run_send_11(31 downto 22) <= "0000100000";
                                           run_send_12(31 downto 22) <= "0000100000";
                                           run_send_13(31 downto 22) <= "0000100000";
                                           run_send_14(31 downto 22) <= "0000100000";
                                           run_send_21(31 downto 22) <= "0000100000";
                                           run_send_22(31 downto 22) <= "0000100000";
                                           run_send_23(31 downto 22) <= "0000100000";
                                           run_send_24(31 downto 22) <= "0000100000";
                                           run_send_31(31 downto 22) <= "0000100000";
                                           run_send_32(31 downto 22) <= "0000100000";
                                           run_send_33(31 downto 22) <= "0000100000";
                                           run_send_34(31 downto 22) <= "0000100000";
                                           run_send_41(31 downto 22) <= "0000100000";
                                           run_send_42(31 downto 22) <= "0000100000";
                                           run_send_43(31 downto 22) <= "0000100000";
                                           run_send_44(31 downto 22) <= "0000100000";
                                           run_send_11(15 downto 0)  <= (others => '0');
                                           run_send_12(15 downto 0)  <= (others => '0');
                                           run_send_13(15 downto 0)  <= (others => '0');
                                           run_send_14(15 downto 0)  <= (others => '0');
                                           run_send_21(15 downto 0)  <= (others => '0');
                                           run_send_22(15 downto 0)  <= (others => '0');
                                           run_send_23(15 downto 0)  <= (others => '0');
                                           run_send_24(15 downto 0)  <= (others => '0');
                                           run_send_31(15 downto 0)  <= (others => '0');
                                           run_send_32(15 downto 0)  <= (others => '0');
                                           run_send_33(15 downto 0)  <= (others => '0');
                                           run_send_34(15 downto 0)  <= (others => '0');
                                           run_send_41(15 downto 0)  <= (others => '0');
                                           run_send_42(15 downto 0)  <= (others => '0');
                                           run_send_43(15 downto 0)  <= (others => '0');
                                           run_send_44(15 downto 0)  <= (others => '0');
                                           run_send_11(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_12(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_13(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_14(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_21(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_22(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_23(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_24(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_31(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_32(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_33(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_34(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_41(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_42(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_43(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                                           run_send_44(21 downto 16) <= std_logic_vector(to_unsigned(run_tot_ctr-2,6));
                        end case;
                    end if;
                
                    -- Counting all three counters
                    if run_phase = 7 then
                        run_phase <= 0;
                        if run_clk_ctr = 35 then
                            run_clk_ctr <= 0;
                            if run_tot_ctr = 19 then
                                run_tot_ctr <= 0;
                                if run_package = 1562499 then -- This is equal to 90 sec (100Mhz/(8*36*20)*90 = 1562500)
                                    run_package <= 0;
                                else
                                    run_package <= run_package + 1;
                                end if;
                            else
                                run_tot_ctr <= run_tot_ctr + 1;
                            end if;
                        else
                            run_clk_ctr <= run_clk_ctr + 1;
                        end if;
                    else
                        run_phase <= run_phase + 1;
                    end if;
                end if;
            end if;
        end if;
	end process;       
	
	-- Decide if we should send data
    process(clk) is
    begin
        if(rising_edge(clk)) then
            if(resetn='0') then 
                run_en_send        <= '0';
                pack_drop          <=  0;
                pack_drop_old      <=  0;
                pack_drop_recv     <=  0;
                pack_drop_recv_old <=  0;
            else
                if package_loss = '1' then
                    pack_drop_recv <= pack_drop_recv + 1;
                end if;
                if run_clk_ctr = 0 and run_phase = 1 and run_tot_ctr = 0 then
                    if unsigned(fifo_length) <= 32768 - 375 then
                        run_en_send        <= '1';
                        pack_drop_old      <= pack_drop;
                        pack_drop          <= 0;
                        pack_drop_recv     <= 0;
                        if package_loss = '1' then
                            pack_drop_recv_old <= pack_drop_recv +1;
                        else
                            pack_drop_recv_old <= pack_drop_recv;
                        end if;
                    else
                        run_en_send <= '0'; -- This implies there is dataloss!
                        pack_drop <= pack_drop + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    
	-- Defining the commands sent to the chips
    process(clk) is
    begin
        if(rising_edge(clk)) then
            if(resetn='0') then 
                command_1_11 <= "11000000111111110000000000000000";
                command_1_12 <= "11000000111111110000000000000000";
                command_1_13 <= "11000000111111110000000000000000";
                command_1_14 <= "11000000111111110000000000000000";
                command_1_21 <= "11000000111111110000000000000000";
                command_1_22 <= "11000000111111110000000000000000";
                command_1_23 <= "11000000111111110000000000000000";
                command_1_24 <= "11000000111111110000000000000000";
                command_1_31 <= "11000000111111110000000000000000";
                command_1_32 <= "11000000111111110000000000000000";
                command_1_33 <= "11000000111111110000000000000000";
                command_1_34 <= "11000000111111110000000000000000";
                command_1_41 <= "11000000111111110000000000000000";
                command_1_42 <= "11000000111111110000000000000000";
                command_1_43 <= "11000000111111110000000000000000";
                command_1_44 <= "11000000111111110000000000000000";
                command_2_11 <= "11000000111111110000000000000000";
                command_2_12 <= "11000000111111110000000000000000";
                command_2_13 <= "11000000111111110000000000000000";
                command_2_14 <= "11000000111111110000000000000000";
                command_2_21 <= "11000000111111110000000000000000";
                command_2_22 <= "11000000111111110000000000000000";
                command_2_23 <= "11000000111111110000000000000000";
                command_2_24 <= "11000000111111110000000000000000";
                command_2_31 <= "11000000111111110000000000000000";
                command_2_32 <= "11000000111111110000000000000000";
                command_2_33 <= "11000000111111110000000000000000";
                command_2_34 <= "11000000111111110000000000000000";
                command_2_41 <= "11000000111111110000000000000000";
                command_2_42 <= "11000000111111110000000000000000";
                command_2_43 <= "11000000111111110000000000000000";
                command_2_44 <= "11000000111111110000000000000000";
                command_3_11 <= "11000000111111110000000000000000";
                command_3_12 <= "11000000111111110000000000000000";
                command_3_13 <= "11000000111111110000000000000000";
                command_3_14 <= "11000000111111110000000000000000";
                command_3_21 <= "11000000111111110000000000000000";
                command_3_22 <= "11000000111111110000000000000000";
                command_3_23 <= "11000000111111110000000000000000";
                command_3_24 <= "11000000111111110000000000000000";
                command_3_31 <= "11000000111111110000000000000000";
                command_3_32 <= "11000000111111110000000000000000";
                command_3_33 <= "11000000111111110000000000000000";
                command_3_34 <= "11000000111111110000000000000000";
                command_3_41 <= "11000000111111110000000000000000";
                command_3_42 <= "11000000111111110000000000000000";
                command_3_43 <= "11000000111111110000000000000000";
                command_3_44 <= "11000000111111110000000000000000";
                command_4_11 <= "11000000111111110000000000000000";
                command_4_12 <= "11000000111111110000000000000000";
                command_4_13 <= "11000000111111110000000000000000";
                command_4_14 <= "11000000111111110000000000000000";
                command_4_21 <= "11000000111111110000000000000000";
                command_4_22 <= "11000000111111110000000000000000";
                command_4_23 <= "11000000111111110000000000000000";
                command_4_24 <= "11000000111111110000000000000000";
                command_4_31 <= "11000000111111110000000000000000";
                command_4_32 <= "11000000111111110000000000000000";
                command_4_33 <= "11000000111111110000000000000000";
                command_4_34 <= "11000000111111110000000000000000";
                command_4_41 <= "11000000111111110000000000000000";
                command_4_42 <= "11000000111111110000000000000000";
                command_4_43 <= "11000000111111110000000000000000";
                command_4_44 <= "11000000111111110000000000000000";
            else
                if run_phase = 2 and run_clk_ctr = 0 then
                case(run_tot_ctr) is
                    when 0 =>
                        command_1_11 <= command_11;
                        command_1_12 <= command_12;
                        command_1_13 <= command_13;
                        command_1_14 <= command_14;
                        command_1_21 <= command_21;
                        command_1_22 <= command_22;
                        command_1_23 <= command_23;
                        command_1_24 <= command_24;
                        command_1_31 <= command_31;
                        command_1_32 <= command_32;
                        command_1_33 <= command_33;
                        command_1_34 <= command_34;
                        command_1_41 <= command_41;
                        command_1_42 <= command_42;
                        command_1_43 <= command_43;
                        command_1_44 <= command_44;
                    when 1 =>
                        command_3_11 <= command_11;
                        command_3_12 <= command_12;
                        command_3_13 <= command_13;
                        command_3_14 <= command_14;
                        command_3_21 <= command_21;
                        command_3_22 <= command_22;
                        command_3_23 <= command_23;
                        command_3_24 <= command_24;
                        command_3_31 <= command_31;
                        command_3_32 <= command_32;
                        command_3_33 <= command_33;
                        command_3_34 <= command_34;
                        command_3_41 <= command_41;
                        command_3_42 <= command_42;
                        command_3_43 <= command_43;
                        command_3_44 <= command_44;
                    when others => null;
                    end case;
                elsif run_phase = 2 and run_clk_ctr = 15 then
                case(run_tot_ctr) is
                    when 0 =>
                        command_2_11 <= command_11;
                        command_2_12 <= command_12;
                        command_2_13 <= command_13;
                        command_2_14 <= command_14;
                        command_2_21 <= command_21;
                        command_2_22 <= command_22;
                        command_2_23 <= command_23;
                        command_2_24 <= command_24;
                        command_2_31 <= command_31;
                        command_2_32 <= command_32;
                        command_2_33 <= command_33;
                        command_2_34 <= command_34;
                        command_2_41 <= command_41;
                        command_2_42 <= command_42;
                        command_2_43 <= command_43;
                        command_2_44 <= command_44;
                    when 1 =>
                        command_4_11 <= command_11;
                        command_4_12 <= command_12;
                        command_4_13 <= command_13;
                        command_4_14 <= command_14;
                        command_4_21 <= command_21;
                        command_4_22 <= command_22;
                        command_4_23 <= command_23;
                        command_4_24 <= command_24;
                        command_4_31 <= command_31;
                        command_4_32 <= command_32;
                        command_4_33 <= command_33;
                        command_4_34 <= command_34;
                        command_4_41 <= command_41;
                        command_4_42 <= command_42;
                        command_4_43 <= command_43;
                        command_4_44 <= command_44;
                    when others => null;
                    end case;
                end if;
            end if;
        end if;
    end process;
    
    -- Sending data
    process(clk) is
    begin
        if(rising_edge(clk)) then
            if(resetn='0') then 
                write_en    <= '0';
                write_data  <= (others => '0');
            else
                if run_clk_ctr >= 1 and run_phase >= 2 and run_en_send = '1' then
                    case(run_tot_ctr) is
                        when 0      => if (run_clk_ctr = 1) then -- We only send enable at run_clk_ctr = 1. <=2 necessary for next step
                                           write_data <= std_logic_vector(to_unsigned(run_package,32));
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;
                                       elsif (run_clk_ctr = 2) then    
                                           write_data <= std_logic_vector(to_unsigned(run_tot_ctr,32));
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;
                                       elsif (run_clk_ctr = 3) then    
                                           write_data(15 downto 0) <= fifo_length;
                                           write_data(21 downto 16) <= (others => '0');
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;
                                       elsif (run_clk_ctr = 4) then    
                                           write_data(15 downto 0)  <= std_logic_vector(to_unsigned(pack_drop_old,16));
                                           write_data(31 downto 16) <= std_logic_vector(to_unsigned(pack_drop_recv_old,16));
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;
                                       elsif (run_clk_ctr = 5) then    
                                           write_data <= COUNTER_IN;
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;    
                                       elsif (run_clk_ctr = 6) then    
                                           write_data(31 downto 15) <= (others => '0');
                                           write_data(14 downto 0)  <= temperature_1;  
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;      
                                       elsif (run_clk_ctr = 7) then    
                                           write_data(31 downto 15) <= (others => '0');
                                           write_data(14 downto 0)  <= temperature_2;
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;      
                                       elsif (run_clk_ctr = 8) then    
                                           write_data(31 downto 15) <= (others => '0');
                                           write_data(14 downto 0)  <= temperature_3;
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;      
                                       elsif (run_clk_ctr = 9) then    
                                           write_data(31 downto 15) <= (others => '0');
                                           write_data(14 downto 0)  <= temperature_4;
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;   
                                       elsif (run_clk_ctr = 10) then    
                                           write_data(31 downto 16) <= (others => '0');
                                           write_data(15 downto 0)  <= temperature_reservoir;
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;   
                                       elsif (run_clk_ctr = 11) then    
                                           write_data(31 downto 16) <= (others => '0');
                                           write_data(15 downto 0)  <= humidity_reservoir;
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;   
                                       elsif (run_clk_ctr = 12) then    
                                           write_data(31 downto 16) <= (others => '0');
                                           write_data(15 downto 0)  <= co2_concentration_reservoir;
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;      
                                       elsif (run_clk_ctr = 13) then    
                                           write_data <= "10111011101110111011101110111011";
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;     
                                       elsif (run_clk_ctr = 14) then    
                                           write_data <= level_out_1;
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;     
                                       elsif (run_clk_ctr = 15) then    
                                           write_data <= level_out_2;
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;     
                                       elsif (run_clk_ctr = 16) then    
                                           write_data <= level_out_3;
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;     
                                       elsif (run_clk_ctr = 17) then    
                                           write_data <= level_out_4;
                                           if (run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;      
                                       else
                                           write_data <= "10101010010101011010101001010101"; -- for package "padding" (3 times)
                                           if (run_clk_ctr < 21 and run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;
                                       end if;
                            when 1      => if (run_clk_ctr < 33 and run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;
                                       case(run_clk_ctr) is
                                           when 1      => write_data <= command_1_11;
                                           when 2      => write_data <= command_1_12;
                                           when 3      => write_data <= command_1_13;
                                           when 4      => write_data <= command_1_14;
                                           when 5      => write_data <= command_1_21;
                                           when 6      => write_data <= command_1_22;
                                           when 7      => write_data <= command_1_23;
                                           when 8      => write_data <= command_1_24;
                                           when 9      => write_data <= command_1_31;
                                           when 10     => write_data <= command_1_32;
                                           when 11     => write_data <= command_1_33;
                                           when 12     => write_data <= command_1_34;
                                           when 13     => write_data <= command_1_41;
                                           when 14     => write_data <= command_1_42;
                                           when 15     => write_data <= command_1_43;
                                           when 16     => write_data <= command_1_44;
                                           when 17     => write_data <= command_2_11;
                                           when 18     => write_data <= command_2_12;
                                           when 19     => write_data <= command_2_13;
                                           when 20     => write_data <= command_2_14;
                                           when 21     => write_data <= command_2_21;
                                           when 22     => write_data <= command_2_22;
                                           when 23     => write_data <= command_2_23;
                                           when 24     => write_data <= command_2_24;
                                           when 25     => write_data <= command_2_31;
                                           when 26     => write_data <= command_2_32;
                                           when 27     => write_data <= command_2_33;
                                           when 28     => write_data <= command_2_34;
                                           when 29     => write_data <= command_2_41;
                                           when 30     => write_data <= command_2_42;
                                           when 31     => write_data <= command_2_43;
                                           when 32     => write_data <= command_2_44;
                                           when others => write_data <= (others => '0');
                                       end case;
                        when 2      => if (run_clk_ctr < 33 and run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;
                                       case(run_clk_ctr) is
                                           when 1      => write_data <= command_3_11;
                                           when 2      => write_data <= command_3_12;
                                           when 3      => write_data <= command_3_13;
                                           when 4      => write_data <= command_3_14;
                                           when 5      => write_data <= command_3_21;
                                           when 6      => write_data <= command_3_22;
                                           when 7      => write_data <= command_3_23;
                                           when 8      => write_data <= command_3_24;
                                           when 9      => write_data <= command_3_31;
                                           when 10     => write_data <= command_3_32;
                                           when 11     => write_data <= command_3_33;
                                           when 12     => write_data <= command_3_34;
                                           when 13     => write_data <= command_3_41;
                                           when 14     => write_data <= command_3_42;
                                           when 15     => write_data <= command_3_43;
                                           when 16     => write_data <= command_3_44;
                                           when 17     => write_data <= command_4_11;
                                           when 18     => write_data <= command_4_12;
                                           when 19     => write_data <= command_4_13;
                                           when 20     => write_data <= command_4_14;
                                           when 21     => write_data <= command_4_21;
                                           when 22     => write_data <= command_4_22;
                                           when 23     => write_data <= command_4_23;
                                           when 24     => write_data <= command_4_24;
                                           when 25     => write_data <= command_4_31;
                                           when 26     => write_data <= command_4_32;
                                           when 27     => write_data <= command_4_33;
                                           when 28     => write_data <= command_4_34;
                                           when 29     => write_data <= command_4_41;
                                           when 30     => write_data <= command_4_42;
                                           when 31     => write_data <= command_4_43;
                                           when 32     => write_data <= command_4_44;
                                           when others => write_data <= (others => '0');
                                       end case;
                        when others => if (run_clk_ctr < 17 and run_phase = 4) then write_en <= '1'; else write_en <= '0'; end if;
                                       case(run_clk_ctr) is
                                           when 1      => write_data <= run_buff_11;
                                           when 2      => write_data <= run_buff_12;
                                           when 3      => write_data <= run_buff_13;
                                           when 4      => write_data <= run_buff_14;
                                           when 5      => write_data <= run_buff_21;
                                           when 6      => write_data <= run_buff_22;
                                           when 7      => write_data <= run_buff_23;
                                           when 8      => write_data <= run_buff_24;
                                           when 9      => write_data <= run_buff_31;
                                           when 10     => write_data <= run_buff_32;
                                           when 11     => write_data <= run_buff_33;
                                           when 12     => write_data <= run_buff_34;
                                           when 13     => write_data <= run_buff_41;
                                           when 14     => write_data <= run_buff_42;
                                           when 15     => write_data <= run_buff_43;
                                           when 16     => write_data <= run_buff_44;
                                           when others => write_data <= (others => '0');
                                       end case;
                    end case;
                else
                    write_en <= '0';
                end if;
            end if;
        end if;
    end process;
	
    package_count <= std_logic_vector(to_unsigned(run_package,32));
    word_count    <= std_logic_vector(to_unsigned(run_tot_ctr,32));
        
    INTAN_CS      <= run_cs when     run_running = '1' else init_cs;
    INTAN_CLK     <= run_clk when    run_running = '1' else init_clk;
    INTAN_MOSI_1  <= run_mosi_1 when run_running = '1' else init_mosi_1;
    INTAN_MOSI_2  <= run_mosi_2 when run_running = '1' else init_mosi_2;
    INTAN_MOSI_3  <= run_mosi_3 when run_running = '1' else init_mosi_3;
    INTAN_MOSI_4  <= run_mosi_4 when run_running = '1' else init_mosi_4;

end Behavioral;
