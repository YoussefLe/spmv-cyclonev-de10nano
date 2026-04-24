-- =============================================================================
-- spmv_accelerator.vhd
-- Top-level : Avalon-MM Slave (registres HPS) + Avalon-MM Master (DMA) + FSM
-- Cyclone V DE10-Nano — SpMV Y = A·X  (CSR, Int8→Int32)
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spmv_pkg.all;

entity spmv_accelerator is
  port (
    clk               : in  std_logic;
    reset_n           : in  std_logic;

    -- ==================== Avalon-MM Slave (HPS → IP) ====================
    avs_address       : in  std_logic_vector(AVS_ADDR_W-1 downto 0);
    avs_read          : in  std_logic;
    avs_readdata      : out std_logic_vector(AVS_DATA_W-1 downto 0);
    avs_write         : in  std_logic;
    avs_writedata     : in  std_logic_vector(AVS_DATA_W-1 downto 0);
    avs_waitrequest   : out std_logic;

    -- ==================== Avalon-MM Master (IP → SDRAM) =================
    avm_address       : out std_logic_vector(AVM_ADDR_W-1 downto 0);
    avm_read          : out std_logic;
    avm_readdata      : in  std_logic_vector(AVM_DATA_W-1 downto 0);
    avm_readdatavalid : in  std_logic;
    avm_write         : out std_logic;
    avm_writedata     : out std_logic_vector(AVM_DATA_W-1 downto 0);
    avm_waitrequest   : in  std_logic;
    avm_byteenable    : out std_logic_vector(3 downto 0);
    avm_burstcount    : out std_logic_vector(3 downto 0)
  );
end entity spmv_accelerator;

architecture rtl of spmv_accelerator is

  -- ====================== Registres esclave ======================
  signal reg_ctrl       : word_t := (others => '0');
  signal reg_num_rows   : word_t := (others => '0');
  signal reg_nnz        : word_t := (others => '0');
  signal reg_row_ptr    : word_t := (others => '0');
  signal reg_col_ind    : word_t := (others => '0');
  signal reg_values     : word_t := (others => '0');
  signal reg_x_vec      : word_t := (others => '0');
  signal reg_y_vec      : word_t := (others => '0');
  signal reg_cycle_cnt  : unsigned(31 downto 0) := (others => '0');

  -- Bits de contrôle
  signal start_pulse    : std_logic := '0';
  signal done_flag      : std_logic := '0';
  signal busy_flag      : std_logic := '0';

  -- ====================== FSM ======================
  signal state          : fsm_state_t := S_IDLE;

  -- ====================== Compteurs / Indices ======================
  signal row_idx        : unsigned(31 downto 0) := (others => '0');
  signal num_rows_reg   : unsigned(31 downto 0) := (others => '0');
  signal rp0            : unsigned(31 downto 0) := (others => '0');
  signal rp1            : unsigned(31 downto 0) := (others => '0');
  signal nz_idx         : unsigned(31 downto 0) := (others => '0');
  signal nz_end         : unsigned(31 downto 0) := (others => '0');

  -- ====================== Données lues ======================
  signal col_val        : unsigned(31 downto 0) := (others => '0');
  signal a_val_packed   : std_logic_vector(31 downto 0) := (others => '0');
  signal x_word         : std_logic_vector(31 downto 0) := (others => '0');

  -- ====================== MAC / Accumulateur ======================
  signal accumulator    : signed(31 downto 0) := (others => '0');
  signal a_byte         : signed(7 downto 0)  := (others => '0');
  signal x_byte         : signed(7 downto 0)  := (others => '0');
  signal mac_product    : signed(15 downto 0) := (others => '0');

  -- ====================== Signaux Master internes ======================
  signal avm_read_r     : std_logic := '0';
  signal avm_write_r    : std_logic := '0';
  signal avm_address_r  : std_logic_vector(31 downto 0) := (others => '0');
  signal avm_writedata_r: std_logic_vector(31 downto 0) := (others => '0');

begin

  avs_waitrequest <= '0';

  -- Écriture registres par le HPS
  process(clk, reset_n)
  begin
    if reset_n = '0' then
      reg_ctrl     <= (others => '0');
      reg_num_rows <= (others => '0');
      reg_nnz      <= (others => '0');
      reg_row_ptr  <= (others => '0');
      reg_col_ind  <= (others => '0');
      reg_values   <= (others => '0');
      reg_x_vec    <= (others => '0');
      reg_y_vec    <= (others => '0');
      start_pulse  <= '0';
    elsif rising_edge(clk) then
      start_pulse <= '0';

      if avs_write = '1' then
        case to_integer(unsigned(avs_address)) is
          when REG_CTRL     =>
            reg_ctrl <= avs_writedata;
            if avs_writedata(0) = '1' and reg_ctrl(0) = '0' then
              start_pulse <= '1';
            end if;
          when REG_NUM_ROWS => reg_num_rows <= avs_writedata;
          when REG_NNZ      => reg_nnz      <= avs_writedata;
          when REG_ROW_PTR  => reg_row_ptr  <= avs_writedata;
          when REG_COL_IND  => reg_col_ind  <= avs_writedata;
          when REG_VALUES   => reg_values   <= avs_writedata;
          when REG_X_VEC    => reg_x_vec    <= avs_writedata;
          when REG_Y_VEC    => reg_y_vec    <= avs_writedata;
          when others       => null;
        end case;
      end if;

      if busy_flag = '1' then
        reg_ctrl(0) <= '0';
      end if;

      reg_ctrl(1) <= done_flag;
      reg_ctrl(2) <= busy_flag;
    end if;
  end process;

  -- Lecture registres par le HPS
  process(avs_address, reg_ctrl, reg_num_rows, reg_nnz,
          reg_row_ptr, reg_col_ind, reg_values,
          reg_x_vec, reg_y_vec, reg_cycle_cnt, done_flag, busy_flag)
  begin
    avs_readdata <= (others => '0');
    case to_integer(unsigned(avs_address)) is
      when REG_CTRL      => avs_readdata <= reg_ctrl;
      when REG_STATUS    => avs_readdata <= x"000000" & "00000" & busy_flag & done_flag & '0';
      when REG_NUM_ROWS  => avs_readdata <= reg_num_rows;
      when REG_NNZ       => avs_readdata <= reg_nnz;
      when REG_ROW_PTR   => avs_readdata <= reg_row_ptr;
      when REG_COL_IND   => avs_readdata <= reg_col_ind;
      when REG_VALUES    => avs_readdata <= reg_values;
      when REG_X_VEC     => avs_readdata <= reg_x_vec;
      when REG_Y_VEC     => avs_readdata <= reg_y_vec;
      when REG_CYCLE_CNT => avs_readdata <= std_logic_vector(reg_cycle_cnt);
      when others        => avs_readdata <= x"DEADBEEF";
    end case;
  end process;

  avm_read       <= avm_read_r;
  avm_write      <= avm_write_r;
  avm_address    <= avm_address_r;
  avm_writedata  <= avm_writedata_r;
  avm_byteenable <= "1111";
  avm_burstcount <= std_logic_vector(to_unsigned(BURST_LEN, 4));

  process(clk, reset_n)
    variable byte_sel   : integer range 0 to 3;
    variable addr_calc  : unsigned(31 downto 0);
  begin
    if reset_n = '0' then
      state          <= S_IDLE;
      done_flag      <= '0';
      busy_flag      <= '0';
      avm_read_r     <= '0';
      avm_write_r    <= '0';
      avm_address_r  <= (others => '0');
      avm_writedata_r<= (others => '0');
      row_idx        <= (others => '0');
      rp0            <= (others => '0');
      rp1            <= (others => '0');
      nz_idx         <= (others => '0');
      nz_end         <= (others => '0');
      col_val        <= (others => '0');
      accumulator    <= (others => '0');
      reg_cycle_cnt  <= (others => '0');
      a_val_packed   <= (others => '0');
      x_word         <= (others => '0');

    elsif rising_edge(clk) then

      if busy_flag = '1' then
        reg_cycle_cnt <= reg_cycle_cnt + 1;
      end if;

      case state is

        when S_IDLE =>
          done_flag <= '0';
          busy_flag <= '0';
          if start_pulse = '1' then
            busy_flag     <= '1';
            done_flag     <= '0';
            row_idx       <= (others => '0');
            num_rows_reg  <= unsigned(reg_num_rows);
            reg_cycle_cnt <= (others => '0');
            state         <= S_LOAD_ROW_PTR;
          end if;

        when S_LOAD_ROW_PTR =>
          addr_calc     := unsigned(reg_row_ptr) + (row_idx sll 2);
          avm_address_r <= std_logic_vector(addr_calc);
          avm_read_r    <= '1';
          state         <= S_WAIT_ROW_PTR_0;

        when S_WAIT_ROW_PTR_0 =>
          if avm_waitrequest = '0' then
            avm_read_r <= '0';
          end if;
          if avm_readdatavalid = '1' then
            rp0   <= unsigned(avm_readdata);
            addr_calc     := unsigned(reg_row_ptr) + ((row_idx + 1) sll 2);
            avm_address_r <= std_logic_vector(addr_calc);
            avm_read_r    <= '1';
            state         <= S_WAIT_ROW_PTR_1;
          end if;

        when S_WAIT_ROW_PTR_1 =>
          if avm_waitrequest = '0' then
            avm_read_r <= '0';
          end if;
          if avm_readdatavalid = '1' then
            rp1   <= unsigned(avm_readdata);
            state <= S_CALC_NNZ_ROW;
          end if;

        when S_CALC_NNZ_ROW =>
          nz_idx      <= rp0;
          nz_end      <= rp1;
          accumulator <= (others => '0');
          if rp0 = rp1 then
            state <= S_WRITE_Y;
          else
            state <= S_LOAD_COL_VAL;
          end if;

        when S_LOAD_COL_VAL =>
          addr_calc     := unsigned(reg_col_ind) + (nz_idx sll 2);
          avm_address_r <= std_logic_vector(addr_calc);
          avm_read_r    <= '1';
          state         <= S_WAIT_COL;

        when S_WAIT_COL =>
          if avm_waitrequest = '0' then
            avm_read_r <= '0';
          end if;
          if avm_readdatavalid = '1' then
            col_val <= unsigned(avm_readdata);
            addr_calc     := unsigned(reg_values) + (nz_idx(31 downto 2) & "00");
            avm_address_r <= std_logic_vector(addr_calc);
            avm_read_r    <= '1';
            state         <= S_WAIT_VAL;
          end if;

        when S_WAIT_VAL =>
          if avm_waitrequest = '0' then
            avm_read_r <= '0';
          end if;
          if avm_readdatavalid = '1' then
            a_val_packed <= avm_readdata;
            state        <= S_LOAD_X;
          end if;

        when S_LOAD_X =>
          addr_calc     := unsigned(reg_x_vec) + (col_val(31 downto 2) & "00");
          avm_address_r <= std_logic_vector(addr_calc);
          avm_read_r    <= '1';
          state         <= S_WAIT_X;

        when S_WAIT_X =>
          if avm_waitrequest = '0' then
            avm_read_r <= '0';
          end if;
          if avm_readdatavalid = '1' then
            x_word <= avm_readdata;
            state  <= S_MAC;
          end if;

        when S_MAC =>
          byte_sel := to_integer(nz_idx(1 downto 0));
          case byte_sel is
            when 0 => a_byte <= signed(a_val_packed( 7 downto  0));
            when 1 => a_byte <= signed(a_val_packed(15 downto  8));
            when 2 => a_byte <= signed(a_val_packed(23 downto 16));
            when 3 => a_byte <= signed(a_val_packed(31 downto 24));
          end case;

          byte_sel := to_integer(col_val(1 downto 0));
          case byte_sel is
            when 0 => x_byte <= signed(x_word( 7 downto  0));
            when 1 => x_byte <= signed(x_word(15 downto  8));
            when 2 => x_byte <= signed(x_word(23 downto 16));
            when 3 => x_byte <= signed(x_word(31 downto 24));
          end case;

          mac_product <= a_byte * x_byte;
          accumulator <= accumulator + resize(mac_product, 32);
          state       <= S_NEXT_NZ;

        when S_NEXT_NZ =>
          nz_idx <= nz_idx + 1;
          if (nz_idx + 1) = nz_end then
            state <= S_WRITE_Y;
          else
            state <= S_LOAD_COL_VAL;
          end if;

        when S_WRITE_Y =>
          addr_calc      := unsigned(reg_y_vec) + (row_idx sll 2);
          avm_address_r  <= std_logic_vector(addr_calc);
          avm_writedata_r<= std_logic_vector(accumulator);
          avm_write_r    <= '1';
          state          <= S_WAIT_WRITE;

        when S_WAIT_WRITE =>
          if avm_waitrequest = '0' then
            avm_write_r <= '0';
            state       <= S_NEXT_ROW;
          end if;

        when S_NEXT_ROW =>
          row_idx <= row_idx + 1;
          if (row_idx + 1) = num_rows_reg then
            state <= S_DONE;
          else
            state <= S_LOAD_ROW_PTR;
          end if;

        when S_DONE =>
          done_flag   <= '1';
          busy_flag   <= '0';
          avm_read_r  <= '0';
          avm_write_r <= '0';
          state       <= S_IDLE;

      end case;
    end if;
  end process;

end architecture rtl;
