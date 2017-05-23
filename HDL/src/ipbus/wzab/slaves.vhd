-- The ipbus slaves live in this entity - modify according to requirements
--
-- Ports can be added to give ipbus slaves access to the chip top level.
-- Written by Wojciech M. Zabolotny (wzab@ise.pw.edu.pl)
-- Based template slaves.vhd prepared by:
-- Dave Newbold, February 2011

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.numeric_std.all;
use work.ipbus.all;
use work.ipbus_reg_types.all;

entity slaves is
  port(
    ipb_clk           : in  std_logic;
    ipb_rst           : in  std_logic;
    ipb_in            : in  ipb_wbus;
    ipb_out           : out ipb_rbus;
    -- Portd used to communicate with the core
    buttons : in std_logic_vector(3 downto 0);
    leds : out std_logic_vector(7 downto 0)
    );

end slaves;

architecture rtl of slaves is

  constant NSLV   : positive := 1;
  constant N_CTRL : positive := 1;
  constant N_STAT : positive := 2;

  signal ipbw               : ipb_wbus_array(NSLV-1 downto 0);
  signal ipbr, ipbr_d       : ipb_rbus_array(NSLV-1 downto 0);
  signal rst_reg            : std_logic_vector(31 downto 0);
  signal ctrl_reg           : ipb_reg_v(N_CTRL-1 downto 0);
  signal stat_reg           : ipb_reg_v(N_STAT-1 downto 0);
  constant id_number        : std_logic_vector(31 downto 0) := x"abcdfedd";

begin

  fabric : entity work.ipbus_fabric
    generic map(NSLV => NSLV)
    port map(
      ipb_in          => ipb_in,
      ipb_out         => ipb_out,
      ipb_to_slaves   => ipbw,
      ipb_from_slaves => ipbr
      );

-- Slave 0: id / rst reg

  slave0 : entity work.ipbus_ctrlreg_v
    generic map (
      N_CTRL => N_CTRL,
      N_STAT => N_STAT)
    port map (
      clk       => ipb_clk,
      reset     => ipb_rst,
      ipbus_in  => ipbw(0),
      ipbus_out => ipbr(0),
      d         => stat_reg,
      q         => ctrl_reg,
      stb       => open);

  -- Assignment of signals
  stat_reg(0) <= id_number;
  stat_reg(1)(31 downto 4) <= (others => '0');
  stat_reg(1)(3 downto 0) <= buttons;
  leds                    <= ctrl_reg(0)(7 downto 0);

end rtl;
