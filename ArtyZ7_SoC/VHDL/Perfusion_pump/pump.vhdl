-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05/04/2022 02:25:42 PM
-- Design Name: 
-- Module Name: pump - Behavioral
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

entity pump is
    Generic (
        clk_freq       : integer := 100000000; -- Hz
        pump_period    : integer :=       200; -- us (must be at least 10 us)
        pump_warmup    : integer :=       100; -- ms
        pump_cooldown  : integer :=       100; -- ms
        pump_max_steps : integer :=     74980  -- also need to be changed in perfusion_pump_valve_s00_axi
    );
    Port (
        CLK100MHZ        : in  std_logic; -- clk
    
        enable           : in  std_logic; -- 1
        position         : in  integer range 0 to 2147483647; -- 99999
        
        pump_empty       : in  std_logic; -- 0
        pump_full        : in  std_logic; -- 0
        
        can_pump         : in  std_logic; -- 1
        
        pump_dir         : out std_logic;
        pump_enable      : out std_logic;
        pump_step        : out std_logic;
        
        pump_en_movement : in  std_logic;
        
        ready            : out std_logic
    );
end pump;

architecture Behavioral of pump is
    signal is_position     : integer range 0 to 2147483647 := pump_max_steps;
    signal ought_position  : integer range 0 to 2147483647 := pump_max_steps;
    
    -- added by BM
    signal pump_full_counter  : integer range 0 to 2147483647 := 0;
    signal pump_empty_counter : integer range 0 to 2147483647 := 0;
    -- end of implementation
    
    signal pump_enable_buf : std_logic := '1';
    signal pump_dir_buf    : std_logic := '0';
    signal pump_step_buf   : std_logic := '0';
    
    signal on_counter      : integer   :=  0;
    
    signal steps_ok        : std_logic := '0';
    
    signal step_counter    : integer   :=  0;
    
    signal can_restart     : std_logic := '0';
    
begin
    ought_position <= pump_max_steps when pump_max_steps < position else position;
    pump_enable    <= pump_enable_buf;
    pump_dir       <= pump_dir_buf;
    pump_step      <= pump_step_buf when pump_en_movement = '1' else '0';
    
    ready          <= '1' when (ought_position = is_position) and (position = ought_position) else '0';
    
    -- This process makes sure that the pump gets switched on and off at the correct time points.
    -- Does not do steps and does not react to enable. If steps can be done, steps_ok will be high.
    -- This process also makes sure, that the shift register is ready (can_pump).
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if can_pump = '0' then
                null;
            elsif on_counter = 1 then
                on_counter <= 0;
                if is_position = ought_position then
                    pump_enable_buf <= '1';
                    can_restart     <= '0';
                else
                    steps_ok        <= '1';
                end if;
            elsif on_counter > 1 then
                on_counter     <= on_counter - 1;
                if can_restart = '1' and (is_position /= ought_position) then
                    on_counter <=  0;
                    steps_ok   <= '1';
                end if;
            else
                if pump_enable_buf = '0' then
                    -- In this case the pump can do steps
                    if is_position = ought_position or enable = '0' then
                        on_counter  <= pump_cooldown*(clk_freq/1000);
                        steps_ok    <= '0';
                        can_restart <= '1';
                    end if;
                else
                    -- In this case the pump are switched off
                    if is_position /= ought_position and enable = '1' then
                        on_counter      <= pump_warmup*(clk_freq/1000);
                        pump_enable_buf <= '0';
                        can_restart     <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    -- This process does steps, provided steps_ok is high and pump is enabled and the shift register is ready
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if can_pump = '1' and steps_ok = '1' and enable = '1' then
                if step_counter < pump_period*(clk_freq/1000000) - 1 then
                    step_counter <= step_counter + 1;
                    if step_counter = 5*(clk_freq/1000000) then -- 5 us
                        if pump_step_buf = '1' then
                            pump_step_buf <= '0';
                            if pump_dir_buf = '1' then
                                is_position <= is_position + 1;
                            else
                                is_position <= is_position - 1;
                            end if;
                        end if;
                    end if;
                else
                    step_counter <= 0;
                    if is_position > ought_position then
                        if pump_dir_buf = '1' then
                            pump_dir_buf <= '0';
                        else
                            if is_position > 0 then
                                pump_step_buf <= '1';
                            end if;
                        end if;
                    else
                        if pump_dir_buf = '0' then
                            pump_dir_buf <= '1';
                        else
                            if is_position < pump_max_steps then
                                pump_step_buf <= '1';
                            end if;
                        end if;
                    end if;
                end if;
            else
                step_counter  <=  0;
                if steps_ok = '0' or enable = '0' then
                    pump_step_buf <= '0';
                end if;
            end if;
            
            -- In case the home position is being hit
            -- This is dangerous, since if button is pressed but (ought_)position is > 0, the pump will retract
            -- instead of approaching (which is likely the reason that caused pump_home to be high)
            -- BM modify here for filtering
            if pump_empty = '0' then
                if pump_empty_counter < 100000 then
                    pump_empty_counter <= pump_empty_counter + 1;
                else
                    is_position   <= 0;
                    if pump_dir_buf = '0' then
                        pump_step_buf <= '0';
                    end if;
                end if;
                pump_full_counter <= 0; 
            elsif pump_full = '0' then
                if pump_full_counter < 100000 then
                    pump_full_counter <= pump_full_counter + 1;    
                else            
                    is_position   <= pump_max_steps;
                    if pump_dir_buf = '1' then
                        pump_step_buf <= '0';
                    end if;
                end if;
                pump_empty_counter <= 0;
            else
                pump_empty_counter <= 0;
                pump_full_counter <= 0;            
            end if;
        end if;
    end process;
    
end Behavioral;
