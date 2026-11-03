; ModuleID = 'examples/ffi_qsort.c'
source_filename = "examples/ffi_qsort.c"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

@__const.main.a = private unnamed_addr constant [5 x i32] [i32 3, i32 1, i32 4, i32 2, i32 5], align 16

; Function Attrs: noinline nounwind optnone uwtable
define i32 @cmp(ptr noundef %a, ptr noundef %b) #0 !dbg !13 {
entry:
  %a.addr = alloca ptr, align 8
  %b.addr = alloca ptr, align 8
  %x = alloca i32, align 4
  %y = alloca i32, align 4
  store ptr %a, ptr %a.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %a.addr, metadata !19, metadata !DIExpression()), !dbg !20
  store ptr %b, ptr %b.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %b.addr, metadata !21, metadata !DIExpression()), !dbg !22
  call void @llvm.dbg.declare(metadata ptr %x, metadata !23, metadata !DIExpression()), !dbg !24
  %0 = load ptr, ptr %a.addr, align 8, !dbg !25
  %1 = load i32, ptr %0, align 4, !dbg !26
  store i32 %1, ptr %x, align 4, !dbg !24
  call void @llvm.dbg.declare(metadata ptr %y, metadata !27, metadata !DIExpression()), !dbg !28
  %2 = load ptr, ptr %b.addr, align 8, !dbg !29
  %3 = load i32, ptr %2, align 4, !dbg !30
  store i32 %3, ptr %y, align 4, !dbg !28
  %4 = load i32, ptr %x, align 4, !dbg !31
  %5 = load i32, ptr %y, align 4, !dbg !32
  %sub = sub nsw i32 %4, %5, !dbg !33
  ret i32 %sub, !dbg !34
}

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare void @llvm.dbg.declare(metadata, metadata, metadata) #1

; Function Attrs: noinline nounwind optnone uwtable
define i32 @main() #0 !dbg !35 {
entry:
  %retval = alloca i32, align 4
  %a = alloca [5 x i32], align 16
  store i32 0, ptr %retval, align 4
  call void @llvm.dbg.declare(metadata ptr %a, metadata !38, metadata !DIExpression()), !dbg !42
  call void @llvm.memcpy.p0.p0.i64(ptr align 16 %a, ptr align 16 @__const.main.a, i64 20, i1 false), !dbg !42
  %arraydecay = getelementptr inbounds [5 x i32], ptr %a, i64 0, i64 0, !dbg !43
  call void @qsort(ptr noundef %arraydecay, i64 noundef 5, i64 noundef 4, ptr noundef @cmp), !dbg !44
  %arrayidx = getelementptr inbounds [5 x i32], ptr %a, i64 0, i64 0, !dbg !45
  %0 = load i32, ptr %arrayidx, align 16, !dbg !45
  ret i32 %0, !dbg !46
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias nocapture writeonly, ptr noalias nocapture readonly, i64, i1 immarg) #2

declare void @qsort(ptr noundef, i64 noundef, i64 noundef, ptr noundef) #3

attributes #0 = { noinline nounwind optnone uwtable "frame-pointer"="all" "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="znver3" "target-features"="+64bit,+adx,+aes,+allow-light-256-bit,+avx,+avx2,+bmi,+bmi2,+branchfusion,+clflushopt,+clwb,+clzero,+cmov,+crc32,+cx16,+cx8,+f16c,+fast-15bytenop,+fast-bextr,+fast-lzcnt,+fast-movbe,+fast-scalar-fsqrt,+fast-scalar-shift-masks,+fast-variable-perlane-shuffle,+fast-vector-fsqrt,+fma,+fsgsbase,+fsrm,+fxsr,+invpcid,+lzcnt,+macrofusion,+mmx,+movbe,+nopl,+pclmul,+popcnt,+prfchw,+rdpid,+rdpru,+rdrnd,+rdseed,+sahf,+sbb-dep-breaking,+sha,+shstk,+slow-shld,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+sse4a,+ssse3,+vaes,+vpclmulqdq,+vzeroupper,+x87,+xsave,+xsavec,+xsaveopt,+xsaves,-16bit-mode,-32bit-mode,-3dnow,-3dnowa,-amx-bf16,-amx-complex,-amx-fp16,-amx-int8,-amx-tile,-avx10.1-256,-avx10.1-512,-avx512bf16,-avx512bitalg,-avx512bw,-avx512cd,-avx512dq,-avx512er,-avx512f,-avx512fp16,-avx512ifma,-avx512pf,-avx512vbmi,-avx512vbmi2,-avx512vl,-avx512vnni,-avx512vp2intersect,-avx512vpopcntdq,-avxifma,-avxneconvert,-avxvnni,-avxvnniint16,-avxvnniint8,-ccmp,-cf,-cldemote,-cmpccxadd,-egpr,-enqcmd,-ermsb,-false-deps-getmant,-false-deps-lzcnt-tzcnt,-false-deps-mulc,-false-deps-mullq,-false-deps-perm,-false-deps-popcnt,-false-deps-range,-fast-11bytenop,-fast-7bytenop,-fast-gather,-fast-hops,-fast-shld-rotate,-fast-variable-crosslane-shuffle,-fast-vector-shift-masks,-faster-shift-than-shuffle,-fma4,-gfni,-harden-sls-ijmp,-harden-sls-ret,-hreset,-idivl-to-divb,-idivq-to-divl,-kl,-lea-sp,-lea-uses-ag,-lvi-cfi,-lvi-load-hardening,-lwp,-movdir64b,-movdiri,-mwaitx,-ndd,-no-bypass-delay,-no-bypass-delay-blend,-no-bypass-delay-mov,-no-bypass-delay-shuffle,-pad-short-functions,-pconfig,-pku,-ppx,-prefer-128-bit,-prefer-256-bit,-prefer-mask-registers,-prefer-movmsk-over-vtest,-prefer-no-gather,-prefer-no-scatter,-prefetchi,-prefetchwt1,-ptwrite,-push2pop2,-raoint,-retpoline,-retpoline-external-thunk,-retpoline-indirect-branches,-retpoline-indirect-calls,-rtm,-serialize,-seses,-sgx,-sha512,-slow-3ops-lea,-slow-incdec,-slow-lea,-slow-pmaddwd,-slow-pmulld,-slow-two-mem-ops,-slow-unaligned-mem-16,-slow-unaligned-mem-32,-sm3,-sm4,-soft-float,-sse-unaligned-mem,-tagged-globals,-tbm,-tsxldtrk,-tuning-fast-imm-vector-shift,-uintr,-use-glm-div-sqrt-costs,-use-slm-arith-costs,-usermsr,-waitpkg,-wbnoinvd,-widekl,-xop" "tune-cpu"="generic" }
attributes #1 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #2 = { nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #3 = { "frame-pointer"="all" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="znver3" "target-features"="+64bit,+adx,+aes,+allow-light-256-bit,+avx,+avx2,+bmi,+bmi2,+branchfusion,+clflushopt,+clwb,+clzero,+cmov,+crc32,+cx16,+cx8,+f16c,+fast-15bytenop,+fast-bextr,+fast-lzcnt,+fast-movbe,+fast-scalar-fsqrt,+fast-scalar-shift-masks,+fast-variable-perlane-shuffle,+fast-vector-fsqrt,+fma,+fsgsbase,+fsrm,+fxsr,+invpcid,+lzcnt,+macrofusion,+mmx,+movbe,+nopl,+pclmul,+popcnt,+prfchw,+rdpid,+rdpru,+rdrnd,+rdseed,+sahf,+sbb-dep-breaking,+sha,+shstk,+slow-shld,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+sse4a,+ssse3,+vaes,+vpclmulqdq,+vzeroupper,+x87,+xsave,+xsavec,+xsaveopt,+xsaves,-16bit-mode,-32bit-mode,-3dnow,-3dnowa,-amx-bf16,-amx-complex,-amx-fp16,-amx-int8,-amx-tile,-avx10.1-256,-avx10.1-512,-avx512bf16,-avx512bitalg,-avx512bw,-avx512cd,-avx512dq,-avx512er,-avx512f,-avx512fp16,-avx512ifma,-avx512pf,-avx512vbmi,-avx512vbmi2,-avx512vl,-avx512vnni,-avx512vp2intersect,-avx512vpopcntdq,-avxifma,-avxneconvert,-avxvnni,-avxvnniint16,-avxvnniint8,-ccmp,-cf,-cldemote,-cmpccxadd,-egpr,-enqcmd,-ermsb,-false-deps-getmant,-false-deps-lzcnt-tzcnt,-false-deps-mulc,-false-deps-mullq,-false-deps-perm,-false-deps-popcnt,-false-deps-range,-fast-11bytenop,-fast-7bytenop,-fast-gather,-fast-hops,-fast-shld-rotate,-fast-variable-crosslane-shuffle,-fast-vector-shift-masks,-faster-shift-than-shuffle,-fma4,-gfni,-harden-sls-ijmp,-harden-sls-ret,-hreset,-idivl-to-divb,-idivq-to-divl,-kl,-lea-sp,-lea-uses-ag,-lvi-cfi,-lvi-load-hardening,-lwp,-movdir64b,-movdiri,-mwaitx,-ndd,-no-bypass-delay,-no-bypass-delay-blend,-no-bypass-delay-mov,-no-bypass-delay-shuffle,-pad-short-functions,-pconfig,-pku,-ppx,-prefer-128-bit,-prefer-256-bit,-prefer-mask-registers,-prefer-movmsk-over-vtest,-prefer-no-gather,-prefer-no-scatter,-prefetchi,-prefetchwt1,-ptwrite,-push2pop2,-raoint,-retpoline,-retpoline-external-thunk,-retpoline-indirect-branches,-retpoline-indirect-calls,-rtm,-serialize,-seses,-sgx,-sha512,-slow-3ops-lea,-slow-incdec,-slow-lea,-slow-pmaddwd,-slow-pmulld,-slow-two-mem-ops,-slow-unaligned-mem-16,-slow-unaligned-mem-32,-sm3,-sm4,-soft-float,-sse-unaligned-mem,-tagged-globals,-tbm,-tsxldtrk,-tuning-fast-imm-vector-shift,-uintr,-use-glm-div-sqrt-costs,-use-slm-arith-costs,-usermsr,-waitpkg,-wbnoinvd,-widekl,-xop" "tune-cpu"="generic" }

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!6, !7, !8, !9, !10, !11}
!llvm.ident = !{!12}

!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "clang version 18.1.6 (https://github.com/ziglang/zig-bootstrap 98bc6bf4fc4009888d33941daf6b600d20a42a56)", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !2, splitDebugInlining: false, nameTableKind: None)
!1 = !DIFile(filename: "examples/ffi_qsort.c", directory: "/home/admin/cl")
!2 = !{!3}
!3 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !4, size: 64)
!4 = !DIDerivedType(tag: DW_TAG_const_type, baseType: !5)
!5 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!6 = !{i32 7, !"Dwarf Version", i32 4}
!7 = !{i32 2, !"Debug Info Version", i32 3}
!8 = !{i32 1, !"wchar_size", i32 4}
!9 = !{i32 8, !"PIC Level", i32 2}
!10 = !{i32 7, !"uwtable", i32 2}
!11 = !{i32 7, !"frame-pointer", i32 2}
!12 = !{!"clang version 18.1.6 (https://github.com/ziglang/zig-bootstrap 98bc6bf4fc4009888d33941daf6b600d20a42a56)"}
!13 = distinct !DISubprogram(name: "cmp", scope: !1, file: !1, line: 4, type: !14, scopeLine: 4, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !18)
!14 = !DISubroutineType(types: !15)
!15 = !{!5, !16, !16}
!16 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !17, size: 64)
!17 = !DIDerivedType(tag: DW_TAG_const_type, baseType: null)
!18 = !{}
!19 = !DILocalVariable(name: "a", arg: 1, scope: !13, file: !1, line: 4, type: !16)
!20 = !DILocation(line: 4, column: 21, scope: !13)
!21 = !DILocalVariable(name: "b", arg: 2, scope: !13, file: !1, line: 4, type: !16)
!22 = !DILocation(line: 4, column: 36, scope: !13)
!23 = !DILocalVariable(name: "x", scope: !13, file: !1, line: 5, type: !5)
!24 = !DILocation(line: 5, column: 9, scope: !13)
!25 = !DILocation(line: 5, column: 27, scope: !13)
!26 = !DILocation(line: 5, column: 13, scope: !13)
!27 = !DILocalVariable(name: "y", scope: !13, file: !1, line: 6, type: !5)
!28 = !DILocation(line: 6, column: 9, scope: !13)
!29 = !DILocation(line: 6, column: 27, scope: !13)
!30 = !DILocation(line: 6, column: 13, scope: !13)
!31 = !DILocation(line: 7, column: 12, scope: !13)
!32 = !DILocation(line: 7, column: 16, scope: !13)
!33 = !DILocation(line: 7, column: 14, scope: !13)
!34 = !DILocation(line: 7, column: 5, scope: !13)
!35 = distinct !DISubprogram(name: "main", scope: !1, file: !1, line: 10, type: !36, scopeLine: 10, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !18)
!36 = !DISubroutineType(types: !37)
!37 = !{!5}
!38 = !DILocalVariable(name: "a", scope: !35, file: !1, line: 11, type: !39)
!39 = !DICompositeType(tag: DW_TAG_array_type, baseType: !5, size: 160, elements: !40)
!40 = !{!41}
!41 = !DISubrange(count: 5)
!42 = !DILocation(line: 11, column: 9, scope: !35)
!43 = !DILocation(line: 12, column: 11, scope: !35)
!44 = !DILocation(line: 12, column: 5, scope: !35)
!45 = !DILocation(line: 13, column: 12, scope: !35)
!46 = !DILocation(line: 13, column: 5, scope: !35)
