-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 06/18/2022 08:37:12 PM
-- Design Name: 
-- Module Name: uart_to_parallel - Behavioral
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

entity uart_to_parallel is
    Generic (
        BAUD      : integer := 9600;
        CLK_FREQ  : integer := 100000000
    );
    Port ( 
        CLK100MHz : in  std_logic;
        uart      : in  std_logic;
		
		level_1   : out std_logic_vector(15 downto 0);
		level_2   : out std_logic_vector(15 downto 0);
		level_3   : out std_logic_vector(15 downto 0);
		level_4   : out std_logic_vector(15 downto 0);
	
		valid_1   : out std_logic;
		valid_2   : out std_logic;
		valid_3   : out std_logic;
		valid_4   : out std_logic;
		
		ctr_1     : out std_logic_vector(15 downto 0);
		ctr_2     : out std_logic_vector(15 downto 0);
		ctr_3     : out std_logic_vector(15 downto 0);
		ctr_4     : out std_logic_vector(15 downto 0)
    );
end uart_to_parallel;

architecture Behavioral of uart_to_parallel is
    constant max_counter : integer := CLK_FREQ/(2*BAUD);

    signal status        : integer range 0 to 127 := 0;
    signal counter       : integer range 0 to max_counter := 0; -- We do not do (max_counter-1) effectively rounding up not down (wlog)
    
    signal byte_1        : std_logic_vector(7 downto 0) := "00000000";
    signal byte_2        : std_logic_vector(7 downto 0) := "00000000";
    signal byte_3        : std_logic_vector(7 downto 0) := "00000000";
    
    signal counter_1     : integer range 0 to 65535 := 0;
    signal counter_2     : integer range 0 to 65535 := 0;
    signal counter_3     : integer range 0 to 65535 := 0;
    signal counter_4     : integer range 0 to 65535 := 0;
    
    signal level_1_buf   : std_logic_vector(15 downto 0) := (others => '0');
    signal level_2_buf   : std_logic_vector(15 downto 0) := (others => '0');
    signal level_3_buf   : std_logic_vector(15 downto 0) := (others => '0');
    signal level_4_buf   : std_logic_vector(15 downto 0) := (others => '0');
    
    signal valid_1_buf   : std_logic := '0';
    signal valid_2_buf   : std_logic := '0';
    signal valid_3_buf   : std_logic := '0';
    signal valid_4_buf   : std_logic := '0';
begin

    ctr_1 <= std_logic_vector(to_unsigned(counter_1,16));
    ctr_2 <= std_logic_vector(to_unsigned(counter_2,16));
    ctr_3 <= std_logic_vector(to_unsigned(counter_3,16));
    ctr_4 <= std_logic_vector(to_unsigned(counter_4,16));
    
    level_1 <= level_1_buf;
    level_2 <= level_2_buf;
    level_3 <= level_3_buf;
    level_4 <= level_4_buf;
    
    valid_1 <= valid_1_buf;
    valid_2 <= valid_2_buf;
    valid_3 <= valid_3_buf;
    valid_4 <= valid_4_buf;

    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if counter = max_counter then
                counter <= 0;
            else
                counter <= counter + 1;
            end if;
            case status is
                when      0 => if uart = '0' then counter <= 0; status <= status + 1; end if; 
                when      1 => if counter = max_counter then status <= status + 1; end if;                  -- (Start first)
                when      2 => if counter = max_counter then status <= status + 1; end if;                  -- (Start second)
                when      3 => if counter = max_counter then status <= status + 1; byte_1(0) <= uart; end if; -- (1     first)
                when      4 => if counter = max_counter then status <= status + 1; end if;                  -- (1     second)
                when      5 => if counter = max_counter then status <= status + 1; byte_1(1) <= uart; end if; -- (2     first)
                when      6 => if counter = max_counter then status <= status + 1; end if;                  -- (2     second)
                when      7 => if counter = max_counter then status <= status + 1; byte_1(2) <= uart; end if; -- (3     first)
                when      8 => if counter = max_counter then status <= status + 1; end if;                  -- (3     second)
                when      9 => if counter = max_counter then status <= status + 1; byte_1(3) <= uart; end if; -- (4     first)
                when     10 => if counter = max_counter then status <= status + 1; end if;                  -- (4     second)
                when     11 => if counter = max_counter then status <= status + 1; byte_1(4) <= uart; end if; -- (5     first)
                when     12 => if counter = max_counter then status <= status + 1; end if;                  -- (5     second)
                when     13 => if counter = max_counter then status <= status + 1; byte_1(5) <= uart; end if; -- (6     first)
                when     14 => if counter = max_counter then status <= status + 1; end if;                  -- (6     second)
                when     15 => if counter = max_counter then status <= status + 1; byte_1(6) <= uart; end if; -- (7     first)
                when     16 => if counter = max_counter then status <= status + 1; end if;                  -- (7     second)
                when     17 => if counter = max_counter then status <= status + 1; byte_1(7) <= uart; end if; -- (8     first)
                when     18 => if counter = max_counter then status <= status + 1; end if;                  -- (8     second)
                when     19 => if counter = max_counter then status <= status + 1; end if;                  -- (Stop  first)
                when     20 => if counter = max_counter then status <= status + 1; end if;                  -- (Stop  second)
                when     21 => if byte_1(7 downto 4) = "1001" then 
                                   status <= status + 1;
                               else
                                   status <= 0;
                               end if;
                
                when     22 => if uart = '0' then counter <= 0; status <= status + 1; end if; 
                when     23 => if counter = max_counter then status <= status + 1; end if;                  -- (Start first)
                when     24 => if counter = max_counter then status <= status + 1; end if;                  -- (Start second)
                when     25 => if counter = max_counter then status <= status + 1; byte_2(0) <= uart; end if; -- (1     first)
                when     26 => if counter = max_counter then status <= status + 1; end if;                  -- (1     second)
                when     27 => if counter = max_counter then status <= status + 1; byte_2(1) <= uart; end if; -- (2     first)
                when     28 => if counter = max_counter then status <= status + 1; end if;                  -- (2     second)
                when     29 => if counter = max_counter then status <= status + 1; byte_2(2) <= uart; end if; -- (3     first)
                when     30 => if counter = max_counter then status <= status + 1; end if;                  -- (3     second)
                when     31 => if counter = max_counter then status <= status + 1; byte_2(3) <= uart; end if; -- (4     first)
                when     32 => if counter = max_counter then status <= status + 1; end if;                  -- (4     second)
                when     33 => if counter = max_counter then status <= status + 1; byte_2(4) <= uart; end if; -- (5     first)
                when     34 => if counter = max_counter then status <= status + 1; end if;                  -- (5     second)
                when     35 => if counter = max_counter then status <= status + 1; byte_2(5) <= uart; end if; -- (6     first)
                when     36 => if counter = max_counter then status <= status + 1; end if;                  -- (6     second)
                when     37 => if counter = max_counter then status <= status + 1; byte_2(6) <= uart; end if; -- (7     first)
                when     38 => if counter = max_counter then status <= status + 1; end if;                  -- (7     second)
                when     39 => if counter = max_counter then status <= status + 1; byte_2(7) <= uart; end if; -- (8     first)
                when     40 => if counter = max_counter then status <= status + 1; end if;                  -- (8     second)
                when     41 => if counter = max_counter then status <= status + 1; end if;                  -- (Stop  first)
                when     42 => if counter = max_counter then status <= status + 1; end if;                  -- (Stop  second)
                when     43 => status <= status + 1; -- Here, do calculations for next step
                
                when     44 => if uart = '0' then counter <= 0; status <= status + 1; end if; 
                when     45 => if counter = max_counter then status <= status + 1; end if;                  -- (Start first)
                when     46 => if counter = max_counter then status <= status + 1; end if;                  -- (Start second)
                when     47 => if counter = max_counter then status <= status + 1; byte_3(0) <= uart; end if; -- (1     first)
                when     48 => if counter = max_counter then status <= status + 1; end if;                  -- (1     second)
                when     49 => if counter = max_counter then status <= status + 1; byte_3(1) <= uart; end if; -- (2     first)
                when     50 => if counter = max_counter then status <= status + 1; end if;                  -- (2     second)
                when     51 => if counter = max_counter then status <= status + 1; byte_3(2) <= uart; end if; -- (3     first)
                when     52 => if counter = max_counter then status <= status + 1; end if;                  -- (3     second)
                when     53 => if counter = max_counter then status <= status + 1; byte_3(3) <= uart; end if; -- (4     first)
                when     54 => if counter = max_counter then status <= status + 1; end if;                  -- (4     second)
                when     55 => if counter = max_counter then status <= status + 1; byte_3(4) <= uart; end if; -- (5     first)
                when     56 => if counter = max_counter then status <= status + 1; end if;                  -- (5     second)
                when     57 => if counter = max_counter then status <= status + 1; byte_3(5) <= uart; end if; -- (6     first)
                when     58 => if counter = max_counter then status <= status + 1; end if;                  -- (6     second)
                when     59 => if counter = max_counter then status <= status + 1; byte_3(6) <= uart; end if; -- (7     first)
                when     60 => if counter = max_counter then status <= status + 1; end if;                  -- (7     second)
                when     61 => if counter = max_counter then status <= status + 1; byte_3(7) <= uart; end if; -- (8     first)
                when     62 => if counter = max_counter then status <= status + 1; end if;                  -- (8     second)
                when     63 => if counter = max_counter then status <= status + 1; end if;                  -- (Stop  first)
                when     64 => if counter = max_counter then status <= status + 1; end if;                  -- (Stop  second)
                -- We are looking at 3 bit here. This is because the highest of the 3 is the command bit. 
                -- It must be 0 in order for it to be data send from inkulevel
                when     65 => if byte_1(2 downto 0) = "000" then 
                                   valid_1_buf <= byte_1(3);
                                   counter_1   <= counter_1 + 1;
                                   level_1_buf(15 downto 8) <= byte_2;
                                   level_1_buf( 7 downto 0) <= byte_3;
                               elsif byte_1(2 downto 0) = "001" then
                                   valid_2_buf <= byte_1(3);
                                   counter_2   <= counter_2 + 1;
                                   level_2_buf(15 downto 8) <= byte_2;
                                   level_2_buf( 7 downto 0) <= byte_3;
                               elsif byte_1(2 downto 0) = "010" then
                                   valid_3_buf <= byte_1(3);
                                   counter_3   <= counter_3 + 1;
                                   level_3_buf(15 downto 8) <= byte_2;
                                   level_3_buf( 7 downto 0) <= byte_3;
                               elsif byte_1(2 downto 0) = "011" then
                                   valid_4_buf <= byte_1(3);
                                   counter_4   <= counter_4 + 1;
                                   level_4_buf(15 downto 8) <= byte_2;
                                   level_4_buf( 7 downto 0) <= byte_3;
                               end if;
                               status <= 0; -- Here, do calculations for next step
                when others => status <= 0;
            end case;
        end if;
    end process;
end Behavioral;
