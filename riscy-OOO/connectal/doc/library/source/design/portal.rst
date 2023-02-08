
==================
What is Connectal?
==================

Connectal provides a hardware-software interface for applications split
between user mode code and custom hardware in an FPGA or ASIC.

Connectal can automaticaly build the software and hardware glue for a
message based interface and also provides for configuring and using
shared memory between applications and hardware. Communications
between hardware and software are provided by a bidirectional flow of
events and regions of memory shared between hardware and software.
Events from software to hardware are called requests and events from
hardware to software are called indications, but in fact they are
symmetric.

.. _bsvdocumentation: http://wiki.bluespec.com/Home/BSV-Documentation
.. _bluespecdotcom:     http://www.bluespec.com/

Lexicon
-------

connectal:: The name of the project, whose goal is to ease the task of
building applications composed of hardware and software components.
Programmers use bsv as an IDL to specify the interface between the
hardware and software components.  A combination of generated code and
libraries coordinate the data-flow between the program modules.
Because the HW and SW stacks are customized for each application, the
overheads associated with communicating across the HW/SW boundary are
low.

HW/SW interface :: portal

bsv:: Bluespec System Verilog.  bsv is a language for describing hardware that is might higher level than verilog. See {bsvdocumentation}[BSV Documentation] and {bluespecdotcom}[Bluespec, Inc].

bluespec:: Shorthand for Bluespec System Verilog (bsv)

indexterm:portal
portal:: a logical request/indication pair is referred to as a portal.  current tools require their specification in the IDL to be syntactically identifiable (i.e. fooRequest/fooIndication).  An application can make use of multiple portals, which may be specified independently.

request interface:: These methods are implemented by the application hardware to be invoked by application software.   A bsv interface consisting of ‘Action’ methods.  Because of the ‘Action’ type, data flow across this interface is unidirectional (SW -> HW).

indication interface:: The dual of a request interface, indication interfaces are ‘Action’ methods implemented by application software to be invoked by application hardware.   As with request interfaces, the data flow across this interface is unidirectional, but in the opposite direction.

pcieportal/zynqportal:: these two loadable kernel modules implement the minimal set of driver functionality.  Specifically, they expose portal HW registers to SW through mmap, and set up interrupts to notify SW that an indication method has been invoked by HW.  

portalalloc:: This loadable kernel module exposes a subset of dma-buf functionality to user-space software (though a set of ioctl commands) to allocate and manage memory regions which can be shared between SW and HW processes.   Maintaining coherence of the allocated buffers between processes is not automatic: ioctl commands for flush/invalidate are provided to be invoked explicitly by the users if necessary. 

connectalgen:: The name of the interface compiler which takes as input the bsv interface specification along with a description of a target platform and generates logic in both HW and SW to support this interface across the communication fabric.

Example setups:
---------------

A zedboard ( http://www.zedboard.org/ ),
with Android running on the embedded ARM processors (the Processing
System 7), an application running as a user process, and custom
hardware configured into the Programmable Logic FPGA.

An x86 server, with Linux running on the host processor, an
application running partly as a user process on the host and partly as
hardware configured into an FPGA connected by PCI express (such as the
Xilinx VC707
(http://www.xilinx.com/products/boards-and-kits/EK-V7-VC707-G.htm).

Background
----------

When running part or all of an application in an FPGA, it is usually
necessary to communicate between code running in user mode on the host
and the hardware.  Typically this has been accomplished by custom
device drivers in the OS, or by shared memory mapped between the
software and the hardware, or both.  Shared memory has been
particularly troublesome under Linux or Android, because devices
frequently require contiguous memory, and the mechanisms for
guaranteeing successful memory allocation often require reserving the
maximum amount of memory at boot time.

Portal tries to provide convenient solutions to these problems in a portable way.

It is desirable to have

* low latency for small messages

* high bandwidth for large messages

* notification of arriving messages

* asynchronous replies to messages

* support for hardware simulation by a separate user mode process

* support for shared memory (DMA) between hardware and software


Overview
--------

Portal is implemented as a loadable kernel module device driver for Linux/Android and a set of tools to automatically construct the hardware and software glue necessary for communications.

Short messages are handled by programmed I/O.  The message interface
from software to hardware (so called "requests") is defined as a bsv
interface containing a number of Action methods, each with a name and
typed arguments.  The interface generator creates all the software and
hardware glue so that software invocations of the interface stubs flow
through to, and are turned into bsv invocations of the matching
hardware.  The machinery does not have flow control. Software is
responsible for not overrunning the hardware.  There is a debug
mechanism which will return the request type of a failed method, but
it does not tell which invocation failed.  Hardware to software
interfaces (so called “indications”) are likewise defined by bsv
interfaces containing Action methods. Hardware invocations of these
methods flow through to and cause software calls to corresponding
user-supplied functions.  In the current implementation there is flow
control, in that the hardware will stall until there is room for a
hardware to software message.  There is also a mechanism for software
to report a failure, and there is machinery for these failures to be
returned to the hardware.

    ["seqdiag",target="request-response-1.png"]
    ---------------------------------------------------------------------
    {
      // edge label
      SW -> HW [label = "request"];
      SW <- HW [label = "indication"];
    }
    ---------------------------------------------------------------------

Portals do not have to be structured as request/response. Hardware can
send messages to software without a prior request from software.

    ["seqdiag",target="indication-only.png"]
    ---------------------------------------------------------------------
    {
      // edge label
      SW <- HW [label = "indication"];
    }
    ---------------------------------------------------------------------

Incoming messages can cause host interrupts, which wake up the device
driver, which can wake up the user mode application by using the
select(2) or poll(2) interfaces.


Most of the time, communications between hardware and software will
proceed without requiring use of the OS.  User code will read and
write directly to memory mapped I/O space. Library code will poll for
incoming messages, and [true? eventually time out and call poll(2).
Only when poll(2) or select(2) are called will the device driver
enable hardware interrupts.  Thus interrupts are only used to wake up
software after a quiet period.

The designer specifies a set of hardware functions that can be called
from software, and a set of actions that the hardware can take which
result in messages to software. Portal tools take this specification
and build software glue modules to translate software function calls
into I/O writes to hardware registers, and to report hardware events
to software.

For larger memory and OS bypass (OS bypass means letting the user mode
application talk directly to the hardware without using the OS except
for setup), portal implements shared memory.  Portal memory objects
are allocated by the user mode program, and appear as Linux file
descriptors. The user can mmap(2) the file to obtain user mode access
to the shared memory region. Portal does not assure that the memory is
physically contiguous, but does pin it to prevent the OS from reusing
the memory.  An FPGA DMA controller module is provided that gives the
illusion of contiguous memory to application hardware, while under the
covers using a translation table of scattered addresses.

The physical addresses are provided to the user code in order to
initialize the dma controller, and address "handles" are provided for
the application hardware to use.

The DMA controller provides Bluespec objects that support streaming access with automatic page crossings, or random access.

An Example
----------

An application developer will typically write the hardware part of the
application in Bluespec and the software part of the application in C
or C++.  In a short example, there will be a bsv source file for the
hardware and a cpp source file for the application.

The application developer is free to specify whatever hardware-software interface makes sense.

Refer to https://github.com/cambridgehackers/connectal

In the examples directory, see [simple](../examples/simple/).  The
file [Simple.bsv](../examples/simple/Simple.bsv) defines the hardware,
and testsimple.cpp supplies the software part. In this case, the
software part is a test framework for the hardware.

Simple.bsv declares a few `struct` and `enum` types::

    typedef struct{
       Bit#(32) a;
       Bit#(32) b;
       } S1 deriving (Bits);

    typedef struct{
       Bit#(32) a;
       Bit#(16) b;
       Bit#(7) c;
       } S2 deriving (Bits);

    typedef enum {
       E1Choice1,
       E1Choice2,
       E1Choice3
       } E1 deriving (Bits,Eq);

    typedef struct{
       Bit#(32) a;
       E1 e1;
       } S3 deriving (Bits);

Simple.bsv defines the actions (called Requests) that software can use
to cause the hardware to act, and defines the notifications (called
Indications) that the hardware can use to signal the software. ::

    interface SimpleIndication;
	method Action heard1(Bit#(32) v);
	method Action heard2(Bit#(16) a, Bit#(16) b);
	method Action heard3(S1 v);
	method Action heard4(S2 v);
	method Action heard5(Bit#(32) a, Bit#(64) b, Bit#(32) c);
	method Action heard6(Bit#(32) a, Bit#(40) b, Bit#(32) c);
	method Action heard7(Bit#(32) a, E1 e1);
    endinterface

    interface SimpleRequest;
	method Action say1(Bit#(32) v);
	method Action say2(Bit#(16) a, Bit#(16) b);
	method Action say3(S1 v);
	method Action say4(S2 v);
	method Action say5(Bit#(32)a, Bit#(64) b, Bit#(32) c);
	method Action say6(Bit#(32)a, Bit#(40) b, Bit#(32) c);
	method Action say7(S3 v);
    endinterface

Software can start the hardware working via say, say2, ... Hardware
signals back to software with heard and heard2 and so fort.  In the
case of this example, say and say2 merely echo their arguments back to
software.

The definitions in the bsv file are used by the connectal infrastructure ( a python program)  to automatically create corresponding c++ interfaces.::

    ../../connectalgen -Bbluesim -p bluesim -x mkBsimTop \
         -s2h SimpleRequest \
         -h2s SimpleIndication \
         -s testsimple.cpp \
         -t ../../bsv/BsimTop.bsv  Simple.bsv Top.bsv

The tools have to be told which interface records should be used for
Software to Hardware messages and which should be used for Hardware to
Software messages. These interfaces are given on the command line for
genxpprojfrombsv

connectalgen constructs all the hardware and software modules
needed to wire up portals. This is sort of like an RPC compiler for
the hardware-software interface. However, unlike an RPC each method is
asynchronous.

The user must also create a toplevel bsv module Top.bsv, which
instantiates the user portals, the standard hardware environment, and
any additional hardware modules.

Rather than constructing the *makefilegen* command line from
scratch, the examples in connectal use include
*Makefile.connectal* and define some *make*
variables.

Here is the Makefile for the `simple` example::

    CONNECTALDIR?=../..
    INTERFACES = SimpleRequest SimpleIndication
    BSVFILES = Simple.bsv Top.bsv
    CPPFILES=testsimple.cpp

    include $(CONNECTALDIR)/Makefile.connectal



Designs outside the connectal directory using `connectal` may also include `Makefile.connectal`::

    CONNECTALDIR?=/scratch/connectal
    INTERFACES = ...
    BSVFILES = ...
    CPPFILES = ...
    include $(CONNECTALDIR)/Makefile.connectal

simple/Top.bsv
---------------

Each CONNECTAL design implements [Top.bsv](../examples/simple/Top.bsv) with some standard components.

It defines the `IfcNames` enum, for use in identifying the portals between software and hardware::

    typedef enum {SimpleIndication, SimpleRequest} IfcNames deriving (Eq,Bits);

It defines `mkConnectalTop`, which instantiates the wrappers, proxies, and the design itself::

    module mkConnectalTop(StdConnectalTop#(addrWidth));



:bsv:module:StdConnectalTop is parameterized by `addrWidth` because Zynq and x86 have different width addressing. `StdConnectalTop` is a typedef::

    typedef ConnectalTop#(addrWidth,64,Empty)     StdConnectalTop#(numeric type addrWidth);

The "64" specifies the data width and `Empty` specifies the empty
interface is exposed as pins from the design. In designs using HDMI,
for example, `Empty` is replaced by `HDMI`.  On some platforms, the
design may be able to use different data widths, such as 128 bits on
x86/PCIe.

Next, `mkConnectalTop` instantiates user portals::

    // instantiate user portals
       SimpleIndicationProxy simpleIndicationProxy <- mkSimpleIndicationProxy(SimpleIndication);

Instantiate the design::

       SimpleRequest simpleRequest <- mkSimpleRequest(simpleIndicationProxy.ifc);

Instantiate the wrapper for the design::

       SimpleRequestWrapper simpleRequestWrapper <- mkSimpleRequestWrapper(SimpleRequest,simpleRequest);

Collect the portals into a vector::

       Vector#(2,StdPortal) portals;
       portals[0] = simpleRequestWrapper.portalIfc; 
       portals[1] = simpleIndicationProxy.portalIfc;

Create an interrupt multiplexer from the vector of portals::

       let interrupt_mux <- mkInterruptMux(portals);

Create the system directory, which is used by software to locate each portal via the `IfcNames` enum::

       // instantiate system directory
       StdDirectory dir <- mkStdDirectory(portals);
       let ctrl_mux <- mkAxiSlaveMux(dir,portals);

The following generic interfaces are used by the platform specific top BSV module::

       interface interrupt = interrupt_mux;
       interface ctrl = ctrl_mux;
       interface m_axi = null_axi_master;
       interface leds = echoRequestInternal.leds;

    endmodule : mkConnectalTop

simple/testsimple.cpp
---------------------

CONNECTAL generates header files declaring wrappers for
hardware-to-software interfaces and proxies for software-to-hardware
interfaces. These will be in the "jni/" subdirectory of the project directory. ::

    #include "SimpleIndication.h"
    #include "SimpleRequest.h"


It also declares software equivalents for structs and enums declared in the processed BSV files::

    #include "GeneratedTypes.h"


CONNECTAL generates abstract virtual base classes for each Indication interface. ::

    class SimpleIndicationWrapper : public Portal {

    public:
	...
	SimpleIndicationWrapper(int id, PortalPoller *poller = 0);
	virtual void heard1 ( const uint32_t v )= 0;
	...
    };

Implement subclasses of the wrapper in order to define the callbacks::

    class SimpleIndication : public SimpleIndicationWrapper
    {  
    public:
      ...
	virtual void heard1(uint32_t a) {
	  fprintf(stderr, "heard1(%d)\n", a);
	  assert(a == v1a);
	  incr_cnt();
	}
	...
    };

To connect these classes to the hardware, instantiate them using the
`IfcNames` enum identifiers. CONNECTAL prepends the name of the type
because C++ does not support overloading of enum tags. ::

    SimpleIndication *indication = new SimpleIndication(IfcNames_SimpleIndication);
    SimpleRequestProxy *device = new SimpleRequestProxy(IfcNames_SimpleRequest);


Create a thread for handling notifications from hardware::

    pthread_t tid;
    if(pthread_create(&tid, NULL,  portalExec, NULL)){
      exit(1);
    }

Now the software invokes hardware methods via the proxy::

    device->say1(v1a);  

    device->say2(v2a,v2b);


Simple Example Design Structure
-------------------------------

The `simple` example consists of the following files::

    Simple.bsv
    Makefile
    Top.bsv
    testsimple.cpp

After running `make BOARD=zedboard verilog` in the `simple` directory,
the `zedboard` project directory is created, populated by the generated files.

A top level `Makefile` is created::

    zedboard/Makefile

makefilegen generates wrappers for software-to-hardware interfaces and proxies for hardware-to-software interfaces::

    zedboard/sources/mkzynqtop/SimpleIndicationProxy.bsv
    zedboard/sources/mkzynqtop/SimpleRequestWrapper.bsv

Connectal supports Android on Zynq platforms, so connectalgen generates `jni/Android.mk` for `ndk-build`::

    zedboard/jni/Android.mk
    zedboard/jni/Application.mk

Connectal generates `jni/Makefile` to compile the software for PCIe platforms (vc707 and kc705):

    zedboard/jni/Makefile

CONNECTAL generates software proxies for software-to-hardware interfaces and software wrappers for hardware-to-software interfaces::

    zedboard/jni/SimpleIndication.h
    zedboard/jni/SimpleIndication.cpp
    zedboard/jni/SimpleRequest.cpp
    zedboard/jni/SimpleRequest.h

CONNECTAL also generates `GeneratedTypes.h` for struct and enum types in the processed BSV source files::

    zedboard/jni/GeneratedTypes.h

CONNECTAL copies in standard and specified constraints files::

    zedboard/constraints/design_1_processing_system7_1_0.xdc
    zedboard/constraints/zedboard.xdc

CONNECTAL generates several TCL files to run `vivado`. 

The `board.tcl` file specifies `partname`, `boardname`, and `connectaldir` for the other TCL scripts.::

    zedboard/board.tcl

To generate an FPGA bit file, run `make bits`. This runs vivado with the `mkzynqtop-impl.tcl` script.::

    zedboard/mkzynqtop-impl.tcl


make verilog
^^^^^^^^^^^^

Compiling to verilog results in the following verilog files::

    zedboard/verilog/top/mkSimpleIndicationProxySynth.v
    zedboard/verilog/top/mkZynqTop.v

Verilog library files referenced in the design are copied for use in synthesis.::

    zedboard/verilog/top/FIFO1.v
    ...

make bits
^^^^^^^^^

Running `make bits` in the zedboard directory results in timing reports::

    zedboard/bin/mkzynqtop_post_place_timing_summary.rpt
    zedboard/bin/mkzynqtop_post_route_timing_summary.rpt
    zedboard/bin/mkzynqtop_post_route_timing.rpt

and some design checkpoints::

    zedboard/hw/mkzynqtop_post_synth.dcp
    zedboard/hw/mkzynqtop_post_place.dcp
    zedboard/hw/mkzynqtop_post_route.dcp

and the FPGA configuration file in .bit and .bin formats::

    zedboard/hw/mkZynqTop.bit
    zedboard/hw/mkZynqTop.bin

make android_exe
^^^^^^^^^^^^^^^^

CONNECTAL supports Android 4.0 on Zynq platforms. It generates
`jni/Android.mk` which is used by `ndk-build` to create a native
Android executable.::

    make android_exe

This produces the ARM elf executable::

    libs/armeabi/android_exe

make run
^^^^^^^^

For Zynq platforms::

    make run

will copy the Android executable and FPGA configuration file to the
target device, program the FPGA, and run the executable. See
[run.android](../scripts/run.android) for details.

It uses `checkip` to determine the IP address of the
device via a USB console connection to the device (it is built/installed
on the host machine from the git repo cambridgehackers/consolable). If the target is
not connected to the build machine via USB, specify the IP address of
the target manually::

    make RUNPARAM=ipaddr run

For PCIe platforms, `make run` programs the FPGA via USB and runs the software locally.

For bluesim, `make run` invokes bluesim on the design and runs the software locally.

Shared Memory
-------------

Shared Memory Hardware
^^^^^^^^^^^^^^^^^^^^^^

In order to use shared memory, the hardware design instantiates a DMA module in Top.bsv::

   AxiDmaServer#(addrWidth,64) dma <- mkAxiDmaServer(dmaIndicationProxy.ifc, readClients, writeClients);

The AxiDmaServer multiplexes read and write requests from the
clients, translates DMA addresses to physical addresses, initiates bus
transactions to memory, and delivers responses to the clients.

DMA requests are specified with respect to "portal" memory allocated
by software and identified by a `pointer`.

Requests and responses are tagged in order to enable pipelining::

    typedef struct {
       SGLId pointer;
       Bit#(MemOffsetSize) offset;
       Bit#(8) burstLen;
       Bit#(6)  tag;
       } MemRequest deriving (Bits);

    typedef struct {
       Bit#(dsz) data;
       Bit#(6) tag;
       } MemData#(numeric type dsz) deriving (Bits);

Read clients implement the `MemReadClient` interface. On response to
the read, `burstLen` `MemData` items will be put to the `readData`
interface. The design must be ready to consume the data when it is
delivered from the memory bus or the system may hang::

    interface MemReadClient#(numeric type dsz);
       interface GetF#(MemRequest)    readReq;
       interface PutF#(MemData#(dsz)) readData;
    endinterface

Write clients implement `MemWriteClient`. To complete the transaction,
`burstLen` data items will be consumed from the `writeData`
interace. Upon completion of the request, the specified tag will be
put to the `writeDone` interface. The data must be available when the
write request is issued to the memory bus or the system may hang::

    interface MemWriteClient#(numeric type dsz);
       interface GetF#(MemRequest)    writeReq;
       interface GetF#(MemData#(dsz)) writeData;
       interface PutF#(Bit#(6))       writeDone;
    endinterface

A design may implement `MemReadClient` and `MemWriteClient` interfaces directly, or it may instantiate DmaReadBuffer or DmaWriteBuffer.

The `AxiDmaServer` is configured with physical address translations
for each region of memory identified by a `pointer`. A design using
DMA must export the `DmaConfig` and `DmaIndication` interfaces of the
DMA server.

Here are the DMA components of [memread_nobuff/Top.bsv](../examples/memread_nobuff/Top.bsv):

Instantiate the design and its interface wrappers and proxies::

    MemreadIndicationProxy memreadIndicationProxy <- mkMemreadIndicationProxy(MemreadIndication);
    Memread memread <- mkMemread(memreadIndicationProxy.ifc);
    MemreadRequestWrapper memreadRequestWrapper <- mkMemreadRequestWrapper(MemreadRequest,memread.request);

Collect the read and write clients::

    Vector#(1, MemReadClient#(64)) readClients = cons(memread.dmaClient, nil);
    Vector#(0, MemReadClient#(64)) writeClients = nil;

Instantiate the DMA server and its wrapper and proxy::

    DmaIndicationProxy dmaIndicationProxy <- mkDmaIndicationProxy(DmaIndication);
    AxiDmaServer#(addrWidth,64) dma <- mkAxiDmaServer(dmaIndicationProxy.ifc, readClients, writeClients);
    DmaConfigWrapper dmaConfigWrapper <- mkDmaConfigWrapper(DmaConfig,dma.request);

Include `DmaConfig` and `DmaIndication` in the portals of the design::

    Vector#(4,StdPortal) portals;
    portals[0] = memreadRequestWrapper.portalIfc;
    portals[1] = memreadIndicationProxy.portalIfc; 
    portals[2] = dmaConfigWrapper.portalIfc;
    portals[3] = dmaIndicationProxy.portalIfc; 

The code generation tools will then produce the software glue necessary for the shared memory support libraries to initialize the DMA "library module" included in the hardware.

Shared Memory Software
^^^^^^^^^^^^^^^^^^^^^^

The software side instantiates the DmaConfig proxy and the DmaIndication wrapper::

    dma = new DmaConfigProxy(IfcNames_DmaConfig);
    dmaIndication = new DmaIndication(dma, IfcNames_DmaIndication);

Call `dma->alloc()` to allocate DMA memory. Each chunk of portal
memory is identified by a file descriptor. Portal memory may be shared
with other processes. Portal memory is reference counted according to
the number of file descriptors associated with it::

    PortalAlloc *srcAlloc;
    dma->alloc(alloc_sz, &srcAlloc);

Memory map it to make it accessible to software::

    srcBuffer = (unsigned int *)mmap(0, alloc_sz, PROT_READ|PROT_WRITE|PROT_EXEC, MAP_SHARED, srcAlloc->header.fd, 0);

Connectal is currently using non-snooped interfaces, so the cache must be flushed and invalidated before hardware accesses portal memory::

    dma->dCacheFlushInval(srcAlloc, srcBuffer);

Call `dma->reference()` to get a pointer that may be passed to hardware::

    unsigned int ref_srcAlloc = dma->reference(srcAlloc);

This also transfers the DMA-to-physical address translation information to the hardware via the `DmaConfig` interface::

    device->startRead(ref_srcAlloc, numWords, burstLen, iterCnt);

Notes
-----

stewart notes
^^^^^^^^^^^^^

.. caution::
Currently there are no valid bits and no protections against bursts crossing page boundaries

.. caution::

There needs to be a way to synchronize Request actions and DMA reads,
and to synchronize DMA writes with Indications, so that the writes
complete to the coherence point before the indication is delivered to
software. One could imagine an absurdly buffered memory interface and
a rather direct path for I/O reads that could get out of order.

