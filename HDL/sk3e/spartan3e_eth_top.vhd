-------------------------------------------------------------------------------
-- Title      : L3 FADE protocol demo for Spartan-3E Starter Kit board
-- Project    : 
-------------------------------------------------------------------------------
-- File       : spartan3e_eth_top.vhd
-- Author     : Wojciech M. Zabolotny <wzab@ise.pw.edu.pl>
-- Company    : 
-- Created    : 2007-12-31
-- Last update: 2017-05-23
-- Platform   : 
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description:
-- This file implements a simple entity with JTAG driven internal bus
-- allowing to control LEDs, read buttons, set two registers
-- and to read results of simple arithmetical operations
-------------------------------------------------------------------------------
-- Copyright (c) 2010
-- This is public domain code!!!
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2010-08-03  1.0      wzab    Created
-------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.ipbus.all;
use work.ipbus_trans_decl.all;
use work.emac_hostbus_decl.all;

library unisim;
use unisim.vcomponents.all;

entity spart3e_sk_eth is
  port(CLK_50MHZ     : in  std_logic;
       RS232_DCE_RXD : in  std_logic;
       RS232_DCE_TXD : out std_logic;

       SD_CK_P : out std_logic;         --DDR SDRAM clock_positive
       SD_CK_N : out std_logic;         --clock_negative
       SD_CKE  : out std_logic;         --clock_enable

       SD_BA  : out std_logic_vector(1 downto 0);   --bank_address
       SD_A   : out std_logic_vector(12 downto 0);  --address(row or col)
       SD_CS  : out std_logic;                      --chip_select
       SD_RAS : out std_logic;                      --row_address_strobe
       SD_CAS : out std_logic;                      --column_address_strobe
       SD_WE  : out std_logic;                      --write_enable

       SD_DQ   : inout std_logic_vector(15 downto 0);  --data
       SD_UDM  : out   std_logic;                      --upper_byte_enable
       SD_UDQS : inout std_logic;                      --upper_data_strobe
       SD_LDM  : out   std_logic;                      --low_byte_enable
       SD_LDQS : inout std_logic;                      --low_data_strobe

       E_MDC    : out   std_logic;      --Ethernet PHY
       E_MDIO   : inout std_logic;      --management data in/out
       E_COL    : in    std_logic;
       E_CRS    : in    std_logic;
       E_RX_CLK : in    std_logic;      --receive clock
       E_RX_ER  : in    std_logic;      --receive error
       E_RX_DV  : in    std_logic;      --data valid
       E_RXD    : in    std_logic_vector(3 downto 0);
       E_TX_CLK : in    std_logic;      --transmit clock
       E_TX_EN  : out   std_logic;      --data valid
       E_TX_ER  : out   std_logic;      --transmit error
       E_TXD    : out   std_logic_vector(3 downto 0);

       SF_CE0   : out   std_logic;      --NOR flash
       SF_OE    : out   std_logic;
       SF_WE    : out   std_logic;
       SF_BYTE  : out   std_logic;
       SF_STS   : in    std_logic;      --status
       SF_A     : out   std_logic_vector(24 downto 0);
       SF_D     : inout std_logic_vector(15 downto 1);
       SPI_MISO : inout std_logic;

       CDC_MCK        : out std_logic;
       CDC_CSn        : out std_logic;
       CDC_SDIN       : out std_logic;
       CDC_SCLK       : out std_logic;
       CDC_DIN        : out std_logic;
       CDC_BCLK       : out std_logic;
       --CDC_CLKOUT                : in  std_logic;
       CDC_DOUT       : in  std_logic;
       CDC_LRC_IN_OUT : out std_logic;

       VGA_VSYNC : out std_logic;       --VGA port
       VGA_HSYNC : out std_logic;
       VGA_RED   : out std_logic;
       VGA_GREEN : out std_logic;
       VGA_BLUE  : out std_logic;

       PS2_CLK  : in std_logic;         --Keyboard
       PS2_DATA : in std_logic;

       LED        : out std_logic_vector(7 downto 0);
       ROT_CENTER : in  std_logic;
       ROT_A      : in  std_logic;
       ROT_B      : in  std_logic;
       BTN_EAST   : in  std_logic;
       BTN_NORTH  : in  std_logic;
       BTN_SOUTH  : in  std_logic;
       BTN_WEST   : in  std_logic;
       SW         : in  std_logic_vector(3 downto 0));

end spart3e_sk_eth;

architecture beh of spart3e_sk_eth is

  signal my_mac          : std_logic_vector(47 downto 0);
  constant my_ether_type : std_logic_vector(15 downto 0) := x"fade";
  signal transm_delay    : unsigned(31 downto 0);
  signal restart         : std_logic;
  signal dbg             : std_logic_vector(3 downto 0);
  signal dta             : std_logic_vector(31 downto 0);
  signal dta_we          : std_logic                     := '0';
  signal dta_ready       : std_logic;
  signal snd_start       : std_logic;
  signal snd_ready       : std_logic;
  signal dmem_addr       : std_logic_vector(13 downto 0);
  signal dmem_dta        : std_logic_vector(31 downto 0);
  signal dmem_we         : std_logic;
  signal addr_a, addr_b  : integer;
  signal test_dta        : unsigned(31 downto 0);
  signal tx_mem_addr     : std_logic_vector(13 downto 0);
  signal tx_mem_data     : std_logic_vector(31 downto 0);

  signal arg1, arg2, res1                   : unsigned(7 downto 0);
  signal res2                               : unsigned(15 downto 0);
  signal sender                             : std_logic_vector(47 downto 0);
  signal peer_mac                           : std_logic_vector(47 downto 0);
  signal inputs, din, dout                  : std_logic_vector(7 downto 0);
  signal addr                               : std_logic_vector(3 downto 0);
  signal leds                               : std_logic_vector(7 downto 0);
  signal nwr, nrd, rst_p, rst_n, dcm_locked : std_logic;
  signal cpu_reset, not_cpu_reset, rst_del  : std_logic;

  signal set_number          : unsigned(15 downto 0);
  signal pkt_number          : unsigned(15 downto 0);
  signal retry_number        : unsigned(15 downto 0) := (others => '0');
  signal start_pkt, stop_pkt : unsigned(7 downto 0)  := (others => '0');


  signal read_addr                   : std_logic_vector(15 downto 0);
  signal read_data                   : std_logic_vector(15 downto 0);
  signal read_done, read_in_progress : std_logic;

  signal rst_cnt : integer := 0;

  signal led_counter        : integer                       := 0;
  signal tx_counter         : integer                       := 10000;
  signal Reset              : std_logic;
  signal s_gtx_clk          : std_logic;
  signal sysclk             : std_logic;
  signal Speed              : std_logic_vector(2 downto 0);
  signal Rx_mac_ra          : std_logic;
  signal Rx_mac_rd          : std_logic;
  signal Rx_mac_data        : std_logic_vector(31 downto 0);
  signal Rx_mac_BE          : std_logic_vector(1 downto 0);
  signal Rx_mac_pa          : std_logic;
  signal Rx_mac_sop         : std_logic;
  signal Rx_mac_eop         : std_logic;
  signal Tx_mac_wa          : std_logic;
  signal Tx_mac_wr          : std_logic;
  signal Tx_mac_data        : std_logic_vector(31 downto 0);
  signal Tx_mac_BE          : std_logic_vector(1 downto 0);
  signal Tx_mac_sop         : std_logic;
  signal Tx_mac_eop         : std_logic;
  signal Pkg_lgth_fifo_rd   : std_logic;
  signal Pkg_lgth_fifo_ra   : std_logic;
  signal Pkg_lgth_fifo_data : std_logic_vector(15 downto 0);
  signal Gtx_clk            : std_logic;
  signal Tx_er              : std_logic;
  signal Tx_en              : std_logic;
  signal s_Txd              : std_logic_vector(3 downto 0);
  signal Rx_er              : std_logic;
  signal Rx_dv              : std_logic;
  signal s_Rxd              : std_logic_vector(3 downto 0);
  signal Crs                : std_logic;
  signal Col                : std_logic;
  signal CSB                : std_logic                     := '1';
  signal WRB                : std_logic                     := '1';
  signal CD_in              : std_logic_vector(15 downto 0) := (others => '0');
  signal CD_out             : std_logic_vector(15 downto 0) := (others => '0');
  signal CA                 : std_logic_vector(7 downto 0)  := (others => '0');
  signal s_Mdo              : std_logic;
  signal s_MdoEn            : std_logic;
  signal s_Mdi              : std_logic;

  signal buttons        : std_logic_vector(3 downto 0);
  signal clk25, ipb_clk : std_logic;

  signal s_dta_we    : std_logic;
  constant zeroes_32 : std_logic_vector(31 downto 0) := (others => '0');

  signal mac_tx_data, mac_rx_data                                                                       : std_logic_vector(7 downto 0);
  signal mac_tx_valid, mac_tx_last, mac_tx_error, mac_tx_ready, mac_rx_valid, mac_rx_last, mac_rx_error : std_logic;

  signal ipb_master_out : ipb_wbus;
  signal ipb_master_in  : ipb_rbus;
  signal mac_addr       : std_logic_vector(47 downto 0);
  signal ip_addr        : std_logic_vector(31 downto 0);

  component clk_ipb100
    port(
      CLKIN_IN        : in  std_logic;
      RST_IN          : in  std_logic;
      CLKDV_OUT       : out std_logic;
      CLKIN_IBUFG_OUT : out std_logic;
      CLK0_OUT        : out std_logic;
      LOCKED_OUT      : out std_logic
      );
  end component;
  component eth_s3e_100mii is
    port (
      clk25       : in    std_logic;
      clksys      : in    std_logic;
      rst         : in    std_logic;
      mii_mdc     : out   std_logic;
      mii_mdio    : inout std_logic;
      mii_tx_clk  : in    std_logic;
      mii_col     : in    std_logic;
      mii_crs     : in    std_logic;
      mii_txd     : out   std_logic_vector(3 downto 0);
      mii_tx_en   : out   std_logic;
      mii_tx_er   : out   std_logic;
      mii_rx_clk  : in    std_logic;
      mii_rxd     : in    std_logic_vector(3 downto 0);
      mii_rx_dv   : in    std_logic;
      mii_rx_er   : in    std_logic;
      tx_data     : in    std_logic_vector(7 downto 0);
      tx_valid    : in    std_logic;
      tx_last     : in    std_logic;
      tx_error    : in    std_logic;
      tx_ready    : out   std_logic;
      rx_data     : out   std_logic_vector(7 downto 0);
      rx_valid    : out   std_logic;
      rx_last     : out   std_logic;
      rx_error    : out   std_logic;
      hostbus_in  : in    emac_hostbus_in := ('0', "00", "0000000000", X"00000000", '0', '0', '0');
      hostbus_out : out   emac_hostbus_out);
  end component eth_s3e_100mii;


  
  component ipbus_ctrl is
    generic (
      MAC_CFG       : ipb_mac_cfg := EXTERNAL;
      IP_CFG        : ipb_ip_cfg := EXTERNAL;
      BUFWIDTH      : natural := 2;
      INTERNALWIDTH : natural := 1;
      ADDRWIDTH     : natural := 11;
      IPBUSPORT     : std_logic_vector(15 downto 0) := x"C351";
      SECONDARYPORT : std_logic := '0';
      N_OOB         : natural := 0);
    port (
      mac_clk      : in  std_logic;
      rst_macclk   : in  std_logic;
      ipb_clk      : in  std_logic;
      rst_ipb      : in  std_logic;
      mac_rx_data  : in  std_logic_vector(7 downto 0);
      mac_rx_valid : in  std_logic;
      mac_rx_last  : in  std_logic;
      mac_rx_error : in  std_logic;
      mac_tx_data  : out std_logic_vector(7 downto 0);
      mac_tx_valid : out std_logic;
      mac_tx_last  : out std_logic;
      mac_tx_error : out std_logic;
      mac_tx_ready : in  std_logic;
      ipb_out      : out ipb_wbus;
      ipb_in       : in  ipb_rbus;
      ipb_req      : out std_logic;
      ipb_grant    : in  std_logic                                := '1';
      mac_addr     : in  std_logic_vector(47 downto 0)            := X"000000000000";
      ip_addr      : in  std_logic_vector(31 downto 0)            := X"00000000";
      enable       : in  std_logic                                := '1';
      RARP_select  : in  std_logic                                := '1';
      pkt_rx       : out std_logic;
      pkt_tx       : out std_logic;
      pkt_rx_led   : out std_logic;
      pkt_tx_led   : out std_logic;
      oob_in       : in  ipbus_trans_in_array(N_OOB - 1 downto 0) := (others => ('0', X"00000000", '0'));
      oob_out      : out ipbus_trans_out_array(N_OOB - 1 downto 0));
  end component ipbus_ctrl;

begin  -- beh

  mac_addr <= X"020ddba11598";  -- Careful here, arbitrary addresses do not always work
  ip_addr  <= X"c0a80008";              -- 192.168.0.8


  buttons(0) <= BTN_WEST;
  buttons(1) <= BTN_EAST;
  buttons(2) <= BTN_NORTH;
  buttons(3) <= BTN_SOUTH;

  cpu_reset <= not ROT_CENTER;
  -- Different not used signals
  sysclk    <= clk_50mhz;
  sd_dq     <= (others => 'Z');
  sf_oe     <= '1';
  sf_we     <= '1';
  sf_d      <= (others => 'Z');

  sd_cs  <= '1';
  sd_we  <= '1';
  sd_ras <= '1';
  sd_cas <= '1';

  SD_CK_P <= '0';
  SD_CK_N <= '1';
  SD_CKE  <= '0';

  SD_BA <= (others => '0');
  SD_A  <= (others => '0');

  SD_UDM  <= 'Z';
  SD_UDQS <= 'Z';
  SD_LDM  <= 'Z';
  SD_LDQS <= 'Z';

  --E_MDC   <= '1';
  --E_MDIO  <= 'Z';
  --E_TX_ER <= '0';
  --E_TXD   <= (others => '0');

  SF_CE0   <= '0';
  SF_BYTE  <= '0';
  SF_A     <= (others => '0');
  SPI_MISO <= 'Z';

  VGA_VSYNC <= '0';
  VGA_HSYNC <= '0';
  VGA_RED   <= '0';
  VGA_GREEN <= '0';
  VGA_BLUE  <= '0';

  -- Codec is not connected
  CDC_DIN        <= '0';
  CDC_LRC_IN_OUT <= '0';
  CDC_BCLK       <= '0';
  CDC_MCK        <= '0';
  CDC_SCLK       <= '0';
  CDC_SDIN       <= '0';
  CDC_CSn        <= '0';

  -- LEDs are not used
  LED <= LEDs;

  -- RS not used
  RS232_DCE_TXD <= '1';

--  iic_sda_main <= 'Z';
-- iic_scl_main <= 'Z';

  not_cpu_reset <= not cpu_reset;
  rst_p         <= not rst_n;

--  flash_oe_b <= '1';
--  flash_we_b <= '1';
--  flash_ce_b <= '1';
  s_RXD(3 downto 0) <= E_RXD;
  E_TXD             <= s_TXD(3 downto 0);

  Pkg_lgth_fifo_rd <= Pkg_lgth_fifo_ra;

  addr_a <= to_integer(unsigned(dmem_addr));
  addr_b <= to_integer(unsigned(tx_mem_addr));


  -- We don't use 125MHz clock!
  s_gtx_clk <= '0';

  ipb_clk <= clk25;

  -- Added IPbus part

  -- Clocks - to be done!
  clk_ipb100_1 : entity work.clk_ipb100
    port map (
      CLKIN_IN        => sysclk,
      RST_IN          => not_cpu_reset,
      CLKDV_OUT       => clk25,
      CLKIN_IBUFG_OUT => open,
      CLK0_OUT        => open,
      LOCKED_OUT      => rst_n);

  --leds <= (pkt_rx_led, pkt_tx_led, locked, onehz);
  --leds  <= (led1, led2, locked, onehz);

--      Ethernet MAC core and PHY interface
-- In this version, consists of hard MAC core and GMII interface to external PHY
-- Can be replaced by any other MAC / PHY combination
  eth_iface : eth_s3e_100mii
    port map (
      clk25       => clk25,
      clksys      => sysclk,
      rst         => rst_p,             -- @@ To be verified , maybe rst_n?
      mii_mdc     => E_MDC,
      mii_mdio    => E_MDIO,
      mii_tx_clk  => E_TX_CLK,
      mii_col     => E_COL,
      mii_crs     => E_CRS,
      mii_txd     => s_TXD,
      mii_tx_en   => E_TX_EN,
      mii_tx_er   => E_TX_ER,
      mii_rx_clk  => E_RX_CLK,
      mii_rxd     => E_RXD,
      mii_rx_dv   => E_RX_DV,
      mii_rx_er   => E_RX_ER,
      tx_data     => mac_tx_data,
      tx_valid    => mac_tx_valid,
      tx_last     => mac_tx_last,
      tx_error    => mac_tx_error,
      tx_ready    => mac_tx_ready,
      rx_data     => mac_rx_data,
      rx_valid    => mac_rx_valid,
      rx_last     => mac_rx_last,
      rx_error    => mac_rx_error,
      hostbus_in  => open,
      hostbus_out => open);

-- ipbus control logic

  ipbus : ipbus_ctrl
    port map(
      mac_clk      => clk25,
      rst_macclk   => rst_p,            -- @@ To be checked, maybe rst_n?
      ipb_clk      => ipb_clk,
      rst_ipb      => rst_p,            -- @@ To be checked, maybe rst_n?
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
      pkt_rx       => open,
      pkt_tx       => open,
      pkt_rx_led   => open,
      pkt_tx_led   => open
      );

  mac_addr <= X"020ddba11598";  -- Careful here, arbitrary addresses do not always work
  ip_addr  <= X"c0a80008";              -- 192.168.0.8

-- ipbus slaves live in the entity below, and can expose top-level ports
-- The ipbus fabric is instantiated within.
  slaves_1 : entity work.slaves
    port map (
      ipb_clk => ipb_clk,
      ipb_rst => rst_p,
      ipb_in  => ipb_master_out,
      ipb_out => ipb_master_in,
      buttons => buttons,
      leds    => leds);

  -- End of IPbus part

  -- reset

  --phy_reset <= rst_n;


  -- gpio_led(1 downto 0) <= std_logic_vector(to_unsigned(led_counter, 2));

end beh;
