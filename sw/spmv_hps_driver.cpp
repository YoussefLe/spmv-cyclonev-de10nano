// =============================================================================
// spmv_hps_driver.cpp
// Driver C++ côté HPS (ARM Cortex-A9) pour l'accélérateur SpMV FPGA
// Cyclone V DE10-Nano — Linux /dev/mem + mmap
//
// Compilation croisée :
//   arm-linux-gnueabihf-g++ -O2 -std=c++17 -o spmv_driver spmv_hps_driver.cpp
// =============================================================================

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <chrono>
#include <string>
#include <vector>

// =============================================================================
//  Adresses mémoire Cyclone V (DE10-Nano)
// =============================================================================

constexpr uint32_t LW_H2F_BASE     = 0xFF200000;
constexpr uint32_t LW_H2F_SPAN     = 0x00200000;  // 2 MB
constexpr uint32_t SPMV_IP_OFFSET  = 0x00000000;
constexpr uint32_t H2F_BRIDGE_BASE = 0xC0000000;
constexpr uint32_t SHARED_MEM_PHYS = 0x30000000;
constexpr uint32_t SHARED_MEM_SPAN = 0x00100000;  // 1 MB

// =============================================================================
//  Registres de l'IP (offsets en mots de 32 bits)
// =============================================================================
namespace reg {
    constexpr uint32_t CTRL       = 0;
    constexpr uint32_t STATUS     = 1;
    constexpr uint32_t NUM_ROWS   = 2;
    constexpr uint32_t NNZ        = 3;
    constexpr uint32_t ROW_PTR    = 4;
    constexpr uint32_t COL_IND    = 5;
    constexpr uint32_t VALUES     = 6;
    constexpr uint32_t X_VEC      = 7;
    constexpr uint32_t Y_VEC      = 8;
    constexpr uint32_t CYCLE_CNT  = 9;
}

constexpr uint32_t CTRL_START = (1 << 0);
constexpr uint32_t CTRL_DONE  = (1 << 1);
constexpr uint32_t CTRL_BUSY  = (1 << 2);

// =============================================================================
//  Classe d'accès mémoire FPGA
// =============================================================================
class FPGAMemMap {
public:
    FPGAMemMap() : fd_(-1), lw_base_(nullptr), shared_base_(nullptr) {}
    ~FPGAMemMap() { close_all(); }

    bool open_all() {
        fd_ = open("/dev/mem", O_RDWR | O_SYNC);
        if (fd_ < 0) { perror("ERROR: /dev/mem (root requis)"); return false; }

        lw_base_ = static_cast<volatile uint32_t*>(
            mmap(nullptr, LW_H2F_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd_, LW_H2F_BASE));
        if (lw_base_ == MAP_FAILED) { perror("ERROR: mmap LW H2F"); lw_base_ = nullptr; return false; }

        shared_base_ = static_cast<volatile uint8_t*>(
            mmap(nullptr, SHARED_MEM_SPAN, PROT_READ | PROT_WRITE, MAP_SHARED, fd_, SHARED_MEM_PHYS));
        if (shared_base_ == MAP_FAILED) { perror("ERROR: mmap shared"); shared_base_ = nullptr; return false; }

        printf("[OK] /dev/mem ouvert, bridges mappés\n");
        printf("     LW H2F  : virt=%p  phys=0x%08X\n", lw_base_, LW_H2F_BASE);
        printf("     Shared  : virt=%p  phys=0x%08X\n", shared_base_, SHARED_MEM_PHYS);
        return true;
    }

    void close_all() {
        if (lw_base_)    { munmap(const_cast<uint32_t*>(lw_base_), LW_H2F_SPAN); lw_base_ = nullptr; }
        if (shared_base_) { munmap(const_cast<uint8_t*>(shared_base_), SHARED_MEM_SPAN); shared_base_ = nullptr; }
        if (fd_ >= 0)    { ::close(fd_); fd_ = -1; }
    }

    void write_reg(uint32_t index, uint32_t value) {
        volatile uint32_t* ip = lw_base_ + (SPMV_IP_OFFSET / sizeof(uint32_t));
        ip[index] = value;
    }

    uint32_t read_reg(uint32_t index) {
        volatile uint32_t* ip = lw_base_ + (SPMV_IP_OFFSET / sizeof(uint32_t));
        return ip[index];
    }

    volatile uint8_t* shared_ptr() { return shared_base_; }

    uint32_t fpga_addr(uint32_t offset) { return SHARED_MEM_PHYS + offset; }

private:
    int fd_;
    volatile uint32_t* lw_base_;
    volatile uint8_t*  shared_base_;
};

// =============================================================================
//  Structure CSR
// =============================================================================
struct CSRMatrix {
    uint32_t              num_rows;
    uint32_t              nnz;
    std::vector<uint32_t> row_ptr;
    std::vector<uint32_t> col_ind;
    std::vector<int8_t>   values;
};

CSRMatrix create_test_matrix() {
    CSRMatrix csr;
    csr.num_rows = 3; csr.nnz = 6;
    csr.row_ptr  = {0, 2, 4, 6};
    csr.col_ind  = {0, 1, 1, 2, 0, 2};
    csr.values   = {1, 2, 3, 4, 5, 6};
    return csr;
}

CSRMatrix create_cora_simulation() {
    CSRMatrix csr;
    csr.num_rows = 2708;
    srand(42);
    csr.row_ptr.push_back(0);
    uint32_t total_nnz = 0;
    for (uint32_t i = 0; i < csr.num_rows; i++) {
        uint32_t nnz_row = 2 + (rand() % 6);
        for (uint32_t j = 0; j < nnz_row; j++) {
            csr.col_ind.push_back(rand() % csr.num_rows);
            csr.values.push_back(static_cast<int8_t>(-128 + (rand() % 256)));
        }
        total_nnz += nnz_row;
        csr.row_ptr.push_back(total_nnz);
    }
    csr.nnz = total_nnz;
    return csr;
}

// =============================================================================
//  Layout mémoire partagée
// =============================================================================
constexpr uint32_t OFF_ROW_PTR = 0x00000;
constexpr uint32_t OFF_COL_IND = 0x10000;
constexpr uint32_t OFF_VALUES  = 0x20000;
constexpr uint32_t OFF_X_VEC   = 0x30000;
constexpr uint32_t OFF_Y_VEC   = 0x40000;

void load_data_to_shared(FPGAMemMap& fpga, const CSRMatrix& csr, const std::vector<int8_t>& x_vec) {
    volatile uint8_t* base = fpga.shared_ptr();

    volatile uint32_t* rp = reinterpret_cast<volatile uint32_t*>(base + OFF_ROW_PTR);
    for (size_t i = 0; i < csr.row_ptr.size(); i++) rp[i] = csr.row_ptr[i];

    volatile uint32_t* ci = reinterpret_cast<volatile uint32_t*>(base + OFF_COL_IND);
    for (size_t i = 0; i < csr.col_ind.size(); i++) ci[i] = csr.col_ind[i];

    volatile int8_t* vals = reinterpret_cast<volatile int8_t*>(base + OFF_VALUES);
    for (size_t i = 0; i < csr.values.size(); i++) vals[i] = csr.values[i];

    volatile int8_t* xv = reinterpret_cast<volatile int8_t*>(base + OFF_X_VEC);
    for (size_t i = 0; i < x_vec.size(); i++) xv[i] = x_vec[i];

    printf("[OK] Données CSR chargées en mémoire partagée\n");
}

std::vector<int32_t> read_y_result(FPGAMemMap& fpga, uint32_t num_rows) {
    volatile uint8_t* base = fpga.shared_ptr();
    volatile int32_t* yv = reinterpret_cast<volatile int32_t*>(base + OFF_Y_VEC);
    std::vector<int32_t> y(num_rows);
    for (uint32_t i = 0; i < num_rows; i++) y[i] = yv[i];
    return y;
}

std::vector<int32_t> spmv_cpu_reference(const CSRMatrix& csr, const std::vector<int8_t>& x_vec) {
    std::vector<int32_t> y(csr.num_rows, 0);
    for (uint32_t row = 0; row < csr.num_rows; row++) {
        int32_t acc = 0;
        for (uint32_t k = csr.row_ptr[row]; k < csr.row_ptr[row + 1]; k++) {
            acc += static_cast<int32_t>(csr.values[k]) * static_cast<int32_t>(x_vec[csr.col_ind[k]]);
        }
        y[row] = acc;
    }
    return y;
}

// =============================================================================
//  MAIN
// =============================================================================
int main(int argc, char* argv[]) {
    printf("==============================================\n");
    printf("  SpMV FPGA Accelerator — DE10-Nano Driver\n");
    printf("  Green AI — GNN (Cora) — Int8/Int32\n");
    printf("==============================================\n\n");

    bool use_cora = (argc > 1 && std::string(argv[1]) == "--cora");
    CSRMatrix csr;
    std::vector<int8_t> x_vec;

    if (use_cora) {
        printf("[MODE] Simulation Cora (2708 nœuds)\n\n");
        csr = create_cora_simulation();
        x_vec.resize(csr.num_rows);
        srand(123);
        for (auto& v : x_vec) v = static_cast<int8_t>(-128 + (rand() % 256));
    } else {
        printf("[MODE] Test 3×3 (vérification fonctionnelle)\n\n");
        csr   = create_test_matrix();
        x_vec = {1, 2, 3};
    }

    FPGAMemMap fpga;
    if (!fpga.open_all()) return EXIT_FAILURE;

    load_data_to_shared(fpga, csr, x_vec);

    printf("\n[STEP] Configuration des registres IP...\n");
    fpga.write_reg(reg::NUM_ROWS, csr.num_rows);
    fpga.write_reg(reg::NNZ,      csr.nnz);
    fpga.write_reg(reg::ROW_PTR,  fpga.fpga_addr(OFF_ROW_PTR));
    fpga.write_reg(reg::COL_IND,  fpga.fpga_addr(OFF_COL_IND));
    fpga.write_reg(reg::VALUES,   fpga.fpga_addr(OFF_VALUES));
    fpga.write_reg(reg::X_VEC,    fpga.fpga_addr(OFF_X_VEC));
    fpga.write_reg(reg::Y_VEC,    fpga.fpga_addr(OFF_Y_VEC));

    printf("  NUM_ROWS = %u\n", fpga.read_reg(reg::NUM_ROWS));
    printf("  ROW_PTR  = 0x%08X\n", fpga.read_reg(reg::ROW_PTR));
    printf("  Y_VEC    = 0x%08X\n", fpga.read_reg(reg::Y_VEC));

    printf("\n[STEP] Déclenchement START...\n");
    auto t_start = std::chrono::high_resolution_clock::now();
    fpga.write_reg(reg::CTRL, CTRL_START);

    uint32_t poll_count = 0;
    constexpr uint32_t MAX_POLLS = 100000000;
    while (poll_count < MAX_POLLS) {
        if (fpga.read_reg(reg::CTRL) & CTRL_DONE) break;
        poll_count++;
        if ((poll_count % 1000000) == 0)
            printf("  ... polling (%u M)\n", poll_count / 1000000);
    }

    auto t_end = std::chrono::high_resolution_clock::now();
    double elapsed_ms = std::chrono::duration<double, std::milli>(t_end - t_start).count();

    if (poll_count >= MAX_POLLS) {
        printf("[ERREUR] Timeout !\n");
        fpga.close_all();
        return EXIT_FAILURE;
    }

    uint32_t fpga_cycles = fpga.read_reg(reg::CYCLE_CNT);
    printf("\n[RÉSULTATS]\n");
    printf("  FPGA cycles : %u\n", fpga_cycles);
    printf("  Temps réel  : %.3f ms\n", elapsed_ms);

    auto y_fpga = read_y_result(fpga, csr.num_rows);

    auto t_cpu_start = std::chrono::high_resolution_clock::now();
    auto y_cpu = spmv_cpu_reference(csr, x_vec);
    auto t_cpu_end = std::chrono::high_resolution_clock::now();
    printf("  Temps CPU   : %.3f ms\n",
           std::chrono::duration<double, std::milli>(t_cpu_end - t_cpu_start).count());

    uint32_t errors = 0;
    for (uint32_t i = 0; i < csr.num_rows; i++) {
        if (y_fpga[i] != y_cpu[i]) {
            if (errors < 10) printf("  MISMATCH Y[%u]: FPGA=%d CPU=%d\n", i, y_fpga[i], y_cpu[i]);
            errors++;
        }
    }

    if (errors == 0) printf("\n  ✅ VÉRIFICATION OK — %u résultats identiques\n", csr.num_rows);
    else printf("\n  ❌ %u ERREURS sur %u résultats\n", errors, csr.num_rows);

    if (use_cora) {
        printf("\n[GREEN AI METRICS]\n");
        double cpu_ms = std::chrono::duration<double, std::milli>(t_cpu_end - t_cpu_start).count();
        printf("  Speedup FPGA/CPU : %.2fx\n", cpu_ms / elapsed_ms);
        printf("  Énergie FPGA     : %.3f mJ  (3W × %.3f ms)\n",
               3.0 * (fpga_cycles / 50000.0) / 1000.0, fpga_cycles / 50000.0);
        printf("  Énergie CPU      : %.3f mJ  (2W × %.3f ms)\n",
               2.0 * cpu_ms / 1000.0, cpu_ms);
    }

    printf("\n[Aperçu Y] :\n");
    for (uint32_t i = 0; i < std::min(csr.num_rows, 10u); i++)
        printf("  Y[%u] = %d\n", i, y_fpga[i]);

    fpga.close_all();
    printf("\n[FIN] Driver terminé.\n");
    return EXIT_SUCCESS;
}
