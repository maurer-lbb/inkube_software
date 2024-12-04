-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 02/01/2023 07:58:41 PM
-- Design Name: 
-- Module Name: complex_spi - Behavioral
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

entity complex_spi is
    Port (
        CLK100MHZ    : in std_logic;
     
        upper_byte   : in  std_logic_vector(7 downto 0);
        lower_byte   : in  std_logic_vector(7 downto 0);
        DIG_AUX      : in  std_logic_vector(2 downto 0);
        cs           : in  std_logic_vector(4 downto 0);
        start        : in  std_logic;
        
        ready        : out std_logic;
        
        spi_clk_pwr  : out std_logic;
        spi_mosi_pwr : out std_logic;
        
        sr_sdi_pwr   : out std_logic;
        sr_sclk_pwr  : out std_logic;
        sr_latch_pwr : out std_logic;
        
        output_byte : out std_logic_vector(7 downto 0)
    );
end complex_spi;

architecture Behavioral of complex_spi is
    signal ready_buf       : std_logic := '0';
    signal running         : std_logic := '0';
    
    signal upper_byte_buf  : std_logic_vector(7 downto 0);
    signal lower_byte_buf  : std_logic_vector(7 downto 0);
    signal output_byte_buf : std_logic_vector(7 downto 0);
    signal cs_buf          : std_logic_vector(4 downto 0);
    signal DIG_AUX_buf     : std_logic_vector(2 downto 0);
    
    signal counter         : integer := 0;
    signal sub_ctr         : integer range 0 to 19 := 0; 
    signal offset          : integer := 0;
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
                cs_buf         <= cs;
                DIG_AUX_buf    <= DIG_AUX;
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
            spi_clk_pwr  <= '0';
            spi_mosi_pwr <= '0';
            sr_latch_pwr <= '0';
            sr_sclk_pwr  <= '0';
            sr_sdi_pwr   <= '0';
            
            if running = '0' or counter = 0 then -- Initialize all connections
                offset   <=  0;
                
            -- Setting the Latch register with potential cs.
            elsif counter + offset <= 8 then
                case counter + offset is
                    when 1 => sr_sdi_pwr <= DIG_AUX_buf(2); -- Pin of shift register is not connected
                    when 2 => sr_sdi_pwr <= DIG_AUX_buf(1);
                    when 3 => sr_sdi_pwr <= DIG_AUX_buf(0);
                    when 4 => sr_sdi_pwr <= not cs_buf(4);
                    when 5 => sr_sdi_pwr <= not cs_buf(3);
                    when 6 => sr_sdi_pwr <= not cs_buf(2);
                    when 7 => sr_sdi_pwr <= not cs_buf(1);
                    when 8 => sr_sdi_pwr <= not cs_buf(0);
                    when others => null;
                end case;
                if sub_ctr >= 10 then
                    sr_sclk_pwr <= '1';
                end if;
            elsif counter + offset = 9 then
                if sub_ctr >= 10 then
                    sr_latch_pwr <= '1';
                end if;
                if sub_ctr = 19 then
                    if cs_buf(4)='1' or cs_buf(3)='1' or cs_buf(2)='1' or cs_buf(1)='1' or cs_buf(0)='1' then
                        offset <= 0;   -- SPI mode 0 (idle low,  first edge sampling)
                    else
                        offset <= 1000;
                    end if;
                end if;
            elsif counter + offset = 10 then
                null;
            elsif counter + offset = 510 then
                null;
                
            -- Send the upper byte (SPI mode 0)
            elsif counter + offset <= 18 then
                case counter + offset is
                    when 11 => spi_mosi_pwr <= upper_byte_buf(7);
                    when 12 => spi_mosi_pwr <= upper_byte_buf(6);
                    when 13 => spi_mosi_pwr <= upper_byte_buf(5);
                    when 14 => spi_mosi_pwr <= upper_byte_buf(4);
                    when 15 => spi_mosi_pwr <= upper_byte_buf(3);
                    when 16 => spi_mosi_pwr <= upper_byte_buf(2);
                    when 17 => spi_mosi_pwr <= upper_byte_buf(1);
                    when 18 => spi_mosi_pwr <= upper_byte_buf(0);
                    when others => null;
                end case;
                if sub_ctr >= 10 then
                    spi_clk_pwr <= '1';
                end if;
                
            -- Send lower byte (SPI mode 0) and clear the cs in the shift register
            elsif counter + offset <= 26 then
                case counter + offset is
                    when 19 => spi_mosi_pwr <= lower_byte_buf(7); sr_sdi_pwr <= DIG_AUX_buf(2);
                    when 20 => spi_mosi_pwr <= lower_byte_buf(6); sr_sdi_pwr <= DIG_AUX_buf(1);
                    when 21 => spi_mosi_pwr <= lower_byte_buf(5); sr_sdi_pwr <= DIG_AUX_buf(0);
                    when 22 => spi_mosi_pwr <= lower_byte_buf(4); sr_sdi_pwr <= '1';
                    when 23 => spi_mosi_pwr <= lower_byte_buf(3); sr_sdi_pwr <= '1';
                    when 24 => spi_mosi_pwr <= lower_byte_buf(2); sr_sdi_pwr <= '1';
                    when 25 => spi_mosi_pwr <= lower_byte_buf(1); sr_sdi_pwr <= '1';
                    when 26 => spi_mosi_pwr <= lower_byte_buf(0); sr_sdi_pwr <= '1';
                    when others => null;
                end case;
                if sub_ctr >= 10 then
                    spi_clk_pwr <= '1';
                    sr_sclk_pwr <= '1';
                end if;
                
            -- Latch the SR for SPI mode 0
            elsif counter + offset = 27 then
                if sub_ctr >= 10 then
                    sr_latch_pwr <= '1';
                end if;
                if sub_ctr = 19 then
                    offset <= 1000;
                end if;
                
            -- Send the upper byte (SPI mode 1)
            elsif counter + offset <= 518 then
                case counter + offset is
                    when 511 => spi_mosi_pwr <= upper_byte_buf(7);
                    when 512 => spi_mosi_pwr <= upper_byte_buf(6);
                    when 513 => spi_mosi_pwr <= upper_byte_buf(5);
                    when 514 => spi_mosi_pwr <= upper_byte_buf(4);
                    when 515 => spi_mosi_pwr <= upper_byte_buf(3);
                    when 516 => spi_mosi_pwr <= upper_byte_buf(2);
                    when 517 => spi_mosi_pwr <= upper_byte_buf(1);
                    when 518 => spi_mosi_pwr <= upper_byte_buf(0);
                    when others => null;
                end case;
                if sub_ctr < 10 then
                    spi_clk_pwr <= '1';
                end if;
                
            -- Send lower byte (SPI mode 1) and clear the cs in the shift register
            elsif counter + offset <= 526 then
                case counter + offset is
                    when 519 => spi_mosi_pwr <= lower_byte_buf(7); sr_sdi_pwr <= DIG_AUX_buf(2);
                    when 520 => spi_mosi_pwr <= lower_byte_buf(6); sr_sdi_pwr <= DIG_AUX_buf(1);
                    when 521 => spi_mosi_pwr <= lower_byte_buf(5); sr_sdi_pwr <= DIG_AUX_buf(0);
                    when 522 => spi_mosi_pwr <= lower_byte_buf(4); sr_sdi_pwr <= '1';
                    when 523 => spi_mosi_pwr <= lower_byte_buf(3); sr_sdi_pwr <= '1';
                    when 524 => spi_mosi_pwr <= lower_byte_buf(2); sr_sdi_pwr <= '1';
                    when 525 => spi_mosi_pwr <= lower_byte_buf(1); sr_sdi_pwr <= '1';
                    when 526 => spi_mosi_pwr <= lower_byte_buf(0); sr_sdi_pwr <= '1';
                    when others => null;
                end case;
                if sub_ctr >= 10 then
                    sr_sclk_pwr <= '1';
                else
                    spi_clk_pwr <= '1';
                end if;
                
            -- Latch the SR for SPI mode 1
            elsif counter + offset = 527 then
                if sub_ctr >= 10 then
                    sr_latch_pwr <= '1';
                end if;
                if sub_ctr = 19 then
                    offset <= 1000;
                end if;
                
            end if;
        end if;
    end process;

end Behavioral;
