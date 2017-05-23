-------------------------------------------------------------------------------
-- Title      : FPGA Ethernet interface - block receiving packets from MII PHY
-- Project    : 
-------------------------------------------------------------------------------
-- File       : dpr_eth_receiver.vhd
-- Author     : Wojciech M. Zabolotny (wzab@ise.pw.edu.pl)
-- License    : Dual LGPL/BSD License
-- Company    : 
-- Created    : 2014-11-10
-- Last update: 2017-05-23
-- Platform   : 
-- Standard   : VHDL'93
-------------------------------------------------------------------------------
-- Description: This blocks receives packets from PHY, and puts only the
-- complete packets with correct CRC to the FIFO
-------------------------------------------------------------------------------
-- Copyright (c) 2014 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2014-11-10  1.0      WZab      Created
-- 2015-09-07  1.1      WZab & Junfeng Yang (bug fixes)
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.pkg_newcrc32_d4.all;

entity eth_receiver is

  port (
    -- Rx interface
    rx_data  : out std_logic_vector(7 downto 0);
    rx_valid : out std_logic;
    rx_last  : out std_logic;
    rx_error : out std_logic;
    -- System interface
    clk      : in  std_logic;
    rst_n    : in  std_logic;
    -- MAC inerface
    Rx_Clk   : in  std_logic;
    Rx_Er    : in  std_logic;
    Rx_Dv    : in  std_logic;
    RxD      : in  std_logic_vector(3 downto 0);
    leds     : out std_logic_vector(3 downto 0)
    );

end eth_receiver;


architecture beh1 of eth_receiver is

  type T_STATE is (ST_RCV_IDLE, ST_RCV_PREAMB, ST_RCV_PACKET_1, ST_RCV_PACKET_1b,
                   ST_RCV_WAIT_IDLE);

  type T_RD_STATE is (SRD_IDLE, SRD_RECV0, SRD_RECV1, SRD_WAIT, SRD_WAIT1);
  constant DELAY_TIME : integer    := 10;
  signal delay        : integer range 0 to DELAY_TIME;
  signal rd_state     : T_RD_STATE := SRD_IDLE;

  function rev(a : in std_logic_vector)
    return std_logic_vector is
    variable result : std_logic_vector(a'range);
    alias aa        : std_logic_vector(a'reverse_range) is a;
  begin
    for i in aa'range loop
      result(i) := aa(i);
    end loop;
    return result;
  end;  -- function reverse_any_bus

  constant DPR_AWDTH : integer := 12;

  type T_RCV_REGS is record
    state         : T_STATE;
    transmit_data : std_logic;
    restart       : std_logic;
    pkt_start     : unsigned(DPR_AWDTH-1 downto 0);
    dpr_wr_ptr    : unsigned(DPR_AWDTH-1 downto 0);
    update_flag   : std_logic;
    nibble        : std_logic_vector(3 downto 0);
    count         : integer range 0 to 256;
    dbg           : std_logic_vector(3 downto 0);
    crc32         : std_logic_vector(31 downto 0);
    cmd           : std_logic_vector(63 downto 0);
    mac_addr      : std_logic_vector(47 downto 0);
    peer_mac      : std_logic_vector(47 downto 0);
  end record;

  constant RCV_REGS_INI : T_RCV_REGS := (
    state         => ST_RCV_IDLE,
    transmit_data => '0',
    restart       => '0',
    nibble        => (others => '0'),
    pkt_start     => (others => '0'),
    dpr_wr_ptr    => (others => '0'),
    update_flag   => '0',
    count         => 0,
    dbg           => (others => '0'),
    crc32         => (others => '0'),
    cmd           => (others => '0'),
    mac_addr      => (others => '0'),
    peer_mac      => (others => '0')
    );

  signal r, r_n : T_RCV_REGS := RCV_REGS_INI;

  type T_RCV_COMB is record
    dpr_wr       : std_logic;
    pkt_fifo_wr  : std_logic;
    pkt_fifo_din : std_logic_vector(2*DPR_AWDTH-1 downto 0);
    dp_din : std_logic_vector(7 downto 0);
    Rx_mac_rd : std_logic;
    restart   : std_logic;
  end record;

  constant RCV_COMB_DEFAULT : T_RCV_COMB := (
    dpr_wr       => '0',
    pkt_fifo_wr  => '0',
    pkt_fifo_din => (others => '0'),
    dp_din => (others => '0'),
    Rx_mac_rd    => '0',
    restart      => '0'
    );

  signal c : T_RCV_COMB := RCV_COMB_DEFAULT;

  component pkt_fifo is
    port (
      rst    : in  std_logic;
      wr_clk : in  std_logic;
      rd_clk : in  std_logic;
      din    : in  std_logic_vector(2*DPR_AWDTH-1 downto 0);
      wr_en  : in  std_logic;
      rd_en  : in  std_logic;
      dout   : out std_logic_vector(2*DPR_AWDTH-1 downto 0);
      full   : out std_logic;
      empty  : out std_logic);
  end component pkt_fifo;

  component dp_ram_scl is
    generic (
      DATA_WIDTH : integer;
      ADDR_WIDTH : integer);
    port (
      clk_a  : in  std_logic;
      we_a   : in  std_logic;
      addr_a : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
      data_a : in  std_logic_vector(DATA_WIDTH-1 downto 0);
      q_a    : out std_logic_vector(DATA_WIDTH-1 downto 0);
      clk_b  : in  std_logic;
      we_b   : in  std_logic;
      addr_b : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
      data_b : in  std_logic_vector(DATA_WIDTH-1 downto 0);
      q_b    : out std_logic_vector(DATA_WIDTH-1 downto 0));
  end component dp_ram_scl;


  signal dpr_end_ptr, dpr_rd_ptr                    : unsigned(DPR_AWDTH-1 downto 0)           := (others => '0');
  signal pkt_fifo_dout                              : std_logic_vector(2*DPR_AWDTH-1 downto 0) := (others => '0');
  signal pkt_fifo_rd, pkt_fifo_empty, pkt_fifo_full : std_logic                                := '0';
  signal rst_p                                      : std_logic;
  signal rx_rst_n, rx_rst_n_0, rx_rst_n_1           : std_logic                                := '0';
  signal s_leds                                     : std_logic_vector(3 downto 0)             := (others => '0');

  -- Additional pipeline registers to improve timing
  signal Rx_Dv_0                                    : std_logic;
  signal Rx_Er_0                                    : std_logic;
  signal RxD_0                                      : std_logic_vector(3 downto 0);

  constant zeroes_8 : std_logic_vector(7 downto 0) := (others => '0');
  
begin  -- beh1

  leds               <= s_leds;
  --s_leds(3) <= pkt_fifo_empty;
  s_leds(2 downto 0) <= r.dbg(2 downto 0);
  rst_p              <= not rst_n;
  rx_error           <= '0';

  pkt_fifo_1 : pkt_fifo
    port map (
      rst    => rst_p,
      wr_clk => Rx_Clk,
      rd_clk => clk,
      din    => c.pkt_fifo_din,
      wr_en  => c.pkt_fifo_wr,
      rd_en  => pkt_fifo_rd,
      dout   => pkt_fifo_dout,
      full   => pkt_fifo_full,
      empty  => pkt_fifo_empty);


  dp_ram_scl_1 : dp_ram_scl
    generic map (
      DATA_WIDTH => 8,
      ADDR_WIDTH => DPR_AWDTH)
    port map (
      clk_a  => Rx_Clk,
      we_a   => c.dpr_wr,
      addr_a => std_logic_vector(r.dpr_wr_ptr),
      data_a => c.dp_din,
      q_a    => open,
      clk_b  => clk,
      we_b   => '0',
      addr_b => std_logic_vector(dpr_rd_ptr),
      data_b => zeroes_8,
      q_b    => rx_data);


  -- Reading of ethernet data
  rdp1 : process (Rx_Clk)
  begin  -- process rdp1
    if Rx_Clk'event and Rx_Clk = '1' then  -- rising clock edge
      if rx_rst_n = '0' then               -- synchronous reset (active low)
        r       <= RCV_REGS_INI;
        Rx_Dv_0 <= '0';
        Rx_Er_0 <= '0';
        RxD_0   <= (others => '0');
      else
        r       <= r_n;
        Rx_Dv_0 <= Rx_Dv;
        Rx_Er_0 <= Rx_Er;
        RxD_0   <= RxD;
      end if;
    end if;
  end process rdp1;

  rdp2 : process (RxD_0, Rx_Dv_0, dpr_rd_ptr, pkt_fifo_full, r)

    variable v_mac_addr   : std_logic_vector(47 downto 0);
    variable v_cmd        : std_logic_vector(63 downto 0);
    variable v_dpr_wr_ptr : unsigned(DPR_AWDTH-1 downto 0) := (others => '0');

  begin  -- process
    c   <= RCV_COMB_DEFAULT;
    r_n <= r;
    --dbg <= "1111";
    case r.state is
      when ST_RCV_IDLE =>
        --dbg <= "0000";
        if Rx_Dv_0 = '1' then
          if RxD_0 = x"5" then
            r_n.count  <= 1;
            r_n.dbg(0) <= not r.dbg(0);
            r_n.state  <= ST_RCV_PREAMB;
          end if;
        end if;
      when ST_RCV_PREAMB =>
        --dbg <= "0001";
        if Rx_Dv_0 = '0' then
          -- interrupted preamble reception
          r_n.state <= ST_RCV_IDLE;
        elsif RxD_0 = x"5" then
          if r.count < 15 then
            r_n.count <= r.count + 1;
          end if;
        elsif (RxD_0 = x"d") and (r.count = 15) then  --D
          -- If there is space in the DPRAM and in the packet FIFO,
          -- we start reception of the packet
          if pkt_fifo_full = '0' then
            r_n.crc32     <= (others => '1');
            r_n.count     <= 0;
            r_n.state     <= ST_RCV_PACKET_1;
            r_n.pkt_start <= r.dpr_wr_ptr;
          else
            r_n.state <= ST_RCV_WAIT_IDLE;
          end if;
        else
          -- something wrong happened during preamble detection
          r_n.state <= ST_RCV_WAIT_IDLE;
        end if;
      when ST_RCV_PACKET_1 =>
        --dbg <= "0010";
        --We assemble bytes as to nibbles
        if Rx_Dv_0 = '1' then
          r_n.crc32  <= newCRC32_D4(RxD_0, r.crc32);
          r_n.nibble <= RxD_0;
          r_n.state  <= ST_RCV_PACKET_1b;
        else
          -- Rx_Dv = 0!
          -- Packet broken, or completed?
          -- Theoretically, we should check here, if the packet is longer than
          -- the minimal length!
          if r.crc32 /= x"c704dd7b" then
            -- Broken packet, recover the space in the buffer
            r_n.dpr_wr_ptr <= r.pkt_start;
            r_n.dbg(1)     <= not r.dbg(1);
            r_n.state      <= ST_RCV_IDLE;
          else
            v_dpr_wr_ptr   := r.dpr_wr_ptr - 5;       -- drop the CRC!
            c.pkt_fifo_din <= std_logic_vector(r.pkt_start & v_dpr_wr_ptr);
            c.pkt_fifo_wr  <= '1';
            r_n.dbg(2)     <= not r.dbg(2);
            r_n.state      <= ST_RCV_IDLE;
          end if;
        end if;
      when ST_RCV_PACKET_1b =>
        --dbg <= "0010";
        --We assemble bytes as to nibbles
        if Rx_Dv_0 = '1' then
          -- Check if there is place for the received byte
          v_dpr_wr_ptr := r.dpr_wr_ptr + 1;
          if v_dpr_wr_ptr /= dpr_rd_ptr then
            c.dpr_wr       <= '1';
            c.dp_din <= RxD_0 & r.nibble;       -- @@ to be verified!!!
            r_n.crc32      <= newcrc32_D4(RxD_0, r.crc32);
            r_n.dpr_wr_ptr <= v_dpr_wr_ptr;
            r_n.state      <= ST_RCV_PACKET_1;
          else
            -- No place for data, drop the packet
            r_n.state <= ST_RCV_WAIT_IDLE;
          end if;
        else
          -- packet broken?
          r_n.state <= ST_RCV_WAIT_IDLE;
        end if;
      when ST_RCV_WAIT_IDLE =>
        --dbg             <= "1001";
        if Rx_Dv_0 = '0' then
          r_n.state <= ST_RCV_IDLE;
        end if;
      when others => null;
    end case;
  end process rdp2;

  -- Synchronization of the reset signal for the Rx_Clk domain
  process (Rx_Clk, rst_n)
  begin  -- process
    if rst_n = '0' then                 -- asynchronous reset (active low)
      rx_rst_n_0 <= '0';
      rx_rst_n_1 <= '0';
      rx_rst_n   <= '0';
    elsif Rx_Clk'event and Rx_Clk = '1' then  -- rising clock edge
      rx_rst_n_0 <= rst_n;
      rx_rst_n_1 <= rx_rst_n_0;
      rx_rst_n   <= rx_rst_n_1;
    end if;
  end process;


  -- Process for reading of data (very simple, one process state machine)
  process (clk) is
  begin  -- process
    if clk'event and clk = '1' then     -- rising clock edge
      if rst_n = '0' then               -- asynchronous reset (active low)
        rd_state    <= SRD_IDLE;
        dpr_rd_ptr  <= (others => '0');
        dpr_end_ptr <= (others => '0');
        delay       <= 0;
      else
        -- defaults
        pkt_fifo_rd <= '0';
        rx_valid    <= '0';
        rx_last     <= '0';
        case rd_state is
          when SRD_IDLE =>
            if pkt_fifo_empty = '0' then
              s_leds(3)   <= not s_leds(3);
              dpr_rd_ptr  <= unsigned(pkt_fifo_dout(2*DPR_AWDTH-1 downto DPR_AWDTH));
              dpr_end_ptr <= unsigned(pkt_fifo_dout(DPR_AWDTH-1 downto 0));
              rd_state    <= SRD_RECV1;
            end if;
          when SRD_RECV1 =>
            rx_valid   <= '1';
            dpr_rd_ptr <= dpr_rd_ptr+1;
            -- Check for end of packet
            if dpr_rd_ptr = dpr_end_ptr then
              rx_last     <= '1';
              pkt_fifo_rd <= '1';
              --s_leds(0) <= not s_leds(0);
              rd_state    <= SRD_WAIT;  -- we can't go immediately to IDLE, as
                                        -- the queue will be read in the next state!
            end if;
          when SRD_WAIT =>
            delay    <= 0;
            rd_state <= SRD_WAIT1;
          when SRD_WAIT1 =>
            if delay = DELAY_TIME then
              rd_state <= SRD_IDLE;
            else
              delay <= delay+1;
            end if;
          when others => null;
        end case;
      end if;
    end if;
  end process;

end beh1;
