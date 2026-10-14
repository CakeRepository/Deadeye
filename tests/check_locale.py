"""Check one Deadeye translation file: python tests/check_locale.py deDE

Uses the Lua 5.1 that comes with lupa (pip install lupa), like run_tests.py.
"""
import pathlib
import sys

from lupa import lua51

root = pathlib.Path(__file__).resolve().parent.parent
lua = lua51.LuaRuntime()
lua.globals().ROOT = root.as_posix()
lua.globals().LOCALE = sys.argv[1] if len(sys.argv) > 1 else None
failed = lua.execute(f"return dofile([[{(root / 'tests' / 'check_locale.lua').as_posix()}]])")
sys.exit(1 if failed else 0)
