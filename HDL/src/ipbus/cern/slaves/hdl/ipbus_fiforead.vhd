-- Generic FIFO reading block
-- Written by W.M. Zabolotny 29.02.2016
--
library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.numeric_std.all;
use work.ipbus.all;

entity ipbus_fiforead is
  generic (
    FIFO_DATA_WIDTH : integer := 24);
  port(
    clk       : in  std_logic;
    reset     : in  std_logic;
    ipbus_in  : in  ipb_wbus;
    ipbus_out : out ipb_rbus;
    fifo_out  : in  std_logic_vector(FIFO_DATA_WIDTH-1 downto 0);
    fifo_av   : in  std_logic;
    fifo_full : in  std_logic;
    fifo_rd   : out std_logic
    );

end ipbus_fiforead;

architecture rtl of ipbus_fiforead is

signal ack:std_logic;

begin

  p1 : process(fifo_av, fifo_full, fifo_out)
  begin
    ipbus_out.ipb_rdata              <= (others => '0');
    ipbus_out.ipb_rdata(FIFO_DATA_WIDTH-1 downto 0) <= fifo_out;
    ipbus_out.ipb_rdata(31)          <= not fifo_av;
    ipbus_out.ipb_rdata(30)          <= fifo_full;
  end process p1;

  -- If this is a read access, we confirm it immediately
  ack <= '1' when ipbus_in.ipb_strobe = '1' and ipbus_in.ipb_write = '0'
                       else '0';
  ipbus_out.ipb_err <= '0';
  fifo_rd           <= '1' when ack = '1' and fifo_av = '1'
                       else '0';

  ipbus_out.ipb_ack <= ack;

end rtl;
