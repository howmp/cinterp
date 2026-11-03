; ModuleID = 'fixture.c'
source_filename = "fixture.c"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

%struct.Nested = type { %struct.Point, [3 x i32], ptr }
%struct.Point = type { i32, i32 }
%struct.Big = type { i64, i64, i64 }

@.str = private unnamed_addr constant [3 x i8] c"hi\00", align 1, !dbg !0
@g_nested = global %struct.Nested { %struct.Point { i32 3, i32 4 }, [3 x i32] [i32 5, i32 6, i32 7], ptr @.str }, align 8, !dbg !7
@g_arr = global [4 x i32] [i32 10, i32 20, i32 30, i32 40], align 16, !dbg !13
@g_ld = global x86_fp80 0xK3FFFC000000000000000, align 16, !dbg !18
@g_f128 = global fp128 0xL00000000000000004000400000000000, align 16, !dbg !21
@g_reloc = global ptr getelementptr (i8, ptr @g_arr, i64 8), align 8, !dbg !24
@g_ext = external global i32, align 4

; Function Attrs: noinline nounwind optnone uwtable
define i32 @classify(i32 noundef %x) #0 !dbg !45 {
entry:
  %retval = alloca i32, align 4
  %x.addr = alloca i32, align 4
  store i32 %x, ptr %x.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %x.addr, metadata !49, metadata !DIExpression()), !dbg !50
  %0 = load i32, ptr %x.addr, align 4, !dbg !51
  switch i32 %0, label %sw.default [
    i32 0, label %sw.bb
    i32 -3, label %sw.bb1
  ], !dbg !52

sw.bb:                                            ; preds = %entry
  store i32 10, ptr %retval, align 4, !dbg !53
  br label %return, !dbg !53

sw.bb1:                                           ; preds = %entry
  store i32 40, ptr %retval, align 4, !dbg !55
  br label %return, !dbg !55

sw.default:                                       ; preds = %entry
  store i32 50, ptr %retval, align 4, !dbg !56
  br label %return, !dbg !56

return:                                           ; preds = %sw.default, %sw.bb1, %sw.bb
  %1 = load i32, ptr %retval, align 4, !dbg !57
  ret i32 %1, !dbg !57
}

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare void @llvm.dbg.declare(metadata, metadata, metadata) #1

; Function Attrs: noinline nounwind optnone uwtable
define i32 @take_big(ptr noundef byval(%struct.Big) align 8 %b) #0 !dbg !58 {
entry:
  call void @llvm.dbg.declare(metadata ptr %b, metadata !67, metadata !DIExpression()), !dbg !68
  %a = getelementptr inbounds %struct.Big, ptr %b, i32 0, i32 0, !dbg !69
  %0 = load i64, ptr %a, align 8, !dbg !69
  %b1 = getelementptr inbounds %struct.Big, ptr %b, i32 0, i32 1, !dbg !70
  %1 = load i64, ptr %b1, align 8, !dbg !70
  %add = add nsw i64 %0, %1, !dbg !71
  %c = getelementptr inbounds %struct.Big, ptr %b, i32 0, i32 2, !dbg !72
  %2 = load i64, ptr %c, align 8, !dbg !72
  %add2 = add nsw i64 %add, %2, !dbg !73
  %conv = trunc i64 %add2 to i32, !dbg !74
  ret i32 %conv, !dbg !75
}

; Function Attrs: noinline nounwind optnone uwtable
define x86_fp80 @ld_add(x86_fp80 noundef %a, x86_fp80 noundef %b) #0 !dbg !76 {
entry:
  %a.addr = alloca x86_fp80, align 16
  %b.addr = alloca x86_fp80, align 16
  store x86_fp80 %a, ptr %a.addr, align 16
  call void @llvm.dbg.declare(metadata ptr %a.addr, metadata !79, metadata !DIExpression()), !dbg !80
  store x86_fp80 %b, ptr %b.addr, align 16
  call void @llvm.dbg.declare(metadata ptr %b.addr, metadata !81, metadata !DIExpression()), !dbg !82
  %0 = load x86_fp80, ptr %a.addr, align 16, !dbg !83
  %1 = load x86_fp80, ptr %b.addr, align 16, !dbg !84
  %add = fadd x86_fp80 %0, %1, !dbg !85
  ret x86_fp80 %add, !dbg !86
}

; Function Attrs: noinline nounwind optnone uwtable
define i32 @use(i32 noundef %c) #0 !dbg !87 {
entry:
  %c.addr = alloca i32, align 4
  %s = alloca i32, align 4
  %i = alloca i32, align 4
  store i32 %c, ptr %c.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %c.addr, metadata !88, metadata !DIExpression()), !dbg !89
  call void @llvm.dbg.declare(metadata ptr %s, metadata !90, metadata !DIExpression()), !dbg !91
  store i32 0, ptr %s, align 4, !dbg !91
  call void @llvm.dbg.declare(metadata ptr %i, metadata !92, metadata !DIExpression()), !dbg !94
  store i32 0, ptr %i, align 4, !dbg !94
  br label %for.cond, !dbg !95

for.cond:                                         ; preds = %for.inc, %entry
  %0 = load i32, ptr %i, align 4, !dbg !96
  %1 = load i32, ptr %c.addr, align 4, !dbg !98
  %cmp = icmp slt i32 %0, %1, !dbg !99
  br i1 %cmp, label %for.body, label %for.end, !dbg !100

for.body:                                         ; preds = %for.cond
  %2 = load i32, ptr %i, align 4, !dbg !101
  %idxprom = sext i32 %2 to i64, !dbg !102
  %arrayidx = getelementptr inbounds [4 x i32], ptr @g_arr, i64 0, i64 %idxprom, !dbg !102
  %3 = load i32, ptr %arrayidx, align 4, !dbg !102
  %4 = load i32, ptr %i, align 4, !dbg !103
  %idxprom1 = sext i32 %4 to i64, !dbg !104
  %arrayidx2 = getelementptr inbounds [3 x i32], ptr getelementptr inbounds (%struct.Nested, ptr @g_nested, i32 0, i32 1), i64 0, i64 %idxprom1, !dbg !104
  %5 = load i32, ptr %arrayidx2, align 4, !dbg !104
  %add = add nsw i32 %3, %5, !dbg !105
  %6 = load i32, ptr %s, align 4, !dbg !106
  %add3 = add nsw i32 %6, %add, !dbg !106
  store i32 %add3, ptr %s, align 4, !dbg !106
  br label %for.inc, !dbg !107

for.inc:                                          ; preds = %for.body
  %7 = load i32, ptr %i, align 4, !dbg !108
  %inc = add nsw i32 %7, 1, !dbg !108
  store i32 %inc, ptr %i, align 4, !dbg !108
  br label %for.cond, !dbg !109, !llvm.loop !110

for.end:                                          ; preds = %for.cond
  %8 = load i32, ptr %s, align 4, !dbg !113
  %9 = load i32, ptr @g_ext, align 4, !dbg !114
  %add4 = add nsw i32 %8, %9, !dbg !115
  ret i32 %add4, !dbg !116
}

; Function Attrs: noinline nounwind optnone uwtable
define i32 @main(i32 noundef %argc, ptr noundef %argv) #0 !dbg !117 {
entry:
  %retval = alloca i32, align 4
  %argc.addr = alloca i32, align 4
  %argv.addr = alloca ptr, align 8
  %.compoundliteral = alloca %struct.Big, align 8
  store i32 0, ptr %retval, align 4
  store i32 %argc, ptr %argc.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %argc.addr, metadata !121, metadata !DIExpression()), !dbg !122
  store ptr %argv, ptr %argv.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %argv.addr, metadata !123, metadata !DIExpression()), !dbg !124
  %0 = load i32, ptr %argc.addr, align 4, !dbg !125
  %call = call i32 @use(i32 noundef %0), !dbg !126
  %1 = load i32, ptr %argc.addr, align 4, !dbg !127
  %call1 = call i32 @classify(i32 noundef %1), !dbg !128
  %add = add nsw i32 %call, %call1, !dbg !129
  %a = getelementptr inbounds %struct.Big, ptr %.compoundliteral, i32 0, i32 0, !dbg !130
  store i64 1, ptr %a, align 8, !dbg !130
  %b = getelementptr inbounds %struct.Big, ptr %.compoundliteral, i32 0, i32 1, !dbg !130
  store i64 2, ptr %b, align 8, !dbg !130
  %c = getelementptr inbounds %struct.Big, ptr %.compoundliteral, i32 0, i32 2, !dbg !130
  store i64 3, ptr %c, align 8, !dbg !130
  %call2 = call i32 @take_big(ptr noundef byval(%struct.Big) align 8 %.compoundliteral), !dbg !131
  %add3 = add nsw i32 %add, %call2, !dbg !132
  %2 = load x86_fp80, ptr @g_ld, align 16, !dbg !133
  %call4 = call x86_fp80 @ld_add(x86_fp80 noundef %2, x86_fp80 noundef 0xK3FFF8000000000000000), !dbg !134
  %conv = fptosi x86_fp80 %call4 to i32, !dbg !135
  %add5 = add nsw i32 %add3, %conv, !dbg !136
  %3 = load fp128, ptr @g_f128, align 16, !dbg !137
  %conv6 = fptosi fp128 %3 to i32, !dbg !138
  %add7 = add nsw i32 %add5, %conv6, !dbg !139
  %4 = load ptr, ptr @g_reloc, align 8, !dbg !140
  %5 = load i32, ptr %4, align 4, !dbg !141
  %add8 = add nsw i32 %add7, %5, !dbg !142
  ret i32 %add8, !dbg !143
}

attributes #0 = { noinline nounwind optnone uwtable "frame-pointer"="all" "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="znver3" "target-features"="+64bit,+adx,+aes,+allow-light-256-bit,+avx,+avx2,+bmi,+bmi2,+branchfusion,+clflushopt,+clwb,+clzero,+cmov,+crc32,+cx16,+cx8,+f16c,+fast-15bytenop,+fast-bextr,+fast-lzcnt,+fast-movbe,+fast-scalar-fsqrt,+fast-scalar-shift-masks,+fast-variable-perlane-shuffle,+fast-vector-fsqrt,+fma,+fsgsbase,+fsrm,+fxsr,+invpcid,+lzcnt,+macrofusion,+mmx,+movbe,+nopl,+pclmul,+popcnt,+prfchw,+rdpid,+rdpru,+rdrnd,+rdseed,+sahf,+sbb-dep-breaking,+sha,+shstk,+slow-shld,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+sse4a,+ssse3,+vaes,+vpclmulqdq,+vzeroupper,+x87,+xsave,+xsavec,+xsaveopt,+xsaves,-16bit-mode,-32bit-mode,-3dnow,-3dnowa,-amx-bf16,-amx-complex,-amx-fp16,-amx-int8,-amx-tile,-avx10.1-256,-avx10.1-512,-avx512bf16,-avx512bitalg,-avx512bw,-avx512cd,-avx512dq,-avx512er,-avx512f,-avx512fp16,-avx512ifma,-avx512pf,-avx512vbmi,-avx512vbmi2,-avx512vl,-avx512vnni,-avx512vp2intersect,-avx512vpopcntdq,-avxifma,-avxneconvert,-avxvnni,-avxvnniint16,-avxvnniint8,-ccmp,-cf,-cldemote,-cmpccxadd,-egpr,-enqcmd,-ermsb,-false-deps-getmant,-false-deps-lzcnt-tzcnt,-false-deps-mulc,-false-deps-mullq,-false-deps-perm,-false-deps-popcnt,-false-deps-range,-fast-11bytenop,-fast-7bytenop,-fast-gather,-fast-hops,-fast-shld-rotate,-fast-variable-crosslane-shuffle,-fast-vector-shift-masks,-faster-shift-than-shuffle,-fma4,-gfni,-harden-sls-ijmp,-harden-sls-ret,-hreset,-idivl-to-divb,-idivq-to-divl,-kl,-lea-sp,-lea-uses-ag,-lvi-cfi,-lvi-load-hardening,-lwp,-movdir64b,-movdiri,-mwaitx,-ndd,-no-bypass-delay,-no-bypass-delay-blend,-no-bypass-delay-mov,-no-bypass-delay-shuffle,-pad-short-functions,-pconfig,-pku,-ppx,-prefer-128-bit,-prefer-256-bit,-prefer-mask-registers,-prefer-movmsk-over-vtest,-prefer-no-gather,-prefer-no-scatter,-prefetchi,-prefetchwt1,-ptwrite,-push2pop2,-raoint,-retpoline,-retpoline-external-thunk,-retpoline-indirect-branches,-retpoline-indirect-calls,-rtm,-serialize,-seses,-sgx,-sha512,-slow-3ops-lea,-slow-incdec,-slow-lea,-slow-pmaddwd,-slow-pmulld,-slow-two-mem-ops,-slow-unaligned-mem-16,-slow-unaligned-mem-32,-sm3,-sm4,-soft-float,-sse-unaligned-mem,-tagged-globals,-tbm,-tsxldtrk,-tuning-fast-imm-vector-shift,-uintr,-use-glm-div-sqrt-costs,-use-slm-arith-costs,-usermsr,-waitpkg,-wbnoinvd,-widekl,-xop" "tune-cpu"="generic" }
attributes #1 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }

!llvm.dbg.cu = !{!9}
!llvm.module.flags = !{!38, !39, !40, !41, !42, !43}
!llvm.ident = !{!44}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(scope: null, file: !2, line: 6, type: !3, isLocal: true, isDefinition: true)
!2 = !DIFile(filename: "fixture.c", directory: "/tmp/commandcode-1000/-home-admin-cl/b69c5faa-fc81-4386-99ed-84755c744157/scratchpad/ir")
!3 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 24, elements: !5)
!4 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!5 = !{!6}
!6 = !DISubrange(count: 3)
!7 = !DIGlobalVariableExpression(var: !8, expr: !DIExpression())
!8 = distinct !DIGlobalVariable(name: "g_nested", scope: !9, file: !2, line: 6, type: !27, isLocal: false, isDefinition: true)
!9 = distinct !DICompileUnit(language: DW_LANG_C11, file: !2, producer: "clang version 18.1.6 (https://github.com/ziglang/zig-bootstrap 98bc6bf4fc4009888d33941daf6b600d20a42a56)", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !10, globals: !12, splitDebugInlining: false, nameTableKind: None)
!10 = !{!11}
!11 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!12 = !{!0, !7, !13, !18, !21, !24}
!13 = !DIGlobalVariableExpression(var: !14, expr: !DIExpression())
!14 = distinct !DIGlobalVariable(name: "g_arr", scope: !9, file: !2, line: 7, type: !15, isLocal: false, isDefinition: true)
!15 = !DICompositeType(tag: DW_TAG_array_type, baseType: !11, size: 128, elements: !16)
!16 = !{!17}
!17 = !DISubrange(count: 4)
!18 = !DIGlobalVariableExpression(var: !19, expr: !DIExpression())
!19 = distinct !DIGlobalVariable(name: "g_ld", scope: !9, file: !2, line: 8, type: !20, isLocal: false, isDefinition: true)
!20 = !DIBasicType(name: "long double", size: 128, encoding: DW_ATE_float)
!21 = !DIGlobalVariableExpression(var: !22, expr: !DIExpression())
!22 = distinct !DIGlobalVariable(name: "g_f128", scope: !9, file: !2, line: 9, type: !23, isLocal: false, isDefinition: true)
!23 = !DIBasicType(name: "__float128", size: 128, encoding: DW_ATE_float)
!24 = !DIGlobalVariableExpression(var: !25, expr: !DIExpression())
!25 = distinct !DIGlobalVariable(name: "g_reloc", scope: !9, file: !2, line: 10, type: !26, isLocal: false, isDefinition: true)
!26 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !11, size: 64)
!27 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "Nested", file: !2, line: 4, size: 256, elements: !28)
!28 = !{!29, !34, !36}
!29 = !DIDerivedType(tag: DW_TAG_member, name: "p", scope: !27, file: !2, line: 4, baseType: !30, size: 64)
!30 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "Point", file: !2, line: 1, size: 64, elements: !31)
!31 = !{!32, !33}
!32 = !DIDerivedType(tag: DW_TAG_member, name: "x", scope: !30, file: !2, line: 1, baseType: !11, size: 32)
!33 = !DIDerivedType(tag: DW_TAG_member, name: "y", scope: !30, file: !2, line: 1, baseType: !11, size: 32, offset: 32)
!34 = !DIDerivedType(tag: DW_TAG_member, name: "arr", scope: !27, file: !2, line: 4, baseType: !35, size: 96, offset: 64)
!35 = !DICompositeType(tag: DW_TAG_array_type, baseType: !11, size: 96, elements: !5)
!36 = !DIDerivedType(tag: DW_TAG_member, name: "name", scope: !27, file: !2, line: 4, baseType: !37, size: 64, offset: 192)
!37 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !4, size: 64)
!38 = !{i32 7, !"Dwarf Version", i32 4}
!39 = !{i32 2, !"Debug Info Version", i32 3}
!40 = !{i32 1, !"wchar_size", i32 4}
!41 = !{i32 8, !"PIC Level", i32 2}
!42 = !{i32 7, !"uwtable", i32 2}
!43 = !{i32 7, !"frame-pointer", i32 2}
!44 = !{!"clang version 18.1.6 (https://github.com/ziglang/zig-bootstrap 98bc6bf4fc4009888d33941daf6b600d20a42a56)"}
!45 = distinct !DISubprogram(name: "classify", scope: !2, file: !2, line: 13, type: !46, scopeLine: 13, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !9, retainedNodes: !48)
!46 = !DISubroutineType(types: !47)
!47 = !{!11, !11}
!48 = !{}
!49 = !DILocalVariable(name: "x", arg: 1, scope: !45, file: !2, line: 13, type: !11)
!50 = !DILocation(line: 13, column: 18, scope: !45)
!51 = !DILocation(line: 14, column: 13, scope: !45)
!52 = !DILocation(line: 14, column: 5, scope: !45)
!53 = !DILocation(line: 15, column: 17, scope: !54)
!54 = distinct !DILexicalBlock(scope: !45, file: !2, line: 14, column: 16)
!55 = !DILocation(line: 16, column: 18, scope: !54)
!56 = !DILocation(line: 17, column: 18, scope: !54)
!57 = !DILocation(line: 19, column: 1, scope: !45)
!58 = distinct !DISubprogram(name: "take_big", scope: !2, file: !2, line: 21, type: !59, scopeLine: 21, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !9, retainedNodes: !48)
!59 = !DISubroutineType(types: !60)
!60 = !{!11, !61}
!61 = distinct !DICompositeType(tag: DW_TAG_structure_type, name: "Big", file: !2, line: 2, size: 192, elements: !62)
!62 = !{!63, !65, !66}
!63 = !DIDerivedType(tag: DW_TAG_member, name: "a", scope: !61, file: !2, line: 2, baseType: !64, size: 64)
!64 = !DIBasicType(name: "long", size: 64, encoding: DW_ATE_signed)
!65 = !DIDerivedType(tag: DW_TAG_member, name: "b", scope: !61, file: !2, line: 2, baseType: !64, size: 64, offset: 64)
!66 = !DIDerivedType(tag: DW_TAG_member, name: "c", scope: !61, file: !2, line: 2, baseType: !64, size: 64, offset: 128)
!67 = !DILocalVariable(name: "b", arg: 1, scope: !58, file: !2, line: 21, type: !61)
!68 = !DILocation(line: 21, column: 25, scope: !58)
!69 = !DILocation(line: 21, column: 45, scope: !58)
!70 = !DILocation(line: 21, column: 51, scope: !58)
!71 = !DILocation(line: 21, column: 47, scope: !58)
!72 = !DILocation(line: 21, column: 57, scope: !58)
!73 = !DILocation(line: 21, column: 53, scope: !58)
!74 = !DILocation(line: 21, column: 37, scope: !58)
!75 = !DILocation(line: 21, column: 30, scope: !58)
!76 = distinct !DISubprogram(name: "ld_add", scope: !2, file: !2, line: 23, type: !77, scopeLine: 23, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !9, retainedNodes: !48)
!77 = !DISubroutineType(types: !78)
!78 = !{!20, !20, !20}
!79 = !DILocalVariable(name: "a", arg: 1, scope: !76, file: !2, line: 23, type: !20)
!80 = !DILocation(line: 23, column: 32, scope: !76)
!81 = !DILocalVariable(name: "b", arg: 2, scope: !76, file: !2, line: 23, type: !20)
!82 = !DILocation(line: 23, column: 47, scope: !76)
!83 = !DILocation(line: 23, column: 59, scope: !76)
!84 = !DILocation(line: 23, column: 63, scope: !76)
!85 = !DILocation(line: 23, column: 61, scope: !76)
!86 = !DILocation(line: 23, column: 52, scope: !76)
!87 = distinct !DISubprogram(name: "use", scope: !2, file: !2, line: 25, type: !46, scopeLine: 25, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !9, retainedNodes: !48)
!88 = !DILocalVariable(name: "c", arg: 1, scope: !87, file: !2, line: 25, type: !11)
!89 = !DILocation(line: 25, column: 13, scope: !87)
!90 = !DILocalVariable(name: "s", scope: !87, file: !2, line: 26, type: !11)
!91 = !DILocation(line: 26, column: 9, scope: !87)
!92 = !DILocalVariable(name: "i", scope: !93, file: !2, line: 27, type: !11)
!93 = distinct !DILexicalBlock(scope: !87, file: !2, line: 27, column: 5)
!94 = !DILocation(line: 27, column: 14, scope: !93)
!95 = !DILocation(line: 27, column: 10, scope: !93)
!96 = !DILocation(line: 27, column: 21, scope: !97)
!97 = distinct !DILexicalBlock(scope: !93, file: !2, line: 27, column: 5)
!98 = !DILocation(line: 27, column: 25, scope: !97)
!99 = !DILocation(line: 27, column: 23, scope: !97)
!100 = !DILocation(line: 27, column: 5, scope: !93)
!101 = !DILocation(line: 27, column: 44, scope: !97)
!102 = !DILocation(line: 27, column: 38, scope: !97)
!103 = !DILocation(line: 27, column: 62, scope: !97)
!104 = !DILocation(line: 27, column: 49, scope: !97)
!105 = !DILocation(line: 27, column: 47, scope: !97)
!106 = !DILocation(line: 27, column: 35, scope: !97)
!107 = !DILocation(line: 27, column: 33, scope: !97)
!108 = !DILocation(line: 27, column: 29, scope: !97)
!109 = !DILocation(line: 27, column: 5, scope: !97)
!110 = distinct !{!110, !100, !111, !112}
!111 = !DILocation(line: 27, column: 63, scope: !93)
!112 = !{!"llvm.loop.mustprogress"}
!113 = !DILocation(line: 28, column: 12, scope: !87)
!114 = !DILocation(line: 28, column: 16, scope: !87)
!115 = !DILocation(line: 28, column: 14, scope: !87)
!116 = !DILocation(line: 28, column: 5, scope: !87)
!117 = distinct !DISubprogram(name: "main", scope: !2, file: !2, line: 31, type: !118, scopeLine: 31, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !9, retainedNodes: !48)
!118 = !DISubroutineType(types: !119)
!119 = !{!11, !11, !120}
!120 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !37, size: 64)
!121 = !DILocalVariable(name: "argc", arg: 1, scope: !117, file: !2, line: 31, type: !11)
!122 = !DILocation(line: 31, column: 14, scope: !117)
!123 = !DILocalVariable(name: "argv", arg: 2, scope: !117, file: !2, line: 31, type: !120)
!124 = !DILocation(line: 31, column: 27, scope: !117)
!125 = !DILocation(line: 31, column: 46, scope: !117)
!126 = !DILocation(line: 31, column: 42, scope: !117)
!127 = !DILocation(line: 31, column: 63, scope: !117)
!128 = !DILocation(line: 31, column: 54, scope: !117)
!129 = !DILocation(line: 31, column: 52, scope: !117)
!130 = !DILocation(line: 31, column: 92, scope: !117)
!131 = !DILocation(line: 31, column: 71, scope: !117)
!132 = !DILocation(line: 31, column: 69, scope: !117)
!133 = !DILocation(line: 31, column: 117, scope: !117)
!134 = !DILocation(line: 31, column: 110, scope: !117)
!135 = !DILocation(line: 31, column: 105, scope: !117)
!136 = !DILocation(line: 31, column: 103, scope: !117)
!137 = !DILocation(line: 31, column: 136, scope: !117)
!138 = !DILocation(line: 31, column: 131, scope: !117)
!139 = !DILocation(line: 31, column: 129, scope: !117)
!140 = !DILocation(line: 31, column: 146, scope: !117)
!141 = !DILocation(line: 31, column: 145, scope: !117)
!142 = !DILocation(line: 31, column: 143, scope: !117)
!143 = !DILocation(line: 31, column: 35, scope: !117)
