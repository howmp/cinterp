/* Win32 `__thiscall` callback: the first integer argument is in ECX and the
   second is on the callee-cleaned stack. Expected result: 4 * 10 + 2 = 42. */
__attribute__((thiscall)) int cb(int a, int b) { return a * 10 + b; }

int call_tc_cb(int(__attribute__((thiscall)) *fn)(int, int), int a, int b);

int main(void) { return call_tc_cb(cb, 4, 2); }
