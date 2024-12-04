-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 07/26/2021 11:50:48 PM
-- Design Name: 
-- Module Name: axis_fifo_core - Behavioral
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

entity axis_fifo_core is
    Port ( 
        clk :            in  std_logic;
        resetn :         in  std_logic;
        fifo_write_data: in  std_logic_vector(31 downto 0);
        fifo_read_data:  out std_logic_vector(31 downto 0);
        fifo_write_en:   in  std_logic;
        fifo_read_en:    in  std_logic;
        fifo_full:       out std_logic;
        fifo_not_empty:  out std_logic;
        fifo_length:     out std_logic_vector(15 downto 0);
        package_count:   in  std_logic_vector(31 downto 0);
        word_count:      in  std_logic_vector(31 downto 0)
    );
end axis_fifo_core;

architecture Behavioral of axis_fifo_core is
    component fifo_record IS
        PORT (
            clk        : IN STD_LOGIC;
            srst       : IN STD_LOGIC;
            din        : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
            wr_en      : IN STD_LOGIC;
            rd_en      : IN STD_LOGIC;
            dout       : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
            full       : OUT STD_LOGIC;
            empty      : OUT STD_LOGIC;
            data_count : OUT STD_LOGIC_VECTOR(15 DOWNTO 0)
        );
    end component;
    
    signal empty  : std_logic;
    signal reset  : std_logic;

begin

    fifo_not_empty <= not empty;
    reset          <= not resetn;

    fifo: fifo_record port map(
        clk        => clk,
        srst       => reset,
        din        => fifo_write_data,
        wr_en      => fifo_write_en,
        rd_en      => fifo_read_en,
        dout       => fifo_read_data,
        full       => fifo_full,
        empty      => empty,
        data_count => fifo_length
    );

end Behavioral;
