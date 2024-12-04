-- inkube Software © 2024 by Maurer et al. (ETH Zurich, Switzerland) is licensed under the GNU General Public License v3.0 (GPLv3).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_environment_controller_v1_0 is
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
        temperature_1     : out std_logic_vector(14 downto 0);
        temperature_2     : out std_logic_vector(14 downto 0);
        temperature_3     : out std_logic_vector(14 downto 0);
        temperature_4     : out std_logic_vector(14 downto 0);
                
        co2_pwm           : out std_logic;
        
        ext_enable        : in  std_logic;
        
        temperature_reservoir       : out   std_logic_vector(15 downto 0);
        humidity_reservoir          : out   std_logic_vector(15 downto 0);
        co2_concentration_reservoir : out   std_logic_vector(15 downto 0);
        
        sda_out           : out std_logic;
        scl_out           : out std_logic;
        sda_in            : in  std_logic;
        scl_in            : in  std_logic;
        
        calibrate_co2     : in  std_logic;
        
        spi_clk_pwr       : out std_logic;
        spi_mosi_pwr      : out std_logic;
        
        spi_clk_bot       : out std_logic;
        spi_miso_bot      : in  std_logic;
        spi_mosi_bot      : out std_logic;
        spi_cs_bot        : out std_logic_vector(3 downto 0);
        
        sr_sdi_pwr        : out std_logic;
        sr_sclk_pwr       : out std_logic;
        sr_latch_pwr      : out std_logic;
        
        EN_VCC            : out std_logic;                    -- new since inkube 4.0
        DAUX1             : out std_logic;                    -- new since inkube 4.0
        
        debug_sig         : out std_logic_vector(1 downto 0);
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
end axi_environment_controller_v1_0;

architecture arch_imp of axi_environment_controller_v1_0 is

	-- component declaration
	component axi_environment_controller_v1_0_S00_AXI is
		generic (
		C_S_AXI_DATA_WIDTH	: integer	:= 32;
		C_S_AXI_ADDR_WIDTH	: integer	:= 6
		);
		port (
		p_factor_1        : out std_logic_vector(7 downto 0);       
        p_factor_2        : out std_logic_vector(7 downto 0); 
        p_factor_3        : out std_logic_vector(7 downto 0); 
        p_factor_4        : out std_logic_vector(7 downto 0); 
        p_factor_res      : out std_logic_vector(7 downto 0);
        p_factor_aux      : out std_logic_vector(7 downto 0);
        i_factor_1        : out std_logic_vector(7 downto 0); 
        i_factor_2        : out std_logic_vector(7 downto 0); 
        i_factor_3        : out std_logic_vector(7 downto 0); 
        i_factor_4        : out std_logic_vector(7 downto 0); 
        i_factor_res      : out std_logic_vector(7 downto 0); 
        i_factor_aux      : out std_logic_vector(7 downto 0); 
        ought_temp_1      : out std_logic_vector(14 downto 0);
        ought_temp_2      : out std_logic_vector(14 downto 0); 
        ought_temp_3      : out std_logic_vector(14 downto 0); 
        ought_temp_4      : out std_logic_vector(14 downto 0);
        heater_on_1       : out std_logic;
        heater_on_2       : out std_logic;
        heater_on_3       : out std_logic;
        heater_on_4       : out std_logic;
        heater_on_res     : out std_logic;
        heater_on_aux     : out std_logic;
        is_temp_1         : in  std_logic_vector(14 downto 0);
        is_temp_2         : in  std_logic_vector(14 downto 0); 
        is_temp_3         : in  std_logic_vector(14 downto 0); 
        is_temp_4         : in  std_logic_vector(14 downto 0);
        valve_on          : out std_logic;
        aux_is_humidity   : out std_logic;  
        aux_is_temp       : out std_logic;        
        running_co2_calib : out std_logic; -- If set to 1, then the co2 sensor gets calibrated
        running_i2c_init  : out std_logic; -- If set to 1, then the i2c gets re-initalized
        p_factor_co2      : out std_logic_vector(7 downto 0);
        i_factor_co2      : out std_logic_vector(7 downto 0);
        p_factor_humidity : out std_logic_vector(7 downto 0);
        i_factor_humidity : out std_logic_vector(7 downto 0);
        ought_co2         : out std_logic_vector(15 downto 0);
        is_co2            : in  std_logic_vector(15 downto 0);
        ought_humidity    : out std_logic_vector(15 downto 0);
        is_humidity       : in  std_logic_vector(15 downto 0);
        ought_aux_heater  : out std_logic_vector(15 downto 0);
        is_aux_heater     : out std_logic_vector(15 downto 0);
        ought_temperature : out std_logic_vector(15 downto 0);
        is_temperature    : in  std_logic_vector(15 downto 0);
        EN_VCC            : out std_logic;                    -- new since inkube 4.0
        DAUX1             : out std_logic;                    -- new since inkube 4.0
        DIG_AUX           : out std_logic_vector(2 downto 0); -- new since inkube 4.0
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
	end component axi_environment_controller_v1_0_S00_AXI;
	
	component heater is
	    Generic (
		      DIMENSION    : integer := 16;
              SCALE        : integer := 1
		);
        Port (CLK100MHZ    : in  std_logic;
        
              ought_value  : in  std_logic_vector(DIMENSION-1 downto 0);
              is_value     : in  std_logic_vector(DIMENSION-1 downto 0);
              
              p_factor     : in  std_logic_vector(7 downto 0);
              i_factor     : in  std_logic_vector(7 downto 0);
              
              heater_on    : in  std_logic;
              heater       : out std_logic_vector(11 downto 0));
              
    end component;
	
	component heater_single_sided is
	    Generic (
		      DIMENSION    : integer := 16;
              SCALE        : integer := 1
		);
        Port (CLK100MHZ    : in  std_logic;
        
              ought_value  : in  std_logic_vector(DIMENSION-1 downto 0);
              is_value     : in  std_logic_vector(DIMENSION-1 downto 0);
              
              p_factor     : in  std_logic_vector(7 downto 0);
              i_factor     : in  std_logic_vector(7 downto 0);
              
              heater_on    : in  std_logic;
              heater       : out std_logic_vector(11 downto 0));
              
    end component;
    
    component co2_controller is
        Port (CLK100MHZ    : in  std_logic;
        
              ought_value  : in  std_logic_vector(15 downto 0);
              is_value     : in  std_logic_vector(15 downto 0);
              
              p_factor     : in  std_logic_vector(7 downto 0);
              i_factor     : in  std_logic_vector(7 downto 0);
              
              valve_on     : in  std_logic;
              valve        : out std_logic);
    end component;
    
    component i2c_interface is
        Port ( 
            CLK100MHZ         : in  std_logic;
        
            temperature       : out std_logic_vector(15 downto 0);
            humidity          : out std_logic_vector(15 downto 0);
            co2_concentration : out std_logic_vector(15 downto 0);
            
            sda_in            : in  std_logic;
            scl_in            : in  std_logic;
            sda_out           : out std_logic;
            scl_out           : out std_logic;
            
            calibrate_co2     : in  std_logic;
            
            running_i2c_init  : in std_logic;
            running_co2_calib : in  std_logic;
            
            debug_sig         : out std_logic_vector(1 downto 0));
    end component;
    
    component interface is
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
    end component;
        
    signal p_factor_1         : std_logic_vector(7 downto 0);     
    signal p_factor_2         : std_logic_vector(7 downto 0);
    signal p_factor_3         : std_logic_vector(7 downto 0);
    signal p_factor_4         : std_logic_vector(7 downto 0);
    signal p_factor_res       : std_logic_vector(7 downto 0);
    signal p_factor_aux       : std_logic_vector(7 downto 0);

    signal i_factor_1         : std_logic_vector(7 downto 0);
    signal i_factor_2         : std_logic_vector(7 downto 0);
    signal i_factor_3         : std_logic_vector(7 downto 0);
    signal i_factor_4         : std_logic_vector(7 downto 0);
    signal i_factor_res       : std_logic_vector(7 downto 0);
    signal i_factor_aux       : std_logic_vector(7 downto 0);
    
    signal ought_temp_1       : std_logic_vector(14 downto 0);
    signal ought_temp_2       : std_logic_vector(14 downto 0);
    signal ought_temp_3       : std_logic_vector(14 downto 0);
    signal ought_temp_4       : std_logic_vector(14 downto 0);
    
    signal heater_on_1        : std_logic;
    signal heater_on_2        : std_logic;
    signal heater_on_3        : std_logic;
    signal heater_on_4        : std_logic;
    signal heater_on_res      : std_logic;
    signal heater_on_aux      : std_logic;
    
    signal is_temp_1          : std_logic_vector(14 downto 0);
    signal is_temp_2          : std_logic_vector(14 downto 0);
    signal is_temp_3          : std_logic_vector(14 downto 0);
    signal is_temp_4          : std_logic_vector(14 downto 0);
    
    signal heater_on_1_gated  : std_logic;
    signal heater_on_2_gated  : std_logic;
    signal heater_on_3_gated  : std_logic;
    signal heater_on_4_gated  : std_logic;
    signal heater_on_res_gated: std_logic;
    signal heater_on_aux_gated: std_logic;
        
    signal valve_on           : std_logic;
    signal valve_on_gated     : std_logic;
    signal aux_is_humidity    : std_logic;
    signal aux_is_temp        : std_logic := '1';
    
    signal running_co2_calib  : std_logic;
    signal running_i2c_init   : std_logic;
    
    signal p_factor_co2       : std_logic_vector(7 downto 0);
    signal i_factor_co2       : std_logic_vector(7 downto 0);
    signal p_factor_humidity  : std_logic_vector(7 downto 0);
    signal i_factor_humidity  : std_logic_vector(7 downto 0);
    
    signal ought_co2          : std_logic_vector(15 downto 0);
    signal is_co2             : std_logic_vector(15 downto 0);
    signal co2_concentration_reservoir_buf : std_logic_vector(15 downto 0);
    
    signal ought_humidity     : std_logic_vector(15 downto 0);
    signal is_humidity        : std_logic_vector(15 downto 0);
    signal humidity_reservoir_buf : std_logic_vector(15 downto 0);
    
    signal ought_aux_heater   : std_logic_vector(15 downto 0);
    signal is_aux_heater      : std_logic_vector(15 downto 0);
    
    signal ought_temperature  : std_logic_vector(15 downto 0);
    signal is_temperature     : std_logic_vector(15 downto 0);
    signal temperature_reservoir_buf : std_logic_vector(15 downto 0);
    
    signal DIG_AUX            : std_logic_vector(2 downto 0); -- new since inkube 4.0
    
    signal heater_1           : std_logic_vector(11 downto 0);
    signal heater_2           : std_logic_vector(11 downto 0);
    signal heater_3           : std_logic_vector(11 downto 0);
    signal heater_4           : std_logic_vector(11 downto 0);
    signal heater_res         : std_logic_vector(11 downto 0);
    signal heater_aux         : std_logic_vector(11 downto 0);
    
    signal heater_1_sup       : std_logic_vector(11 downto 0);
    signal heater_2_sup       : std_logic_vector(11 downto 0);
    signal heater_3_sup       : std_logic_vector(11 downto 0);
    signal heater_4_sup       : std_logic_vector(11 downto 0);
    signal heater_res_sup     : std_logic_vector(11 downto 0);
    signal heater_aux_sup     : std_logic_vector(11 downto 0);
    
    signal heater_1_pipe      : std_logic_vector(11 downto 0);
    signal heater_2_pipe      : std_logic_vector(11 downto 0);
    signal heater_3_pipe      : std_logic_vector(11 downto 0);
    signal heater_4_pipe      : std_logic_vector(11 downto 0);
    signal heater_res_pipe    : std_logic_vector(11 downto 0);
    signal heater_aux_pipe    : std_logic_vector(11 downto 0);
    
    signal heater_aux_1       : std_logic_vector(11 downto 0);
    signal heater_aux_2       : std_logic_vector(11 downto 0);
    
    signal spi_cs_bot_buf     : std_logic_vector(3 downto 0);
begin

-- Instantiation of Axi Bus Interface S00_AXI
axi_environment_controller_v1_0_S00_AXI_inst : axi_environment_controller_v1_0_S00_AXI
	generic map (
		C_S_AXI_DATA_WIDTH	=> C_S00_AXI_DATA_WIDTH,
		C_S_AXI_ADDR_WIDTH	=> C_S00_AXI_ADDR_WIDTH
	)
	port map (
		p_factor_1        => p_factor_1,      
        p_factor_2        => p_factor_2,
        p_factor_3        => p_factor_3,
        p_factor_4        => p_factor_4,
        p_factor_res      => p_factor_res,
        p_factor_aux      => p_factor_aux,
        i_factor_1        => i_factor_1,
        i_factor_2        => i_factor_2,
        i_factor_3        => i_factor_3,
        i_factor_4        => i_factor_4,
        i_factor_res      => i_factor_res,
        i_factor_aux      => i_factor_aux,
        ought_temp_1      => ought_temp_1,
        ought_temp_2      => ought_temp_2, 
        ought_temp_3      => ought_temp_3, 
        ought_temp_4      => ought_temp_4,
        heater_on_1       => heater_on_1,
        heater_on_2       => heater_on_2,
        heater_on_3       => heater_on_3,
        heater_on_4       => heater_on_4,
        heater_on_res     => heater_on_res,
        heater_on_aux     => heater_on_aux,
        is_temp_1         => is_temp_1,
        is_temp_2         => is_temp_2, 
        is_temp_3         => is_temp_3, 
        is_temp_4         => is_temp_4,
        valve_on          => valve_on,
        aux_is_humidity   => aux_is_humidity,
        aux_is_temp       => aux_is_temp,
        running_co2_calib => running_co2_calib,
        running_i2c_init  => running_i2c_init,
        p_factor_co2      => p_factor_co2,
        i_factor_co2      => i_factor_co2,
        p_factor_humidity => p_factor_humidity,
        i_factor_humidity => i_factor_humidity,
        ought_co2         => ought_co2,
        is_co2            => is_co2,
        ought_humidity    => ought_humidity,
        is_humidity       => is_humidity,
        ought_aux_heater  => ought_aux_heater,
        is_aux_heater     => is_aux_heater,
        ought_temperature => ought_temperature,
        is_temperature    => is_temperature,
        EN_VCC            => EN_VCC,
        DAUX1             => DAUX1,
        DIG_AUX           => DIG_AUX,
		S_AXI_ACLK	    => s00_axi_aclk,
		S_AXI_ARESETN	=> s00_axi_aresetn,
		S_AXI_AWADDR	=> s00_axi_awaddr,
		S_AXI_AWPROT	=> s00_axi_awprot,
		S_AXI_AWVALID	=> s00_axi_awvalid,
		S_AXI_AWREADY	=> s00_axi_awready,
		S_AXI_WDATA	    => s00_axi_wdata,
		S_AXI_WSTRB	    => s00_axi_wstrb,
		S_AXI_WVALID	=> s00_axi_wvalid,
		S_AXI_WREADY	=> s00_axi_wready,
		S_AXI_BRESP	    => s00_axi_bresp,
		S_AXI_BVALID	=> s00_axi_bvalid,
		S_AXI_BREADY	=> s00_axi_bready,
		S_AXI_ARADDR	=> s00_axi_araddr,
		S_AXI_ARPROT	=> s00_axi_arprot,
		S_AXI_ARVALID	=> s00_axi_arvalid,
		S_AXI_ARREADY	=> s00_axi_arready,
		S_AXI_RDATA	    => s00_axi_rdata,
		S_AXI_RRESP	    => s00_axi_rresp,
		S_AXI_RVALID	=> s00_axi_rvalid,
		S_AXI_RREADY	=> s00_axi_rready
	);

	-- Add user logic here
	
	is_co2         <= co2_concentration_reservoir_buf;
	is_humidity    <= humidity_reservoir_buf;
	is_temperature <= temperature_reservoir_buf;
	
	i2c_interface_instance : i2c_interface port map(
        CLK100MHZ         => s00_axi_aclk,
        
        temperature       => temperature_reservoir_buf,
        humidity          => humidity_reservoir_buf,
        co2_concentration => co2_concentration_reservoir_buf,
        
        sda_in            => sda_in,
        scl_in            => scl_in,
        sda_out           => sda_out,
        scl_out           => scl_out,
        
        calibrate_co2     => calibrate_co2,
            
        running_i2c_init  => running_i2c_init, 
        running_co2_calib => running_co2_calib,
        
        debug_sig         => debug_sig
    );
    co2_concentration_reservoir <= co2_concentration_reservoir_buf;
    humidity_reservoir          <= humidity_reservoir_buf;
    temperature_reservoir       <= temperature_reservoir_buf;
    
    co2_controller_inst : co2_controller port map (
        CLK100MHZ    => s00_axi_aclk,
        
        ought_value  => ought_co2,
        is_value     => co2_concentration_reservoir_buf,
        
        p_factor     => p_factor_co2,
        i_factor     => i_factor_co2,
        
        valve_on     => valve_on_gated,
        valve        => co2_pwm
    );
    valve_on_gated    <= valve_on    and ext_enable;
    
    process(s00_axi_aclk)
    begin
        if rising_edge(s00_axi_aclk) then
            heater_1_sup   <= heater_1_pipe;
            heater_2_sup   <= heater_2_pipe;
            heater_3_sup   <= heater_3_pipe;
            heater_4_sup   <= heater_4_pipe;
            heater_res_sup <= heater_res_pipe;
            heater_aux_sup <= heater_aux_pipe;
        end if;
    end process;
    
    -- The case of "111111111111" that means "heating off" is for these 4 heaters implemented in interface.vhd, as 
    -- these heaters are following a differential approach
    heater_1_pipe <= heater_1;
    heater_2_pipe <= heater_2; 
    heater_3_pipe <= heater_3;
    heater_4_pipe <= heater_4;  
                     
    heater_res_pipe <= "000000000000" when heater_res = "111111111111" else
                       heater_res; 
    heater_aux_pipe <= "000000000000" when heater_aux = "111111111111" else
                       heater_aux; 
    
    spi_cs_bot <= spi_cs_bot_buf;
    
    interface_instance : interface port map (
            CLK100MHZ    => s00_axi_aclk,

            heater_1     => heater_1_sup,
            heater_2     => heater_2_sup,
            heater_3     => heater_3_sup,
            heater_4     => heater_4_sup,
            heater_res   => heater_res_sup,
            heater_aux   => heater_aux_sup,
            
            DIG_AUX      => DIG_AUX,

            temp_1       => is_temp_1,
            temp_2       => is_temp_2,
            temp_3       => is_temp_3,
            temp_4       => is_temp_4,

            spi_clk_pwr  => spi_clk_pwr,
            spi_mosi_pwr => spi_mosi_pwr,
            
            spi_clk_bot  => spi_clk_bot,
            spi_miso_bot => spi_miso_bot,
            spi_mosi_bot => spi_mosi_bot,
            spi_cs_bot   => spi_cs_bot_buf,

            sr_sdi_pwr   => sr_sdi_pwr,
            sr_sclk_pwr  => sr_sclk_pwr,
            sr_latch_pwr => sr_latch_pwr
            );
    
    heater_res_instance : heater_single_sided 
        generic map (DIMENSION => 16, SCALE => 1)
        port map (
            CLK100MHZ    => s00_axi_aclk,
            
            ought_value  => ought_temperature,
            is_value     => is_temperature,
            
            p_factor     => p_factor_res,
            i_factor     => i_factor_res,
            
            heater_on    => heater_on_res_gated,
            heater       => heater_res
        );
    heater_on_res_gated <= heater_on_res and ext_enable;
    
    heater_1_instance : heater
        generic map (DIMENSION => 15, SCALE => 1)
        port map (
            CLK100MHZ    => s00_axi_aclk,
            
            ought_value  => ought_temp_1,
            is_value     => is_temp_1,
            
            p_factor     => p_factor_1,
            i_factor     => i_factor_1,
            
            heater_on    => heater_on_1_gated,
            heater       => heater_1
        );
    heater_on_1_gated <= heater_on_1 and ext_enable;
    temperature_1 <= is_temp_1;
    
    heater_2_instance : heater
        generic map (DIMENSION => 15, SCALE => 1)
        port map (
            CLK100MHZ    => s00_axi_aclk,
            
            ought_value  => ought_temp_2,
            is_value     => is_temp_2,
            
            p_factor     => p_factor_2,
            i_factor     => i_factor_2,
            
            heater_on    => heater_on_2_gated,
            heater       => heater_2
        );
    heater_on_2_gated <= heater_on_2 and ext_enable;
    temperature_2 <= is_temp_2;
    
    heater_3_instance : heater
        generic map (DIMENSION => 15, SCALE => 1)
        port map (
            CLK100MHZ    => s00_axi_aclk,
            
            ought_value  => ought_temp_3,
            is_value     => is_temp_3,
            
            p_factor     => p_factor_3,
            i_factor     => i_factor_3,
            
            heater_on    => heater_on_3_gated,
            heater       => heater_3
        );
    heater_on_3_gated <= heater_on_3 and ext_enable;
    temperature_3 <= is_temp_3;
    
    heater_4_instance : heater
        generic map (DIMENSION => 15, SCALE => 1)
        port map (
            CLK100MHZ    => s00_axi_aclk,
            
            ought_value  => ought_temp_4,
            is_value     => is_temp_4,
            
            p_factor     => p_factor_4,
            i_factor     => i_factor_4,
            
            heater_on    => heater_on_4_gated,
            heater       => heater_4
        );
    heater_on_4_gated <= heater_on_4 and ext_enable;
    temperature_4 <= is_temp_4;
    
    heater_aux_instance : heater_single_sided
        generic map (DIMENSION => 16, SCALE => 1)
        port map (
            CLK100MHZ    => s00_axi_aclk,
            
            ought_value  => ought_aux_heater,
            is_value     => is_aux_heater,
            
            p_factor     => p_factor_aux,
            i_factor     => i_factor_aux,
            
            heater_on    => heater_on_aux_gated,
            heater       => heater_aux_1
        );
    heater_humidity_instance : heater_single_sided
        generic map (DIMENSION => 16, SCALE => 1)
        port map (
            CLK100MHZ    => s00_axi_aclk,
            
            ought_value  => ought_humidity,
            is_value     => is_humidity,
            
            p_factor     => p_factor_humidity,
            i_factor     => i_factor_humidity,
            
            heater_on    => heater_on_aux_gated,
            heater       => heater_aux_2
        );
    heater_on_aux_gated <= heater_on_aux and ext_enable;
    
--    heater_aux <= heater_aux_1;
--    process(s00_axi_aclk)
--    begin
--        if rising_edge(s00_axi_aclk) then
--            if aux_is_temp = '1' then
--                heater_aux <= heater_res;
--            elsif aux_is_humidity = '0' then
--                heater_aux <= heater_aux_1;
--            else
--                heater_aux <= heater_aux_2;
--            end if;
--        end if;
--    end process; 
    heater_aux <= heater_res   when aux_is_temp     = '1' else
                  heater_aux_1 when aux_is_humidity = '0' else
                  heater_aux_2;          
    
	-- User logic ends

end arch_imp;
