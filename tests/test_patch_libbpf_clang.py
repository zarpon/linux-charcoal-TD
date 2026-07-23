#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "automation/fix-libbpf-clang-warning.py"

spec = importlib.util.spec_from_file_location("fix_libbpf_clang", SCRIPT)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)


class LibbpfClangCompatibilityTests(unittest.TestCase):
    def test_two_gcc_pragmas_are_guarded_from_clang(self) -> None:
        source = (
            "#pragma GCC diagnostic push\n"
            f"{module.PRAGMA}\n"
            "int first;\n"
            "#pragma GCC diagnostic pop\n"
            "#pragma GCC diagnostic push\n"
            f"{module.PRAGMA}\n"
            "int second;\n"
            "#pragma GCC diagnostic pop\n"
        )
        adapted = module.adapt(source)
        self.assertEqual(adapted.count(module.GUARDED), 2)
        self.assertEqual(adapted.count(module.PRAGMA), 2)
        self.assertIn("#if !defined(__clang__)", adapted)

    def test_unexpected_upstream_structure_is_rejected(self) -> None:
        with self.assertRaises(module.CompatibilityError):
            module.adapt(f"{module.PRAGMA}\n")

    def test_double_application_is_rejected(self) -> None:
        guarded = f"{module.GUARDED}\n{module.GUARDED}\n"
        with self.assertRaises(module.CompatibilityError):
            module.adapt(guarded)


if __name__ == "__main__":
    unittest.main()
