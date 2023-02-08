#!/usr/bin/python

# Copyright (c) 2018 Massachusetts Institute of Technology
# 
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use, copy,
# modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import argparse
import os
import glob
import subprocess

test_bin_dir = os.path.join(os.environ['RISCY_TOOLS'],
                            'riscv64-unknown-elf', 'share', 'riscv-tests')

def extract_asm_name(file_path):
    return os.path.splitext(os.path.basename(file_path))[0]

# legal test types
class TestType:
    assembly = 'assembly'
    assembly_fp = 'assembly_fp'
    benchmarks = 'benchmarks'
    custom = 'custom'

# assembly test programs
assembly_tests = map(extract_asm_name,
                     glob.glob(os.path.join(test_bin_dir,
                                            'isa', 'rv64ui-p-*.dump')))
# assembly_fp test programs
assembly_fp_tests = map(extract_asm_name,
                        glob.glob(os.path.join(test_bin_dir,
                                               'isa', 'rv64uf-p-*.dump')))
# benchmarks test programs
benchmarks_tests = [
    'median.riscv',
    'multiply.riscv',
    'qsort.riscv',
    'vvadd.riscv',
    'towers.riscv',
    'dhrystone.riscv',
    'sort.riscv',
    'rsort.riscv',
    'security_flush.riscv',
    #'spmv.riscv'
    ]

custom_tests = ['test_trusted_load.elf',
    'test_untrusted_load.elf']

# parse command line args
parser = argparse.ArgumentParser()
parser.add_argument('--exe', required = True,
                    metavar = 'UBUNTU_EXE', dest = 'exe')
parser.add_argument('--rom', required = True,
                    metavar = 'ROM', dest = 'rom')
parser.add_argument('--test', required = True,
                    metavar = 'TEST_TYPE', dest = 'test',
                    choices = [TestType.assembly,
                               TestType.assembly_fp,
                               TestType.benchmarks,
                               TestType.custom])
parser.add_argument('--cores', required = True,
                    metavar = 'CORE_NUM', dest = 'core_num')
parser.add_argument('--outdir', required = False,
                    metavar = 'OUT_DIR', dest = 'out_dir', default = 'out')
parser.add_argument('--log', action = 'store_true', dest =  'log')
args = parser.parse_args()

# set up the tests to run
out_dir = os.path.join(os.path.abspath(args.out_dir), args.test)
test_dir = ''
test_arg = ' --core-num {} --rom {} '.format(args.core_num, args.rom)
tests = []
if args.test == TestType.assembly:
    test_dir = os.path.join(test_bin_dir, 'isa')
    test_arg += ' --assembly-tests '
    tests = assembly_tests
elif args.test == TestType.assembly_fp:
    test_dir = os.path.join(test_bin_dir, 'isa')
    test_arg += ' --assembly-tests '
    tests = assembly_fp_tests
elif args.test == TestType.benchmarks:
    test_dir = os.path.join(test_bin_dir, 'benchmarks')
    tests = benchmarks_tests
elif args.test == TestType.custom:
    test_dir = os.path.join(test_bin_dir, 'custom')
    tests = custom_tests

# create output log folder and go to it
if not os.path.exists(out_dir):
    os.makedirs(out_dir)
os.chdir(out_dir)

for t in tests:
    test_prog = os.path.join(test_dir, t)
    test_log = 'log.txt' if args.log else '/dev/null'
    if not os.path.isfile(test_prog):
        print '[WARNING] {} does not exist'.format(test_prog)
    else:
        print 'Run ' + test_prog
        cmd = args.exe + test_arg + ' --elf ' + test_prog + ' > ' + test_log
        print 'Command ' + cmd
        subprocess.check_call(cmd, shell = True) # stop if fail a test
