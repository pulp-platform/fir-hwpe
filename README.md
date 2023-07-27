# Finite Impulse Response HWPE
This repository contains a simple but feature-complete Finite Impulse Response (FIR) filter HWPE designed in particular as a teaching aid.
Lecturers can split out part of the repository or remove material to prepare guided exercises and lab lectures to learn:
 - about data-flow acceleration in general, exploiting the HWPE-Stream paradigm in particular (with details on `ready`/`valid` handshakes,
   aides to understand how to write proper arithmetic SystemVerilog code, etc.)
 - about the control of a simple accelerator
 - about the HWPE streamer mechanism, and integration within a SoC platform (PULP in our case)
 - about the internal architecture of a FIR filter, experimenting with several possible architectures

## FIR HWPE structure
The FIR HWPE IP is fully described in SystemVerilog in the `rtl` folder. Each module is contained in a file with its own name, moreover there is a `fir_package` SV package containing constants data structure definitions.
The overall hierarchy of the FIR HWPE looks like this:

```
fir_top              # top-level of the IP
 |-> fir_ctrl        # main controller, including the central FSM, the `hwpe_ctrl_slave` module with register file
 |-> fir_streamer    # streamer containing two load units (`hci_core_source`) and one store unit (`hci_core_sink`)
 |-> fir_tap_buffer  # buffer for FIR taps
 |-> fir_datapath    # main multiply-accumulate datapath of the FIR filter, implementing a direct (Type I) filter
```

For simplicity, the FIR HWPE does not multiplex memory accesses into a single wide-bandwidth port (as customary in HCI accelerators) but rather it keeps the 3 ports related to separate streams distinct.

### Dependencies
The dependencies are managed via Bender (https://github.com/pulp-platform/bender), but the key HWPE IPs are manually inserted in the repository as git submodules for easier access, and are located in the `deps` folder:
```
deps/
 |-> hwpe-ctrl    # IPs necessary to build the HWPE slave interface for configuration
 |-> hwpe-stream  # IPs to implement the HWPE-Stream paradigm
 |-> hci          # IPs to connect HWPE-Stream streams with external HCI-protocol IPs
```
Other dependencies are automatically managed by Bender and kept in the hidden `.bender` folder to minimize clutter.

## Test infrastructure
The FIR HWPE can be tested at three levels: multiply-accumulate datapath, full datapath with tap buffer and multiply-accumulate, and full HWPE.
The testbenches are located in `rtl/verif`; for the former two ones everything related to the simulation is located there, whereas for the latter, also the `sw` folder is involved.

### Fetching dependencies
To build the simulation infrastructure one needs to first fetch all dependencies (by a combination of `git submodule` and Bender).
This can be performed by means of the following command:

```
make update-ips
```

### Building the RTL simulation infrastructure
The simulation infrastructure can then be built for one of the three targets available, which need to be selected by means of the `TESTBENCH` environment variable:
```
make hw-all TESTBENCH=tb_fir_datapath         # multiply-accumulate datapath only
make hw-all TESTBENCH=tb_fir_buffer_datapath  # full datapath with tap buffer and multiply-accumulate
make hw-all TESTBENCH=tb_fir_top              # full HWPE
```
The default is `TESTBENCH=tb_fir_datapath`.
These need to be performed with `vsim` in the path. In case a prefix must be added before the `vsim` commands (e.g., `questa-2022.1 vsim`), the `QUESTA` environment variable must be exported before the `make hw-all` command:
```
export QUESTA=questa-2022.1 # example of prefix setting before building the simulation infrastructure
make hw-all
```
The built simulation infrastructure, composed of QuestaSim models, `modelsim.ini`, etc., will appear in the `sim` folder.

### Building the SW
In case of the full HWPE simulation (`TESTBENCH=tb_fir_top`), you also need to build software as described in the following. In the other cases, skip to the next paragraph.
Building the software requires a RISC-V GCC compiler in the path, i.e., `riscv32-unknown-elf-gcc`.
The full software stack (tiny!) is hosted in the `sw` directory.
To build the test,  one needs to do:
```
make sw-all
```
This will generate two stimuli file, `stim_instr.txt` and `stim_data.txt`, in the `sim` folder.

### Running a test
To run a test, one needs to issue the `run` command while keeping the `TESTBENCH` variable in the environment:
```
make run TESTBENCH=tb_fir_datapath         # multiply-accumulate datapath only
make run TESTBENCH=tb_fir_buffer_datapath  # full datapath with tap buffer and multiply-accumulate
make run TESTBENCH=tb_fir_top              # full HWPE
```
Additional options can be specified:
```
make run gui=0                                  # run in CLI (default)
make run gui=1                                  # run in QuestaSim GUI
make run P_STALL_GEN=0.01 P_STALL_RECV=0.02     # specify 1% stall probability for stream generators and 2% for receivers (not for full HWPE)
make run P_STALL_GEN=0.01 TESTBENCH=tb_fir_top  # specify 1% stall probability for memories
```
