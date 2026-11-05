/* Exported helper for examples/ffi/ffi_callback_stdcall.c: call a `__stdcall`
   function pointer with two integers. The i686 callee pops the 8 argument
   bytes, so the cinterp trampoline has to pop them as well. */
int call_std_cb(int(__stdcall *fn)(int, int), int a, int b) { return fn(a, b); }
