-- Ethernet Packet Receiver
-- (c) 2025 Dr.-Ing. Christian Noeding
-- christian@noeding-online.de
-- Released under GNU General Public License v3
-- Source: https://www.github.com/xn--nding-jua/AES50_Transmitter
--
-- This file contains an ethernet-packet-receiver to receives individual bytes from a FIFO.

library ieee;
use ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.ALL;

entity ethernet_receive is 
	generic(
		lastRamAddress : integer := 1500 -- more entries will use lots of FPGA-ressources. Better use a dedicated SD-RAM here instead
	);
	port
	(
		rx_clk				: in std_logic;
		rx_frame				: in std_logic; -- start of packet (we are ignoring this as we wait until we have the FIFO filled with a full frame
		rx_data				: in std_logic_vector(7 downto 0); -- data-octet
		rx_byte_received	: in std_logic;
		rx_error				: in std_logic;

		ram_addr				: out unsigned(10 downto 0); -- 11 bit to store one full fifo
		ram_data				: out std_logic_vector(7 downto 0);
		frame_rdy			: out std_logic; -- ready
		rx_byte_count		: out unsigned(10 downto 0);

	
		is_mcu_pkt_tog_o	: out std_logic;
		is_ptp_pkt_tog_o	: out std_logic;
		is_rtp_pkt_tog_o	: out std_logic
	);
end entity;

architecture Behavioral of ethernet_receive is
	type t_SM_Ethernet is (s_Idle, s_Read, s_FrameRdy, s_Done);
	signal s_SM_Ethernet : t_SM_Ethernet := s_Idle;
	signal ram_ptr 		: integer range 0 to 2000 := 0; -- we expecting not more than 2^11 bytes per frame
	signal udp_port_sig : std_logic_vector(15 downto 0);
	signal is_ipv4		: std_logic;
	signal is_udp		: std_logic;
	signal is_rtp_pkt_tog: std_logic;
	signal is_ptp_pkt_tog: std_logic;
	signal is_mcu_pkt_tog: std_logic;
begin
	process (rx_clk)
	begin
		if (rising_edge(rx_clk)) then
			if (s_SM_Ethernet = s_Idle) then
				is_ipv4 <= '0';
				is_udp <= '0';
				udp_port_sig <= (others => '0');
				if ((rx_frame = '1') and (rx_error = '0')) then
					-- prepare receiving new ethernet-frame into RAM
					-- IMPORTANT: Also capture first byte immediately if available
					if (rx_byte_received = '1') then
						ram_addr <= to_unsigned(0, 11);
						ram_data <= rx_data;
						ram_ptr <= 1;  -- first byte already stored
					else
						ram_ptr <= 0;
					end if;

					s_SM_Ethernet <= s_Read;
				end if;
				
			elsif (s_SM_Ethernet = s_Read) then
				if (rx_error = '0') then
					if (rx_frame = '1') then
						if (rx_byte_received = '1') then
							-- we received a valid byte
							if (ram_ptr <= lastRamAddress) then
								ram_addr <= to_unsigned(ram_ptr, 11);
								ram_data <= rx_data;
							else
								-- dont store received byte into ram as data is out of ram-size
								-- we can store only "lastRamAddress" bytes
							end if;

							ram_ptr <= ram_ptr + 1;
							if ram_ptr = 12 and rx_data = x"08" then
								is_ipv4 <= '1';
							end if;
							if ram_ptr = 13 then
								if rx_data = x"00" and is_ipv4 = '1' then
									is_ipv4 <= '1';
								else
									is_ipv4 <= '0';
								end if;
							end if;
							if (ram_ptr = 23 and rx_data = x"11") then
								is_udp <= '1';
							end if;
							if (ram_ptr = 36) then
								udp_port_sig(15 downto 8 ) <= rx_data;
							elsif (ram_ptr = 37) then
								udp_port_sig(7 downto 0 ) <= rx_data;
							end if;
							if (is_ipv4 = '1' and is_udp = '1' and ram_ptr = 60) then
								if (unsigned(udp_port_sig) = 319 or unsigned(udp_port_sig) = 320) then
									-- ptp packet
									is_ptp_pkt_tog <= not is_ptp_pkt_tog;
									is_mcu_pkt_tog <= not is_mcu_pkt_tog; -- not used, mcu needs packet length, we do not know yet

								elsif (unsigned(udp_port_sig) = 5004 and ram_ptr = 60) then
									-- rtp
									is_rtp_pkt_tog <= not is_rtp_pkt_tog;
								end if;
							else
								is_mcu_pkt_tog <= not is_mcu_pkt_tog;

							end if;
						else
							-- data not valid -> just wait until rx_byte_received is reached
							-- during this we keep the values on ram_addr and ram_data
							-- so we can keep the RAM clocked by the rx_clock without a WriteEnable-signal
						end if;
					else
						-- end of frame
						s_SM_Ethernet <= s_FrameRdy;
					end if;
				else
					-- an error occured
					s_SM_Ethernet <= s_Done;
				end if;

			elsif (s_SM_Ethernet = s_FrameRdy) then
				-- set signal, that frame in RAM is completed
				rx_byte_count <= to_unsigned(ram_ptr, 11);
				frame_rdy <= '1';
				
				s_SM_Ethernet <= s_Done;

			elsif (s_SM_Ethernet = s_Done) then
				frame_rdy <= '0';
				ram_ptr <= 0;
				s_SM_Ethernet <= s_Idle;
				
			end if;
		end if;
	end process;
	is_mcu_pkt_tog_o <= is_mcu_pkt_tog;
	is_ptp_pkt_tog_o <= is_ptp_pkt_tog;
	is_rtp_pkt_tog_o <= is_rtp_pkt_tog;
end Behavioral;