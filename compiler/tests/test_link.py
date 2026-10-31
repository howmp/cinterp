import struct
import unittest

from cinterp.link import cstdapi, winmd
from cinterp.link.imports import ImportEntry, ImportTable, Provider
from cinterp.link.target import TARGETS
from cinterp.llvm_ir.lower import compile_text


class TargetAndImportTests(unittest.TestCase):
    def test_target_metadata_layout(self):
        target = TARGETS["x86_64-linux"]
        data = target.serialize()
        self.assertEqual(data[:4], b"CIPM")
        self.assertEqual(data[4], 1)
        self.assertEqual(struct.unpack_from("<H", data, 5)[0], 29)
        self.assertEqual(data[7], 1)  # x86_64
        self.assertEqual(data[8], 1)  # linux
        self.assertEqual(data[9], 1)  # sysv
        self.assertEqual(data[10], 64)

    def test_import_table_layout(self):
        table = ImportTable()
        table.add(
            ImportEntry(
                plan_index=3,
                name="printf",
                providers=[Provider(kind=1, name="libc.so.6", symbol="printf")],
            )
        )
        data = table.serialize()
        self.assertEqual(data[:4], b"CIPI")
        self.assertEqual(data[4], 1)
        self.assertEqual(struct.unpack_from("<H", data, 6)[0], 1)
        self.assertIn(b"printf", data)
        self.assertIn(b"libc.so.6", data)

    def test_cstdapi_providers(self):
        self.assertEqual(
            [p.name for p in cstdapi.lookup(TARGETS["x86_64-linux"], "printf")],
            ["libc.so.6", "libm.so.6"],
        )
        windows = cstdapi.lookup(TARGETS["x86_64-windows"], "snprintf")
        self.assertEqual(windows[0].name, "ucrtbase.dll")
        self.assertIn("_snprintf", [p.symbol for p in windows])

    def test_cstdapi_rejects_known_bad(self):
        with self.assertRaises(ValueError):
            cstdapi.lookup(TARGETS["x86_64-windows"], "abort_handler_s")

    def test_winmd_providers_and_decorated_names(self):
        providers, conv, min_os = winmd.lookup(TARGETS["x86_64-windows"], "GetTickCount64")
        self.assertEqual(providers[0].name, "kernel32.dll")
        self.assertEqual(conv, 1)
        self.assertGreater(min_os, 0)
        providers, _, _ = winmd.lookup(TARGETS["i686-windows"], "_GetSystemMetrics@4")
        self.assertEqual(providers[0].name, "user32.dll")

    def test_compile_v2_has_target_and_empty_imports(self):
        package, _, _, _, plans = compile_text(
            "define i32 @main() {\nentry:\n  ret i32 0\n}\n",
            auto_link=False,
        )
        self.assertEqual(package[:6], b"CIPKG\x02")
        self.assertEqual(len(plans.plans), 0)
        module_len, plan_len, meta_len = struct.unpack_from("<III", package, 9)
        self.assertGreater(meta_len, 0)
        offset = 25 + module_len + plan_len
        self.assertEqual(package[offset : offset + 4], b"CIPM")


if __name__ == "__main__":
    unittest.main()
