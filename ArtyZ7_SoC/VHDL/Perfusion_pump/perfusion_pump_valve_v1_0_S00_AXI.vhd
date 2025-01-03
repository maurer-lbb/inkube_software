-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity perfusion_pump_valve_v1_0_S00_AXI is
	generic (
		-- Users to add parameters here

		-- User parameters ends
		-- Do not modify the parameters beyond this line

		-- Width of S_AXI data bus
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		-- Width of S_AXI address bus
		C_S_AXI_ADDR_WIDTH	: integer	:= 5
	);
	port (
		-- Users to add ports here

        -- REGISTER DEFINTIONS:
        -- slv_reg0(0) .. enable (Active high?)
        -- slv_reg1    .. delay counter
        -- slv_reg2    .. FiFo status register
        --   (11:0)    .. fifo_length
        --     (30)    .. fifo_empty
        --     (31)    .. fifo_full
        -- (others)    .. 0
        -- slv_reg3    .. pump_loc or valve_status (lowest 24 bit)
        -- slv_reg4    .. To enable the pumps to actually do steps
        --      (0)    .. Enable the pump to actually do steps (this only masks the pump_steps and does nothing else)
        --   (31:1)    .. NC
        
        pump_empty       : in  std_logic;
        pump_full        : in  std_logic;
        pump_step        : out std_logic;
        
        ext_enable       : in  std_logic;
        
        shift_reg_clk    : out std_logic;
        shift_reg_data   : out std_logic;
        shift_reg_latch  : out std_logic;

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
end perfusion_pump_valve_v1_0_S00_AXI;

architecture arch_imp of perfusion_pump_valve_v1_0_S00_AXI is
    
    component shift_register is
        Generic (
            clk_freq        : integer := 100000000; -- Hz
            clk_half_period : integer :=         1  -- us
        );
        Port ( 
            CLK100MHZ       : in  std_logic;
        
            shift_reg_clk   : out std_logic;
            shift_reg_data  : out std_logic;
            shift_reg_latch : out std_logic;
            
            output_rdy      : out std_logic;
            
            valve_state     : in  std_logic_vector(23 downto 0);
            pump_enable     : in  std_logic;
            pump_dir        : in  std_logic;
            valve_enable    : in  std_logic
        );
    end component;
    
    component pump is
        Generic (
            clk_freq       : integer := 100000000; -- Hz
            pump_period    : integer :=       200; -- us (must be at least 10 us)
            pump_warmup    : integer :=       100; -- ms
            pump_cooldown  : integer :=       100; -- ms
            pump_max_steps : integer :=     74980  -- also need to be changed in shift_register and below
        );
        Port (
            CLK100MHZ        : in  std_logic;
        
            enable           : in  std_logic;
            position         : in  integer range 0 to 2147483647;
            
            pump_empty       : in  std_logic;
            pump_full        : in  std_logic;
            
            can_pump         : in  std_logic;
            
            pump_dir         : out std_logic;
            pump_enable      : out std_logic;
            pump_step        : out std_logic;
            
            pump_en_movement : in  std_logic;
            
            ready            : out std_logic
        );
    end component;
    
    component fifo_generator_0 IS
        PORT (
            clk        : in  std_logic;
            srst       : in  std_logic;
            din        : in  std_logic_vector(31 DOWNTO 0);
            wr_en      : in  std_logic;
            rd_en      : in  std_logic;
            dout       : out std_logic_vector(31 DOWNTO 0);
            full       : out std_logic;
            empty      : out std_logic;
            data_count : out std_logic_vector(11 DOWNTO 0)
        );
    end component;

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

	-- Example-specific design signals
	-- local parameter for addressing 32 bit / 64 bit C_S_AXI_DATA_WIDTH
	-- ADDR_LSB is used for addressing 32/64 bit registers/memories
	-- ADDR_LSB = 2 for 32 bits (n downto 2)
	-- ADDR_LSB = 3 for 64 bits (n downto 3)
	constant ADDR_LSB  : integer := (C_S_AXI_DATA_WIDTH/32)+ 1;
	constant OPT_MEM_ADDR_BITS : integer := 2;
	------------------------------------------------
	---- Signals for user logic register space example
	--------------------------------------------------
	---- Number of Slave Registers 5
	signal slv_reg0	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg1	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg2	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg3	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg4	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal slv_reg_rden	: std_logic;
	signal slv_reg_wren	: std_logic;
	signal reg_data_out	:std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
	signal byte_index	: integer;
	signal aw_en	: std_logic;
	
	
    signal shift_reg_ready  : std_logic;
    signal pump_ready       : std_logic;
    signal system_ready     : std_logic := '0';
    
    signal fifo_wr_en       : std_logic;
    signal fifo_rd_en       : std_logic;
    signal fifo_dout        : std_logic_vector(31 downto 0);
    signal fifo_full        : std_logic;
    signal fifo_empty       : std_logic;
    signal fifo_length      : std_logic_vector(11 downto 0);
       
    signal delay_start      : integer range 0 to 2147483647 := 0;
    signal delay_counter    : integer range 0 to 2147483647 := 0;
    
    signal rst              : std_logic;
    
    signal pump_step_buf    : std_logic;
    signal pump_enable_buf  : std_logic;
    signal pump_dir_buf     : std_logic;
    signal sys_enable       : std_logic;
    
    signal pump_position    : integer range 0 to 2147483647 := 74980; -- Also needs to be changed in the generic session AND pump.vhd

    signal valve_state      : std_logic_vector(23 downto 0) := (others => '0');
    
    signal pump_en_movement : std_logic := '0';
    
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
	variable loc_addr :std_logic_vector(OPT_MEM_ADDR_BITS downto 0); 
	begin
	  if rising_edge(S_AXI_ACLK) then 
	    fifo_wr_en <= '0'; -- Standard value
	    if S_AXI_ARESETN = '0' then
	      slv_reg0 <= (others => '0');
	      --slv_reg1 <= (others => '0');
	      --slv_reg2 <= (others => '0');
	      slv_reg3 <= (others => '0');
	      slv_reg4 <= (others => '0');
	    else
	      loc_addr := axi_awaddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);
	      if (slv_reg_wren = '1') then
	        case loc_addr is
	          when b"000" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 0
	                slv_reg0(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"001" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 1
	                -- slv_reg1(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"010" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 2
	                -- slv_reg2(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"011" =>
	            fifo_wr_en <= '1'; -- Assuming that all three strobe bits are identical. Just using last one did not work
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 3
	                slv_reg3(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when b"100" =>
	            for byte_index in 0 to (C_S_AXI_DATA_WIDTH/8-1) loop
	              if ( S_AXI_WSTRB(byte_index) = '1' ) then
	                -- Respective byte enables are asserted as per write strobes                   
	                -- slave registor 4
	                slv_reg4(byte_index*8+7 downto byte_index*8) <= S_AXI_WDATA(byte_index*8+7 downto byte_index*8);
	              end if;
	            end loop;
	          when others =>
	            slv_reg0 <= slv_reg0;
	            --slv_reg1 <= slv_reg1;
	            --slv_reg2 <= slv_reg2;
	            slv_reg3 <= slv_reg3;
	            slv_reg4 <= slv_reg4;
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
	      axi_bresp   <= "00"; --need to work more on the responses
	    else
	      if (axi_awready = '1' and S_AXI_AWVALID = '1' and axi_wready = '1' and S_AXI_WVALID = '1' and axi_bvalid = '0'  ) then
	        axi_bvalid <= '1';
	        axi_bresp  <= "00"; 
	      elsif (S_AXI_BREADY = '1' and axi_bvalid = '1') then   --check if bready is asserted while bvalid is high)
	        axi_bvalid <= '0';                                 -- (there is a possibility that bready is always asserted high)
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

	process (slv_reg0, slv_reg1, slv_reg2, slv_reg3, slv_reg4, axi_araddr, S_AXI_ARESETN, slv_reg_rden)
	variable loc_addr :std_logic_vector(OPT_MEM_ADDR_BITS downto 0);
	begin
	    -- Address decoding for reading registers
	    loc_addr := axi_araddr(ADDR_LSB + OPT_MEM_ADDR_BITS downto ADDR_LSB);
	    case loc_addr is
	      when b"000" =>
	        reg_data_out <= slv_reg0;
	      when b"001" =>
	        reg_data_out <= slv_reg1;
	      when b"010" =>
	        reg_data_out <= slv_reg2;
	      when b"011" =>
	        reg_data_out <= slv_reg3;
	      when b"100" =>
	        reg_data_out <= slv_reg4;
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
    sys_enable  <= slv_reg0(0) and ext_enable;
    
    pump_step   <= pump_step_buf;
    
    pump_inst : pump port map (
        CLK100MHZ   => S_AXI_ACLK,
        
        can_pump    => shift_reg_ready,
                    
        enable      => sys_enable,
        position    => pump_position,
        pump_empty  => pump_empty,
        pump_full   => pump_full,
                    
        pump_step   => pump_step_buf,
        pump_dir    => pump_dir_buf,
        pump_enable => pump_enable_buf,
        
        pump_en_movement => pump_en_movement,
        
        ready       => pump_ready
    );
	
	rst <= not S_AXI_ARESETN;
	
	fifo : fifo_generator_0 port map(
        clk        => S_AXI_ACLK,
        srst       => rst,
        din        => slv_reg3,
        wr_en      => fifo_wr_en,
        rd_en      => fifo_rd_en,
        dout       => fifo_dout,
        full       => fifo_full,
        empty      => fifo_empty,
        data_count => fifo_length
    );
    
    shift_register_inst : shift_register port map(
            CLK100MHZ       => S_AXI_ACLK,
                            
            shift_reg_clk   => shift_reg_clk,
            shift_reg_data  => shift_reg_data,
            shift_reg_latch => shift_reg_latch,
                            
            output_rdy      => shift_reg_ready,
                            
            valve_state     => valve_state,
            pump_enable     => pump_enable_buf,
            pump_dir        => pump_dir_buf,
            valve_enable    => sys_enable
    );
    
    process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if (S_AXI_ARESETN = '0') then
                fifo_rd_en     <= '0';
                delay_start    <=  0;
                pump_position  <= 74980; -- also need to be changed at other locations in this file and pump.vhd  
            else
                fifo_rd_en  <= '0';
                delay_start <=  0;
                if ((not fifo_empty) and system_ready and (not fifo_rd_en)) = '1' then
                
                    fifo_rd_en     <= '1';
                    if fifo_dout(31) = '1' then
                        pump_position  <= to_integer(unsigned(fifo_dout(23 downto 0)));
                    else
                        valve_state    <= fifo_dout(23 downto 0);
                    end if;
                    
                    case (fifo_dout(27 downto 24)) is
                        when "0000" => delay_start <=          0; --   0 ms
                        when "0001" => delay_start <=     100000; --   1 ms
                        when "0010" => delay_start <=     200000; --   2 ms
                        when "0011" => delay_start <=     500000; --   5 ms
                        when "0100" => delay_start <=    1000000; --  10 ms
                        when "0101" => delay_start <=    2000000; --  20 ms
                        when "0110" => delay_start <=    5000000; --  50 ms
                        when "0111" => delay_start <=   10000000; -- 100 ms
                        when "1000" => delay_start <=   20000000; -- 200 ms
                        when "1001" => delay_start <=   50000000; -- 500 ms
                        when "1010" => delay_start <=  100000000; --  1 sec
                        when "1011" => delay_start <=  200000000; --  2 sec
                        when "1100" => delay_start <=  500000000; --  5 sec
                        when "1101" => delay_start <= 1000000000; -- 10 sec
                        when "1110" => delay_start <= 1500000000; -- 15 sec
                        when "1111" => delay_start <= 2000000000; -- 20 sec
                        when others => delay_start <=          0;
                    end case;
                end if;    
            end if;
        end if;
    end process;
    
    process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            system_ready <= '0';
            if delay_counter = 0 then
                delay_counter <= delay_start; -- delay_start is usually 0, except if a new command was just executed
            end if;
            
            if shift_reg_ready = '1' and
               pump_ready      = '1' then
                if delay_counter > 0 then
                    delay_counter <= delay_counter - 1;
                elsif delay_counter = 0 and delay_start = 0 then
                    system_ready <= '1';
                end if;
            end if;
        end if;
    end process;
    
    slv_reg2(31)           <= fifo_full;
	slv_reg2(30)           <= fifo_empty;
	slv_reg2(29)           <= shift_reg_ready;
	slv_reg2(28)           <= system_ready;
	slv_reg2(11 downto 0)  <= fifo_length;
	
	slv_reg2(27 downto 12) <= (others => '0');
    
    slv_reg1               <= std_logic_vector(to_unsigned(delay_counter,32));
    
    pump_en_movement       <= slv_reg4(0);
    
	-- User logic ends

end arch_imp;
