typedef struct { long a,b,c; } S24;
S24 c_invoke_s24(S24 (*cb)(S24), S24 s);
S24 cb_s24(S24 x) { S24 y={x.a+1,x.b+2,x.c+3}; return y; }
int main(void){ S24 s={1,2,3}; S24 r=c_invoke_s24(cb_s24,s); return (int)(r.a*100+r.b*10+r.c); }
