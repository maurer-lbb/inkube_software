-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 05/25/2023 07:39:01 PM
-- Design Name: 
-- Module Name: simple_spi - Behavioral
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

entity simple_spi is
    Port (
        CLK100MHZ      : in std_logic;
     
        upper_byte     : in  std_logic_vector(7 downto 0);
        lower_byte     : in  std_logic_vector(7 downto 0);
        start          : in  std_logic;
        
        ready          : out std_logic;
        
        spi_clk_bot    : out std_logic;
        spi_miso_bot   : in  std_logic;
        spi_mosi_bot   : out std_logic;
        spi_cs_bot     : in std_logic_vector(3 downto 0);
        
        output_byte    : out std_logic_vector(7 downto 0);
        
        spi_cs_bot_out : out std_logic_vector(3 downto 0)
    );
end simple_spi;

architecture Behavioral of simple_spi is
    signal ready_buf       : std_logic := '0';
    signal running         : std_logic := '0';
    
    signal upper_byte_buf  : std_logic_vector(7 downto 0);
    signal lower_byte_buf  : std_logic_vector(7 downto 0);
    signal output_byte_buf : std_logic_vector(7 downto 0);
    
    signal counter         : integer := 0;
    signal sub_ctr         : integer range 0 to 19 := 0; 
    signal offset          : integer := 0;
    
    signal spi_cs_bot_buf  : std_logic_vector(3 downto 0) := "1111";
begin
    ready     <= ready_buf;
    
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if ready_buf = '0' then
                if start = '0' and running = '0' then
                    ready_buf <= '1';
                end if;
            else
                if start = '1' and running = '0' then
                    ready_buf <= '0';
                end if;
            end if;
        end if;
    end process;

    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if ready_buf = '1' and start = '1' and running = '0' then
                upper_byte_buf <= upper_byte;
                lower_byte_buf <= lower_byte;
                spi_cs_bot_buf <= spi_cs_bot;
                running        <= '1';
                counter        <= 0;
                sub_ctr        <= 0;
            elsif offset >= 1000 then
                running     <= '0';
                output_byte <= output_byte_buf;
            elsif running = '1' then
                if sub_ctr = 19 then
                    sub_ctr <= 0;
                    counter <= counter + 1;
                else
                    sub_ctr <= sub_ctr + 1;
                end if;
            end if;
        end if;
    end process;
    
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            -- Define normal cases
            spi_clk_bot    <= '0';
            spi_mosi_bot   <= '0';
            spi_cs_bot_out <= "1111";
            
            -- Gating
            if counter + offset > 500 and counter + offset < 1000 then
                spi_cs_bot_out <= not spi_cs_bot_buf;                
            end if;
            
            if running = '0' or counter = 0 then -- Initialize all connections
                offset   <=  0;
            
            -- Setting the CS.
            elsif counter + offset = 1 then
                if sub_ctr = 19 then
                    if spi_cs_bot_buf(0)='1' or spi_cs_bot_buf(1)='1' or spi_cs_bot_buf(2)='1' or spi_cs_bot_buf(3)='1' then
                        offset <= 500; -- SPI mode 1 (idle low, second edge sampling)
                    else
                        offset <= 1000;
                    end if;
                end if;
                
            -- Send the upper byte (SPI mode 1)
            elsif counter + offset <= 510 then
                case counter + offset is
                    when 503 => spi_mosi_bot <= upper_byte_buf(7);
                    when 504 => spi_mosi_bot <= upper_byte_buf(6);
                    when 505 => spi_mosi_bot <= upper_byte_buf(5);
                    when 506 => spi_mosi_bot <= upper_byte_buf(4);
                    when 507 => spi_mosi_bot <= upper_byte_buf(3);
                    when 508 => spi_mosi_bot <= upper_byte_buf(2);
                    when 509 => spi_mosi_bot <= upper_byte_buf(1);
                    when 510 => spi_mosi_bot <= upper_byte_buf(0);
                    when others => null;
                end case;
                if sub_ctr < 10 and counter + offset > 502 then
                    spi_clk_bot <= '1';
                end if;
                
            -- Send lower byte (SPI mode 1) and clear the cs in the shift register
            elsif counter + offset <= 518 then
                case counter + offset is
                    when 511 => spi_mosi_bot <= lower_byte_buf(7);
                    when 512 => spi_mosi_bot <= lower_byte_buf(6);
                    when 513 => spi_mosi_bot <= lower_byte_buf(5);
                    when 514 => spi_mosi_bot <= lower_byte_buf(4);
                    when 515 => spi_mosi_bot <= lower_byte_buf(3);
                    when 516 => spi_mosi_bot <= lower_byte_buf(2);
                    when 517 => spi_mosi_bot <= lower_byte_buf(1);
                    when 518 => spi_mosi_bot <= lower_byte_buf(0);
                    when others => null;
                end case;
                if sub_ctr < 10 then
                    spi_clk_bot <= '1';
                end if;
                if sub_ctr = 10 then
                    case counter + offset is
                        when 511 => output_byte_buf(7) <= spi_miso_bot;
                        when 512 => output_byte_buf(6) <= spi_miso_bot;
                        when 513 => output_byte_buf(5) <= spi_miso_bot;
                        when 514 => output_byte_buf(4) <= spi_miso_bot;
                        when 515 => output_byte_buf(3) <= spi_miso_bot;
                        when 516 => output_byte_buf(2) <= spi_miso_bot;
                        when 517 => output_byte_buf(1) <= spi_miso_bot;
                        when 518 => output_byte_buf(0) <= spi_miso_bot;
                        when others => null;
                    end case;
                end if;                
            -- Set CS for SPI mode 1
            elsif counter + offset = 519 then
                if sub_ctr = 19 then
                    offset <= 1000;
                end if;
            end if;
        end if;
    end process;

end Behavioral;

