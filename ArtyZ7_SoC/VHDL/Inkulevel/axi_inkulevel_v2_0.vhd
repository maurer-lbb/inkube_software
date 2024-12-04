-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_inkulevel_v2_0 is
	generic (
		-- Users to add parameters here

		-- User parameters ends
		-- Do not modify the parameters beyond this line


		-- Parameters of Axi Slave Bus Interface S00_AXI
		C_S00_AXI_DATA_WIDTH	: integer	:= 32;
		C_S00_AXI_ADDR_WIDTH	: integer	:= 6
	);
	port (
		-- Users to add ports here
		uart_recv :    in  std_logic;
		uart_send :    out std_logic;
		
		level_out_1 : out std_logic_vector(31 downto 0);
		level_out_2 : out std_logic_vector(31 downto 0);
		level_out_3 : out std_logic_vector(31 downto 0);
		level_out_4 : out std_logic_vector(31 downto 0);
		
		valid_1 : out std_logic;
		valid_2 : out std_logic;
		valid_3 : out std_logic;
		valid_4 : out std_logic;
		
		debug_sig : out std_logic_vector(4 downto 0);
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
end axi_inkulevel_v2_0;

architecture arch_imp of axi_inkulevel_v2_0 is

    component uart_to_parallel is
        Generic (
            BAUD      : integer := 9600;
            CLK_FREQ  : integer := 100000000
        );
        Port ( 
            CLK100MHz : in  std_logic;
            uart      : in  std_logic;
            
            level_1   : out std_logic_vector(15 downto 0);
            level_2   : out std_logic_vector(15 downto 0);
            level_3   : out std_logic_vector(15 downto 0);
            level_4   : out std_logic_vector(15 downto 0);
        
            valid_1   : out std_logic;
            valid_2   : out std_logic;
            valid_3   : out std_logic;
            valid_4   : out std_logic;
            
            ctr_1     : out std_logic_vector(15 downto 0);
            ctr_2     : out std_logic_vector(15 downto 0);
            ctr_3     : out std_logic_vector(15 downto 0);
            ctr_4     : out std_logic_vector(15 downto 0)
        );
    end component;
    
    component uart_send_commands is
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
    end component;

	-- component declaration
	component axi_inkulevel_v2_0_S00_AXI is
		generic (
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		C_S_AXI_ADDR_WIDTH	: integer	:= 6
		);
		port (
        level_1         : in std_logic_vector(15 downto 0);
        level_2         : in std_logic_vector(15 downto 0);
        level_3         : in std_logic_vector(15 downto 0);
        level_4         : in std_logic_vector(15 downto 0);
        
        ctr_1           : in std_logic_vector(15 downto 0);
        ctr_2           : in std_logic_vector(15 downto 0);
        ctr_3           : in std_logic_vector(15 downto 0);
        ctr_4           : in std_logic_vector(15 downto 0);
        
        valid_1         : in std_logic;
        valid_2         : in std_logic;
        valid_3         : in std_logic;
        valid_4         : in std_logic;
        
        conversion_1    : out std_logic;
        conversion_2    : out std_logic;
        conversion_3    : out std_logic;
        conversion_4    : out std_logic;
        
        send_images_1   : out std_logic_vector(7 downto 0);
        send_images_2   : out std_logic_vector(7 downto 0);
        send_images_3   : out std_logic_vector(7 downto 0);
        send_images_4   : out std_logic_vector(7 downto 0);
        
        low_thr_inkulevel_1 : out std_logic_vector(7 downto 0);
        low_thr_inkulevel_2 : out std_logic_vector(7 downto 0);
        low_thr_inkulevel_3 : out std_logic_vector(7 downto 0);
        low_thr_inkulevel_4 : out std_logic_vector(7 downto 0);
        
        high_thr_inkulevel_1 : out std_logic_vector(7 downto 0);
        high_thr_inkulevel_2 : out std_logic_vector(7 downto 0);
        high_thr_inkulevel_3 : out std_logic_vector(7 downto 0);
        high_thr_inkulevel_4 : out std_logic_vector(7 downto 0);
        
        intensity_thr_inkulevel_1 : out std_logic_vector(7 downto 0);
        intensity_thr_inkulevel_2 : out std_logic_vector(7 downto 0);
        intensity_thr_inkulevel_3 : out std_logic_vector(7 downto 0);
        intensity_thr_inkulevel_4 : out std_logic_vector(7 downto 0);
        
        inkulevel_command_11_1 : out std_logic_vector(7 downto 0);
        inkulevel_command_11_2 : out std_logic_vector(7 downto 0);
        inkulevel_command_11_3 : out std_logic_vector(7 downto 0);
        inkulevel_command_11_4 : out std_logic_vector(7 downto 0);
        inkulevel_command_12_1 : out std_logic_vector(7 downto 0);
        inkulevel_command_12_2 : out std_logic_vector(7 downto 0);
        inkulevel_command_12_3 : out std_logic_vector(7 downto 0);
        inkulevel_command_12_4 : out std_logic_vector(7 downto 0);
        inkulevel_command_13_1 : out std_logic_vector(7 downto 0);
        inkulevel_command_13_2 : out std_logic_vector(7 downto 0);
        inkulevel_command_13_3 : out std_logic_vector(7 downto 0);
        inkulevel_command_13_4 : out std_logic_vector(7 downto 0);
        inkulevel_command_14_1 : out std_logic_vector(7 downto 0);
        inkulevel_command_14_2 : out std_logic_vector(7 downto 0);
        inkulevel_command_14_3 : out std_logic_vector(7 downto 0);
        inkulevel_command_14_4 : out std_logic_vector(7 downto 0);
        inkulevel_command_15_1 : out std_logic_vector(7 downto 0);
        inkulevel_command_15_2 : out std_logic_vector(7 downto 0);
        inkulevel_command_15_3 : out std_logic_vector(7 downto 0);
        inkulevel_command_15_4 : out std_logic_vector(7 downto 0);
        
        assign_order    : out std_logic;
        debug_0         : out std_logic;
        
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
	end component axi_inkulevel_v2_0_S00_AXI;
	
	signal valid_1_buf : std_logic;
	signal valid_2_buf : std_logic;
	signal valid_3_buf : std_logic;
	signal valid_4_buf : std_logic;
	
	signal level_1_buf : std_logic_vector(15 downto 0);
	signal level_2_buf : std_logic_vector(15 downto 0);
	signal level_3_buf : std_logic_vector(15 downto 0);
	signal level_4_buf : std_logic_vector(15 downto 0);
	
	signal ctr_1       : std_logic_vector(15 downto 0);
	signal ctr_2       : std_logic_vector(15 downto 0);
	signal ctr_3       : std_logic_vector(15 downto 0);
	signal ctr_4       : std_logic_vector(15 downto 0);
        
    signal conversion_1  : std_logic := '0';
    signal conversion_2  : std_logic := '0';
    signal conversion_3  : std_logic := '0';
    signal conversion_4  : std_logic := '0';
    
    signal send_images_1 : std_logic_vector(7 downto 0) := "00000000";
    signal send_images_2 : std_logic_vector(7 downto 0) := "00000000";
    signal send_images_3 : std_logic_vector(7 downto 0) := "00000000";
    signal send_images_4 : std_logic_vector(7 downto 0) := "00000000";
    
    signal low_thr_inkulevel_1 : std_logic_vector(7 downto 0) := "00000000";
    signal low_thr_inkulevel_2 : std_logic_vector(7 downto 0) := "00000000";
    signal low_thr_inkulevel_3 : std_logic_vector(7 downto 0) := "00000000";
    signal low_thr_inkulevel_4 : std_logic_vector(7 downto 0) := "00000000";
    
    signal high_thr_inkulevel_1 : std_logic_vector(7 downto 0) := "10010110";
    signal high_thr_inkulevel_2 : std_logic_vector(7 downto 0) := "10010110";
    signal high_thr_inkulevel_3 : std_logic_vector(7 downto 0) := "10010110";
    signal high_thr_inkulevel_4 : std_logic_vector(7 downto 0) := "10010110";
    
    signal intensity_thr_inkulevel_1 : std_logic_vector(7 downto 0) := "00000000";
    signal intensity_thr_inkulevel_2 : std_logic_vector(7 downto 0) := "00000000";
    signal intensity_thr_inkulevel_3 : std_logic_vector(7 downto 0) := "00000000";
    signal intensity_thr_inkulevel_4 : std_logic_vector(7 downto 0) := "00000000";
       
    signal inkulevel_command_11_1 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_11_2 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_11_3 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_11_4 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_12_1 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_12_2 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_12_3 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_12_4 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_13_1 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_13_2 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_13_3 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_13_4 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_14_1 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_14_2 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_14_3 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_14_4 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_15_1 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_15_2 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_15_3 : std_logic_vector(7 downto 0):= "00000000";
    signal inkulevel_command_15_4 : std_logic_vector(7 downto 0):= "00000000";
    
    signal assign_order  : std_logic := '0';

begin

-- Instantiation of Axi Bus Interface S00_AXI
axi_inkulevel_v2_0_S00_AXI_inst : axi_inkulevel_v2_0_S00_AXI
	generic map (
		C_S_AXI_DATA_WIDTH	=> C_S00_AXI_DATA_WIDTH,
		C_S_AXI_ADDR_WIDTH	=> C_S00_AXI_ADDR_WIDTH
	)
	port map (
        level_1 => level_1_buf,
        level_2 => level_2_buf,
        level_3 => level_3_buf,
        level_4 => level_4_buf,
                   
        ctr_1   => ctr_1,
        ctr_2   => ctr_2,
        ctr_3   => ctr_3,
        ctr_4   => ctr_4,
                   
        valid_1 => valid_1_buf,
        valid_2 => valid_2_buf,
        valid_3 => valid_3_buf,
        valid_4 => valid_4_buf,
        
        conversion_1 => conversion_1,
        conversion_2 => conversion_2,
        conversion_3 => conversion_3,
        conversion_4 => conversion_4,
        
        send_images_1 => send_images_1,
        send_images_2 => send_images_2,
        send_images_3 => send_images_3,
        send_images_4 => send_images_4,
        
        low_thr_inkulevel_1 => low_thr_inkulevel_1,
        low_thr_inkulevel_2 => low_thr_inkulevel_2,
        low_thr_inkulevel_3 => low_thr_inkulevel_3,
        low_thr_inkulevel_4 => low_thr_inkulevel_4,
        
        high_thr_inkulevel_1 => high_thr_inkulevel_1,
        high_thr_inkulevel_2 => high_thr_inkulevel_2,
        high_thr_inkulevel_3 => high_thr_inkulevel_3,
        high_thr_inkulevel_4 => high_thr_inkulevel_4,
        
        intensity_thr_inkulevel_1 => intensity_thr_inkulevel_1,
        intensity_thr_inkulevel_2 => intensity_thr_inkulevel_2,
        intensity_thr_inkulevel_3 => intensity_thr_inkulevel_3,
        intensity_thr_inkulevel_4 => intensity_thr_inkulevel_4,
            
        inkulevel_command_11_1 => inkulevel_command_11_1,
        inkulevel_command_11_2 => inkulevel_command_11_2,
        inkulevel_command_11_3 => inkulevel_command_11_3,
        inkulevel_command_11_4 => inkulevel_command_11_4,
        inkulevel_command_12_1 => inkulevel_command_12_1,
        inkulevel_command_12_2 => inkulevel_command_12_2,
        inkulevel_command_12_3 => inkulevel_command_12_3,
        inkulevel_command_12_4 => inkulevel_command_12_4,
        inkulevel_command_13_1 => inkulevel_command_13_1,
        inkulevel_command_13_2 => inkulevel_command_13_2,
        inkulevel_command_13_3 => inkulevel_command_13_3,
        inkulevel_command_13_4 => inkulevel_command_13_4,
        inkulevel_command_14_1 => inkulevel_command_14_1,
        inkulevel_command_14_2 => inkulevel_command_14_2,
        inkulevel_command_14_3 => inkulevel_command_14_3,
        inkulevel_command_14_4 => inkulevel_command_14_4,
        inkulevel_command_15_1 => inkulevel_command_15_1,
        inkulevel_command_15_2 => inkulevel_command_15_2,
        inkulevel_command_15_3 => inkulevel_command_15_3,
        inkulevel_command_15_4 => inkulevel_command_15_4,
        
        assign_order  => assign_order,
        debug_0       => debug_sig(0),
	
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

	-- Add user logic here
    uart_to_parallel_inst : uart_to_parallel
        port map ( 
            CLK100MHz => s00_axi_aclk,
            uart      => uart_recv,
                      
            level_1   => level_1_buf,
            level_2   => level_2_buf,
            level_3   => level_3_buf,
            level_4   => level_4_buf,
                      
            valid_1   => valid_1_buf,
            valid_2   => valid_2_buf,
            valid_3   => valid_3_buf,
            valid_4   => valid_4_buf,
                      
            ctr_1     => ctr_1,
            ctr_2     => ctr_2,
            ctr_3     => ctr_3,
            ctr_4     => ctr_4
        );
        
    uart_send_commands_inst : uart_send_commands
        port map ( 
            CLK100MHz     => s00_axi_aclk,     
            uart          => uart_send,          
       
            conversion_1  => conversion_1,  
            conversion_2  => conversion_2,  
            conversion_3  => conversion_3,  
            conversion_4  => conversion_4,  
 
            send_images_1 => send_images_1, 
            send_images_2 => send_images_2, 
            send_images_3 => send_images_3, 
            send_images_4 => send_images_4,
            
            low_thr_inkulevel_1       => low_thr_inkulevel_1,      
            low_thr_inkulevel_2       => low_thr_inkulevel_2,      
            low_thr_inkulevel_3       => low_thr_inkulevel_3,      
            low_thr_inkulevel_4       => low_thr_inkulevel_4,
             
            high_thr_inkulevel_1      => high_thr_inkulevel_1,     
            high_thr_inkulevel_2      => high_thr_inkulevel_2,     
            high_thr_inkulevel_3      => high_thr_inkulevel_3,     
            high_thr_inkulevel_4      => high_thr_inkulevel_4,   
             
            intensity_thr_inkulevel_1 => intensity_thr_inkulevel_1,
            intensity_thr_inkulevel_2 => intensity_thr_inkulevel_2,
            intensity_thr_inkulevel_3 => intensity_thr_inkulevel_3,
            intensity_thr_inkulevel_4 => intensity_thr_inkulevel_4,
            
            inkulevel_command_11_1 => inkulevel_command_11_1,
            inkulevel_command_11_2 => inkulevel_command_11_2,
            inkulevel_command_11_3 => inkulevel_command_11_3,
            inkulevel_command_11_4 => inkulevel_command_11_4,
            inkulevel_command_12_1 => inkulevel_command_12_1,
            inkulevel_command_12_2 => inkulevel_command_12_2,
            inkulevel_command_12_3 => inkulevel_command_12_3,
            inkulevel_command_12_4 => inkulevel_command_12_4,
            inkulevel_command_13_1 => inkulevel_command_13_1,
            inkulevel_command_13_2 => inkulevel_command_13_2,
            inkulevel_command_13_3 => inkulevel_command_13_3,
            inkulevel_command_13_4 => inkulevel_command_13_4,
            inkulevel_command_14_1 => inkulevel_command_14_1,
            inkulevel_command_14_2 => inkulevel_command_14_2,
            inkulevel_command_14_3 => inkulevel_command_14_3,
            inkulevel_command_14_4 => inkulevel_command_14_4,
            inkulevel_command_15_1 => inkulevel_command_15_1,
            inkulevel_command_15_2 => inkulevel_command_15_2,
            inkulevel_command_15_3 => inkulevel_command_15_3,
            inkulevel_command_15_4 => inkulevel_command_15_4,
            
            assign_order  => assign_order,
            debug_sig     => debug_sig(4 downto 1)
        );
        
    level_out_1(15 downto  0) <= level_1_buf;
    level_out_2(15 downto  0) <= level_2_buf;
    level_out_3(15 downto  0) <= level_3_buf;
    level_out_4(15 downto  0) <= level_4_buf;
    level_out_1(31 downto 16) <= ctr_1;
    level_out_2(31 downto 16) <= ctr_2;
    level_out_3(31 downto 16) <= ctr_3;
    level_out_4(31 downto 16) <= ctr_4;
    
    valid_1 <= valid_1_buf;
    valid_2 <= valid_2_buf;
    valid_3 <= valid_3_buf;
    valid_4 <= valid_4_buf;
    
	-- User logic ends

end arch_imp;
