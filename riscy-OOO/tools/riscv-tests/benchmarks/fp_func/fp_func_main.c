
// This benchmark is testing the basic functionality of floating point
// instructions. It does not test corner cases like rounding mode, correct FP
// exceptions, NaN, etc.

#include "util.h"

#define test_op2( type, test_id, inst, answer, val1, val2, max_error ) do { \
    type res; \
    type src1 = val1; \
    type src2 = val2; \
    asm volatile(inst " %0, %1, %2" : "=f"(res) : "f"(src1), "f"(src2)); \
    type diff = answer > res ? answer - res : res - answer; \
    if(diff > max_error) return test_id; \
} while(0)

#define test_op3( type, test_id, inst, answer, val1, val2, val3, max_error ) do { \
    type res; \
    type src1 = val1; \
    type src2 = val2; \
    type src3 = val3; \
    asm volatile(inst " %0, %1, %2, %3" : "=f"(res) : "f"(src1), "f"(src2), "f"(src3)); \
    type diff = answer > res ? answer - res : res - answer; \
    if(diff > max_error) return test_id; \
} while(0)

int main(int argc, char *argv[]) {
    setStats(1);

    // fmadd
    test_op3( float,  1,  "fmadd.s",     3.5,  1.0,     2.5,  1.0, 1e-6);
    test_op3( float,  2,  "fmadd.s",  1236.2, -1.0, -1235.1,  1.1, 1e-3);
    test_op3( float,  3,  "fmadd.s",   -12.0,  2.0,    -5.0, -2.0, 1e-6);
    test_op3(double,  4,  "fmadd.d",     3.5,  1.0,     2.5,  1.0, 1e-6);
    test_op3(double,  5,  "fmadd.d",  1236.2, -1.0, -1235.1,  1.1, 1e-3);
    test_op3(double,  6,  "fmadd.d",   -12.0,  2.0,    -5.0, -2.0, 1e-6);
    // fnmadd
    test_op3( float,  7, "fnmadd.s",    -3.5,  1.0,     2.5,  1.0, 1e-6);
    test_op3( float,  8, "fnmadd.s", -1236.2, -1.0, -1235.1,  1.1, 1e-3);
    test_op3( float,  9, "fnmadd.s",    12.0,  2.0,    -5.0, -2.0, 1e-6);
    test_op3(double, 10, "fnmadd.d",    -3.5,  1.0,     2.5,  1.0, 1e-6);
    test_op3(double, 11, "fnmadd.d", -1236.2, -1.0, -1235.1,  1.1, 1e-3);
    test_op3(double, 12, "fnmadd.d",    12.0,  2.0,    -5.0, -2.0, 1e-6);
    // fmsub
    test_op3( float, 13,  "fmsub.s",     1.5,  1.0,     2.5,  1.0, 1e-6);
    test_op3( float, 14,  "fmsub.s",    1234, -1.0, -1235.1,  1.1, 1e-3);
    test_op3( float, 15,  "fmsub.s",    -8.0,  2.0,    -5.0, -2.0, 1e-6);
    test_op3(double, 16,  "fmsub.d",     1.5,  1.0,     2.5,  1.0, 1e-6);
    test_op3(double, 17,  "fmsub.d",    1234, -1.0, -1235.1,  1.1, 1e-3);
    test_op3(double, 18,  "fmsub.d",    -8.0,  2.0,    -5.0, -2.0, 1e-6);
    // fnmsub
    test_op3( float, 19, "fnmsub.s",    -1.5,  1.0,     2.5,  1.0, 1e-6);
    test_op3( float, 20, "fnmsub.s",   -1234, -1.0, -1235.1,  1.1, 1e-3);
    test_op3( float, 21, "fnmsub.s",     8.0,  2.0,    -5.0, -2.0, 1e-6);
    test_op3(double, 22, "fnmsub.d",    -1.5,  1.0,     2.5,  1.0, 1e-6);
    test_op3(double, 23, "fnmsub.d",   -1234, -1.0, -1235.1,  1.1, 1e-3);
    test_op3(double, 24, "fnmsub.d",     8.0,  2.0,    -5.0, -2.0, 1e-6);

    setStats(0);

    return 0;
}
