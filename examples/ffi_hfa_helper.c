typedef struct { double a, b, c, d; } D4;
double c_hfa4(D4 s) { return s.a + s.b + s.c + s.d; }
D4 c_hfa4_ret(void) { D4 r = { 1.5, 2.5, 3.5, 4.5 }; return r; }
