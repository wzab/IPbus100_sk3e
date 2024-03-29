-------------------------------------------------------------------------------
-- Title      : FPGA Ethernet interface - block sending packets via GMII Phy
-- Project    : 
-------------------------------------------------------------------------------
-- File       : dpr_eth_sender.vhd
-- Author     : Wojciech M. Zabolotny (wzab@ise.pw.edu.pl)
-- License    : Dual LGPL/BSD License
-- Company    : 
-- Created    : 2014-11-10
-- Last update: 2017-05-24
-- Platform   : 
-- Standard   : VHDL'93
-------------------------------------------------------------------------------
-- Description: This file implements an Ethernet transmitter, which receives
-- packets from IPbus
--
-- It consists of two FSMs - one responsible for reception of packets and
-- writing them to the DP RAM
-- The second one, receives packets from the DP RAM and transmits them via
-- Ethernet PHY.
--
-- The original version was prepared for the FADE project
-- https://doi.org/10.1088/1748-0221/10/07/T07005
-- and https://doi.org/10.1117/12.2033278
-- This is a remastered version for IPbus100

-------------------------------------------------------------------------------
-- Copyright (c) 2014 
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author  Description
-- 2014-11-10  1.0      WZab      Created
-- 2017-05-20  1.1      WZab      Modified for IPbus100
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library work;
use work.pkg_newcrc32_d4.all;

entity eth_sender is

  port (
    -- System interface
    clk      : in  std_logic;
    rst_n    : in  std_logic;
    --
    tx_data  : in  std_logic_vector(7 downto 0);
    tx_valid : in  std_logic;
    tx_last  : in  std_logic;
    tx_error : in  std_logic;
    tx_ready : out std_logic;
    -- TX Phy interface
    Tx_Clk   : in  std_logic;
    Tx_En    : out std_logic;
    TxD      : out std_logic_vector(3 downto 0);
    leds     : out std_logic_vector(3 downto 0)
    );

end eth_sender;


architecture beh1 of eth_sender is

  constant DPR_AWDTH : integer := 12;

  type T_ETH_SENDER_STATE is (WST_IDLE, WST_SEND_PREAMB, WST_SEND_SOF,
                              WST_SEND_PACKET_1, WST_SEND_PACKET_1b,
                              WST_SEND_PACKET_2, WST_SEND_PACKET_2b,
                              WST_SEND_CRC,
                              WST_SEND_COMPLETED);

  type T_TX_STATE is (DST_IDLE, DST_PACKET);

  signal dr_state : T_TX_STATE := DST_IDLE;
  -- Additional pipeline registers to improve timing
  signal Tx_En_0  : std_logic;
  signal TxD_0    : std_logic_vector(3 downto 0);

  type T_ETH_SENDER_REGS is record
    state   : T_ETH_SENDER_STATE;
    ready   : std_logic;
    count   : integer;
    nibble : integer; 
    pkt_len : integer;
    rd_ptr  : unsigned(DPR_AWDTH-1 downto 0);
    byte    : integer;
    crc32   : std_logic_vector(31 downto 0);
  end record;


  constant ETH_SENDER_REGS_INI : T_ETH_SENDER_REGS := (
    state   => WST_IDLE,
    ready   => '1',
    count   => 0,
    pkt_len => 0,
    nibble  => 0,
    rd_ptr  => (others => '0'),
    byte    => 0,
    crc32   => (others => '0')
    );

  signal r, r_n : T_ETH_SENDER_REGS := ETH_SENDER_REGS_INI;

  type T_ETH_SENDER_COMB is record
    TxD         : std_logic_vector(3 downto 0);
    Tx_En       : std_logic;
    pkt_fifo_rd : std_logic;
    stall       : std_logic;
  end record;

  constant ETH_SENDER_COMB_DEFAULT : T_ETH_SENDER_COMB := (
    TxD         => (others => '0'),
    Tx_En       => '0',
    pkt_fifo_rd => '0',
    stall       => '1'
    );

  signal c     : T_ETH_SENDER_COMB := ETH_SENDER_COMB_DEFAULT;
  signal rst_p : std_logic;

  function select_nibble (
    constant vec        : std_logic_vector;
    constant nibble_num : integer)
    return std_logic_vector is
    variable byte_num : integer;
    variable v_byte   : std_logic_vector(7 downto 0);
    variable v_nibble : std_logic_vector(3 downto 0);
  begin
    -- first select byte
    byte_num := nibble_num / 2;
    v_byte   := vec(vec'left-byte_num*8 downto vec'left-byte_num*8-7);
    -- then select nibble (lower nibble is sent first!)
    if nibble_num mod 2 = 0 then
      v_nibble := v_byte(3 downto 0);
    else
      v_nibble := v_byte(7 downto 4);
    end if;
    return v_nibble;
  end select_nibble;

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
      empty  : out std_logic
      );
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

  signal tx_rst_n, tx_rst_n_0, tx_rst_n_1 : std_logic := '0';

  type T_STATE1 is (ST1_IDLE, ST1_WAIT_NOT_READY, ST1_WAIT_NOT_START,
                    ST1_WAIT_READY);
  signal state1 : T_STATE1;

  type T_STATE2 is (ST2_IDLE, ST2_WAIT_NOT_READY, ST2_WAIT_READY);
  signal state2          : T_STATE2;
  signal dta_packet_type : std_logic_vector(15 downto 0) := (others => '0');

  -- Signals used by the first FSM
  signal dpr_st_ptr, dpr_wr_ptr, dpr_rd_ptr, dpr_end_ptr, dpr_beg_ptr : unsigned(DPR_AWDTH-1 downto 0)           := (others => '0');
  signal pkt_fifo_din, pkt_fifo_dout                                  : std_logic_vector(2*DPR_AWDTH-1 downto 0) := (others => '0');
  signal pkt_fifo_wr, pkt_fifo_full, pkt_fifo_empty                   : std_logic                                := '0';
  signal dpr_din, dpr_dout                                            : std_logic_vector(7 downto 0);
  signal dpr_wr                                                       : std_logic;
  signal s_tx_ready                                                   : std_logic;
  signal s_leds                                                       : std_logic_vector(3 downto 0)             := (others => '0');
  constant zeroes_8 : std_logic_vector(7 downto 0) := (others => '0');
-- 
begin  -- beh1

  dpr_end_ptr <= unsigned(pkt_fifo_dout(DPR_AWDTH-1 downto 0));
  dpr_beg_ptr <= unsigned(pkt_fifo_dout(2*DPR_AWDTH-1 downto DPR_AWDTH));
  leds        <= s_leds;
  s_leds(0)   <= s_tx_ready;
  tx_ready    <= s_tx_ready;


  rst_p      <= not rst_n;
  -- Connection of the DP_RAM
  -- write address: dpr_wr_ptr
  -- read address: dpr_rd_ptr
  -- input data: dpr_din
  -- output_data: dpr_dout
  dpr_rd_ptr <= r.rd_ptr;

  dp_ram_scl_1 : dp_ram_scl
    generic map (
      DATA_WIDTH => 8,
      ADDR_WIDTH => DPR_AWDTH)
    port map (
      clk_a  => clk,
      we_a   => dpr_wr,
      addr_a => std_logic_vector(dpr_wr_ptr),
      data_a => dpr_din,
      q_a    => open,
      clk_b  => Tx_Clk,
      we_b   => '0',
      addr_b => std_logic_vector(dpr_rd_ptr),
      data_b => zeroes_8,
      q_b    => dpr_dout);

  pkt_fifo_1 : pkt_fifo
    port map (
      rst    => rst_p,
      wr_clk => clk,
      rd_clk => Tx_Clk,
      din    => pkt_fifo_din,
      wr_en  => pkt_fifo_wr,
      rd_en  => c.pkt_fifo_rd,
      dout   => pkt_fifo_dout,
      full   => pkt_fifo_full,
      empty  => pkt_fifo_empty);

  -- Check if we are ready for the next byte
  -- In fact we compare here signals from different clock domains
  -- so the signals should be appropriately synchronized and
  -- pointers should count in the Gray code
  -- BUT in upper block: eth_7s_gmii.vhd both
  -- clk and TxClk are the same clk_125 clock.
  -- This allows to make things simpler, but may create serious
  -- problems if you port this design to environment, where
  -- clk and TxClk are diffent!
  -- In this case you must redesign this block!!!
  process (dpr_rd_ptr, dpr_wr_ptr, pkt_fifo_full) is
    variable v_dr_ptr : unsigned(DPR_AWDTH-1 downto 0);
  begin  -- process
    v_dr_ptr   := dpr_wr_ptr + 1;
    s_tx_ready <= '0';
    if v_dr_ptr /= dpr_rd_ptr then
      if pkt_fifo_full = '0' then
        s_tx_ready <= '1';
      end if;
    end if;
  end process;

  -- The first state machine - writes the data to the DP RAM
  -- It is an extremely simple machine, so it can be a single process one
  -- Please note, that a single packet bigger than DP RAM capacity
  -- will freeze the design! (As data won't be read before the packet
  -- is completed, and it will be never completed, as memory gets full...)

  process (clk) is
    variable v_dpr_ptr : unsigned(DPR_AWDTH-1 downto 0);
  begin  -- process
    if clk'event and clk = '1' then     -- rising clock edge
                                        -- default values
      if rst_n = '0' then               -- synchronous reset (active low)
        dpr_st_ptr   <= (others => '0');
        dpr_wr_ptr   <= (others => '0');
        dpr_din      <= (others => '0');
        pkt_fifo_din <= (others => '0');
        dpr_wr       <= '0';
        pkt_fifo_wr  <= '0';
        dr_state     <= DST_IDLE;
      else
        dpr_wr      <= '0';
        pkt_fifo_wr <= '0';
        v_dpr_ptr   := dpr_wr_ptr+1;
        if dpr_wr = '1' then
          dpr_wr_ptr <= v_dpr_ptr;
        end if;
        case dr_state is
          when DST_IDLE =>
            if tx_valid = '1' and s_tx_ready = '1' then
              -- Start of the packet
              s_leds(1)  <= not s_leds(1);
              dpr_st_ptr <= dpr_wr_ptr;
              dpr_din    <= tx_data;
              dpr_wr     <= '1';
              dr_state   <= DST_PACKET;
            end if;
          when DST_PACKET =>
            if tx_valid = '1' and s_tx_ready = '1' then
              dpr_wr     <= '1';
              dpr_din    <= tx_data;
              dpr_wr_ptr <= v_dpr_ptr;
              if tx_last = '1' then
                -- Write the next packet
                pkt_fifo_din <= std_logic_vector(dpr_st_ptr & v_dpr_ptr);
                pkt_fifo_wr  <= '1';
                s_leds(2)    <= not s_leds(2);
                dr_state     <= DST_IDLE;
              end if;

            end if;
          when others => null;
        end case;
      end if;
    end if;
  end process;

                                        -- Connection of the signals

                                        -- Main state machine used to send the packet

  snd1 : process (Tx_Clk)
  begin
    if Tx_Clk'event and Tx_Clk = '1' then  -- rising clock edge
      if tx_rst_n = '0' then               -- asynchronous reset (active low)
        r       <= ETH_SENDER_REGS_INI;
        TxD_0   <= (others => '0');
        Tx_En_0 <= '0';

      else
        r       <= r_n;
        -- To minimize glitches and propagation delay, let's add pipeline register
        Tx_En_0 <= c.Tx_En;
        TxD_0   <= c.TxD;
      end if;
    end if;
  end process snd1;  -- snd1

  -- Signals feeding the interface lines should change on falling slope!
  snd1b : process (Tx_Clk)
  begin
    if Tx_Clk'event and Tx_Clk = '0' then  -- rising clock edge
      if tx_rst_n = '0' then               -- asynchronous reset (active low)
        TxD     <= (others => '0');
        Tx_En   <= '0';
      else
        TxD     <= TxD_0;
        Tx_En   <= Tx_En_0;
      end if;
    end if;
  end process snd1b;  -- snd1b

  
  

  snd2 : process (dpr_beg_ptr, dpr_dout, dpr_end_ptr, pkt_fifo_empty, r)
    variable v_TxD : std_logic_vector(3 downto 0);
  begin  -- process snd1
    -- default values
    c   <= ETH_SENDER_COMB_DEFAULT;
    r_n <= r;
    case r.state is
      when WST_IDLE =>
        r_n.ready <= '1';
        if pkt_fifo_empty = '0' then
                                        -- We have a packet to transmit!
          r_n.rd_ptr <= dpr_beg_ptr;
          r_n.ready  <= '0';
          r_n.state  <= WST_SEND_PREAMB;
          r_n.count  <= 15;
        end if;
      when WST_SEND_PREAMB =>
        c.TxD     <= x"5";
        c.Tx_En   <= '1';
        r_n.count <= r.count - 1;
        if r.count = 1 then
          r_n.state <= WST_SEND_SOF;
        end if;
      when WST_SEND_SOF =>
        c.TxD       <= x"D";
        c.Tx_En     <= '1';
                                        -- Prepare for sending of packet
        r_n.crc32   <= (others => '1');
        r_n.state   <= WST_SEND_PACKET_1;
        r_n.pkt_len <= 0;
      when WST_SEND_PACKET_1 =>  
        v_TxD       := select_nibble(dpr_dout,0); 
        c.TxD       <= v_TxD;
        c.Tx_En     <= '1';
        r_n.crc32   <= newcrc32_d4(v_TxD, r.crc32);
        r_n.state <= WST_SEND_PACKET_1b;
                                        -- Increase the address (but due to 1clk delay,
                                        -- the DPRAM will still present the previous value!)
        r_n.rd_ptr  <= r.rd_ptr+1;
      when WST_SEND_PACKET_1b =>
        v_TxD       := select_nibble(dpr_dout,1);
        c.TxD       <= v_TxD;
        c.Tx_En     <= '1';
        r_n.pkt_len <= r.pkt_len + 1;
        r_n.crc32   <= newcrc32_d4(v_TxD, r.crc32);
                                        -- If we are at the last byte of the packet (it will be provided
                                        -- by the DPRAM in the next cycle), leave the loop
        if r.rd_ptr = dpr_end_ptr then
          -- If this is the last last byte, go directly to sending it
          -- without increasing the read pointer!
          -- Otherwise the read pointer may go above the write pointer
          -- which is detected as memory full condition!
          r_n.state     <= WST_SEND_PACKET_2;
                                        -- Remove packet from the packet FIFO
          c.pkt_fifo_rd <= '1';
        else
          r_n.state <= WST_SEND_PACKET_1;
        end if;
      when WST_SEND_PACKET_2 =>
        v_TxD       := select_nibble(dpr_dout,0);
        c.TxD       <= v_TxD;
        c.Tx_En     <= '1';
        r_n.crc32   <= newcrc32_d4(v_TxD, r.crc32);
        r_n.state <= WST_SEND_PACKET_2b;
      when WST_SEND_PACKET_2b =>
        v_TxD       := select_nibble(dpr_dout,1);
        c.TxD       <= v_TxD;
        c.Tx_En     <= '1';
        r_n.pkt_len <= r.pkt_len + 1;
        r_n.crc32   <= newcrc32_d4(v_TxD, r.crc32);
        -- if the length of packet is sufficient, go to sending of checksum
        if r.pkt_len > 98 then
          r_n.nibble  <= 0;
          r_n.state <= WST_SEND_CRC;
        end if;
      when WST_SEND_CRC =>
        v_TxD   := r.crc32(31-4*r.nibble downto 28-4*r.nibble);
        c.TxD   <= not rev(v_TxD);
        c.Tx_En <= '1';
        if r.nibble < 7 then
          r_n.nibble <= r.nibble + 1;
        else
          r_n.count <= 24;              -- generate the IFG - 24-nibbles  = 96
          -- bits
          r_n.state <= WST_SEND_COMPLETED;
        end if;
      when WST_SEND_COMPLETED =>
        if r.count > 0 then
          r_n.count <= r.count - 1;
        else
          r_n.ready <= '1';
          r_n.state <= WST_IDLE;
        end if;
    end case;
  end process snd2;


-- Synchronization of the reset signal for the Tx_Clk domain
  process (Tx_Clk, rst_n)
  begin  -- process
    if rst_n = '0' then                 -- asynchronous reset (active low)
      tx_rst_n_0 <= '0';
      tx_rst_n_1 <= '0';
      tx_rst_n   <= '0';
    elsif Tx_Clk'event and Tx_Clk = '1' then  -- rising clock edge
      tx_rst_n_0 <= rst_n;
      tx_rst_n_1 <= tx_rst_n_0;
      tx_rst_n   <= tx_rst_n_1;
    end if;
  end process;

end beh1;
