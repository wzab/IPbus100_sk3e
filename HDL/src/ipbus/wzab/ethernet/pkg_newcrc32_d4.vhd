library ieee;
use ieee.std_logic_1164.all;
package pkg_newcrc32_d4 is
  -- CRC update for 32-bit CRC and 4-bit data (LSB first)
  -- The CRC polynomial exponents: [0, 1, 2, 4, 5, 7, 8, 10, 11, 12, 16, 22, 23, 26, 32]
  function newcrc32_d4(
   din : std_logic_vector(3 downto 0);
   crc : std_logic_vector(31 downto 0))
  return std_logic_vector;
end pkg_newcrc32_d4;

package body pkg_newcrc32_d4 is
  function newcrc32_d4(
   din : std_logic_vector(3 downto 0);
   crc : std_logic_vector(31 downto 0))
  return std_logic_vector is 
    variable c,n : std_logic_vector(31 downto 0);
    variable d : std_logic_vector(3 downto 0);
  begin
    c := crc;
    d := din; 
      n(0) := c(28) xor d(3);
      n(1) := c(28) xor c(29) xor d(2) xor d(3);
      n(2) := c(28) xor c(29) xor c(30) xor d(1) xor d(2) xor d(3);
      n(3) := c(29) xor c(30) xor c(31) xor d(0) xor d(1) xor d(2);
      n(4) := c(0) xor c(28) xor c(30) xor c(31) xor d(0) xor d(1) xor d(3);
      n(5) := c(1) xor c(28) xor c(29) xor c(31) xor d(0) xor d(2) xor d(3);
      n(6) := c(2) xor c(29) xor c(30) xor d(1) xor d(2);
      n(7) := c(3) xor c(28) xor c(30) xor c(31) xor d(0) xor d(1) xor d(3);
      n(8) := c(4) xor c(28) xor c(29) xor c(31) xor d(0) xor d(2) xor d(3);
      n(9) := c(5) xor c(29) xor c(30) xor d(1) xor d(2);
      n(10) := c(6) xor c(28) xor c(30) xor c(31) xor d(0) xor d(1) xor d(3);
      n(11) := c(7) xor c(28) xor c(29) xor c(31) xor d(0) xor d(2) xor d(3);
      n(12) := c(8) xor c(28) xor c(29) xor c(30) xor d(1) xor d(2) xor d(3);
      n(13) := c(9) xor c(29) xor c(30) xor c(31) xor d(0) xor d(1) xor d(2);
      n(14) := c(10) xor c(30) xor c(31) xor d(0) xor d(1);
      n(15) := c(11) xor c(31) xor d(0);
      n(16) := c(12) xor c(28) xor d(3);
      n(17) := c(13) xor c(29) xor d(2);
      n(18) := c(14) xor c(30) xor d(1);
      n(19) := c(15) xor c(31) xor d(0);
      n(20) := c(16);
      n(21) := c(17);
      n(22) := c(18) xor c(28) xor d(3);
      n(23) := c(19) xor c(28) xor c(29) xor d(2) xor d(3);
      n(24) := c(20) xor c(29) xor c(30) xor d(1) xor d(2);
      n(25) := c(21) xor c(30) xor c(31) xor d(0) xor d(1);
      n(26) := c(22) xor c(28) xor c(31) xor d(0) xor d(3);
      n(27) := c(23) xor c(29) xor d(2);
      n(28) := c(24) xor c(30) xor d(1);
      n(29) := c(25) xor c(31) xor d(0);
      n(30) := c(26);
      n(31) := c(27);
    return n;
  end newcrc32_d4;
end pkg_newcrc32_d4;

