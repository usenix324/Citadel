require_extension('A');
require_rv64;
WRITE_RD(MMU.amo_uint64(RS1, [&](int64_t lhs) { return std::min(lhs, int64_t(RS2)); }));
if (insn.aq()) MMU.flush_dcache();
