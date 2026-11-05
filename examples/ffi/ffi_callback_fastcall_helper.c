/* Exported helper for examples/ffi/ffi_callback_fastcall.c: call a `__fastcall`
   function pointer with two integers in ECX/EDX. The callee pops any stack
   arguments it receives, so the cinterp trampoline must use the same cleanup. */
int call_fast_cb(int(__fastcall *fn)(int, int), int a, int b) { return fn(a, b); }
