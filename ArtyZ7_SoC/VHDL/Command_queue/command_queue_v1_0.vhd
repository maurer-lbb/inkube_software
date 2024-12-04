-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity command_queue_v1_0 is
	generic (
		-- Users to add parameters here

		-- User parameters ends
		-- Do not modify the parameters beyond this line


		-- Parameters of Axi Slave Bus Interface S00_AXI
		C_S00_AXI_DATA_WIDTH	: integer	:= 32;
		C_S00_AXI_ADDR_WIDTH	: integer	:= 9
	);
	port (
		-- Users to add ports here
		package_count   : in  std_logic_vector(31 downto 0);
		word_count      : in  std_logic_vector(31 downto 0);
		command_11      : out std_logic_vector(31 downto 0);
		command_12      : out std_logic_vector(31 downto 0);
		command_13      : out std_logic_vector(31 downto 0);
		command_14      : out std_logic_vector(31 downto 0);
		command_21      : out std_logic_vector(31 downto 0);
		command_22      : out std_logic_vector(31 downto 0);
		command_23      : out std_logic_vector(31 downto 0);
		command_24      : out std_logic_vector(31 downto 0);
		command_31      : out std_logic_vector(31 downto 0);
		command_32      : out std_logic_vector(31 downto 0);
		command_33      : out std_logic_vector(31 downto 0);
		command_34      : out std_logic_vector(31 downto 0);
		command_41      : out std_logic_vector(31 downto 0);
		command_42      : out std_logic_vector(31 downto 0);
		command_43      : out std_logic_vector(31 downto 0);
		command_44      : out std_logic_vector(31 downto 0);
		
		package_loss    : out std_logic;
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
end command_queue_v1_0;

architecture arch_imp of command_queue_v1_0 is

	-- component declaration
	component command_queue_v1_0_S00_AXI is
		generic (
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		C_S_AXI_ADDR_WIDTH	: integer	:= 9
		);
		port (
		command_11      : out std_logic_vector(31 downto 0);
		command_12      : out std_logic_vector(31 downto 0);
		command_13      : out std_logic_vector(31 downto 0);
		command_14      : out std_logic_vector(31 downto 0);
		command_21      : out std_logic_vector(31 downto 0);
		command_22      : out std_logic_vector(31 downto 0);
		command_23      : out std_logic_vector(31 downto 0);
		command_24      : out std_logic_vector(31 downto 0);
		command_31      : out std_logic_vector(31 downto 0);
		command_32      : out std_logic_vector(31 downto 0);
		command_33      : out std_logic_vector(31 downto 0);
		command_34      : out std_logic_vector(31 downto 0);
		command_41      : out std_logic_vector(31 downto 0);
		command_42      : out std_logic_vector(31 downto 0);
		command_43      : out std_logic_vector(31 downto 0);
		command_44      : out std_logic_vector(31 downto 0);
		
		package_count   : in  std_logic_vector(31 downto 0);
		word_count      : in  std_logic_vector(31 downto 0);
		
		package_loss    : out std_logic;
		
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
	end component command_queue_v1_0_S00_AXI;

	signal package_count_buf : std_logic_vector(31 downto 0) := (others => '0');
	
begin

-- Instantiation of Axi Bus Interface S00_AXI
command_queue_v1_0_S00_AXI_inst : command_queue_v1_0_S00_AXI
	generic map (
		C_S_AXI_DATA_WIDTH	=> C_S00_AXI_DATA_WIDTH,
		C_S_AXI_ADDR_WIDTH	=> C_S00_AXI_ADDR_WIDTH
	)
	port map (
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
		S_AXI_RREADY	=> s00_axi_rready,
		command_11      => command_11,
		command_12      => command_12,
		command_13      => command_13,
		command_14      => command_14,
		command_21      => command_21,
		command_22      => command_22,
		command_23      => command_23,
		command_24      => command_24,
		command_31      => command_31,
		command_32      => command_32,
		command_33      => command_33,
		command_34      => command_34,
		command_41      => command_41,
		command_42      => command_42,
		command_43      => command_43,
		command_44      => command_44,
		package_loss    => package_loss,
		
		package_count   => package_count_buf,
		word_count      => word_count
	);

	-- Add user logic here      
	process(s00_axi_aclk) is
	begin
	    if (rising_edge (s00_axi_aclk)) then
            package_count_buf <= package_count; -- Done to solve a timing issue. Not necessary otherwise
        end if;
    end process;
	-- User logic ends

end arch_imp;
