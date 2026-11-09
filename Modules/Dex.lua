-- Pet abilities: every rank of every pet ability, and the beasts you have found
-- that teach it. WoW: Forever keeps which beast knows which rank on its servers.
-- The game shows it to you when you cast Beast Lore on a beast, and a tamed
-- beast brings its ranks along. Deadeye saves what you find that way, and rare
-- beasts you come across, with where you found them. It's your own dex, shared
-- by the hunters on your account and filled in as you play.
--
-- What it reads:
--   Beast Lore      the target's tooltip after the cast (C_TooltipInfo.GetUnit):
--                   each ability name with the first number after it
--   Tame Beast      the new pet's spellbook: its ranks are the wild beast's
--   rare beasts     targets, mouseovers and nameplates the game classes rare
--   Beast Training  the ranks this hunter has learned, while its window is open
--   pet trainers    the abilities they sell, while their window is open
--   your pet        its spellbook, family and level
-- The ranks, their pet levels and training costs come from the game's data, the
-- same for everyone. The beasts are only ever what you found yourself.
--
-- Clicking a beast shows it on the world map: pins where you found it (frames on
-- the map's canvas), a TomTom arrow when TomTom is installed, or else the game's
-- own map pin. A key binding casts Beast Lore on your mouseover target (or your
-- target), for sweeping a zone.
local _, ns = ...
local L = ns.L

local Dex = ns:NewModule("Dex", {
	record = true, -- save beasts from Beast Lore and taming
	rares = true, -- save rare beasts you see
	upgradeAlert = true, -- tell me when my pet's level reaches a new rank
	allPins = false, -- pins for every beast you found on the world map, not just the one you clicked
	tomtom = true, -- a TomTom arrow to the beast you click, when TomTom is installed
})
Dex.title = L["Pet abilities"]
Dex.slashPrefix = "dex"

local BEAST_LORE = 1462
local TAME_BEAST = 1515
local BEAST_TRAINING = 5149
local LORE_READS = { 0, 0.5, 1.5 } -- seconds after the cast: the game fills the tooltip in when it hears back
local TAME_SECONDS = 40 -- from starting Tame Beast to the new pet's spellbook
local SEEN_SECONDS = 30 -- a rare seen again this soon isn't saved again
local SPOTS_PER_BEAST = 6
local SAME_SPOT = 0.03 -- spots closer than this (share of the map) are one spot
local ROWS, ROW_HEIGHT = 18, 20
local WIDTH, HEIGHT = 560, 500
local PADDING = 14
local RANK_LIMIT = 20 -- the highest rank number believed when reading a tooltip
local CONFIRM_SECONDS = 3

local ALL = "all"
-- Pet families by their English names, with their IDs (CreatureFamily) for the
-- names the game uses in other languages.
local FAMILY_IDS = {
	Wolf = 1, Cat = 2, Spider = 3, Bear = 4, Boar = 5, Crocolisk = 6, ["Carrion Bird"] = 7, Crab = 8, Gorilla = 9,
	Raptor = 11, Tallstrider = 12, Scorpid = 20, Turtle = 21, Bat = 24, Hyena = 25, ["Bird of Prey"] = 26, ["Wind Serpent"] = 27, ["Core Hound"] = 312, Fox = 319,
}

-- Every Forever pet ability, from the game's own data (build 1.60.1.70862:
-- the hunter pet families' skill lines in SkillLineAbility, each rank's pet level
-- in SpellLevels, its training point cost in SkillLineAbility): the families that
-- learn it, each rank's pet level and cost (0: none), and its first rank's spell,
-- for its name in the game's language. Which ones pet trainers sell isn't in the
-- data: Deadeye reads it from a pet trainer's window (Dex:ReadTrainer).
local ABILITIES = {
	{ name = "Bite", spell = 17253, levels = { 1, 8, 16, 24, 32, 40, 48, 56 }, costs = { 1, 4, 7, 10, 13, 17, 21, 25 },
		families = { "Bat", "Bear", "Boar", "Carrion Bird", "Cat", "Core Hound", "Crocolisk", "Fox", "Gorilla", "Hyena", "Raptor", "Spider", "Tallstrider", "Turtle", "Wind Serpent", "Wolf" } },
	{ name = "Claw", spell = 16827, levels = { 1, 8, 16, 24, 32, 40, 48, 56 }, costs = { 1, 4, 7, 10, 13, 17, 21, 25 },
		families = { "Bear", "Bird of Prey", "Carrion Bird", "Cat", "Crab", "Raptor", "Scorpid" } },
	{ name = "Cower", spell = 1742, levels = { 5, 15, 25, 35, 45, 55 }, costs = { 8, 10, 12, 14, 16, 18 },
		families = ALL },
	{ name = "Dash", spell = 23099, levels = { 30, 40, 50 }, costs = { 15, 20, 25 },
		families = { "Bear", "Boar", "Cat", "Crab", "Crocolisk", "Fox", "Gorilla", "Hyena", "Raptor", "Scorpid", "Spider", "Tallstrider", "Turtle", "Wolf" } },
	{ name = "Dive", spell = 23145, levels = { 30, 40, 50 }, costs = { 15, 20, 25 },
		families = { "Bat", "Bird of Prey", "Carrion Bird", "Wind Serpent" } },
	{ name = "Charge", spell = 7371, levels = { 1, 12, 24, 36, 48, 60 }, costs = { 5, 9, 13, 17, 21, 25 },
		families = { "Boar" } },
	{ name = "Demoralizing Screech", spell = 24423, levels = { 8, 24, 48, 56 }, costs = { 10, 15, 20, 25 },
		families = { "Carrion Bird" } },
	{ name = "Dismember", spell = 1264758, levels = { 12, 24, 36, 48, 60 }, costs = { 1, 1, 1, 1, 1 },
		families = { "Crocolisk" } },
	{ name = "Dust Cloud", spell = 1265899, levels = { 12, 24, 36, 48, 60 }, costs = { 0, 0, 0, 0, 0 },
		families = { "Tallstrider" } },
	{ name = "Furious Howl", spell = 24604, levels = { 10, 24, 40, 56 }, costs = { 10, 15, 20, 25 },
		families = { "Wolf" } },
	{ name = "Lava Breath", spell = 444678, levels = { 48, 48 }, costs = { 0, 0 },
		families = { "Core Hound" } },
	{ name = "Lightning Breath", spell = 24844, levels = { 1, 12, 24, 36, 48, 60 }, costs = { 1, 5, 10, 15, 20, 25 },
		families = { "Wind Serpent" } },
	{ name = "Mine!", spell = 1265054, levels = { 10, 20, 30, 40, 50 }, costs = { 0, 0, 0, 0, 0 },
		families = { "Bird of Prey" } },
	{ name = "Pinch", spell = 1264735, levels = { 12, 24, 36, 48, 60 }, costs = { 0, 0, 0, 0, 0 },
		families = { "Crab" } },
	{ name = "Prowl", spell = 24450, levels = { 30, 40, 50 }, costs = { 15, 20, 25 },
		families = { "Cat" } },
	{ name = "Savage Rend", spell = 1265065, levels = { 12, 24, 36, 48, 60 }, costs = { 0, 0, 0, 0, 0 },
		families = { "Raptor" } },
	{ name = "Scorpid Poison", spell = 24640, levels = { 8, 24, 40, 56 }, costs = { 10, 15, 20, 25 },
		families = { "Scorpid" } },
	{ name = "Shell Shield", spell = 26064, levels = { 20 }, costs = { 15 },
		families = { "Turtle" } },
	{ name = "Sonic Blast", spell = 1264478, levels = { 12, 24, 36, 48, 60 }, costs = { 1, 1, 1, 1, 1 },
		families = { "Bat" } },
	{ name = "Swipe", spell = 1264494, levels = { 12, 24, 36, 48, 60 }, costs = { 0, 0, 0, 0, 0 },
		families = { "Bear" } },
	{ name = "Tendon Rip", spell = 1265038, levels = { 12, 24, 36, 48, 60 }, costs = { 0, 0, 0, 0, 0 },
		families = { "Hyena" } },
	{ name = "Thunderstomp", spell = 26090, levels = { 30, 40, 50, 60 }, costs = { 15, 20, 25, 0 },
		families = { "Gorilla" } },
	{ name = "Trickster's Dance", spell = 1310612, levels = { 20 }, costs = { 10 },
		families = { "Fox" } },
	{ name = "Web", spell = 1265843, levels = { 12, 24, 36, 48, 60 }, costs = { 0, 0, 0, 0, 0 },
		families = { "Spider" } },
	{ name = "Growl", spell = 2649, levels = { 1, 10, 20, 30, 40, 50, 60 }, costs = { 0, 0, 0, 0, 0, 0, 0 },
		families = ALL },
	{ name = "Great Stamina", spell = 4187, levels = { 1, 12, 18, 24, 30, 36, 42, 48, 54, 60 }, costs = { 5, 10, 15, 25, 50, 75, 100, 125, 150, 185 },
		families = ALL },
	{ name = "Natural Armor", spell = 24545, levels = { 1, 12, 18, 24, 30, 36, 42, 48, 54, 60 }, costs = { 1, 5, 10, 15, 25, 50, 75, 100, 125, 150 },
		families = ALL },
	{ name = "Arcane Resistance", spell = 24493, levels = { 20, 30, 40, 50 }, costs = { 5, 15, 45, 90 },
		families = ALL },
	{ name = "Fire Resistance", spell = 23992, levels = { 20, 30, 40, 50 }, costs = { 5, 15, 45, 90 },
		families = ALL },
	{ name = "Frost Resistance", spell = 24446, levels = { 20, 30, 40, 50 }, costs = { 5, 15, 45, 90 },
		families = ALL },
	{ name = "Nature Resistance", spell = 24492, levels = { 20, 30, 40, 50 }, costs = { 5, 15, 45, 90 },
		families = ALL },
	{ name = "Shadow Resistance", spell = 24488, levels = { 20, 30, 40, 40 }, costs = { 5, 15, 45, 90 },
		families = ALL },
}
local ABILITY = {} -- by English name
for _, ability in ipairs(ABILITIES) do
	ABILITY[ability.name] = ability
end

local COLORS = {
	background = { 0.05, 0.05, 0.07, 0.97 },
	titleBar = { 0.11, 0.11, 0.14, 1 },
	border = { 0.28, 0.28, 0.33, 1 },
	ability = { 1, 0.82, 0 },
	rank = { 1, 1, 1 },
	dim = { 0.55, 0.55, 0.55 },
	low = { 1, 0.35, 0.35 }, -- a pet level your pet hasn't reached
	has = { 0.35, 0.9, 0.35 },
	learned = { 0.6, 0.85, 0.45 },
	found = { 1, 0.82, 0 },
	trainer = { 0.55, 0.75, 1 },
	beast = { 0.85, 0.85, 0.85 },
	rare = { 0.75, 0.55, 1 },
}

BINDING_NAME_DEADEYE_DEX = L["Open or close pet abilities"]
_G["BINDING_NAME_CLICK DeadeyeBeastLore:LeftButton"] = L["Beast Lore on your mouseover target"]

---------------------------------------------------------------------------
-- Names: the game's names for families and abilities, in its language
---------------------------------------------------------------------------
local familyByName = {} -- the game's family name -> English name
local abilityByName = {} -- the game's ability name -> English name (or itself)

local function Text(value)
	value = ns.Readable(value)
	if type(value) == "string" and value ~= "" then
		return value
	end
end

local function Number(value)
	value = ns.Readable(value)
	return type(value) == "number" and value or nil
end

-- Abilities have their English names on English clients. Elsewhere the name of
-- their first rank's spell, when the game has it.
local function LocalName(ability)
	if ability.local_ then
		return ability.local_
	end
	local name
	if ability.spell and ns.locale ~= "enUS" and ns.locale ~= "enGB" then
		name = Text(C_Spell.GetSpellName(ability.spell))
	end
	ability.local_ = name or ability.name
	return ability.local_
end

local function LearnNames()
	for key, id in pairs(FAMILY_IDS) do
		familyByName[key] = key
		local info = C_CreatureInfo and C_CreatureInfo.GetCreatureFamilyInfo and C_CreatureInfo.GetCreatureFamilyInfo(id)
		local name = info and Text(info.name)
		if name and not familyByName[name] then
			familyByName[name] = key
		end
	end
	for _, ability in ipairs(ABILITIES) do
		ability.local_ = nil
		abilityByName[ability.name] = ability.name
		abilityByName[LocalName(ability)] = ability.name
	end
end

local function FamilyKey(name)
	name = Text(name)
	return name and familyByName[name] or name
end

local function AbilityKey(name)
	return abilityByName[name] or name
end

local function AbilityName(key)
	local ability = ABILITY[key]
	return ability and LocalName(ability) or key
end

local function Learns(ability, family)
	if ability.families == ALL then
		return true
	end
	for _, name in ipairs(ability.families) do
		if name == family then
			return true
		end
	end
	return false
end

-- The rank in "Rank 2", "Rang 2", "等级 2".
local function RankOf(text)
	text = Text(text)
	return text and tonumber(text:match("%d+")) or nil
end

---------------------------------------------------------------------------
-- What the game tells: units, positions, spellbooks
---------------------------------------------------------------------------
local function NpcID(unit)
	local guid = Text(UnitGUID(unit))
	local kind, id = (guid or ""):match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)")
	if kind == "Creature" then
		return tonumber(id)
	end
end

-- A beast out in the world: name, level, family and whether it's rare. Nothing
-- for players and their pets.
local function ReadBeast(unit)
	if not UnitExists(unit) or ns.Readable(UnitPlayerControlled(unit)) ~= false then
		return nil
	end
	local name = Text(UnitName(unit))
	if not name then
		return nil
	end
	local level = Number(UnitLevel(unit))
	local class = Text(UnitClassification(unit))
	return {
		id = NpcID(unit), name = name, family = FamilyKey(UnitCreatureFamily(unit)),
		level = level and level > 0 and level or nil,
		rare = (class == "rare" or class == "rareelite") or nil,
		elite = (class == "elite" or class == "rareelite" or class == "worldboss") or nil,
	}
end

local function Round(value)
	return math.floor(value * 1000 + 0.5) / 1000
end

-- Where you stand: the map, your position on it (none in dungeons) and the zone.
local function CurrentSpot()
	local map = C_Map and Number(C_Map.GetBestMapForUnit("player"))
	if not map then
		return nil
	end
	local info = C_Map.GetMapInfo(map)
	local spot = { map = map, zone = info and Text(info.name) }
	local position = C_Map.GetPlayerMapPosition(map, "player")
	if position then
		local x, y = position:GetXY()
		x, y = Number(x), Number(y)
		if x and y and (x > 0 or y > 0) then
			spot.x, spot.y = Round(x), Round(y)
		end
	end
	return spot
end

local PET_BANK = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet or "pet"

-- The pet's abilities from its spellbook: { [ability] = rank }.
local function PetAbilities()
	local abilities = {}
	local count
	if C_SpellBook and C_SpellBook.HasPetSpells then
		count = C_SpellBook.HasPetSpells()
	elseif HasPetSpells then
		count = HasPetSpells()
	end
	count = Number(count)
	for index = 1, count or 0 do
		local name, sub
		if C_SpellBook and C_SpellBook.GetSpellBookItemName then
			name, sub = C_SpellBook.GetSpellBookItemName(index, PET_BANK)
		else
			name, sub = GetSpellBookItemName(index, "pet")
		end
		name = Text(name)
		if name then
			local key = AbilityKey(name)
			-- One-rank abilities may come without "Rank 1".
			local rank = RankOf(sub) or (ABILITY[key] and 1)
			if rank and (abilities[key] or 0) < rank then
				abilities[key] = rank
			end
		end
	end
	return abilities
end

-- Abilities on a tooltip's lines: each name the game uses for one, with the
-- first number after it before the next comma ("Bite 3, Claw (Rank 2)"). A name
-- without a number counts only for one-rank abilities ("Shell Shield, Bite 3").
-- The first line is the beast's own name, which can hold an ability's ("Ice
-- Claw Bear"). Names are matched as written, so "Frostbite" isn't Bite.
local function ParseAbilities(lines)
	local found, any = {}, false
	for index = 2, #lines do
		local text = lines[index]
		for name, key in pairs(abilityByName) do
			local start, finish = text:find(name, 1, true)
			if start then
				local after = text:sub(finish + 1):match("^[^,;]*") or ""
				local rank = tonumber(after:sub(1, 24):match("%d+") or "")
				if not rank and ABILITY[key] and #ABILITY[key].levels == 1 and not after:find("^%a") then
					rank = 1
				end
				if rank and rank >= 1 and rank <= RANK_LIMIT and (found[key] or 0) < rank then
					found[key], any = rank, true
				end
			end
		end
	end
	return any and found or nil
end

local function TooltipLines(unit)
	local lines = {}
	local data = C_TooltipInfo and C_TooltipInfo.GetUnit and C_TooltipInfo.GetUnit(unit)
	for _, line in ipairs(data and data.lines or {}) do
		local left, right = Text(line.leftText), Text(line.rightText)
		if left or right then
			lines[#lines + 1] = (left or "") .. (right and (" " .. right) or "")
		end
	end
	return lines
end

local function CharacterKey()
	local name = Text(UnitName("player")) or "?"
	local realm = GetRealmName and Text(GetRealmName())
	return realm and (name .. "-" .. realm) or name
end

local function Ago(seconds)
	if seconds < 3600 then
		return L["%d min ago"]:format(math.max(1, math.floor(seconds / 60)))
	elseif seconds < 86400 then
		return L["%d h ago"]:format(math.floor(seconds / 3600))
	end
	return L["%d days ago"]:format(math.floor(seconds / 86400))
end

---------------------------------------------------------------------------
-- The saved beasts (DeadeyeDB.dex, kept when settings are reset)
---------------------------------------------------------------------------
local function Store()
	local store = ns.db.dex
	if type(store) ~= "table" then
		store = {}
		ns.db.dex = store
	end
	store.beasts = type(store.beasts) == "table" and store.beasts or {}
	store.learned = type(store.learned) == "table" and store.learned or {}
	store.trainer = type(store.trainer) == "table" and store.trainer or {} -- [ability] = true: pet trainers sell it
	return store
end

local function SoldByTrainer(ability)
	return Store().trainer[ability] == true
end

local function AddSpot(beast, spot)
	if not spot then
		return
	end
	beast.zone = spot.zone or beast.zone
	if not spot.x then
		return
	end
	for _, saved in ipairs(beast.spots) do
		if saved.map == spot.map and saved.x and math.abs(saved.x - spot.x) < SAME_SPOT and math.abs(saved.y - spot.y) < SAME_SPOT then
			return
		end
	end
	table.insert(beast.spots, 1, { map = spot.map, x = spot.x, y = spot.y, zone = spot.zone })
	while #beast.spots > SPOTS_PER_BEAST do
		table.remove(beast.spots)
	end
end

-- Saves a beast, what it teaches and where you are. Returns the abilities it
-- teaches that weren't saved for it before ({ [ability] = rank } or nil), and
-- whether the beast itself is new.
function Dex:Save(info, abilities, spot)
	local beasts = Store().beasts
	local key = info.id or ("name:" .. info.name)
	local beast = beasts[key]
	local isNew = beast == nil
	if isNew then
		beast = { abilities = {}, spots = {} }
		beasts[key] = beast
	end
	beast.id, beast.name = info.id, info.name
	beast.family = info.family or beast.family
	if info.level then
		beast.minLevel = math.min(beast.minLevel or info.level, info.level)
		beast.maxLevel = math.max(beast.maxLevel or info.level, info.level)
	end
	beast.rare = beast.rare or info.rare
	beast.elite = beast.elite or info.elite
	beast.seen = GetServerTime()
	local added
	for ability, rank in pairs(abilities or {}) do
		-- What pet trainers sell, a tamed beast doesn't teach (it came with Growl).
		if not SoldByTrainer(ability) and (beast.abilities[ability] or 0) < rank then
			beast.abilities[ability] = rank
			added = added or {}
			added[ability] = rank
		end
	end
	AddSpot(beast, spot)
	self:Changed()
	return added, isNew
end

local function AbilityList(abilities)
	local parts = {}
	for ability, rank in pairs(abilities) do
		parts[#parts + 1] = AbilityName(ability) .. " " .. rank
	end
	table.sort(parts)
	return table.concat(parts, ", ")
end

function Dex:Forget()
	local store = Store()
	store.beasts = {}
	self.focus = nil
	self:Changed()
end

---------------------------------------------------------------------------
-- Beast Lore, taming and rare beasts
---------------------------------------------------------------------------
-- The spell by its Classic ID, or by its name, in case Forever numbers it
-- differently.
local function SpellIs(spellID, id, english)
	if spellID == id then
		return true
	end
	local name = spellID and Text(C_Spell.GetSpellName(spellID))
	return name ~= nil and (name == Text(C_Spell.GetSpellName(id)) or name == english)
end

function Dex:UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	spellID = Number(spellID)
	if SpellIs(spellID, BEAST_LORE, "Beast Lore") then
		self:BeastLore()
	elseif SpellIs(spellID, TAME_BEAST, "Tame Beast") then
		self:StartTaming()
	end
end

function Dex:UNIT_SPELLCAST_CHANNEL_START(_, _, spellID)
	if SpellIs(Number(spellID), TAME_BEAST, "Tame Beast") then
		self:StartTaming()
	end
end

-- The tooltip of the beast you cast Beast Lore on, read a few times while the
-- game fills it in. A beast whose abilities can't be read is still saved where
-- you found it.
function Dex:BeastLore()
	if not self.db.record then
		return
	end
	local info = ReadBeast("target")
	if not info then
		return
	end
	local lore = { info = info, spot = CurrentSpot(), guid = Text(UnitGUID("target")) }
	self.lore = lore
	for index, delay in ipairs(LORE_READS) do
		local last = index == #LORE_READS
		local function Read()
			self:ReadLore(lore, last)
		end
		if delay == 0 then
			Read()
		else
			C_Timer.After(delay, Read)
		end
	end
end

function Dex:ReadLore(lore, last)
	if self.lore ~= lore then
		return
	end
	local sameTarget = UnitExists("target") and Text(UnitGUID("target")) == lore.guid
	local abilities = sameTarget and ParseAbilities(TooltipLines("target"))
	if abilities then
		self.lore = nil
		local added, isNew = self:Save(lore.info, abilities, lore.spot)
		if added then
			ns.Print(L["Saved %s: teaches %s."]:format(lore.info.name, AbilityList(added)))
		elseif isNew then
			ns.Print(L["Saved %s."]:format(lore.info.name))
		end
	elseif last then
		self.lore = nil
		local _, isNew = self:Save(lore.info, nil, lore.spot)
		if isNew and not self.loreHintShown then
			self.loreHintShown = true
			ns.Print(L["Saved %s, but Deadeye couldn't read its abilities from Beast Lore. If Beast Lore lists some, target it and type /deadeye dex lore, and send the lines it prints to Deadeye's author."]:format(lore.info.name))
		end
	end
end

-- Tame Beast takes a while: the beast is noted as the cast starts, and its
-- abilities read from the new pet's spellbook.
function Dex:StartTaming()
	if not self.db.record then
		return
	end
	local info = ReadBeast("target")
	if info then
		self.taming = { info = info, spot = CurrentSpot(), untilTime = GetTime() + TAME_SECONDS }
	end
end

function Dex:ReadTamed()
	local taming = self.taming
	if not taming or GetTime() > taming.untilTime then
		self.taming = nil
		return
	end
	if not UnitExists("pet") or Text(UnitName("pet")) ~= taming.info.name then
		return -- not the beast you tamed (yet)
	end
	local abilities = PetAbilities()
	if next(abilities) == nil then
		return -- its spellbook isn't in yet
	end
	self.taming = nil
	local added = self:Save(taming.info, abilities, taming.spot)
	if added then
		ns.Print(L["Saved %s: teaches %s."]:format(taming.info.name, AbilityList(added)))
	end
end

function Dex:SeeUnit(unit)
	if not (self.db.record and self.db.rares) then
		return
	end
	local class = Text(UnitClassification(unit))
	if class ~= "rare" and class ~= "rareelite" then
		return
	end
	local info = ReadBeast(unit)
	if not (info and info.family) then
		return
	end
	local key = info.id or info.name
	local now = GetTime()
	self.seenAt = self.seenAt or {}
	if self.seenAt[key] and now - self.seenAt[key] < SEEN_SECONDS then
		return
	end
	self.seenAt[key] = now
	local _, isNew = self:Save(info, nil, CurrentSpot())
	if isNew then
		ns.Print(L["Rare beast saved: %s (%s)."]:format(info.name, info.family))
	end
end

function Dex:PLAYER_TARGET_CHANGED()
	self:SeeUnit("target")
end

function Dex:UPDATE_MOUSEOVER_UNIT()
	self:SeeUnit("mouseover")
end

function Dex:NAME_PLATE_UNIT_ADDED(unit)
	self:SeeUnit(unit)
end

---------------------------------------------------------------------------
-- Your pet and Beast Training
---------------------------------------------------------------------------
function Dex:PetFamily()
	return UnitExists("pet") and FamilyKey(UnitCreatureFamily("pet")) or nil
end

function Dex:ReadPet()
	if UnitExists("pet") then
		self.petAbilities = PetAbilities()
		-- Another pet: its level is where level-ups count from. (A GUID hidden in
		-- combat isn't taken for another pet.)
		local guid = Text(UnitGUID("pet"))
		if (guid and guid ~= self.petGUID) or not self.petLevel then
			self.petGUID = guid or self.petGUID
			self.petLevel = Number(UnitLevel("pet"))
		end
	else
		self.petAbilities, self.petGUID, self.petLevel = {}, nil, nil
	end
	self:ReadTamed()
	self:Changed()
end

Dex.UNIT_PET = Dex.ReadPet
Dex.PET_BAR_UPDATE = Dex.ReadPet
Dex.SPELLS_CHANGED = Dex.ReadPet

-- Your pet reached a level with new ranks for its family: which ones, and
-- whether you've found a beast that teaches each.
function Dex:UNIT_LEVEL()
	local level = UnitExists("pet") and Number(UnitLevel("pet"))
	local before = self.petLevel
	self.petLevel = level or before
	if not (self.db.upgradeAlert and level and before and level > before) then
		return
	end
	local family = self:PetFamily()
	local teachers = self:Teachers()
	for _, ability in ipairs(ABILITIES) do
		if family and Learns(ability, family) then
			local newRank
			for rank, needed in ipairs(ability.levels) do
				if needed > before and needed <= level then
					newRank = rank
				end
			end
			if newRank and (self.petAbilities[ability.name] or 0) < newRank then
				local count = #(teachers[ability.name] and teachers[ability.name][newRank] or {})
				local name = Text(UnitName("pet")) or L["Your pet"]
				local where = L["You haven't found where to learn it yet."]
				if SoldByTrainer(ability.name) then
					where = L["Pet trainers sell it."]
				elseif count > 0 then
					where = L["%d of the beasts you've found teach it (/deadeye dex)."]:format(count)
				end
				ns.Print(L["%s can learn %s %d now."]:format(name, LocalName(ability), newRank) .. " " .. where)
			end
		end
	end
end

-- The ranks this hunter learned, from the Beast Training window.
function Dex:ReadBeastTraining()
	if not (GetNumCrafts and GetCraftInfo) then
		return
	end
	local line = GetCraftDisplaySkillLine and Text(GetCraftDisplaySkillLine())
	local beastTraining = Text(C_Spell.GetSpellName(BEAST_TRAINING))
	if line and beastTraining and line ~= beastTraining then
		return -- another craft's window
	end
	local learned = {}
	for index = 1, Number(GetNumCrafts()) or 0 do
		local name, sub, kind = GetCraftInfo(index)
		name = Text(name)
		if name and kind ~= "header" then
			local key = AbilityKey(name)
			local rank = RankOf(sub) or (ABILITY[key] and 1)
			if rank then
				learned[key] = learned[key] or {}
				learned[key][rank] = true
			end
		end
	end
	Store().learned[CharacterKey()] = learned
	self:Changed()
end

Dex.CRAFT_SHOW = Dex.ReadBeastTraining
Dex.CRAFT_UPDATE = Dex.ReadBeastTraining

-- The abilities a pet trainer sells, from its window. The game's data doesn't
-- say which abilities trainers sell and which beasts teach.
function Dex:ReadTrainer()
	if not (GetNumTrainerServices and GetTrainerServiceInfo) then
		return
	end
	local beastTraining = Text(C_Spell.GetSpellName(BEAST_TRAINING))
	local sold = Store().trainer
	local changed = false
	for index = 1, Number(GetNumTrainerServices()) or 0 do
		local name, _, kind = GetTrainerServiceInfo(index)
		local key = AbilityKey(Text(name) or "")
		local line = GetTrainerServiceSkillLine and Text(GetTrainerServiceSkillLine(index))
		if kind ~= "header" and ABILITY[key] and not (line and beastTraining and line ~= beastTraining) and not sold[key] then
			sold[key], changed = true, true
		end
	end
	if changed then
		self:Changed()
	end
end

Dex.TRAINER_SHOW = Dex.ReadTrainer
Dex.TRAINER_UPDATE = Dex.ReadTrainer

---------------------------------------------------------------------------
-- The dex: rows for the window
---------------------------------------------------------------------------
-- The beasts you found for each rank: teachers[ability][rank] = { beast, ... }.
function Dex:Teachers()
	local teachers = {}
	for _, beast in pairs(Store().beasts) do
		for ability, rank in pairs(beast.abilities) do
			teachers[ability] = teachers[ability] or {}
			teachers[ability][rank] = teachers[ability][rank] or {}
			table.insert(teachers[ability][rank], beast)
		end
	end
	for _, ranks in pairs(teachers) do
		for _, list in pairs(ranks) do
			table.sort(list, function(a, b)
				if (a.minLevel or 0) ~= (b.minLevel or 0) then
					return (a.minLevel or 0) < (b.minLevel or 0)
				end
				return a.name < b.name
			end)
		end
	end
	return teachers
end

function Dex:Learned()
	return Store().learned[CharacterKey()] or {}
end

-- Ranks you have found, out of every one there is: a beast that teaches it, a
-- pet trainer that sells it, or learned in Beast Training.
function Dex:Progress()
	local teachers, learned = self:Teachers(), self:Learned()
	local found, total = 0, 0
	for _, ability in ipairs(ABILITIES) do
		local sold = SoldByTrainer(ability.name)
		for rank in ipairs(ability.levels) do
			total = total + 1
			if sold or (teachers[ability.name] and teachers[ability.name][rank]) or (learned[ability.name] and learned[ability.name][rank]) then
				found = found + 1
			end
		end
	end
	return found, total
end

local function BeastSort(a, b)
	if (a.minLevel or 0) ~= (b.minLevel or 0) then
		return (a.minLevel or 0) < (b.minLevel or 0)
	end
	return a.name < b.name
end

-- view: "pet" (your pet's family), "all" or "rares".
function Dex:Rows(view)
	local rows = {}
	if view == "rares" then
		local rares = {}
		for _, beast in pairs(Store().beasts) do
			if beast.rare then
				rares[#rares + 1] = beast
			end
		end
		table.sort(rares, BeastSort)
		for _, beast in ipairs(rares) do
			rows[#rows + 1] = { kind = "beast", beast = beast }
		end
		if #rares == 0 then
			rows[1] = { kind = "note", text = L["No rare beasts yet. Target or mouse over one and Deadeye saves where you saw it."] }
		end
		return rows
	end
	local family = view == "pet" and self:PetFamily() or nil
	if view == "pet" and not family then
		rows[1] = { kind = "note", text = L["No pet out: showing every ability."] }
	end
	local teachers = self:Teachers()
	for _, ability in ipairs(ABILITIES) do
		if not family or Learns(ability, family) then
			local sold = SoldByTrainer(ability.name)
			rows[#rows + 1] = { kind = "ability", ability = ability.name, text = LocalName(ability), trainer = sold }
			for rank, level in ipairs(ability.levels) do
				rows[#rows + 1] = { kind = "rank", ability = ability.name, rank = rank, level = level,
					cost = ability.costs and ability.costs[rank] or 0, trainer = sold }
				for _, beast in ipairs(not sold and teachers[ability.name] and teachers[ability.name][rank] or {}) do
					rows[#rows + 1] = { kind = "beast", beast = beast, ability = ability.name, rank = rank }
				end
			end
		end
	end
	-- Abilities Deadeye doesn't know by name: new ones, or names in another language.
	if not family then
		local others = {}
		for name in pairs(teachers) do
			if not ABILITY[name] then
				others[#others + 1] = name
			end
		end
		table.sort(others)
		for _, name in ipairs(others) do
			rows[#rows + 1] = { kind = "ability", ability = name, text = name }
			local ranks = {}
			for rank in pairs(teachers[name]) do
				ranks[#ranks + 1] = rank
			end
			table.sort(ranks)
			for _, rank in ipairs(ranks) do
				rows[#rows + 1] = { kind = "rank", ability = name, rank = rank, cost = 0 }
				for _, beast in ipairs(teachers[name][rank]) do
					rows[#rows + 1] = { kind = "beast", beast = beast, ability = name, rank = rank }
				end
			end
		end
	end
	return rows
end

-- What a rank row says on the right, and its color.
function Dex:RankStatus(row, teachers, learned)
	local petRank = self.petAbilities and self.petAbilities[row.ability]
	if petRank and petRank >= row.rank then
		return L["Your pet has it"], COLORS.has
	elseif learned[row.ability] and learned[row.ability][row.rank] then
		return L["Learned"], COLORS.learned
	elseif row.trainer then
		return L["Pet trainer"], COLORS.trainer
	end
	local count = #(teachers[row.ability] and teachers[row.ability][row.rank] or {})
	if count > 0 then
		return L["%d found"]:format(count), COLORS.found
	end
	return L["Not found yet"], COLORS.dim
end

local function BeastLevels(beast)
	if not beast.minLevel then
		return ""
	elseif beast.minLevel == beast.maxLevel then
		return tostring(beast.minLevel)
	end
	return beast.minLevel .. "-" .. beast.maxLevel
end

function Dex:BeastLine(beast)
	local tags = {}
	if beast.rare then
		tags[#tags + 1] = L["rare"]
	elseif beast.elite then
		tags[#tags + 1] = L["elite"]
	end
	local text = beast.name
	local levels = BeastLevels(beast)
	if levels ~= "" then
		text = text .. "  " .. levels
	end
	if #tags > 0 then
		text = text .. "  (" .. table.concat(tags, ", ") .. ")"
	end
	return text
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local function Fill(frame, layer, color)
	local texture = frame:CreateTexture(nil, layer)
	texture:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
	return texture
end

local function Font(parent, template, justify)
	local text = parent:CreateFontString(nil, "OVERLAY", template)
	text:SetJustifyH(justify or "LEFT")
	text:SetWordWrap(false)
	return text
end

function Dex:BuildWindow()
	local frame = CreateFrame("Frame", "DeadeyeDexFrame", UIParent)
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("HIGH")
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	frame:Hide()
	frame:SetScript("OnShow", function()
		self:Refresh()
	end)
	if UISpecialFrames then
		table.insert(UISpecialFrames, frame:GetName())
	end
	Fill(frame, "BACKGROUND", COLORS.background):SetAllPoints()
	local titleBar = Fill(frame, "ARTWORK", COLORS.titleBar)
	titleBar:SetPoint("TOPLEFT", 1, -1)
	titleBar:SetPoint("TOPRIGHT", -1, -1)
	titleBar:SetHeight(32)
	local title = Font(frame, "GameFontNormalLarge")
	title:SetPoint("LEFT", titleBar, "LEFT", PADDING, 0)
	title:SetText(L["Pet abilities"])
	local progress = Font(frame, "GameFontDisableSmall")
	progress:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 10, 1)
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("RIGHT", titleBar, "RIGHT", -4, 0)
	close:SetScript("OnClick", function()
		frame:Hide()
	end)

	local tabs = {}
	for index, tab in ipairs({ { "pet", L["Your pet"] }, { "all", L["All abilities"] }, { "rares", L["Rares"] } }) do
		local button = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
		button:SetSize(130, 22)
		button:SetPoint("TOPLEFT", PADDING + (index - 1) * 136, -42)
		button:SetText(tab[2])
		button:SetScript("OnClick", function()
			self.view, self.offset = tab[1], 0
			self:Refresh()
		end)
		button.view = tab[1]
		tabs[index] = button
	end
	local heading = Font(frame, "GameFontHighlight")
	heading:SetPoint("TOPLEFT", PADDING, -74)
	heading:SetPoint("RIGHT", -PADDING, 0)

	local list = CreateFrame("Frame", nil, frame)
	list:SetPoint("TOPLEFT", PADDING, -96)
	list:SetSize(WIDTH - PADDING * 2, ROWS * ROW_HEIGHT)
	list:EnableMouseWheel(true)
	list:SetScript("OnMouseWheel", function(_, delta)
		self:Scroll(-delta * 3)
	end)
	local rows = {}
	for index = 1, ROWS do
		local row = CreateFrame("Button", nil, list)
		row:SetSize(WIDTH - PADDING * 2, ROW_HEIGHT)
		row:SetPoint("TOPLEFT", 0, -(index - 1) * ROW_HEIGHT)
		local highlight = row:CreateTexture(nil, "HIGHLIGHT")
		highlight:SetAllPoints()
		highlight:SetColorTexture(1, 1, 1, 0.07)
		row.left = Font(row, "GameFontHighlight")
		row.left:SetPoint("LEFT", 4, 0)
		row.middle = Font(row, "GameFontHighlightSmall")
		row.middle:SetPoint("LEFT", 190, 0)
		row.right = Font(row, "GameFontHighlightSmall", "RIGHT")
		row.right:SetPoint("RIGHT", -4, 0)
		row:SetScript("OnClick", function(button)
			if button.entry and button.entry.beast then
				self:ShowOnMap(button.entry.beast)
			end
		end)
		row:SetScript("OnEnter", function(button)
			self:ShowBeastTooltip(button, button.entry and button.entry.beast)
		end)
		row:SetScript("OnLeave", function()
			GameTooltip:Hide()
		end)
		rows[index] = row
	end
	local more = Font(frame, "GameFontDisableSmall", "RIGHT")
	more:SetPoint("TOPRIGHT", list, "BOTTOMRIGHT", -4, -4)
	local hint = Font(frame, "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", PADDING, 12)
	hint:SetPoint("RIGHT", -PADDING, 0)
	hint:SetWordWrap(true)
	hint:SetText(L["Cast Beast Lore on a beast to save what it teaches. Click a beast to see it on your map."])

	self.frame, self.tabs, self.rows, self.list = frame, tabs, rows, list
	self.progressText, self.heading, self.moreText = progress, heading, more
	self.view, self.offset = self.view or "pet", 0
end

function Dex:Scroll(by)
	self.offset = math.max(0, math.min((self.offset or 0) + by, math.max(0, #(self.entries or {}) - ROWS)))
	self:DrawRows()
end

function Dex:Refresh()
	local frame = self.frame
	if not (frame and frame:IsShown()) then
		return
	end
	local found, total = self:Progress()
	self.progressText:SetText(L["%d of %d ranks found"]:format(found, total))
	for _, tab in ipairs(self.tabs) do
		tab:SetEnabled(tab.view ~= self.view)
	end
	local heading = ""
	if self.view == "pet" and UnitExists("pet") then
		local family = UnitCreatureFamily("pet")
		heading = L["%s: %s, level %d"]:format(Text(UnitName("pet")) or L["Your pet"], Text(family) or "?", self.petLevel or 0)
	elseif self.view == "rares" then
		heading = L["Rare beasts you've seen"]
	end
	self.heading:SetText(heading)
	self.entries = self:Rows(self.view)
	self.teachers, self.learned = self:Teachers(), self:Learned()
	self:Scroll(0)
end

function Dex:DrawRows()
	local entries, offset = self.entries or {}, self.offset or 0
	local now = GetServerTime()
	local petLevel = UnitExists("pet") and self.petLevel or nil
	for index, row in ipairs(self.rows) do
		local entry = entries[offset + index]
		row.entry = entry
		if entry then
			row.middle:SetText("")
			row.right:SetText("")
			if entry.kind == "ability" then
				row.left:SetText(entry.text)
				row.left:SetTextColor(COLORS.ability[1], COLORS.ability[2], COLORS.ability[3])
			elseif entry.kind == "rank" then
				row.left:SetText("   " .. L["Rank %d"]:format(entry.rank))
				row.left:SetTextColor(COLORS.rank[1], COLORS.rank[2], COLORS.rank[3])
				if entry.level then
					local text = L["pet level %d"]:format(entry.level)
					if entry.cost > 0 then
						text = text .. "  \194\183  " .. L["%d TP"]:format(entry.cost)
					end
					row.middle:SetText(text)
					local color = petLevel and petLevel < entry.level and COLORS.low or COLORS.dim
					row.middle:SetTextColor(color[1], color[2], color[3])
				end
				local status, color = self:RankStatus(entry, self.teachers, self.learned)
				row.right:SetText(status)
				row.right:SetTextColor(color[1], color[2], color[3])
			elseif entry.kind == "beast" then
				local beast = entry.beast
				row.left:SetText("      " .. self:BeastLine(beast))
				local color = beast.rare and COLORS.rare or COLORS.beast
				row.left:SetTextColor(color[1], color[2], color[3])
				row.middle:SetText("")
				local where = beast.zone or ""
				if not entry.ability and beast.seen then
					where = where .. "  \194\183  " .. Ago(math.max(0, now - beast.seen))
				end
				row.right:SetText(where)
				row.right:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
			else
				row.left:SetText(entry.text)
				row.left:SetTextColor(COLORS.dim[1], COLORS.dim[2], COLORS.dim[3])
			end
			row:Show()
		else
			row:Hide()
		end
	end
	local below = #entries - offset - ROWS
	self.moreText:SetText(below > 0 and L["%d more below: scroll"]:format(below) or "")
end

function Dex:ShowBeastTooltip(owner, beast)
	if not beast then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(beast.name)
	local family = beast.family and (beast.family .. "  ") or ""
	GameTooltip:AddLine(family .. BeastLevels(beast), 1, 1, 1)
	if next(beast.abilities) then
		GameTooltip:AddLine(L["Teaches: %s"]:format(AbilityList(beast.abilities)), 1, 0.82, 0)
	end
	if beast.zone then
		GameTooltip:AddLine(beast.zone, 0.7, 0.7, 0.7)
	end
	if beast.seen then
		GameTooltip:AddLine(L["Last seen %s"]:format(Ago(math.max(0, GetServerTime() - beast.seen))), 0.7, 0.7, 0.7)
	end
	GameTooltip:AddLine(L["Click: show it on the map"], 0.35, 0.9, 0.35)
	GameTooltip:Show()
end

function Dex:Changed()
	if self.frame and self.frame:IsShown() then
		self:Refresh()
	end
	self:UpdatePins()
end

function Dex:Open(view)
	if not self.frame then
		self:BuildWindow()
	end
	if view then
		self.view, self.offset = view, 0
	end
	if self.frame:IsShown() then
		self:Refresh()
	else
		self.frame:Show()
	end
end

function Dex:Toggle()
	if self.frame and self.frame:IsShown() then
		self.frame:Hide()
	else
		self:Open()
	end
end

function Deadeye_ToggleDex()
	if Dex.enabled then
		Dex:Toggle()
	end
end

---------------------------------------------------------------------------
-- The map
---------------------------------------------------------------------------
-- The spot to head for: one on your map if there is one.
local function BestSpot(beast)
	local here = C_Map and Number(C_Map.GetBestMapForUnit("player"))
	local first
	for _, spot in ipairs(beast.spots) do
		if spot.x then
			if spot.map == here then
				return spot
			end
			first = first or spot
		end
	end
	return first
end

function Dex:ShowOnMap(beast)
	local spot = BestSpot(beast)
	if not spot then
		ns.Print(L["No map position saved for %s (found in %s)."]:format(beast.name, beast.zone or "?"))
		return
	end
	self.focus = beast
	if self.db.tomtom and TomTom and TomTom.AddWaypoint then
		TomTom:AddWaypoint(spot.map, spot.x, spot.y, { title = beast.name, from = "Deadeye", persistent = false })
	elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint and C_Map.CanSetUserWaypointOnMap and C_Map.CanSetUserWaypointOnMap(spot.map) then
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(spot.map, spot.x, spot.y))
		if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
			C_SuperTrack.SetSuperTrackedUserWaypoint(true)
		end
	end
	if not WorldMapFrame then
		return
	end
	self:HookMap()
	if InCombatLockdown() then
		ns.Print(L["Open your map to see %s: Deadeye can't open it for you in combat."]:format(beast.name))
	else
		if not WorldMapFrame:IsShown() then
			ShowUIPanel(WorldMapFrame)
		end
		WorldMapFrame:SetMapID(spot.map)
	end
	self:UpdatePins()
end

function Dex:HookMap()
	if self.mapHooked or not (WorldMapFrame and WorldMapFrame.GetCanvas) then
		return
	end
	self.mapHooked = true
	local function Update()
		self:UpdatePins()
	end
	for _, method in ipairs({ "OnMapChanged", "OnShow", "OnCanvasScaleChanged" }) do
		if WorldMapFrame[method] then
			hooksecurefunc(WorldMapFrame, method, Update)
		end
	end
end

local function NewPin(canvas)
	local pin = CreateFrame("Button", nil, canvas)
	pin:SetSize(18, 18)
	pin:SetFrameLevel(2400)
	pin.icon = pin:CreateTexture(nil, "OVERLAY")
	pin.icon:SetAllPoints()
	pin.icon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTaming")
	pin:SetScript("OnEnter", function(button)
		Dex:ShowBeastTooltip(button, button.beast)
	end)
	pin:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return pin
end

-- Pins on the shown map for the beast you clicked, or for every beast you've
-- found. They sit on the map's canvas, scaled against its zoom.
function Dex:UpdatePins()
	if not (WorldMapFrame and WorldMapFrame.GetCanvas and self.mapHooked) then
		return
	end
	self.pins = self.pins or {}
	for _, pin in ipairs(self.pins) do
		pin:Hide()
	end
	if not WorldMapFrame:IsShown() then
		return
	end
	local beasts = {}
	if self.db.allPins then
		for _, beast in pairs(Store().beasts) do
			beasts[#beasts + 1] = beast
		end
	elseif self.focus then
		beasts[1] = self.focus
	end
	local mapID = WorldMapFrame:GetMapID()
	local canvas = WorldMapFrame:GetCanvas()
	local width, height = canvas:GetWidth(), canvas:GetHeight()
	local container = WorldMapFrame.ScrollContainer
	local zoom = container and container.GetCanvasScale and Number(container:GetCanvasScale()) or 1
	local scale = 1 / math.max(zoom, 0.1)
	local used = 0
	for _, beast in ipairs(beasts) do
		for _, spot in ipairs(beast.spots) do
			if spot.map == mapID and spot.x then
				used = used + 1
				local pin = self.pins[used] or NewPin(canvas)
				self.pins[used] = pin
				pin.beast = beast
				pin:SetScale(scale)
				pin:ClearAllPoints()
				pin:SetPoint("CENTER", canvas, "TOPLEFT", spot.x * width / scale, -spot.y * height / scale)
				pin.icon:SetVertexColor(1, 1, 1)
				if beast ~= self.focus and self.focus then
					pin.icon:SetVertexColor(0.6, 0.6, 0.6)
				end
				pin:Show()
			end
		end
	end
end

---------------------------------------------------------------------------
-- The Beast Lore key (Key Bindings > AddOns > Deadeye)
---------------------------------------------------------------------------
-- A hidden secure button that casts Beast Lore on your mouseover target, or your
-- target. Made out of combat, so after a reload mid-fight it waits.
function Dex:BuildLoreKey()
	if self.loreKey or InCombatLockdown() then
		return
	end
	local name = Text(C_Spell.GetSpellName(BEAST_LORE)) or "Beast Lore"
	local button = CreateFrame("Button", "DeadeyeBeastLore", UIParent, "SecureActionButtonTemplate")
	button:SetSize(1, 1)
	button:SetPoint("TOPLEFT")
	button:SetAlpha(0)
	button:EnableMouse(false)
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("useOnKeyDown", true)
	button:SetAttribute("type", "macro")
	button:SetAttribute("macrotext", "/cast [@mouseover,exists,nodead][] " .. name)
	self.loreKey = button
end

function Dex:PLAYER_REGEN_ENABLED()
	self:BuildLoreKey()
end

---------------------------------------------------------------------------
-- Diagnostics: /deadeye dex lore
---------------------------------------------------------------------------
function Dex:PrintLore()
	if not UnitExists("target") then
		ns.Print(L["Target a beast you cast Beast Lore on, then type this again."])
		return
	end
	local lines = TooltipLines("target")
	ns.Print(L["Your target's tooltip, %d lines:"]:format(#lines))
	for index, line in ipairs(lines) do
		print(string.format("  %d: %s", index, line))
	end
	local abilities = ParseAbilities(lines)
	ns.Print(abilities and L["Read as: %s"]:format(AbilityList(abilities)) or L["No abilities read."])
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
function Dex:ShouldEnable()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

function Dex:OnEnable()
	Store()
	LearnNames()
	self.petAbilities = {}
	local events = ns.CreateEventFrame(self)
	for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "NAME_PLATE_UNIT_ADDED",
		"PET_BAR_UPDATE", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED" }) do
		events:RegisterEvent(event)
	end
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	events:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", "player")
	events:RegisterUnitEvent("UNIT_PET", "player")
	events:RegisterUnitEvent("UNIT_LEVEL", "pet")
	-- Beast Training's window is a craft on Classic clients; others may not have these.
	for _, event in ipairs({ "CRAFT_SHOW", "CRAFT_UPDATE", "TRAINER_SHOW", "TRAINER_UPDATE" }) do
		pcall(events.RegisterEvent, events, event)
	end
	self.events = events
	self:BuildLoreKey()
	self:HookMap()
	self:ReadPet()
	-- "/deadeye dex" opens the window; its settings keep their commands.
	ns:RegisterCommand("dex", "dex", L["Open pet abilities: every rank and the beasts you've found that teach it (/deadeye dex settings lists its settings)."], function(text)
		self:Command(text)
	end)
end

function Dex:Command(text)
	local name, value = (text or ""):match("^%s*(%S*)%s*(.-)%s*$")
	name = name:lower()
	if name == "" then
		self:Toggle()
	elseif name == "lore" then
		self:PrintLore()
	elseif name == "rares" and value == "" then
		self:Open("rares")
	elseif name == "forget" then
		self:ConfirmForget()
	elseif name == "settings" or name == "list" then
		ns.Slash.List(self)
	elseif not ns.Slash.Handle(self, name, value) then
		ns.Print(L["No %s setting called '%s'. Type /deadeye %s settings."]:format("dex", name, "dex"))
	end
end

function Dex:OnOptionChanged(key)
	if key == "allPins" then
		self:UpdatePins()
	end
end

function Dex:ConfirmForget()
	if self.forgetUntil and GetTime() < self.forgetUntil then
		self.forgetUntil = nil
		self:Forget()
		ns.Print(L["Forgot every beast you'd saved."])
		return
	end
	self.forgetUntil = GetTime() + CONFIRM_SECONDS
	ns.Print(L["Click again within %d seconds to forget every beast you've saved, on all your hunters."]:format(CONFIRM_SECONDS))
end

function Dex:GetOptionSections()
	return {
		{
			name = L["Pet abilities"],
			keys = { "record", "rares", "upgradeAlert", "allPins", "tomtom" },
			controls = {
				{ type = "button", label = L["Open pet abilities"], func = function()
					self:Open()
				end },
				{ type = "toggle", label = L["Save beasts from Beast Lore and taming"], key = "record", slash = "record" },
				{ type = "toggle", label = L["Save rare beasts you see"], key = "rares", slash = "rares" },
				{ type = "toggle", label = L["Tell me when my pet can learn a new rank"], key = "upgradeAlert", slash = "upgrades" },
				{ type = "toggle", label = L["Pins for every beast you've found on the map"], key = "allPins", slash = "allpins" },
				{ type = "toggle", label = L["TomTom arrow to a beast you click"], key = "tomtom", slash = "tomtom" },
				{ type = "note", text = L["Bind a key to Beast Lore on your mouseover target under Key Bindings > AddOns > Deadeye, then tap it on each beast you pass. What you find is saved for all your hunters on this account."] },
				{ type = "button", label = L["Forget every beast"], func = function()
					self:ConfirmForget()
				end },
			},
		},
	}
end
