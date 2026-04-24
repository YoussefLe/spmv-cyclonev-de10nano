-- =============================================================================
-- spmv_pkg.vhd
-- Package de constantes et types pour l'accélérateur SpMV (Cyclone V)
-- Green AI — GNN Cora Dataset — Int8 entrées / Int32 accumulation
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package spmv_pkg is

  -- ===================== Dimensions Avalon-MM =====================
  constant AVM_DATA_W      : natural := 32;
  constant AVM_ADDR_W      : natural := 32;
  constant AVS_DATA_W      : natural := 32;
  constant AVS_ADDR_W      : natural := 4;

  -- ===================== Burst =====================
  constant BURST_LEN       : natural := 1;

  -- ===================== Registres esclave (offsets mots) =====================
  constant REG_CTRL        : natural := 0;
  constant REG_STATUS      : natural := 1;
  constant REG_NUM_ROWS    : natural := 2;
  constant REG_NNZ         : natural := 3;
  constant REG_ROW_PTR     : natural := 4;
  constant REG_COL_IND     : natural := 5;
  constant REG_VALUES      : natural := 6;
  constant REG_X_VEC       : natural := 7;
  constant REG_Y_VEC       : natural := 8;
  constant REG_CYCLE_CNT   : natural := 9;

  -- ===================== DSP / Calcul =====================
  constant MAC_INPUT_W     : natural := 8;
  constant MAC_OUTPUT_W    : natural := 32;

  -- ===================== Types utilitaires =====================
  subtype word_t   is std_logic_vector(31 downto 0);
  subtype addr_t   is unsigned(AVM_ADDR_W-1 downto 0);
  subtype int8_t   is signed(7 downto 0);
  subtype int32_t  is signed(31 downto 0);

  type int8_array4_t is array (0 to 3) of int8_t;

  -- ===================== États FSM =====================
  type fsm_state_t is (
    S_IDLE,
    S_LOAD_ROW_PTR,
    S_WAIT_ROW_PTR_0,
    S_WAIT_ROW_PTR_1,
    S_CALC_NNZ_ROW,
    S_LOAD_COL_VAL,
    S_WAIT_COL,
    S_WAIT_VAL,
    S_LOAD_X,
    S_WAIT_X,
    S_MAC,
    S_NEXT_NZ,
    S_WRITE_Y,
    S_WAIT_WRITE,
    S_NEXT_ROW,
    S_DONE
  );

end package spmv_pkg;

package body spmv_pkg is
end package body spmv_pkg;
