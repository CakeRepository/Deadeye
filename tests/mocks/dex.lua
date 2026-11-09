-- Beasts, Beast Lore, the pet's spellbook, Beast Training and the world map, for
-- the pet abilities dex (Modules\Dex.lua). See MOCK_FILES in tests/harness.lua.
--   W.units[unit]        a beast shown as that unit ("target", "mouseover",
--                          "nameplate1"): { id, name, level, family, classification,
--                          lines = { tooltip lines after the name }, loreAt = time
--                          from which lore lines show, lore = { those lines } }
--   W.pet.family / .spells / .guid   the pet's family, spellbook entries
--                          ({ name, subtext }) and GUID
--   W.craft              the Beast Training window's entries while it's open:
--                          { name, rank text, kind } ("header" for headers)
--   W.trainerServices    a trainer's services while its window is open, the same
--                          way; W.trainerLine their skill line (Beast Training)
--   W.mapID, W.position  the map you're on and your { x, y } on it (nil in dungeons)
--   W.mapNames, W.familyNames   names by map ID and pet family ID
--   W.userWaypoint, W.superTracked   the game's map pin
-- WorldMapFrame has a canvas (W.mapCanvas) that zooms by W.mapZoom.
local ENGLISH_FAMILIES = {
	[1] = "Wolf", [2] = "Cat", [3] = "Spider", [4] = "Bear", [5] = "Boar", [6] = "Crocolisk", [7] = "Carrion Bird",
	[8] = "Crab", [9] = "Gorilla", [11] = "Raptor", [12] = "Tallstrider", [20] = "Scorpid", [21] = "Turtle",
	[24] = "Bat", [25] = "Hyena", [26] = "Bird of Prey", [27] = "Wind Serpent", [45] = "Core Hound",
}

return function(W, env, M)
	local check, isNumber = M.check, M.isNumber
	W.units = {}
	W.craft = nil
	W.mapID, W.position = 1429, { 0.5, 0.6 }
	W.mapNames = { [1429] = "Elwynn Forest", [1426] = "Dun Morogh", [1411] = "Durotar" }
	W.familyNames = {}
	for id, name in pairs(ENGLISH_FAMILIES) do
		W.familyNames[id] = name
	end
	W.playerName, W.mapZoom = "Huntress", 1
	W.spellNames[1462] = "Beast Lore"
	W.spellNames[1515] = "Tame Beast"
	W.spellNames[5149] = "Beast Training"

	local function Beast(unit)
		return type(unit) == "string" and W.units[unit] or nil
	end

	local UnitExists, UnitName, UnitLevel = env.UnitExists, env.UnitName, env.UnitLevel
	local UnitPlayerControlled = env.UnitPlayerControlled
	env.UnitExists = function(unit)
		if Beast(unit) then
			return true
		elseif unit == "mouseover" then
			return false
		end
		return UnitExists(unit)
	end
	env.UnitName = function(unit)
		local beast = Beast(unit)
		if beast then
			return beast.name, nil
		elseif unit == "player" then
			return W.playerName, nil
		end
		return UnitName(unit)
	end
	env.UnitLevel = function(unit)
		local beast = Beast(unit)
		if beast then
			return beast.level or 1
		end
		return UnitLevel(unit)
	end
	env.UnitPlayerControlled = function(unit)
		if Beast(unit) then
			return Beast(unit).player == true
		end
		return UnitPlayerControlled(unit)
	end
	env.UnitGUID = function(unit)
		local beast = Beast(unit)
		if beast then
			return string.format("Creature-0-4372-0-1-%d-0000%s", beast.id or 0, unit == "target" and "AB12" or "CD34")
		elseif unit == "pet" then
			return W.pet and (W.pet.guid or "Pet-0-4372-0-1-42-0100000001") or nil
		elseif unit == "player" then
			return "Player-4372-00000001"
		end
		return nil
	end
	env.UnitClassification = function(unit)
		local beast = Beast(unit)
		return beast and beast.classification or "normal"
	end
	env.UnitCreatureFamily = function(unit)
		local beast = Beast(unit)
		if beast then
			return beast.family
		elseif unit == "pet" then
			return W.pet and W.pet.family
		end
		return nil
	end
	env.GetRealmName = function()
		return "Forever"
	end
	env.GetServerTime = function()
		return math.floor(1700000000 + W.now)
	end
	env.C_CreatureInfo = {
		GetCreatureFamilyInfo = function(id)
			check(isNumber(id), "GetCreatureFamilyInfo: family id expected")
			local name = W.familyNames[id]
			return name and { name = name, iconFile = 132186 } or nil
		end,
	}

	-- Unit tooltips: the name, then the beast's lines, then Beast Lore's once the
	-- game has heard back.
	env.C_TooltipInfo.GetUnit = function(unit)
		local beast = Beast(unit)
		if not beast then
			return nil
		end
		local lines = { { leftText = beast.name, type = 2 } }
		for _, text in ipairs(beast.lines or {}) do
			lines[#lines + 1] = { leftText = text, type = 0 }
		end
		if beast.lore and W.now >= (beast.loreAt or 0) then
			for _, text in ipairs(beast.lore) do
				lines[#lines + 1] = { leftText = W.inCombat and beast.secretInCombat and M.H.Secret(text) or text, type = 0 }
			end
		end
		return { type = 2, guid = env.UnitGUID(unit), lines = lines }
	end

	-- The pet's spellbook.
	env.C_SpellBook.HasPetSpells = function()
		local spells = W.pet and W.pet.spells
		if not spells or #spells == 0 then
			return nil
		end
		return #spells, "PET"
	end
	env.C_SpellBook.GetSpellBookItemName = function(index, bank)
		check(isNumber(index) and bank == "pet", "GetSpellBookItemName: pet spellbook index expected")
		local entry = W.pet and W.pet.spells and W.pet.spells[index]
		if entry then
			return entry[1], entry[2]
		end
	end

	-- Beast Training (a craft window on Classic clients).
	env.GetNumCrafts = function()
		return W.craft and #W.craft or 0
	end
	env.GetCraftInfo = function(index)
		check(isNumber(index), "GetCraftInfo: index expected")
		local entry = W.craft and W.craft[index]
		if entry then
			return entry[1], entry[2], entry[3] or "used", 0, true, 0, 0
		end
	end
	env.GetCraftDisplaySkillLine = function()
		return W.craftName or "Beast Training", 1, 1
	end

	-- Trainers' windows.
	env.GetNumTrainerServices = function()
		return W.trainerServices and #W.trainerServices or 0
	end
	env.GetTrainerServiceInfo = function(index)
		check(isNumber(index), "GetTrainerServiceInfo: index expected")
		local entry = W.trainerServices and W.trainerServices[index]
		if entry then
			return entry[1], entry[2], entry[3] or "available", true
		end
	end
	env.GetTrainerServiceSkillLine = function(index)
		check(isNumber(index), "GetTrainerServiceSkillLine: index expected")
		return W.trainerLine or "Beast Training", 1, 1
	end

	-- Maps.
	env.C_Map = {
		GetBestMapForUnit = function(unit)
			check(unit == "player", "GetBestMapForUnit: only the player is mocked")
			return W.mapID
		end,
		GetPlayerMapPosition = function(map, unit)
			check(isNumber(map) and unit == "player", "GetPlayerMapPosition: map and player expected")
			if not W.position or map ~= W.mapID then
				return nil
			end
			local x, y = W.position[1], W.position[2]
			return { GetXY = function()
				return x, y
			end }
		end,
		GetMapInfo = function(map)
			check(isNumber(map), "GetMapInfo: map id expected")
			return W.mapNames[map] and { mapID = map, name = W.mapNames[map], mapType = 3 } or nil
		end,
		CanSetUserWaypointOnMap = function(map)
			return W.mapNames[map] ~= nil
		end,
		SetUserWaypoint = function(point)
			check(type(point) == "table" and isNumber(point.uiMapID), "SetUserWaypoint: UiMapPoint expected")
			W.userWaypoint = point
		end,
	}
	env.UiMapPoint = {
		CreateFromCoordinates = function(map, x, y)
			check(isNumber(map) and isNumber(x) and isNumber(y), "UiMapPoint.CreateFromCoordinates: map, x, y expected")
			return { uiMapID = map, position = { x = x, y = y } }
		end,
	}
	env.C_SuperTrack = {
		SetSuperTrackedUserWaypoint = function(on)
			W.superTracked = on
		end,
	}

	-- The world map: a frame with a canvas, shown by ShowUIPanel. Its methods
	-- are plain fields, so hooksecurefunc can hook them.
	local map = M.NewFrame("Frame", "WorldMapFrame", env.UIParent)
	map:Hide()
	local canvas = M.NewFrame("Frame", nil, map)
	canvas:SetSize(1002, 668)
	W.mapCanvas = canvas
	map.ScrollContainer = {
		GetCanvasScale = function()
			return W.mapZoom
		end,
	}
	map.GetCanvas = function()
		return canvas
	end
	map.GetMapID = function(self)
		return self.mapID
	end
	map.OnMapChanged = function() end
	map.OnShow = function() end
	map.OnCanvasScaleChanged = function() end
	map.SetMapID = function(self, id)
		check(isNumber(id), "WorldMapFrame:SetMapID: map id expected")
		self.mapID = id
		self:OnMapChanged()
	end
	env.ShowUIPanel = function(frame)
		check(not W.inCombat or frame ~= map, "ShowUIPanel: the map is opened out of combat")
		frame:Show()
		if frame.OnShow then
			frame:OnShow()
		end
	end
	env.WorldMapFrame = map
end
