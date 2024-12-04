-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 08/23/2023 06:50:55 PM
-- Design Name: 
-- Module Name: uart_send_commands - Behavioral
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

entity uart_send_commands is
    Port ( 
        CLK100MHz     : in  std_logic;
        uart          : out std_logic;
        
        conversion_1  : in std_logic;
        conversion_2  : in std_logic;
        conversion_3  : in std_logic;
        conversion_4  : in std_logic;
        
        send_images_1 : in std_logic_vector(7 downto 0);
        send_images_2 : in std_logic_vector(7 downto 0);
        send_images_3 : in std_logic_vector(7 downto 0);
        send_images_4 : in std_logic_vector(7 downto 0);
        
        low_thr_inkulevel_1 : in std_logic_vector(7 downto 0);
        low_thr_inkulevel_2 : in std_logic_vector(7 downto 0);
        low_thr_inkulevel_3 : in std_logic_vector(7 downto 0);
        low_thr_inkulevel_4 : in std_logic_vector(7 downto 0);
        
        high_thr_inkulevel_1 : in std_logic_vector(7 downto 0);
        high_thr_inkulevel_2 : in std_logic_vector(7 downto 0);
        high_thr_inkulevel_3 : in std_logic_vector(7 downto 0);
        high_thr_inkulevel_4 : in std_logic_vector(7 downto 0);
        
        intensity_thr_inkulevel_1 : in std_logic_vector(7 downto 0);
        intensity_thr_inkulevel_2 : in std_logic_vector(7 downto 0);
        intensity_thr_inkulevel_3 : in std_logic_vector(7 downto 0);
        intensity_thr_inkulevel_4 : in std_logic_vector(7 downto 0);
        
        inkulevel_command_11_1 : in  std_logic_vector(7 downto 0);
        inkulevel_command_11_2 : in  std_logic_vector(7 downto 0);
        inkulevel_command_11_3 : in  std_logic_vector(7 downto 0);
        inkulevel_command_11_4 : in  std_logic_vector(7 downto 0);
        inkulevel_command_12_1 : in  std_logic_vector(7 downto 0);
        inkulevel_command_12_2 : in  std_logic_vector(7 downto 0);
        inkulevel_command_12_3 : in  std_logic_vector(7 downto 0);
        inkulevel_command_12_4 : in  std_logic_vector(7 downto 0);
        inkulevel_command_13_1 : in  std_logic_vector(7 downto 0);
        inkulevel_command_13_2 : in  std_logic_vector(7 downto 0);
        inkulevel_command_13_3 : in  std_logic_vector(7 downto 0);
        inkulevel_command_13_4 : in  std_logic_vector(7 downto 0);
        inkulevel_command_14_1 : in  std_logic_vector(7 downto 0);
        inkulevel_command_14_2 : in  std_logic_vector(7 downto 0);
        inkulevel_command_14_3 : in  std_logic_vector(7 downto 0);
        inkulevel_command_14_4 : in  std_logic_vector(7 downto 0);
        inkulevel_command_15_1 : in  std_logic_vector(7 downto 0);
        inkulevel_command_15_2 : in  std_logic_vector(7 downto 0);
        inkulevel_command_15_3 : in  std_logic_vector(7 downto 0);
        inkulevel_command_15_4 : in  std_logic_vector(7 downto 0);
        
        assign_order  : in std_logic;
        
        debug_sig     : out std_logic_vector(3 downto 0)
    );
end uart_send_commands;

architecture Behavioral of uart_send_commands is
    signal conversion_1_old  : std_logic := '0';
    signal conversion_2_old  : std_logic := '0';
    signal conversion_3_old  : std_logic := '0';
    signal conversion_4_old  : std_logic := '0';
    
    signal send_images_1_old : std_logic_vector(7 downto 0) := "00000000";
    signal send_images_2_old : std_logic_vector(7 downto 0) := "00000000";
    signal send_images_3_old : std_logic_vector(7 downto 0) := "00000000";
    signal send_images_4_old : std_logic_vector(7 downto 0) := "00000000";
    
    signal low_thr_inkulevel_1_old : std_logic_vector(7 downto 0) := "00000000";
    signal low_thr_inkulevel_2_old : std_logic_vector(7 downto 0) := "00000000";
    signal low_thr_inkulevel_3_old : std_logic_vector(7 downto 0) := "00000000";
    signal low_thr_inkulevel_4_old : std_logic_vector(7 downto 0) := "00000000";
    
    signal high_thr_inkulevel_1_old : std_logic_vector(7 downto 0) := "10010110";
    signal high_thr_inkulevel_2_old : std_logic_vector(7 downto 0) := "10010110";
    signal high_thr_inkulevel_3_old : std_logic_vector(7 downto 0) := "10010110";
    signal high_thr_inkulevel_4_old : std_logic_vector(7 downto 0) := "10010110";
    
    signal intensity_thr_inkulevel_1_old : std_logic_vector(7 downto 0) := "00000000";
    signal intensity_thr_inkulevel_2_old : std_logic_vector(7 downto 0) := "00000000";
    signal intensity_thr_inkulevel_3_old : std_logic_vector(7 downto 0) := "00000000";
    signal intensity_thr_inkulevel_4_old : std_logic_vector(7 downto 0) := "00000000";
    
    signal inkulevel_command_11_1_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_11_2_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_11_3_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_11_4_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_12_1_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_12_2_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_12_3_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_12_4_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_13_1_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_13_2_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_13_3_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_13_4_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_14_1_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_14_2_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_14_3_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_14_4_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_15_1_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_15_2_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_15_3_old : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_15_4_old : std_logic_vector(7 downto 0):= "00000000";
    
    signal assign_order_rst  : std_logic := '0';
    signal assign_order_buf  : std_logic := '0';
    
    signal start : std_logic := '0';
    signal ready : std_logic := '0';
    
    signal byte_1 : std_logic_vector(7 downto 0) := "00000000";
    signal byte_2 : std_logic_vector(7 downto 0) := "00000000";
    signal byte_3 : std_logic_vector(7 downto 0) := "00000000";
    
    component uart_send is
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
    end component;
    
begin
    uart_send_inst : uart_send
        port map ( 
            CLK100MHz    => CLK100MHz,
            uart         => uart,    
                      
            byte_1       => byte_1,   
            byte_2       => byte_2,   
            byte_3       => byte_3,   
                      
            ready        => ready,    
            start        => start
        );
        
--    assign_order_buf <= '1' when assign_order = '1' or (assign_order_buf = '1' and assign_order_rst = '0');
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if assign_order = '1' then
                assign_order_buf <= '1';
            elsif assign_order_rst = '1' then
                assign_order_buf <= '0'; 
            end if;
        end if;
    end process;

    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            assign_order_rst <= '0';
            start <= '1'; -- Gets overwritten to 0 at the end, if no update is necessary
            if ready = '1' and start = '0' then
                if assign_order_buf = '1' then
                    byte_1             <= "10011100";
                    byte_2             <= "00000010"; 
                    byte_3             <= "00000000";
                    assign_order_rst <= '1';
                elsif conversion_1  /= conversion_1_old then
                    byte_1             <= "10010100";
                    byte_2             <= "00000000"; 
                    byte_3(7 downto 1) <=  "0000000";
                    byte_3(0)          <= conversion_1; 
                    conversion_1_old   <= conversion_1;
                elsif conversion_2  /= conversion_2_old then
                    byte_1             <= "10010101";
                    byte_2             <= "00000000"; 
                    byte_3(7 downto 1) <=  "0000000";
                    byte_3(0)          <= conversion_2; 
                    conversion_2_old   <= conversion_2;
                elsif conversion_3  /= conversion_3_old then
                    byte_1             <= "10010110";
                    byte_2             <= "00000000"; 
                    byte_3(7 downto 1) <=  "0000000";
                    byte_3(0)          <= conversion_3; 
                    conversion_3_old   <= conversion_3;
                elsif conversion_4  /= conversion_4_old then
                    byte_1             <= "10010111";
                    byte_2             <= "00000000"; 
                    byte_3(7 downto 1) <=  "0000000";
                    byte_3(0)          <= conversion_4; 
                    conversion_4_old   <= conversion_4;
                elsif send_images_1 /= send_images_1_old then
                    byte_1             <= "10010100";
                    byte_2             <= "00000001"; 
                    byte_3             <= send_images_1;
                    send_images_1_old  <= send_images_1;
                elsif send_images_2 /= send_images_2_old then
                    byte_1             <= "10010101";
                    byte_2             <= "00000001"; 
                    byte_3             <= send_images_2;
                    send_images_2_old  <= send_images_2;
                elsif send_images_3 /= send_images_3_old then
                    byte_1             <= "10010110";
                    byte_2             <= "00000001"; 
                    byte_3             <= send_images_3;
                    send_images_3_old  <= send_images_3;
                elsif send_images_4 /= send_images_4_old then
                    byte_1             <= "10010111";
                    byte_2             <= "00000001"; 
                    byte_3             <= send_images_4;
                    send_images_4_old  <= send_images_4;
                elsif low_thr_inkulevel_1  /= low_thr_inkulevel_1_old then
                    byte_1                    <= "10010100";
                    byte_2                    <= "00000011"; 
                    byte_3                    <= low_thr_inkulevel_1;
                    low_thr_inkulevel_1_old   <= low_thr_inkulevel_1;
                elsif low_thr_inkulevel_2  /= low_thr_inkulevel_2_old then
                    byte_1                    <= "10010101";
                    byte_2                    <= "00000011"; 
                    byte_3                    <= low_thr_inkulevel_2;
                    low_thr_inkulevel_2_old   <= low_thr_inkulevel_2;
                elsif low_thr_inkulevel_3  /= low_thr_inkulevel_3_old then
                    byte_1                    <= "10010110";
                    byte_2                    <= "00000011"; 
                    byte_3                    <= low_thr_inkulevel_3;
                    low_thr_inkulevel_3_old   <= low_thr_inkulevel_3;
                elsif low_thr_inkulevel_4  /= low_thr_inkulevel_4_old then
                    byte_1                    <= "10010111";
                    byte_2                    <= "00000011"; 
                    byte_3                    <= low_thr_inkulevel_4;
                    low_thr_inkulevel_4_old   <= low_thr_inkulevel_4;
                elsif high_thr_inkulevel_1  /= high_thr_inkulevel_1_old then
                    byte_1                     <= "10010100";
                    byte_2                     <= "00000100"; 
                    byte_3                     <= high_thr_inkulevel_1;
                    high_thr_inkulevel_1_old   <= high_thr_inkulevel_1;
                elsif high_thr_inkulevel_2  /= high_thr_inkulevel_2_old then
                    byte_1                     <= "10010101";
                    byte_2                     <= "00000100"; 
                    byte_3                     <= high_thr_inkulevel_2;
                    high_thr_inkulevel_2_old   <= high_thr_inkulevel_2;
                elsif high_thr_inkulevel_3  /= high_thr_inkulevel_3_old then
                    byte_1                     <= "10010110";
                    byte_2                     <= "00000100"; 
                    byte_3                     <= high_thr_inkulevel_3;
                    high_thr_inkulevel_3_old   <= high_thr_inkulevel_3;
                elsif high_thr_inkulevel_4  /= high_thr_inkulevel_4_old then
                    byte_1                     <= "10010111";
                    byte_2                     <= "00000100"; 
                    byte_3                     <= high_thr_inkulevel_4;
                    high_thr_inkulevel_4_old   <= high_thr_inkulevel_4;
                elsif intensity_thr_inkulevel_1  /= intensity_thr_inkulevel_1_old then
                    byte_1                          <= "10010100";
                    byte_2                          <= "00000101"; 
                    byte_3                          <= intensity_thr_inkulevel_1;
                    intensity_thr_inkulevel_1_old   <= intensity_thr_inkulevel_1;
                elsif intensity_thr_inkulevel_2  /= intensity_thr_inkulevel_2_old then
                    byte_1                          <= "10010101";
                    byte_2                          <= "00000101"; 
                    byte_3                          <= intensity_thr_inkulevel_2;
                    intensity_thr_inkulevel_2_old   <= intensity_thr_inkulevel_2;
                elsif intensity_thr_inkulevel_3  /= intensity_thr_inkulevel_3_old then
                    byte_1                          <= "10010110";
                    byte_2                          <= "00000101"; 
                    byte_3                          <= intensity_thr_inkulevel_3;
                    intensity_thr_inkulevel_3_old   <= intensity_thr_inkulevel_3;
                elsif intensity_thr_inkulevel_4  /= intensity_thr_inkulevel_4_old then
                    byte_1                          <= "10010111";
                    byte_2                          <= "00000101"; 
                    byte_3                          <= intensity_thr_inkulevel_4;
                    intensity_thr_inkulevel_4_old   <= intensity_thr_inkulevel_4;
                    
                elsif inkulevel_command_11_1 /= inkulevel_command_11_1_old then
                    byte_1                      <= "10010100";
                    byte_2                      <= "00000110"; 
                    byte_3                      <= inkulevel_command_11_1;
                    inkulevel_command_11_1_old  <= inkulevel_command_11_1;
                elsif inkulevel_command_11_2 /= inkulevel_command_11_2_old then
                    byte_1                      <= "10010101";
                    byte_2                      <= "00000110"; 
                    byte_3                      <= inkulevel_command_11_2;
                    inkulevel_command_11_2_old  <= inkulevel_command_11_2;
                elsif inkulevel_command_11_3 /= inkulevel_command_11_3_old then
                    byte_1                      <= "10010110";
                    byte_2                      <= "00000110"; 
                    byte_3                      <= inkulevel_command_11_3;
                    inkulevel_command_11_3_old  <= inkulevel_command_11_3;
                elsif inkulevel_command_11_4 /= inkulevel_command_11_4_old then
                    byte_1                      <= "10010111";
                    byte_2                      <= "00000110"; 
                    byte_3                      <= inkulevel_command_11_4;
                    inkulevel_command_11_4_old  <= inkulevel_command_11_4;
                    
                elsif inkulevel_command_12_1 /= inkulevel_command_12_1_old then
                    byte_1                      <= "10010100";
                    byte_2                      <= "00000111";
                    byte_3                      <= inkulevel_command_12_1;
                    inkulevel_command_12_1_old  <= inkulevel_command_12_1;
                elsif inkulevel_command_12_2 /= inkulevel_command_12_2_old then
                    byte_1                      <= "10010101";
                    byte_2                      <= "00000111";
                    byte_3                      <= inkulevel_command_12_2;
                    inkulevel_command_12_2_old  <= inkulevel_command_12_2;
                elsif inkulevel_command_12_3 /= inkulevel_command_12_3_old then
                    byte_1                      <= "10010110";
                    byte_2                      <= "00000111";
                    byte_3                      <= inkulevel_command_12_3;
                    inkulevel_command_12_3_old  <= inkulevel_command_12_3;
                elsif inkulevel_command_12_4 /= inkulevel_command_12_4_old then
                    byte_1                      <= "10010111";
                    byte_2                      <= "00000111";
                    byte_3                      <= inkulevel_command_12_4;
                    inkulevel_command_12_4_old  <= inkulevel_command_12_4;
                
                elsif inkulevel_command_13_1 /= inkulevel_command_13_1_old then
                    byte_1 <= "10010100";
                    byte_2 <= "00001000";
                    byte_3 <= inkulevel_command_13_1;
                    inkulevel_command_13_1_old <= inkulevel_command_13_1;
                elsif inkulevel_command_13_2 /= inkulevel_command_13_2_old then
                    byte_1 <= "10010101";
                    byte_2 <= "00001000";
                    byte_3 <= inkulevel_command_13_2;
                    inkulevel_command_13_2_old <= inkulevel_command_13_2;
                elsif inkulevel_command_13_3 /= inkulevel_command_13_3_old then
                    byte_1 <= "10010110";
                    byte_2 <= "00001000";
                    byte_3 <= inkulevel_command_13_3;
                    inkulevel_command_13_3_old <= inkulevel_command_13_3;
                elsif inkulevel_command_13_4 /= inkulevel_command_13_4_old then
                    byte_1 <= "10010111";
                    byte_2 <= "00001000";
                    byte_3 <= inkulevel_command_13_4;
                    inkulevel_command_13_4_old <= inkulevel_command_13_4;
                
                elsif inkulevel_command_14_1 /= inkulevel_command_14_1_old then
                    byte_1 <= "10010100";
                    byte_2 <= "00001001";
                    byte_3 <= inkulevel_command_14_1;
                    inkulevel_command_14_1_old <= inkulevel_command_14_1;
                elsif inkulevel_command_14_2 /= inkulevel_command_14_2_old then
                    byte_1 <= "10010101";
                    byte_2 <= "00001001";
                    byte_3 <= inkulevel_command_14_2;
                    inkulevel_command_14_2_old <= inkulevel_command_14_2;
                elsif inkulevel_command_14_3 /= inkulevel_command_14_3_old then
                    byte_1 <= "10010110";
                    byte_2 <= "00001001";
                    byte_3 <= inkulevel_command_14_3;
                    inkulevel_command_14_3_old <= inkulevel_command_14_3;
                elsif inkulevel_command_14_4 /= inkulevel_command_14_4_old then
                    byte_1 <= "10010111";
                    byte_2 <= "00001001";
                    byte_3 <= inkulevel_command_14_4;
                    inkulevel_command_14_4_old <= inkulevel_command_14_4;
                
                elsif inkulevel_command_15_1 /= inkulevel_command_15_1_old then
                    byte_1 <= "10010100";
                    byte_2 <= "00001010";
                    byte_3 <= inkulevel_command_15_1;
                    inkulevel_command_15_1_old <= inkulevel_command_15_1;
                elsif inkulevel_command_15_2 /= inkulevel_command_15_2_old then
                    byte_1 <= "10010101";
                    byte_2 <= "00001010";
                    byte_3 <= inkulevel_command_15_2;
                    inkulevel_command_15_2_old <= inkulevel_command_15_2;
                elsif inkulevel_command_15_3 /= inkulevel_command_15_3_old then
                    byte_1 <= "10010110";
                    byte_2 <= "00001010";
                    byte_3 <= inkulevel_command_15_3;
                    inkulevel_command_15_3_old <= inkulevel_command_15_3;
                elsif inkulevel_command_15_4 /= inkulevel_command_15_4_old then
                    byte_1 <= "10010111";
                    byte_2 <= "00001010";
                    byte_3 <= inkulevel_command_15_4;
                    inkulevel_command_15_4_old <= inkulevel_command_15_4;
                                
                else
                    start <= '0';
                end if;
            else
                start <= '0';
            end if;
        end if;
    end process;
    
    debug_sig(0) <= assign_order;
    debug_sig(1) <= assign_order_buf;
    debug_sig(2) <= assign_order_rst;
    debug_sig(3) <= ready;

end Behavioral;

