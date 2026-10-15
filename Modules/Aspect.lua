-- Aspect reminder. In a fight, Aspect of the Cheetah or of the Pack gets you
-- dazed whenever you're hit, and no aspect at all leaves Hawk's attack power
-- unused. While either is the case in combat, the range indicator's text says
-- so, and a fight that starts that way gets an alert.
--
-- Out of combat your buffs are read directly. In combat the game can keep aura
-- details from addons, so the aspect is followed through your own casts, which
-- stay readable, and through its aura instance ID, a plain number even in
-- combat. The ID is learned when the aura is read, or as the one new buff of
-- yours right after you cast an aspect. Once that ID is gone from your buffs,
-- so is the aspect.
local _, ns = ...
local L = ns.L

local Aspect = ns:NewModule("Aspect", {
	enabled = true,
	dazeWarning = true, -- Cheetah or Pack in combat
	noAspectWarning = true, -- no aspect in combat
	pullAlert = true, -- an alert when a fight starts in Cheetah, Pack or no aspect
	alertSound = "RAID_WARNING",
	color = { 1, 0.3, 0.3 },
})
Aspect.title = L["Aspect"]
Aspect.slashPrefix = "aspect"

-- Rank 1 of each aspect. They're found by name, so any rank counts.
local ASPECTS = {
	{ spellID = 13165 }, -- Hawk
	{ spellID = 13163 }, -- Monkey
	{ spellID = 5118, dazes = true }, -- Cheetah
	{ spellID = 13159, dazes = true }, -- Pack
	{ spellID = 13161 }, -- Beast
	{ spellID = 20043 }, -- Wild
}
local BUFF_FILTER = "HELPFUL|PLAYER" -- buffs you put on yourself
local CAST_WINDOW_SECONDS = 1.5 -- how long after a cast its aura is looked for

local state -- what is known about your aspect (see Forget)
local idsWork = false -- your aspect's aura ID was seen in combat, so not seeing it means something

local function Forget()
	state = {
		aspect = nil, -- the ASPECTS entry you have on, false for none, nil when unknown
		auraID = nil, -- its aura instance ID
		buffs = nil, -- your buffs at the last check, as a set of aura instance IDs
		baseline = nil, -- your buffs when you cast an aspect
		baselineUntil = 0,
	}
end
Forget()

local function InCombat()
	return ns.Readable(UnitAffectingCombat("player"), false)
end

-- Whether the game shows this aspect's aura to addons right now.
local function AuraReadable(entry)
	if not InCombatLockdown() then
		return true
	end
	return C_Secrets ~= nil and C_Secrets.ShouldSpellAuraBeSecret ~= nil
		and ns.Readable(C_Secrets.ShouldSpellAuraBeSecret(entry.spellID)) == false
end

-- Your buffs as a set of aura instance IDs, or nil if the game won't say.
local function MyBuffs()
	if not C_UnitAuras.GetUnitAuraInstanceIDs then
		return nil
	end
	local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, "player", BUFF_FILTER)
	ids = ok and ns.Readable(ids)
	if type(ids) ~= "table" then
		return nil
	end
	local set = {}
	for _, id in ipairs(ids) do
		id = ns.Readable(id)
		if id then
			set[id] = true
		end
	end
	return set
end

local function ByName(name)
	for _, entry in ipairs(ASPECTS) do
		if entry.name == name then
			return entry
		end
	end
end

function Aspect:Track(now)
	-- Read the aura directly where the game allows it.
	local found, sure = nil, true
	for _, entry in ipairs(ASPECTS) do
		if entry.name then
			if AuraReadable(entry) then
				local aura = ns.Readable(C_UnitAuras.GetAuraDataBySpellName("player", entry.name, "HELPFUL"))
				if aura then
					found = entry
					state.auraID = ns.Readable(aura.auraInstanceID) or (state.aspect == entry and state.auraID or nil)
					break
				end
			else
				sure = false
			end
		end
	end
	if found then
		state.aspect = found
	elseif sure and not state.baseline then -- (a cast's aura can take a moment to show)
		state.aspect, state.auraID = false, nil
	end
	-- Follow its aura ID where it can't be read.
	local buffs = MyBuffs()
	if buffs then
		if state.baseline then
			-- Just cast: the one buff of yours that wasn't there before is the aspect.
			local new
			for id in pairs(buffs) do
				if not state.baseline[id] then
					new = new == nil and id or false
				end
			end
			if new then
				state.auraID, state.baseline = new, nil
			elseif now > state.baselineUntil then
				state.baseline = nil
			end
		end
		if state.auraID and buffs[state.auraID] and InCombatLockdown() then
			idsWork = true
		end
		if idsWork and not (found or sure or state.baseline) and state.aspect and state.auraID and not buffs[state.auraID] then
			ns.Debug("Aspect: its aura is gone")
			state.aspect, state.auraID = false, nil
		end
		state.buffs = buffs
	end
	if state.aspect then
		self.seenAspect = true
	end
end

-- No aspect is only worth a warning once you have one to use.
function Aspect:KnowsAnAspect()
	if self.seenAspect then
		return true
	end
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		for _, entry in ipairs(ASPECTS) do
			if ns.Readable(C_SpellBook.IsSpellKnown(entry.spellID)) then
				return true
			end
		end
	end
	return false
end

-- What needs changing: "daze" (Cheetah or Pack), "none", or nil.
function Aspect:Problem()
	local db, aspect = self.db, state.aspect
	if aspect and aspect.dazes and db.dazeWarning then
		return "daze"
	elseif aspect == false and db.noAspectWarning and self:KnowsAnAspect() then
		return "none"
	end
end

-- "aspect" in combat while your aspect needs changing; the range indicator
-- then shows WarningText().
function Aspect:Warning()
	if not (self.db.enabled and InCombat()) then
		return nil
	end
	self:Track(GetTime())
	return self:Problem() and "aspect" or nil
end

function Aspect:WarningText()
	local aspect = state.aspect
	if aspect then
		return L["%s is on"]:format(aspect.name), self.db.color
	end
	return L["No aspect"], self.db.color
end

function Aspect:Alert(message)
	ns.Print(message)
	local sound = ns.Media.Sound(self.db.alertSound)
	if sound then
		PlaySound(sound, "Master")
	end
end

function Aspect:GetOptionSections()
	return {
		{
			name = L["Aspect"],
			keys = { "enabled", "dazeWarning", "noAspectWarning", "pullAlert", "alertSound", "color" },
			controls = {
				{ type = "toggle", label = L["Remind me about my aspect in combat"], key = "enabled", slash = "enabled" },
				{ type = "toggle", label = L["In Cheetah or Pack (you get dazed)"], key = "dazeWarning", slash = "daze" },
				{ type = "toggle", label = L["With no aspect"], key = "noAspectWarning", slash = "none" },
				{ type = "toggle", label = L["Alert me when a fight starts that way"], key = "pullAlert", slash = "pull" },
				{ type = "select", label = L["Alert sound"], key = "alertSound", values = ns.Media.Sounds(), slash = "sound" },
				{ type = "color", label = L["Warning color"], key = "color", slash = "color" },
				{ type = "note", text = L["The warning takes the range indicator's text above the Auto Shot bar until you change aspect."] },
			},
		},
	}
end

function Aspect:ShouldEnable()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

function Aspect:OnEnable()
	for _, entry in ipairs(ASPECTS) do
		entry.name = C_Spell.GetSpellName(entry.spellID)
	end
	local events = ns.CreateEventFrame(self)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		events:RegisterEvent(event)
	end
	events:RegisterUnitEvent("UNIT_AURA", "player")
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	self.events = events
	self:Track(GetTime())
end

-- Your buffs changed. In combat the event's details may be secret, so it's only a cue.
function Aspect:UNIT_AURA()
	self:Track(GetTime())
end

-- Casting an aspect puts it on (you can only have one); its aura is spotted on
-- the next checks.
function Aspect:UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	if ns.IsSecret(spellID) then
		return
	end
	local entry = ByName(C_Spell.GetSpellName(spellID))
	if entry then
		local now = GetTime()
		state.aspect, state.auraID = entry, nil
		state.baseline, state.baselineUntil = state.buffs or {}, now + CAST_WINDOW_SECONDS
		self.seenAspect = true
		self:Track(now)
	end
end

-- Your aspect was read before the fight; a bad one gets an alert.
function Aspect:PLAYER_REGEN_DISABLED()
	self:Track(GetTime())
	if not (self.db.enabled and self.db.pullAlert) then
		return
	end
	local problem = self:Problem()
	if problem == "daze" then
		self:Alert(L["You're fighting in %s: you'll be dazed when hit."]:format(state.aspect.name))
	elseif problem == "none" then
		self:Alert(L["You're fighting without an aspect."])
	end
end

function Aspect:PLAYER_REGEN_ENABLED()
	self:Track(GetTime())
end

Aspect.PLAYER_ENTERING_WORLD = Aspect.PLAYER_REGEN_ENABLED
