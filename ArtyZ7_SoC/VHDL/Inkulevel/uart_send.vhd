-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 08/23/2023 07:22:16 PM
-- Design Name: 
-- Module Name: uart_send - Behavioral
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
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity uart_send is
    Generic (
        BAUD         : integer := 9600;
        CLK_FREQ     : integer := 100000000
    );
    Port ( 
        CLK100MHz    : in  std_logic;
        uart         : out std_logic;
        
        byte_1       : in  std_logic_vector(7 downto 0);
        byte_2       : in  std_logic_vector(7 downto 0);
        byte_3       : in  std_logic_vector(7 downto 0);
        
        ready        : out std_logic;
        start        : in  std_logic
    );
end uart_send;

architecture Behavioral of uart_send is
    constant max_counter : integer := CLK_FREQ/BAUD;

    signal status        : integer range 0 to 63 := 0;
    signal counter       : integer range 0 to max_counter := 0; -- We do not do (max_counter-1) effectively rounding up not down (wlog)
    
    signal byte_1_buf    : std_logic_vector(7 downto 0) := "00000000";
    signal byte_2_buf    : std_logic_vector(7 downto 0) := "00000000";
    signal byte_3_buf    : std_logic_vector(7 downto 0) := "00000000";
begin

    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if counter = max_counter then
                counter <= 0;
            else
                counter <= counter + 1;
            end if;
            case status is
                -- init and wait for one cyle (To enable one stop bit)
                when       0 => counter <= 0; 
                                ready   <= '0'; 
                                uart    <= '1'; 
                                status  <= status + 1;
                when       1 => if counter = max_counter then 
                                    status <= status + 1; 
                                    ready <= '1'; 
                                end if;
                                
                -- waiting for start
                when       2 => if start = '1' then 
                                    byte_1_buf <= byte_1;
                                    byte_2_buf <= byte_2;
                                    byte_3_buf <= byte_3;
                                    ready      <= '0';
                                    status     <= status + 1;
                                end if;
                                
                -- sending start bit for first byte
                when       3 => counter <= 0; 
                                uart    <= '0';
                                status  <= status + 1;
                -- sending first byte
                when       4 => if counter = max_counter then uart <= byte_1_buf(0); status <= status + 1; end if; 
                when       5 => if counter = max_counter then uart <= byte_1_buf(1); status <= status + 1; end if; 
                when       6 => if counter = max_counter then uart <= byte_1_buf(2); status <= status + 1; end if; 
                when       7 => if counter = max_counter then uart <= byte_1_buf(3); status <= status + 1; end if; 
                when       8 => if counter = max_counter then uart <= byte_1_buf(4); status <= status + 1; end if; 
                when       9 => if counter = max_counter then uart <= byte_1_buf(5); status <= status + 1; end if; 
                when      10 => if counter = max_counter then uart <= byte_1_buf(6); status <= status + 1; end if; 
                when      11 => if counter = max_counter then uart <= byte_1_buf(7); status <= status + 1; end if; 
                -- sending stop bit for first byte
                when      12 => if counter = max_counter then uart <= '1';           status <= status + 1; end if;
                
                -- sending start bit for second byte
                when      13 => if counter = max_counter then uart <= '0';           status <= status + 1; end if;
                -- sending second byte
                when      14 => if counter = max_counter then uart <= byte_2_buf(0); status <= status + 1; end if; 
                when      15 => if counter = max_counter then uart <= byte_2_buf(1); status <= status + 1; end if; 
                when      16 => if counter = max_counter then uart <= byte_2_buf(2); status <= status + 1; end if; 
                when      17 => if counter = max_counter then uart <= byte_2_buf(3); status <= status + 1; end if; 
                when      18 => if counter = max_counter then uart <= byte_2_buf(4); status <= status + 1; end if; 
                when      19 => if counter = max_counter then uart <= byte_2_buf(5); status <= status + 1; end if; 
                when      20 => if counter = max_counter then uart <= byte_2_buf(6); status <= status + 1; end if; 
                when      21 => if counter = max_counter then uart <= byte_2_buf(7); status <= status + 1; end if; 
                -- sending stop bit for second byte
                when      22 => if counter = max_counter then uart <= '1';           status <= status + 1; end if;
                
                -- sending start bit for third byte
                when      23 => if counter = max_counter then uart <= '0';           status <= status + 1; end if;
                -- sending third byte
                when      24 => if counter = max_counter then uart <= byte_3_buf(0); status <= status + 1; end if; 
                when      25 => if counter = max_counter then uart <= byte_3_buf(1); status <= status + 1; end if; 
                when      26 => if counter = max_counter then uart <= byte_3_buf(2); status <= status + 1; end if; 
                when      27 => if counter = max_counter then uart <= byte_3_buf(3); status <= status + 1; end if; 
                when      28 => if counter = max_counter then uart <= byte_3_buf(4); status <= status + 1; end if; 
                when      29 => if counter = max_counter then uart <= byte_3_buf(5); status <= status + 1; end if; 
                when      30 => if counter = max_counter then uart <= byte_3_buf(6); status <= status + 1; end if; 
                when      31 => if counter = max_counter then uart <= byte_3_buf(7); status <= status + 1; end if; 
                -- Wait until data has beend send. Then send stop bit (during next init cycle)
                when      32 => if counter = max_counter then uart <= '1';           status <= 0;          end if;
                
                when  others => status <= 0;
                
                -- 
            end case;
        end if;
    end process;

end Behavioral;
