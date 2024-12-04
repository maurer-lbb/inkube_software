-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity SPI_16_v1_0 is
	generic (
		-- Users to add parameters here

		-- User parameters ends
		-- Do not modify the parameters beyond this line


		-- Parameters of Axi Slave Bus Interface S00_AXI
		C_S00_AXI_DATA_WIDTH	: integer	:= 32;
		C_S00_AXI_ADDR_WIDTH	: integer	:= 4
	);
	port (
		-- Users to add ports here
        package_count : out std_logic_vector(31 downto 0);
        word_count    : out std_logic_vector(31 downto 0);
        fifo_length   : in  std_logic_vector(15 downto 0);
        
        write_en      : out std_logic;
        write_data    : out std_logic_vector(31 downto 0);
        
        INTAN_CS      : out std_logic;
        INTAN_CLK     : out std_logic;
        INTAN_MOSI_1  : out std_logic_vector(3 downto 0);
        INTAN_MOSI_2  : out std_logic_vector(3 downto 0);
        INTAN_MOSI_3  : out std_logic_vector(3 downto 0);
        INTAN_MOSI_4  : out std_logic_vector(3 downto 0);
        INTAN_MISO_1  : in  std_logic_vector(3 downto 0);
        INTAN_MISO_2  : in  std_logic_vector(3 downto 0);
        INTAN_MISO_3  : in  std_logic_vector(3 downto 0);
        INTAN_MISO_4  : in  std_logic_vector(3 downto 0);
        
        COUNTER_IN    : in  std_logic_vector(31 downto 0);
        
		command_11    : in  std_logic_vector(31 downto 0);
		command_12    : in  std_logic_vector(31 downto 0);
		command_13    : in  std_logic_vector(31 downto 0);
		command_14    : in  std_logic_vector(31 downto 0);
		command_21    : in  std_logic_vector(31 downto 0);
		command_22    : in  std_logic_vector(31 downto 0);
		command_23    : in  std_logic_vector(31 downto 0);
		command_24    : in  std_logic_vector(31 downto 0);
		command_31    : in  std_logic_vector(31 downto 0);
		command_32    : in  std_logic_vector(31 downto 0);
		command_33    : in  std_logic_vector(31 downto 0);
		command_34    : in  std_logic_vector(31 downto 0);
		command_41    : in  std_logic_vector(31 downto 0);
		command_42    : in  std_logic_vector(31 downto 0);
		command_43    : in  std_logic_vector(31 downto 0);
		command_44    : in  std_logic_vector(31 downto 0);
		
		level_out_1   : in  std_logic_vector(31 downto 0);
		level_out_2   : in  std_logic_vector(31 downto 0);
		level_out_3   : in  std_logic_vector(31 downto 0);
		level_out_4   : in  std_logic_vector(31 downto 0);
		
		package_loss  : in  std_logic;
        
        temperature_1 : in std_logic_vector(14 downto 0);
        temperature_2 : in std_logic_vector(14 downto 0);
        temperature_3 : in std_logic_vector(14 downto 0);
        temperature_4 : in std_logic_vector(14 downto 0);
        
        temperature_reservoir : in std_logic_vector(15 downto 0);
        humidity_reservoir : in std_logic_vector(15 downto 0);
        co2_concentration_reservoir : in std_logic_vector(15 downto 0);

		-- User ports ends
		-- Do not modify the ports beyond this line


		-- Ports of Axi Slave Bus Interface S00_AXI
		s00_axi_aclk	: in std_logic;
		s00_axi_aresetn	: in std_logic;
		s00_axi_awaddr	: in std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
		s00_axi_awprot	: in std_logic_vector(2 downto 0);
		s00_axi_awvalid	: in std_logic;
		s00_axi_awready	: out std_logic;
		s00_axi_wdata	: in std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
		s00_axi_wstrb	: in std_logic_vector((C_S00_AXI_DATA_WIDTH/8)-1 downto 0);
		s00_axi_wvalid	: in std_logic;
		s00_axi_wready	: out std_logic;
		s00_axi_bresp	: out std_logic_vector(1 downto 0);
		s00_axi_bvalid	: out std_logic;
		s00_axi_bready	: in std_logic;
		s00_axi_araddr	: in std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
		s00_axi_arprot	: in std_logic_vector(2 downto 0);
		s00_axi_arvalid	: in std_logic;
		s00_axi_arready	: out std_logic;
		s00_axi_rdata	: out std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
		s00_axi_rresp	: out std_logic_vector(1 downto 0);
		s00_axi_rvalid	: out std_logic;
		s00_axi_rready	: in std_logic
	);
end SPI_16_v1_0;

architecture arch_imp of SPI_16_v1_0 is

    component spi_interface is
        Port (
            clk           : in  std_logic;
            resetn        : in  std_logic;
            
            package_count : out std_logic_vector(31 downto 0);
            word_count    : out std_logic_vector(31 downto 0);
            run           : in  std_logic;
            init          : in  std_logic;
            phase_1       : in  std_logic_vector(3 downto 0);
            phase_2       : in  std_logic_vector(3 downto 0);
            
            fifo_length   : in  std_logic_vector(15 downto 0); 
            write_en      : out std_logic;
            write_data    : out std_logic_vector(31 downto 0);
            
            INTAN_CS      : out std_logic;
            INTAN_CLK     : out std_logic;
            INTAN_MOSI_1  : out std_logic_vector(3 downto 0);
            INTAN_MOSI_2  : out std_logic_vector(3 downto 0);
            INTAN_MOSI_3  : out std_logic_vector(3 downto 0);
            INTAN_MOSI_4  : out std_logic_vector(3 downto 0);
            INTAN_MISO_1  : in  std_logic_vector(3 downto 0);
            INTAN_MISO_2  : in  std_logic_vector(3 downto 0);
            INTAN_MISO_3  : in  std_logic_vector(3 downto 0);
            INTAN_MISO_4  : in  std_logic_vector(3 downto 0);
            
            COUNTER_IN    : in  std_logic_vector(31 downto 0);
            
            command_11    : in  std_logic_vector(31 downto 0);
            command_12    : in  std_logic_vector(31 downto 0);
            command_13    : in  std_logic_vector(31 downto 0);
            command_14    : in  std_logic_vector(31 downto 0);
            command_21    : in  std_logic_vector(31 downto 0);
            command_22    : in  std_logic_vector(31 downto 0);
            command_23    : in  std_logic_vector(31 downto 0);
            command_24    : in  std_logic_vector(31 downto 0);
            command_31    : in  std_logic_vector(31 downto 0);
            command_32    : in  std_logic_vector(31 downto 0);
            command_33    : in  std_logic_vector(31 downto 0);
            command_34    : in  std_logic_vector(31 downto 0);
            command_41    : in  std_logic_vector(31 downto 0);
            command_42    : in  std_logic_vector(31 downto 0);
            command_43    : in  std_logic_vector(31 downto 0);
            command_44    : in  std_logic_vector(31 downto 0);
        
            package_loss  : in std_logic;  
        
            temperature_1 : in std_logic_vector(14 downto 0);
            temperature_2 : in std_logic_vector(14 downto 0);
            temperature_3 : in std_logic_vector(14 downto 0);
            temperature_4 : in std_logic_vector(14 downto 0); 
		
		    level_out_1   : in  std_logic_vector(31 downto 0);
		    level_out_2   : in  std_logic_vector(31 downto 0);
		    level_out_3   : in  std_logic_vector(31 downto 0);
		    level_out_4   : in  std_logic_vector(31 downto 0);
            
        
            temperature_reservoir : in std_logic_vector(15 downto 0);
            humidity_reservoir : in std_logic_vector(15 downto 0);
            co2_concentration_reservoir : in std_logic_vector(15 downto 0)
        );
    end component spi_interface;

	-- component declaration
	component SPI_16_v1_0_S00_AXI is
		generic (
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		C_S_AXI_ADDR_WIDTH	: integer	:= 4
		);
		port (
        run           : out std_logic;
        init          : out std_logic;
        phase_1       : out std_logic_vector(3 downto 0);
        phase_2       : out std_logic_vector(3 downto 0);
		S_AXI_ACLK	: in std_logic;
		S_AXI_ARESETN	: in std_logic;
		S_AXI_AWADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		S_AXI_AWPROT	: in std_logic_vector(2 downto 0);
		S_AXI_AWVALID	: in std_logic;
		S_AXI_AWREADY	: out std_logic;
		S_AXI_WDATA	: in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		S_AXI_WSTRB	: in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
		S_AXI_WVALID	: in std_logic;
		S_AXI_WREADY	: out std_logic;
		S_AXI_BRESP	: out std_logic_vector(1 downto 0);
		S_AXI_BVALID	: out std_logic;
		S_AXI_BREADY	: in std_logic;
		S_AXI_ARADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
		S_AXI_ARVALID	: in std_logic;
		S_AXI_ARREADY	: out std_logic;
		S_AXI_RDATA	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		S_AXI_RRESP	: out std_logic_vector(1 downto 0);
		S_AXI_RVALID	: out std_logic;
		S_AXI_RREADY	: in std_logic
		);
	end component SPI_16_v1_0_S00_AXI;
        
    signal run_buffer : std_logic;
    signal init_buffer : std_logic;
    signal phase_1_buffer : std_logic_vector(3 downto 0);
    signal phase_2_buffer : std_logic_vector(3 downto 0);

begin

-- Instantiation of Axi Bus Interface S00_AXI
SPI_16_v1_0_S00_AXI_inst : SPI_16_v1_0_S00_AXI
	generic map (
		C_S_AXI_DATA_WIDTH	=> C_S00_AXI_DATA_WIDTH,
		C_S_AXI_ADDR_WIDTH	=> C_S00_AXI_ADDR_WIDTH
	)
	port map (
	    run             => run_buffer,
	    init            => init_buffer,
		S_AXI_ACLK	=> s00_axi_aclk,
		S_AXI_ARESETN	=> s00_axi_aresetn,
		S_AXI_AWADDR	=> s00_axi_awaddr,
		S_AXI_AWPROT	=> s00_axi_awprot,
		S_AXI_AWVALID	=> s00_axi_awvalid,
		S_AXI_AWREADY	=> s00_axi_awready,
		S_AXI_WDATA	=> s00_axi_wdata,
		S_AXI_WSTRB	=> s00_axi_wstrb,
		S_AXI_WVALID	=> s00_axi_wvalid,
		S_AXI_WREADY	=> s00_axi_wready,
		S_AXI_BRESP	=> s00_axi_bresp,
		S_AXI_BVALID	=> s00_axi_bvalid,
		S_AXI_BREADY	=> s00_axi_bready,
		S_AXI_ARADDR	=> s00_axi_araddr,
		S_AXI_ARPROT	=> s00_axi_arprot,
		S_AXI_ARVALID	=> s00_axi_arvalid,
		S_AXI_ARREADY	=> s00_axi_arready,
		S_AXI_RDATA	=> s00_axi_rdata,
		S_AXI_RRESP	=> s00_axi_rresp,
		S_AXI_RVALID	=> s00_axi_rvalid,
		S_AXI_RREADY	=> s00_axi_rready
	);
spi_interface_inst : spi_interface
    port map (
        clk           => s00_axi_aclk,
        resetn        => s00_axi_aresetn,
        
        package_count => package_count,
        word_count    => word_count,
        run           => run_buffer,
        init          => init_buffer,
        
        phase_1       => phase_1_buffer,
        phase_2       => phase_2_buffer,
        
        fifo_length   => fifo_length, 
        write_en      => write_en,
        write_data    => write_data,
        
        INTAN_CS      => INTAN_CS,
        INTAN_CLK     => INTAN_CLK,
        INTAN_MOSI_1  => INTAN_MOSI_1,
        INTAN_MOSI_2  => INTAN_MOSI_2,
        INTAN_MOSI_3  => INTAN_MOSI_3,
        INTAN_MOSI_4  => INTAN_MOSI_4,
        INTAN_MISO_1  => INTAN_MISO_1,
        INTAN_MISO_2  => INTAN_MISO_2,
        INTAN_MISO_3  => INTAN_MISO_3,
        INTAN_MISO_4  => INTAN_MISO_4,
        
        COUNTER_IN    => COUNTER_IN,
        
        
		command_11    => command_11,
		command_12    => command_12,
		command_13    => command_13,
		command_14    => command_14,
		command_21    => command_21,
		command_22    => command_22,
		command_23    => command_23,
		command_24    => command_24,
		command_31    => command_31,
		command_32    => command_32,
		command_33    => command_33,
		command_34    => command_34,
		command_41    => command_41,
		command_42    => command_42,
		command_43    => command_43,
		command_44    => command_44,
		
		package_loss  => package_loss,
		
		temperature_1 => temperature_1,
		temperature_2 => temperature_2,
		temperature_3 => temperature_3,
		temperature_4 => temperature_4,
		
		level_out_1   => level_out_1,
		level_out_2   => level_out_2,
		level_out_3   => level_out_3,
		level_out_4   => level_out_4,
		
        temperature_reservoir       => temperature_reservoir,
        humidity_reservoir          => humidity_reservoir,
        co2_concentration_reservoir => co2_concentration_reservoir
    );

	-- Add user logic here

	-- User logic ends

end arch_imp;
