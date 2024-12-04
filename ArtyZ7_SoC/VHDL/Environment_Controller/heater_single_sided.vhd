-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 04/27/2022 01:05:51 AM
-- Design Name: 
-- Module Name: heater - Behavioral
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

entity heater is
    Generic (
          DIMENSION    : integer := 16;
          SCALE        : integer := 1
    );
    Port (CLK100MHZ    : in  std_logic;
    
          ought_value  : in  std_logic_vector(DIMENSION-1 downto 0);
          is_value     : in  std_logic_vector(DIMENSION-1 downto 0);
          
          p_factor     : in  std_logic_vector(7 downto 0);
          i_factor     : in  std_logic_vector(7 downto 0);
          
          heater_on    : in  std_logic;
          heater       : out std_logic_vector(11 downto 0)
    );
end heater;

architecture Behavioral of heater is
    signal clk_dividor    : integer range 0 to 99999999  := 0; -- every 100 ms
    
    signal heater_factor  : integer range -2048 to 2047  := 0; -- 0 means off, 4095 means completely on. The rest is safety.
    
    signal c_p            : integer range -2147483648 to 2147483647 := 0; -- should never be outside of -100 -> 100 (right now number has 21 bit)
    signal c_i            : integer range -2147483648 to 2147483647 := 0; -- should never be outside of -100 -> 100 (right now number has 21 bit)
    
    signal c_p_bounded    : integer range -4096 to 4095 := 0;
    signal c_i_bounded    : integer range -4096 to 4095 := 0;
    
    signal c_total        : integer range -8192 to 9191 := 0;
    
    signal integral       : integer range 0 to 2147483647 := 1073741824; -- right now number has 31 bit
    
    signal diff           : unsigned(21 downto 0);
    signal diff_pipe      : integer range -2147483648 to 2147483647 := 0;
    
    constant offset       : integer range 0 to 4194303 := 2097152;
    
    signal pdm_sig        : std_logic;
    
begin

    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            diff      <= to_unsigned(offset + diff_pipe,22); -- 1unit is 0.00267K, 1K is 375unit
            
            diff_pipe <= (to_integer(unsigned(ought_value)) - to_integer(unsigned(is_value)))*SCALE;
        end if;
    end process;

    heater <= "111111111111" when heater_on='0' else 
              std_logic_vector(to_unsigned(heater_factor+2048,12));
    
    c_p_bounded <= 4095 when c_p > 4095  else
                  -4096 when c_p < -4096 else
                  c_p;
    c_i_bounded <= 4095 when c_i > 4095  else
                  -4096 when c_i < -4096 else
                  c_i;
    c_total     <= c_i_bounded + c_p_bounded;
    
    heater_factor <= -2048 when c_total < -2048            else
                     2046  when c_total > 2046             else --2047 is defined as switched off
                     c_total;
    
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if heater_on = '0' then
                integral <= 1073741824;
                clk_dividor <= 0;
                c_i <= 0;
                c_p <= 0;
            else
                if clk_dividor = 0 then
                    -- This happens every 500 ms
                    if integral + (to_integer(diff) - offset) > 1073741824 + 1048576 then -- Signal has range 1048576 (after 8 bit shifts this is 4096)
                        integral <= 1073741824 + 1048576;
                    elsif integral + (to_integer(diff) - offset) < 1073741824 - 1048576 then -- Signal has range 1048576 (after 8 bit shifts this is 4096)
                        integral <= 1073741824 - 1048576;
                    else
                        integral <= integral + (to_integer(diff) - offset);
                    end if;
                    c_i <= (to_integer((to_unsigned(integral,31)(30 downto 8)))-4194304)*to_integer(unsigned(i_factor));
                    c_p <= (to_integer(diff)-offset)*to_integer(unsigned(p_factor));
                end if;
                
                if clk_dividor < 49999999 then
                    clk_dividor <= clk_dividor + 1;
                else
                    clk_dividor <= 0;
                end if;
            end if;
        end if;
    end process;

end Behavioral;
