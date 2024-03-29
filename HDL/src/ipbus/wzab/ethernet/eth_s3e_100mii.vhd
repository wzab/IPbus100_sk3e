-------------------------------------------------------------------------------
-- Title      : Wrapper for FPGA 100Mbps MII Ethernet interface - replacing the 
--              original IPBus eth_s7_gmii.vhd
--
-- Based on FADE project: https://doi.org/10.1088/1748-0221/10/07/T07005
-- and https://doi.org/10.1117/12.2033278
--  
-------------------------------------------------------------------------------
-- File       : eth_s3_100mii.vhd
-- Author     : Wojciech M. Zabolotny (wzab@ise.pw.edu.pl)
-- License    : Dual LGPL/BSD License
-- Company    : 
-- Created    : 2017-05-20
-- Last update: 2017-05-24
-- Platform   : 
-- Standard   : VHDL'93
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
library unisim;
use unisim.VComponents.all;
use work.emac_hostbus_decl.all;

entity eth_s3e_100mii is
  port(
    clk25       : in  std_logic;
    clksys      : in  std_logic;
    rst         : in  std_logic;
    mii_mdc     : out std_logic;
    mii_mdio    : inout std_logic;
    mii_tx_clk  : in  std_logic;
    mii_col     : in  std_logic;
    mii_crs     : in  std_logic;
    mii_txd     : out std_logic_vector(3 downto 0);
    mii_tx_en   : out std_logic;
    mii_tx_er   : out std_logic;
    mii_rx_clk  : in  std_logic;
    mii_rxd     : in  std_logic_vector(3 downto 0);
    mii_rx_dv   : in  std_logic;
    mii_rx_er   : in  std_logic;
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

end eth_s3e_100mii;

architecture rtl of eth_s3e_100mii is

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

  mii_mdc <= '1';
  mii_mdio <= 'Z';
  mii_tx_er <= '0';
  rst_n      <= not rst;

  eth_sender_1 : entity work.eth_sender
    port map (
      clk      => clk25,
      rst_n    => rst_n,
      tx_data  => tx_data,
      tx_valid => tx_valid,
      tx_last  => tx_last,
      tx_error => tx_error,
      tx_ready => tx_ready,
      Tx_Clk   => mii_tx_clk,
      Tx_En    => mii_tx_en,
      TxD      => mii_txd,
      leds     => open);

  eth_receiver_1 : entity work.eth_receiver
    port map (
      rx_data  => rx_data,
      rx_valid => rx_valid,
      rx_last  => rx_last,
      rx_error => rx_error,
      clk      => clk25,
      rst_n    => rst_n,
      Rx_Clk   => mii_rx_clk,
      Rx_Er    => mii_rx_er,
      Rx_Dv    => mii_rx_dv,
      RxD      => mii_rxd,
      leds     => open);


  hostbus_out.hostrddata  <= (others => '0');
  hostbus_out.hostmiimrdy <= '0';


end rtl;
