# Unsupported 用例

本文件由 `build/test-suites-full.json` 生成，列出当前 **191** 个 `unsupported` skip。

说明：`reason` 保留 suite runner 记录的 skip 原因；其中编译诊断可能只保留首行。

## c-testsuite (2)

- `00204` — requires vector types
- `00216` — requires complex aggregate global initializers

## chibicc (25)

- `alloca` — compile: In file included from build/suites/chibicc/test/alloca.c:1:
- `asm` — compile: In file included from build/suites/chibicc/test/asm.c:1:
- `atomic` — compile: In file included from build/suites/chibicc/test/atomic.c:1:
- `bitfield` — compile: In file included from build/suites/chibicc/test/bitfield.c:1:
- `builtin` — compile: In file included from build/suites/chibicc/test/builtin.c:1:
- `commonsym` — non-goal: shared-library common symbol interposition differs from C/ELF tentative definitions
- `compat` — compile: In file included from build/suites/chibicc/test/compat.c:1:
- `const` — compile: In file included from build/suites/chibicc/test/const.c:1:
- `constexpr` — compile: In file included from build/suites/chibicc/test/constexpr.c:1:
- `control` — compile: In file included from build/suites/chibicc/test/control.c:1:
- `float` — unsupported: test depends on poison/out-of-range conversion
- `function` — compile: In file included from build/suites/chibicc/test/function.c:1:
- `generic` — compile: In file included from build/suites/chibicc/test/generic.c:1:
- `initializer` — unsupported: test depends on UB pointer arithmetic/stack layout
- `line` — compile: In file included from build/suites/chibicc/test/line.c:1:
- `literal` — compile: In file included from build/suites/chibicc/test/literal.c:1:
- `macro` — compile: In file included from build/suites/chibicc/test/macro.c:1:
- `pointer` — unsupported: test depends on adjacent stack objects
- `pragma-once` — compile: In file included from build/suites/chibicc/test/pragma-once.c:1:
- `sizeof` — compile: In file included from build/suites/chibicc/test/sizeof.c:1:
- `struct` — compile: In file included from build/suites/chibicc/test/struct.c:1:
- `tls` — compile: In file included from build/suites/chibicc/test/tls.c:1:
- `typedef` — compile: In file included from build/suites/chibicc/test/typedef.c:1:
- `unicode` — compile: In file included from build/suites/chibicc/test/unicode.c:1:
- `variable` — unsupported: test depends on adjacent stack objects

## compcert (16)

- `alias` — unsupported: wild-pointer/UB test; Clang behavior differs from CompCert reference
- `alignas` — non-goal: C11/dialect: build/suites/CompCert/test/regression/alignas.c:25:10: error: size of array element of type 'int16' (aka 'int') (4 bytes) isn't a multiple of its alignment (16 bytes)
- `aligned` — unsupported: CompCert struct-size/alignment reference differs from Clang
- `attribs1` — unsupported: section grouping/CompCert reference differs from Clang
- `builtins-aarch64` — non-goal: GCC builtin: build/suites/CompCert/test/regression/builtins-aarch64.c:13:31: error: use of unknown builtin '__builtin_cls' [-Wimplicit-function-declaration]
- `builtins-arm` — non-goal: GCC builtin: build/suites/CompCert/test/regression/builtins-arm.c:14:33: error: use of unknown builtin '__builtin_fsqrt' [-Wimplicit-function-declaration]
- `builtins-common` — non-goal: GCC builtin: build/suites/CompCert/test/regression/builtins-common.c:16:33: error: use of unknown builtin '__builtin_bswap' [-Wimplicit-function-declaration]
- `builtins-powerpc` — non-goal: GCC builtin: build/suites/CompCert/test/regression/builtins-powerpc.c:23:40: error: use of unknown builtin '__builtin_mulhw' [-Wimplicit-function-declaration]
- `builtins-riscV` — non-goal: GCC builtin: build/suites/CompCert/test/regression/builtins-riscV.c:14:47: error: use of unknown builtin '__builtin_fmadd' [-Wimplicit-function-declaration]
- `builtins-x86` — non-goal: GCC builtin: build/suites/CompCert/test/regression/builtins-x86.c:24:33: error: use of unknown builtin '__builtin_read16_reversed' [-Wimplicit-function-declaration]
- `charlit` — non-goal: char literal diagnostic: build/suites/CompCert/test/regression/charlit.c:20:21: error: hex escape sequence out of range
- `floats` — unsupported: compiler limit (TooManyFunctions)
- `krfun` — frontend/dialect: unsupported compile: build/suites/CompCert/test/regression/krfun.c:23:14: error: parameter 'c' was not declared, defaults to 'int'; ISO C99 and later do not support implicit int [-Wimplicit-int]
- `memcpy` — non-goal: GCC builtin: build/suites/CompCert/test/regression/memcpy.c:26:3: error: use of unknown builtin '__builtin_memcpy_aligned' [-Wimplicit-function-declaration]
- `packedstruct2` — non-goal: packed struct frontend: build/suites/CompCert/test/regression/packedstruct2.c:7:19: error: expected identifier or '('
- `sections` — non-goal: GCC builtin: build/suites/CompCert/test/regression/sections.c:39:3: error: use of unknown builtin '__builtin_membar' [-Wimplicit-function-declaration]

## compcert-c (12)

- `aes` — unsupported: slow benchmark deferred
- `almabench` — unsupported: slow benchmark deferred
- `binarytrees` — unsupported: slow benchmark deferred
- `chomp` — unsupported: slow benchmark deferred
- `fftw` — unsupported: slow benchmark deferred
- `knucleotide` — unsupported: slow benchmark deferred
- `lists` — unsupported: slow benchmark deferred
- `nbody` — unsupported: slow benchmark deferred
- `sha1` — unsupported: slow benchmark deferred
- `sha3` — unsupported: slow benchmark deferred
- `siphash24` — unsupported: slow benchmark deferred
- `spectral` — unsupported: slow benchmark deferred

## compcert-compile (4)

- `annot1` — compile: build/suites/CompCert/test/regression/annot1.c:7:10: error: use of unknown builtin '__builtin_annot_intval' [-Wimplicit-function-declaration]
- `extasm` — compile: cinterp: unsupported instruction: %1 = call i32 asm "TEST0 out:$0 in:$1", "=r,r,~{cc},~{dirflag},~{fpsr},~{flags}"(i32 %0), !srcloc !24
- `init3` — compile: build/suites/CompCert/test/regression/init3.c:5:14: error: incompatible pointer to integer conversion initializing 'int' with an expression of type 'void *' [-Wint-c
- `packedstruct1` — compile: build/suites/CompCert/test/regression/packedstruct1.c:19:19: error: expected identifier or '('

## gcc-ieee (15)

- `bfloat16-builtin-issignaling-1` — compile: In file included from build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/execute/ieee/bfloat16-builtin-issignaling-1.c:21:
- `builtin-issignaling-1` — compile: cinterp: unsupported instruction: call void asm sideeffect "", "~{memory},~{dirflag},~{fpsr},~{flags}"(), !srcloc !65
- `cdivchkd` — non-goal: _Complex (explicitly unsupported); observed 2026-10-31
- `cdivchkf` — non-goal: _Complex (explicitly unsupported); observed 2026-10-31
- `cdivchkld` — non-goal: _Complex (explicitly unsupported); observed 2026-10-31
- `float128-builtin-issignaling-1` — compile: In file included from build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/execute/ieee/float128-builtin-issignaling-1.c:13:
- `float128x-builtin-issignaling-1` — compile: In file included from build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/execute/ieee/float128x-builtin-issignaling-1.c:13:
- `float16-builtin-issignaling-1` — compile: cinterp: bad parameter: 'half noundef %x'
- `float32-builtin-issignaling-1` — compile: In file included from build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/execute/ieee/float32-builtin-issignaling-1.c:13:
- `float32x-builtin-issignaling-1` — compile: In file included from build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/execute/ieee/float32x-builtin-issignaling-1.c:13:
- `float64-builtin-issignaling-1` — compile: In file included from build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/execute/ieee/float64-builtin-issignaling-1.c:13:
- `float64x-builtin-issignaling-1` — compile: In file included from build/suites/gcc-torture/gcc/testsuite/gcc.c-torture/execute/ieee/float64x-builtin-issignaling-1.c:13:
- `fp-cmp-cond-1` — non-goal:vector_type (<1 x float>): cinterp unsupported fcmp type <1
- `pr50310` — compile: cinterp: unsupported instruction: call void asm sideeffect "", "~{memory},~{dirflag},~{fpsr},~{flags}"(), !srcloc !385
- `pr72824-2` — compile: cinterp: bad parameter: '<4 x float> noundef %value'

## gcc-torture (7)

- `20101011-1` — unsupported: signal/SIGFPE runtime behavior
- `bitfld-3` — dialect: GCC bitfield expression width differs in Clang IR: exit -6 != 0
- `eeprof-1` — unsupported: -finstrument-functions profiling hooks
- `nestfunc-4` — non-goal: nested function/frame limit: exit 1 != 0
- `pr117095` — unsupported: i128 global initializer
- `pr32244-1` — dialect: GCC bitfield expression width differs in Clang IR: exit -6 != 0
- `pr34971` — dialect: GCC bitfield expression width differs in Clang IR: exit -6 != 0

## gcc-torture-compile (8)

- `20010518-2` — compiler limit: static data exceeds VM maximum linear memory (16 MiB)
- `20080625-1` — compiler limit: static data exceeds VM maximum linear memory (16 MiB)
- `limits-externdecl` — compiler limit: more than 512 entries in the CIPI import table
- `pr103813` — compiler limit: static data exceeds VM maximum linear memory (16 MiB)
- `pr37669-2` — compiler limit: more than 64 arguments in one call plan
- `simd-6` — unsupported: vector global initializer
- `stuct` — compiler limit: CIVM module larger than 2 MiB
- `vector-align-1` — unsupported: vector global initializer

## libc-test (28)

- `clocale_mbfuncs` — unsupported: host libc reference difference (musl locale/wide-char)
- `crypt` — unsupported: libcrypt provider unavailable on host
- `dlopen` — unsupported: dlsym returns host pointers outside VM memory/native target model
- `dlopen_dso` — unsupported: dlsym returns host pointers outside VM memory/native target model
- `fnmatch` — unsupported: host libc reference difference (musl fnmatch)
- `fscanf` — unsupported: host libc reference difference (musl scanf)
- `fwscanf` — unsupported: host libc reference difference (musl wide scanf)
- `mbc` — unsupported: host libc reference difference (musl multibyte/locale)
- `pthread_cancel` — unsupported: host pthread/TLS runtime model
- `pthread_cancel-points` — unsupported: host pthread/TLS runtime model
- `pthread_cond` — unsupported: host pthread/TLS runtime model
- `pthread_mutex` — unsupported: host pthread/TLS runtime model
- `pthread_mutex_pi` — unsupported: host pthread/TLS runtime model
- `pthread_robust` — unsupported: host pthread/TLS runtime model
- `pthread_tsd` — foreign-thread callback while the VM is executing (fail-fast thread policy; use idle-VM or same-thread callbacks)
- `sem_init` — unsupported: host pthread/TLS runtime model
- `sscanf` — unsupported: host libc reference difference (musl scanf)
- `strftime` — unsupported: host libc reference difference (musl strftime)
- `strtol` — unsupported: host libc reference difference (musl strtol)
- `tls_align` — unsupported: host pthread/TLS runtime model
- `tls_align_dlopen` — unsupported: host pthread/TLS runtime model
- `tls_align_dso` — unsupported: host pthread/TLS runtime model
- `tls_init` — unsupported: host pthread/TLS runtime model
- `tls_init_dlopen` — unsupported: host pthread/TLS runtime model
- `tls_init_dso` — unsupported: host pthread/TLS runtime model
- `tls_local_exec` — unsupported: host pthread/TLS runtime model
- `vfork` — unsupported: host vfork/expected difference
- `wcstol` — unsupported: host libc reference difference (musl wcstol)

## libc-test-regression (21)

- `daemon-failure` — unsupported: musl-specific daemon behavior
- `dn_expand-empty` — unsupported: musl/glibc resolver reference difference
- `dn_expand-ptr-0` — unsupported: musl/glibc resolver reference difference
- `flockfile-list` — unsupported: native malloc interposition/stdio lifetime model
- `fpclassify-invalid-ld80` — unsupported: musl x87 invalid-ld80 UB semantics
- `malloc-brk-fail` — unsupported: host memory quota/brk semantics out of scope
- `pthread-robust-detach` — unsupported: host pthread/TLS/signal runtime model
- `pthread_atfork-errno-clobber` — unsupported: host pthread/TLS/signal runtime model
- `pthread_cancel-sem_wait` — unsupported: host pthread/TLS/signal runtime model
- `pthread_cond-smasher` — unsupported: host pthread/TLS/signal runtime model
- `pthread_cond_wait-cancel_ignored` — unsupported: host pthread/TLS/signal runtime model
- `pthread_exit-cancel` — unsupported: host pthread/TLS/signal runtime model
- `pthread_exit-dtor` — unsupported: host pthread/TLS/signal runtime model
- `pthread_once-deadlock` — unsupported: host pthread/TLS/signal runtime model
- `raise-race` — unsupported: host pthread/TLS/signal runtime model
- `regex-ere-backref` — unsupported: musl/glibc regex reference difference
- `regex-escaped-high-byte` — unsupported: musl/glibc regex reference difference
- `setvbuf-unget` — unsupported: slow stdio buffer test deferred
- `sigaltstack` — unsupported: host pthread/TLS/signal runtime model
- `tls_get_new-dtv` — unsupported: host pthread/TLS/signal runtime model
- `tls_get_new-dtv_dso` — unsupported: host pthread/TLS/signal runtime model

## llvm-regression-c (2)

- `20020107-1` — unsupported: inline asm
- `pr60822` — compiler limit: CIVM module larger than 2 MiB

## llvm-singlesource (8)

- `2002-12-13-MishaTest` — unsupported: K&R implicit int
- `2006-01-23-UnionInit` — unsupported: zero-size aggregate resource model
- `2007-01-04-KNR-Args` — unsupported: K&R implicit int
- `2008-04-18-LoopBug` — unsupported: K&R implicit int
- `2008-04-20-LoopBug2` — unsupported: K&R implicit int
- `2009-12-07-StructReturn` — unsupported: vector type
- `2020-01-06-coverage-006` — unsupported: i72 aggregate store
- `AtomicOps` — unsupported: K&R implicit int

## tcc-tests2 (43)

- `100_c99array-decls` — diagnostic/frontend: expected compile error/dialect: build/suites/tcc/tests/tests2/100_c99array-decls.c:26:9: error: restrict requires a pointer or reference ('pointer_array' (aka 'int *[2]') is invalid)
- `101_cleanup` — resource: compiler limit: cinterp: compiler limit: function main local_count 65648 exceeds 65535
- `102_alignas` — diagnostic/frontend: expected compile error/dialect: build/suites/tcc/tests/tests2/102_alignas.c:4:14: error: type specifier missing, defaults to 'int'; ISO C99 and later do not support implicit int [-Wimplicit-int]
- `104+_inline` — non-goal: external inline: stdout mismatch
- `104_inline` — non-goal: external inline: stdout mismatch
- `108_constructor` — mismatch: platform/diagnostic: stdout mismatch
- `112_backtrace` — mismatch: platform/diagnostic: stdout mismatch
- `113_btdll` — non-goal: external symbol/inline/asm: stdout mismatch
- `114_bound_signal` — non-goal: threads: stdout mismatch
- `116_bound_setjmp2` — non-goal: threads: exit -11 != 0
- `117_builtins` — non-goal: external symbol/inline/asm: stdout mismatch
- `120+_alias` — harness/test-entry: no runnable main: stdout mismatch
- `120_alias` — frontend/dialect: unsupported compile: build/suites/tcc/tests/tests2/120_alias.c:11:30: error: definition 'alias_int' cannot also be an alias
- `124_atomic_counter` — non-goal: inline asm/atomic: cinterp: unsupported instruction: %4 = atomicrmw add ptr %uc, i8 %3 monotonic, align 1
- `125_atomic_misc` — non-goal: threads: stdout mismatch
- `126_bound_global` — mismatch: platform/diagnostic: stdout mismatch
- `127_asm_goto` — non-goal: inline asm/atomic: cinterp: unsupported instruction: callbr void asm sideeffect "jmp ${0:l}", "!i,~{dirflag},~{fpsr},~{flags}"()
- `128_run_atexit` — harness/test-entry: no runnable main: stdout mismatch
- `136_atomic_gcc_style` — non-goal: inline asm/atomic: cinterp: unsupported instruction: %7 = cmpxchg ptr %atomic_var1, i32 %5, i32 %6 seq_cst seq_cst, align 4
- `138_arm64_encoding` — non-goal: inline asm/atomic: build/suites/tcc/tests/tests2/138_arm64_encoding.c:182:32: error: unknown register name 'x0' in asm
- `139_arm64_errors` — harness/test-entry: no runnable main: stdout mismatch
- `140_arm64_extasm` — non-goal: inline asm/atomic: build/suites/tcc/tests/tests2/140_arm64_extasm.c:156:52: error: value '200' out of range for constraint 'I'
- `141_riscv_asm` — mismatch: platform/diagnostic: stdout mismatch
- `144_tls` — non-goal: threads: stdout mismatch
- `145_winarm64_interlocked` — non-goal: platform header: build/suites/tcc/tests/tests2/145_winarm64_interlocked.c:2:10: fatal error: 'windows.h' file not found
- `146_tls_extern` — non-goal: threads: stdout mismatch
- `148_linker_symbols` — harness/test-entry: no runnable main: stdout mismatch
- `149_parameter_qualifier_errors` — diagnostic/frontend: expected compile error/dialect: build/suites/tcc/tests/tests2/149_parameter_qualifier_errors.c:5:13: error: cannot assign to variable 'pointer' with const-qualified type 'int *const'
- `150_return_qualifiers` — diagnostic/frontend: expected compile error/dialect: build/suites/tcc/tests/tests2/150_return_qualifiers.c:12:5: error: conflicting types for 'const_return'
- `151_atomic_header` — frontend/dialect: unsupported compile: cinterp: unsupported type volatile
- `34_array_assignment` — diagnostic/frontend: expected compile error/dialect: build/suites/tcc/tests/tests2/34_array_assignment.c:16:6: error: array type 'int[4]' is not assignable
- `46_grep` — mismatch: platform/diagnostic: stdout mismatch
- `60_errors_and_warnings` — harness/test-entry: no runnable main: stdout mismatch
- `70_floating_point_literals` — mismatch: platform/diagnostic: stdout mismatch
- `73_arm64` — mismatch: platform/diagnostic: stdout mismatch
- `76_dollars_in_identifiers` — frontend/dialect: unsupported compile: cinterp: unsupported operand: '%"$"'
- `83_utf8_in_identifiers` — mismatch: platform/diagnostic: stdout mismatch
- `85_asm-outside-function` — non-goal: external symbol/inline/asm: stdout mismatch
- `90_struct-init` — frontend/dialect: unsupported compile: build/suites/tcc/tests/tests2/90_struct-init.c:264:14: error: cannot compile this GNU array range designator extension yet
- `95_bitfields` — non-goal: >64-bit bitfield/aggregate: cinterp: aggregate store unsupported: i88
- `95_bitfields_ms` — dialect: Clang ms_struct bitfield width/layout differs from TCC (native clang output matches cinterp)
- `96_nodata_wanted` — harness/test-entry: no runnable main: stdout mismatch
- `98_al_ax_extend` — non-goal: external symbol/inline/asm: stdout mismatch

