-- Checks one translation file on its own, without loading the others:
--   lua5.1 tests/check_locale.lua deDE      (from the project root)
--   python tests/check_locale.py deDE       (uses the Lua 5.1 bundled with lupa)
-- It lists missing texts, texts the addon no longer uses, and translations that
-- lost a %s placeholder or a /deadeye command.
local ROOT = ROOT or "."
local locale = LOCALE or (arg and arg[1])
local H = dofile(ROOT .. "/tests/harness.lua")
local tests = assert(loadfile(ROOT .. "/tests/test_locales.lua"))(H, ROOT)
for _, t in ipairs(tests) do
	if locale and t.name:find(locale .. ": translates", 1, true) == 1 then
		local ok, err = pcall(t.fn)
		print(ok and (locale .. ": no problems") or (locale .. ": " .. tostring(err)))
		return ok and 0 or 1
	end
end
print("Usage: check_locale.lua <locale>, e.g. deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW")
return 1
