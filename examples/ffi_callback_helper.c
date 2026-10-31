typedef struct { int a, b; } S8;

long c_invoke6(long (*cb)(long, long, long, long, long, long),
               long a, long b, long c, long d, long e, long f) {
    return cb(a, b, c, d, e, f);
}

S8 c_invoke_s8(S8 (*cb)(S8), S8 s) {
    return cb(s);
}
