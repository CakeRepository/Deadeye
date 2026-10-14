-- Runs the Deadeye tests on Lua 5.1, the Lua version WoW uses.
--   lua5.1 tests/run.lua          (from the project root)
--   python tests/run_tests.py     (uses the Lua 5.1 bundled with the lupa package)
local ROOT = ROOT or (arg and arg[0] and arg[0]:match("^(.*)[/\\]tests[/\\]run%.lua$")) or "."
local H = dofile(ROOT .. "/tests/harness.lua")

local passed, failed = 0, 0

-- Every file in the .toc must compile before anything else runs.
for line in io.lines(ROOT .. "/Deadeye.toc") do
	line = line:gsub("\r", "")
	if line ~= "" and not line:find("^##") then
		local path = ROOT .. "/" .. line:gsub("\\", "/")
		local chunk, err = loadfile(path)
		if chunk then
			passed = passed + 1
			print("  ok    compiles: " .. line)
		else
			failed = failed + 1
			print("  FAIL  compiles: " .. line .. "\n        " .. err)
		end
	end
end

if failed == 0 then
	for _, file in ipairs({ "test_autoshot.lua", "test_options.lua", "test_hunter_tools.lua", "test_locales.lua" }) do
		local tests = assert(loadfile(ROOT .. "/tests/" .. file))(H, ROOT)
		for _, t in ipairs(tests) do
			local ok, err = xpcall(t.fn, debug.traceback)
			if ok then
				passed = passed + 1
				print("  ok    " .. t.name)
			else
				failed = failed + 1
				print("  FAIL  " .. t.name .. "\n" .. err)
			end
		end
	end
end

print(string.format("\n%d passed, %d failed", passed, failed))
return failed
