-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 11/15/2022 09:23:22 PM
-- Design Name: 
-- Module Name: shift_register - Behavioral
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

entity shift_register is
    Generic (
        clk_freq        : integer := 100000000; -- Hz
        clk_half_period : integer :=         1  -- us
    );
    Port ( 
        CLK100MHZ       : in  std_logic;
    
        shift_reg_clk   : out std_logic;
        shift_reg_data  : out std_logic;
        shift_reg_latch : out std_logic;
        
        output_rdy      : out std_logic;
        
        valve_state     : in  std_logic_vector(23 downto 0);
        pump_enable     : in  std_logic;
        pump_dir        : in  std_logic;
        valve_enable    : in  std_logic
    );
end shift_register;

architecture Behavioral of shift_register is
    constant cycle_cnt    : integer := clk_freq/1000000*clk_half_period - 1;
    
    signal period_ctr     : integer := 0;
    signal counter        : integer := 0;
    
    signal start_trans    : std_logic := '0';

    signal valve_state_1  : std_logic_vector(23 downto 0) := (others => '0');
    signal pump_enable_1  : std_logic := '0';
    signal pump_dir_1     : std_logic := '0';
    signal valve_enable_1 : std_logic := '0';
    signal valve_state_2  : std_logic_vector(23 downto 0) := (others => '0');
    signal pump_enable_2  : std_logic := '0';
    signal pump_dir_2     : std_logic := '0';
    signal valve_enable_2 : std_logic := '0';
    
    signal shift_vector   : std_logic_vector(31 downto 0);
    
    signal shift_reg_clk_buf   : std_logic := '0';
    signal shift_reg_data_buf  : std_logic := '0';
    signal shift_reg_latch_buf : std_logic := '0';
    
begin
    shift_vector(23 downto 0) <= valve_state_1;
    shift_vector(24)          <= pump_dir_1;
    shift_vector(25)          <= pump_enable_1;
    shift_vector(26)          <= '1';
    shift_vector(27)          <= '1';
    shift_vector(28)          <= '1';
    shift_vector(29)          <= not valve_enable_1; -- This not is necessary, as the valve enable is active low
    shift_vector(30)          <= '0';
    shift_vector(31)          <= '0';
    
    shift_reg_clk   <= shift_reg_clk_buf;
    shift_reg_data  <= shift_reg_data_buf;
    shift_reg_latch <= shift_reg_latch_buf;
    
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if start_trans = '1' then
                period_ctr      <= 67;
                valve_state_1   <= valve_state;
                pump_dir_1      <= pump_dir;
                pump_enable_1   <= pump_enable;
                valve_enable_1  <= valve_enable;
                counter         <= 0;
                shift_reg_latch_buf <= '0';
                shift_reg_clk_buf   <= '0';
            elsif period_ctr > 0 then
                if counter = cycle_cnt then
                    counter <= 0;
                    shift_reg_latch_buf <= '0';
                    shift_reg_clk_buf   <= '0';
                    if period_ctr < 4 then
                        if period_ctr = 2 then
                            shift_reg_latch_buf <= '1'; 
                        elsif period_ctr = 1 then
                            valve_state_2   <= valve_state_1;
                            pump_dir_2      <= pump_dir_1;
                            pump_enable_2   <= pump_enable_1;
                            valve_enable_2  <= valve_enable_1;
                        end if;
                    elsif period_ctr mod 2 = 0 then
                        shift_reg_clk_buf <= '1';
                    else
                        shift_reg_data_buf <= shift_vector((period_ctr-5)/2);
                    end if;
                    period_ctr <= period_ctr - 1;
                else
                    counter <= counter + 1;
                end if;
            end if;
        end if;
    end process;
    
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if start_trans = '0' and
               period_ctr  = 0 then
                if valve_state_2  = valve_state_1  and
                   pump_dir_2     = pump_dir_1     and
                   pump_enable_2  = pump_enable_1  and
                   valve_enable_2 = valve_enable_1 and
                   valve_state    = valve_state_1  and
                   pump_dir       = pump_dir_1     and
                   pump_enable    = pump_enable_1  and
                   valve_enable   = valve_enable_1 then
                    start_trans <= '0';
                    output_rdy  <= '1';
                else
                    start_trans <= '1';
                    output_rdy  <= '0';
                end if;
            else 
                start_trans <= '0';
                output_rdy  <= '0';
            end if;
        end if;
    end process;

end Behavioral;
