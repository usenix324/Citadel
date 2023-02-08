
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
import BuildVector::*;
import DefaultValue::*;
import ClientServer::*;
import GetPut::*;
import Assert::*;
import Cntrs::*;
import ConfigReg::*;
import FIFO::*;
import Fifo::*;
import Ehr::*;
import Connectable::*;

import Types::*;
import ProcTypes::*;
import CacheUtils::*;
import TlbTypes::*;
import SynthParam::*;
import VerificationPacket::*;
import Performance::*;
import HasSpecBits::*;
import Exec::*;
import FetchStage::*;
import ITlb::*;
import DTlb::*;
import L2Tlb::*;
import TlbConnect::*;
import EpochManager::*;
import CsrFile::*;
import PhysRFile::*;
import RFileSynth::*;
import RenamingTable::*;
import ReorderBuffer::*;
import ReorderBufferSynth::*;
import Scoreboard::*;
import ScoreboardSynth::*;
import SpecTagManager::*;
import Fpu::*;
import MulDiv::*;
import InorderRS::*;
import ReservationStationAlu::*;
import ReservationStationMem::*;
import ReservationStationFpuMulDiv::*;
import AluExePipeline::*;
import FpuMulDivExePipeline::*;
import MemExePipeline::*;
import SplitLSQ::*;
import StoreBuffer::*;
import GlobalSpecUpdate::*;
import CCTypes::*;
import L1CoCache::*;
import L1Bank::*;
import IBank::*;
import MMIOCore::*;
import RenameStage::*;
import CommitStage::*;
import Bypass::*;

interface CoreReq;
    method Action start(
        Addr startpc,
        Addr toHostAddr, Addr fromHostAddr
    );
    method Action perfReq(PerfLocation loc, PerfType t);
endinterface

interface CoreIndInv;
    method ActionValue#(ProcPerfResp) perfResp;
    method ActionValue#(void) terminate;
endinterface

interface CoreDeadlock;
    interface Get#(L1DCRqStuck) dCacheCRqStuck;
    interface Get#(L1DPRqStuck) dCachePRqStuck;
    interface Get#(L1ICRqStuck) iCacheCRqStuck;
    interface Get#(L1IPRqStuck) iCachePRqStuck;
    interface Get#(RenameStuck) renameInstStuck;
    interface Get#(RenameStuck) renameCorrectPathStuck;
    interface Get#(CommitStuck) commitInstStuck;
    interface Get#(CommitStuck) commitUserInstStuck;
    interface Get#(void) checkStarted;
endinterface

interface CoreRenameDebug;
    interface Get#(RenameErrInfo) renameErr;
endinterface

interface Core;
    // core request & indication
    interface CoreReq coreReq;
    interface CoreIndInv coreIndInv;
    // coherent caches to LLC
    interface ChildCacheToParent#(L1Way, void) dCacheToParent;
    interface ChildCacheToParent#(L1Way, void) iCacheToParent;
    // DMA to LLC
    interface TlbMemClient tlbToMem;
    // MMIO
    interface MMIOCoreToPlatform mmioToPlatform;
    // stats enable
    method ActionValue#(Bool) sendDoStats;
    method Action recvDoStats(Bool x);
    // detect deadlock: only in use when macro CHECK_DEADLOCK is defined
    interface CoreDeadlock deadlock;
    // debug rename
    interface CoreRenameDebug renameDebug;
endinterface

// fixpoint to instantiate modules
interface CoreFixPoint;
    interface Vector#(AluExeNum, AluExePipeline) aluExeIfc;
    interface Vector#(FpuMulDivExeNum, FpuMulDivExePipeline) fpuMulDivExeIfc;
    interface MemExePipeline memExeIfc;
    method Action killAll; // kill everything: used by commit stage
    interface Reg#(Bool) doStatsIfc;
endinterface

(* synthesize *)
module mkCore#(CoreId coreId)(Core);
    let verbose = True;
    Reg#(Bool) outOfReset <- mkReg(False);
    rule rl_outOfReset if (!outOfReset);
        $fwrite(stderr, "mkProc came out of reset\n");
        outOfReset <= True;
    endrule

    Reg#(Bool) started <- mkReg(False);

    // front end
    FetchStage fetchStage <- mkFetchStage;
    ITlb iTlb = fetchStage.iTlbIfc;
    ICoCache iMem = fetchStage.iMemIfc;

    // back end
    RFileSynth rf <- mkRFileSynth;
    ScoreboardSynth sb <- mkScoreboardSynth; // sb is tied with RF
    CsrFile csrf <- mkCsrFile(zeroExtend(coreId)); // hartid in CSRF should be core id
    RegRenamingTable regRenamingTable <- mkRegRenamingTable;
    EpochManager epochManager <- mkEpochManager;
    SpecTagManager specTagManager <- mkSpecTagManager;
    ReorderBufferSynth rob <- mkReorderBufferSynth;

    // MMIO: need to track in flight CSR inst or interrupt; note we can at most
    // 1 CSR inst or 1 interrupt in ROB, so just use 1 bit track it. Commit
    // stage use port 0 to reset this, and Rename stage use port 1 to set this.
    Ehr#(2, Bool) csrInstOrInterruptInflight <- mkEhr(False);
    Reg#(Bool) csrInstOrInterruptInflight_commit = csrInstOrInterruptInflight[0];
    Reg#(Bool) csrInstOrInterruptInflight_rename = csrInstOrInterruptInflight[1];
    MMIOCoreInput mmioInIfc = (interface MMIOCoreInput;
        interface fetch = fetchStage.mmioIfc;
        method getMSIP = csrf.getMSIP;
        method setMSIP = csrf.setMSIP;
        method setMTIP = csrf.setMTIP;
        method noInflightCSRInstOrInterrupt = !csrInstOrInterruptInflight[0];
        method setTime = csrf.setTime;
    endinterface);
    MMIOCore mmio <- mkMMIOCore(mmioInIfc);

    // fix point module to instantiate other function units
    module mkCoreFixPoint#(CoreFixPoint fix)(CoreFixPoint);
        // spec update
        Vector#(AluExeNum, SpeculationUpdate) aluSpecUpdate;
        for(Integer i = 0; i < valueof(AluExeNum); i = i+1) begin
            aluSpecUpdate[i] = fix.aluExeIfc[i].specUpdate;
        end
        Vector#(FpuMulDivExeNum, SpeculationUpdate) fpuMulDivSpecUpdate;
        for(Integer i = 0; i < valueof(FpuMulDivExeNum); i = i+1) begin
            fpuMulDivSpecUpdate[i] = fix.fpuMulDivExeIfc[i].specUpdate;
        end
        GlobalSpecUpdate#(CorrectSpecPortNum, ConflictWrongSpecPortNum) globalSpecUpdate <- mkGlobalSpecUpdate(
            joinSpeculationUpdate(
                append(append(vec(regRenamingTable.specUpdate,
                                  specTagManager.specUpdate,
                                  fix.memExeIfc.specUpdate), aluSpecUpdate), fpuMulDivSpecUpdate)
            ),
            rob.specUpdate
        );

        // whether perf data is collected
        Reg#(Bool) doStatsReg <- mkConfigReg(False); 

        // write bypass rf and sb
        function Action writeReg(Integer wrPort, PhyRIndx dst, Data data);
        action
            rf.write[wrPort].wr(dst, data);
            sb.setReady[wrPort].put(dst);
        endaction
        endfunction

        Vector#(AluExeNum, FIFO#(FetchTrainBP)) trainBPQ <- replicateM(mkFIFO);
        Vector#(AluExeNum, AluExePipeline) aluExe;
        for(Integer i = 0; i < valueof(AluExeNum); i = i+1) begin
            let aluExeInput = (interface AluExeInput;
                method sb_lookup = sb.lookup[aluRdPort(i)].get;
                method rf_rd1 = rf.read[aluRdPort(i)].rd1;
                method rf_rd2 = rf.read[aluRdPort(i)].rd2;
                method csrf_rd = csrf.rd;
                method rob_getPC = rob.getOrigPC[i].get;
                method rob_getPredPC = rob.getOrigPredPC[i].get;
                method rob_setExecuted = rob.setExecuted_doFinishAlu[i].set;
                method fetch_train_predictors = toPut(trainBPQ[i]).put;
                interface SendBypass sendBypass;
                    method Action send(PhyRIndx dst, Data data);
                        // broadcast bypass
                        Integer recvPort = i;
                        for(Integer j = 0; j < valueof(FpuMulDivExeNum); j = j+1) begin
                            fix.fpuMulDivExeIfc[j].recvBypass[recvPort].recv(dst, data);
                        end
                        fix.memExeIfc.recvBypass[recvPort].recv(dst, data);
                        for(Integer j = 0; j < valueof(AluExeNum); j = j+1) begin
                            fix.aluExeIfc[j].recvBypass[recvPort].recv(dst, data);
                        end
                    endmethod
                endinterface
                method writeRegFile = writeReg(aluWrPort(i));
                method Action redirect(Addr new_pc, SpecTag spec_tag, InstTag inst_tag);
                    if (verbose) begin
                        $display("[ALU redirect - %d] ", i, fshow(new_pc),
                                 "; ", fshow(spec_tag), "; ", fshow(inst_tag));
                    end
                    epochManager.incrementEpoch;
                    fetchStage.redirect(new_pc);
                    globalSpecUpdate.incorrectSpec(False, spec_tag, inst_tag);
                endmethod
                method correctSpec = globalSpecUpdate.correctSpec[finishAluCorrectSpecPort(i)].put;
                method doStats = doStatsReg._read;
            endinterface);
            aluExe[i] <- mkAluExePipeline(aluExeInput);
            // truly call fetch method to train branch predictor
            rule doFetchTrainBP;
                let train <- toGet(trainBPQ[i]).get;
                fetchStage.train_predictors(
                    train.pc, train.nextPc, train.iType, train.taken,
                    train.dpTrain, train.mispred
                );
            endrule
        end

        Vector#(FpuMulDivExeNum, FpuMulDivExePipeline) fpuMulDivExe;
        for(Integer i = 0; i < valueof(FpuMulDivExeNum); i = i+1) begin
            let fpuMulDivExeInput = (interface FpuMulDivExeInput;
                method sb_lookup = sb.lookup[fpuMulDivRdPort(i)].get;
                method rf_rd1 = rf.read[fpuMulDivRdPort(i)].rd1;
                method rf_rd2 = rf.read[fpuMulDivRdPort(i)].rd2;
                method rf_rd3 = rf.read[fpuMulDivRdPort(i)].rd3;
                method csrf_rd = csrf.rd;
                method rob_setExecuted = rob.setExecuted_doFinishFpuMulDiv[i].set;
                method writeRegFile = writeReg(fpuMulDivWrPort(i));
                //method conflictWrongSpec = globalSpecUpdate.conflictWrongSpec[finishFpuMulDivConflictWrongSpecPort(i)].put(?);
                method doStats = doStatsReg._read;
            endinterface);
            fpuMulDivExe[i] <- mkFpuMulDivExePipeline(fpuMulDivExeInput);
        end

        let memExeInput = (interface MemExeInput;
            method sb_lookup = sb.lookup[memRdPort].get;
            method rf_rd1 = rf.read[memRdPort].rd1;
            method rf_rd2 = rf.read[memRdPort].rd2;
            method csrf_rd = csrf.rd;
            method rob_getPC = rob.getOrigPC[valueof(AluExeNum)].get; // last getPC port
            method rob_setExecuted_doFinishMem = rob.setExecuted_doFinishMem;
            method rob_setExecuted_deqLSQ = rob.setExecuted_deqLSQ;
            method rob_setLSQTag = rob.setLSQTag;
            method isMMIOAddr = mmio.isMMIOAddr;
            method mmioReq = mmio.dataReq;
            method mmioRespVal = mmio.dataRespVal;
            method mmioRespDeq = mmio.dataRespDeq;
            method writeRegFile = writeReg(memWrPort);
            method doStats = doStatsReg._read;
        endinterface);
        let memExe <- mkMemExePipeline(memExeInput);

        interface aluExeIfc = aluExe;
        interface fpuMulDivExeIfc = fpuMulDivExe;
        interface memExeIfc = memExe;
        method Action killAll;
            globalSpecUpdate.incorrectSpec(True, ?, ?);
        endmethod
        interface doStatsIfc = doStatsReg;
    endmodule
    CoreFixPoint coreFix <- moduleFix(mkCoreFixPoint);

    Vector#(AluExeNum, ReservationStationAlu) reservationStationAlu;
    for(Integer i = 0; i < valueof(AluExeNum); i = i+1) begin
        reservationStationAlu[i] = coreFix.aluExeIfc[i].rsAluIfc;
    end
    Vector#(FpuMulDivExeNum, ReservationStationFpuMulDiv) reservationStationFpuMulDiv;
    for(Integer i = 0; i < valueof(FpuMulDivExeNum); i = i+1) begin
        reservationStationFpuMulDiv[i] = coreFix.fpuMulDivExeIfc[i].rsFpuMulDivIfc;
    end
    ReservationStationMem reservationStationMem = coreFix.memExeIfc.rsMemIfc;
    DTlbSynth dTlb = coreFix.memExeIfc.dTlbIfc;
    SplitLSQ lsq = coreFix.memExeIfc.lsqIfc;
    StoreBuffer stb = coreFix.memExeIfc.stbIfc;
    DCoCache dMem = coreFix.memExeIfc.dMemIfc;

    // L2 TLB
    L2Tlb l2Tlb <- mkL2Tlb;
    mkTlbConnect(iTlb.toParent, dTlb.toParent, l2Tlb.toChildren);

    // flags to flush
    Reg#(Bool)  flush_tlbs <- mkReg(False);
    Reg#(Bool)  update_vm_info <- mkReg(False);
    Reg#(Bool)  flush_reservation <- mkReg(False);
`ifdef SELF_INV_CACHE
    Reg#(Bool)  reconcile_i <- mkReg(False);
`else
    Reg#(Bool)  reconcile_i <- mkReadOnlyReg(False);
`endif
`ifdef SELF_INV_CACHE
`ifdef SYSTEM_SELF_INV_L1D
    Reg#(Bool)  reconcile_d <- mkReg(False);
`else // !SYSTEM_SELF_INV_L1D
    Reg#(Bool)  reconcile_d <- mkReadOnlyReg(False);
`endif // SYSTEM_SELF_INV_L1D
`else // !SELF_INV_CACHE
    Reg#(Bool)  reconcile_d <- mkReadOnlyReg(False);
`endif // SELF_INV_CACHE

    // performance counters
    Reg#(Bool) doStats = coreFix.doStatsIfc; // whether data is collected
`ifdef PERF_COUNT
    // OOO execute stag (in AluExePipeline and MemExePipeline)

    // commit stage (many in CommitStage.bsv)
    // cycle
    Count#(Data) cycleCnt <- mkCount(0);

    // buffer/tags size
    Count#(Data) ldqFullCycles <- mkCount(0);
    Count#(Data) stqFullCycles <- mkCount(0);
    Count#(Data) robFullCycles <- mkCount(0);
    Count#(Data) aluRS0FullCycles <- mkCount(0);
    Count#(Data) aluRS1FullCycles <- mkCount(0);
    Count#(Data) fpuMulDivRSFullCycles <- mkCount(0);
    Count#(Data) memRSFullCycles <- mkCount(0);
    Count#(Data) epochFullCycles <- mkCount(0);
    Count#(Data) specTagFullCycles <- mkCount(0);

    // FIFOs to connect performance counters
    FIFO#(ExeStagePerfType) exePerfReqQ <- mkFIFO1;
    FIFO#(ComStagePerfType) comPerfReqQ <- mkFIFO1;
    FIFO#(CoreSizePerfType) sizePerfReqQ <- mkFIFO1;
    Fifo#(1, PerfResp#(ExeStagePerfType)) exePerfRespQ <- mkCFFifo;
    Fifo#(1, PerfResp#(ComStagePerfType)) comPerfRespQ <- mkCFFifo;
    Fifo#(1, PerfResp#(CoreSizePerfType)) sizePerfRespQ <- mkCFFifo;

    // FIFO of perf resp
    FIFO#(ProcPerfResp) perfRespQ <- mkFIFO1;
`endif
    // FIFO of perf req
    FIFO#(ProcPerfReq) perfReqQ <- mkFIFO1;

    // -- End of performance counters

`ifdef CHECK_DEADLOCK
    // when to start deadlock checking
    Reg#(Bool) startDeadlockCheck <- mkReg(False);
    FIFO#(void) deadlockCheckStartedQ <- mkFIFO;

    rule doStartDeadlockCheck(!startDeadlockCheck && started);
        startDeadlockCheck <= True;
        deadlockCheckStartedQ.enq(?);
    endrule
`endif

    // Rename stage
    let renameInput = (interface RenameInput;
        interface fetchIfc = fetchStage;
        interface robIfc = rob;
        interface rtIfc = regRenamingTable;
        interface sbIfc = sb;
        interface csrfIfc = csrf;
        interface emIfc = epochManager;
        interface smIfc = specTagManager;
        interface rsAluIfc = reservationStationAlu;
        interface rsFpuMulDivIfc = reservationStationFpuMulDiv;
        interface rsMemIfc = reservationStationMem;
        interface lsqIfc = lsq;
        method pendingMMIOPRq = mmio.hasPendingPRq;
        method issueCsrInstOrInterrupt = csrInstOrInterruptInflight_rename._write(True);
        method Bool checkDeadlock;
`ifdef CHECK_DEADLOCK
            return startDeadlockCheck;
`else
            return False;
`endif
        endmethod
        method doStats = coreFix.doStatsIfc._read;
    endinterface);
    RenameStage renameStage <- mkRenameStage(renameInput);

    // commit stage
    let commitInput = (interface CommitInput;
        interface robIfc = rob;
        interface rtIfc = regRenamingTable;
        interface csrfIfc = csrf;
        method stbEmpty = stb.isEmpty;
        method stqEmpty = lsq.stqEmpty;
        method lsqSetAtCommit = lsq.setAtCommit;
        method tlbNoPendingReq = iTlb.noPendingReq && dTlb.noPendingReq;
        method setFlushTlbs = flush_tlbs._write(True);
        method setUpdateVMInfo = update_vm_info._write(True);
        method setFlushReservation = flush_reservation._write(True);
        method setReconcileI = reconcile_i._write(True);
        method setReconcileD = reconcile_d._write(True);
        method killAll = coreFix.killAll;
        method redirectPc = fetchStage.redirect;
        method setFetchWaitRedirect = fetchStage.setWaitRedirect;
        method incrementEpoch = epochManager.incrementEpoch;
        method commitCsrInstOrInterrupt = csrInstOrInterruptInflight_commit._write(False);
        method doStats = coreFix.doStatsIfc._read;
        method Bool checkDeadlock;
`ifdef CHECK_DEADLOCK
            return startDeadlockCheck;
`else
            return False;
`endif
        endmethod
    endinterface);
    CommitStage commitStage <- mkCommitStage(commitInput);

    // preempt has 2 functions here
    // 1. break scheduling cycles
    // 2. XXX since csrf is configReg now, we should not let this rule fire together with doCommit
    // because we read csrf here and write csrf in doCommit

    // TODO We can use wires to catch flush / updateVM enable sigals, because
    // there cannot be any instruction in pipeline (there can be poisoned inst
    // which cannot change CSR or link reg in D$), so doCommit cannot fire.
    // MMIO manager may change pending interrupt bits, but will not affect VM
    // info.
    (* preempts = "prepareCachesAndTlbs, commitStage.doCommitTrap_handle" *)
    (* preempts = "prepareCachesAndTlbs, commitStage.doCommitSystemInst" *)
    rule prepareCachesAndTlbs(flush_reservation || flush_tlbs || update_vm_info);
        if (flush_reservation) begin
            flush_reservation <= False;
            dMem.resetLinkAddr;
        end
        if (flush_tlbs) begin
            flush_tlbs <= False;
            iTlb.flush;
            dTlb.flush;
        end
        if (update_vm_info) begin
            update_vm_info <= False;
            let vmI = csrf.vmI;
            let vmD = csrf.vmD;
            iTlb.updateVMInfo(vmI);
            dTlb.updateVMInfo(vmD);
            l2Tlb.updateVMInfo(vmI, vmD);
        end
    endrule

`ifdef SELF_INV_CACHE
    // Use wires to capture flush regs and empty signals. This is ok because
    // there cannot be any activity to make empty -> not-empty or need-flush ->
    // no-need-flush when we are trying to flush.
    PulseWire doReconcileI <- mkPulseWire;

    // We don't really need to wait for fetch to be empty, but just in case we
    // back pressure I TLB because I$ is reconciling.
    rule setDoReconcileI(reconcile_i && fetchStage.emptyForFlush);
        doReconcileI.send;
    endrule

    rule reconcileI(doReconcileI);
        reconcile_i <= False;
        iMem.reconcile;
    endrule

`ifdef SYSTEM_SELF_INV_L1D
    PulseWire doReconcileD <- mkPulseWire;

    Reg#(Bool) waitReconcileD <- mkReg(False);

    // We don't really need to wait for lsq empty, but just in case
    rule setDoReconcileD(reconcile_d && lsq.noWrongPathLoads);
        doReconcileD.send;
    endrule

    rule startReconcileD(doReconcileD && !waitReconcileD);
        coreFix.memExeIfc.reconcile.request.put(?);
        waitReconcileD <= True;
    endrule

    rule completeReconcileD(waitReconcileD);
        let unused <- coreFix.memExeIfc.reconcile.response.get;
        waitReconcileD <= False;
        reconcile_d <= False;
    endrule
`endif // SYSTEM_SELF_INV_L1D
`endif // SELF_INV_CACHE

    rule readyToFetch(
        !flush_reservation && !flush_tlbs && !update_vm_info
        && iTlb.flush_done && dTlb.flush_done
`ifdef SELF_INV_CACHE
        && !reconcile_i && iMem.reconcile_done
`ifdef SYSTEM_SELF_INV_L1D
        && !reconcile_d
`endif
`endif
    );
        fetchStage.done_flushing();
    endrule

`ifdef PERF_COUNT
    // incr cycle count
    (* fire_when_enabled, no_implicit_conditions *)
    rule incCycleCnt(doStats);
        cycleCnt.incr(1);
    endrule

    // incr buffer full cycles
    (* fire_when_enabled, no_implicit_conditions *)
    rule incLdQFull(doStats && lsq.ldqFull_ehrPort0);
        ldqFullCycles.incr(1);
    endrule
    (* fire_when_enabled, no_implicit_conditions *)
    rule incStQFull(doStats && lsq.stqFull_ehrPort0);
        stqFullCycles.incr(1);
    endrule
    (* fire_when_enabled, no_implicit_conditions *)
    rule incROBFull(doStats && rob.isFull_ehrPort0);
        robFullCycles.incr(1);
    endrule
    (* fire_when_enabled, no_implicit_conditions *)
    rule incAluRS0Full(doStats && reservationStationAlu[0].isFull_ehrPort0);
        aluRS0FullCycles.incr(1);
    endrule
    (* fire_when_enabled, no_implicit_conditions *)
    rule incAluRS1Full(doStats && reservationStationAlu[1].isFull_ehrPort0);
        aluRS1FullCycles.incr(1);
    endrule
    (* fire_when_enabled, no_implicit_conditions *)
    rule incFpuMulDivRSFull(doStats && reservationStationFpuMulDiv[0].isFull_ehrPort0);
        fpuMulDivRSFullCycles.incr(1);
    endrule
    (* fire_when_enabled, no_implicit_conditions *)
    rule incMemRSFull(doStats && reservationStationMem.isFull_ehrPort0);
        memRSFullCycles.incr(1);
    endrule
    (* fire_when_enabled, no_implicit_conditions *)
    rule incEpochFull(doStats && epochManager.isFull_ehrPort0);
        epochFullCycles.incr(1);
    endrule
    (* fire_when_enabled, no_implicit_conditions *)
    rule incSpecTagFull(doStats && specTagManager.isFull_ehrPort0);
        specTagFullCycles.incr(1);
    endrule

    // broadcast whether we should collect data
    rule broadcastDoStats;
        let stats = csrf.doPerfStats;
        doStats <= stats;
        iMem.perf.setStatus(stats);
        dMem.perf.setStatus(stats);
        iTlb.perf.setStatus(stats);
        dTlb.perf.setStatus(stats);
        l2Tlb.perf.setStatus(stats);
        fetchStage.perf.setStatus(stats);

        if(stats && !doStats) begin
            $display("[stats] enabled");
        end
        else if(!stats && doStats) begin
            $display("[stats] disabled");
        end
    endrule

    // dispatch perf req
    rule dispathPerfReq;
        perfReqQ.deq;
        let r = perfReqQ.first;
        case(r.loc)
            ICache: begin
                iMem.perf.req(unpack(truncate(r.pType)));
            end
            DCache: begin
                dMem.perf.req(unpack(truncate(r.pType)));
            end
            ITlb: begin
                iTlb.perf.req(unpack(truncate(r.pType)));
            end
            DTlb: begin
                dTlb.perf.req(unpack(truncate(r.pType)));
            end
            L2Tlb: begin
                l2Tlb.perf.req(unpack(truncate(r.pType)));
            end
            DecStage: begin
                fetchStage.perf.req(unpack(truncate(r.pType)));
            end
            ExeStage: begin
                exePerfReqQ.enq(unpack(truncate(r.pType)));
            end
            ComStage: begin
                comPerfReqQ.enq(unpack(truncate(r.pType)));
            end
            CoreSize: begin
                sizePerfReqQ.enq(unpack(truncate(r.pType)));
            end
            default: begin
                $fwrite(stderr, "[WARNING] unrecognzied perf req location ", fshow(r.loc), "\n");
                doAssert(False, "unknown perf location");
            end
        endcase
    endrule

    // handle perf req: exe stage
    rule readPerfCnt_Exe;
        function Data getAluCnt(ExeStagePerfType pType);
            Data cnt = 0;
            for(Integer i = 0; i < valueof(AluExeNum); i = i+1) begin
                cnt = cnt + coreFix.aluExeIfc[i].getPerf(pType);
            end
            return cnt;
        endfunction

        function Data getFpuMulDivCnt(ExeStagePerfType pType);
            Data cnt = 0;
            for(Integer i = 0; i < valueof(FpuMulDivExeNum); i = i+1) begin
                cnt = cnt + coreFix.fpuMulDivExeIfc[i].getPerf(pType);
            end
            return cnt;
        endfunction

        let pType <- toGet(exePerfReqQ).get;
        Data data = (case(pType)
            SupRenameCnt, SpecNoneCycles, SpecNonMemCycles: renameStage.getPerf(pType);
            ExeRedirectBr, ExeRedirectJr, ExeRedirectOther: getAluCnt(pType);
            ExeTlbExcep, ExeScSuccessCnt,
            ExeLrScAmoAcqCnt, ExeLrScAmoRelCnt,
            ExeFenceAcqCnt, ExeFenceRelCnt, ExeFenceCnt,
            ExeLdStallByLd, ExeLdStallBySt, ExeLdStallBySB,
            ExeLdForward, ExeLdMemLat, ExeStMemLat,
            ExeLdToUseLat, ExeLdToUseCnt: coreFix.memExeIfc.getPerf(pType);
            ExeIntMulCnt, ExeIntDivCnt,
            ExeFpFmaCnt, ExeFpDivCnt, ExeFpSqrtCnt: getFpuMulDivCnt(pType);
            default: 0;
        endcase);
        exePerfRespQ.enq(PerfResp {
            pType: pType,
            data: data
        });
    endrule

    // handle perf req: com stage
    rule readPerfCnt_Com;
        let pType <- toGet(comPerfReqQ).get;
        Data data = (case(pType)
            CycleCnt: cycleCnt;
            default: commitStage.getPerf(pType);
        endcase);
        comPerfRespQ.enq(PerfResp {
            pType: pType,
            data: data
        });
    endrule

    // handle perf req: core size
    rule readPerfCnt_Size;
        let pType <- toGet(sizePerfReqQ).get;
        Data data = (case(pType)
            LdQFullCycles: ldqFullCycles;
            StQFullCycles: stqFullCycles;
            ROBFullCycles: robFullCycles;
            AluRS0FullCycles: aluRS0FullCycles;
            AluRS1FullCycles: aluRS1FullCycles;
            FpuMulDivRSFullCycles: fpuMulDivRSFullCycles;
            MemRSFullCycles: memRSFullCycles;
            EpochFullCycles: epochFullCycles;
            SpecTagFullCycles: specTagFullCycles;
            default: 0;
        endcase);
        sizePerfRespQ.enq(PerfResp {
            pType: pType,
            data: data
        });
    endrule

    // gather perf resp
    rule gatherPerfResp;
        Maybe#(ProcPerfResp) resp = Invalid;
        if(iMem.perf.respValid) begin
            let r <- iMem.perf.resp;
            resp = Valid(ProcPerfResp {
                loc: ICache,
                pType: zeroExtend(pack(r.pType)),
                data: r.data
            });
        end
        else if(dMem.perf.respValid) begin
            let r <- dMem.perf.resp;
            resp = Valid(ProcPerfResp {
                loc: DCache,
                pType: zeroExtend(pack(r.pType)),
                data: r.data
            });
        end
        else if(iTlb.perf.respValid) begin
            let r <- iTlb.perf.resp;
            resp = Valid(ProcPerfResp {
                loc: ITlb,
                pType: zeroExtend(pack(r.pType)),
                data: r.data
            });
        end
        else if(dTlb.perf.respValid) begin
            let r <- dTlb.perf.resp;
            resp = Valid(ProcPerfResp {
                loc: DTlb,
                pType: zeroExtend(pack(r.pType)),
                data: r.data
            });
        end
        else if(l2Tlb.perf.respValid) begin
            let r <- l2Tlb.perf.resp;
            resp = Valid(ProcPerfResp {
                loc: L2Tlb,
                pType: zeroExtend(pack(r.pType)),
                data: r.data
            });
        end
        else if(fetchStage.perf.respValid) begin
            let r <- fetchStage.perf.resp;
            resp = Valid(ProcPerfResp {
                loc: DecStage,
                pType: zeroExtend(pack(r.pType)),
                data: r.data
            });
        end
        else if(exePerfRespQ.notEmpty) begin
            let r <- toGet(exePerfRespQ).get;
            resp = Valid(ProcPerfResp {
                loc: ExeStage,
                pType: zeroExtend(pack(r.pType)),
                data: r.data
            });
        end
        else if(comPerfRespQ.notEmpty) begin
            let r <- toGet(comPerfRespQ).get;
            resp = Valid(ProcPerfResp {
                loc: ComStage,
                pType: zeroExtend(pack(r.pType)),
                data: r.data
            });
        end
        else if(sizePerfRespQ.notEmpty) begin
            let r <- toGet(sizePerfRespQ).get;
            resp = Valid (ProcPerfResp {
                loc: CoreSize,
                pType: zeroExtend(pack(r.pType)),
                data: r.data
            });
        end
        // enq to resp Q
        if(resp matches tagged Valid .r) begin
            perfRespQ.enq(r);
        end
    endrule
`endif

    interface CoreReq coreReq;
        method Action start(
            Bit#(64) startpc,
            Addr toHostAddr, Addr fromHostAddr
        );
            fetchStage.start(startpc);
            started <= True;
            mmio.setHtifAddrs(toHostAddr, fromHostAddr);
            // start rename debug
            commitStage.startRenameDebug;
        endmethod

        method Action perfReq(PerfLocation loc, PerfType t);
            perfReqQ.enq(ProcPerfReq {
                loc: loc,
                pType: t
            });
        endmethod
    endinterface

    interface CoreIndInv coreIndInv;
        method ActionValue#(ProcPerfResp) perfResp;
`ifdef PERF_COUNT
            perfRespQ.deq;
            return perfRespQ.first;
`else
            perfReqQ.deq;
            let r = perfReqQ.first;
            return ProcPerfResp {
                loc: r.loc,
                pType: r.pType,
                data: 0
            };
`endif
        endmethod

        method terminate = csrf.terminate;
    endinterface

    interface dCacheToParent = dMem.to_parent;
    interface iCacheToParent = iMem.to_parent;

    interface tlbToMem = l2Tlb.toMem;

    interface mmioToPlatform = mmio.toP;

    method sendDoStats = csrf.sendDoStats;
    method recvDoStats = csrf.recvDoStats;

    // deadlock check
    interface CoreDeadlock deadlock;
        interface dCacheCRqStuck = dMem.cRqStuck;
        interface dCachePRqStuck = dMem.pRqStuck;
        interface iCacheCRqStuck = iMem.cRqStuck;
        interface iCachePRqStuck = iMem.pRqStuck;
        interface renameInstStuck = renameStage.renameInstStuck;
        interface renameCorrectPathStuck = renameStage.renameCorrectPathStuck;
        interface commitInstStuck = commitStage.commitInstStuck;
        interface commitUserInstStuck = commitStage.commitUserInstStuck;
`ifdef CHECK_DEADLOCK
        interface checkStarted = toGet(deadlockCheckStartedQ);
`else
        interface checkStarted = nullGet;
`endif
    endinterface

    // rename debug
    interface CoreRenameDebug renameDebug;
        interface renameErr = commitStage.renameErr;
    endinterface
endmodule

