import unittest

from cinterp.codegen.binary_writer import write_package
from cinterp.ffi.plan import (
    PlanTable,
    build_aapcs64_plan,
    build_sysv_plan,
    build_win32_plan,
    build_win64_plan,
    serialize_plans,
)
from cinterp.llvm_ir.lower import (
    CallbackTable,
    Function,
    compile_text,
    parse_globals,
    parse_structs,
)


class PlanTests(unittest.TestCase):
    def test_puts_plan(self):
        plan = build_sysv_plan("puts", "i32", ["ptr"])
        self.assertEqual(plan.ret_locs[0].kind, "rax")
        self.assertEqual(plan.ret_locs[0].size, 4)
        self.assertEqual(plan.args[0].locs[0].kind, "gpr")
        self.assertEqual(plan.args[0].locs[0].index, 0)
        self.assertEqual(plan.stack_size, 0)

    def test_printf_vararg_plan(self):
        plan = build_sysv_plan("printf", "i32", ["ptr", "i32", "double"], True)
        self.assertEqual([a.locs[0].kind for a in plan.args], ["gpr", "gpr", "xmm"])
        self.assertEqual(plan.args[2].locs[0].index, 0)
        self.assertEqual(plan.sse_count, 1)

    def test_byval_and_sret_plans(self):
        byval = build_sysv_plan("c_sum_s24", "i64", ["ptr"], byval_sizes=[24])
        self.assertEqual(byval.args[0].locs[0].kind, "stack")
        self.assertTrue(byval.args[0].is_struct)
        self.assertEqual(byval.stack_size, 24)

        sret = build_sysv_plan(
            "c_make_s24", "void", ["ptr", "i64"], sret_idx=0, sret_size=24
        )
        self.assertTrue(sret.sret)
        self.assertEqual(sret.args[0].locs[0].kind, "sret")
        self.assertEqual(sret.args[1].locs[0].kind, "gpr")
        self.assertEqual(sret.args[1].locs[0].index, 1)
        self.assertEqual(sret.ret_size, 24)

    def test_aggregate_return_plan(self):
        plan = build_sysv_plan(
            "c_make_d16", "{ double, double }", ["double", "double"]
        )
        self.assertEqual([loc.kind for loc in plan.ret_locs], ["xmm0", "xmm1"])
        self.assertEqual(plan.ret_size, 16)
        self.assertEqual(plan.sse_count, 2)

    def test_float_plan(self):
        plan = build_sysv_plan("c_scale", "float", ["float"])
        self.assertEqual([loc.kind for loc in plan.ret_locs], ["xmm0"])
        self.assertEqual(plan.ret_size, 4)
        self.assertEqual(plan.args[0].locs[0].kind, "xmm")
        self.assertEqual(plan.args[0].locs[0].index, 0)
        self.assertEqual(plan.sse_count, 1)

    def test_mixed_aggregate_return_plan(self):
        plan = build_sysv_plan("c_make_m", "{ i64, double }", ["i64", "double"])
        self.assertEqual([loc.kind for loc in plan.ret_locs], ["rax", "xmm0"])
        self.assertEqual(plan.ret_size, 16)
        self.assertEqual(plan.sse_count, 1)

    def test_callback_plan_table(self):
        plans = PlanTable()
        callbacks = CallbackTable()
        fn = Function(
            name="cmp",
            ret="i32",
            params=[("ptr", "a"), ("ptr", "b")],
            body=[],
        )
        slot, func_index, plan_index = callbacks.add("cmp", fn, 3, plans)
        self.assertEqual((slot, func_index, plan_index), (0, 3, 0))
        plan = plans.plans[plan_index]
        self.assertEqual(plan.name, "callback:cmp")
        self.assertEqual(len(plan.args), 2)
        self.assertEqual([loc.kind for loc in plan.ret_locs], ["rax"])
        self.assertEqual(callbacks.add("cmp", fn, 3, plans), (0, 3, 0))
        self.assertEqual(len(plans.plans), 1)

    def test_win64_positional_registers(self):
        plan = build_win64_plan(
            "c_mix", "i32", ["i32", "double", "i32", "double"]
        )
        self.assertEqual(
            [(a.locs[0].kind, a.locs[0].index) for a in plan.args],
            [("gpr", 0), ("xmm", 1), ("gpr", 2), ("xmm", 3)],
        )
        self.assertEqual([loc.kind for loc in plan.ret_locs], ["rax"])

    def test_win64_sret_shifts_both_register_files(self):
        plan = build_win64_plan(
            "c_make_m", "void", ["ptr", "i32", "double"],
            sret_idx=0, sret_size=16,
        )
        self.assertEqual(
            [(a.locs[0].kind, a.locs[0].index) for a in plan.args],
            [("sret", 0), ("gpr", 1), ("xmm", 2)],
        )
        self.assertTrue(plan.sret)

    def test_win32_stack_and_returns(self):
        plan = build_win32_plan("f", "i64", ["i32", "double"], ptr_size=4)
        self.assertEqual([loc.kind for loc in plan.ret_locs], ["rax"])
        self.assertEqual(plan.ret_locs[0].size, 8)
        self.assertEqual(
            [(a.locs[0].kind, a.locs[0].index) for a in plan.args],
            [("stack", 0), ("stack", 4)],
        )
        fp = build_win32_plan("g", "float", ["float"], ptr_size=4)
        self.assertEqual([loc.kind for loc in fp.ret_locs], ["xmm0"])
        self.assertEqual(fp.ret_locs[0].size, 4)

    def test_aapcs64_hfa_and_sret(self):
        plan = build_aapcs64_plan(
            "c_hfa", "double", ["[2 x double]"],
            structs={}, ptr_size=8,
        )
        self.assertEqual(
            [(loc.kind, loc.index) for loc in plan.args[0].locs],
            [("xmm", 0), ("xmm", 1)],
        )
        hfa_ret = build_aapcs64_plan(
            "c_hfa_ret", "%struct.D2", [],
            structs={"%struct.D2": ["double", "double"]}, ptr_size=8,
        )
        self.assertEqual(
            [(loc.kind, loc.size) for loc in hfa_ret.ret_locs],
            [("xmm0", 8), ("xmm1", 8)],
        )
        sret = build_aapcs64_plan(
            "big", "void", ["ptr", "i64"],
            sret_idx=0, sret_size=24, structs={}, ptr_size=8,
        )
        self.assertEqual(sret.args[0].locs[0].kind, "sret")
        self.assertEqual(sret.args[1].locs[0].kind, "gpr")

    def test_plan_serialization_and_package(self):
        table = PlanTable()
        table.add(build_sysv_plan("puts", "i32", ["ptr"]))
        plans = table.serialize()
        self.assertTrue(plans.startswith(b"CIPL"))
        package = write_package(b"CIVM", plans)
        self.assertTrue(package.startswith(b"CIPKG"))
        self.assertEqual(int.from_bytes(package[7:11], "little"), 4)
        self.assertEqual(int.from_bytes(package[11:15], "little"), len(plans))


class LowerTests(unittest.TestCase):
    def test_return_42(self):
        ir = """
define dso_local i32 @main() {
entry:
  ret i32 42
}
"""
        package, module, plans, functions, table = compile_text(ir)
        self.assertTrue(package.startswith(b"CIPKG"))
        self.assertTrue(module.startswith(b"CIVM"))
        self.assertEqual(len(functions), 1)
        self.assertEqual(len(table.plans), 0)
        self.assertTrue(plans.startswith(b"CIPL"))

    def test_global_string(self):
        ir = """
@.str = private unnamed_addr constant [4 x i8] c"abc\\00", align 1

define dso_local i32 @main() {
entry:
  ret i32 0
}
"""
        structs = parse_structs(ir)
        globals_map, data = parse_globals(ir, structs)
        self.assertEqual(globals_map, {"@.str": 0})
        self.assertEqual(data[:4], b"abc\x00")

    def test_external_puts_plan(self):
        ir = """
@.str = private unnamed_addr constant [3 x i8] c"hi\\00", align 1
declare i32 @puts(ptr noundef)

define dso_local i32 @main() {
entry:
  %r = call i32 @puts(ptr noundef @.str)
  ret i32 0
}
"""
        _, _, _, functions, table = compile_text(ir)
        self.assertEqual(len(functions), 1)
        self.assertEqual(len(table.plans), 1)
        self.assertEqual(table.plans[0].name, "puts")
        self.assertEqual(table.plans[0].args[0].locs[0].kind, "gpr")


if __name__ == "__main__":
    unittest.main()
