-- Macros, duels and pet ability cooldowns, for the pet commands (Modules\PetCommands.lua).
-- See MOCK_FILES in tests/harness.lua.
--   W.macroList          your macros: { account = { macro, ... }, character = { ... } },
--                          each { name =, icon =, body = }, kept sorted by name as the game does
--   W.duels              who you challenged (StartDuel)
--   petActions[slot].cooldown   { start, duration } of a pet ability (GetPetActionCooldown)
-- Macros can't be made or changed in combat (the client blocks it). Macro names
-- are at most 16 characters and bodies 255 bytes.
local MAX_ACCOUNT, MAX_CHARACTER = 120, 30
local ICON_IDS = {
	["Interface\\Icons\\Ability_GhoulFrenzy"] = 132152,
	["Interface\\Icons\\Ability_Tracking"] = 132328,
	["Interface\\Icons\\Spell_Nature_TimeStop"] = 136106,
	["Interface\\Icons\\Ability_Hunter_Pet_Goto"] = 132177,
	["Interface\\Icons\\Ability_Defend"] = 132110,
}

return function(W, env, M)
	local check, isNumber = M.check, M.isNumber
	W.macroList = { account = {}, character = {} }
	W.duels = {}
	W.iconIDs = ICON_IDS

	local function Length(text)
		local count = 0
		for _ in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
			count = count + 1
		end
		return count
	end
	local function Sort(list)
		table.sort(list, function(a, b)
			return a.name < b.name
		end)
	end
	local function Find(index)
		if index >= 1 and index <= #W.macroList.account then
			return W.macroList.account, index
		elseif index > MAX_ACCOUNT and index - MAX_ACCOUNT <= #W.macroList.character then
			return W.macroList.character, index - MAX_ACCOUNT
		end
	end
	local function IndexOf(list, macro)
		for i, each in ipairs(list) do
			if each == macro then
				return list == W.macroList.account and i or MAX_ACCOUNT + i
			end
		end
	end
	local function Blocked(what)
		if W.inCombat then
			W.blocked[#W.blocked + 1] = what
			return true
		end
	end
	local function CheckMacro(name, icon, body)
		check(type(name) == "string" and name ~= "" and Length(name) <= 16, "macro name: 1 to 16 characters, not " .. tostring(name))
		check(isNumber(icon), "macro icon: a file ID expected")
		check(type(body) == "string" and #body <= 255, "macro body: up to 255 bytes")
	end

	env.Constants = env.Constants or {}
	env.Constants.MacroConsts = { MAX_ACCOUNT_MACROS = MAX_ACCOUNT, MAX_CHARACTER_MACROS = MAX_CHARACTER }
	env.GetNumMacros = function()
		return #W.macroList.account, #W.macroList.character
	end
	env.GetMacroInfo = function(index)
		check(isNumber(index), "GetMacroInfo: index expected")
		local list, i = Find(index)
		if list then
			local macro = list[i]
			return macro.name, macro.icon, macro.body
		end
	end
	env.CreateMacro = function(name, icon, body, perCharacter)
		CheckMacro(name, icon, body)
		if Blocked("CreateMacro") then
			return nil
		end
		local list = perCharacter and W.macroList.character or W.macroList.account
		check(#list < (perCharacter and MAX_CHARACTER or MAX_ACCOUNT), "CreateMacro: no room left")
		local macro = { name = name, icon = icon, body = body }
		list[#list + 1] = macro
		Sort(list)
		return IndexOf(list, macro)
	end
	env.EditMacro = function(index, name, icon, body)
		local list, i = Find(index)
		check(list, "EditMacro: no macro at " .. tostring(index))
		local macro = list[i]
		CheckMacro(name or macro.name, icon or macro.icon, body or macro.body)
		if Blocked("EditMacro") then
			return nil
		end
		macro.name, macro.icon, macro.body = name or macro.name, icon or macro.icon, body or macro.body
		Sort(list)
		return IndexOf(list, macro)
	end
	env.GetFileIDFromPath = function(path)
		check(type(path) == "string", "GetFileIDFromPath: path expected")
		return ICON_IDS[path]
	end

	env.StartDuel = function(unit)
		W.duels[#W.duels + 1] = unit or "target"
	end

	env.GetPetActionCooldown = function(slot)
		check(isNumber(slot), "GetPetActionCooldown: slot expected")
		local action = W.pet and W.petActions[slot]
		local cooldown = action and action.cooldown
		if cooldown then
			return cooldown[1], cooldown[2], 1
		end
		return 0, 0, 1
	end
end
