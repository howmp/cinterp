/* Win32 `__thiscall` native call: the first integer argument is passed in ECX,
   the remaining arguments on the callee-cleaned stack. */
__attribute__((thiscall)) int c_tc_add3(int a, int b, int c);

int main(void) { return c_tc_add3(1, 2, 3); }
