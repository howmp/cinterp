/* Win32 `__fastcall` callback: the helper calls the function pointer with the
   first two int arguments in ECX/EDX. The callback must reach the VM and hand
   4 * 10 + 2 = 42 back. */
__attribute__((fastcall)) int cb(int a, int b) { return a * 10 + b; }

int call_fast_cb(int(__fastcall *fn)(int, int), int a, int b);

int main(void) { return call_fast_cb(cb, 4, 2); }
