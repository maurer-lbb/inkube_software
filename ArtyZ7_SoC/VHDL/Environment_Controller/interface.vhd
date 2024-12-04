-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 02/02/2023 06:24:53 PM
-- Design Name: 
-- Module Name: interface - Behavioral
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

entity interface is
    Port (
        CLK100MHZ    : in  std_logic;
     
        heater_1     : in  std_logic_vector(11 downto 0);
        heater_2     : in  std_logic_vector(11 downto 0);
        heater_3     : in  std_logic_vector(11 downto 0);
        heater_4     : in  std_logic_vector(11 downto 0);
        heater_res   : in  std_logic_vector(11 downto 0);
        heater_aux   : in  std_logic_vector(11 downto 0);
        
        DIG_AUX      : in  std_logic_vector(2  downto 0);
        
        temp_1       : out std_logic_vector(14 downto 0);
        temp_2       : out std_logic_vector(14 downto 0);
        temp_3       : out std_logic_vector(14 downto 0);
        temp_4       : out std_logic_vector(14 downto 0);
        
        spi_clk_pwr  : out std_logic;
        spi_mosi_pwr : out std_logic;
        
        spi_clk_bot  : out std_logic;
        spi_miso_bot : in  std_logic;
        spi_mosi_bot : out std_logic;
        spi_cs_bot   : out std_logic_vector(3 downto 0);
        
        sr_sdi_pwr   : out std_logic;
        sr_sclk_pwr  : out std_logic;
        sr_latch_pwr : out std_logic
        );
end interface;

architecture Behavioral of interface is
    component simple_spi is
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
    end component;


    component complex_spi is
        port (
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
    end component;
    
    signal upper_byte      : std_logic_vector(7 downto 0) := "00000000";
    signal lower_byte      : std_logic_vector(7 downto 0) := "00000000";
    signal start_pwr       : std_logic := '0';
    signal ready_pwr       : std_logic := '1';
    signal start_bot       : std_logic := '0';
    signal ready_bot       : std_logic := '1';
    signal output_byte_pwr : std_logic_vector(7 downto 0) := "00000000";
    signal output_byte_bot : std_logic_vector(7 downto 0) := "00000000";
    
    signal spi_cs_bot_buf  : std_logic_vector(3 downto 0) := "1111";
    signal spi_cs_bot_out  : std_logic_vector(3 downto 0) := "1111";
    
    signal ms_counter      : integer range 0 to 124 := 0;
    signal sub_counter     : integer range 0 to 99999 := 0;
    signal phase_counter   : integer range 0 to 3 := 0;
    
    signal state           : integer := 0;
    
    signal data_buffer     : std_logic_vector(14 downto 0);
    
    signal heater_1_pos    : std_logic_vector(11 downto 0) := "000000000000";
    signal heater_2_pos    : std_logic_vector(11 downto 0) := "000000000000";
    signal heater_3_pos    : std_logic_vector(11 downto 0) := "000000000000";
    signal heater_4_pos    : std_logic_vector(11 downto 0) := "000000000000";
    signal heater_1_neg    : std_logic_vector(11 downto 0) := "000000000000";
    signal heater_2_neg    : std_logic_vector(11 downto 0) := "000000000000";
    signal heater_3_neg    : std_logic_vector(11 downto 0) := "000000000000";
    signal heater_4_neg    : std_logic_vector(11 downto 0) := "000000000000";
    
    signal spi_cs_pwr      : std_logic_vector(4 downto 0) := "00000";
    
    signal data : integer;
    
    signal spi_clk_bot_inv : std_logic;
    
begin
    complex_spi_instance: complex_spi port map (
        CLK100MHZ    => CLK100MHZ,
                    
        upper_byte   => upper_byte,
        lower_byte   => lower_byte,
        DIG_AUX      => DIG_AUX,
        cs           => spi_cs_pwr,
        start        => start_pwr,
                    
        ready        => ready_pwr,
                    
        spi_clk_pwr  => spi_clk_pwr,
        spi_mosi_pwr => spi_mosi_pwr,
                    
        sr_sdi_pwr   => sr_sdi_pwr,
        sr_sclk_pwr  => sr_sclk_pwr,
        sr_latch_pwr => sr_latch_pwr,
                    
        output_byte => output_byte_pwr
    );
    
    simple_spi_instance: simple_spi port map (
        CLK100MHZ      => CLK100MHZ,
                      
        upper_byte     => upper_byte,
        lower_byte     => lower_byte,
        start          => start_bot,
                      
        ready          => ready_bot,
                      
        spi_clk_bot    => spi_clk_bot_inv,
        spi_mosi_bot   => spi_mosi_bot,
        spi_miso_bot   => spi_miso_bot,
        spi_cs_bot     => spi_cs_bot_buf,
                    
        output_byte    => output_byte_bot,
        spi_cs_bot_out => spi_cs_bot_out
    );
    
    spi_cs_bot <= spi_cs_bot_out;
    spi_clk_bot <= not spi_clk_bot_inv;
    
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if state = 0 then
                if heater_1 = "111111111111" then
                    heater_1_pos <= "100000000000";
                    heater_1_neg <= "100000000000";
                else
                    heater_1_pos <= heater_1;
                    heater_1_neg <= std_logic_vector(to_unsigned(4095-to_integer(unsigned(heater_1)),12));
                end if;
                if heater_2 = "111111111111" then
                    heater_2_pos <= "100000000000";
                    heater_2_neg <= "100000000000";
                else
                    heater_2_pos <= heater_2;
                    heater_2_neg <= std_logic_vector(to_unsigned(4095-to_integer(unsigned(heater_2)),12));
                end if;
                if heater_3 = "111111111111" then
                    heater_3_pos <= "100000000000";
                    heater_3_neg <= "100000000000";
                else
                    heater_3_pos <= heater_3;
                    heater_3_neg <= std_logic_vector(to_unsigned(4095-to_integer(unsigned(heater_3)),12));
                end if;
                if heater_4 = "111111111111" then
                    heater_4_pos <= "100000000000";
                    heater_4_neg <= "100000000000";
                else
                    heater_4_pos <= heater_4;
                    heater_4_neg <= std_logic_vector(to_unsigned(4095-to_integer(unsigned(heater_4)),12));
                end if;
            end if;
        end if;
    end process;
    
    -- This process is only there to count the clocks. sub_counter counts every clock, 
    -- ms_counter counts every ms, phase_counter counts 4 phases in total (for the 4 MEAs)
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            if sub_counter = 99999 then
                sub_counter <= 0;
                if ms_counter = 124 then
                    ms_counter <= 0;
                    if phase_counter = 3 then
                        phase_counter <= 0;
                    else
                        phase_counter <= phase_counter + 1;
                    end if;
                else
                    ms_counter <= ms_counter + 1;
                end if;
            else
                sub_counter <= sub_counter + 1;
            end if;
        end if;
    end process;
    
    -- Needs driving: upper_byte, lower_byte, cs, start
    process(CLK100MHZ)
    begin
        if rising_edge(CLK100MHZ) then
            case state is
                -- Writing config reg to clear faults (MEA A)
                when 0   => spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "0001";
                            upper_byte <= "10000000";
                            lower_byte <= "10000011";
                            start_pwr  <= '0';
                            start_bot  <= '0';
                            if(ms_counter = 0) then state <= 1; end if;
                when 1   => if(ready_bot = '1') then start_bot <= '1'; state <= 2; end if;
                when 2   => if(ready_bot = '0') then start_bot <= '0'; state <= 3; end if;
                -- Start a conversion (MEA A)
                when 3   => spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "0001";
                            upper_byte <= "10000000";
                            lower_byte <= "10100001";
                            start_pwr  <= '0';
                            start_bot  <= '0';
                            if(ms_counter = 2) then state <= 4; end if;
                when 4   => if(ready_bot = '1') then start_bot <= '1'; state <= 5; end if;
                when 5   => if(ready_bot = '0') then start_bot <= '0'; state <= 6; end if;
                
                -- Writing config reg to clear faults (MEA B)
                when 6   => spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "0010";
                            upper_byte <= "10000000";
                            lower_byte <= "10000011";
                            start_pwr  <= '0';
                            start_bot  <= '0';
                            if(ms_counter = 5) then state <= 7; end if;
                when 7   => if(ready_bot = '1') then start_bot <= '1'; state <= 8; end if;
                when 8   => if(ready_bot = '0') then start_bot <= '0'; state <= 9; end if;
                -- Start a conversion (MEA B)
                when 9   => spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "0010";
                            upper_byte <= "10000000";
                            lower_byte <= "10100001";
                            start_pwr  <= '0';
                            start_bot  <= '0';
                            if(ms_counter = 7) then state <= 10; end if;
                when 10  => if(ready_bot = '1') then start_bot <= '1'; state <= 11; end if;
                when 11  => if(ready_bot = '0') then start_bot <= '0'; state <= 12; end if;
                
                -- Writing config reg to clear faults (MEA C)
                when 12  => spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "0100";
                            upper_byte <= "10000000";
                            lower_byte <= "10000011";
                            start_pwr  <= '0';
                            start_bot  <= '0';
                            if(ms_counter = 10) then state <= 13; end if;
                when 13  => if(ready_bot = '1') then start_bot <= '1'; state <= 14; end if;
                when 14  => if(ready_bot = '0') then start_bot <= '0'; state <= 15; end if;
                -- Start a conversion (MEA C)
                when 15  => spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "0100";
                            upper_byte <= "10000000";
                            lower_byte <= "10100001";
                            start_pwr  <= '0';
                            start_bot  <= '0';
                            if(ms_counter = 12) then state <= 16; end if;
                when 16  => if(ready_bot = '1') then start_bot <= '1'; state <= 17; end if;
                when 17  => if(ready_bot = '0') then start_bot <= '0'; state <= 18; end if;
                
                -- Writing config reg to clear faults (MEA D)
                when 18  => spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "1000";
                            upper_byte <= "10000000";
                            lower_byte <= "10000011";
                            start_pwr  <= '0';
                            start_bot  <= '0';
                            if(ms_counter = 15) then state <= 19; end if;
                when 19  => if(ready_bot = '1') then start_bot <= '1'; state <= 20; end if;
                when 20  => if(ready_bot = '0') then start_bot <= '0'; state <= 21; end if;
                -- Start a conversion (MEA D)
                when 21  => spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "1000";
                            upper_byte <= "10000000";
                            lower_byte <= "10100001";
                            start_pwr  <= '0';
                            start_bot  <= '0';
                            if(ms_counter = 17) then state <= 22; end if;
                when 22  => if(ready_bot = '1') then start_bot <= '1'; state <= 23; end if;
                when 23  => if(ready_bot = '0') then start_bot <= '0'; state <= 24; end if;
                
                
                -- DAC MEAA pos channel
                when 24  => upper_byte(7 downto 4) <= "0011";
                            upper_byte(3 downto 0) <= heater_1_pos(11 downto 8);
                            lower_byte             <= heater_1_pos(7  downto 0);
                            spi_cs_pwr             <= "00001";
                            spi_cs_bot_buf             <= "0000";
                            if(ms_counter = 80) then state <= 25; end if;
                when 25  => if(ready_pwr = '1') then start_pwr <= '1'; state <= 26; end if;
                when 26  => if(ready_pwr = '0') then start_pwr <= '0'; state <= 27; end if;
                -- DAC MEAA neg channel
                when 27  => upper_byte(7 downto 4) <= "1011";
                            upper_byte(3 downto 0) <= heater_1_neg(11 downto 8);
                            lower_byte             <= heater_1_neg(7  downto 0);
                            spi_cs_pwr             <= "00001";
                            if(ms_counter = 81) then state <= 28; end if;
                when 28  => if(ready_pwr = '1') then start_pwr <= '1'; state <= 29; end if;
                when 29  => if(ready_pwr = '0') then start_pwr <= '0'; state <= 30; end if;
                -- DAC MEAB pos channel
                when 30  => upper_byte(7 downto 4) <= "0011";
                            upper_byte(3 downto 0) <= heater_2_pos(11 downto 8);
                            lower_byte             <= heater_2_pos(7  downto 0);
                            spi_cs_pwr             <= "00010";
                            if(ms_counter = 82) then state <= 31; end if;
                when 31  => if(ready_pwr = '1') then start_pwr <= '1'; state <= 32; end if;
                when 32  => if(ready_pwr = '0') then start_pwr <= '0'; state <= 33; end if;
                -- DAC MEAB neg channel
                when 33  => upper_byte(7 downto 4) <= "1011";
                            upper_byte(3 downto 0) <= heater_2_neg(11 downto 8);
                            lower_byte             <= heater_2_neg(7  downto 0);
                            spi_cs_pwr             <= "00010";
                            if(ms_counter = 83) then state <= 34; end if;
                when 34  => if(ready_pwr = '1') then start_pwr <= '1'; state <= 35; end if;
                when 35  => if(ready_pwr = '0') then start_pwr <= '0'; state <= 36; end if;
                -- DAC MEAC pos channel
                when 36  => upper_byte(7 downto 4) <= "0011";
                            upper_byte(3 downto 0) <= heater_3_pos(11 downto 8);
                            lower_byte             <= heater_3_pos(7  downto 0);
                            spi_cs_pwr             <= "00100";
                            if(ms_counter = 84) then state <= 37; end if;
                when 37  => if(ready_pwr = '1') then start_pwr <= '1'; state <= 38; end if;
                when 38  => if(ready_pwr = '0') then start_pwr <= '0'; state <= 39; end if;
                -- DAC MEAC neg channel
                when 39  => upper_byte(7 downto 4) <= "1011";
                            upper_byte(3 downto 0) <= heater_3_neg(11 downto 8);
                            lower_byte             <= heater_3_neg(7  downto 0);
                            spi_cs_pwr             <= "00100";
                            if(ms_counter = 85) then state <= 40; end if;
                when 40  => if(ready_pwr = '1') then start_pwr <= '1'; state <= 41; end if;
                when 41  => if(ready_pwr = '0') then start_pwr <= '0'; state <= 42; end if;
                -- DAC MEAD pos channel
                when 42  => upper_byte(7 downto 4) <= "0011";
                            upper_byte(3 downto 0) <= heater_4_pos(11 downto 8);
                            lower_byte             <= heater_4_pos(7  downto 0);
                            spi_cs_pwr             <= "01000";
                            if(ms_counter = 86) then state <= 43; end if;
                when 43  => if(ready_pwr = '1') then start_pwr <= '1'; state <= 44; end if;
                when 44  => if(ready_pwr = '0') then start_pwr <= '0'; state <= 45; end if;
                -- DAC MEAD neg channel
                when 45  => upper_byte(7 downto 4) <= "1011";
                            upper_byte(3 downto 0) <= heater_4_neg(11 downto 8);
                            lower_byte             <= heater_4_neg(7  downto 0);
                            spi_cs_pwr             <= "01000";
                            if(ms_counter = 87) then state <= 46; end if;
                when 46  => if(ready_pwr = '1') then start_pwr <= '1'; state <= 47; end if;
                when 47  => if(ready_pwr = '0') then start_pwr <= '0'; state <= 48; end if;
                
                -- DAC MEA htr
                when 48  => upper_byte(7 downto 4) <= "0011";
                            upper_byte(3 downto 0) <= heater_res(11 downto 8);
                            lower_byte             <= heater_res(7  downto 0);
                            spi_cs_pwr             <= "10000";
                            if(ms_counter = 88) then state <= 49; end if;
                when 49  => if(ready_pwr = '1') then start_pwr <= '1'; state <= 50; end if;
                when 50  => if(ready_pwr = '0') then start_pwr <= '0'; state <= 51; end if;
                -- DAC MEA AUX
                when 51  => upper_byte(7 downto 4) <= "1011";
                            upper_byte(3 downto 0) <= heater_aux(11 downto 8);
                            lower_byte             <= heater_aux(7  downto 0);
                            spi_cs_pwr             <= "10000";
                            if(ms_counter = 89) then state <= 52; end if;
                when 52  => if(ready_pwr = '1') then start_pwr <= '1'; state <= 53; end if;
                when 53  => if(ready_pwr = '0') then start_pwr <= '0'; state <= 54; end if;
                
                -- Read MSB MEA_A
                when 54  => upper_byte <= "00000001";
                            lower_byte <= "00000000";
                            spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "0001";
                            if(ms_counter = 105) then state <= 55; end if;
                when 55  => if(ready_bot = '1') then start_bot <= '1'; state <= 56; end if;
                when 56  => if(ready_bot = '0') then start_bot <= '0'; state <= 57; end if;
                when 57  => if(ready_bot = '1') then
                                data_buffer(14 downto 7) <= output_byte_bot;
                                state <= 58;
                            end if; 
                -- Read LSB MEA_A
                when 58  => upper_byte <= "00000010";
                            lower_byte <= "00000000";
                            spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "0001";
                            if(ms_counter = 106) then state <= 59; end if;
                when 59  => if(ready_bot = '1') then start_bot <= '1'; state <= 60; end if;
                when 60  => if(ready_bot = '0') then start_bot <= '0'; state <= 61; end if;
                when 61  => if(ready_bot = '1') then
                                data_buffer(6 downto 0) <= output_byte_bot(7 downto 1);
                                state <= 62;
                            end if; 
                when 62  => temp_1 <= data_buffer; state <= 63;
                
                -- Read MSB MEA_B
                when 63  => upper_byte <= "00000001";
                            lower_byte <= "00000000";
                            spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "0010";
                            if(ms_counter = 110) then state <= 64; end if;
                when 64  => if(ready_bot = '1') then start_bot <= '1'; state <= 65; end if;
                when 65  => if(ready_bot = '0') then start_bot <= '0'; state <= 66; end if;
                when 66  => if(ready_bot = '1') then
                                data_buffer(14 downto 7) <= output_byte_bot;
                                state <= 67;
                            end if; 
                -- Read LSB MEA_B
                when 67  => upper_byte <= "00000010";
                            lower_byte <= "00000000";
                            spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "0010";
                            if(ms_counter = 111) then state <= 68; end if;
                when 68  => if(ready_bot = '1') then start_bot <= '1'; state <= 69; end if;
                when 69  => if(ready_bot = '0') then start_bot <= '0'; state <= 70; end if;
                when 70  => if(ready_bot = '1') then
                                data_buffer(6 downto 0) <= output_byte_bot(7 downto 1);
                                state <= 71;
                            end if; 
                when 71  => temp_2 <= data_buffer; state <= 72;
                
                -- Read MSB MEA_C
                when 72  => upper_byte <= "00000001";
                            lower_byte <= "00000000";
                            spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "0100";
                            if(ms_counter = 115) then state <= 73; end if;
                when 73  => if(ready_bot = '1') then start_bot <= '1'; state <= 74; end if;
                when 74  => if(ready_bot = '0') then start_bot <= '0'; state <= 75; end if;
                when 75  => if(ready_bot = '1') then
                                data_buffer(14 downto 7) <= output_byte_bot;
                                state <= 76;
                            end if; 
                -- Read LSB MEA_C
                when 76  => upper_byte <= "00000010";
                            lower_byte <= "00000000";
                            spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "0100";
                            if(ms_counter = 116) then state <= 77; end if;
                when 77  => if(ready_bot = '1') then start_bot <= '1'; state <= 78; end if;
                when 78  => if(ready_bot = '0') then start_bot <= '0'; state <= 79; end if;
                when 79  => if(ready_bot = '1') then
                                data_buffer(6 downto 0) <= output_byte_bot(7 downto 1);
                                state <= 80;
                            end if; 
                when 80  => temp_3 <= data_buffer; state <= 81;
                
                -- Read MSB MEA_D
                when 81  => upper_byte <= "00000001";
                            lower_byte <= "00000000";
                            spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "1000";
                            if(ms_counter = 120) then state <= 82; end if;
                when 82  => if(ready_bot = '1') then start_bot <= '1'; state <= 83; end if;
                when 83  => if(ready_bot = '0') then start_bot <= '0'; state <= 84; end if;
                when 84  => if(ready_bot = '1') then
                                data_buffer(14 downto 7) <= output_byte_bot;
                                state <= 85;
                            end if; 
                -- Read LSB MEA_D
                when 85  => upper_byte <= "00000010";
                            lower_byte <= "00000000";
                            spi_cs_pwr <= "00000";
                            spi_cs_bot_buf <= "1000";
                            if(ms_counter = 121) then state <= 86; end if;
                when 86  => if(ready_bot = '1') then start_bot <= '1'; state <= 87; end if;
                when 87  => if(ready_bot = '0') then start_bot <= '0'; state <= 88; end if;
                when 88  => if(ready_bot = '1') then
                                data_buffer(6 downto 0) <= output_byte_bot(7 downto 1);
                                state <= 89;
                            end if; 
                when 89  => temp_4 <= data_buffer; state <= 90;
                
                when others => state <= 0;
            end case;
        end if;
    end process;

end Behavioral;
