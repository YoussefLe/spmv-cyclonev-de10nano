# =============================================================================
# Makefile pour le driver HPS SpMV
# Compilation croisée ARM (DE10-Nano) ou native (test x86)
# =============================================================================

CROSS_COMPILE ?= arm-linux-gnueabihf-
CXX_ARM       = $(CROSS_COMPILE)g++
CXX_NATIVE    = g++

CXXFLAGS = -O2 -std=c++17 -Wall -Wextra

TARGET = spmv_driver
SRC    = spmv_hps_driver.cpp

arm:
	$(CXX_ARM) $(CXXFLAGS) -o $(TARGET)_arm $(SRC)
	@echo "[OK] Compilé pour ARM : $(TARGET)_arm"
	@echo "     Copier sur la DE10-Nano : scp $(TARGET)_arm root@<IP>:/root/"

native:
	$(CXX_NATIVE) $(CXXFLAGS) -DSIMULATION_MODE -o $(TARGET)_sim $(SRC)
	@echo "[OK] Compilé en simulation : $(TARGET)_sim"

clean:
	rm -f $(TARGET)_arm $(TARGET)_sim

.PHONY: arm native clean
