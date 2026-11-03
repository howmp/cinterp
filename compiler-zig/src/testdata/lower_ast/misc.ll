; ModuleID = '/tmp/commandcode-1000/-home-admin-cl/b69c5faa-fc81-4386-99ed-84755c744157/scratchpad/misc.c'
source_filename = "/tmp/commandcode-1000/-home-admin-cl/b69c5faa-fc81-4386-99ed-84755c744157/scratchpad/misc.c"
target datalayout = "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128-f80:128-n8:16:32:64-S128"
target triple = "x86_64-unknown-linux-gnu"

@.str = private unnamed_addr constant [4 x i8] c"abc\00", align 1, !dbg !0

; Function Attrs: noinline nounwind optnone uwtable
define i64 @vla_sum(i32 noundef %n) #0 !dbg !25 {
entry:
  %n.addr = alloca i32, align 4
  %saved_stack = alloca ptr, align 8
  %__vla_expr0 = alloca i64, align 8
  %i = alloca i32, align 4
  %s = alloca i64, align 8
  %i1 = alloca i32, align 4
  store i32 %n, ptr %n.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %n.addr, metadata !29, metadata !DIExpression()), !dbg !30
  %0 = load i32, ptr %n.addr, align 4, !dbg !31
  %1 = zext i32 %0 to i64, !dbg !32
  %2 = call ptr @llvm.stacksave.p0(), !dbg !32
  store ptr %2, ptr %saved_stack, align 8, !dbg !32
  %vla = alloca i32, i64 %1, align 16, !dbg !32
  store i64 %1, ptr %__vla_expr0, align 8, !dbg !32
  call void @llvm.dbg.declare(metadata ptr %__vla_expr0, metadata !33, metadata !DIExpression()), !dbg !35
  call void @llvm.dbg.declare(metadata ptr %vla, metadata !36, metadata !DIExpression()), !dbg !40
  call void @llvm.dbg.declare(metadata ptr %i, metadata !41, metadata !DIExpression()), !dbg !43
  store i32 0, ptr %i, align 4, !dbg !43
  br label %for.cond, !dbg !44

for.cond:                                         ; preds = %for.inc, %entry
  %3 = load i32, ptr %i, align 4, !dbg !45
  %4 = load i32, ptr %n.addr, align 4, !dbg !47
  %cmp = icmp slt i32 %3, %4, !dbg !48
  br i1 %cmp, label %for.body, label %for.end, !dbg !49

for.body:                                         ; preds = %for.cond
  %5 = load i32, ptr %i, align 4, !dbg !50
  %mul = mul nsw i32 %5, 2, !dbg !51
  %6 = load i32, ptr %i, align 4, !dbg !52
  %idxprom = sext i32 %6 to i64, !dbg !53
  %arrayidx = getelementptr inbounds i32, ptr %vla, i64 %idxprom, !dbg !53
  store i32 %mul, ptr %arrayidx, align 4, !dbg !54
  br label %for.inc, !dbg !53

for.inc:                                          ; preds = %for.body
  %7 = load i32, ptr %i, align 4, !dbg !55
  %inc = add nsw i32 %7, 1, !dbg !55
  store i32 %inc, ptr %i, align 4, !dbg !55
  br label %for.cond, !dbg !56, !llvm.loop !57

for.end:                                          ; preds = %for.cond
  call void @llvm.dbg.declare(metadata ptr %s, metadata !60, metadata !DIExpression()), !dbg !61
  store i64 0, ptr %s, align 8, !dbg !61
  call void @llvm.dbg.declare(metadata ptr %i1, metadata !62, metadata !DIExpression()), !dbg !64
  store i32 0, ptr %i1, align 4, !dbg !64
  br label %for.cond2, !dbg !65

for.cond2:                                        ; preds = %for.inc7, %for.end
  %8 = load i32, ptr %i1, align 4, !dbg !66
  %9 = load i32, ptr %n.addr, align 4, !dbg !68
  %cmp3 = icmp slt i32 %8, %9, !dbg !69
  br i1 %cmp3, label %for.body4, label %for.end9, !dbg !70

for.body4:                                        ; preds = %for.cond2
  %10 = load i32, ptr %i1, align 4, !dbg !71
  %idxprom5 = sext i32 %10 to i64, !dbg !72
  %arrayidx6 = getelementptr inbounds i32, ptr %vla, i64 %idxprom5, !dbg !72
  %11 = load i32, ptr %arrayidx6, align 4, !dbg !72
  %conv = sext i32 %11 to i64, !dbg !72
  %12 = load i64, ptr %s, align 8, !dbg !73
  %add = add nsw i64 %12, %conv, !dbg !73
  store i64 %add, ptr %s, align 8, !dbg !73
  br label %for.inc7, !dbg !74

for.inc7:                                         ; preds = %for.body4
  %13 = load i32, ptr %i1, align 4, !dbg !75
  %inc8 = add nsw i32 %13, 1, !dbg !75
  store i32 %inc8, ptr %i1, align 4, !dbg !75
  br label %for.cond2, !dbg !76, !llvm.loop !77

for.end9:                                         ; preds = %for.cond2
  %14 = load i64, ptr %s, align 8, !dbg !79
  %15 = load ptr, ptr %saved_stack, align 8, !dbg !80
  call void @llvm.stackrestore.p0(ptr %15), !dbg !80
  ret i64 %14, !dbg !80
}

; Function Attrs: nocallback nofree nosync nounwind speculatable willreturn memory(none)
declare void @llvm.dbg.declare(metadata, metadata, metadata) #1

; Function Attrs: nocallback nofree nosync nounwind willreturn
declare ptr @llvm.stacksave.p0() #2

; Function Attrs: nocallback nofree nosync nounwind willreturn
declare void @llvm.stackrestore.p0(ptr) #2

; Function Attrs: noinline nounwind optnone uwtable
define i32 @pick(i32 noundef %which, i32 noundef %a, i32 noundef %b) #0 !dbg !81 {
entry:
  %which.addr = alloca i32, align 4
  %a.addr = alloca i32, align 4
  %b.addr = alloca i32, align 4
  %f = alloca ptr, align 8
  store i32 %which, ptr %which.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %which.addr, metadata !84, metadata !DIExpression()), !dbg !85
  store i32 %a, ptr %a.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %a.addr, metadata !86, metadata !DIExpression()), !dbg !87
  store i32 %b, ptr %b.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %b.addr, metadata !88, metadata !DIExpression()), !dbg !89
  call void @llvm.dbg.declare(metadata ptr %f, metadata !90, metadata !DIExpression()), !dbg !95
  %0 = load i32, ptr %which.addr, align 4, !dbg !96
  %tobool = icmp ne i32 %0, 0, !dbg !96
  %1 = zext i1 %tobool to i64, !dbg !96
  %cond = select i1 %tobool, ptr @add, ptr @sub, !dbg !96
  store ptr %cond, ptr %f, align 8, !dbg !95
  %2 = load ptr, ptr %f, align 8, !dbg !97
  %3 = load i32, ptr %a.addr, align 4, !dbg !98
  %4 = load i32, ptr %b.addr, align 4, !dbg !99
  %call = call i32 %2(i32 noundef %3, i32 noundef %4), !dbg !97
  ret i32 %call, !dbg !100
}

; Function Attrs: noinline nounwind optnone uwtable
define internal i32 @add(i32 noundef %a, i32 noundef %b) #0 !dbg !101 {
entry:
  %a.addr = alloca i32, align 4
  %b.addr = alloca i32, align 4
  store i32 %a, ptr %a.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %a.addr, metadata !102, metadata !DIExpression()), !dbg !103
  store i32 %b, ptr %b.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %b.addr, metadata !104, metadata !DIExpression()), !dbg !105
  %0 = load i32, ptr %a.addr, align 4, !dbg !106
  %1 = load i32, ptr %b.addr, align 4, !dbg !107
  %add = add nsw i32 %0, %1, !dbg !108
  ret i32 %add, !dbg !109
}

; Function Attrs: noinline nounwind optnone uwtable
define internal i32 @sub(i32 noundef %a, i32 noundef %b) #0 !dbg !110 {
entry:
  %a.addr = alloca i32, align 4
  %b.addr = alloca i32, align 4
  store i32 %a, ptr %a.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %a.addr, metadata !111, metadata !DIExpression()), !dbg !112
  store i32 %b, ptr %b.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %b.addr, metadata !113, metadata !DIExpression()), !dbg !114
  %0 = load i32, ptr %a.addr, align 4, !dbg !115
  %1 = load i32, ptr %b.addr, align 4, !dbg !116
  %sub = sub nsw i32 %0, %1, !dbg !117
  ret i32 %sub, !dbg !118
}

; Function Attrs: noinline nounwind optnone uwtable
define void @copy_pair(ptr noundef %dst, ptr noundef %src) #0 !dbg !119 {
entry:
  %dst.addr = alloca ptr, align 8
  %src.addr = alloca ptr, align 8
  store ptr %dst, ptr %dst.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %dst.addr, metadata !130, metadata !DIExpression()), !dbg !131
  store ptr %src, ptr %src.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %src.addr, metadata !132, metadata !DIExpression()), !dbg !133
  %0 = load ptr, ptr %dst.addr, align 8, !dbg !134
  %1 = load ptr, ptr %src.addr, align 8, !dbg !135
  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %0, ptr align 8 %1, i64 16, i1 false), !dbg !136
  ret void, !dbg !137
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: readwrite)
declare void @llvm.memcpy.p0.p0.i64(ptr noalias nocapture writeonly, ptr noalias nocapture readonly, i64, i1 immarg) #3

; Function Attrs: noinline nounwind optnone uwtable
define void @zero_buf(ptr noundef %p) #0 !dbg !138 {
entry:
  %p.addr = alloca ptr, align 8
  store ptr %p, ptr %p.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %p.addr, metadata !141, metadata !DIExpression()), !dbg !142
  %0 = load ptr, ptr %p.addr, align 8, !dbg !143
  call void @llvm.memset.p0.i64(ptr align 1 %0, i8 0, i64 32, i1 false), !dbg !144
  %1 = load ptr, ptr %p.addr, align 8, !dbg !145
  %add.ptr = getelementptr inbounds i8, ptr %1, i64 32, !dbg !146
  call void @llvm.memcpy.p0.p0.i64(ptr align 1 %add.ptr, ptr align 1 @.str, i64 4, i1 false), !dbg !147
  ret void, !dbg !148
}

; Function Attrs: nocallback nofree nounwind willreturn memory(argmem: write)
declare void @llvm.memset.p0.i64(ptr nocapture writeonly, i8, i64, i1 immarg) #4

; Function Attrs: noinline nounwind optnone uwtable
define float @fcasts(float noundef %x, double noundef %y) #0 !dbg !149 {
entry:
  %x.addr = alloca float, align 4
  %y.addr = alloca double, align 8
  store float %x, ptr %x.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %x.addr, metadata !152, metadata !DIExpression()), !dbg !153
  store double %y, ptr %y.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %y.addr, metadata !154, metadata !DIExpression()), !dbg !155
  %0 = load double, ptr %y.addr, align 8, !dbg !156
  %conv = fptrunc double %0 to float, !dbg !157
  %1 = load float, ptr %x.addr, align 4, !dbg !158
  %add = fadd float %conv, %1, !dbg !159
  ret float %add, !dbg !160
}

; Function Attrs: noinline nounwind optnone uwtable
define double @ucasts(i32 noundef %u) #0 !dbg !161 {
entry:
  %u.addr = alloca i32, align 4
  store i32 %u, ptr %u.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %u.addr, metadata !164, metadata !DIExpression()), !dbg !165
  %0 = load i32, ptr %u.addr, align 4, !dbg !166
  %conv = uitofp i32 %0 to double, !dbg !167
  ret double %conv, !dbg !168
}

; Function Attrs: noinline nounwind optnone uwtable
define double @fextend(float noundef %x) #0 !dbg !169 {
entry:
  %x.addr = alloca float, align 4
  store float %x, ptr %x.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %x.addr, metadata !172, metadata !DIExpression()), !dbg !173
  %0 = load float, ptr %x.addr, align 4, !dbg !174
  %conv = fpext float %0 to double, !dbg !174
  ret double %conv, !dbg !175
}

; Function Attrs: noinline nounwind optnone uwtable
define i32 @ftrunc(double noundef %d) #0 !dbg !176 {
entry:
  %d.addr = alloca double, align 8
  store double %d, ptr %d.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %d.addr, metadata !179, metadata !DIExpression()), !dbg !180
  %0 = load double, ptr %d.addr, align 8, !dbg !181
  %conv = fptoui double %0 to i32, !dbg !182
  ret i32 %conv, !dbg !183
}

; Function Attrs: noinline nounwind optnone uwtable
define i32 @deref(i64 noundef %p) #0 !dbg !184 {
entry:
  %p.addr = alloca i64, align 8
  store i64 %p, ptr %p.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %p.addr, metadata !187, metadata !DIExpression()), !dbg !188
  %0 = load i64, ptr %p.addr, align 8, !dbg !189
  %1 = inttoptr i64 %0 to ptr, !dbg !190
  %2 = load i32, ptr %1, align 4, !dbg !191
  ret i32 %2, !dbg !192
}

; Function Attrs: noinline nounwind optnone uwtable
define i32 @arith(i32 noundef %a, i32 noundef %b) #0 !dbg !193 {
entry:
  %a.addr = alloca i32, align 4
  %b.addr = alloca i32, align 4
  store i32 %a, ptr %a.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %a.addr, metadata !196, metadata !DIExpression()), !dbg !197
  store i32 %b, ptr %b.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %b.addr, metadata !198, metadata !DIExpression()), !dbg !199
  %0 = load i32, ptr %a.addr, align 4, !dbg !200
  %1 = load i32, ptr %b.addr, align 4, !dbg !201
  %div = udiv i32 %0, %1, !dbg !202
  %2 = load i32, ptr %a.addr, align 4, !dbg !203
  %3 = load i32, ptr %b.addr, align 4, !dbg !204
  %rem = urem i32 %2, %3, !dbg !205
  %add = add i32 %div, %rem, !dbg !206
  %4 = load i32, ptr %a.addr, align 4, !dbg !207
  %shr = lshr i32 %4, 2, !dbg !208
  %add1 = add i32 %add, %shr, !dbg !209
  %5 = load i32, ptr %a.addr, align 4, !dbg !210
  %or = or i32 %5, 1, !dbg !211
  %add2 = add i32 %add1, %or, !dbg !212
  %6 = load i32, ptr %a.addr, align 4, !dbg !213
  %and = and i32 %6, 3, !dbg !214
  %sub = sub i32 %add2, %and, !dbg !215
  %7 = load i32, ptr %a.addr, align 4, !dbg !216
  %xor = xor i32 %7, 5, !dbg !217
  %shl = shl i32 %xor, 1, !dbg !218
  %add3 = add i32 %sub, %shl, !dbg !219
  ret i32 %add3, !dbg !220
}

; Function Attrs: noinline nounwind optnone uwtable
define i32 @srem(i32 noundef %a, i32 noundef %b) #0 !dbg !221 {
entry:
  %a.addr = alloca i32, align 4
  %b.addr = alloca i32, align 4
  store i32 %a, ptr %a.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %a.addr, metadata !222, metadata !DIExpression()), !dbg !223
  store i32 %b, ptr %b.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %b.addr, metadata !224, metadata !DIExpression()), !dbg !225
  %0 = load i32, ptr %a.addr, align 4, !dbg !226
  %1 = load i32, ptr %b.addr, align 4, !dbg !227
  %rem = srem i32 %0, %1, !dbg !228
  ret i32 %rem, !dbg !229
}

; Function Attrs: noinline nounwind optnone uwtable
define i32 @icmps(i32 noundef %a, i32 noundef %b) #0 !dbg !230 {
entry:
  %a.addr = alloca i32, align 4
  %b.addr = alloca i32, align 4
  %r = alloca i32, align 4
  store i32 %a, ptr %a.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %a.addr, metadata !231, metadata !DIExpression()), !dbg !232
  store i32 %b, ptr %b.addr, align 4
  call void @llvm.dbg.declare(metadata ptr %b.addr, metadata !233, metadata !DIExpression()), !dbg !234
  call void @llvm.dbg.declare(metadata ptr %r, metadata !235, metadata !DIExpression()), !dbg !236
  store i32 0, ptr %r, align 4, !dbg !236
  %0 = load i32, ptr %a.addr, align 4, !dbg !237
  %1 = load i32, ptr %b.addr, align 4, !dbg !238
  %cmp = icmp eq i32 %0, %1, !dbg !239
  %conv = zext i1 %cmp to i32, !dbg !239
  %2 = load i32, ptr %r, align 4, !dbg !240
  %add = add nsw i32 %2, %conv, !dbg !240
  store i32 %add, ptr %r, align 4, !dbg !240
  %3 = load i32, ptr %a.addr, align 4, !dbg !241
  %4 = load i32, ptr %b.addr, align 4, !dbg !242
  %cmp1 = icmp ne i32 %3, %4, !dbg !243
  %conv2 = zext i1 %cmp1 to i32, !dbg !243
  %5 = load i32, ptr %r, align 4, !dbg !244
  %add3 = add nsw i32 %5, %conv2, !dbg !244
  store i32 %add3, ptr %r, align 4, !dbg !244
  %6 = load i32, ptr %a.addr, align 4, !dbg !245
  %7 = load i32, ptr %b.addr, align 4, !dbg !246
  %cmp4 = icmp slt i32 %6, %7, !dbg !247
  %conv5 = zext i1 %cmp4 to i32, !dbg !247
  %8 = load i32, ptr %r, align 4, !dbg !248
  %add6 = add nsw i32 %8, %conv5, !dbg !248
  store i32 %add6, ptr %r, align 4, !dbg !248
  %9 = load i32, ptr %a.addr, align 4, !dbg !249
  %10 = load i32, ptr %b.addr, align 4, !dbg !250
  %cmp7 = icmp ule i32 %9, %10, !dbg !251
  %conv8 = zext i1 %cmp7 to i32, !dbg !251
  %11 = load i32, ptr %r, align 4, !dbg !252
  %add9 = add nsw i32 %11, %conv8, !dbg !252
  store i32 %add9, ptr %r, align 4, !dbg !252
  %12 = load i32, ptr %a.addr, align 4, !dbg !253
  %13 = load i32, ptr %b.addr, align 4, !dbg !254
  %cmp10 = icmp sgt i32 %12, %13, !dbg !255
  %conv11 = zext i1 %cmp10 to i32, !dbg !255
  %14 = load i32, ptr %r, align 4, !dbg !256
  %add12 = add nsw i32 %14, %conv11, !dbg !256
  store i32 %add12, ptr %r, align 4, !dbg !256
  %15 = load i32, ptr %a.addr, align 4, !dbg !257
  %16 = load i32, ptr %b.addr, align 4, !dbg !258
  %cmp13 = icmp uge i32 %15, %16, !dbg !259
  %conv14 = zext i1 %cmp13 to i32, !dbg !259
  %17 = load i32, ptr %r, align 4, !dbg !260
  %add15 = add nsw i32 %17, %conv14, !dbg !260
  store i32 %add15, ptr %r, align 4, !dbg !260
  %18 = load i32, ptr %a.addr, align 4, !dbg !261
  %19 = load i32, ptr %b.addr, align 4, !dbg !262
  %cmp16 = icmp sge i32 %18, %19, !dbg !263
  %conv17 = zext i1 %cmp16 to i32, !dbg !263
  %20 = load i32, ptr %r, align 4, !dbg !264
  %add18 = add nsw i32 %20, %conv17, !dbg !264
  store i32 %add18, ptr %r, align 4, !dbg !264
  %21 = load i32, ptr %a.addr, align 4, !dbg !265
  %22 = load i32, ptr %b.addr, align 4, !dbg !266
  %cmp19 = icmp ult i32 %21, %22, !dbg !267
  %conv20 = zext i1 %cmp19 to i32, !dbg !267
  %23 = load i32, ptr %r, align 4, !dbg !268
  %add21 = add nsw i32 %23, %conv20, !dbg !268
  store i32 %add21, ptr %r, align 4, !dbg !268
  %24 = load i32, ptr %r, align 4, !dbg !269
  ret i32 %24, !dbg !270
}

; Function Attrs: noinline nounwind optnone uwtable
define i32 @fcmps(double noundef %a, double noundef %b) #0 !dbg !271 {
entry:
  %a.addr = alloca double, align 8
  %b.addr = alloca double, align 8
  store double %a, ptr %a.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %a.addr, metadata !274, metadata !DIExpression()), !dbg !275
  store double %b, ptr %b.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %b.addr, metadata !276, metadata !DIExpression()), !dbg !277
  %0 = load double, ptr %a.addr, align 8, !dbg !278
  %1 = load double, ptr %b.addr, align 8, !dbg !279
  %cmp = fcmp oeq double %0, %1, !dbg !280
  %conv = zext i1 %cmp to i32, !dbg !280
  %2 = load double, ptr %a.addr, align 8, !dbg !281
  %3 = load double, ptr %b.addr, align 8, !dbg !282
  %cmp1 = fcmp olt double %2, %3, !dbg !283
  %conv2 = zext i1 %cmp1 to i32, !dbg !283
  %mul = mul nsw i32 %conv2, 2, !dbg !284
  %add = add nsw i32 %conv, %mul, !dbg !285
  %4 = load double, ptr %a.addr, align 8, !dbg !286
  %5 = load double, ptr %b.addr, align 8, !dbg !287
  %cmp3 = fcmp ogt double %4, %5, !dbg !288
  %conv4 = zext i1 %cmp3 to i32, !dbg !288
  %mul5 = mul nsw i32 %conv4, 4, !dbg !289
  %add6 = add nsw i32 %add, %mul5, !dbg !290
  %6 = load double, ptr %a.addr, align 8, !dbg !291
  %7 = load double, ptr %a.addr, align 8, !dbg !292
  %cmp7 = fcmp une double %6, %7, !dbg !293
  %conv8 = zext i1 %cmp7 to i32, !dbg !293
  %mul9 = mul nsw i32 %conv8, 8, !dbg !294
  %add10 = add nsw i32 %add6, %mul9, !dbg !295
  ret i32 %add10, !dbg !296
}

; Function Attrs: noinline nounwind optnone uwtable
define double @negate(double noundef %x) #0 !dbg !297 {
entry:
  %x.addr = alloca double, align 8
  store double %x, ptr %x.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %x.addr, metadata !300, metadata !DIExpression()), !dbg !301
  %0 = load double, ptr %x.addr, align 8, !dbg !302
  %fneg = fneg double %0, !dbg !303
  ret double %fneg, !dbg !304
}

; Function Attrs: noinline nounwind optnone uwtable
define i64 @ptr_roundtrip(ptr noundef %p) #0 !dbg !305 {
entry:
  %p.addr = alloca ptr, align 8
  store ptr %p, ptr %p.addr, align 8
  call void @llvm.dbg.declare(metadata ptr %p.addr, metadata !309, metadata !DIExpression()), !dbg !310
  %0 = load ptr, ptr %p.addr, align 8, !dbg !311
  %1 = ptrtoint ptr %0 to i64, !dbg !312
  ret i64 %1, !dbg !313
}

; Function Attrs: noinline nounwind optnone uwtable
define i32 @main() #0 !dbg !314 {
entry:
  %retval = alloca i32, align 4
  store i32 0, ptr %retval, align 4
  %call = call i32 @icmps(i32 noundef 1, i32 noundef 2), !dbg !317
  %call1 = call i32 @fcmps(double noundef 1.000000e+00, double noundef 2.000000e+00), !dbg !318
  %add = add nsw i32 %call, %call1, !dbg !319
  ret i32 %add, !dbg !320
}

attributes #0 = { noinline nounwind optnone uwtable "frame-pointer"="all" "min-legal-vector-width"="0" "no-trapping-math"="true" "stack-protector-buffer-size"="8" "target-cpu"="znver3" "target-features"="+64bit,+adx,+aes,+allow-light-256-bit,+avx,+avx2,+bmi,+bmi2,+branchfusion,+clflushopt,+clwb,+clzero,+cmov,+crc32,+cx16,+cx8,+f16c,+fast-15bytenop,+fast-bextr,+fast-lzcnt,+fast-movbe,+fast-scalar-fsqrt,+fast-scalar-shift-masks,+fast-variable-perlane-shuffle,+fast-vector-fsqrt,+fma,+fsgsbase,+fsrm,+fxsr,+invpcid,+lzcnt,+macrofusion,+mmx,+movbe,+nopl,+pclmul,+popcnt,+prfchw,+rdpid,+rdpru,+rdrnd,+rdseed,+sahf,+sbb-dep-breaking,+sha,+shstk,+slow-shld,+sse,+sse2,+sse3,+sse4.1,+sse4.2,+sse4a,+ssse3,+vaes,+vpclmulqdq,+vzeroupper,+x87,+xsave,+xsavec,+xsaveopt,+xsaves,-16bit-mode,-32bit-mode,-3dnow,-3dnowa,-amx-bf16,-amx-complex,-amx-fp16,-amx-int8,-amx-tile,-avx10.1-256,-avx10.1-512,-avx512bf16,-avx512bitalg,-avx512bw,-avx512cd,-avx512dq,-avx512er,-avx512f,-avx512fp16,-avx512ifma,-avx512pf,-avx512vbmi,-avx512vbmi2,-avx512vl,-avx512vnni,-avx512vp2intersect,-avx512vpopcntdq,-avxifma,-avxneconvert,-avxvnni,-avxvnniint16,-avxvnniint8,-ccmp,-cf,-cldemote,-cmpccxadd,-egpr,-enqcmd,-ermsb,-false-deps-getmant,-false-deps-lzcnt-tzcnt,-false-deps-mulc,-false-deps-mullq,-false-deps-perm,-false-deps-popcnt,-false-deps-range,-fast-11bytenop,-fast-7bytenop,-fast-gather,-fast-hops,-fast-shld-rotate,-fast-variable-crosslane-shuffle,-fast-vector-shift-masks,-faster-shift-than-shuffle,-fma4,-gfni,-harden-sls-ijmp,-harden-sls-ret,-hreset,-idivl-to-divb,-idivq-to-divl,-kl,-lea-sp,-lea-uses-ag,-lvi-cfi,-lvi-load-hardening,-lwp,-movdir64b,-movdiri,-mwaitx,-ndd,-no-bypass-delay,-no-bypass-delay-blend,-no-bypass-delay-mov,-no-bypass-delay-shuffle,-pad-short-functions,-pconfig,-pku,-ppx,-prefer-128-bit,-prefer-256-bit,-prefer-mask-registers,-prefer-movmsk-over-vtest,-prefer-no-gather,-prefer-no-scatter,-prefetchi,-prefetchwt1,-ptwrite,-push2pop2,-raoint,-retpoline,-retpoline-external-thunk,-retpoline-indirect-branches,-retpoline-indirect-calls,-rtm,-serialize,-seses,-sgx,-sha512,-slow-3ops-lea,-slow-incdec,-slow-lea,-slow-pmaddwd,-slow-pmulld,-slow-two-mem-ops,-slow-unaligned-mem-16,-slow-unaligned-mem-32,-sm3,-sm4,-soft-float,-sse-unaligned-mem,-tagged-globals,-tbm,-tsxldtrk,-tuning-fast-imm-vector-shift,-uintr,-use-glm-div-sqrt-costs,-use-slm-arith-costs,-usermsr,-waitpkg,-wbnoinvd,-widekl,-xop" "tune-cpu"="generic" }
attributes #1 = { nocallback nofree nosync nounwind speculatable willreturn memory(none) }
attributes #2 = { nocallback nofree nosync nounwind willreturn }
attributes #3 = { nocallback nofree nounwind willreturn memory(argmem: readwrite) }
attributes #4 = { nocallback nofree nounwind willreturn memory(argmem: write) }

!llvm.dbg.cu = !{!7}
!llvm.module.flags = !{!18, !19, !20, !21, !22, !23}
!llvm.ident = !{!24}

!0 = !DIGlobalVariableExpression(var: !1, expr: !DIExpression())
!1 = distinct !DIGlobalVariable(scope: null, file: !2, line: 29, type: !3, isLocal: true, isDefinition: true)
!2 = !DIFile(filename: "/tmp/commandcode-1000/-home-admin-cl/b69c5faa-fc81-4386-99ed-84755c744157/scratchpad/misc.c", directory: "")
!3 = !DICompositeType(tag: DW_TAG_array_type, baseType: !4, size: 32, elements: !5)
!4 = !DIBasicType(name: "char", size: 8, encoding: DW_ATE_signed_char)
!5 = !{!6}
!6 = !DISubrange(count: 4)
!7 = distinct !DICompileUnit(language: DW_LANG_C11, file: !8, producer: "clang version 18.1.6 (https://github.com/ziglang/zig-bootstrap 98bc6bf4fc4009888d33941daf6b600d20a42a56)", isOptimized: false, runtimeVersion: 0, emissionKind: FullDebug, retainedTypes: !9, globals: !17, splitDebugInlining: false, nameTableKind: None)
!8 = !DIFile(filename: "/tmp/commandcode-1000/-home-admin-cl/b69c5faa-fc81-4386-99ed-84755c744157/scratchpad/misc.c", directory: "/home/admin/cl")
!9 = !{!10, !11, !12, !13, !15, !16}
!10 = !DIBasicType(name: "float", size: 32, encoding: DW_ATE_float)
!11 = !DIBasicType(name: "double", size: 64, encoding: DW_ATE_float)
!12 = !DIBasicType(name: "unsigned int", size: 32, encoding: DW_ATE_unsigned)
!13 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !14, size: 64)
!14 = !DIBasicType(name: "int", size: 32, encoding: DW_ATE_signed)
!15 = !DIBasicType(name: "long", size: 64, encoding: DW_ATE_signed)
!16 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !4, size: 64)
!17 = !{!0}
!18 = !{i32 7, !"Dwarf Version", i32 4}
!19 = !{i32 2, !"Debug Info Version", i32 3}
!20 = !{i32 1, !"wchar_size", i32 4}
!21 = !{i32 8, !"PIC Level", i32 2}
!22 = !{i32 7, !"uwtable", i32 2}
!23 = !{i32 7, !"frame-pointer", i32 2}
!24 = !{!"clang version 18.1.6 (https://github.com/ziglang/zig-bootstrap 98bc6bf4fc4009888d33941daf6b600d20a42a56)"}
!25 = distinct !DISubprogram(name: "vla_sum", scope: !2, file: !2, line: 12, type: !26, scopeLine: 12, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!26 = !DISubroutineType(types: !27)
!27 = !{!15, !14}
!28 = !{}
!29 = !DILocalVariable(name: "n", arg: 1, scope: !25, file: !2, line: 12, type: !14)
!30 = !DILocation(line: 12, column: 18, scope: !25)
!31 = !DILocation(line: 13, column: 13, scope: !25)
!32 = !DILocation(line: 13, column: 5, scope: !25)
!33 = !DILocalVariable(name: "__vla_expr0", scope: !25, type: !34, flags: DIFlagArtificial)
!34 = !DIBasicType(name: "unsigned long", size: 64, encoding: DW_ATE_unsigned)
!35 = !DILocation(line: 0, scope: !25)
!36 = !DILocalVariable(name: "buf", scope: !25, file: !2, line: 13, type: !37)
!37 = !DICompositeType(tag: DW_TAG_array_type, baseType: !14, elements: !38)
!38 = !{!39}
!39 = !DISubrange(count: !33)
!40 = !DILocation(line: 13, column: 9, scope: !25)
!41 = !DILocalVariable(name: "i", scope: !42, file: !2, line: 14, type: !14)
!42 = distinct !DILexicalBlock(scope: !25, file: !2, line: 14, column: 5)
!43 = !DILocation(line: 14, column: 14, scope: !42)
!44 = !DILocation(line: 14, column: 10, scope: !42)
!45 = !DILocation(line: 14, column: 21, scope: !46)
!46 = distinct !DILexicalBlock(scope: !42, file: !2, line: 14, column: 5)
!47 = !DILocation(line: 14, column: 25, scope: !46)
!48 = !DILocation(line: 14, column: 23, scope: !46)
!49 = !DILocation(line: 14, column: 5, scope: !42)
!50 = !DILocation(line: 14, column: 42, scope: !46)
!51 = !DILocation(line: 14, column: 44, scope: !46)
!52 = !DILocation(line: 14, column: 37, scope: !46)
!53 = !DILocation(line: 14, column: 33, scope: !46)
!54 = !DILocation(line: 14, column: 40, scope: !46)
!55 = !DILocation(line: 14, column: 29, scope: !46)
!56 = !DILocation(line: 14, column: 5, scope: !46)
!57 = distinct !{!57, !49, !58, !59}
!58 = !DILocation(line: 14, column: 46, scope: !42)
!59 = !{!"llvm.loop.mustprogress"}
!60 = !DILocalVariable(name: "s", scope: !25, file: !2, line: 15, type: !15)
!61 = !DILocation(line: 15, column: 10, scope: !25)
!62 = !DILocalVariable(name: "i", scope: !63, file: !2, line: 16, type: !14)
!63 = distinct !DILexicalBlock(scope: !25, file: !2, line: 16, column: 5)
!64 = !DILocation(line: 16, column: 14, scope: !63)
!65 = !DILocation(line: 16, column: 10, scope: !63)
!66 = !DILocation(line: 16, column: 21, scope: !67)
!67 = distinct !DILexicalBlock(scope: !63, file: !2, line: 16, column: 5)
!68 = !DILocation(line: 16, column: 25, scope: !67)
!69 = !DILocation(line: 16, column: 23, scope: !67)
!70 = !DILocation(line: 16, column: 5, scope: !63)
!71 = !DILocation(line: 16, column: 42, scope: !67)
!72 = !DILocation(line: 16, column: 38, scope: !67)
!73 = !DILocation(line: 16, column: 35, scope: !67)
!74 = !DILocation(line: 16, column: 33, scope: !67)
!75 = !DILocation(line: 16, column: 29, scope: !67)
!76 = !DILocation(line: 16, column: 5, scope: !67)
!77 = distinct !{!77, !70, !78, !59}
!78 = !DILocation(line: 16, column: 43, scope: !63)
!79 = !DILocation(line: 17, column: 12, scope: !25)
!80 = !DILocation(line: 18, column: 1, scope: !25)
!81 = distinct !DISubprogram(name: "pick", scope: !2, file: !2, line: 20, type: !82, scopeLine: 20, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!82 = !DISubroutineType(types: !83)
!83 = !{!14, !14, !14, !14}
!84 = !DILocalVariable(name: "which", arg: 1, scope: !81, file: !2, line: 20, type: !14)
!85 = !DILocation(line: 20, column: 14, scope: !81)
!86 = !DILocalVariable(name: "a", arg: 2, scope: !81, file: !2, line: 20, type: !14)
!87 = !DILocation(line: 20, column: 25, scope: !81)
!88 = !DILocalVariable(name: "b", arg: 3, scope: !81, file: !2, line: 20, type: !14)
!89 = !DILocation(line: 20, column: 32, scope: !81)
!90 = !DILocalVariable(name: "f", scope: !81, file: !2, line: 21, type: !91)
!91 = !DIDerivedType(tag: DW_TAG_typedef, name: "binop", file: !2, line: 7, baseType: !92)
!92 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !93, size: 64)
!93 = !DISubroutineType(types: !94)
!94 = !{!14, !14, !14}
!95 = !DILocation(line: 21, column: 11, scope: !81)
!96 = !DILocation(line: 21, column: 15, scope: !81)
!97 = !DILocation(line: 22, column: 12, scope: !81)
!98 = !DILocation(line: 22, column: 14, scope: !81)
!99 = !DILocation(line: 22, column: 17, scope: !81)
!100 = !DILocation(line: 22, column: 5, scope: !81)
!101 = distinct !DISubprogram(name: "add", scope: !2, file: !2, line: 9, type: !93, scopeLine: 9, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !7, retainedNodes: !28)
!102 = !DILocalVariable(name: "a", arg: 1, scope: !101, file: !2, line: 9, type: !14)
!103 = !DILocation(line: 9, column: 20, scope: !101)
!104 = !DILocalVariable(name: "b", arg: 2, scope: !101, file: !2, line: 9, type: !14)
!105 = !DILocation(line: 9, column: 27, scope: !101)
!106 = !DILocation(line: 9, column: 39, scope: !101)
!107 = !DILocation(line: 9, column: 43, scope: !101)
!108 = !DILocation(line: 9, column: 41, scope: !101)
!109 = !DILocation(line: 9, column: 32, scope: !101)
!110 = distinct !DISubprogram(name: "sub", scope: !2, file: !2, line: 10, type: !93, scopeLine: 10, flags: DIFlagPrototyped, spFlags: DISPFlagLocalToUnit | DISPFlagDefinition, unit: !7, retainedNodes: !28)
!111 = !DILocalVariable(name: "a", arg: 1, scope: !110, file: !2, line: 10, type: !14)
!112 = !DILocation(line: 10, column: 20, scope: !110)
!113 = !DILocalVariable(name: "b", arg: 2, scope: !110, file: !2, line: 10, type: !14)
!114 = !DILocation(line: 10, column: 27, scope: !110)
!115 = !DILocation(line: 10, column: 39, scope: !110)
!116 = !DILocation(line: 10, column: 43, scope: !110)
!117 = !DILocation(line: 10, column: 41, scope: !110)
!118 = !DILocation(line: 10, column: 32, scope: !110)
!119 = distinct !DISubprogram(name: "copy_pair", scope: !2, file: !2, line: 25, type: !120, scopeLine: 25, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!120 = !DISubroutineType(types: !121)
!121 = !{null, !122, !128}
!122 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !123, size: 64)
!123 = !DIDerivedType(tag: DW_TAG_typedef, name: "Pair", file: !2, line: 5, baseType: !124)
!124 = distinct !DICompositeType(tag: DW_TAG_structure_type, file: !2, line: 3, size: 128, elements: !125)
!125 = !{!126, !127}
!126 = !DIDerivedType(tag: DW_TAG_member, name: "a", scope: !124, file: !2, line: 4, baseType: !15, size: 64)
!127 = !DIDerivedType(tag: DW_TAG_member, name: "b", scope: !124, file: !2, line: 4, baseType: !15, size: 64, offset: 64)
!128 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: !129, size: 64)
!129 = !DIDerivedType(tag: DW_TAG_const_type, baseType: !123)
!130 = !DILocalVariable(name: "dst", arg: 1, scope: !119, file: !2, line: 25, type: !122)
!131 = !DILocation(line: 25, column: 22, scope: !119)
!132 = !DILocalVariable(name: "src", arg: 2, scope: !119, file: !2, line: 25, type: !128)
!133 = !DILocation(line: 25, column: 39, scope: !119)
!134 = !DILocation(line: 25, column: 47, scope: !119)
!135 = !DILocation(line: 25, column: 54, scope: !119)
!136 = !DILocation(line: 25, column: 53, scope: !119)
!137 = !DILocation(line: 25, column: 59, scope: !119)
!138 = distinct !DISubprogram(name: "zero_buf", scope: !2, file: !2, line: 27, type: !139, scopeLine: 27, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!139 = !DISubroutineType(types: !140)
!140 = !{null, !16}
!141 = !DILocalVariable(name: "p", arg: 1, scope: !138, file: !2, line: 27, type: !16)
!142 = !DILocation(line: 27, column: 21, scope: !138)
!143 = !DILocation(line: 28, column: 12, scope: !138)
!144 = !DILocation(line: 28, column: 5, scope: !138)
!145 = !DILocation(line: 29, column: 12, scope: !138)
!146 = !DILocation(line: 29, column: 14, scope: !138)
!147 = !DILocation(line: 29, column: 5, scope: !138)
!148 = !DILocation(line: 30, column: 1, scope: !138)
!149 = distinct !DISubprogram(name: "fcasts", scope: !2, file: !2, line: 32, type: !150, scopeLine: 32, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!150 = !DISubroutineType(types: !151)
!151 = !{!10, !10, !11}
!152 = !DILocalVariable(name: "x", arg: 1, scope: !149, file: !2, line: 32, type: !10)
!153 = !DILocation(line: 32, column: 20, scope: !149)
!154 = !DILocalVariable(name: "y", arg: 2, scope: !149, file: !2, line: 32, type: !11)
!155 = !DILocation(line: 32, column: 30, scope: !149)
!156 = !DILocation(line: 32, column: 49, scope: !149)
!157 = !DILocation(line: 32, column: 42, scope: !149)
!158 = !DILocation(line: 32, column: 53, scope: !149)
!159 = !DILocation(line: 32, column: 51, scope: !149)
!160 = !DILocation(line: 32, column: 35, scope: !149)
!161 = distinct !DISubprogram(name: "ucasts", scope: !2, file: !2, line: 33, type: !162, scopeLine: 33, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!162 = !DISubroutineType(types: !163)
!163 = !{!11, !12}
!164 = !DILocalVariable(name: "u", arg: 1, scope: !161, file: !2, line: 33, type: !12)
!165 = !DILocation(line: 33, column: 28, scope: !161)
!166 = !DILocation(line: 33, column: 48, scope: !161)
!167 = !DILocation(line: 33, column: 40, scope: !161)
!168 = !DILocation(line: 33, column: 33, scope: !161)
!169 = distinct !DISubprogram(name: "fextend", scope: !2, file: !2, line: 35, type: !170, scopeLine: 35, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!170 = !DISubroutineType(types: !171)
!171 = !{!11, !10}
!172 = !DILocalVariable(name: "x", arg: 1, scope: !169, file: !2, line: 35, type: !10)
!173 = !DILocation(line: 35, column: 22, scope: !169)
!174 = !DILocation(line: 35, column: 34, scope: !169)
!175 = !DILocation(line: 35, column: 27, scope: !169)
!176 = distinct !DISubprogram(name: "ftrunc", scope: !2, file: !2, line: 36, type: !177, scopeLine: 36, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!177 = !DISubroutineType(types: !178)
!178 = !{!12, !11}
!179 = !DILocalVariable(name: "d", arg: 1, scope: !176, file: !2, line: 36, type: !11)
!180 = !DILocation(line: 36, column: 24, scope: !176)
!181 = !DILocation(line: 36, column: 46, scope: !176)
!182 = !DILocation(line: 36, column: 36, scope: !176)
!183 = !DILocation(line: 36, column: 29, scope: !176)
!184 = distinct !DISubprogram(name: "deref", scope: !2, file: !2, line: 38, type: !185, scopeLine: 38, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!185 = !DISubroutineType(types: !186)
!186 = !{!14, !15}
!187 = !DILocalVariable(name: "p", arg: 1, scope: !184, file: !2, line: 38, type: !15)
!188 = !DILocation(line: 38, column: 16, scope: !184)
!189 = !DILocation(line: 38, column: 36, scope: !184)
!190 = !DILocation(line: 38, column: 29, scope: !184)
!191 = !DILocation(line: 38, column: 28, scope: !184)
!192 = !DILocation(line: 38, column: 21, scope: !184)
!193 = distinct !DISubprogram(name: "arith", scope: !2, file: !2, line: 40, type: !194, scopeLine: 40, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!194 = !DISubroutineType(types: !195)
!195 = !{!12, !12, !12}
!196 = !DILocalVariable(name: "a", arg: 1, scope: !193, file: !2, line: 40, type: !12)
!197 = !DILocation(line: 40, column: 25, scope: !193)
!198 = !DILocalVariable(name: "b", arg: 2, scope: !193, file: !2, line: 40, type: !12)
!199 = !DILocation(line: 40, column: 37, scope: !193)
!200 = !DILocation(line: 41, column: 12, scope: !193)
!201 = !DILocation(line: 41, column: 16, scope: !193)
!202 = !DILocation(line: 41, column: 14, scope: !193)
!203 = !DILocation(line: 41, column: 20, scope: !193)
!204 = !DILocation(line: 41, column: 24, scope: !193)
!205 = !DILocation(line: 41, column: 22, scope: !193)
!206 = !DILocation(line: 41, column: 18, scope: !193)
!207 = !DILocation(line: 41, column: 29, scope: !193)
!208 = !DILocation(line: 41, column: 31, scope: !193)
!209 = !DILocation(line: 41, column: 26, scope: !193)
!210 = !DILocation(line: 41, column: 40, scope: !193)
!211 = !DILocation(line: 41, column: 42, scope: !193)
!212 = !DILocation(line: 41, column: 37, scope: !193)
!213 = !DILocation(line: 41, column: 50, scope: !193)
!214 = !DILocation(line: 41, column: 52, scope: !193)
!215 = !DILocation(line: 41, column: 47, scope: !193)
!216 = !DILocation(line: 41, column: 61, scope: !193)
!217 = !DILocation(line: 41, column: 63, scope: !193)
!218 = !DILocation(line: 41, column: 68, scope: !193)
!219 = !DILocation(line: 41, column: 57, scope: !193)
!220 = !DILocation(line: 41, column: 5, scope: !193)
!221 = distinct !DISubprogram(name: "srem", scope: !2, file: !2, line: 44, type: !93, scopeLine: 44, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!222 = !DILocalVariable(name: "a", arg: 1, scope: !221, file: !2, line: 44, type: !14)
!223 = !DILocation(line: 44, column: 14, scope: !221)
!224 = !DILocalVariable(name: "b", arg: 2, scope: !221, file: !2, line: 44, type: !14)
!225 = !DILocation(line: 44, column: 21, scope: !221)
!226 = !DILocation(line: 44, column: 33, scope: !221)
!227 = !DILocation(line: 44, column: 37, scope: !221)
!228 = !DILocation(line: 44, column: 35, scope: !221)
!229 = !DILocation(line: 44, column: 26, scope: !221)
!230 = distinct !DISubprogram(name: "icmps", scope: !2, file: !2, line: 46, type: !93, scopeLine: 46, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!231 = !DILocalVariable(name: "a", arg: 1, scope: !230, file: !2, line: 46, type: !14)
!232 = !DILocation(line: 46, column: 15, scope: !230)
!233 = !DILocalVariable(name: "b", arg: 2, scope: !230, file: !2, line: 46, type: !14)
!234 = !DILocation(line: 46, column: 22, scope: !230)
!235 = !DILocalVariable(name: "r", scope: !230, file: !2, line: 47, type: !14)
!236 = !DILocation(line: 47, column: 9, scope: !230)
!237 = !DILocation(line: 48, column: 11, scope: !230)
!238 = !DILocation(line: 48, column: 16, scope: !230)
!239 = !DILocation(line: 48, column: 13, scope: !230)
!240 = !DILocation(line: 48, column: 7, scope: !230)
!241 = !DILocation(line: 49, column: 11, scope: !230)
!242 = !DILocation(line: 49, column: 16, scope: !230)
!243 = !DILocation(line: 49, column: 13, scope: !230)
!244 = !DILocation(line: 49, column: 7, scope: !230)
!245 = !DILocation(line: 50, column: 11, scope: !230)
!246 = !DILocation(line: 50, column: 15, scope: !230)
!247 = !DILocation(line: 50, column: 13, scope: !230)
!248 = !DILocation(line: 50, column: 7, scope: !230)
!249 = !DILocation(line: 51, column: 20, scope: !230)
!250 = !DILocation(line: 51, column: 35, scope: !230)
!251 = !DILocation(line: 51, column: 22, scope: !230)
!252 = !DILocation(line: 51, column: 7, scope: !230)
!253 = !DILocation(line: 52, column: 11, scope: !230)
!254 = !DILocation(line: 52, column: 15, scope: !230)
!255 = !DILocation(line: 52, column: 13, scope: !230)
!256 = !DILocation(line: 52, column: 7, scope: !230)
!257 = !DILocation(line: 53, column: 20, scope: !230)
!258 = !DILocation(line: 53, column: 35, scope: !230)
!259 = !DILocation(line: 53, column: 22, scope: !230)
!260 = !DILocation(line: 53, column: 7, scope: !230)
!261 = !DILocation(line: 54, column: 11, scope: !230)
!262 = !DILocation(line: 54, column: 16, scope: !230)
!263 = !DILocation(line: 54, column: 13, scope: !230)
!264 = !DILocation(line: 54, column: 7, scope: !230)
!265 = !DILocation(line: 55, column: 20, scope: !230)
!266 = !DILocation(line: 55, column: 34, scope: !230)
!267 = !DILocation(line: 55, column: 22, scope: !230)
!268 = !DILocation(line: 55, column: 7, scope: !230)
!269 = !DILocation(line: 56, column: 12, scope: !230)
!270 = !DILocation(line: 56, column: 5, scope: !230)
!271 = distinct !DISubprogram(name: "fcmps", scope: !2, file: !2, line: 59, type: !272, scopeLine: 59, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!272 = !DISubroutineType(types: !273)
!273 = !{!14, !11, !11}
!274 = !DILocalVariable(name: "a", arg: 1, scope: !271, file: !2, line: 59, type: !11)
!275 = !DILocation(line: 59, column: 18, scope: !271)
!276 = !DILocalVariable(name: "b", arg: 2, scope: !271, file: !2, line: 59, type: !11)
!277 = !DILocation(line: 59, column: 28, scope: !271)
!278 = !DILocation(line: 60, column: 13, scope: !271)
!279 = !DILocation(line: 60, column: 18, scope: !271)
!280 = !DILocation(line: 60, column: 15, scope: !271)
!281 = !DILocation(line: 60, column: 24, scope: !271)
!282 = !DILocation(line: 60, column: 28, scope: !271)
!283 = !DILocation(line: 60, column: 26, scope: !271)
!284 = !DILocation(line: 60, column: 31, scope: !271)
!285 = !DILocation(line: 60, column: 21, scope: !271)
!286 = !DILocation(line: 60, column: 38, scope: !271)
!287 = !DILocation(line: 60, column: 42, scope: !271)
!288 = !DILocation(line: 60, column: 40, scope: !271)
!289 = !DILocation(line: 60, column: 45, scope: !271)
!290 = !DILocation(line: 60, column: 35, scope: !271)
!291 = !DILocation(line: 60, column: 52, scope: !271)
!292 = !DILocation(line: 60, column: 57, scope: !271)
!293 = !DILocation(line: 60, column: 54, scope: !271)
!294 = !DILocation(line: 60, column: 60, scope: !271)
!295 = !DILocation(line: 60, column: 49, scope: !271)
!296 = !DILocation(line: 60, column: 5, scope: !271)
!297 = distinct !DISubprogram(name: "negate", scope: !2, file: !2, line: 63, type: !298, scopeLine: 63, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!298 = !DISubroutineType(types: !299)
!299 = !{!11, !11}
!300 = !DILocalVariable(name: "x", arg: 1, scope: !297, file: !2, line: 63, type: !11)
!301 = !DILocation(line: 63, column: 22, scope: !297)
!302 = !DILocation(line: 63, column: 35, scope: !297)
!303 = !DILocation(line: 63, column: 34, scope: !297)
!304 = !DILocation(line: 63, column: 27, scope: !297)
!305 = distinct !DISubprogram(name: "ptr_roundtrip", scope: !2, file: !2, line: 64, type: !306, scopeLine: 64, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7, retainedNodes: !28)
!306 = !DISubroutineType(types: !307)
!307 = !{!15, !308}
!308 = !DIDerivedType(tag: DW_TAG_pointer_type, baseType: null, size: 64)
!309 = !DILocalVariable(name: "p", arg: 1, scope: !305, file: !2, line: 64, type: !308)
!310 = !DILocation(line: 64, column: 26, scope: !305)
!311 = !DILocation(line: 64, column: 59, scope: !305)
!312 = !DILocation(line: 64, column: 38, scope: !305)
!313 = !DILocation(line: 64, column: 31, scope: !305)
!314 = distinct !DISubprogram(name: "main", scope: !2, file: !2, line: 66, type: !315, scopeLine: 66, flags: DIFlagPrototyped, spFlags: DISPFlagDefinition, unit: !7)
!315 = !DISubroutineType(types: !316)
!316 = !{!14}
!317 = !DILocation(line: 66, column: 25, scope: !314)
!318 = !DILocation(line: 66, column: 39, scope: !314)
!319 = !DILocation(line: 66, column: 37, scope: !314)
!320 = !DILocation(line: 66, column: 18, scope: !314)
