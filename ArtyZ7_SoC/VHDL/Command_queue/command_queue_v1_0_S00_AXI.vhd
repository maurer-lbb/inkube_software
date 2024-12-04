-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity command_queue_v1_0_S00_AXI is
	generic (
		-- Users to add parameters here

		-- User parameters ends
		-- Do not modify the parameters beyond this line

		-- Width of S_AXI data bus
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		-- Width of S_AXI address bus
		C_S_AXI_ADDR_WIDTH	: integer	:= 9
	);
	port (
		-- Users to add ports here
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
		-- User ports ends
		-- Do not modify the ports beyond this line

		-- Global Clock Signal
		S_AXI_ACLK	: in std_logic;
		-- Global Reset Signal. This Signal is Active LOW
		S_AXI_ARESETN	: in std_logic;
		-- Write address (issued by master, acceped by Slave)
		S_AXI_AWADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		-- Write channel Protection type. This signal indicates the
    		-- privilege and security level of the transaction, and whether
    		-- the transaction is a data access or an instruction access.
		S_AXI_AWPROT	: in std_logic_vector(2 downto 0);
		-- Write address valid. This signal indicates that the master signaling
    		-- valid write address and control information.
		S_AXI_AWVALID	: in std_logic;
		-- Write address ready. This signal indicates that the slave is ready
    		-- to accept an address and associated control signals.
		S_AXI_AWREADY	: out std_logic;
		-- Write data (issued by master, acceped by Slave) 
		S_AXI_WDATA	: in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		-- Write strobes. This signal indicates which byte lanes hold
    		-- valid data. There is one write strobe bit for each eight
    		-- bits of the write data bus.    
		S_AXI_WSTRB	: in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
		-- Write valid. This signal indicates that valid write
    		-- data and strobes are available.
		S_AXI_WVALID	: in std_logic;
		-- Write ready. This signal indicates that the slave
    		-- can accept the write data.
		S_AXI_WREADY	: out std_logic;
		-- Write response. This signal indicates the status
    		-- of the write transaction.
		S_AXI_BRESP	: out std_logic_vector(1 downto 0);
		-- Write response valid. This signal indicates that the channel
    		-- is signaling a valid write response.
		S_AXI_BVALID	: out std_logic;
		-- Response ready. This signal indicates that the master
    		-- can accept a write response.
		S_AXI_BREADY	: in std_logic;
		-- Read address (issued by master, acceped by Slave)
		S_AXI_ARADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
		-- Protection type. This signal indicates the privilege
    		-- and security level of the transaction, and whether the
    		-- transaction is a data access or an instruction access.
		S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
		-- Read address valid. This signal indicates that the channel
    		-- is signaling valid read address and control information.
		S_AXI_ARVALID	: in std_logic;
		-- Read address ready. This signal indicates that the slave is
    		-- ready to accept an address and associated control signals.
		S_AXI_ARREADY	: out std_logic;
		-- Read data (issued by slave)
		S_AXI_RDATA	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
		-- Read response. This signal indicates the status of the
    		-- read transfer.
		S_AXI_RRESP	: out std_logic_vector(1 downto 0);
		-- Read valid. This signal indicates that the channel is
    		-- signaling the required read data.
		S_AXI_RVALID	: out std_logic;
		-- Read ready. This signal indicates that the master can
    		-- accept the read data and response information.
		S_AXI_RREADY	: in std_logic
	);
end command_queue_v1_0_S00_AXI;

architecture arch_imp of command_queue_v1_0_S00_AXI is

    
  component lfifo_wrapper is
      port (
            clk_100MHz : in STD_LOGIC;
            data_in    : in STD_LOGIC_VECTOR ( 2079 downto 0 );
            data_out_0 : out STD_LOGIC_VECTOR ( 31 downto 0 );
            data_out_1 : out STD_LOGIC_VECTOR ( 511 downto 0 );
            data_out_2 : out STD_LOGIC_VECTOR ( 511 downto 0 );
            data_out_3 : out STD_LOGIC_VECTOR ( 511 downto 0 );
            data_out_4 : out STD_LOGIC_VECTOR ( 511 downto 0 );
            empty      : out STD_LOGIC_VECTOR ( 4 downto 0 );
            full       : out STD_LOGIC_VECTOR ( 4 downto 0 );
            rd_en      : in STD_LOGIC;
            reset_n    : in STD_LOGIC_VECTOR ( 0 to 0 );
            wr_en      : in STD_LOGIC
      );
    end component lfifo_wrapper;
    
    signal command_1_11 : std_logic_vector(31 downto 0);
    signal command_2_11 : std_logic_vector(31 downto 0);
    signal command_3_11 : std_logic_vector(31 downto 0);
    signal command_4_11 : std_logic_vector(31 downto 0);
    signal command_1_12 : std_logic_vector(31 downto 0);
    signal command_2_12 : std_logic_vector(31 downto 0);
    signal command_3_12 : std_logic_vector(31 downto 0);
    signal command_4_12 : std_logic_vector(31 downto 0);
    signal command_1_13 : std_logic_vector(31 downto 0);
    signal command_2_13 : std_logic_vector(31 downto 0);
    signal command_3_13 : std_logic_vector(31 downto 0);
    signal command_4_13 : std_logic_vector(31 downto 0);
    signal command_1_14 : std_logic_vector(31 downto 0);
    signal command_2_14 : std_logic_vector(31 downto 0);
    signal command_3_14 : std_logic_vector(31 downto 0);
    signal command_4_14 : std_logic_vector(31 downto 0);
    signal command_1_21 : std_logic_vector(31 downto 0);
    signal command_2_21 : std_logic_vector(31 downto 0);
    signal command_3_21 : std_logic_vector(31 downto 0);
    signal command_4_21 : std_logic_vector(31 downto 0);
    signal command_1_22 : std_logic_vector(31 downto 0);
    signal command_2_22 : std_logic_vector(31 downto 0);
    signal command_3_22 : std_logic_vector(31 downto 0);
    signal command_4_22 : std_logic_vector(31 downto 0);
    signal command_1_23 : std_logic_vector(31 downto 0);
    signal command_2_23 : std_logic_vector(31 downto 0);
    signal command_3_23 : std_logic_vector(31 downto 0);
    signal command_4_23 : std_logic_vector(31 downto 0);
    signal command_1_24 : std_logic_vector(31 downto 0);
    signal command_2_24 : std_logic_vector(31 downto 0);
    signal command_3_24 : std_logic_vector(31 downto 0);
    signal command_4_24 : std_logic_vector(31 downto 0);
    signal command_1_31 : std_logic_vector(31 downto 0);
    signal command_2_31 : std_logic_vector(31 downto 0);
    signal command_3_31 : std_logic_vector(31 downto 0);
    signal command_4_31 : std_logic_vector(31 downto 0);
    signal command_1_32 : std_logic_vector(31 downto 0);
    signal command_2_32 : std_logic_vector(31 downto 0);
    signal command_3_32 : std_logic_vector(31 downto 0);
    signal command_4_32 : std_logic_vector(31 downto 0);
    signal command_1_33 : std_logic_vector(31 downto 0);
    signal command_2_33 : std_logic_vector(31 downto 0);
    signal command_3_33 : std_logic_vector(31 downto 0);
    signal command_4_33 : std_logic_vector(31 downto 0);
    signal command_1_34 : std_logic_vector(31 downto 0);
    signal command_2_34 : std_logic_vector(31 downto 0);
    signal command_3_34 : std_logic_vector(31 downto 0);
    signal command_4_34 : std_logic_vector(31 downto 0);
    signal command_1_41 : std_logic_vector(31 downto 0);
    signal command_2_41 : std_logic_vector(31 downto 0);
    signal command_3_41 : std_logic_vector(31 downto 0);
    signal command_4_41 : std_logic_vector(31 downto 0);
    signal command_1_42 : std_logic_vector(31 downto 0);
    signal command_2_42 : std_logic_vector(31 downto 0);
    signal command_3_42 : std_logic_vector(31 downto 0);
    signal command_4_42 : std_logic_vector(31 downto 0);
    signal command_1_43 : std_logic_vector(31 downto 0);
    signal command_2_43 : std_logic_vector(31 downto 0);
    signal command_3_43 : std_logic_vector(31 downto 0);
    signal command_4_43 : std_logic_vector(31 downto 0);
    signal command_1_44 : std_logic_vector(31 downto 0);
    signal command_2_44 : std_logic_vector(31 downto 0);
    signal command_3_44 : std_logic_vector(31 downto 0);
    signal command_4_44 : std_logic_vector(31 downto 0);
    
    signal all_empty    : std_logic;
    signal old_word     : std_logic_vector(31 downto 0);
    
    signal data_in_buf  : std_logic_vector(2079 downto 0);
    signal data_in      : std_logic_vector(2079 downto 0);
    signal data_out     : std_logic_vector(2079 downto 0);
    signal empty        : std_logic_vector(4 downto 0);
    signal full         : std_logic_vector(4 downto 0);
    signal rd_en        : std_logic;
    signal wr_en_buf    : std_logic;
    signal wr_en        : std_logic;
    signal resetn       : std_logic_vector(0 downto 0);
    
    signal second_half  : std_logic;
    signal phase_ctr    : natural range 0 to 40;

	-- AXI4LITE signals
	signal axi_awaddr	: std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
	signal axi_awready	: std_logic;
	signal axi_wready	: std_logic;
	signal axi_bresp	: std_logic_vector(1 downto 0);
	signal axi_bvalid	: std_logic;
	signal axi_araddr	: std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
	signal axi_arready	: std_logic;
	signal axi_rdata	: std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal axi_rresp	: std_logic_vector(1 downto 0);
	signal axi_rvalid	: std_logic;
	
	signal get_commands      : std_logic := '0';
	signal use_commands      : std_logic := '0';
	signal update_commands_1 : std_logic := '0';
	signal update_commands_2 : std_logic := '0';

	-- Example-specific design signals
	-- local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	-- ADDR_LSB is used for addressing 32/64 bit registers/memories
	-- ADDR_LSB = 2 for 32 bits (n downto 2)
	-- ADDR_LSB = 3 for 64 bits (n downto 3)
	constant ADDR_LSB  : integer := (C_S_AXI_DATA_WIDTH/32)+ 1;
	constant OPT_MEM_ADDR_BITS : integer := 6;
	------------------------------------------------
	---- Signals for user logic register space example
	--------------------------------------------------
	---- Number of Slave Registers 65
	signal slv_reg0	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg1	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg2	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg3	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg4	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg5	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg6	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg7	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg8	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg9	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg10	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg11	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg12	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg13	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg14	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg15	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg16	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg17	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg18	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg19	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg20	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg21	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg22	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg23	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg24	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg25	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg26	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg27	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg28	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg29	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg30	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg31	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg32	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg33	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg34	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg35	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg36	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg37	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg38	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg39	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg40	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg41	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg42	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg43	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg44	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg45	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg46	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg47	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg48	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg49	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg50	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg51	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg52	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg53	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg54	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg55	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg56	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg57	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg58	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg59	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg60	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg61	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg62	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg63	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg64	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg_rden	: std_logic;
	signal slv_reg_wren	: std_logic;
	signal reg_data_out	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal byte_index	: integer;
	signal aw_en	: std_logic;
	
	signal package_loss_signal : std_logic;
	
	signal package_ctr_rd    : natural range 0 to 255 := 0;
	signal package_ctr_wr    : natural range 0 to 255 := 0;
	signal package_ctr_word  : integer range 0 to 1562500 := 0;
	
	signal data_out_last_2        : std_logic := '0';
	signal data_out_count_2       : std_logic_vector(31 downto 0) := (others => '0');
	signal data_out_last_1        : std_logic := '0';
	signal data_out_count_1       : std_logic_vector(31 downto 0) := (others => '0');
	signal data_out_last          : std_logic := '0';
	signal data_out_count         : std_logic_vector(31 downto 0) := (others => '0');
	
	signal data_out_unsigned      : unsigned(31 downto 0) := to_unsigned(0,32);
	signal package_count_unsigned : unsigned(31 downto 0) := to_unsigned(0,32);
	signal data_out_sim           : unsigned(31 downto 0) := to_unsigned(1562500,32);
	signal data_out_sim_mod       : unsigned(31 downto 0) := to_unsigned(1562500,32);

begin
	-- I/O Connections assignments

	S_AXI_AWREADY	<= axi_awready;
	S_AXI_WREADY	<= axi_wready;
	S_AXI_BRESP	<= axi_bresp;
	S_AXI_BVALID	<= axi_bvalid;
	S_AXI_ARREADY	<= axi_arready;
	S_AXI_RDATA	<= axi_rdata;
	S_AXI_RRESP	<= axi_rresp;
	S_AXI_RVALID	<= axi_rvalid;
	-- Implement axi_awready generation
	-- axi_awready is asserted for one S_AXI_ACLK clock cycle when both
	-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_awready is
	-- de-asserted when reset is low.

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_awready <= '0';
	      aw_en <= '1';
	    else
	      if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' and aw_en = '1') then
	        -- slave is ready to accept write address when
	        -- there is a valid write address and write data
	        -- on the write address and data bus. This design 
	        -- expects no outstanding transactions. 
	           axi_awready <= '1';
	           aw_en <= '0';
	        elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then
	           aw_en <= '1';
	           axi_awready <= '0';
	      else
	        axi_awready <= '0';
	      end if;
	    end if;
	  end if;
	end process;

	-- Implement axi_awaddr latching
	-- This process is used to latch the address when both 
	-- S_AXI_AWVALID and S_AXI_WVALID are valid. 

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_awaddr <= (others => '0');
	    else
	      if (axi_awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' and aw_en = '1') then
	        -- Write Address latching
	        axi_awaddr <= S_AXI_AWADDR;
	      end if;
	    end if;
	  end if;                   
	end process; 

	-- Implement axi_wready generation
	-- axi_wready is asserted for one S_AXI_ACLK clock cycle when both
	-- S_AXI_AWVALID and S_AXI_WVALID are asserted. axi_wready is 
	-- de-asserted when reset is low. 

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_wready <= '0';
	    else
	      if (axi_wready = '0' and S_AXI_WVALID = '1' and S_AXI_AWVALID = '1' and aw_en = '1') then
	          -- slave is ready to accept write data when 
	          -- there is a valid write address and write data
	          -- on the write address and data bus. This design 
	          -- expects no outstanding transactions.           
	          axi_wready <= '1';
	      else
	        axi_wready <= '0';
	      end if;
	    end if;
	  end if;
	end process; 

	-- Implement memory mapped register select and write logic generation
	-- The write data is accepted and written to memory mapped registers when
	-- axi_awready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted. Write strobes are used to
	-- select byte enables of slave registers while writing.
	-- These registers are cleared when reset (active low) is applied.
	-- Slave register write enable is asserted when valid address and data are available
	-- and the slave is ready to accept the write address and write data.
	slv_reg_wren <= axi_wready and S_AXI_WVALID and axi_awready and S_AXI_AWVALID ;

	process (S_AXI_ACLK)
	variable loc_addr : std_logic_vector(OPT_MEM_ADDR_BITS downto 0); 
	variable i        : natural range 0 to 2080;
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      package_ctr_wr <= 0;
	      slv_reg0    <= (others => '0');
	      slv_reg1    <= (others => '0');
	      slv_reg2    <= (others => '0');
	      slv_reg3    <= (others => '0');
	      slv_reg4    <= (others => '0');
	      slv_reg5    <= (others => '0');
	      slv_reg6    <= (others => '0');
	      slv_reg7    <= (others => '0');
	      slv_reg8    <= (others => '0');
	      slv_reg9    <= (others => '0');
	      slv_reg10   <= (others => '0');
	      slv_reg11   <= (others => '0');
	      slv_reg12   <= (others => '0');
	      slv_reg13   <= (others => '0');
	      slv_reg14   <= (others => '0');
	      slv_reg15   <= (others => '0');
	      slv_reg16   <= (others => '0');
	      slv_reg17   <= (others => '0');
	      slv_reg18   <= (others => '0');
	      slv_reg19   <= (others => '0');
	      slv_reg20   <= (others => '0');
	      slv_reg21   <= (others => '0');
	      slv_reg22   <= (others => '0');
	      slv_reg23   <= (others => '0');
	      slv_reg24   <= (others => '0');
	      slv_reg25   <= (others => '0');
	      slv_reg26   <= (others => '0');
	      slv_reg27   <= (others => '0');
	      slv_reg28   <= (others => '0');
	      slv_reg29   <= (others => '0');
	      slv_reg30   <= (others => '0');
	      slv_reg31   <= (others => '0');
	      slv_reg32   <= (others => '0');
	      slv_reg33   <= (others => '0');
	      slv_reg34   <= (others => '0');
	      slv_reg35   <= (others => '0');
	      slv_reg36   <= (others => '0');
	      slv_reg37   <= (others => '0');
	      slv_reg38   <= (others => '0');
	      slv_reg39   <= (others => '0');
	      slv_reg40   <= (others => '0');
	      slv_reg41   <= (others => '0');
	      slv_reg42   <= (others => '0');
	      slv_reg43   <= (others => '0');
	      slv_reg44   <= (others => '0');
	      slv_reg45   <= (others => '0');
	      slv_reg46   <= (others => '0');
	      slv_reg47   <= (others => '0');
	      slv_reg48   <= (others => '0');
	      slv_reg49   <= (others => '0');
	      slv_reg50   <= (others => '0');
	      slv_reg51   <= (others => '0');
	      slv_reg52   <= (others => '0');
	      slv_reg53   <= (others => '0');
	      slv_reg54   <= (others => '0');
	      slv_reg55   <= (others => '0');
	      slv_reg56   <= (others => '0');
	      slv_reg57   <= (others => '0');
	      slv_reg58   <= (others => '0');
	      slv_reg59   <= (others => '0');
	      slv_reg60   <= (others => '0');
	      slv_reg61   <= (others => '0');
	      slv_reg62   <= (others => '0');
	      slv_reg63   <= (others => '0');
	      slv_reg64   <= (others => '0');
	      data_in_buf <= (others => '0');
	      wr_en_buf   <= '0';
	    else
	      loc_addr := axi_awaddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);
	      wr_en_buf <= '0';
	      
	      if (slv_reg_wren = '1') then
	        -- This part akes sure we also load the data into data_in(_buf)
	        if (unsigned(loc_addr) <= 64) then
	          for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	             if ( S_AXI_WSTRB(byte_index) = '1' ) then
	               i := byte_index*8+to_integer(unsigned(loc_addr))*32;
	               data_in_buf((i+7) downto i) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	             end if;
	           end loop;
	        end if;
	        
	        case loc_addr is
	          when b"0000000" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 0
	                slv_reg0(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0000001" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 1
	                slv_reg1(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0000010" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 2
	                slv_reg2(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0000011" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 3
	                slv_reg3(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0000100" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 4
	                slv_reg4(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0000101" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 5
	                slv_reg5(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0000110" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 6
	                slv_reg6(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0000111" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 7
	                slv_reg7(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0001000" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 8
	                slv_reg8(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0001001" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 9
	                slv_reg9(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0001010" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 10
	                slv_reg10(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0001011" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 11
	                slv_reg11(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0001100" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 12
	                slv_reg12(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0001101" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 13
	                slv_reg13(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0001110" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 14
	                slv_reg14(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0001111" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 15
	                slv_reg15(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0010000" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 16
	                slv_reg16(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0010001" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 17
	                slv_reg17(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0010010" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 18
	                slv_reg18(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0010011" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 19
	                slv_reg19(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0010100" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 20
	                slv_reg20(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0010101" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 21
	                slv_reg21(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0010110" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 22
	                slv_reg22(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0010111" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 23
	                slv_reg23(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0011000" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 24
	                slv_reg24(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0011001" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 25
	                slv_reg25(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0011010" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 26
	                slv_reg26(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0011011" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 27
	                slv_reg27(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0011100" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 28
	                slv_reg28(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0011101" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 29
	                slv_reg29(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0011110" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 30
	                slv_reg30(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0011111" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 31
	                slv_reg31(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0100000" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 32
	                slv_reg32(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0100001" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 33
	                slv_reg33(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0100010" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 34
	                slv_reg34(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0100011" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 35
	                slv_reg35(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0100100" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 36
	                slv_reg36(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0100101" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 37
	                slv_reg37(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0100110" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 38
	                slv_reg38(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0100111" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 39
	                slv_reg39(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0101000" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 40
	                slv_reg40(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0101001" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 41
	                slv_reg41(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0101010" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 42
	                slv_reg42(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0101011" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 43
	                slv_reg43(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0101100" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 44
	                slv_reg44(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0101101" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 45
	                slv_reg45(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0101110" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 46
	                slv_reg46(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0101111" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 47
	                slv_reg47(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0110000" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 48
	                slv_reg48(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0110001" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 49
	                slv_reg49(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0110010" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 50
	                slv_reg50(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0110011" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 51
	                slv_reg51(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0110100" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 52
	                slv_reg52(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0110101" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 53
	                slv_reg53(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0110110" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 54
	                slv_reg54(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0110111" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 55
	                slv_reg55(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0111000" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 56
	                slv_reg56(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0111001" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 57
	                slv_reg57(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0111010" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 58
	                slv_reg58(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0111011" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 59
	                slv_reg59(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0111100" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 60
	                slv_reg60(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0111101" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 61
	                slv_reg61(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0111110" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 62
	                slv_reg62(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"0111111" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 63
	                slv_reg63(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"1000000" =>
	            wr_en_buf <= '1'; -- This is the (only) time, where the whole data sample is written into the FIFO
	            package_ctr_wr <= package_ctr_wr + 1;
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 64
	                slv_reg64(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when others =>
	            slv_reg0 <= slv_reg0;
	            slv_reg1 <= slv_reg1;
	            slv_reg2 <= slv_reg2;
	            slv_reg3 <= slv_reg3;
	            slv_reg4 <= slv_reg4;
	            slv_reg5 <= slv_reg5;
	            slv_reg6 <= slv_reg6;
	            slv_reg7 <= slv_reg7;
	            slv_reg8 <= slv_reg8;
	            slv_reg9 <= slv_reg9;
	            slv_reg10 <= slv_reg10;
	            slv_reg11 <= slv_reg11;
	            slv_reg12 <= slv_reg12;
	            slv_reg13 <= slv_reg13;
	            slv_reg14 <= slv_reg14;
	            slv_reg15 <= slv_reg15;
	            slv_reg16 <= slv_reg16;
	            slv_reg17 <= slv_reg17;
	            slv_reg18 <= slv_reg18;
	            slv_reg19 <= slv_reg19;
	            slv_reg20 <= slv_reg20;
	            slv_reg21 <= slv_reg21;
	            slv_reg22 <= slv_reg22;
	            slv_reg23 <= slv_reg23;
	            slv_reg24 <= slv_reg24;
	            slv_reg25 <= slv_reg25;
	            slv_reg26 <= slv_reg26;
	            slv_reg27 <= slv_reg27;
	            slv_reg28 <= slv_reg28;
	            slv_reg29 <= slv_reg29;
	            slv_reg30 <= slv_reg30;
	            slv_reg31 <= slv_reg31;
	            slv_reg32 <= slv_reg32;
	            slv_reg33 <= slv_reg33;
	            slv_reg34 <= slv_reg34;
	            slv_reg35 <= slv_reg35;
	            slv_reg36 <= slv_reg36;
	            slv_reg37 <= slv_reg37;
	            slv_reg38 <= slv_reg38;
	            slv_reg39 <= slv_reg39;
	            slv_reg40 <= slv_reg40;
	            slv_reg41 <= slv_reg41;
	            slv_reg42 <= slv_reg42;
	            slv_reg43 <= slv_reg43;
	            slv_reg44 <= slv_reg44;
	            slv_reg45 <= slv_reg45;
	            slv_reg46 <= slv_reg46;
	            slv_reg47 <= slv_reg47;
	            slv_reg48 <= slv_reg48;
	            slv_reg49 <= slv_reg49;
	            slv_reg50 <= slv_reg50;
	            slv_reg51 <= slv_reg51;
	            slv_reg52 <= slv_reg52;
	            slv_reg53 <= slv_reg53;
	            slv_reg54 <= slv_reg54;
	            slv_reg55 <= slv_reg55;
	            slv_reg56 <= slv_reg56;
	            slv_reg57 <= slv_reg57;
	            slv_reg58 <= slv_reg58;
	            slv_reg59 <= slv_reg59;
	            slv_reg60 <= slv_reg60;
	            slv_reg61 <= slv_reg61;
	            slv_reg62 <= slv_reg62;
	            slv_reg63 <= slv_reg63;
	            slv_reg64 <= slv_reg64;
	        end case;
	      end if;
	    end if;
	  end if;                   
	end process; 

	-- Implement write response logic generation
	-- The write response and response valid signals are asserted by the slave 
	-- when axi_wready, S_AXI_WVALID, axi_wready and S_AXI_WVALID are asserted.  
	-- This marks the acceptance of address and indicates the status of 
	-- write transaction.

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_bvalid  <= '0';
	      axi_bresp   <= "00";                                   -- need to work more on the responses
	    else
	      if (axi_awready = '1' and S_AXI_AWVALID = '1' and axi_wready = '1' and S_AXI_WVALID = '1' and axi_bvalid = '0'  ) then
	        axi_bvalid <= '1';
	        axi_bresp  <= "00"; 
	      elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then   -- check if bready is asserted while bvalid is high)
	        axi_bvalid <= '0';                                   -- (there is a possibility that bready is always asserted high)
	      end if;
	    end if;
	  end if;                   
	end process; 

	-- Implement axi_arready generation
	-- axi_arready is asserted for one S_AXI_ACLK clock cycle when
	-- S_AXI_ARVALID is asserted. axi_awready is 
	-- de-asserted when reset (active low) is asserted. 
	-- The read address is also latched when S_AXI_ARVALID is 
	-- asserted. axi_araddr is reset to zero on reset assertion.

	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    if S_AXI_ARESETN = '0' then
	      axi_arready <= '0';
	      axi_araddr  <= (others => '1');
	    else
	      if (axi_arready = '0' and S_AXI_ARVALID = '1') then
	        -- indicates that the slave has acceped the valid read address
	        axi_arready <= '1';
	        -- Read Address latching 
	        axi_araddr  <= S_AXI_ARADDR;           
	      else
	        axi_arready <= '0';
	      end if;
	    end if;
	  end if;                   
	end process; 

	-- Implement axi_arvalid generation
	-- axi_rvalid is asserted for one S_AXI_ACLK clock cycle when both 
	-- S_AXI_ARVALID and axi_arready are asserted. The slave registers 
	-- data are available on the axi_rdata bus at this instance. The 
	-- assertion of axi_rvalid marks the validity of read data on the 
	-- bus and axi_rresp indicates the status of read transaction.axi_rvalid 
	-- is deasserted on reset (active low). axi_rresp and axi_rdata are 
	-- cleared to zero on reset (active low).  
	process (S_AXI_ACLK)
	begin
	  if rising_edge(S_AXI_ACLK) then
	    if S_AXI_ARESETN = '0' then
	      axi_rvalid <= '0';
	      axi_rresp  <= "00";
	    else
	      if (axi_arready = '1' and S_AXI_ARVALID = '1' and axi_rvalid = '0') then
	        -- Valid read data is available at the read data bus
	        axi_rvalid <= '1';
	        axi_rresp  <= "00"; -- 'OKAY' response
	      elsif (axi_rvalid = '1' and S_AXI_RREADY = '1') then
	        -- Read data is accepted by the master
	        axi_rvalid <= '0';
	      end if;            
	    end if;
	  end if;
	end process;

	-- Implement memory mapped register select and read logic generation
	-- Slave register read enable is asserted when valid address is available
	-- and the slave is ready to accept the read address.
	slv_reg_rden <= axi_arready and S_AXI_ARVALID and (not axi_rvalid) ;

	process (slv_reg0, slv_reg1, slv_reg2, slv_reg3, slv_reg4, slv_reg5, slv_reg6, slv_reg7, slv_reg8, slv_reg9, slv_reg10, slv_reg11, slv_reg12, slv_reg13, slv_reg14, slv_reg15, slv_reg16, slv_reg17, slv_reg18, slv_reg19, slv_reg20, slv_reg21, slv_reg22, slv_reg23, slv_reg24, slv_reg25, slv_reg26, slv_reg27, slv_reg28, slv_reg29, slv_reg30, slv_reg31, slv_reg32, slv_reg33, slv_reg34, slv_reg35, slv_reg36, slv_reg37, slv_reg38, slv_reg39, slv_reg40, slv_reg41, slv_reg42, slv_reg43, slv_reg44, slv_reg45, slv_reg46, slv_reg47, slv_reg48, slv_reg49, slv_reg50, slv_reg51, slv_reg52, slv_reg53, slv_reg54, slv_reg55, slv_reg56, slv_reg57, slv_reg58, slv_reg59, slv_reg60, slv_reg61, slv_reg62, slv_reg63, slv_reg64, axi_araddr, S_AXI_ARESETN, slv_reg_rden)
	variable loc_addr :std_logic_vector(OPT_MEM_ADDR_BITS downto 0);
	begin
	    -- Address decoding for reading registers
	    loc_addr := axi_araddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);
	    case loc_addr is
	      when b"0000000" =>
	        reg_data_out(4  downto 0) <= full;
	        reg_data_out(31 downto 5) <= (others => '0');
	        -- reg_data_out <= slv_reg0;
	      when b"0000001" =>
	        reg_data_out(4  downto 0) <= empty;
	        reg_data_out(31 downto 5) <= (others => '0');
	        -- reg_data_out <= slv_reg1;
	      when b"0000010" =>
	        reg_data_out <= std_logic_vector(to_unsigned(package_ctr_wr,32));
	        -- reg_data_out <= slv_reg2;
	      when b"0000011" =>
	        reg_data_out <= std_logic_vector(to_unsigned(package_ctr_rd,32));
	        -- reg_data_out <= slv_reg3;
	      when b"0000100" =>
	        reg_data_out <= std_logic_vector(to_unsigned(package_ctr_word,32));
	        -- reg_data_out <= slv_reg4;
	      when b"0000101" =>
	        reg_data_out <= package_count;
	        -- reg_data_out <= slv_reg5;
	      when b"0000110" =>
	        reg_data_out <= slv_reg6;
	      when b"0000111" =>
	        reg_data_out <= slv_reg7;
	      when b"0001000" =>
	        reg_data_out <= slv_reg8;
	      when b"0001001" =>
	        reg_data_out <= slv_reg9;
	      when b"0001010" =>
	        reg_data_out <= slv_reg10;
	      when b"0001011" =>
	        reg_data_out <= slv_reg11;
	      when b"0001100" =>
	        reg_data_out <= slv_reg12;
	      when b"0001101" =>
	        reg_data_out <= slv_reg13;
	      when b"0001110" =>
	        reg_data_out <= slv_reg14;
	      when b"0001111" =>
	        reg_data_out <= slv_reg15;
	      when b"0010000" =>
	        reg_data_out <= slv_reg16;
	      when b"0010001" =>
	        reg_data_out <= slv_reg17;
	      when b"0010010" =>
	        reg_data_out <= slv_reg18;
	      when b"0010011" =>
	        reg_data_out <= slv_reg19;
	      when b"0010100" =>
	        reg_data_out <= slv_reg20;
	      when b"0010101" =>
	        reg_data_out <= slv_reg21;
	      when b"0010110" =>
	        reg_data_out <= slv_reg22;
	      when b"0010111" =>
	        reg_data_out <= slv_reg23;
	      when b"0011000" =>
	        reg_data_out <= slv_reg24;
	      when b"0011001" =>
	        reg_data_out <= slv_reg25;
	      when b"0011010" =>
	        reg_data_out <= slv_reg26;
	      when b"0011011" =>
	        reg_data_out <= slv_reg27;
	      when b"0011100" =>
	        reg_data_out <= slv_reg28;
	      when b"0011101" =>
	        reg_data_out <= slv_reg29;
	      when b"0011110" =>
	        reg_data_out <= slv_reg30;
	      when b"0011111" =>
	        reg_data_out <= slv_reg31;
	      when b"0100000" =>
	        reg_data_out <= slv_reg32;
	      when b"0100001" =>
	        reg_data_out <= slv_reg33;
	      when b"0100010" =>
	        reg_data_out <= slv_reg34;
	      when b"0100011" =>
	        reg_data_out <= slv_reg35;
	      when b"0100100" =>
	        reg_data_out <= slv_reg36;
	      when b"0100101" =>
	        reg_data_out <= slv_reg37;
	      when b"0100110" =>
	        reg_data_out <= slv_reg38;
	      when b"0100111" =>
	        reg_data_out <= slv_reg39;
	      when b"0101000" =>
	        reg_data_out <= slv_reg40;
	      when b"0101001" =>
	        reg_data_out <= slv_reg41;
	      when b"0101010" =>
	        reg_data_out <= slv_reg42;
	      when b"0101011" =>
	        reg_data_out <= slv_reg43;
	      when b"0101100" =>
	        reg_data_out <= slv_reg44;
	      when b"0101101" =>
	        reg_data_out <= slv_reg45;
	      when b"0101110" =>
	        reg_data_out <= slv_reg46;
	      when b"0101111" =>
	        reg_data_out <= slv_reg47;
	      when b"0110000" =>
	        reg_data_out <= slv_reg48;
	      when b"0110001" =>
	        reg_data_out <= slv_reg49;
	      when b"0110010" =>
	        reg_data_out <= slv_reg50;
	      when b"0110011" =>
	        reg_data_out <= slv_reg51;
	      when b"0110100" =>
	        reg_data_out <= slv_reg52;
	      when b"0110101" =>
	        reg_data_out <= slv_reg53;
	      when b"0110110" =>
	        reg_data_out <= slv_reg54;
	      when b"0110111" =>
	        reg_data_out <= slv_reg55;
	      when b"0111000" =>
	        reg_data_out <= slv_reg56;
	      when b"0111001" =>
	        reg_data_out <= slv_reg57;
	      when b"0111010" =>
	        reg_data_out <= slv_reg58;
	      when b"0111011" =>
	        reg_data_out <= slv_reg59;
	      when b"0111100" =>
	        reg_data_out <= slv_reg60;
	      when b"0111101" =>
	        reg_data_out <= slv_reg61;
	      when b"0111110" =>
	        reg_data_out <= slv_reg62;
	      when b"0111111" =>
	        reg_data_out <= slv_reg63;
	      when b"1000000" =>
	        reg_data_out <= slv_reg64;
	      when others =>
	        reg_data_out  <= (others => '0');
	    end case;
	end process; 

	-- Output register or memory read data
	process( S_AXI_ACLK ) is
	begin
	  if (rising_edge (S_AXI_ACLK)) then
	    if ( S_AXI_ARESETN = '0' ) then
	      axi_rdata  <= (others => '0');
	    else
	      if (slv_reg_rden = '1') then
	        -- When there is a valid read address (S_AXI_ARVALID) with 
	        -- acceptance of read address by the slave (axi_arready), 
	        -- output the read dada 
	        -- Read address mux
	          axi_rdata <= reg_data_out;     -- register read data
	      end if;   
	    end if;
	  end if;
	end process;


	-- Add user logic here
	
	large_fifo : lfifo_wrapper
	port map (
	   clk_100MHz => S_AXI_ACLK,
	   data_in    => data_in   ,
       data_out_0 => data_out(2079 downto 2048),
       data_out_1 => data_out(2047 downto 1536),
       data_out_2 => data_out(1535 downto 1024),
       data_out_3 => data_out(1023 downto  512),
       data_out_4 => data_out( 511 downto    0),
	   empty      => empty     ,
	   full       => full      ,
	   rd_en      => rd_en     ,
	   reset_n    => resetn    ,
	   wr_en      => wr_en     
	);
	resetn(0) <= S_AXI_ARESETN;
	
	-- Choosing what the commands are that are send to the device
	process( S_AXI_ACLK ) is
	begin
	  if (rising_edge (S_AXI_ACLK)) then
	    old_word            <= word_count;
	    update_commands_1   <= '0';
	    if ( S_AXI_ARESETN = '0' ) then
	      package_ctr_word <= to_integer(unsigned(package_count));
	      phase_ctr    <= 0;
	    else
	      if ((word_count = "00000000000000000000000000000000") and (word_count /= old_word)) then
	        package_ctr_word <= package_ctr_word + 1;
	        update_commands_1 <= '1';
	        phase_ctr <= 0;
	      else
	        phase_ctr <= phase_ctr + 1; 
	      end if; 
	    end if;
	  end if;
	end process;
	
	process( S_AXI_ACLK ) is
	begin
	  if (rising_edge (S_AXI_ACLK)) then
	    data_out_last_2        <= data_out(2079);                                       -- 1
	    data_out_count_2       <= data_out(2079 downto 2048);                           -- 1 
	    data_out_last_1        <= data_out_last_2;                                      -- 2
	    data_out_count_1       <= data_out_count_2;                                     -- 2
	    data_out_last          <= data_out_last_1;                                      -- 3
	    data_out_count         <= data_out_count_1;                                     -- 3
	    
	    data_out_unsigned      <= unsigned(data_out(2079 downto 2048));                 -- 1
	    package_count_unsigned <= unsigned(package_count);                              -- 1
	    data_out_sim           <= 1562500 + data_out_unsigned - package_count_unsigned; -- 2
	    if data_out_sim >= 1562500*2 then
	       data_out_sim_mod <= data_out_sim - 1562500*2;
	    elsif data_out_sim >= 1562500*1 then
	       data_out_sim_mod <= data_out_sim - 1562500*1;
	    else
	       data_out_sim_mod <= data_out_sim;
	    end if;
	    -- data_out_sim_mod       <= data_out_sim mod 1562500;                             -- 3
	  end if;
    end process;
	
	process( S_AXI_ACLK ) is
	begin
	  if (rising_edge (S_AXI_ACLK)) then
	    get_commands        <= '0';
	    use_commands        <= '0';
	    update_commands_2   <= '0';
	    package_loss_signal <= '0';
	    if update_commands_1 = '1' then
	      update_commands_2   <= '1';
	      if ((all_empty = '0') and ((data_out_count = package_count) or (data_out_last = '1'))) then
	        package_ctr_rd <= package_ctr_rd + 1;
	        get_commands <= '1';
	        use_commands <= '1';
	      elsif ((all_empty = '0') and (data_out_sim_mod > 781250)) then
	        package_loss_signal <= '1';
	        get_commands <= '1';
	        use_commands <= '0';
	      else
	        get_commands <= '0';
	        use_commands <= '0';
	      end if; 
	    end if;
        if ( S_AXI_ARESETN = '0' ) then
            package_ctr_rd <= 0;
        end if;
	  end if;
	end process;
	
	-- Choosing what the commands are that are send to the device
	process( S_AXI_ACLK ) is
	begin
	  if (rising_edge (S_AXI_ACLK)) then
	    rd_en <= '0';
	    if ( S_AXI_ARESETN = '0' ) then
	      command_1_11 <= "11000000111111110000000000000000";
	      command_2_11 <= "11000000111111110000000000000000";
	      command_3_11 <= "11000000111111110000000000000000";
	      command_4_11 <= "11000000111111110000000000000000";
	      command_1_12 <= "11000000111111110000000000000000";
	      command_2_12 <= "11000000111111110000000000000000";
	      command_3_12 <= "11000000111111110000000000000000";
	      command_4_12 <= "11000000111111110000000000000000";
	      command_1_13 <= "11000000111111110000000000000000";
	      command_2_13 <= "11000000111111110000000000000000";
	      command_3_13 <= "11000000111111110000000000000000";
	      command_4_13 <= "11000000111111110000000000000000";
	      command_1_14 <= "11000000111111110000000000000000";
	      command_2_14 <= "11000000111111110000000000000000";
	      command_3_14 <= "11000000111111110000000000000000";
	      command_4_14 <= "11000000111111110000000000000000";
	      command_1_21 <= "11000000111111110000000000000000";
	      command_2_21 <= "11000000111111110000000000000000";
	      command_3_21 <= "11000000111111110000000000000000";
	      command_4_21 <= "11000000111111110000000000000000";
	      command_1_22 <= "11000000111111110000000000000000";
	      command_2_22 <= "11000000111111110000000000000000";
	      command_3_22 <= "11000000111111110000000000000000";
	      command_4_22 <= "11000000111111110000000000000000";
	      command_1_23 <= "11000000111111110000000000000000";
	      command_2_23 <= "11000000111111110000000000000000";
	      command_3_23 <= "11000000111111110000000000000000";
	      command_4_23 <= "11000000111111110000000000000000";
	      command_1_24 <= "11000000111111110000000000000000";
	      command_2_24 <= "11000000111111110000000000000000";
	      command_3_24 <= "11000000111111110000000000000000";
	      command_4_24 <= "11000000111111110000000000000000";
	      command_1_31 <= "11000000111111110000000000000000";
	      command_2_31 <= "11000000111111110000000000000000";
	      command_3_31 <= "11000000111111110000000000000000";
	      command_4_31 <= "11000000111111110000000000000000";
	      command_1_32 <= "11000000111111110000000000000000";
	      command_2_32 <= "11000000111111110000000000000000";
	      command_3_32 <= "11000000111111110000000000000000";
	      command_4_32 <= "11000000111111110000000000000000";
	      command_1_33 <= "11000000111111110000000000000000";
	      command_2_33 <= "11000000111111110000000000000000";
	      command_3_33 <= "11000000111111110000000000000000";
	      command_4_33 <= "11000000111111110000000000000000";
	      command_1_34 <= "11000000111111110000000000000000";
	      command_2_34 <= "11000000111111110000000000000000";
	      command_3_34 <= "11000000111111110000000000000000";
	      command_4_34 <= "11000000111111110000000000000000";
	      command_1_41 <= "11000000111111110000000000000000";
	      command_2_41 <= "11000000111111110000000000000000";
	      command_3_41 <= "11000000111111110000000000000000";
	      command_4_41 <= "11000000111111110000000000000000";
	      command_1_42 <= "11000000111111110000000000000000";
	      command_2_42 <= "11000000111111110000000000000000";
	      command_3_42 <= "11000000111111110000000000000000";
	      command_4_42 <= "11000000111111110000000000000000";
	      command_1_43 <= "11000000111111110000000000000000";
	      command_2_43 <= "11000000111111110000000000000000";
	      command_3_43 <= "11000000111111110000000000000000";
	      command_4_43 <= "11000000111111110000000000000000";
	      command_1_44 <= "11000000111111110000000000000000";
	      command_2_44 <= "11000000111111110000000000000000";
	      command_3_44 <= "11000000111111110000000000000000";
	      command_4_44 <= "11000000111111110000000000000000";
	    else
	      if (update_commands_2 = '1') then
	        if (get_commands = '1' and use_commands = '1') then
	          rd_en        <= '1';
	          command_1_11 <= data_out(32*63+31 downto 32*63);
	          command_2_11 <= data_out(32*62+31 downto 32*62);
	          command_3_11 <= data_out(32*61+31 downto 32*61);
	          command_4_11 <= data_out(32*60+31 downto 32*60);
	          command_1_12 <= data_out(32*59+31 downto 32*59);
	          command_2_12 <= data_out(32*58+31 downto 32*58);
	          command_3_12 <= data_out(32*57+31 downto 32*57);
	          command_4_12 <= data_out(32*56+31 downto 32*56);
	          command_1_13 <= data_out(32*55+31 downto 32*55);
	          command_2_13 <= data_out(32*54+31 downto 32*54);
	          command_3_13 <= data_out(32*53+31 downto 32*53);
	          command_4_13 <= data_out(32*52+31 downto 32*52);
	          command_1_14 <= data_out(32*51+31 downto 32*51);
	          command_2_14 <= data_out(32*50+31 downto 32*50);
	          command_3_14 <= data_out(32*49+31 downto 32*49);
	          command_4_14 <= data_out(32*48+31 downto 32*48);
	          command_1_21 <= data_out(32*47+31 downto 32*47);
	          command_2_21 <= data_out(32*46+31 downto 32*46);
	          command_3_21 <= data_out(32*45+31 downto 32*45);
	          command_4_21 <= data_out(32*44+31 downto 32*44);
	          command_1_22 <= data_out(32*43+31 downto 32*43);
	          command_2_22 <= data_out(32*42+31 downto 32*42);
	          command_3_22 <= data_out(32*41+31 downto 32*41);
	          command_4_22 <= data_out(32*40+31 downto 32*40);
	          command_1_23 <= data_out(32*39+31 downto 32*39);
	          command_2_23 <= data_out(32*38+31 downto 32*38);
	          command_3_23 <= data_out(32*37+31 downto 32*37);
	          command_4_23 <= data_out(32*36+31 downto 32*36);
	          command_1_24 <= data_out(32*35+31 downto 32*35);
	          command_2_24 <= data_out(32*34+31 downto 32*34);
	          command_3_24 <= data_out(32*33+31 downto 32*33);
	          command_4_24 <= data_out(32*32+31 downto 32*32);
	          command_1_31 <= data_out(32*31+31 downto 32*31);
	          command_2_31 <= data_out(32*30+31 downto 32*30);
	          command_3_31 <= data_out(32*29+31 downto 32*29);
	          command_4_31 <= data_out(32*28+31 downto 32*28);
	          command_1_32 <= data_out(32*27+31 downto 32*27);
	          command_2_32 <= data_out(32*26+31 downto 32*26);
	          command_3_32 <= data_out(32*25+31 downto 32*25);
	          command_4_32 <= data_out(32*24+31 downto 32*24);
	          command_1_33 <= data_out(32*23+31 downto 32*23);
	          command_2_33 <= data_out(32*22+31 downto 32*22);
	          command_3_33 <= data_out(32*21+31 downto 32*21);
	          command_4_33 <= data_out(32*20+31 downto 32*20);
	          command_1_34 <= data_out(32*19+31 downto 32*19);
	          command_2_34 <= data_out(32*18+31 downto 32*18);
	          command_3_34 <= data_out(32*17+31 downto 32*17);
	          command_4_34 <= data_out(32*16+31 downto 32*16);
	          command_1_41 <= data_out(32*15+31 downto 32*15);
	          command_2_41 <= data_out(32*14+31 downto 32*14);
	          command_3_41 <= data_out(32*13+31 downto 32*13);
	          command_4_41 <= data_out(32*12+31 downto 32*12);
	          command_1_42 <= data_out(32*11+31 downto 32*11);
	          command_2_42 <= data_out(32*10+31 downto 32*10);
	          command_3_42 <= data_out(32*9+31  downto 32*9);
	          command_4_42 <= data_out(32*8+31  downto 32*8);
	          command_1_43 <= data_out(32*7+31  downto 32*7);
	          command_2_43 <= data_out(32*6+31  downto 32*6);
	          command_3_43 <= data_out(32*5+31  downto 32*5);
	          command_4_43 <= data_out(32*4+31  downto 32*4);
	          command_1_44 <= data_out(32*3+31  downto 32*3);
	          command_2_44 <= data_out(32*2+31  downto 32*2);
	          command_3_44 <= data_out(32*1+31  downto 32*1);
	          command_4_44 <= data_out(32*0+31  downto 32*0);
	        elsif (get_commands = '1' and use_commands = '0') then
	          rd_en        <= '1';
	          command_1_11 <= "11000000111111000000000000000000";
	          command_2_11 <= "11000000111111000000000000000000";
	          command_3_11 <= "11000000111111000000000000000000";
	          command_4_11 <= "11000000111111000000000000000000";
	          command_1_12 <= "11000000111111000000000000000000";
	          command_2_12 <= "11000000111111000000000000000000";
	          command_3_12 <= "11000000111111000000000000000000";
	          command_4_12 <= "11000000111111000000000000000000";
	          command_1_13 <= "11000000111111000000000000000000";
	          command_2_13 <= "11000000111111000000000000000000";
	          command_3_13 <= "11000000111111000000000000000000";
	          command_4_13 <= "11000000111111000000000000000000";
	          command_1_14 <= "11000000111111000000000000000000";
	          command_2_14 <= "11000000111111000000000000000000";
	          command_3_14 <= "11000000111111000000000000000000";
	          command_4_14 <= "11000000111111000000000000000000";
	          command_1_21 <= "11000000111111000000000000000000";
	          command_2_21 <= "11000000111111000000000000000000";
	          command_3_21 <= "11000000111111000000000000000000";
	          command_4_21 <= "11000000111111000000000000000000";
	          command_1_22 <= "11000000111111000000000000000000";
	          command_2_22 <= "11000000111111000000000000000000";
	          command_3_22 <= "11000000111111000000000000000000";
	          command_4_22 <= "11000000111111000000000000000000";
	          command_1_23 <= "11000000111111000000000000000000";
	          command_2_23 <= "11000000111111000000000000000000";
	          command_3_23 <= "11000000111111000000000000000000";
	          command_4_23 <= "11000000111111000000000000000000";
	          command_1_24 <= "11000000111111000000000000000000";
	          command_2_24 <= "11000000111111000000000000000000";
	          command_3_24 <= "11000000111111000000000000000000";
	          command_4_24 <= "11000000111111000000000000000000";
	          command_1_31 <= "11000000111111000000000000000000";
	          command_2_31 <= "11000000111111000000000000000000";
	          command_3_31 <= "11000000111111000000000000000000";
	          command_4_31 <= "11000000111111000000000000000000";
	          command_1_32 <= "11000000111111000000000000000000";
	          command_2_32 <= "11000000111111000000000000000000";
	          command_3_32 <= "11000000111111000000000000000000";
	          command_4_32 <= "11000000111111000000000000000000";
	          command_1_33 <= "11000000111111000000000000000000";
	          command_2_33 <= "11000000111111000000000000000000";
	          command_3_33 <= "11000000111111000000000000000000";
	          command_4_33 <= "11000000111111000000000000000000";
	          command_1_34 <= "11000000111111000000000000000000";
	          command_2_34 <= "11000000111111000000000000000000";
	          command_3_34 <= "11000000111111000000000000000000";
	          command_4_34 <= "11000000111111000000000000000000";
	          command_1_41 <= "11000000111111000000000000000000";
	          command_2_41 <= "11000000111111000000000000000000";
	          command_3_41 <= "11000000111111000000000000000000";
	          command_4_41 <= "11000000111111000000000000000000";
	          command_1_42 <= "11000000111111000000000000000000";
	          command_2_42 <= "11000000111111000000000000000000";
	          command_3_42 <= "11000000111111000000000000000000";
	          command_4_42 <= "11000000111111000000000000000000";
	          command_1_43 <= "11000000111111000000000000000000";
	          command_2_43 <= "11000000111111000000000000000000";
	          command_3_43 <= "11000000111111000000000000000000";
	          command_4_43 <= "11000000111111000000000000000000";
	          command_1_44 <= "11000000111111000000000000000000";
	          command_2_44 <= "11000000111111000000000000000000";
	          command_3_44 <= "11000000111111000000000000000000";
	          command_4_44 <= "11000000111111000000000000000000";
	        else
	          command_1_11 <= "11000000111111100000000000000000";
	          command_2_11 <= "11000000111111100000000000000000";
	          command_3_11 <= "11000000111111100000000000000000";
	          command_4_11 <= "11000000111111100000000000000000";
	          command_1_12 <= "11000000111111100000000000000000";
	          command_2_12 <= "11000000111111100000000000000000";
	          command_3_12 <= "11000000111111100000000000000000";
	          command_4_12 <= "11000000111111100000000000000000";
	          command_1_13 <= "11000000111111100000000000000000";
	          command_2_13 <= "11000000111111100000000000000000";
	          command_3_13 <= "11000000111111100000000000000000";
	          command_4_13 <= "11000000111111100000000000000000";
	          command_1_14 <= "11000000111111100000000000000000";
	          command_2_14 <= "11000000111111100000000000000000";
	          command_3_14 <= "11000000111111100000000000000000";
	          command_4_14 <= "11000000111111100000000000000000";
	          command_1_21 <= "11000000111111100000000000000000";
	          command_2_21 <= "11000000111111100000000000000000";
	          command_3_21 <= "11000000111111100000000000000000";
	          command_4_21 <= "11000000111111100000000000000000";
	          command_1_22 <= "11000000111111100000000000000000";
	          command_2_22 <= "11000000111111100000000000000000";
	          command_3_22 <= "11000000111111100000000000000000";
	          command_4_22 <= "11000000111111100000000000000000";
	          command_1_23 <= "11000000111111100000000000000000";
	          command_2_23 <= "11000000111111100000000000000000";
	          command_3_23 <= "11000000111111100000000000000000";
	          command_4_23 <= "11000000111111100000000000000000";
	          command_1_24 <= "11000000111111100000000000000000";
	          command_2_24 <= "11000000111111100000000000000000";
	          command_3_24 <= "11000000111111100000000000000000";
	          command_4_24 <= "11000000111111100000000000000000";
	          command_1_31 <= "11000000111111100000000000000000";
	          command_2_31 <= "11000000111111100000000000000000";
	          command_3_31 <= "11000000111111100000000000000000";
	          command_4_31 <= "11000000111111100000000000000000";
	          command_1_32 <= "11000000111111100000000000000000";
	          command_2_32 <= "11000000111111100000000000000000";
	          command_3_32 <= "11000000111111100000000000000000";
	          command_4_32 <= "11000000111111100000000000000000";
	          command_1_33 <= "11000000111111100000000000000000";
	          command_2_33 <= "11000000111111100000000000000000";
	          command_3_33 <= "11000000111111100000000000000000";
	          command_4_33 <= "11000000111111100000000000000000";
	          command_1_34 <= "11000000111111100000000000000000";
	          command_2_34 <= "11000000111111100000000000000000";
	          command_3_34 <= "11000000111111100000000000000000";
	          command_4_34 <= "11000000111111100000000000000000";
	          command_1_41 <= "11000000111111100000000000000000";
	          command_2_41 <= "11000000111111100000000000000000";
	          command_3_41 <= "11000000111111100000000000000000";
	          command_4_41 <= "11000000111111100000000000000000";
	          command_1_42 <= "11000000111111100000000000000000";
	          command_2_42 <= "11000000111111100000000000000000";
	          command_3_42 <= "11000000111111100000000000000000";
	          command_4_42 <= "11000000111111100000000000000000";
	          command_1_43 <= "11000000111111100000000000000000";
	          command_2_43 <= "11000000111111100000000000000000";
	          command_3_43 <= "11000000111111100000000000000000";
	          command_4_43 <= "11000000111111100000000000000000";
	          command_1_44 <= "11000000111111100000000000000000";
	          command_2_44 <= "11000000111111100000000000000000";
	          command_3_44 <= "11000000111111100000000000000000";
	          command_4_44 <= "11000000111111100000000000000000";
	        end if; 
	      end if; 
	    end if;
	  end if;
	end process;
	
	second_half <= '1' when phase_ctr > 10 else '0';
	
	all_empty  <= empty(4) and empty(3) and empty(2) and empty(1) and empty(0);
	
    process( S_AXI_ACLK ) is
	   begin
	   if (rising_edge (S_AXI_ACLK)) then
	       if word_count = "00000000000000000000000000000000" and second_half = '0' then
	           command_11 <= command_1_11;
	           command_12 <= command_1_12;
	           command_13 <= command_1_13;
	           command_14 <= command_1_14;
	           command_21 <= command_1_21;
	           command_22 <= command_1_22;
	           command_23 <= command_1_23;
	           command_24 <= command_1_24;
	           command_31 <= command_1_31;
	           command_32 <= command_1_32;
	           command_33 <= command_1_33;
	           command_34 <= command_1_34;
	           command_41 <= command_1_41;
	           command_42 <= command_1_42;
	           command_43 <= command_1_43;
	           command_44 <= command_1_44;
	       elsif word_count = "00000000000000000000000000000000" and second_half = '1' then
	           command_11 <= command_2_11;
	           command_12 <= command_2_12;
	           command_13 <= command_2_13;
	           command_14 <= command_2_14;
	           command_21 <= command_2_21;
	           command_22 <= command_2_22;
	           command_23 <= command_2_23;
	           command_24 <= command_2_24;
	           command_31 <= command_2_31;
	           command_32 <= command_2_32;
	           command_33 <= command_2_33;
	           command_34 <= command_2_34;
	           command_41 <= command_2_41;
	           command_42 <= command_2_42;
	           command_43 <= command_2_43;
	           command_44 <= command_2_44;
	       elsif word_count = "00000000000000000000000000000001" and second_half = '0' then
	           command_11 <= command_3_11;
	           command_12 <= command_3_12;
	           command_13 <= command_3_13;
	           command_14 <= command_3_14;
	           command_21 <= command_3_21;
	           command_22 <= command_3_22;
	           command_23 <= command_3_23;
	           command_24 <= command_3_24;
	           command_31 <= command_3_31;
	           command_32 <= command_3_32;
	           command_33 <= command_3_33;
	           command_34 <= command_3_34;
	           command_41 <= command_3_41;
	           command_42 <= command_3_42;
	           command_43 <= command_3_43;
	           command_44 <= command_3_44;
	       elsif word_count = "00000000000000000000000000000001" and second_half = '1' then
	           command_11 <= command_4_11;
	           command_12 <= command_4_12;
	           command_13 <= command_4_13;
	           command_14 <= command_4_14;
	           command_21 <= command_4_21;
	           command_22 <= command_4_22;
	           command_23 <= command_4_23;
	           command_24 <= command_4_24;
	           command_31 <= command_4_31;
	           command_32 <= command_4_32;
	           command_33 <= command_4_33;
	           command_34 <= command_4_34;
	           command_41 <= command_4_41;
	           command_42 <= command_4_42;
	           command_43 <= command_4_43;
	           command_44 <= command_4_44;
	       else
	           command_11 <= "11000000111111010000000000000000";
	           command_12 <= "11000000111111010000000000000000";
	           command_13 <= "11000000111111010000000000000000";
	           command_14 <= "11000000111111010000000000000000";
	           command_21 <= "11000000111111010000000000000000";
	           command_22 <= "11000000111111010000000000000000";
	           command_23 <= "11000000111111010000000000000000";
	           command_24 <= "11000000111111010000000000000000";
	           command_31 <= "11000000111111010000000000000000";
	           command_32 <= "11000000111111010000000000000000";
	           command_33 <= "11000000111111010000000000000000";
	           command_34 <= "11000000111111010000000000000000";
	           command_41 <= "11000000111111010000000000000000";
	           command_42 <= "11000000111111010000000000000000";
	           command_43 <= "11000000111111010000000000000000";
	           command_44 <= "11000000111111010000000000000000";
	       end if;
	   end if;
	end process;   
                  
	process( S_AXI_ACLK ) is
	begin
	  if (rising_edge (S_AXI_ACLK)) then
        package_loss <= package_loss_signal; -- Done to solve a timing issue. Not necessary otherwise
      end if;
    end process;
    
    -- Done to solve a timing issue. Not necessary otherwise
	process( S_AXI_ACLK ) is
	begin
	  if (rising_edge (S_AXI_ACLK)) then
        wr_en   <= wr_en_buf;    
        data_in <= data_in_buf;
      end if;
    end process;
    
	-- User logic ends

end arch_imp;
