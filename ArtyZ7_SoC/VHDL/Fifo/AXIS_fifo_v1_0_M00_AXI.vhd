-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity AXIS_fifo_v1_0_M00_AXIS is
	generic (
		-- Users to add parameters here

		-- User parameters ends
		-- Do not modify the parameters beyond this line

		-- Width of S_AXIS address bus. The slave accepts the read and write addresses of width C_M_AXIS_TDATA_WIDTH.
		C_M_AXIS_TDATA_WIDTH	: integer	:= 32;
		-- Start count is the number of clock cycles the master will wait after a reset
		C_M_START_COUNT	: integer	:= 128
	);
	port (
		-- Users to add ports here
		
		fifo_read_data   : in  std_logic_vector(31 downto 0);
		fifo_read_en     : out std_logic;
		fifo_not_empty   : in  std_logic;
		fifo_length      : in  std_logic_vector(15 downto 0);
        enable_recording : in  std_logic;

		-- User ports ends
		-- Do not modify the ports beyond this line

		-- Global ports
		M_AXIS_ACLK	: in std_logic;
		M_AXIS_ARESETN	: in std_logic;
		-- Master Stream Ports. TVALID indicates that the master is driving a valid transfer, A transfer takes place when both TVALID and TREADY are asserted. 
		M_AXIS_TVALID	: out std_logic;
		-- TDATA is the primary payload that is used to provide the data that is passing across the interface from the master.
		M_AXIS_TDATA	: out std_logic_vector(C_M_AXIS_TDATA_WIDTH-1 downto 0);
		-- TSTRB is the byte qualifier that indicates whether the content of the associated byte of TDATA is processed as a data byte or a position byte.
		M_AXIS_TSTRB	: out std_logic_vector((C_M_AXIS_TDATA_WIDTH/8)-1 downto 0);
		-- TLAST indicates the boundary of a packet.
		M_AXIS_TLAST	: out std_logic;
		-- TREADY indicates that the slave can accept a transfer in the current cycle.
		M_AXIS_TREADY	: in std_logic
	);
end AXIS_fifo_v1_0_M00_AXIS;

architecture implementation of AXIS_fifo_v1_0_M00_AXIS is
	-- Total number of output data                                              
	constant NUMBER_OF_OUTPUT_WORDS : integer := 352 + 1 + 3; -- 352 data words + 1 ctrl (word + which quarter) + 3 preamble
       
	-- AXI Stream internal signals
	
	--streaming data valid
	signal axis_tvalid	: std_logic;
	--Last of the streaming data 
	signal axis_tlast	: std_logic;
	--FIFO implementation signals
	signal stream_data_out	: std_logic_vector(C_M_AXIS_TDATA_WIDTH-1 downto 0);
	
	-- Used to find out what word we are sending within a frame (0 - C_M_START_COUNT-1);
	signal subframe_counter : integer range 0 to NUMBER_OF_OUTPUT_WORDS := 0;
	
	-- Used to make sure the beginning is not communicating;
	signal initial_counter : integer range 0 to C_M_START_COUNT := C_M_START_COUNT;
	
	-- Used to cause some break in tvalid after sucessful transmitting a package
	signal break_counter   : integer range 0 to 16 := 0;
	    
begin
	-- I/O Connections assignments

	M_AXIS_TVALID	<= axis_tvalid;
	M_AXIS_TDATA	<= stream_data_out;
	M_AXIS_TLAST	<= axis_tlast;
	M_AXIS_TSTRB	<= (others => '1');
	
	-- Code changed below this mark (SI)
	
	-- Process to disable data transfer for the first C_M_START_COUNT clock cycles
	process(M_AXIS_ACLK)
	begin
	   if (rising_edge (M_AXIS_ACLK)) then
           if(M_AXIS_ARESETN = '0') then  
               initial_counter <= C_M_START_COUNT;
           else
               if (initial_counter > 0) then
                   initial_counter <= initial_counter - 1 + break_counter;
               else
                   initial_counter <= break_counter;
               end if;
           end if;
	   end if;
	end process;
	
	axis_tvalid <= '0' when (initial_counter > 0) or (enable_recording = '0') or (fifo_not_empty = '0') else '1';
	
	-- Since the fifo is synchronized, we will get one data point if the following holds. No need to put into a process
	fifo_read_en <= '1' when (axis_tvalid = '1' and M_AXIS_TREADY = '1' and M_AXIS_ARESETN = '1' ) else '0';

	-- Control state machine implementation         
	-- This frame should count the following way, if reset not active AND enable_recording is set:
	-- SUB_FRAME   | 0 | 1 | 2 |...| NUMBER_OF_OUTPUT_WORDS-1 | NUMBER_OF_OUTPUT_WORDS | 0 | 1 | 2 |...| NUMBER_OF_OUTPUT_WORDS-1 | NUMBER_OF_OUTPUT_WORDS |...| NUMBER_OF_OUTPUT_WORDS | 0 |...
	-- PACKAGE     | 0 | 0 | 0 |...| 0                        | 0                      | 1 | 1 | 1 |...| 1                        | 1                      |...| 59999                  | 0 |...
	-- TLAST       |   |   |   |...|                          | x                      |   |   |   |...|                          | x                      |...| x                      |   |...
	process(M_AXIS_ACLK)  
	begin                                                                                       
	  if (rising_edge (M_AXIS_ACLK)) then  
	    break_counter        <= 0; -- Is 0 unless we send the last word                                                           
	    if(M_AXIS_ARESETN = '0' or enable_recording = '0') then                                                           
	      -- Synchronous reset (active low)      
	      axis_tlast         <= '0';
	      subframe_counter   <= 0;  
	    else      
	      if axis_tvalid = '1' and M_AXIS_TREADY = '1' then
              subframe_counter <= subframe_counter + 1;                                                                            
              if subframe_counter = NUMBER_OF_OUTPUT_WORDS-1 then
                axis_tlast         <= '0';
                subframe_counter   <= 0;
              else if subframe_counter = NUMBER_OF_OUTPUT_WORDS-2 then
                axis_tlast    <= '1';
                break_counter <= 4;
              else
                axis_tlast    <= '0';
              end if; end if; -- 2x "end if" because of "else if"
	      end if;                                                    
	    end if;                                                                                 
	  end if;                                                                                   
	end process;                    
		
	stream_data_out <= fifo_read_data;
	--std_logic_vector(to_unsigned(package_counter,32)) when subframe_counter = 0 else
	--"10101010010101011010101001010101"                when subframe_counter = 1 else -- 0xAA55AA55
	--"01010101101010100101010110101010"                when subframe_counter = 2 else -- 0x55AA55AA
	--"10101010010101011010101001010101"                when subframe_counter = 3 else -- 0xAA55AA55
	--std_logic_vector(to_unsigned(subframe_counter-4,32));                                                               

end implementation;

