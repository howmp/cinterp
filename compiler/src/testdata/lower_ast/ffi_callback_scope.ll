; ModuleID = 'examples/ffi_callback_scope.c'
source_filename = "examples/ffi_callback_scope.c"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

@__const.main.a = private unnamed_addr constant [5 x i32] [i32 3, i32 1, i32 4, i32 2, i32 5], align 16

; Function Attrs: noinline nounwind optnone uwtable
define i32 @cmp(ptr noundef %a, ptr noundef %b) #0 {
entry:
  %a.addr = alloca ptr, align 8
  %b.addr = alloca ptr, align 8
  %x = alloca i32, align 4
  %y = alloca i32, align 4
  store ptr %a, ptr %a.addr, align 8
  store ptr %b, ptr %b.addr, align 8
  %0 = load ptr, ptr %a.addr, align 8
  %1 = load i32, ptr %0, align 4
  store i32 %1, ptr %x, align 4
  %2 = load ptr, ptr %b.addr, align 8
  %3 = load i32, ptr %2, align 4
  store i32 %3, ptr %y, align 4
  %4 = load i32, ptr %x, align 4
  %5 = load i32, ptr %y, align 4
  %sub = sub nsw i32 %4, %5
  ret i32 %sub
}

; Function Attrs: noinline nounwind optnone uwtable
define i32 @main() #0 {
entry:
  %retval = alloca i32, align 4
  %a = alloca [5 x i32], align 16
  %cb = alloca ptr, align 8
  %status = alloca i32, align 4
  store i32 0, ptr %retval, align 4
  call void @llvm.memcpy.p0.p0.i64(ptr align 16 %a, ptr align 16 @__const.main.a, i64 20, i1 false)
  %call = call ptr @__ci_callback_acquire(ptr noundef @cmp)
  store ptr %call, ptr %cb, align 8
  %0 = load ptr, ptr %cb, align 8
  %cmp = icmp eq ptr %0, null
  br i1 %cmp, label %if.then, label %if.end

if.then:                                          ; preds = %entry
  store i32 1, ptr %retval, align 4
  br label %return

if.end:                                           ; preds = %entry
  %arraydecay = getelementptr inbounds [5 x i32], ptr %a, i64 0, i64 0
  %1 = load ptr, ptr %cb, align 8
  call void @qsort(ptr noundef %arraydecay, i64 noundef 5, i64 noundef 4, ptr noundef %1)
  %2 = load ptr, ptr %cb, align 8
  %call1 = call i32 @__ci_callback_release(ptr noundef %2)
  store i32 %call1, ptr %status, align 4
  %3 = load i32, ptr %status, align 4
  %cmp2 = icmp ne i32 %3, 0
  br i1 %cmp2, label %if.then3, label %if.end4

if.then3:                                         ; preds = %if.end
  store i32 2, ptr %retval, align 4
  br label %return

if.end4:                                          ; preds = %if.end
  %arrayidx = getelementptr inbounds [5 x i32], ptr %a, i64 0, i64 0
  %4 = load i32, ptr %arrayidx, align 16
  store i32 %4, ptr %retval, align 4
  br label %return

return:                                           ; preds = %if.end4, %if.then3, %if.then
  %5 = load i32, ptr %retval, align 4
  ret i32 %5
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias nocapture writeonly, ptr noalias nocapture readonly, i64, i1 immarg) #1

declare ptr @__ci_callback_acquire(ptr noundef) #2

declare void @qsort(ptr noundef, i64 noundef, i64 noundef, ptr noundef) #2

declare i32 @__ci_callback_release(ptr noundef) #2

attributes #0 = { noinline nounwind optnone uwtable "frame-pointer"="all" "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="znver3" "target-features"="+64bit,+adx,+aes,+allow-light-256-bit,+avx,+avx2,+bmi,+bmi2,+branchfusion,+clflushopt,+clwb,+clzero,+cmov,+crc32,+cx16,+cx8,+f16c,+fast-15bytenop,+fast-bextr,+fast-lzcnt,+fast-movbe,+fast-scalar-fsqrt,+fast-scalar-shift-masks,+fast-variable-perlane-shuffle,+fast-vector-fsqrt,+fma,+fsgsbase,+fsrm,+fxsr,+invpcid,+lzcnt,+macrofusion,+mmx,+movbe,+nopl,+pclmul,+popcnt,+prfchw,+rdpid,+rdpru,+rdrnd,+rdseed,+sahf,+sbb-dep-breaking,+sha,+shstk,+slow-shld,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+sse4a,+ssse3,+vaes,+vpclmulqdq,+vzeroupper,+x87,+xsave,+xsavec,+xsaveopt,+xsaves,-16bit-mode,-32bit-mode,-3dnow,-3dnowa,-amx-bf16,-amx-complex,-amx-fp16,-amx-int8,-amx-tile,-avx10.1-256,-avx10.1-512,-avx512bf16,-avx512bitalg,-avx512bw,-avx512cd,-avx512dq,-avx512er,-avx512f,-avx512fp16,-avx512ifma,-avx512pf,-avx512vbmi,-avx512vbmi2,-avx512vl,-avx512vnni,-avx512vp2intersect,-avx512vpopcntdq,-avxifma,-avxneconvert,-avxvnni,-avxvnniint16,-avxvnniint8,-ccmp,-cf,-cldemote,-cmpccxadd,-egpr,-enqcmd,-ermsb,-false-deps-getmant,-false-deps-lzcnt-tzcnt,-false-deps-mulc,-false-deps-mullq,-false-deps-perm,-false-deps-popcnt,-false-deps-range,-fast-11bytenop,-fast-7bytenop,-fast-gather,-fast-hops,-fast-shld-rotate,-fast-variable-crosslane-shuffle,-fast-vector-shift-masks,-faster-shift-than-shuffle,-fma4,-gfni,-harden-sls-ijmp,-harden-sls-ret,-hreset,-idivl-to-divb,-idivq-to-divl,-kl,-lea-sp,-lea-uses-ag,-lvi-cfi,-lvi-load-hardening,-lwp,-movdir64b,-movdiri,-mwaitx,-ndd,-no-bypass-delay,-no-bypass-delay-blend,-no-bypass-delay-mov,-no-bypass-delay-shuffle,-pad-short-functions,-pconfig,-pku,-ppx,-prefer-128-bit,-prefer-256-bit,-prefer-mask-registers,-prefer-movmsk-over-vtest,-prefer-no-gather,-prefer-no-scatter,-prefetchi,-prefetchwt1,-ptwrite,-push2pop2,-raoint,-retpoline,-retpoline-external-thunk,-retpoline-indirect-branches,-retpoline-indirect-calls,-rtm,-serialize,-seses,-sgx,-sha512,-slow-3ops-lea,-slow-incdec,-slow-lea,-slow-pmaddwd,-slow-pmulld,-slow-two-mem-ops,-slow-unaligned-mem-16,-slow-unaligned-mem-32,-sm3,-sm4,-soft-float,-sse-unaligned-mem,-tagged-globals,-tbm,-tsxldtrk,-tuning-fast-imm-vector-shift,-uintr,-use-glm-div-sqrt-costs,-use-slm-arith-costs,-usermsr,-waitpkg,-wbnoinvd,-widekl,-xop" "tune-cpu"="generic" }
attributes #1 = { nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #2 = { "frame-pointer"="all" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="znver3" "target-features"="+64bit,+adx,+aes,+allow-light-256-bit,+avx,+avx2,+bmi,+bmi2,+branchfusion,+clflushopt,+clwb,+clzero,+cmov,+crc32,+cx16,+cx8,+f16c,+fast-15bytenop,+fast-bextr,+fast-lzcnt,+fast-movbe,+fast-scalar-fsqrt,+fast-scalar-shift-masks,+fast-variable-perlane-shuffle,+fast-vector-fsqrt,+fma,+fsgsbase,+fsrm,+fxsr,+invpcid,+lzcnt,+macrofusion,+mmx,+movbe,+nopl,+pclmul,+popcnt,+prfchw,+rdpid,+rdpru,+rdrnd,+rdseed,+sahf,+sbb-dep-breaking,+sha,+shstk,+slow-shld,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+sse4a,+ssse3,+vaes,+vpclmulqdq,+vzeroupper,+x87,+xsave,+xsavec,+xsaveopt,+xsaves,-16bit-mode,-32bit-mode,-3dnow,-3dnowa,-amx-bf16,-amx-complex,-amx-fp16,-amx-int8,-amx-tile,-avx10.1-256,-avx10.1-512,-avx512bf16,-avx512bitalg,-avx512bw,-avx512cd,-avx512dq,-avx512er,-avx512f,-avx512fp16,-avx512ifma,-avx512pf,-avx512vbmi,-avx512vbmi2,-avx512vl,-avx512vnni,-avx512vp2intersect,-avx512vpopcntdq,-avxifma,-avxneconvert,-avxvnni,-avxvnniint16,-avxvnniint8,-ccmp,-cf,-cldemote,-cmpccxadd,-egpr,-enqcmd,-ermsb,-false-deps-getmant,-false-deps-lzcnt-tzcnt,-false-deps-mulc,-false-deps-mullq,-false-deps-perm,-false-deps-popcnt,-false-deps-range,-fast-11bytenop,-fast-7bytenop,-fast-gather,-fast-hops,-fast-shld-rotate,-fast-variable-crosslane-shuffle,-fast-vector-shift-masks,-faster-shift-than-shuffle,-fma4,-gfni,-harden-sls-ijmp,-harden-sls-ret,-hreset,-idivl-to-divb,-idivq-to-divl,-kl,-lea-sp,-lea-uses-ag,-lvi-cfi,-lvi-load-hardening,-lwp,-movdir64b,-movdiri,-mwaitx,-ndd,-no-bypass-delay,-no-bypass-delay-blend,-no-bypass-delay-mov,-no-bypass-delay-shuffle,-pad-short-functions,-pconfig,-pku,-ppx,-prefer-128-bit,-prefer-256-bit,-prefer-mask-registers,-prefer-movmsk-over-vtest,-prefer-no-gather,-prefer-no-scatter,-prefetchi,-prefetchwt1,-ptwrite,-push2pop2,-raoint,-retpoline,-retpoline-external-thunk,-retpoline-indirect-branches,-retpoline-indirect-calls,-rtm,-serialize,-seses,-sgx,-sha512,-slow-3ops-lea,-slow-incdec,-slow-lea,-slow-pmaddwd,-slow-pmulld,-slow-two-mem-ops,-slow-unaligned-mem-16,-slow-unaligned-mem-32,-sm3,-sm4,-soft-float,-sse-unaligned-mem,-tagged-globals,-tbm,-tsxldtrk,-tuning-fast-imm-vector-shift,-uintr,-use-glm-div-sqrt-costs,-use-slm-arith-costs,-usermsr,-waitpkg,-wbnoinvd,-widekl,-xop" "tune-cpu"="generic" }

!llvm.module.flags = !{!0, !1, !2, !3, !4}
!llvm.ident = !{!5}

!0 = !{i32 7, !"Dwarf Version", i32 4}
!1 = !{i32 1, !"wchar_size", i32 4}
!2 = !{i32 8, !"PIC Level", i32 2}
!3 = !{i32 7, !"uwtable", i32 2}
!4 = !{i32 7, !"frame-pointer", i32 2}
!5 = !{!"clang version 18.1.6 (https://github.com/ziglang/zig-bootstrap 98bc6bf4fc4009888d33941daf6b600d20a42a56)"}
