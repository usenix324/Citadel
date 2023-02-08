
// Copyright (c) 2013 Nokia, Inc.
// Copyright (c) 2013 Quanta Research Cambridge, Inc.

// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:

// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import FIFO::*;
import Vector::*;
import EchoInterface::*;

interface Echo;
   interface EchoRequest request;
endinterface

typedef struct {
	Bit#(16) a;
	Bit#(16) b;
} EchoPair deriving (Bits);

module mkEcho#(EchoResponse indication)(Echo);

    FIFO#(Bit#(32)) delay <- mkSizedFIFO(8);
    FIFO#(EchoPair) delay2 <- mkSizedFIFO(8);

    rule heard;
        delay.deq;
        indication.heard(delay.first);
    endrule

    rule heard2;
        delay2.deq;
        indication.heard2(delay2.first.b, delay2.first.a);
    endrule
   
   interface EchoRequest request;
      method Action say(Bit#(32) v);
   $display("say %h", v);
	 delay.enq(v);
      endmethod
      
      method Action say2(Bit#(16) a, Bit#(16) b);
   $display("say2 %h %h", a, b);
	 delay2.enq(EchoPair { a: a, b: b});
      endmethod
   endinterface
endmodule
