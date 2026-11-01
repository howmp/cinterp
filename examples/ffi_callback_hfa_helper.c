typedef struct { float a, b, c, d; } F4;
typedef struct { double a, b; } D2;

F4 c_invoke_f4(F4 (*cb)(F4), F4 x) { return cb(x); }
double c_invoke_d2(D2 (*cb)(D2), D2 x) { D2 r = cb(x); return r.a + r.b; }
long double c_invoke_ld(long double (*cb)(long double), long double x) { return cb(x); }
