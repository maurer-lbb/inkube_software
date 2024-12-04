-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 06/17/2022 12:14:18 PM
-- Design Name: 
-- Module Name: co2_controller - Behavioral
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

entity co2_controller is
    Port (CLK100MHZ    : in  std_logic;
    
          ought_value  : in  std_logic_vector(15 downto 0);
          is_value     : in  std_logic_vector(15 downto 0);
          
          p_factor     : in  std_logic_vector(7 downto 0);
          i_factor     : in  std_logic_vector(7 downto 0);
          
          valve_on     : in  std_logic;
          valve        : out std_logic);
end co2_controller;

architecture Behavioral of co2_controller is

    signal clk_dividor    : integer range 0 to 9999999  := 0; -- every 100 ms
    
    signal pwm_counter    : integer range 0 to 99       := 0; 
    signal pwm_dividor    : integer range 0 to 999999   := 0; -- every 10 ms
    
    signal valve_factor   : integer range -100 to 200   := 0; -- 0 means off, 100 means constantly on. The rest is safety.
    
    signal c_p            : integer range -2147483648 to 2147483647 := 0; -- should never be outside of -100 -> 100 (right now number has 21 bit)
    signal c_i            : integer range -2147483648 to 2147483647 := 0; -- should never be outside of -100 -> 100 (right now number has 21 bit)
    
    signal c_p_bounded    : integer range -100 to 100 := 0;
    signal c_i_bounded    : integer range -100 to 100 := 0;
    
    signal c_total        : integer range -200 to 200 := 0;
    
    signal integral       : integer range 0 to 2147483647 := 1073741824; -- right now number has 31 bit
    
    signal diff           : unsigned(21 downto 0);
    
    constant offset       : integer range 0 to 4194303 := 2097152;
    
    signal pwm_sig        : std_logic;

begin

    diff <= to_unsigned(offset + to_integer(unsigned(ought_value)) - to_integer(unsigned(is_value)),22); -- 1unit is 0.000277 v%, 1 v% is 3604.4 units

    valve   <= '1' when valve_on='1' and pwm_sig = '1' else '0';
    pwm_sig <= '1' when valve_factor > pwm_counter else '0';
    
    c_p_bounded <= 100 when c_p > 100 else
                  -100 when c_p < -100 else
                  c_p;
    c_i_bounded <= 100 when c_i > 100 else
                  -100 when c_i < -100 else
                  c_i;
    c_total     <= c_i_bounded + c_p_bounded;
    
    valve_factor <= 0 when c_total < 0 else
                     100 when c_total > 100 else
                     c_total;
    
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if pwm_dividor < 999999 then
                pwm_dividor <= pwm_dividor + 1;
            else
                pwm_dividor <= 0;
                
                if pwm_counter < 99 then
                    pwm_counter <= pwm_counter + 1;
                else
                    pwm_counter <= 0;
                end if;
            end if;
        end if;
    end process;
    
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if valve_on = '0' then
                integral <= 1073741824;
                clk_dividor <= 0;
                c_i <= 0;
                c_p <= 0;
            else
                if clk_dividor = 0 then
                    -- This happens every 100 ms
                    if integral + (to_integer(diff) - offset) > 1073741824 + 819200 then -- Signal has range 819200 (after 13 bit shifts this is 100)
                        integral <= 1073741824 + 819200;
                    elsif integral + (to_integer(diff) - offset) < 1073741824 - 819200 then -- Signal has range 819200 (after 13 bit shifts this is 100)
                        integral <= 1073741824 - 819200;
                    else
                        integral <= integral + (to_integer(diff) - offset);
                    end if;
                    c_i <= (to_integer((to_unsigned(integral,31)(30 downto 13)))-131072)*to_integer(unsigned(i_factor));
                    c_p <= (to_integer((diff(21 downto 6)))-32768)*to_integer(unsigned(p_factor));
                end if;
                
                if clk_dividor < 9999999 then
                    clk_dividor <= clk_dividor + 1;
                else
                    clk_dividor <= 0;
                end if;
            end if;
        end if;
    end process;

end Behavioral;

