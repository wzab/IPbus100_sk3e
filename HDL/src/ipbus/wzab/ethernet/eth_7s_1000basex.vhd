-- Contains the instantiation of the Xilinx MAC & 1000baseX pcs/pma & GTP transceiver cores
--
-- Do not change signal names in here without correspondig alteration to the timing contraints file
--
-- Dave Newbold, April 2011
--
-- $Id$

library ieee;
use ieee.std_logic_1164.all;

library unisim;
use unisim.VComponents.all;
use work.emac_hostbus_decl.all;

entity eth_7s_1000basex is
  port(
    clk2   : in  std_logic;
    gt_clkp, gt_clkn : in  std_logic;
    gt_txp, gt_txn   : out std_logic;
    gt_rxp, gt_rxn   : in  std_logic;
    clk125_out       : out std_logic;
    rsti             : in  std_logic;
    locked           : out std_logic;
    tx_data          : in  std_logic_vector(7 downto 0);
    tx_valid         : in  std_logic;
    tx_last          : in  std_logic;
    tx_error         : in  std_logic;
    tx_ready         : out std_logic;
    rx_data          : out std_logic_vector(7 downto 0);
    rx_valid         : out std_logic;
    rx_last          : out std_logic;
    rx_error         : out std_logic;
    status_o         : out std_logic_vector(15 downto 0);
    hostbus_in       : in  emac_hostbus_in := ('0', "00", "0000000000", X"00000000", '0', '0', '0');
    hostbus_out      : out emac_hostbus_out
    );

end eth_7s_1000basex;

architecture rtl of eth_7s_1000basex is

  component eth_7s_gmii is
    port (
      clk125       : in  std_logic;
      clk200       : in  std_logic;
      rst          : in  std_logic;
      gmii_gtx_clk : out std_logic;
      gmii_txd     : out std_logic_vector(7 downto 0);
      gmii_tx_en   : out std_logic;
      gmii_tx_er   : out std_logic;
      gmii_rx_clk  : in  std_logic;
      gmii_rxd     : in  std_logic_vector(7 downto 0);
      gmii_rx_dv   : in  std_logic;
      gmii_rx_er   : in  std_logic;
      tx_data      : in  std_logic_vector(7 downto 0);
      tx_valid     : in  std_logic;
      tx_last      : in  std_logic;
      tx_error     : in  std_logic;
      tx_ready     : out std_logic;
      rx_data      : out std_logic_vector(7 downto 0);
      rx_valid     : out std_logic;
      rx_last      : out std_logic;
      rx_error     : out std_logic;
      hostbus_in   : in  emac_hostbus_in := ('0', "00", "0000000000", X"00000000", '0', '0', '0');
      hostbus_out  : out emac_hostbus_out);
  end component eth_7s_gmii;

  COMPONENT gig_ethernet_pcs_pma_0
  PORT (
    gtrefclk_p : IN STD_LOGIC;
    gtrefclk_n : IN STD_LOGIC;
    gtrefclk_out : OUT STD_LOGIC;
    txn : OUT STD_LOGIC;
    txp : OUT STD_LOGIC;
    rxn : IN STD_LOGIC;
    rxp : IN STD_LOGIC;
    independent_clock_bufg : IN STD_LOGIC;
    userclk_out : OUT STD_LOGIC;
    userclk2_out : OUT STD_LOGIC;
    rxuserclk_out : OUT STD_LOGIC;
    rxuserclk2_out : OUT STD_LOGIC;
    resetdone : OUT STD_LOGIC;
    pma_reset_out : OUT STD_LOGIC;
    mmcm_locked_out : OUT STD_LOGIC;
    gmii_txd : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    gmii_tx_en : IN STD_LOGIC;
    gmii_tx_er : IN STD_LOGIC;
    gmii_rxd : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    gmii_rx_dv : OUT STD_LOGIC;
    gmii_rx_er : OUT STD_LOGIC;
    gmii_isolate : OUT STD_LOGIC;
    configuration_vector : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
    an_interrupt : OUT STD_LOGIC;
    an_adv_config_vector : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
    an_restart_config : IN STD_LOGIC;
    status_vector : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
    reset : IN STD_LOGIC;
    signal_detect : IN STD_LOGIC;
    gt0_qplloutclk_out : OUT STD_LOGIC;
    gt0_qplloutrefclk_out : OUT STD_LOGIC
  );
  END COMPONENT;
  
  signal gmii_txd, gmii_rxd                                      : std_logic_vector(7 downto 0);
  signal gmii_tx_en, gmii_tx_er, gmii_rx_dv, gmii_rx_er          : std_logic;
  signal gmii_rx_clk                                             : std_logic;
  signal clkin, clk125, txoutclk_ub, txoutclk, clk125_ub, clk_fr : std_logic;
  signal clk62_5_ub, clk62_5, clkfb,rxoutclk_nb                  : std_logic;
  signal clk2_nbuf                             : std_logic;

  signal phy_done, mmcm_locked : std_logic;
  signal status                                  : std_logic_vector(15 downto 0);

begin

  --ibuf1 : IBUFDS_GTE2 port map(
  --  i   => clk2_p,
  --  ib  => clk2_n,
  --  o   => clk2_nbuf,
  --  ceb => '0'
  --  );

  --bufg2 : BUFG port map(
  --  i => clk2_nbuf,
  --  o => clk2
  --  );
  --bufg2 : BUFG port map(
  --  i => rxoutclk_nb,
  --  o => rxoutclk
  --);

--  clk125_fr <= clk_fr;

  locked <= mmcm_locked;
  
  eth_7s_gmii_1 : eth_7s_gmii
    port map (
      clk125       => clk125,
      clk200       => clk2,
      rst          => rsti,
      gmii_gtx_clk => open,
      gmii_txd     => gmii_txd,
      gmii_tx_en   => gmii_tx_en,
      gmii_tx_er   => gmii_tx_er,
      gmii_rx_clk  => clk125,         --? Czy rxoutclk?
      gmii_rxd     => gmii_rxd,
      gmii_rx_dv   => gmii_rx_dv,
      gmii_rx_er   => gmii_rx_er,
      tx_data      => tx_data,
      tx_valid     => tx_valid,
      tx_last      => tx_last,
      tx_error     => tx_error,
      tx_ready     => tx_ready,
      rx_data      => rx_data,
      rx_valid     => rx_valid,
      rx_last      => rx_last,
      rx_error     => rx_error,
      hostbus_in   => hostbus_in,
      hostbus_out  => hostbus_out);

  clk125_out <= clk125;
  status_o <= status;
  
  --hostbus_out.hostrddata  <= (others => '0');
  --hostbus_out.hostmiimrdy <= '0';

  gig_ethernet_pcs_pma_0_2: entity work.gig_ethernet_pcs_pma_0
    port map (
      gtrefclk_p             => gt_clkp,
      gtrefclk_n             => gt_clkn,
      gtrefclk_out           => open,
      txn                    => gt_txn,
      txp                    => gt_txp,
      rxn                    => gt_rxn,
      rxp                    => gt_rxp,
      independent_clock_bufg => clk2,
      userclk_out            => open,
      userclk2_out           => clk125,
      rxuserclk_out          => open,
      rxuserclk2_out         => open,
      resetdone              => phy_done,
      pma_reset_out          => open,
      mmcm_locked_out        => mmcm_locked,
      gmii_txd               => gmii_txd,
      gmii_tx_en             => gmii_tx_en,
      gmii_tx_er             => gmii_tx_er,
      gmii_rxd               => gmii_rxd,
      gmii_rx_dv             => gmii_rx_dv,
      gmii_rx_er             => gmii_rx_er,
      gmii_isolate           => open,
      configuration_vector   => "10001",  -- "10000" for AN 
      an_interrupt => open,
      an_adv_config_vector => "0000000000100000", -- IN STD_LOGIC_VECTOR(15 DOWNTO 0);
      an_restart_config => '0', --: IN STD_LOGIC;
      status_vector          => status,
      reset                  => rsti,
      signal_detect          => '1',
      gt0_qplloutclk_out     => open,
      gt0_qplloutrefclk_out  => open);
  
end rtl;

