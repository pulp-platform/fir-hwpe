/*
 * Copyright (C) 2018-2019 ETH Zurich and University of Bologna
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/* 
 * Authors:  Francesco Conti <fconti@iis.ee.ethz.ch>
 */

#ifndef __HAL_FIR_H__
#define __HAL_FIR_H__

/* REGISTER MAP */
#define ARCHI_CL_EVT_ACC0 0
#define ARCHI_CL_EVT_ACC1 1
#define __builtin_bitinsert(a,b,c,d) (a | (((b << (32-c)) >> (32-c)) << d))


#define FIR_TRIGGER          0x00
#define FIR_ACQUIRE          0x04
#define FIR_FINISHED         0x08
#define FIR_STATUS           0x0c
#define FIR_RUNNING_JOB      0x10
#define FIR_SOFT_CLEAR       0x14

#define FIR_REG_X_ADDR       0x40
#define FIR_REG_H_ADDR       0x44
#define FIR_REG_Y_ADDR       0x48
#define FIR_REG_SHIFT_LENGTH 0x4c

/* LOW-LEVEL HAL */
#define FIR_ADDR_BASE 0x100000
#define FIR_ADDR_SPACE 0x00000100

#define HWPE_WRITE(value, offset) *(int *)(ARCHI_HWPE_ADDR_BASE + offset) = value
#define HWPE_READ(offset) *(int *)(ARCHI_HWPE_ADDR_BASE + offset)

static inline void fir_x_addr_set(unsigned int value) {
  HWPE_WRITE(value, FIR_REG_X_ADDR);
}

static inline void fir_y_addr_set(unsigned int value) {
  HWPE_WRITE(value, FIR_REG_Y_ADDR);
}

static inline void fir_h_addr_set(unsigned int value) {
  HWPE_WRITE(value, FIR_REG_H_ADDR);
}

static inline void fir_shift_length_set(
  unsigned int shift,
  unsigned int length
) {
  unsigned int res = 0;
  res |= ((length & 0xffff) << 16) |
         ((shift  & 0x1f));
  HWPE_WRITE(res, FIR_REG_SHIFT_LENGTH;
}

static inline void fir_trigger_job() {
  HWPE_WRITE(0, FIR_TRIGGER);
}

static inline int fir_acquire_job() {
  return HWPE_READ(FIR_ACQUIRE);
}

static inline unsigned int fir_get_status() {
  return HWPE_READ(FIR_STATUS);
}

static inline void fir_soft_clear() {
  volatile int i;
  HWPE_WRITE(0, FIR_SOFT_CLEAR);
}

#endif /* __HAL_FIR_H__ */

