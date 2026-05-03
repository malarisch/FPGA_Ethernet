-- Data-storage for ethernet data
-- (c) 2024 Dr.-Ing. Christian Noeding
-- christian@noeding-online.de
-- Released under GNU General Public License v3
-- Source: https://www.github.com/xn--nding-jua/AES50_Transmitter
--
-- This file contains a RAM-module with asynchronuous read/write
-- from/to the DMX512-data. It stores 512 bytes plus start-byte.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity eth_ram is
	generic(
		lastAddress : integer := 1532
	);
	port(
		rx_clk			: in std_logic;
		
		writeAddr		: in unsigned(10 downto 0); -- 0..1531
		data_in			: in std_logic_vector(7 downto 0); -- 8 bit

		sync_in			: in std_logic;

		readAddrPTP		: in unsigned(10 downto 0); -- 0..1531
		readAddrRTP		: in unsigned(10 downto 0); -- 0..1531
		readAddrMCU		: in unsigned(10 downto 0); -- 0..1531
		
		dataOut_sysclk_ptp		: out STD_LOGIC_VECTOR(7 downto 0);
		dataOut_sysclk_rtp		: out STD_LOGIC_VECTOR(7 downto 0);
		dataOut_rxclk			: out STD_LOGIC_VECTOR(7 downto 0);
		
		sync_out			: out std_logic;
		is_mcu_pkt_o	: out std_logic;
		is_ptp_pkt_o	: out std_logic;
		is_rtp_pkt_o	: out std_logic;
		is_mcu_pkt_tog_o	: out std_logic;
		is_ptp_pkt_tog_o	: out std_logic;
		is_rtp_pkt_tog_o	: out std_logic;
		sys_clk_i : in std_logic
	);
end eth_ram;

architecture Behavioral of eth_ram is
	type t_ram is array(lastAddress downto 0) of std_logic_vector(7 downto 0);
	type t_parser_ram is array(38 downto 0) of std_logic_vector(7 downto 0);
	signal ram_ptp: t_ram;
	signal ram_rtp: t_ram;
	signal ram_mcu: t_ram;
	signal ram_parser: t_parser_ram;
	signal pkt_type_msb_sig: STD_LOGIC_VECTOR(7 downto 0);
	signal ip_type_sig: STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
	signal udp_dst_port_sig: STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
	signal processing_stage: integer range 0 to 5;
	signal is_rtp_pkt: std_logic;
	signal is_ptp_pkt: std_logic;
	signal is_mcu_pkt: std_logic;
	signal is_rtp_pkt_tog: std_logic;
	signal is_ptp_pkt_tog: std_logic;
	signal is_mcu_pkt_tog: std_logic;

begin
	-- writing data to ram and synchronous read
	process(rx_clk)
	begin
		if rising_edge(rx_clk) then
			-- write to RAM
			if (writeAddr <= lastAddress) then
				ram_ptp(to_integer(writeAddr)) <= data_in;
				ram_rtp(to_integer(writeAddr)) <= data_in;
				ram_mcu(to_integer(writeAddr)) <= data_in;
			end if;
			if (writeAddr <= 38) then
				ram_parser(to_integer(writeAddr)) <= data_in;
			end if;
			


		end if;
	end process;
	
	-- packet routing
	process (rx_clk)
	begin 
		if rising_edge(rx_clk) then
			processing_stage <= 0;
			sync_out <= '0';
			if (sync_in = '1') then
				pkt_type_msb_sig <= ram_parser(12);
				processing_stage <= 1;
				sync_out <= '1';
			elsif (processing_stage = 0) then
			end if;
			if (processing_stage = 1) then
				sync_out <= '1';
				if ((pkt_type_msb_sig & ram_parser(13)) = x"0800") then -- ipv4
				processing_stage <= 2;
				else 
				processing_stage <= 0;
									is_mcu_pkt_tog <= not is_mcu_pkt_tog;
					is_mcu_pkt <= '1';
					is_ptp_pkt <= '0';
					is_rtp_pkt <= '0';
				end if;
			elsif (processing_stage = 2) then
				sync_out <= '1';
				if (ram_parser(23) = x"11") then -- udp
					processing_stage <= 3;
				else
					-- not an udp packet, jump to mcu fwd
					is_mcu_pkt_tog <= not is_mcu_pkt_tog;
					is_mcu_pkt <= '1';
					is_ptp_pkt <= '0';
					is_rtp_pkt <= '0';
					processing_stage <= 0;
				end if;
			elsif (processing_stage = 3) then -- process udp
				udp_dst_port_sig(15 downto 8) <= ram_parser(36); -- udp lenght
				processing_stage <= 4;
			elsif (processing_stage = 4) then 
				udp_dst_port_sig(7 downto 0) <= ram_parser(37);
				processing_stage <= 5;
			elsif (processing_stage = 5) then
				is_mcu_pkt <= '0';
				is_ptp_pkt <= '0';
				is_rtp_pkt <= '0';
				if unsigned(udp_dst_port_sig) = 319 or unsigned(udp_dst_port_sig) = 320 then
					is_ptp_pkt <= '1';
					is_ptp_pkt_tog <= not is_ptp_pkt_tog;
				elsif (unsigned(udp_dst_port_sig) = 5004) then
					is_rtp_pkt <= '1';
					is_rtp_pkt_tog <= not is_rtp_pkt_tog;
				else 
					is_mcu_pkt <= '1';
					is_mcu_pkt_tog <= not is_mcu_pkt_tog;
				end if;
				processing_stage <= 0;
			end if;

		end if;

	end process;

	is_mcu_pkt_o <= is_mcu_pkt;
	is_ptp_pkt_o <= is_ptp_pkt;
	is_rtp_pkt_o <= is_rtp_pkt;
	is_mcu_pkt_tog_o <= is_mcu_pkt_tog;
	is_ptp_pkt_tog_o <= is_ptp_pkt_tog;
	is_rtp_pkt_tog_o <= is_rtp_pkt_tog;
    process (sys_clk_i)
    begin
        if rising_edge(sys_clk_i) then
            dataOut_sysclk_ptp <= ram_ptp(to_integer(readAddrPTP));
            dataOut_sysclk_rtp <= ram_rtp(to_integer(readAddrRTP));
        end if;
    end process;
    process (rx_clk)
    begin
        if rising_edge(sys_clk_i) then
            dataOut_rxclk <= ram_mcu(to_integer(readAddrMCU));
        end if;
    end process;

end Behavioral;
