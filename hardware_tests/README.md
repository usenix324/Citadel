# hardware_tests

This repo contains a set of hardware tests to check hardware memory islation mechanisms for the Citadel processor. 

These tests can be run on both FPGA as well as simulation through QEMU or Verilator. Note that performance counters (i.e. writing to CSR `0x801`) cannot be used on QEMU.

To build the tests, run

`make elfs`


