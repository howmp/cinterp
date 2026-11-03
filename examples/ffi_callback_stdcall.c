/* Win32 `__stdcall` callback: `call_std_cb` (examples/ffi_callback_stdcall_helper.c)
   calls the function pointer below through the i686 callee-pops convention.
   The callback must reach the VM and hand 4 * 10 + 2 = 42 back. */
__attribute__((stdcall)) int cb(int a, int b) { return a * 10 + b; }

int call_std_cb(int(__stdcall *fn)(int, int), int a, int b);

int main(void) { return call_std_cb(cb, 4, 2); }
