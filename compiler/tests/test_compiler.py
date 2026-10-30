import unittest

from cinterp.codegen.binary_writer import write_package
from cinterp.ffi.plan import PlanTable, build_sysv_plan, serialize_plans
from cinterp.llvm_ir.lower import compile_text, parse_globals, parse_structs


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
