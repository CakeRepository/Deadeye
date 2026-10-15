-- Translations. Each Locales\*.lua file must translate exactly the texts the
-- addon uses, keep their placeholders and chat commands, and the addon must run
-- in every language with its option pages still fitting.
local H, ROOT = ...

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

-- Game locale -> the file that translates it (esMX shares the Spanish file).
local LOCALE_FILES = {
	deDE = "deDE.lua", esES = "esES.lua", esMX = "esES.lua", frFR = "frFR.lua", itIT = "itIT.lua",
	koKR = "koKR.lua", ptBR = "ptBR.lua", ruRU = "ruRU.lua", zhCN = "zhCN.lua", zhTW = "zhTW.lua",
}
local LOCALES = {}
for locale in pairs(LOCALE_FILES) do
	LOCALES[#LOCALES + 1] = locale
end
table.sort(LOCALES)

-- Chat commands and placeholders that stay as they are in every language.
local KEEP = { "/deadeye lock", "/deadeye help", "/deadeye settings", "/deadeye test", "/deadeye pet unskip",
	"/deadeye width 250", "/deadeye texture flat", "<setting> <value>", "/deye", "ff8800" }

-- The addon's code files, in load order, from the .toc.
local function CodeFiles()
	local files = {}
	for line in io.lines(ROOT .. "/Deadeye.toc") do
		line = line:gsub("\r", "")
		if line ~= "" and not line:find("^##") and not line:find("^Locales") then
			files[#files + 1] = line:gsub("\\", "/")
		end
	end
	return files
end

-- Every L["..."] in the code (comments skipped), as the strings they become.
local function EnglishTexts()
	local texts = {}
	for _, file in ipairs(CodeFiles()) do
		for line in io.lines(ROOT .. "/" .. file) do
			for text in line:gsub("%-%-.*$", ""):gmatch('L%["(.-)"%]') do
				texts[(text:gsub("\\n", "\n"))] = true
			end
		end
	end
	return texts
end

-- Loads a locale file on its own and returns what it assigns to L.
local function Translations(locale)
	local strings, duplicates = {}, {}
	local L = setmetatable({}, {
		__newindex = function(_, key, value)
			if strings[key] ~= nil then
				duplicates[#duplicates + 1] = key
			end
			strings[key] = value
		end,
	})
	local chunk = assert(loadfile(ROOT .. "/Locales/" .. LOCALE_FILES[locale]))
	setfenv(chunk, {})
	chunk("Deadeye", { L = L, locale = locale })
	return strings, duplicates
end

local function Placeholders(text)
	local list = {}
	for token in text:gmatch("%%[%-%d%.]*[%a%%]") do
		list[#list + 1] = token
	end
	return table.concat(list, " ")
end

local function Count(text, plain)
	local count, start = 0, 1
	while true do
		local found = text:find(plain, start, true)
		if not found then
			return count
		end
		count, start = count + 1, found + #plain
	end
end

for _, locale in ipairs(LOCALES) do
	test(locale .. ": translates every text, keeping placeholders and commands", function()
		local english = EnglishTexts()
		local strings, duplicates = Translations(locale)
		H.Equal(#duplicates, 0, "texts translated twice (" .. table.concat(duplicates, " | ") .. ")")
		local problems = {}
		for key, value in pairs(strings) do
			if not english[key] then
				problems[#problems + 1] = "not used by the addon: " .. key
			elseif type(value) ~= "string" or value == "" then
				problems[#problems + 1] = "empty: " .. key
			else
				if Placeholders(value) ~= Placeholders(key) then
					problems[#problems + 1] = "placeholders differ: " .. key .. " => " .. value
				end
				for _, keep in ipairs(KEEP) do
					if Count(value, keep) < Count(key, keep) then
						problems[#problems + 1] = "lost '" .. keep .. "': " .. value
					end
				end
				if Count(value, "/deadeye") ~= Count(key, "/deadeye") then
					problems[#problems + 1] = "/deadeye count differs: " .. value
				end
				if value:find("|", 1, true) and not key:find("|", 1, true) then
					problems[#problems + 1] = "'|' starts a WoW escape code: " .. value
				end
			end
		end
		for key in pairs(english) do
			if strings[key] == nil then
				problems[#problems + 1] = "missing: " .. key
			end
		end
		table.sort(problems)
		H.True(#problems == 0, #problems .. " problem(s):\n  " .. table.concat(problems, "\n  "))
	end)
end

---------------------------------------------------------------------------
-- The addon in every language
---------------------------------------------------------------------------
local function PetData()
	return {
		name = "Grrl", level = 30, health = 800, healthMax = 1000, happiness = 3, damage = 125, loyaltyRate = -1,
		loyalty = "Loyalty Level 3", diet = { "Meat", "Fish" }, training = { 120, 85 },
	}
end

local function PagesFit(W)
	local window = W.ns.OptionsWindow
	for index, section in ipairs(window.sections) do
		window:SelectSection(index)
		for _, widget in ipairs(window.pages[index].controls) do
			local _, _, _, x, y = widget:GetPoint(1)
			local label = tostring(widget.spec.label or widget.spec.text)
			H.True(x < 300, section.name .. ": '" .. label .. "' is pushed into a third column")
			H.True(-y + widget.height <= 408, section.name .. ": '" .. label .. "' runs past the bottom")
		end
	end
end

for _, locale in ipairs(LOCALES) do
	test(locale .. ": the addon runs, every page fits, and texts are translated", function()
		local W = H.NewWorld({ locale = locale, tranqKnown = true }) -- so the Tranq Shot page is there too
		H.LoadAddon(W, ROOT)
		local L, AS = W.ns.L, W.ns.modules.AutoShot
		H.True(rawget(L, "Reload") ~= nil, "translations loaded")
		H.Equal(AS.db.labels.reload, L["Reload"], "the bar's default wording is translated")

		-- Chat commands, including the error and listing messages.
		for _, input in ipairs({
			"help", "settings", "settings range", "settings pet", "settings camera", "settings nothing", "bogus",
			"width", "width abc", "width 250", "bordercolor", "bordercolor zz", "label", "outline none",
			"playsound", "debug", "debug", "move", "move", "text off", "text on", "stats",
			"range", "range bogus", "pet", "pet unskip", "camera", "camera zoom 2",
			"ammo", "ammo bogus", "aspect", "tranq", "settings ammo", "settings tranq",
		}) do
			W.Slash(input)
		end
		H.True(W.Printed(L["Frames locked."]), "messages come out translated")

		-- Test mode and a fight with a delayed shot, for the delay report.
		W.Slash("test")
		W.Advance(2.5)
		W.Slash("test")
		W.Slash("report on")
		W.inCombat = true
		W.Fire("PLAYER_REGEN_DISABLED")
		W.Fire("START_AUTOREPEAT_SPELL")
		W.Fire("PLAYER_SWING", 2.0, 2)
		W.Advance(2.0)
		W.Fire("PLAYER_SWING", 2.0, 2)
		W.Advance(2.6)
		W.Fire("PLAYER_SWING", 2.0, 2) -- 0.6s late
		W.Slash("stats")
		W.inCombat = false
		W.Fire("PLAYER_REGEN_ENABLED")
		H.True(W.Printed(L["Last fight: %s"]:sub(1, 6)), "delay report")

		-- Every options page, and the reset buttons.
		W.Slash("")
		PagesFit(W)
		local window = W.ns.OptionsWindow
		window:ResetPage()
		window:ResetAll()
		window:ResetAll()
		W.Slash("")

		-- Range texts and the Hunter's Mark reminder.
		W.hasTarget, W.inRange, W.meleeInRange = true, true, false
		W.Fire("PLAYER_TARGET_CHANGED")
		W.inCombat = true
		W.Fire("PLAYER_REGEN_DISABLED")
		W.Fire("UI_ERROR_MESSAGE", 2, "")
		W.Advance(0.2)
		W.inCombat = false
		W.Fire("PLAYER_REGEN_ENABLED")

		-- Pet panel, alerts, tooltips and the feed button.
		local Pet = W.ns.modules.Pet
		W.pet = PetData()
		W.Fire("UNIT_PET", "player")
		Pet.frame.scripts.OnEnter(Pet.frame)
		W.pet.happiness = 2
		W.Fire("UNIT_HAPPINESS", "pet")
		W.pet.diet = {}
		W.pet.happiness = 1
		W.Fire("UNIT_HAPPINESS", "pet")
		W.pet.diet = { "Meat", "Fish" }
		local button = Pet.feedButton
		button.scripts.OnEnter(button)
		W.bags = { [0] = { size = 16, { itemID = 117, count = 5 }, { itemID = 12210, count = 2 } } }
		W.Fire("BAG_UPDATE_DELAYED")
		button.scripts.OnEnter(button)
		W.pet.level = 40
		W.Fire("UNIT_LEVEL", "pet")
		button.scripts.OnEnter(button)
		W.Click(button, "RightButton")
		button.scripts.OnEnter(button)
		W.Slash("pet unskip")
		W.pet.dead = true
		W.Fire("UNIT_HEALTH", "pet")
		Pet.frame.scripts.OnEnter(Pet.frame)
		W.pet = nil
		W.Fire("UNIT_PET", "player")
		Pet.frame.scripts.OnEnter(Pet.frame)
		W.inCombat = true
		W.Fire("PLAYER_REGEN_DISABLED")
		W.inCombat = false
		W.Fire("PLAYER_REGEN_ENABLED")

		-- Ammo: the counter, its warnings and the vendor button.
		W.bags = { [0] = { size = 16 }, [1] = { size = 6, family = 1 } }
		W.equipped[18], W.equipped[0] = 2504, 2512
		W.AddItem(2512, 300)
		W.Fire("PLAYER_EQUIPMENT_CHANGED", 0, true)
		local Ammo = W.ns.modules.Ammo
		Ammo.frame.scripts.OnEnter(Ammo.frame)
		W.UseItem(2512, 150)
		W.UseItem(2512, 150)
		W.inCombat = true
		W.Fire("PLAYER_REGEN_DISABLED")
		W.inCombat = false
		W.Fire("PLAYER_REGEN_ENABLED")
		W.OpenVendor({ { itemID = 2512, price = 10 } })
		local fill = Ammo.vendorButtonFrame
		fill.scripts.OnEnter(fill)
		W.Click(fill)
		W.Advance(3)
		fill.scripts.OnEnter(fill)
		Ammo:Fill()
		W.Click(fill, "RightButton")
		W.Click(fill, "RightButton")
		W.CloseVendor()
		W.equipped[0] = nil
		W.Fire("PLAYER_EQUIPMENT_CHANGED", 0, false)
		Ammo.frame.scripts.OnEnter(Ammo.frame)
		W.inCombat = true
		W.Fire("PLAYER_REGEN_DISABLED")
		W.inCombat = false
		W.Fire("PLAYER_REGEN_ENABLED")

		-- Aspect warnings and alerts, and the camera's zoom out.
		W.knownSpells = { [13165] = true }
		W.CastAspect(5118)
		W.inCombat = true
		W.Fire("PLAYER_REGEN_DISABLED")
		W.Advance(0.2)
		W.CancelBuff("Aspect of the Cheetah")
		W.Advance(0.2)
		W.inCombat = false
		W.Fire("PLAYER_REGEN_ENABLED")
		W.inCombat = true
		W.Fire("PLAYER_REGEN_DISABLED")
		W.Slash("camera zoomout")
		W.inCombat = false
		W.Fire("PLAYER_REGEN_ENABLED")
		W.Advance(0.1)

		-- The minimap addon button's tooltip.
		W.env.Deadeye_OnAddonCompartmentEnter(nil, button)
	end)
end

test("fonts: Cyrillic versions on Russian clients, the game font for Korean and Chinese", function()
	local W = H.NewWorld({ locale = "ruRU" })
	H.LoadAddon(W, ROOT)
	local Media = W.ns.Media
	H.Equal(Media.Font("Friz"), "Fonts\\FRIZQT___CYR.TTF", "Cyrillic Friz Quadrata")
	H.Equal(Media.Font("Morpheus"), "Fonts\\MORPHEUS_CYR.TTF", "Cyrillic Morpheus")
	for _, option in ipairs(Media.List("font")) do
		H.True(option.value ~= "Arial", "fonts without Cyrillic are not offered")
	end

	local W2 = H.NewWorld({ locale = "koKR" })
	H.LoadAddon(W2, ROOT)
	local list = W2.ns.Media.List("font")
	H.Equal(#list, 1, "only the game font is offered")
	H.Equal(list[1].value, "Default", "the game font")
	H.Equal(W2.ns.Media.Font("Friz"), W2.ns.Media.DefaultFont(), "an old Latin font choice falls back to the game font")

	local W3 = H.NewWorld()
	H.LoadAddon(W3, ROOT)
	H.Equal(W3.ns.Media.Font("Friz"), "Fonts\\FRIZQT__.TTF", "English clients keep the regular files")
	H.Equal(#W3.ns.Media.List("font"), 5, "and every font")
end)

return tests
