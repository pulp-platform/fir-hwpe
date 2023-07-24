# Copyright (C) 2022-2023 ETH Zurich and University of Bologna
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# SPDX-License-Identifier: Apache-2.0
#
# Author: Yvan Tortorella (yvan.tortorella@unibo.it)
#         Francesco Conti (f.conti@unibo.it)
#

# Paths to folders
mkfile_path    := $(dir $(abspath $(firstword $(MAKEFILE_LIST))))
BUILD_DIR      ?= $(mkfile_path)/sim/build
QUESTA         ?=
BENDER_DIR     ?= .
BENDER         ?= sim/bender
WAVES          ?= $(mkfile_path)/sim/wave.do

compile_script ?= compile.tcl
compile_flag   ?= -suppress 2583 -suppress 13314

WORK_PATH = $(BUILD_DIR)
STIM_FILE_X = ../rtl/verif/x_stim.txt 
STIM_FILE_H = ../rtl/verif/h_stim.txt
STIM_FILE_Y = ../rtl/verif/y_gold.txt 
RESERVOIR_SIZE = 1024

# Useful Parameters
gui      ?= 0
P_STALL_GEN  ?= 0.0
P_STALL_RECV ?= 0.0

# Setup build object dirs
VSIM_INI=$(BUILD_DIR)/modelsim.ini
VSIM_LIBS=$(BUILD_DIR)/work

# Build implicit rules
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

SHELL := /bin/bash

# Generate instructions and data stimuli
# Run the simulation
run:
ifeq ($(gui), 0)
	cd $(BUILD_DIR);                       \
	$(QUESTA) vsim -c vopt_tb -do "run -a" \
	-gPROB_STALL_GEN=$(P_STALL_GEN)        \
	-gPROB_STALL_RECV=$(P_STALL_RECV)      \
	-gSTIM_FILE_X=$(STIM_FILE_X)           \
	-gSTIM_FILE_H=$(STIM_FILE_H)           \
	-gSTIM_FILE_Y=$(STIM_FILE_Y)           \
	-gRESERVOIR_SIZE=$(RESERVOIR_SIZE)
else
	cd sim; $(QUESTA) vsim vopt_tb          \
	-do "add log -r sim:/tb_fir_datapath/*" \
	-do "source $(WAVES)"                   \
	-gPROB_STALL_GEN=$(P_STALL_GEN)         \
	-gPROB_STALL_RECV=$(P_STALL_RECV)       \
	-gSTIM_FILE_X=$(STIM_FILE_X)            \
	-gSTIM_FILE_H=$(STIM_FILE_H)            \
	-gSTIM_FILE_Y=$(STIM_FILE_Y)            \
	-gRESERVOIR_SIZE=$(RESERVOIR_SIZE)
endif

# Download bender
sim:
	mkdir -p sim

$(BENDER): sim
	curl --proto '=https'  \
	--tlsv1.2 https://pulp-platform.github.io/bender/init -sSf | sh -s -- 0.24.0
	mv bender $(BENDER)

update-ips: $(BENDER)
	git submodule update --init
	$(BENDER) update
	$(BENDER) script vsim        \
	--vlog-arg="$(compile_flag)" \
	--vcom-arg="-pedanticerrors" \
	-t rtl -t test               \
	> sim/${compile_script}

build-hw: hw-all

# Hardware rules
hw-clean-all:
	rm -rf $(BUILD_DIR)
	rm -rf .bender
	rm -rf $(compile_script)
	rm -rf sim/modelsim.ini
	rm -rf sim/*.log
	rm -rf sim/transcript
	rm -rf .cached_ipdb.json

hw-opt:
	cd sim; $(QUESTA) vopt +acc=npr -o vopt_tb tb_fir_datapath -floatparameters+tb_fir_datapath -work $(BUILD_DIR)/work

hw-compile:
	cd sim; $(QUESTA) vsim -c +incdir+$(UVM_HOME) -do 'quit -code [source $(compile_script)]'

hw-lib:
	@touch sim/modelsim.ini
	@mkdir -p $(BUILD_DIR)
	@cd sim; $(QUESTA) vlib $(BUILD_DIR)/work
	@cd sim; $(QUESTA) vmap work $(BUILD_DIR)/work
	@chmod +w sim/modelsim.ini

hw-clean:
	rm -rf sim/transcript
	rm -rf sim/modelsim.ini

hw-all: hw-lib hw-compile hw-opt
