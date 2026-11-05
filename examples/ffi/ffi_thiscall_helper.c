/* Exported helper for examples/ffi/ffi_thiscall.c. The first argument arrives in
   ECX; b/c are on the stack and this callee pops them. */
__attribute__((thiscall)) int c_tc_add3(int a, int b, int c) {
    return a * 100 + b * 10 + c;
}
