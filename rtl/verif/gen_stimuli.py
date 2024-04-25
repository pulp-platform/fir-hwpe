import numpy as np
from numpy import cos, sin, pi, absolute, arange
import math
import struct

import scipy.signal

NB_BITS = 16

# filter parameters
samples = 512
sample_rate = 100
nyquist_rate = sample_rate/2
passband = 8
cutoff = 12
Ntaps = 50

# given a numpy array of int's returns its binary representation in two's complement,
# as an array of int's
def twos_complement(
    x,
    width = 16
):
    y = np.array(x)
    y[x<0] = 2**(width) + y[x<0]
    return y

# prints an int as hex string
def hex_repr(
    x,
    width = 16
):
    padding = 4 if x == 0 else \
              3 if np.bitwise_and(x, 0xfff0) == 0 else \
              2 if np.bitwise_and(x, 0xff00) == 0 else \
              1 if np.bitwise_and(x, 0xf000) == 0 else 0
    return np.base_repr(x, base=width, padding=padding)

# Function to write Stimuli
def stimuli_tensor2string(
    x,
    width = 16
):
    s = ""
    x = twos_complement(x, width=width)
    for el in x.flatten():
        s += """%s\n""" % hex_repr(el, width=width)
    return s.lower()

# Use firwin to create a lowpass FIR filter with Blackman window.
taps = np.zeros(Ntaps, np.float32)
taps = scipy.signal.firwin(Ntaps, cutoff/nyquist_rate, window=('blackman'))

# example signal
t = arange(samples) / sample_rate
x = cos(2*pi*0.5*t) + 0.2*sin(2*pi*2.5*t+0.1) + \
        0.2*sin(2*pi*15.3*t) + 0.1*sin(2*pi*16.7*t + 0.1) + \
            0.1*sin(2*pi*23.45*t+.8)

# Convert the taps and inputs to the Selected Fixed point format. Use the same names for the variables
x_abs_max = np.abs(x).max()
x_sign_bit  = 1
x_int_bits  = int(np.ceil(np.log2(x_abs_max)))
x_frac_bits = NB_BITS - x_sign_bit - x_int_bits

h_abs_max = np.abs(taps).max()
h_sign_bit  = 1
h_int_bits  = int(np.ceil(np.log2(h_abs_max)))
h_frac_bits = NB_BITS - h_sign_bit - h_int_bits

# Convert to Fixed Point
x_scaled = x / 2**(-x_frac_bits)
x_rounded = np.int64(np.round(x_scaled))
x_sat = np.clip(x_rounded, -2**(x_int_bits+x_frac_bits), 2**(x_int_bits+x_frac_bits)-1)

h_scaled = taps / 2**(-h_frac_bits)
h_rounded = np.int64(np.round(h_scaled))
h_sat = np.clip(h_rounded, -2**(h_int_bits+h_frac_bits), 2**(h_int_bits+h_frac_bits)-1)

# Generate golden output
y_scaled_doublebits = np.int64(np.round(scipy.signal.lfilter(np.float32(h_sat), np.asarray((1,)), np.float32(x_sat))))
y_scaled = np.right_shift(y_scaled_doublebits, h_frac_bits)
y_sat    = np.clip(y_scaled, -2**(x_int_bits+x_frac_bits), 2**(x_int_bits+x_frac_bits)-1)
ygold_fixed = y_sat * 2**(-x_frac_bits)

# Write out stimuli
with open("x_stim.txt", "w") as f:
    f.write(stimuli_tensor2string(x_sat, width=16))
with open("h_stim.txt", "w") as f:
    f.write(stimuli_tensor2string(h_sat, width=16))
with open("y_gold.txt", "w") as f:
    f.write(stimuli_tensor2string(y_sat, width=16))
    