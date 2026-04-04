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

entity ethernet_packet_parser is
	generic(
		udp_port_ptpv2_event : integer := 319;
		udp_port_ptpv2_general : integer := 320;
		udp_port_rtp : integer := 5004
	);
	port
	(
		clk						: in std_logic;


		pkt_type					: in std_logic_vector(15 downto 0); -- valid for all MAC-packets
		ip_type					: in std_logic_vector(7 downto 0);  -- valid for all IP-packeges
		udp_src_port			: in unsigned(15 downto 0); -- only valid for UDP packages
		udp_dst_port			: in unsigned(15 downto 0); -- only valid for UDP packages
		udp_length				: in unsigned(15 downto 0); -- only valid for UDP packages

		ram_data					: in std_logic_vector(7 downto 0);

		sync_in					: in std_logic;


		ram_read_address		: out unsigned(10 downto 0);

		parse_ptp_packet		: out std_logic;
		parse_rtp_packet		: out std_logic; -- Toggle: changes state on each new RTP packet
		parse_mcu_packet		: out std_logic  -- packet destined for MCU (everything except RTP audio)
	);
end entity;

architecture Behavioral of ethernet_packet_parser is
	type t_SM_PacketParser is (s_Idle, s_ProcessUdpPacket, s_UnexpectedPacket, s_Done);
	signal s_SM_PacketParser : t_SM_PacketParser := s_Idle;




	-- Toggle signal for CDC-safe RTP packet notification.
	-- Toggles once per RTP packet so the receiving clock domain can
	-- detect every event regardless of the phase relationship between
	-- the two asynchronous 125 MHz clocks (Gigabit RGMII).
	signal rtp_toggle				: std_logic := '0';

	-- Local flag: was this packet RTP? Used only for MCU-forwarding decision in s_Done.
	signal is_rtp					: std_logic := '0';
begin
	-- Drive the output continuously from the toggle register
	parse_rtp_packet <= rtp_toggle;

	process (clk)
	begin
		if (rising_edge(clk)) then
			if ((sync_in = '1') and (s_SM_PacketParser = s_Idle)) then
				-- a new frame has arrived


				parse_ptp_packet <= '0';
				is_rtp <= '0';
				parse_mcu_packet <= '0';
				-- check packet type
				if (pkt_type = x"0800") then
					-- we received IP packet
					if (ip_type = x"11") then
						-- we received an UDP packet
						ram_read_address <= to_unsigned(42, 11); -- load ram-pointer to first payload-byte
						s_SM_PacketParser <= s_ProcessUdpPacket;
					else
						-- no UDP packet
						s_SM_PacketParser <= s_UnexpectedPacket;
					end if;

				
				else
					-- we received unsupported packet
					s_SM_PacketParser <= s_UnexpectedPacket;
				end if;

			elsif (s_SM_PacketParser = s_ProcessUdpPacket) then
				-- do something with the new data
				-- udp_src_port
				-- udp_dst_port
				-- udp_length
				if (udp_dst_port = udp_port_ptpv2_event OR udp_dst_port = udp_port_ptpv2_general) then
					-- PTPv2 Event Messages (e.g., Sync, Delay_Req)
					-- handle PTPv2 event messages here
					parse_ptp_packet <= '1';
					s_SM_PacketParser <= s_Done;
				elsif (udp_dst_port = udp_port_rtp) then
					-- RTP audio packet (AES67)
					-- Toggle for CDC-safe notification to sys_clk domain
					rtp_toggle <= not rtp_toggle;
					is_rtp <= '1';
					s_SM_PacketParser <= s_Done;
				else
					-- unexpected destination-port
					s_SM_PacketParser <= s_UnexpectedPacket;
				end if;

			
			elsif (s_SM_PacketParser = s_UnexpectedPacket) then
				-- unknown packet type -> forward to MCU
				parse_mcu_packet <= '1';
				s_SM_PacketParser <= s_Idle;

			elsif (s_SM_PacketParser = s_Done) then
				-- everything is done successfully
				-- forward all non-RTP packets to MCU
				if (is_rtp = '0') then
					parse_mcu_packet <= '1';
				end if;
				s_SM_PacketParser <= s_Idle;

			end if;
		end if;
	end process;
end Behavioral;
