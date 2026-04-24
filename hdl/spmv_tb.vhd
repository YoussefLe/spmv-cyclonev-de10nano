-- =============================================================================
-- spmv_tb.vhd
-- Testbench fonctionnel pour spmv_accelerator
-- Matrice test 3×3 :  A = [1,2,0; 0,3,4; 5,0,6]  X = [1,2,3]
-- CSR : row_ptr=[0,2,4,6] col_ind=[0,1,1,2,0,2] values=[1,2,3,4,5,6]
-- Y attendu = [5, 18, 23]
-- =============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.spmv_pkg.all;

entity spmv_tb is
end entity spmv_tb;

architecture sim of spmv_tb is

  signal clk               : std_logic := '0';
  signal reset_n           : std_logic := '0';
  signal avs_address       : std_logic_vector(AVS_ADDR_W-1 downto 0) := (others => '0');
  signal avs_read          : std_logic := '0';
  signal avs_readdata      : std_logic_vector(AVS_DATA_W-1 downto 0);
  signal avs_write         : std_logic := '0';
  signal avs_writedata     : std_logic_vector(AVS_DATA_W-1 downto 0) := (others => '0');
  signal avs_waitrequest   : std_logic;
  signal avm_address       : std_logic_vector(AVM_ADDR_W-1 downto 0);
  signal avm_read          : std_logic;
  signal avm_readdata      : std_logic_vector(AVM_DATA_W-1 downto 0) := (others => '0');
  signal avm_readdatavalid : std_logic := '0';
  signal avm_write         : std_logic;
  signal avm_writedata     : std_logic_vector(AVM_DATA_W-1 downto 0);
  signal avm_waitrequest   : std_logic := '0';
  signal avm_byteenable    : std_logic_vector(3 downto 0);
  signal avm_burstcount    : std_logic_vector(3 downto 0);

  constant CLK_PERIOD : time := 10 ns;

  type mem_t is array (0 to 255) of std_logic_vector(31 downto 0);
  signal mem : mem_t := (others => (others => '0'));

  constant BASE_ROW_PTR : natural := 16#000#;
  constant BASE_COL_IND : natural := 16#040#;
  constant BASE_VALUES  : natural := 16#080#;
  constant BASE_X       : natural := 16#0C0#;
  constant BASE_Y       : natural := 16#100#;

begin

  clk <= not clk after CLK_PERIOD/2;

  dut: entity work.spmv_accelerator
    port map (
      clk => clk, reset_n => reset_n,
      avs_address => avs_address, avs_read => avs_read,
      avs_readdata => avs_readdata, avs_write => avs_write,
      avs_writedata => avs_writedata, avs_waitrequest => avs_waitrequest,
      avm_address => avm_address, avm_read => avm_read,
      avm_readdata => avm_readdata, avm_readdatavalid => avm_readdatavalid,
      avm_write => avm_write, avm_writedata => avm_writedata,
      avm_waitrequest => avm_waitrequest, avm_byteenable => avm_byteenable,
      avm_burstcount => avm_burstcount
    );

  process(clk)
    variable word_addr : natural;
  begin
    if rising_edge(clk) then
      avm_readdatavalid <= '0';
      if avm_read = '1' and avm_waitrequest = '0' then
        word_addr := to_integer(unsigned(avm_address)) / 4;
        if word_addr <= 255 then
          avm_readdata <= mem(word_addr);
        else
          avm_readdata <= x"BAADF00D";
        end if;
        avm_readdatavalid <= '1';
      end if;
      if avm_write = '1' and avm_waitrequest = '0' then
        word_addr := to_integer(unsigned(avm_address)) / 4;
        if word_addr <= 255 then
          mem(word_addr) <= avm_writedata;
        end if;
      end if;
    end if;
  end process;

  avm_waitrequest <= '0';

  process
    procedure avs_wr(addr : natural; data : std_logic_vector(31 downto 0)) is
    begin
      avs_address   <= std_logic_vector(to_unsigned(addr, AVS_ADDR_W));
      avs_writedata <= data;
      avs_write     <= '1';
      wait until rising_edge(clk);
      avs_write     <= '0';
      wait until rising_edge(clk);
    end procedure;

    procedure avs_rd(addr : natural) is
    begin
      avs_address <= std_logic_vector(to_unsigned(addr, AVS_ADDR_W));
      avs_read    <= '1';
      wait until rising_edge(clk);
      avs_read    <= '0';
      wait until rising_edge(clk);
    end procedure;

  begin
    mem(BASE_ROW_PTR/4 + 0) <= std_logic_vector(to_unsigned(0, 32));
    mem(BASE_ROW_PTR/4 + 1) <= std_logic_vector(to_unsigned(2, 32));
    mem(BASE_ROW_PTR/4 + 2) <= std_logic_vector(to_unsigned(4, 32));
    mem(BASE_ROW_PTR/4 + 3) <= std_logic_vector(to_unsigned(6, 32));

    mem(BASE_COL_IND/4 + 0) <= std_logic_vector(to_unsigned(0, 32));
    mem(BASE_COL_IND/4 + 1) <= std_logic_vector(to_unsigned(1, 32));
    mem(BASE_COL_IND/4 + 2) <= std_logic_vector(to_unsigned(1, 32));
    mem(BASE_COL_IND/4 + 3) <= std_logic_vector(to_unsigned(2, 32));
    mem(BASE_COL_IND/4 + 4) <= std_logic_vector(to_unsigned(0, 32));
    mem(BASE_COL_IND/4 + 5) <= std_logic_vector(to_unsigned(2, 32));

    mem(BASE_VALUES/4 + 0) <= x"04030201";
    mem(BASE_VALUES/4 + 1) <= x"00000605";
    mem(BASE_X/4 + 0)      <= x"00030201";

    reset_n <= '0';
    wait for CLK_PERIOD * 5;
    reset_n <= '1';
    wait for CLK_PERIOD * 2;

    avs_wr(REG_NUM_ROWS, std_logic_vector(to_unsigned(3, 32)));
    avs_wr(REG_NNZ,      std_logic_vector(to_unsigned(6, 32)));
    avs_wr(REG_ROW_PTR,  std_logic_vector(to_unsigned(BASE_ROW_PTR, 32)));
    avs_wr(REG_COL_IND,  std_logic_vector(to_unsigned(BASE_COL_IND, 32)));
    avs_wr(REG_VALUES,   std_logic_vector(to_unsigned(BASE_VALUES, 32)));
    avs_wr(REG_X_VEC,    std_logic_vector(to_unsigned(BASE_X, 32)));
    avs_wr(REG_Y_VEC,    std_logic_vector(to_unsigned(BASE_Y, 32)));

    avs_wr(REG_CTRL, x"00000001");

    wait for CLK_PERIOD * 500;

    assert mem(BASE_Y/4 + 0) = std_logic_vector(to_signed(5, 32))
      report "FAIL Y[0]: got " & integer'image(to_integer(signed(mem(BASE_Y/4 + 0))))
      severity error;
    assert mem(BASE_Y/4 + 1) = std_logic_vector(to_signed(18, 32))
      report "FAIL Y[1]: got " & integer'image(to_integer(signed(mem(BASE_Y/4 + 1))))
      severity error;
    assert mem(BASE_Y/4 + 2) = std_logic_vector(to_signed(23, 32))
      report "FAIL Y[2]: got " & integer'image(to_integer(signed(mem(BASE_Y/4 + 2))))
      severity error;

    avs_rd(REG_CYCLE_CNT);
    report "Cycles: " & integer'image(to_integer(unsigned(avs_readdata)));
    report "=== TESTBENCH COMPLETE ===" severity note;
    wait;
  end process;

end architecture sim;
