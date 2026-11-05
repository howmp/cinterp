/* Exported helper for examples/ffi/ffi_callback_thiscall.c: call a `__thiscall`
   function pointer with the first int in ECX and the second on the stack. */
int call_tc_cb(int(__attribute__((thiscall)) *fn)(int, int), int a, int b) {
    return fn(a, b);
}
