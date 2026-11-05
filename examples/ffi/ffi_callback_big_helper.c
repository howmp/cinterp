typedef struct { long a,b,c; } S24;
S24 c_invoke_s24(S24 (*cb)(S24), S24 s) { return cb(s); }
