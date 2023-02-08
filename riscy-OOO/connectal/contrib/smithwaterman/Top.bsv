/* Copyright (c) 2014 Quanta Research Cambridge, Inc
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
import SpecialFIFOs::*;
import Vector::*;
import StmtFSM::*;
import FIFO::*;
import CtrlMux::*;
import Portal::*;
import HostInterface::*;
import BlueScope::*;
import ConnectalMemory::*;
import DmaUtils::*;
import ConnectalMemTypes::*;
import MemServer::*;
import ConnectalMMU::*;
import SmithwatermanRequest::*;
import MemServerRequest::*;
import MMURequest::*;
import SmithwatermanIndication::*;
import MemServerIndication::*;
import MMUIndication::*;
import Smithwaterman::*;

typedef enum {IfcNames_SmithwatermanIndication, IfcNames_SmithwatermanRequest, IfcNames_HostMemServerIndication, IfcNames_HostMemServerRequest, IfcNames_HostMMURequest, IfcNames_HostMMUIndication} IfcNames deriving (Eq,Bits);
typedef 1 DegPar;


module mkConnectalTop(StdConnectalDmaTop#(PhysAddrWidth));

   DmaReadBuffer#(64,1) setupA_read_chan <- mkDmaReadBuffer();
   DmaReadBuffer#(64,1) setupB_read_chan <- mkDmaReadBuffer();
   
   MemReadClient#(64) setupA_read_client = setupA_read_chan.dmaClient;
   MemReadClient#(64) setupB_read_client = setupB_read_chan.dmaClient;
   
   Vector#(2,  MemReadClient#(64)) readClients;
   readClients[0] = setupA_read_client;
   readClients[1] = setupB_read_client;

   MMUIndicationProxy hostMMUIndicationProxy <- mkMMUIndicationProxy(IfcNames_HostMMUIndication);
   MMU#(PhysAddrWidth) hostMMU <- mkMMU(0, True, hostMMUIndicationProxy.ifc);
   MMURequestWrapper hostMMURequestWrapper <- mkMMURequestWrapper(IfcNames_HostMMURequest, hostMMU.request);

   MemServerIndicationProxy hostMemServerIndicationProxy <- mkMemServerIndicationProxy(IfcNames_HostMemServerIndication);
   MemServer#(PhysAddrWidth,64,1) dma <- mkMemServer(readClients, nil, cons(hostMMU,nil), hostMemServerIndicationProxy.ifc);
   MemServerRequestWrapper hostMemServerRequestWrapper <- mkMemServerRequestWrapper(IfcNames_HostMemServerRequest, dma.request);

   SmithwatermanIndicationProxy smithwatermanIndicationProxy <- mkSmithwatermanIndicationProxy(IfcNames_SmithwatermanIndication);
   SmithwatermanRequest smithwatermanRequest <- mkSmithwatermanRequest(smithwatermanIndicationProxy.ifc, setupA_read_chan.dmaServer, setupB_read_chan.dmaServer);
   SmithwatermanRequestWrapper smithwatermanRequestWrapper <- mkSmithwatermanRequestWrapper(IfcNames_SmithwatermanRequest,smithwatermanRequest);

   Vector#(6,StdPortal) portals;
   portals[0] = smithwatermanRequestWrapper.portalIfc;
   portals[1] = smithwatermanIndicationProxy.portalIfc; 
   portals[2] = hostMemServerRequestWrapper.portalIfc;
   portals[3] = hostMemServerIndicationProxy.portalIfc; 
   portals[4] = hostMMURequestWrapper.portalIfc;
   portals[5] = hostMMUIndicationProxy.portalIfc;
   let ctrl_mux <- mkSlaveMux(portals);
   
   interface interrupt = getInterruptVector(portals);
   interface slave = ctrl_mux;
   interface masters = dma.masters;
endmodule
