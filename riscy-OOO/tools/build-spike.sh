#!/bin/bash

# Copyright (c) 2017 Massachusetts Institute of Technology

# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use, copy,
# modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
# BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
# ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
# CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

. build.common

# Build riscv-isa-sim
OUTPUT_FILE=$OUTPUT_PATH/riscv-isa-sim.log
echo "Building riscv-isa-sim... (writing output to $OUTPUT_FILE)"
cd $RISCV
rm -rf build-isa-sim
mkdir -p build-isa-sim
cd build-isa-sim
../../riscv-isa-sim/configure --prefix=$RISCV --with-fesvr=$RISCV --with-isa=RV64IMAFD &> $OUTPUT_FILE
make -j$JOBS &>> $OUTPUT_FILE
make install &>> $OUTPUT_FILE

cd $STARTINGDIR

echo ""
echo "RV64G riscv-isa-sim compiled successfully."
