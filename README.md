## Usenix Security #324: Citadel

Citadel is an open-source side-channel-resistant enclave platform with secure shared memory running on a speculative out-of-order mul-ticore processor.

This repository contains a snapshot of most software elements used in, or developped for Citadel.
In particular, it provides a fully functional software stack to test Citadel through simulation (QEMU/Verilator) as well as FPGAs (AWS F1).

Instructions to build can be found in each sub directories.
Nevertheless, this is not recommended as this repository hasn't been fully tested and is mostly made available to reviewers for consultation.
For instance, some folders have only been placed at the root of the repository to be easily findable.
Striped out of their original location, they might not be buildable.

We will make sure all the repos can be easily built for artefact evaluation.

The repo contains the following subdirectories:

#security_monitor
The Citadel Security Monitor

#secure_bootloader
The Citadel Secure Bootloader

#linux
Srcipts to build and run Linux on top of the Citadel SM

#sm_kernel_module
Linux Kernel Module and test code to launch an enclave from user-mode in Linux
(copied out of the linux/build_linux folder)

#crypto_test
Enclave for an end-to-end demo: A cryptographic library isolated inside an enclave.
(copied out of the security_monitor folder)

#micropython
Enclave for an end-to-end demo: A light python runtime isolated inside an enclave.
The port can be found in ports/bare-riscv

#spectre
Originally a branch of the security_monitor repository.
The untrusted_infra folder contain the attack and victim code for the demo specter
attack presented in the Citadel paper.

#riscv-gnu-toolchain
The toolchain to compile RISC-V code can be found at:

https://github.com/riscv-collab/riscv-gnu-toolchain

#riscy-OOO
BSV Source Code for Citadel (built on top of MI6 / Riscy-OOO). 
Contains the modification for the secure shared memory mechanism introduced by Citadel.
Contains proper wrappers and libraries to compile/run on AWS C4/F1.

#qemu-sanctum
QEMU with a new target with sanctum hardware mechanism that matches the Citadel processors.
Used to debug software components.

#hardware_tests
Simple ASM tests to test Citadel hardware isolation mechanisms.
