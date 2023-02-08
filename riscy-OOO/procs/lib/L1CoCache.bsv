
// Copyright (c) 2017 Massachusetts Institute of Technology
// 
// Permission is hereby granted, free of charge, to any person
// obtaining a copy of this software and associated documentation
// files (the "Software"), to deal in the Software without
// restriction, including without limitation the rights to use, copy,
// modify, merge, publish, distribute, sublicense, and/or sell copies
// of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
// BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
// ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
// CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

`include "ProcConfig.bsv"

import Vector::*;
import FIFO::*;
import ClientServer::*;
import GetPut::*;
import Assert::*;

import CacheUtils::*;
import Types::*;
import ProcTypes::*;
import Performance::*;
import Fifo::*;
import CCTypes::*;
import L1Pipe::*;
import L1CRqMshr::*;
import L1PRqMshr::*;
import L1Bank::*;
import ICRqMshr::*;
import IPRqMshr::*;
import IBank::*;
import SelfInvL1Pipe::*;
import SelfInvL1Bank::*;
import SelfInvIPipe::*;
import SelfInvIBank::*;
import RWBramCore::*;
import LruReplace::*;
import RandomReplace::*;

export L1Num;
export LgL1WayNum;
export L1WayNum;
export L1Way;

export DProcReqId;
export L1DCRqStuck(..);
export L1DPRqStuck(..);
export DCoCache(..);
export mkDCoCache;

export ISupSz;
export L1ICRqStuck(..);
export L1IPRqStuck(..);
export ICoCache(..);
export mkICoCache;

// L1$: 1 I$ and 1 D$
typedef TMul#(CoreNum, 2) L1Num;

// Way num is shared among all coherent L1$ (I and D)
typedef `LOG_L1_WAYS LgL1WayNum;
typedef TExp#(LgL1WayNum) L1WayNum;
typedef Bit#(LgL1WayNum) L1Way;

`ifdef L1_CACHE_LRU
typedef TrueLruRepInfo#(L1WayNum) L1RepInfo;
function module#(RWBramCore#(indexT, L1RepInfo)) mkL1RepRam provisos(Bits#(indexT, indexSz)) = mkRWBramCore;
function module#(ReplacePolicy#(L1WayNum, L1RepInfo)) mkL1RepPolicy = mkTrueLruReplace;
`else
typedef RandRepInfo L1RepInfo;
function module#(RWBramCore#(indexT, L1RepInfo)) mkL1RepRam = mkRandRepRam;
function module#(ReplacePolicy#(L1WayNum, L1RepInfo)) mkL1RepPolicy = mkRandomReplace;
`endif

////////
// D$ //
////////
typedef `LOG_L1_LINES LgDLineNum;
typedef 0 LgDBankNum;
typedef TSub#(LgDLineNum, TAdd#(LgDBankNum, LgL1WayNum)) LgDSetNum;

typedef Bit#(LgDBankNum) DBankId;
typedef LgDSetNum DIndexSz;
typedef Bit#(DIndexSz) DIndex;
typedef GetTagSz#(LgDBankNum, LgDSetNum) DTagSz;
typedef Bit#(DTagSz) DTag;

typedef L1WayNum DCRqNum;
typedef 4 DPRqNum; // match cache pipeline latency
typedef Bit#(TLog#(DCRqNum)) DCRqMshrIdx;
typedef Bit#(TLog#(DPRqNum)) DPRqMshrIdx;

typedef Bit#(TMax#(SizeOf#(LdQTag), SizeOf#(SBIndex))) DProcReqId;

(* synthesize *)
module mkDCRqMshrWrapper(
    L1CRqMshr#(DCRqNum, L1Way, DTag, ProcRq#(DProcReqId))
);
    function Addr getAddrFromReq(ProcRq#(DProcReqId) r);
        return r.addr;
    endfunction
    function Bool isReqToExclusive(ProcRq#(DProcReqId) r);
        return r.toState >= E;
    endfunction
    let m <- mkL1CRqMshr(getAddrFromReq, isReqToExclusive);
    return m;
endmodule

(* synthesize *)
module mkDPRqMshrWrapper(
    L1PRqMshr#(DPRqNum)
);
    let m <- mkL1PRqMshr;
    return m;
endmodule


`ifdef SELF_INV_CACHE

typedef `L1D_MAX_HITS DMaxHitNum;

(* synthesize *)
module mkDPipeline(
    SelfInvL1Pipe#(LgDBankNum, L1WayNum, DMaxHitNum, DIndex, DTag, L1RepInfo, DCRqMshrIdx, DPRqMshrIdx)
);
    RWBramCore#(DIndex, L1RepInfo) repRam <- mkL1RepRam;
    ReplacePolicy#(L1WayNum, L1RepInfo) repPolicy <- mkL1RepPolicy;
    let m <- mkSelfInvL1Pipe(repRam, repPolicy);
    return m;
endmodule

typedef SelfInvL1Bank#(LgDBankNum, L1WayNum, DIndexSz, DTagSz, DCRqNum, DPRqNum, DMaxHitNum, L1RepInfo, DProcReqId) DCacheWrapper;

module mkDCacheWrapper#(L1ProcResp#(DProcReqId) procResp)(DCacheWrapper);
    let m <- mkSelfInvL1Cache(mkDCRqMshrWrapper, mkDPRqMshrWrapper, mkDPipeline, procResp);
    return m;
endmodule

typedef SelfInvL1CRqStuck L1DCRqStuck;
typedef SelfInvL1PRqStuck L1DPRqStuck;

`else // !SELF_INV_CACHE

(* synthesize *)
module mkDPipeline(
    L1Pipe#(LgDBankNum, L1WayNum, DIndex, DTag, L1RepInfo, DCRqMshrIdx, DPRqMshrIdx)
);
    RWBramCore#(DIndex, L1RepInfo) repRam <- mkL1RepRam;
    ReplacePolicy#(L1WayNum, L1RepInfo) repPolicy <- mkL1RepPolicy;
    let m <- mkL1Pipe(repRam, repPolicy);
    return m;
endmodule

typedef L1Bank#(LgDBankNum, L1WayNum, DIndexSz, DTagSz, DCRqNum, DPRqNum, L1RepInfo, DProcReqId) DCacheWrapper;

module mkDCacheWrapper#(L1ProcResp#(DProcReqId) procResp)(DCacheWrapper);
    let m <- mkL1Cache(mkDCRqMshrWrapper, mkDPRqMshrWrapper, mkDPipeline, procResp);
    return m;
endmodule

typedef L1CRqStuck L1DCRqStuck;
typedef L1PRqStuck L1DPRqStuck;

`endif // SELF_INV_CACHE


interface DCoCache;
    interface L1ProcReq#(DProcReqId) procReq;
    method Action flush;
    method Bool flush_done;
    method Action resetLinkAddr;
    interface Perf#(L1DPerfType) perf;

    interface ChildCacheToParent#(L1Way, void) to_parent;

`ifdef SELF_INV_CACHE
    // reconcile
    interface Server#(void, void) reconcile;
`endif
    // detect deadlock: only in use when macro CHECK_DEADLOCK is defined
    interface Get#(L1DCRqStuck) cRqStuck;
    interface Get#(L1DPRqStuck) pRqStuck;
endinterface

module mkDCoCache#(L1ProcResp#(DProcReqId) procResp)(DCoCache);
    let cache <- mkDCacheWrapper(procResp);

    // perf counters
    Fifo#(1, L1DPerfType) perfReqQ <- mkCFFifo;
`ifdef PERF_COUNT
    Fifo#(1, PerfResp#(L1DPerfType)) perfRespQ <- mkCFFifo;

    rule doPerf;
        let t <- toGet(perfReqQ).get;
        let d = cache.getPerfData(t);
        perfRespQ.enq(PerfResp {
            pType: t,
            data: d
        });
    endrule
`endif

`ifdef SELF_INV_CACHE
    // change the reconcile ifc to a FIFO ifc to avoid scheduling issues
    FIFO#(void) reconcileReqQ <- mkFIFO1;
    FIFO#(void) reconcileRespQ <- mkFIFO1;
    Reg#(Bool) waitReconcile <- mkReg(False);

    rule doStartReconcile(!waitReconcile);
        reconcileReqQ.deq;
        cache.reconcile;
        waitReconcile <= True;
    endrule

    rule doEndReconcile(waitReconcile && cache.reconcile_done);
        reconcileRespQ.enq(?);
        waitReconcile <= False;
    endrule

    interface Server reconcile;
        interface Put request = toPut(reconcileReqQ);
        interface Get response = toGet(reconcileRespQ);
    endinterface
`endif

    interface procReq = cache.procReq;

    method flush = cache.flush;
    method flush_done = cache.flush_done;

    method Action resetLinkAddr;
        cache.resetLinkAddr;
    endmethod

    interface Perf perf;
        method Action setStatus(Bool stats);
            cache.setPerfStatus(stats);
        endmethod
        method Action req(L1DPerfType r);
            perfReqQ.enq(r);
        endmethod
        method ActionValue#(PerfResp#(L1DPerfType)) resp;
`ifdef PERF_COUNT
            perfRespQ.deq;
            return perfRespQ.first;
`else
            perfReqQ.deq;
            return PerfResp {
                pType: perfReqQ.first,
                data: 0
            };
`endif
        endmethod
        method Bool respValid;
`ifdef PERF_COUNT
            return perfRespQ.notEmpty;
`else
            return perfReqQ.notEmpty;
`endif
        endmethod
    endinterface

    interface to_parent = cache.to_parent;

    interface cRqStuck = cache.cRqStuck;
    interface pRqStuck = cache.pRqStuck;
endmodule


////////
// I$ //
////////
typedef `LOG_L1_LINES LgILineNum;
typedef 0 LgIBankNum;
typedef TSub#(LgILineNum, TAdd#(LgIBankNum, LgL1WayNum)) LgISetNum;

typedef Bit#(LgIBankNum) IBankId;
typedef LgISetNum IIndexSz;
typedef Bit#(IIndexSz) IIndex;
typedef GetTagSz#(LgIBankNum, LgISetNum) ITagSz;
typedef Bit#(ITagSz) ITag;

typedef L1WayNum ICRqNum;
typedef 4 IPRqNum; // match cache pipeline latency
typedef Bit#(TLog#(ICRqNum)) ICRqMshrIdx;
typedef Bit#(TLog#(IPRqNum)) IPRqMshrIdx;

typedef SupSize ISupSz;

(* synthesize *)
module mkICRqMshrWrapper(
    ICRqMshr#(ICRqNum, L1Way, ITag, ProcRqToI, Vector#(ISupSz, Maybe#(Instruction)))
);
    function Addr getAddrFromReq(ProcRqToI r);
        return r.addr;
    endfunction
    let m <- mkICRqMshr(getAddrFromReq);
    return m;
endmodule


`ifdef SELF_INV_CACHE

(* synthesize *)
module mkIPipeline(
    SelfInvIPipe#(LgIBankNum, L1WayNum, IIndex, ITag, L1RepInfo, ICRqMshrIdx)
);
    RWBramCore#(IIndex, L1RepInfo) repRam <- mkL1RepRam;
    ReplacePolicy#(L1WayNum, L1RepInfo) repPolicy <- mkL1RepPolicy;
    let m <- mkSelfInvIPipe(repRam, repPolicy);
    return m;
endmodule

typedef SelfInvIBank#(ISupSz, LgIBankNum, L1WayNum, IIndexSz, ITagSz, ICRqNum, L1RepInfo) IBankWrapper;

(* synthesize *)
module mkIBankWrapper(IBankWrapper);
    let m <- mkSelfInvIBank(0, mkICRqMshrWrapper, mkIPipeline);
    return m;
endmodule

typedef SelfInvICRqStuck L1ICRqStuck;
typedef SelfInvIPRqStuck L1IPRqStuck;

`else // !SELF_INV_CACHE

(* synthesize *)
module mkIPRqMshrWrapper(
    IPRqMshr#(IPRqNum)
);
    let m <- mkIPRqMshr;
    return m;
endmodule

(* synthesize *)
module mkIPipeline(
    L1Pipe#(LgIBankNum, L1WayNum, IIndex, ITag, L1RepInfo, ICRqMshrIdx, IPRqMshrIdx)
);
    RWBramCore#(IIndex, L1RepInfo) repRam <- mkL1RepRam;
    ReplacePolicy#(L1WayNum, L1RepInfo) repPolicy <- mkL1RepPolicy;
    let m <- mkL1Pipe(repRam, repPolicy);
    return m;
endmodule

typedef IBank#(ISupSz, LgIBankNum, L1WayNum, IIndexSz, ITagSz, ICRqNum, IPRqNum, L1RepInfo) IBankWrapper;

(* synthesize *)
module mkIBankWrapper(IBankWrapper);
    let m <- mkIBank(0, mkICRqMshrWrapper, mkIPRqMshrWrapper, mkIPipeline);
    return m;
endmodule

typedef ICRqStuck L1ICRqStuck;
typedef IPRqStuck L1IPRqStuck;

`endif // SELF_INV_CACHE


interface ICoCache;
    interface Server#(Addr, Vector#(ISupSz, Maybe#(Instruction))) to_proc;
    method Action flush;
    method Bool flush_done;
    interface Perf#(L1IPerfType) perf;

    interface ChildCacheToParent#(L1Way, void) to_parent;

`ifdef SELF_INV_CACHE
    // reconcile
    method Action reconcile;
    method Bool reconcile_done;
`endif
    // detect deadlock: only in use when macro CHECK_DEADLOCK is defined
    interface Get#(L1ICRqStuck) cRqStuck;
    interface Get#(L1IPRqStuck) pRqStuck;
endinterface

(* synthesize *)
module mkICoCache(ICoCache);
`ifdef DEBUG_ICACHE
    staticAssert(False, "DEBUG_ICACHE should not be defined");
`endif

    let cache <- mkIBankWrapper;

    Fifo#(1, L1IPerfType) perfReqQ <- mkCFFifo;
`ifdef PERF_COUNT
    Fifo#(1, PerfResp#(L1IPerfType)) perfRespQ <- mkCFFifo;

    rule doPerf;
        let t <- toGet(perfReqQ).get;
        let d = cache.getPerfData(t);
        perfRespQ.enq(PerfResp {
            pType: t,
            data: d
        });
    endrule
`endif

    interface Server to_proc;
        interface request = cache.to_proc.req;
        interface response = cache.to_proc.resp;
    endinterface

    method flush = cache.flush;
    method flush_done = cache.flush_done;

    interface Perf perf;
        method Action setStatus(Bool stats);
            cache.setPerfStatus(stats);
        endmethod
        method Action req(L1IPerfType r);
            perfReqQ.enq(r);
        endmethod
        method ActionValue#(PerfResp#(L1IPerfType)) resp;
`ifdef PERF_COUNT
            perfRespQ.deq;
            return perfRespQ.first;
`else
            perfReqQ.deq;
            return PerfResp {
                pType: perfReqQ.first,
                data: 0
            };
`endif
        endmethod
        method Bool respValid;
`ifdef PERF_COUNT
            return perfRespQ.notEmpty;
`else
            return perfReqQ.notEmpty;
`endif
        endmethod
    endinterface

    interface to_parent = cache.to_parent;

`ifdef SELF_INV_CACHE
    method reconcile = cache.reconcile;
    method reconcile_done = cache.reconcile_done;
`endif

    interface cRqStuck = cache.cRqStuck;
    interface pRqStuck = cache.pRqStuck;
endmodule
