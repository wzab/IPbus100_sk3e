-------------------------------------------------------------------------------
-- Title      : Wrapper for FPGA Ethernet interface - emulating the 
--              original IPBus eth_s7_gmii.vhd
--
-- Project    : 
-------------------------------------------------------------------------------
-- File       : eth_s7_gmii.vhd
-- Author     : Wojciech M. Zabolotny (wzab@ise.pw.edu.pl)
-- License    : Dual LGPL/BSD License
-- Company    : 
-- Created    : 2014-12-24
-- Last update: 2014-12-25
-- Platform   : 
-- Standard   : VHDL'93
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
library unisim;
use unisim.VComponents.all;
use work.emac_hostbus_decl.all;

entity eth_7s_gmii is
  port(
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
    hostbus_out  : out emac_hostbus_out
    );

end eth_7s_gmii;

architecture rtl of eth_7s_gmii is

  component eth_receiver is
    port (
      rx_data  : out std_logic_vector(7 downto 0);
      rx_valid : out std_logic;
      rx_last  : out std_logic;
      rx_error : out std_logic;
      clk      : in  std_logic;
      rst_n    : in  std_logic;
      Rx_Clk   : in  std_logic;
      Rx_Er    : in  std_logic;
      Rx_Dv    : in  std_logic;
      RxD      : in  std_logic_vector(7 downto 0);
      leds     : out std_logic_vector(3 downto 0)
      );
  end component eth_receiver;

  component eth_sender is
    port (
      clk      : in  std_logic;
      rst_n    : in  std_logic;
      tx_data  : in  std_logic_vector(7 downto 0);
      tx_valid : in  std_logic;
      tx_last  : in  std_logic;
      tx_error : in  std_logic;
      tx_ready : out std_logic;
      Tx_Clk   : in  std_logic;
      Tx_En    : out std_logic;
      TxD      : out std_logic_vector(7 downto 0);
      leds     : out std_logic_vector(3 downto 0));
  end component eth_sender;

  signal rst_n, clk125n : std_logic;

begin

  gmii_tx_er <= '0';
  rst_n      <= not rst;
  clk125n    <= not clk125;

  oddr0 : oddr port map(
    q  => gmii_gtx_clk,
    c  => clk125,
    ce => '1',
    d1 => '0',
    d2 => '1',
    r  => '0',
    s  => '0'
    );                                  -- DDR register for clock forwarding

  eth_sender_1 : entity work.eth_sender
    port map (
      clk      => clk125,
      rst_n    => rst_n,
      tx_data  => tx_data,
      tx_valid => tx_valid,
      tx_last  => tx_last,
      tx_error => tx_error,
      tx_ready => tx_ready,
      Tx_Clk   => clk125,
      Tx_En    => gmii_tx_en,
      TxD      => gmii_txd,
      leds     => open);

  eth_receiver_1 : entity work.eth_receiver
    port map (
      rx_data  => rx_data,
      rx_valid => rx_valid,
      rx_last  => rx_last,
      rx_error => rx_error,
      clk      => clk125,
      rst_n    => rst_n,
      Rx_Clk   => gmii_rx_clk,
      Rx_Er    => gmii_rx_er,
      Rx_Dv    => gmii_rx_dv,
      RxD      => gmii_rxd,
      leds     => open);


  hostbus_out.hostrddata  <= (others => '0');
  hostbus_out.hostmiimrdy <= '0';


end rtl;