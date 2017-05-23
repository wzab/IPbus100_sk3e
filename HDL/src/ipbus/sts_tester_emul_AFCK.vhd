-- Top-level design STS-XYTER tester with STS-XYTER emulator 
--
-- Based on IPbus top level entity by
-- Dave Newbold, 16/7/12
--
-- This file was significantly modified by W.M.Zabolotny
-- (wzab<at>ise.pw.edu.pl)
-- To allow operation with light free MAC replacement.
-- Modifications were associated only with adding two pins:
-- phy_mdio (set to 'Z')
-- phy_mdc (set to '0')
-- Additionally phy_rstb was connected to 'locked' signal to
-- ensure reset of phy

library IEEE;
use IEEE.STD_LOGIC_1164.all;
use ieee.numeric_std.all;
library unisim;
use unisim.vcomponents.all;
use work.ipbus.all;
use work.sts_interface_ctrl_pkg.all;

entity top is port(
  sysclk_p, sysclk_n : in    std_logic;
  --leds               : out   std_logic_vector(3 downto 0);
  led1               : out   std_logic;
  led2               : out   std_logic;
  gt_clkp, gt_clkn   : in    std_logic;
  gt_txp, gt_txn     : out   std_logic;
  gt_rxp, gt_rxn     : in    std_logic;
  --gt_sfp_disable     : out   std_logic;
  --dip_switch: in std_logic_vector(3 downto 0)
  -- FMC cable interface, DPB side
  dpb_sout_pin_p     : out   std_logic;
  dpb_sout_pin_n     : out   std_logic;
  dpb_sin_pin_p      : in    std_logic_vector(4 downto 0);
  dpb_sin_pin_n      : in    std_logic_vector(4 downto 0);
  dpb_clk_pin_p      : out   std_logic;
  dpb_clk_pin_n      : out   std_logic;
  -- FMC cable interface STS side
  sts_sout_pin_p     : in    std_logic;
  sts_sout_pin_n     : in    std_logic;
  sts_sin_pin_p      : out   std_logic_vector(4 downto 0);
  sts_sin_pin_n      : out   std_logic_vector(4 downto 0);
  sts_clk_pin_p      : in    std_logic;
  sts_clk_pin_n      : in    std_logic;
  -- FMC direction control
  ser_in1            : out   std_logic;
  ser_latch1         : out   std_logic;
  ser_clk1           : out   std_logic;
  ser_in2            : out   std_logic;
  ser_latch2         : out   std_logic;
  ser_clk2           : out   std_logic;
  -- I2C
  clk_updaten        : out   std_logic;
  si570_oe           : out   std_logic;
  boot_clk           : in    std_logic;
  scl                : inout std_logic;
  sda                : inout std_logic
  );
end top;

architecture rtl of top is

  signal clk125, clk125_out, clk200, ipb_clk, rst_125, rst_ipb, onehz                                   : std_logic;
  signal mac_tx_data, mac_rx_data                                                                       : std_logic_vector(7 downto 0);
  signal mac_tx_valid, mac_tx_last, mac_tx_error, mac_tx_ready, mac_rx_valid, mac_rx_last, mac_rx_error : std_logic;
  signal ipb_master_out                                                                                 : ipb_wbus;
  signal ipb_master_in                                                                                  : ipb_rbus;
  signal mac_addr                                                                                       : std_logic_vector(47 downto 0);
  signal ip_addr                                                                                        : std_logic_vector(31 downto 0);
  signal pkt_rx, pkt_tx, pkt_rx_led, pkt_tx_led                                                         : std_logic;

  signal daddr                                                                                          : std_logic_vector(6 downto 0);
  signal phase_in                                                                                       : std_logic_vector(8 downto 0);
  signal in_delay_set                                                                                   : std_logic_vector(5 downto 0);
  signal result, strobe, clk_320, clk_160, sysclk                                                       : std_logic;
  signal den, drdy, drst, dwe, test_ena, test_din, ready, test_dta, rst_p, rst_n, in_locked, reg_locked : std_logic;
  signal din, dout                                                                                      : std_logic_vector(15 downto 0);
  signal s_led1, s_led2                                                                                 : std_logic := '0';
  signal cnt_l1, cnt_l2                                                                                 : integer   := 0;
  signal status_o                                                                                       : std_logic_vector(15 downto 0);
  signal sys_rst, locked, eth_locked                                                                    : std_logic_vector(0 to 0);

-- Signals used to communicate with the core from IPbus
  signal din_delays        : T_DEL_ADJUST_VEC(N_OF_LINKS-1 downto 0);
  signal din_delays_locked : std_logic_vector(N_OF_LINKS-1 downto 0);
  signal clk_delay         : T_DEL_CLK_ADJ;
  signal clk_delay_strobe  : std_logic;
  signal clk_delay_ready   : std_logic;
  signal clk_delay_locked  : std_logic;
  signal enc_mode          : std_logic_vector(1 downto 0);
  signal seq_det_ins       : T_SEQ_DET_IN_VEC(N_OF_LINKS-1 downto 0);
  signal seq_det_outs      : T_SEQ_DET_OUT_VEC(N_OF_LINKS-1 downto 0);

  signal sts_sout, sts_clk, sts_clk_ddr : std_logic;
  signal sts_sin                        : std_logic_vector(N_OF_LINKS-1 downto 0);

  signal sts_sout_pin                   : std_logic;
  signal sts_sin_pin, link_break        : std_logic_vector(4 downto 0);
  signal sts_clk_pin, sts_clk_pin_unbuf : std_logic;
  signal sts_rst_n                      : std_logic;

  signal fdirs1, fdirs2 : std_logic_vector(7 downto 0);
  -- Signals used to service commands
  signal dwnl_cmds      : T_DWNL_CMDS := (others => (others => '0'));
  signal cmds_stat      : T_CMD_STATS := (others => (others => '0'));
  signal dwnl_cmd_wr    : std_logic_vector(N_CMD_SLOTS-1 downto 0);

  -- Signals used for hit data FIFO
  signal hit_data : std_logic_vector(23 downto 0);
  signal hit_rd   : std_logic;
  signal hit_av   : std_logic;
  signal hit_full : std_logic;

  component stsxyter_dig
    port (
      clk        : in  std_logic;
      rst_n      : in  std_logic;
      serial_in  : in  std_logic;
      chip_addr  : in  std_logic_vector(3 downto 0);
      serial_out : out std_logic_vector(4 downto 0)
      );
  end component;


begin

  --gt_sfp_disable <= '0';
  clk_updaten <= '1';
  si570_oe    <= '1';
--      DCM clock generation for internal bus, ethernet

  ibufgds0 : IBUFGDS port map(
    i  => sysclk_p,
    ib => sysclk_n,
    o  => sysclk
    );

  clocks : entity work.clocks_7s_extphy
    port map(
      sysclk   => sysclk,
      clko_125 => clk125,
      clko_200 => clk200,
      clko_ipb => ipb_clk,
      locked   => locked(0),
      nuke     => sys_rst(0),
      rsto_125 => rst_125,
      rsto_ipb => rst_ipb,
      onehz    => onehz
      );

  rst_n <= locked(0);
  --leds <= (pkt_rx_led, pkt_tx_led, locked, onehz);
  --leds  <= (led1, led2, locked, onehz);

--      Ethernet MAC core and PHY interface
-- In this version, consists of hard MAC core and GMII interface to external PHY
-- Can be replaced by any other MAC / PHY combination
  eth_7s_1000basex_1 : entity work.eth_7s_1000basex
    port map (
      clk2        => clk200,
      gt_clkp     => gt_clkp,
      gt_clkn     => gt_clkn,
      gt_txp      => gt_txp,
      gt_txn      => gt_txn,
      gt_rxp      => gt_rxp,
      gt_rxn      => gt_rxn,
      clk125_out  => clk125_out,
      rsti        => sys_rst(0),
      locked      => eth_locked(0),
      tx_data     => mac_tx_data,
      tx_valid    => mac_tx_valid,
      tx_last     => mac_tx_last,
      tx_error    => mac_tx_error,
      tx_ready    => mac_tx_ready,
      rx_data     => mac_rx_data,
      rx_valid    => mac_rx_valid,
      rx_last     => mac_rx_last,
      rx_error    => mac_rx_error,
      status_o    => status_o,
      hostbus_in  => open,
      hostbus_out => open);

-- ipbus control logic

  ipbus : entity work.ipbus_ctrl
    port map(
      mac_clk      => clk125_out,
      rst_macclk   => rst_125,
      ipb_clk      => ipb_clk,
      rst_ipb      => rst_ipb,
      mac_rx_data  => mac_rx_data,
      mac_rx_valid => mac_rx_valid,
      mac_rx_last  => mac_rx_last,
      mac_rx_error => mac_rx_error,
      mac_tx_data  => mac_tx_data,
      mac_tx_valid => mac_tx_valid,
      mac_tx_last  => mac_tx_last,
      mac_tx_error => mac_tx_error,
      mac_tx_ready => mac_tx_ready,
      ipb_out      => ipb_master_out,
      ipb_in       => ipb_master_in,
      mac_addr     => mac_addr,
      ip_addr      => ip_addr,
      pkt_rx       => pkt_rx,
      pkt_tx       => pkt_tx,
      pkt_rx_led   => pkt_rx_led,
      pkt_tx_led   => pkt_tx_led
      );

  mac_addr <= X"020ddba11598";  -- Careful here, arbitrary addresses do not always work
  ip_addr  <= X"c0a80008";              -- 192.168.0.8

-- ipbus slaves live in the entity below, and can expose top-level ports
-- The ipbus fabric is instantiated within.

  slaves : entity work.slaves port map(
    ipb_clk           => ipb_clk,
    ipb_rst           => rst_ipb,
    ipb_in            => ipb_master_out,
    ipb_out           => ipb_master_in,
    rst_out           => open,
    -- Signals which are handled on the top level
    sts_rst_n         => sts_rst_n,
    din_delays        => din_delays,
    din_delays_locked => din_delays_locked,
    clk_delay         => clk_delay,
    clk_delay_strobe  => clk_delay_strobe,
    clk_delay_ready   => clk_delay_ready,
    clk_delay_locked  => clk_delay_locked,
    enc_mode          => enc_mode,
    seq_det_ins       => seq_det_ins,
    seq_det_outs      => seq_det_outs,
    dwnl_cmds         => dwnl_cmds,
    cmds_stat         => cmds_stat,
    dwnl_cmd_wr       => dwnl_cmd_wr,
    hit_data          => hit_data,
    hit_av            => hit_av,
    hit_rd            => hit_rd,
    hit_full          => hit_full,
    test_ena          => test_ena,
    link_break        => link_break
    );

  -- User part

  sts_interface_core_1 : entity work.sts_interface_core
    port map (
      sts_clk           => sts_clk,
      sts_sout          => sts_sout,
      sts_sin_n         => dpb_sin_pin_n,
      sts_sin_p         => dpb_sin_pin_p,
      link_break        => link_break,
      din_delays        => din_delays,
      din_delays_locked => din_delays_locked,
      clk_delay         => clk_delay,
      clk_delay_strobe  => clk_delay_strobe,
      clk_delay_ready   => clk_delay_ready,
      clk_delay_locked  => clk_delay_locked,
      enc_mode          => enc_mode,
      seq_det_ins       => seq_det_ins,
      seq_det_outs      => seq_det_outs,
      dwnl_cmds         => dwnl_cmds,
      cmds_stat         => cmds_stat,
      dwnl_cmd_wr       => dwnl_cmd_wr,
      hit_data          => hit_data,
      hit_av            => hit_av,
      hit_rd            => hit_rd,
      hit_full          => hit_full,
      ipb_clk           => ipb_clk,
      clk_160           => clk_160,
      clk_320           => clk_320,
      clk_200           => clk200,
      rst_p             => rst_p);

  bo1 : OBUFDS
    port map (
      I  => sts_sout,
      O  => dpb_sout_pin_p,
      OB => dpb_sout_pin_n);
  bi1 : IBUFDS
    port map (
      I  => sts_sout_pin_p,
      IB => sts_sout_pin_n,
      O  => sts_sout_pin);

  bd2 : ODDR
    port map (
      D1 => '0',
      D2 => '1',
      CE => '1',
      C  => sts_clk,
      Q  => sts_clk_ddr
      );

  bo2 : OBUFDS
    port map (
      I  => sts_clk_ddr,
      O  => dpb_clk_pin_p,
      OB => dpb_clk_pin_n);

  bi2 : IBUFDS
    port map (
      I  => sts_clk_pin_p,
      IB => sts_clk_pin_n,
      O  => sts_clk_pin_unbuf);

  cbg1 : BUFG
    port map (
      I => sts_clk_pin_unbuf,
      O => sts_clk_pin);

  bg1 : for i in 0 to N_OF_LINKS-1 generate
    --bog : IBUFDS
    --  port map (
    --    O  => sts_sin_pin(i),
    --    I  => dpb_sin_pin_p(i),
    --    IB => dpb_sin_pin_n(i));

    big : OBUFDS
      port map (
        O  => sts_sin_pin_p(i),
        OB => sts_sin_pin_n(i),
        I  => sts_sin(i));
  end generate bg1;

  -- STS XYTER instantiation
  stsxyter_dig_1 : entity work.stsxyter_wrap
    port map (
      clk        => sts_clk_pin,
      rst_n      => '1',                -- Removed reset, was: sts_rst_n,
      serial_in  => sts_sout_pin,
      serial_out => sts_sin);

  rst_p <= not rst_n;
  -- Monitoring probes
  vio_2_1 : entity work.vio_2
    port map (
      clk        => boot_clk,
      probe_in0  => status_o,
      probe_in1  => locked,
      probe_in2  => eth_locked,
      probe_out0 => sys_rst);

  -- JTAG<->I2C part for clock-crossbar
  i2c_vio_ctrl_1 : entity work.i2c_vio_ctrl
    port map (
      clk => boot_clk,
      scl => scl,
      sda => sda);

  -- FMC cable direction controllers
  -- We must consider, that directions of lines
  -- Are transmitted in changed order
  -- For 8 lines, directions must be defined in order:
  --        "10325476"
  fdirs2 <= "01101111";
  fdirs1 <= "11010000";
  --fdirs1 <= "10010000";
  --fdirs2 <= "00101111";
  dir_switch_1 : entity work.dir_switch
    generic map (
      CHAIN_LEN => 8)
    port map (
      clk   => boot_clk,
      rst_p => rst_p,
      dirs  => fdirs1,
      ser   => ser_in1,
      srclk => ser_clk1,
      rclk  => ser_latch1);

  dir_switch_2 : entity work.dir_switch
    generic map (
      CHAIN_LEN => 8)
    port map (
      clk   => boot_clk,
      rst_p => rst_p,
      dirs  => fdirs2,
      ser   => ser_in2,
      srclk => ser_clk2,
      rclk  => ser_latch2);

  -- Led 1
  l1 : process (clk_160, rst_n) is
  begin  -- process l1
    if rst_n = '0' then                 -- asynchronous reset (active low)
      cnt_l1 <= 0;
      s_led1 <= '0';
    elsif clk_160'event and clk_160 = '1' then  -- rising clock edge
      if cnt_l1 = 80000000 then
        s_led1 <= not s_led1;
        cnt_l1 <= 0;
      else
        cnt_l1 <= cnt_l1+1;
      end if;
    end if;
  end process l1;
  led1 <= s_led1;
  led2 <= s_led2;
  -- Led 2
  l2 : process (rst_n, sts_clk) is
  begin  -- process l2
    if rst_n = '0' then                 -- asynchronous reset (active low)
      cnt_l2 <= 0;
      s_led2 <= '0';
    elsif sts_clk'event and sts_clk = '1' then  -- rising clock edge
      if cnt_l2 = 80000000 then
        s_led2 <= not s_led2;
        cnt_l2 <= 0;
      else
        cnt_l2 <= cnt_l2+1;
      end if;
    end if;
  end process l2;

end rtl;

