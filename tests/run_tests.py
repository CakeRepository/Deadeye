"""Run the ForeverHunter tests on Lua 5.1 (the version WoW uses) through lupa.

    pip install lupa
    python tests/run_tests.py
"""
import pathlib
import sys

from lupa import lua51

root = pathlib.Path(__file__).resolve().parent.parent
lua = lua51.LuaRuntime()
lua.globals().ROOT = root.as_posix()
failed = lua.execute(f"return dofile([[{(root / 'tests' / 'run.lua').as_posix()}]])")
sys.exit(1 if failed else 0)
