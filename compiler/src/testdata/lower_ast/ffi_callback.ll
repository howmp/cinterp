; ModuleID = 'examples/ffi_callback.c'
source_filename = "examples/ffi_callback.c"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%struct.S8 = type { i32, i32 }

@__const.main.s = private unnamed_addr constant %struct.S8 { i32 3, i32 4 }, align 4

; Function Attrs: noinline nounwind optnone uwtable
define i64 @cb6(i64 noundef %a, i64 noundef %b, i64 noundef %c, i64 noundef %d, i64 noundef %e, i64 noundef %f) #0 !dbg !11 {
entry:
  %a.addr = alloca i64, align 8
  %b.addr = alloca i64, align 8
  %c.addr = alloca i64, align 8
  %d.addr = alloca i64, align 8
  %e.addr = alloca i64, align 8
  %f.addr = alloca i64, align 8
  store i64 %a, ptr %a.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %a.addr, metadata !16, metadata !DIExpression()), !dbg !17
  store i64 %b, ptr %b.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %b.addr, metadata !18, metadata !DIExpression()), !dbg !19
  store i64 %c, ptr %c.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %c.addr, metadata !20, metadata !DIExpression()), !dbg !21
  store i64 %d, ptr %d.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %d.addr, metadata !22, metadata !DIExpression()), !dbg !23
  store i64 %e, ptr %e.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %e.addr, metadata !24, metadata !DIExpression()), !dbg !25
  store i64 %f, ptr %f.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %f.addr, metadata !26, metadata !DIExpression()), !dbg !27
  %0 = load i64, ptr %a.addr, align 8, !dbg !28
  %1 = load i64, ptr %b.addr, align 8, !dbg !29
  %add = add nsw i64 %0, %1, !dbg !30
  %2 = load i64, ptr %c.addr, align 8, !dbg !31
  %add1 = add nsw i64 %add, %2, !dbg !32
  %3 = load i64, ptr %d.addr, align 8, !dbg !33
  %add2 = add nsw i64 %add1, %3, !dbg !34
  %4 = load i64, ptr %e.addr, align 8, !dbg !35
  %add3 = add nsw i64 %add2, %4, !dbg !36
  %5 = load i64, ptr %f.addr, align 8, !dbg !37
  %add4 = add nsw i64 %add3, %5, !dbg !38
  ret i64 %add4, !dbg !39
}

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare void @llvm.dbg.declare(metadata, metadata, metadata) #1

; Function Attrs: noinline nounwind optnone uwtable
define i64 @cb_s8(i64 %x.coerce) #0 !dbg !40 {
entry:
  %retval = alloca %struct.S8, align 4
  %x = alloca %struct.S8, align 4
  store i64 %x.coerce, ptr %x, align 4
  call void @llvm.dbg.declare(metadata ptr %x, metadata !48, metadata !DIExpression()), !dbg !49
  call void @llvm.dbg.declare(metadata ptr %retval, metadata !50, metadata !DIExpression()), !dbg !51
  %a = getelementptr inbounds %struct.S8, ptr %retval, i32 0, i32 0, !dbg !52
  %a1 = getelementptr inbounds %struct.S8, ptr %x, i32 0, i32 0, !dbg !53
  %0 = load i32, ptr %a1, align 4, !dbg !53
  %add = add nsw i32 %0, 1, !dbg !54
  store i32 %add, ptr %a, align 4, !dbg !52
  %b = getelementptr inbounds %struct.S8, ptr %retval, i32 0, i32 1, !dbg !52
  %b2 = getelementptr inbounds %struct.S8, ptr %x, i32 0, i32 1, !dbg !55
  %1 = load i32, ptr %b2, align 4, !dbg !55
  %add3 = add nsw i32 %1, 2, !dbg !56
  store i32 %add3, ptr %b, align 4, !dbg !52
  %2 = load i64, ptr %retval, align 4, !dbg !57
  ret i64 %2, !dbg !57
}

; Function Attrs: noinline nounwind optnone uwtable
define i32 @main() #0 !dbg !58 {
entry:
  %retval = alloca i32, align 4
  %s = alloca %struct.S8, align 4
  %r = alloca %struct.S8, align 4
  store i32 0, ptr %retval, align 4
  call void @llvm.dbg.declare(metadata ptr %s, metadata !60, metadata !DIExpression()), !dbg !61
  call void @llvm.memcpy.p0.p0.i64(ptr align 4 %s, ptr align 4 @__const.main.s, i64 8, i1 false), !dbg !61
  call void @llvm.dbg.declare(metadata ptr %r, metadata !62, metadata !DIExpression()), !dbg !63
  %0 = load i64, ptr %s, align 4, !dbg !64
  %call = call i64 @c_invoke_s8(ptr noundef @cb_s8, i64 %0), !dbg !64
  store i64 %call, ptr %r, align 4, !dbg !64
  %call1 = call i64 @c_invoke6(ptr noundef @cb6, i64 noundef 1, i64 noundef 2, i64 noundef 3, i64 noundef 4, i64 noundef 5, i64 noundef 6), !dbg !65
  %mul = mul nsw i64 %call1, 10, !dbg !66
  %a = getelementptr inbounds %struct.S8, ptr %r, i32 0, i32 0, !dbg !67
  %1 = load i32, ptr %a, align 4, !dbg !67
  %mul2 = mul nsw i32 %1, 10, !dbg !68
  %conv = sext i32 %mul2 to i64, !dbg !69
  %add = add nsw i64 %mul, %conv, !dbg !70
  %b = getelementptr inbounds %struct.S8, ptr %r, i32 0, i32 1, !dbg !71
  %2 = load i32, ptr %b, align 4, !dbg !71
  %conv3 = sext i32 %2 to i64, !dbg !72
  %add4 = add nsw i64 %add, %conv3, !dbg !73
  %conv5 = trunc i64 %add4 to i32, !dbg !74
  ret i32 %conv5, !dbg !75
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias nocapture writeonly, ptr noalias nocapture readonly, i64, i1 immarg) #2

declare i64 @c_invoke_s8(ptr noundef, i64) #3

declare i64 @c_invoke6(ptr noundef, i64 noundef, i64 noundef, i64 noundef, i64 noundef, i64 noundef, i64 noundef) #3

attributes #0 = { noinline nounwind optnone uwtable "frame-pointer"="all" "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="znver3" "target-features"="+64bit,+adx,+aes,+allow-light-256-bit,+avx,+avx2,+bmi,+bmi2,+branchfusion,+clflushopt,+clwb,+clzero,+cmov,+crc32,+cx16,+cx8,+f16c,+fast-15bytenop,+fast-bextr,+fast-lzcnt,+fast-movbe,+fast-scalar-fsqrt,+fast-scalar-shift-masks,+fast-variable-perlane-shuffle,+fast-vector-fsqrt,+fma,+fsgsbase,+fsrm,+fxsr,+invpcid,+lzcnt,+macrofusion,+mmx,+movbe,+nopl,+pclmul,+popcnt,+prfchw,+rdpid,+rdpru,+rdrnd,+rdseed,+sahf,+sbb-dep-breaking,+sha,+shstk,+slow-shld,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+sse4a,+ssse3,+vaes,+vpclmulqdq,+vzeroupper,+x87,+xsave,+xsavec,+xsaveopt,+xsaves,-16bit-mode,-32bit-mode,-3dnow,-3dnowa,-amx-bf16,-amx-complex,-amx-fp16,-amx-int8,-amx-tile,-avx10.1-256,-avx10.1-512,-avx512bf16,-avx512bitalg,-avx512bw,-avx512cd,-avx512dq,-avx512er,-avx512f,-avx512fp16,-avx512ifma,-avx512pf,-avx512vbmi,-avx512vbmi2,-avx512vl,-avx512vnni,-avx512vp2intersect,-avx512vpopcntdq,-avxifma,-avxneconvert,-avxvnni,-avxvnniint16,-avxvnniint8,-ccmp,-cf,-cldemote,-cmpccxadd,-egpr,-enqcmd,-ermsb,-false-deps-getmant,-false-deps-lzcnt-tzcnt,-false-deps-mulc,-false-deps-mullq,-false-deps-perm,-false-deps-popcnt,-false-deps-range,-fast-11bytenop,-fast-7bytenop,-fast-gather,-fast-hops,-fast-shld-rotate,-fast-variable-crosslane-shuffle,-fast-vector-shift-masks,-faster-shift-than-shuffle,-fma4,-gfni,-harden-sls-ijmp,-harden-sls-ret,-hreset,-idivl-to-divb,-idivq-to-divl,-kl,-lea-sp,-lea-uses-ag,-lvi-cfi,-lvi-load-hardening,-lwp,-movdir64b,-movdiri,-mwaitx,-ndd,-no-bypass-delay,-no-bypass-delay-blend,-no-bypass-delay-mov,-no-bypass-delay-shuffle,-pad-short-functions,-pconfig,-pku,-ppx,-prefer-128-bit,-prefer-256-bit,-prefer-mask-registers,-prefer-movmsk-over-vtest,-prefer-no-gather,-prefer-no-scatter,-prefetchi,-prefetchwt1,-ptwrite,-push2pop2,-raoint,-retpoline,-retpoline-external-thunk,-retpoline-indirect-branches,-retpoline-indirect-calls,-rtm,-serialize,-seses,-sgx,-sha512,-slow-3ops-lea,-slow-incdec,-slow-lea,-slow-pmaddwd,-slow-pmulld,-slow-two-mem-ops,-slow-unaligned-mem-16,-slow-unaligned-mem-32,-sm3,-sm4,-soft-float,-sse-unaligned-mem,-tagged-globals,-tbm,-tsxldtrk,-tuning-fast-imm-vector-shift,-uintr,-use-glm-div-sqrt-costs,-use-slm-arith-costs,-usermsr,-waitpkg,-wbnoinvd,-widekl,-xop" "tune-cpu"="generic" }
attributes #1 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #2 = { nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #3 = { "frame-pointer"="all" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="znver3" "target-features"="+64bit,+adx,+aes,+allow-light-256-bit,+avx,+avx2,+bmi,+bmi2,+branchfusion,+clflushopt,+clwb,+clzero,+cmov,+crc32,+cx16,+cx8,+f16c,+fast-15bytenop,+fast-bextr,+fast-lzcnt,+fast-movbe,+fast-scalar-fsqrt,+fast-scalar-shift-masks,+fast-variable-perlane-shuffle,+fast-vector-fsqrt,+fma,+fsgsbase,+fsrm,+fxsr,+invpcid,+lzcnt,+macrofusion,+mmx,+movbe,+nopl,+pclmul,+popcnt,+prfchw,+rdpid,+rdpru,+rdrnd,+rdseed,+sahf,+sbb-dep-breaking,+sha,+shstk,+slow-shld,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+sse4a,+ssse3,+vaes,+vpclmulqdq,+vzeroupper,+x87,+xsave,+xsavec,+xsaveopt,+xsaves,-16bit-mode,-32bit-mode,-3dnow,-3dnowa,-amx-bf16,-amx-complex,-amx-fp16,-amx-int8,-amx-tile,-avx10.1-256,-avx10.1-512,-avx512bf16,-avx512bitalg,-avx512bw,-avx512cd,-avx512dq,-avx512er,-avx512f,-avx512fp16,-avx512ifma,-avx512pf,-avx512vbmi,-avx512vbmi2,-avx512vl,-avx512vnni,-avx512vp2intersect,-avx512vpopcntdq,-avxifma,-avxneconvert,-avxvnni,-avxvnniint16,-avxvnniint8,-ccmp,-cf,-cldemote,-cmpccxadd,-egpr,-enqcmd,-ermsb,-false-deps-getmant,-false-deps-lzcnt-tzcnt,-false-deps-mulc,-false-deps-mullq,-false-deps-perm,-false-deps-popcnt,-false-deps-range,-fast-11bytenop,-fast-7bytenop,-fast-gather,-fast-hops,-fast-shld-rotate,-fast-variable-crosslane-shuffle,-fast-vector-shift-masks,-faster-shift-than-shuffle,-fma4,-gfni,-harden-sls-ijmp,-harden-sls-ret,-hreset,-idivl-to-divb,-idivq-to-divl,-kl,-lea-sp,-lea-uses-ag,-lvi-cfi,-lvi-load-hardening,-lwp,-movdir64b,-movdiri,-mwaitx,-ndd,-no-bypass-delay,-no-bypass-delay-blend,-no-bypass-delay-mov,-no-bypass-delay-shuffle,-pad-short-functions,-pconfig,-pku,-ppx,-prefer-128-bit,-prefer-256-bit,-prefer-mask-registers,-prefer-movmsk-over-vtest,-prefer-no-gather,-prefer-no-scatter,-prefetchi,-prefetchwt1,-ptwrite,-push2pop2,-raoint,-retpoline,-retpoline-external-thunk,-retpoline-indirect-branches,-retpoline-indirect-calls,-rtm,-serialize,-seses,-sgx,-sha512,-slow-3ops-lea,-slow-incdec,-slow-lea,-slow-pmaddwd,-slow-pmulld,-slow-two-mem-ops,-slow-unaligned-mem-16,-slow-unaligned-mem-32,-sm3,-sm4,-soft-float,-sse-unaligned-mem,-tagged-globals,-tbm,-tsxldtrk,-tuning-fast-imm-vector-shift,-uintr,-use-glm-div-sqrt-costs,-use-slm-arith-costs,-usermsr,-waitpkg,-wbnoinvd,-widekl,-xop" "tune-cpu"="generic" }

!llvm.dbg.cu = !{!0}
!llvm.module.flags = !{!4, !5, !6, !7, !8, !9}
!llvm.ident = !{!10}

!0 = distinct !DICompileUnit(language: DW_LANG_C11, file: !1, producer: "clang version 18.1.6 (https://github.com/ziglang/zig-bootstrap 98bc6bf4fc4009888d33941daf6b600d20a42a56)", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !2, splitDebugInlining: false, nameTableKind: None)
!1 = !DIFile(filename: "examples/ffi_callback.c", directory: "/home/admin/cl")
!2 = !{!3}
!3 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!4 = !{i32 7, !"Dwarf Version", i32 4}
!5 = !{i32 2, !"Debug Info Version", i32 3}
!6 = !{i32 1, !"wchar_size", i32 4}
!7 = !{i32 8, !"PIC Level", i32 2}
!8 = !{i32 7, !"uwtable", i32 2}
!9 = !{i32 7, !"frame-pointer", i32 2}
!10 = !{!"clang version 18.1.6 (https://github.com/ziglang/zig-bootstrap 98bc6bf4fc4009888d33941daf6b600d20a42a56)"}
!11 = distinct !DISubprogram(name: "cb6", scope: !1, file: !1, line: 7, type: !12, scopeLine: 7, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !15)
!12 = !DISubroutineType(types: !13)
!13 = !{!14, !14, !14, !14, !14, !14, !14}
!14 = !DIBasicType(name: "long", size: 64, encoding: DW_ATE_signed)
!15 = !{}
!16 = !DILocalVariable(name: "a", arg: 1, scope: !11, file: !1, line: 7, type: !14)
!17 = !DILocation(line: 7, column: 15, scope: !11)
!18 = !DILocalVariable(name: "b", arg: 2, scope: !11, file: !1, line: 7, type: !14)
!19 = !DILocation(line: 7, column: 23, scope: !11)
!20 = !DILocalVariable(name: "c", arg: 3, scope: !11, file: !1, line: 7, type: !14)
!21 = !DILocation(line: 7, column: 31, scope: !11)
!22 = !DILocalVariable(name: "d", arg: 4, scope: !11, file: !1, line: 7, type: !14)
!23 = !DILocation(line: 7, column: 39, scope: !11)
!24 = !DILocalVariable(name: "e", arg: 5, scope: !11, file: !1, line: 7, type: !14)
!25 = !DILocation(line: 7, column: 47, scope: !11)
!26 = !DILocalVariable(name: "f", arg: 6, scope: !11, file: !1, line: 7, type: !14)
!27 = !DILocation(line: 7, column: 55, scope: !11)
!28 = !DILocation(line: 8, column: 12, scope: !11)
!29 = !DILocation(line: 8, column: 16, scope: !11)
!30 = !DILocation(line: 8, column: 14, scope: !11)
!31 = !DILocation(line: 8, column: 20, scope: !11)
!32 = !DILocation(line: 8, column: 18, scope: !11)
!33 = !DILocation(line: 8, column: 24, scope: !11)
!34 = !DILocation(line: 8, column: 22, scope: !11)
!35 = !DILocation(line: 8, column: 28, scope: !11)
!36 = !DILocation(line: 8, column: 26, scope: !11)
!37 = !DILocation(line: 8, column: 32, scope: !11)
!38 = !DILocation(line: 8, column: 30, scope: !11)
!39 = !DILocation(line: 8, column: 5, scope: !11)
!40 = distinct !DISubprogram(name: "cb_s8", scope: !1, file: !1, line: 11, type: !41, scopeLine: 11, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !15)
!41 = !DISubroutineType(types: !42)
!42 = !{!43, !43}
!43 = !DIDerivedType(tag: DW_TAG_typedef, name: "S8", file: !1, line: 1, baseType: !44)
!44 = distinct !DICompositeType(tag: DW_TAG_structure_type, file: !1, line: 1, size: 64, elements: !45)
!45 = !{!46, !47}
!46 = !DIDerivedType(tag: DW_TAG_member, name: "a", scope: !44, file: !1, line: 1, baseType: !3, size: 32)
!47 = !DIDerivedType(tag: DW_TAG_member, name: "b", scope: !44, file: !1, line: 1, baseType: !3, size: 32, offset: 32)
!48 = !DILocalVariable(name: "x", arg: 1, scope: !40, file: !1, line: 11, type: !43)
!49 = !DILocation(line: 11, column: 13, scope: !40)
!50 = !DILocalVariable(name: "y", scope: !40, file: !1, line: 12, type: !43)
!51 = !DILocation(line: 12, column: 8, scope: !40)
!52 = !DILocation(line: 12, column: 12, scope: !40)
!53 = !DILocation(line: 12, column: 16, scope: !40)
!54 = !DILocation(line: 12, column: 18, scope: !40)
!55 = !DILocation(line: 12, column: 25, scope: !40)
!56 = !DILocation(line: 12, column: 27, scope: !40)
!57 = !DILocation(line: 13, column: 5, scope: !40)
!58 = distinct !DISubprogram(name: "main", scope: !1, file: !1, line: 16, type: !59, scopeLine: 16, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !0, retainedNodes: !15)
!59 = !DISubroutineType(types: !2)
!60 = !DILocalVariable(name: "s", scope: !58, file: !1, line: 17, type: !43)
!61 = !DILocation(line: 17, column: 8, scope: !58)
!62 = !DILocalVariable(name: "r", scope: !58, file: !1, line: 18, type: !43)
!63 = !DILocation(line: 18, column: 8, scope: !58)
!64 = !DILocation(line: 18, column: 12, scope: !58)
!65 = !DILocation(line: 19, column: 18, scope: !58)
!66 = !DILocation(line: 19, column: 51, scope: !58)
!67 = !DILocation(line: 19, column: 60, scope: !58)
!68 = !DILocation(line: 19, column: 62, scope: !58)
!69 = !DILocation(line: 19, column: 58, scope: !58)
!70 = !DILocation(line: 19, column: 56, scope: !58)
!71 = !DILocation(line: 19, column: 71, scope: !58)
!72 = !DILocation(line: 19, column: 69, scope: !58)
!73 = !DILocation(line: 19, column: 67, scope: !58)
!74 = !DILocation(line: 19, column: 12, scope: !58)
!75 = !DILocation(line: 19, column: 5, scope: !58)
