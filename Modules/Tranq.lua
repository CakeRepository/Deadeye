-- Tranquilizing Shot callout: a big "Tranq Shot!" with a sound when an enemy
-- you're fighting gains an enrage (a frenzy) that Tranquilizing Shot removes,
-- then whether your shot took it off. It stays dormant until you know the spell.
--
-- What the game lets addons see on Forever:
--  * Aura instance IDs stay plain numbers in combat. The aura filter
--    "HELPFUL|RAID_PLAYER_DISPELLABLE" lists the buffs on an enemy that someone
--    in your group can remove, enrages included.
--  * What kind of buff each one is (dispelName, spellId, ...) is secret in
--    combat, unless the game flags that spell as never secret (C_Secrets says).
--    Out of combat it is read directly, so the buffs an enemy already has are
--    sorted out before the pull.
--  * So in combat, a new removable buff on an enemy you fight counts even when
--    the game won't say it's an enrage: a magic buff a priest could purge sets
--    it off too. Its icon and name go straight to the callout, which shows
--    them even though addons can't read them.
--  * Your own casts and the game's error messages stay readable. With the
--    combat log closed, the enrage going away right after your shot means it
--    hit, and the enrage staying means it missed or was resisted.
--  * Boss emotes ("%s goes into a frenzy!") are secret in raids and dungeons,
--    so they aren't used.
local _, ns = ...
local L = ns.L

local Tranq = ns:NewModule("Tranq", {
	enabled = true,
	nameplates = false, -- also watch enemy nameplates, not just bosses, target and focus
	position = { x = 0, y = 320 }, -- near the top, clear of the options window (follows the screen size on first use)
	scale = 1,
	sound = "RAID_WARNING",
	text = L["Tranq Shot!"],
	font = "Default",
	fontSize = 32,
	fontOutline = "THICKOUTLINE",
	announce = false, -- tell your party or raid whether your shot took the enrage off
})
Tranq.title = L["Tranq Shot callout"]
Tranq.slashPrefix = "tranq"

local TRANQ_SPELL_ID = 19801 -- checked by name, so any rank counts
-- Frenzies Tranquilizing Shot removes in Classic raids (Magmadar, Flamegor,
-- Chromaggus, Princess Huhuran, Gluth). Only examples: any enrage counts. These
-- are read directly in combat if the game flags them as never secret.
local KNOWN_FRENZIES = { 19451, 23342, 23128, 26051, 28371 }
local FRENZY = {}
for _, spellID in ipairs(KNOWN_FRENZIES) do
	FRENZY[spellID] = true
end
local BUFF_FILTER = "HELPFUL|RAID_PLAYER_DISPELLABLE" -- buffs on an enemy your group can remove
-- Dispel types Tranquilizing Shot leaves alone. A buff your group can remove
-- that has none of them is an enrage, whatever the client calls that type.
local NOT_ENRAGE = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true }
local NOTHING_TO_REMOVE = { SPELL_FAILED_NOTHING_TO_DISPEL = true }
local BOSS_UNITS = { "boss1", "boss2", "boss3", "boss4", "boss5" }
local NAMEPLATE_UNITS = 40
local SCAN_SECONDS = 0.25 -- how often enemies are checked in a fight
local MIN_SCAN_SECONDS = 0.1 -- and at most this often when their auras change
local CONFIRM_SECONDS = 2 -- how long the enrage may take to go after your shot
local COOLDOWN_SECONDS = 20 -- Tranquilizing Shot's cooldown: an enrage your shot missed is called out again after it
local ERROR_WINDOW = 0.3 -- a failed cast and its error message arrive this close together
local RESET_SECONDS = 5 -- out of a fight this long (longer than a Feign Death), it's over
local RESULT_SECONDS = 2.5
local MISS_SECONDS = 4
local FAILURE_SECONDS = 2.5
local PULSE_SECONDS = 2.5
local SOUND_GAP = 2 -- a callout that comes back this soon doesn't sound again
local COLORS = {
	alert = { 1, 0.45, 0.1 },
	removed = { 0.35, 0.9, 0.35 },
	missed = { 1, 0.25, 0.25 },
}
local OUTLINES = {
	{ value = "", text = L["None"] },
	{ value = "OUTLINE", text = L["Outline"] },
	{ value = "THICKOUTLINE", text = L["Thick outline"] },
}

-- The enemies watched: your target and focus and the bosses, then enemy nameplates.
local MAIN_UNITS = { "target", "focus" }
for _, unit in ipairs(BOSS_UNITS) do
	MAIN_UNITS[#MAIN_UNITS + 1] = unit
end
local ALL_UNITS, PLATES = {}, {}
for _, unit in ipairs(MAIN_UNITS) do
	ALL_UNITS[#ALL_UNITS + 1] = unit
end
for i = 1, NAMEPLATE_UNITS do
	local unit = "nameplate" .. i
	ALL_UNITS[#ALL_UNITS + 1] = unit
	PLATES[unit] = true
end

local tranqName, tranqIcon -- looked up when the module starts
local preview = false
local encounter = false -- between ENCOUNTER_START and ENCOUNTER_END
local dirty = false -- an enemy's auras or a unit changed since the last check
local fight -- what is known about the enemies in this fight (see ResetFight)
local generation = {} -- [unit] = how often the unit has changed enemies

local function ResetFight()
	fight = {
		kinds = {}, -- [auraInstanceID] = "enrage" or "other", once the game let the addon read it
		seen = {}, -- [auraInstanceID] = "new" (appeared while you watched) or "old"
		handled = {}, -- [auraInstanceID] = until when your shot covers it
		fresh = {}, -- [unit] = true: it shows a different enemy now, whose buffs aren't news
		candidates = {}, -- [auraInstanceID] = unit: the enrages the callout is about
		alert = nil, -- { unit =, id = }: the buff shown under the callout
		pending = nil, -- your last shot: { at =, ids =, unit =, generation = }
		active = false, -- a fight has started
		idleSince = nil,
		toldLocked = false,
	}
	for _, unit in ipairs(ALL_UNITS) do
		fight.fresh[unit] = true
	end
end
ResetFight()

local function InCombat()
	return ns.Readable(UnitAffectingCombat("player"), false)
end

-- In a fight, or in a boss encounter (where a Feign Death doesn't end it).
local function Engaged()
	return InCombat() or encounter
end

-- Looked up by name, the spell is only found once you know it.
local function KnowsTranq()
	return tranqName ~= nil and ns.Readable(C_Spell.GetSpellName(tranqName)) ~= nil
end

local function IsTranq(spellID)
	if ns.IsSecret(spellID) or spellID == nil then
		return false
	end
	return tranqName ~= nil and ns.Readable(C_Spell.GetSpellName(spellID)) == tranqName
end

-- True for anything a widget can show, secret or not.
local function Showable(value)
	return ns.IsSecret(value) or value ~= nil
end

local function Bump(unit)
	generation[unit] = (generation[unit] or 0) + 1
	fight.fresh[unit] = true
	dirty = true
end

---------------------------------------------------------------------------
-- Finding enrages
---------------------------------------------------------------------------
-- The buffs on an enemy that your group can remove, as a set of aura
-- instance IDs, or nil if the game won't say.
local function RemovableBuffs(unit)
	if not C_UnitAuras.GetUnitAuraInstanceIDs then
		return nil
	end
	local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, BUFF_FILTER)
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

-- Whether the game keeps this aura's details from addons right now.
local function AuraSecret(unit, id)
	if C_Secrets and C_Secrets.ShouldUnitAuraInstanceBeSecret then
		local ok, secret = pcall(C_Secrets.ShouldUnitAuraInstanceBeSecret, unit, id)
		return not ok or ns.Readable(secret, true) ~= false
	end
	return InCombatLockdown()
end

-- "enrage", "other", or "hidden" while the game won't say.
local function Classify(unit, id)
	local kind = fight.kinds[id]
	if kind then
		return kind
	end
	if AuraSecret(unit, id) then
		return "hidden"
	end
	local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
	if not ok or ns.IsSecret(aura) or type(aura) ~= "table" then
		return "hidden"
	end
	local spellID, dispel = aura.spellId, aura.dispelName
	if ns.IsSecret(spellID) or ns.IsSecret(dispel) then
		return "hidden"
	end
	if spellID and FRENZY[spellID] then
		kind = "enrage"
	elseif dispel and NOT_ENRAGE[dispel] then
		kind = "other" -- a priest's or a shaman's to remove, not yours
	else
		kind = "enrage"
	end
	fight.kinds[id] = kind
	ns.Debug("Tranq: aura", id, "on", unit, "is", kind, "(dispel type '" .. tostring(dispel) .. "')")
	return kind
end

-- The known frenzies the game shows in combat, flagged as never secret.
local function ReadableFrenzies()
	local list = {}
	if C_UnitAuras.GetUnitAuraBySpellID and C_Secrets and C_Secrets.ShouldSpellAuraBeSecret then
		for _, spellID in ipairs(KNOWN_FRENZIES) do
			if ns.Readable(C_Secrets.ShouldSpellAuraBeSecret(spellID)) == false then
				list[#list + 1] = spellID
			end
		end
	end
	return list
end

-- Adds the readable known frenzies on unit to ids, which works even where the
-- game hides aura IDs.
local function AddFrenzies(unit, frenzies, ids)
	for _, spellID in ipairs(frenzies) do
		local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
		aura = ok and ns.Readable(aura)
		local id = type(aura) == "table" and ns.Readable(aura.auraInstanceID)
		if id then
			ids = ids or {}
			ids[id] = true
			fight.kinds[id] = "enrage"
		end
	end
	return ids
end

-- An enemy you're fighting: bosses, target and focus in combat, and enemy
-- nameplates whose threat list you're on. Not while you're dead.
local function Fighting(unit)
	if not Engaged() or ns.Readable(UnitIsDead(unit), true) or ns.Readable(UnitIsDeadOrGhost("player"), false) then
		return false
	end
	if PLATES[unit] then
		return ns.Readable(UnitThreatSituation("player", unit)) ~= nil
	end
	return ns.Readable(UnitAffectingCombat(unit), false)
end

-- The buff's name and icon, handed to the callout as they are: in combat they
-- are secret, which widgets show but addon code can't read.
local function AuraLooks(unit, id)
	local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
	if ok and not ns.IsSecret(aura) and type(aura) == "table" then
		return aura.name, aura.icon
	end
end

function Tranq:Scan(now)
	self.lastScan, dirty = now, false
	local engaged = Engaged()
	local frenzies = ReadableFrenzies()
	local present, watched, candidates, firstSeen = {}, {}, {}, {}
	local pick, pickID
	for _, unit in ipairs(self.db.nameplates and ALL_UNITS or MAIN_UNITS) do
		-- Tranquilizing Shot works on creatures: enemy players and their pets are left out.
		if ns.Readable(UnitExists(unit), false) and ns.Readable(UnitCanAttack("player", unit), false)
			and not ns.Readable(UnitPlayerControlled(unit), true) then
			local ids = AddFrenzies(unit, frenzies, RemovableBuffs(unit))
			local fighting = Fighting(unit)
			watched[unit] = ids ~= nil
			for id in pairs(ids or {}) do
				present[id] = present[id] or unit
				if not fight.seen[id] and firstSeen[id] ~= "new" then
					-- A buff that was there when you first looked at this enemy isn't news.
					firstSeen[id] = (engaged and not fight.fresh[unit]) and "new" or "old"
				end
				local kind = Classify(unit, id)
				local news = (fight.seen[id] or firstSeen[id]) == "new"
				local handled = fight.handled[id] and now < fight.handled[id]
				if fighting and not handled and (kind == "enrage" or (kind == "hidden" and news)) then
					candidates[id] = candidates[id] or unit
					if not pick or (pick == unit and id < pickID) then
						pick, pickID = unit, id
					end
				end
			end
			fight.fresh[unit] = nil
		end
	end
	for id, verdict in pairs(firstSeen) do
		fight.seen[id] = verdict
	end
	fight.candidates = candidates
	self:JudgeShot(now, present, watched)
	if pick then
		if not fight.alert then
			self:StartAlert(now, pick, pickID)
		end
		fight.alert = { unit = pick, id = pickID }
	else
		fight.alert = nil
	end
	self:Refresh()
end

---------------------------------------------------------------------------
-- Your shot
---------------------------------------------------------------------------
-- The enrage gone soon after your shot means it hit; still there, it missed
-- or was resisted. A shot at an enemy you lost sight of isn't judged.
function Tranq:JudgeShot(now, present, watched)
	local shot = fight.pending
	if not shot then
		return
	end
	local unit = shot.unit
	if generation[unit] ~= shot.generation or not watched[unit] or ns.Readable(UnitIsDead(unit), true) then
		if generation[unit] ~= shot.generation or now - shot.at > CONFIRM_SECONDS then
			fight.pending = nil
		end
		return
	end
	local remaining = false
	for id in pairs(shot.ids) do
		if present[id] then
			remaining = true
		end
	end
	if not remaining then
		fight.pending = nil
		self:ShowResult("removed")
	elseif now - shot.at > CONFIRM_SECONDS then
		fight.pending = nil
		self:ShowResult("missed")
	end
end

function Tranq:ShowResult(kind)
	local now = GetTime()
	ns.Debug("Tranq: your shot", kind == "removed" and "removed the enrage" or "missed")
	if kind == "removed" then
		self.result = { kind = kind, text = L["Enrage removed!"], untilTime = now + RESULT_SECONDS }
		self:Announce(L["My %s removed the enrage."]:format(tranqName))
	else
		self.result = { kind = kind, text = L["Still enraged!"], untilTime = now + MISS_SECONDS,
			detail = L["Your %s missed or was resisted."]:format(tranqName) }
		self:Announce(L["My %s missed or was resisted. Next hunter, go!"]:format(tranqName))
	end
	self:Refresh()
end

-- Your casts stay readable in combat. The shot clears the callout; the next
-- checks tell whether it took the enrage off.
function Tranq:UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	if not IsTranq(spellID) then
		return
	end
	local now = GetTime()
	local alert, ids, unit = fight.alert, {}, nil
	if alert then
		-- The shot goes at your target: its enrages, or else the one the callout showed.
		for id, shownOn in pairs(fight.candidates) do
			if shownOn == "target" then
				ids[id], unit = true, "target"
			end
		end
		if not unit then
			ids[alert.id], unit = true, alert.unit
		end
	end
	for id in pairs(ids) do
		fight.handled[id] = now + COOLDOWN_SECONDS
	end
	fight.pending = unit and { at = now, ids = ids, unit = unit, generation = generation[unit] } or nil
	fight.alert = nil
	self.failure, self.result = nil, nil
	dirty = true
	self:Refresh()
end

-- The game's error message says why a cast failed. It may come just before
-- or just after the failed cast itself.
function Tranq:UNIT_SPELLCAST_FAILED(_, _, spellID)
	if not IsTranq(spellID) then
		return
	end
	local now = GetTime()
	local lastError = self.lastError
	if lastError and now - lastError.at <= ERROR_WINDOW then
		self:CastFailed(lastError)
	else
		self.failedAt = now
	end
end

function Tranq:UI_ERROR_MESSAGE(errorType, message)
	if ns.IsSecret(errorType) or not GetGameMessageInfo then
		return
	end
	local now = GetTime()
	local lastError = { name = ns.Readable((GetGameMessageInfo(errorType)), ""), message = ns.Readable(message), at = now }
	if self.failedAt and now - self.failedAt <= ERROR_WINDOW then
		self:CastFailed(lastError)
	else
		self.lastError = lastError
	end
end

function Tranq:CastFailed(failure)
	self.failedAt, self.lastError = nil, nil
	ns.Debug("Tranq: cast failed,", failure.name)
	if NOTHING_TO_REMOVE[failure.name] then
		-- Nothing on your target for Tranquilizing Shot to take off: its buffs aren't enrages.
		for id, unit in pairs(fight.candidates) do
			if unit == "target" then
				fight.kinds[id] = "other"
			end
		end
		dirty = true
	end
	if type(failure.message) == "string" and failure.message ~= "" then
		self.failure = { message = failure.message, untilTime = GetTime() + FAILURE_SECONDS }
	end
	self:Refresh()
end

---------------------------------------------------------------------------
-- Announcements
---------------------------------------------------------------------------
-- Midnight's chat messaging lockdown keeps addons from sending chat in boss
-- encounters (and on maps where the game restricts addon chat). Only party and
-- raid chat is used, and nothing is sent while the game says chat is locked.
local function ChatLocked()
	if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
		return ns.Readable(C_ChatInfo.InChatMessagingLockdown(), true) ~= false
	end
	return false
end

local function GroupChannel()
	if ns.Readable(IsInRaid(), false) then
		return "RAID"
	elseif ns.Readable(IsInGroup(), false) then
		return "PARTY"
	end
end

function Tranq:Announce(message)
	local channel = self.db.announce and GroupChannel()
	if not (channel and C_ChatInfo and C_ChatInfo.SendChatMessage) then
		return
	end
	if ChatLocked() then
		if not fight.toldLocked then
			fight.toldLocked = true
			ns.Print(L["Not announced: the game doesn't let addons send chat messages right now."])
		end
		return
	end
	local ok, err = pcall(C_ChatInfo.SendChatMessage, message, channel)
	if not ok then
		ns.Debug("Tranq: couldn't announce,", err)
	end
end

---------------------------------------------------------------------------
-- The callout
---------------------------------------------------------------------------
function Tranq:StartAlert(now, unit, id)
	ns.Debug("Tranq: enrage on", unit, "aura", id, fight.kinds[id] or "(the game hides its type)")
	self.failure, self.result = nil, nil
	self.pulseUntil = now + PULSE_SECONDS
	local sound = ns.Media.Sound(self.db.sound)
	if sound and not (self.soundAt and now - self.soundAt < SOUND_GAP) then
		PlaySound(sound, "Master")
		self.soundAt = now
	end
end

local function SampleBuff()
	local spellID = KNOWN_FRENZIES[1]
	return ns.Readable(C_Spell.GetSpellName(spellID)), ns.Readable(C_Spell.GetSpellTexture(spellID))
end

function Tranq:Refresh()
	local frame = self.frame
	if not frame then
		return
	end
	local db, now = self.db, GetTime()
	if not (db.enabled and self.known) then
		frame:Hide()
		return
	end
	local alert, result = fight.alert, self.result
	local text, color, detail, icon
	if alert then
		text, color = db.text, COLORS.alert
		detail, icon = AuraLooks(alert.unit, alert.id)
		if self.failure then
			detail = self.failure.message -- why your cast failed, in the game's words
		end
	elseif result then
		text, color, detail = result.text, COLORS[result.kind], result.detail
	elseif preview or ns:IsUnlocked() then
		text, color = db.text, COLORS.alert
		detail, icon = SampleBuff()
	else
		frame:Hide()
		return
	end
	frame.text:SetText(text)
	frame.text:SetTextColor(color[1], color[2], color[3])
	if Showable(detail) then
		frame.detail:SetText(detail)
		frame.detail:Show()
		if Showable(icon) then
			frame.icon:SetTexture(icon)
		else
			frame.icon:SetTexture(tranqIcon)
		end
		frame.icon:Show()
	else
		frame.detail:Hide()
		frame.icon:Hide()
	end
	if not (alert and self.pulseUntil and now < self.pulseUntil) then
		frame:SetAlpha(1)
	end
	frame:Show()
end

-- Runs every frame while you know the spell: checks enemies, times out what
-- the callout shows, and pulses a new callout.
function Tranq:OnUpdate()
	local now = GetTime()
	if Engaged() then
		fight.active, fight.idleSince = true, nil
	elseif fight.active then
		fight.idleSince = fight.idleSince or now
		if now - fight.idleSince > RESET_SECONDS then
			ResetFight()
			dirty = true
		end
	end
	local since = now - (self.lastScan or -math.huge)
	if self.db.enabled and ((dirty and since >= MIN_SCAN_SECONDS) or ((Engaged() or fight.pending) and since >= SCAN_SECONDS)) then
		self:Scan(now)
	end
	local changed = false
	if self.result and now >= self.result.untilTime then
		self.result, changed = nil, true
	end
	if self.failure and now >= self.failure.untilTime then
		self.failure, changed = nil, true
	end
	if self.lastError and now - self.lastError.at > ERROR_WINDOW then
		self.lastError = nil
	end
	if changed then
		self:Refresh()
	end
	local frame = self.frame
	if frame and fight.alert and self.pulseUntil and frame:IsShown() then
		local remaining = self.pulseUntil - now
		frame:SetAlpha(remaining <= 0 and 1 or 0.45 + 0.55 * math.abs(math.cos(remaining * 6)))
		if remaining <= 0 then
			self.pulseUntil = nil
		end
	end
end

function Tranq:BuildFrame()
	local frame = CreateFrame("Frame", "DeadeyeTranqFrame", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	frame.text:SetPoint("TOP", 0, -4)
	frame.detail = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.detail:SetPoint("TOP", frame.text, "BOTTOM", 0, -4)
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetPoint("RIGHT", frame.detail, "LEFT", -4, 0)
	frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame:Hide()
	ns.Frames.MakeMovable(self, frame, L["Tranq Shot"])
	self.frame = frame
end

function Tranq:ApplyLayout()
	local db, frame = self.db, self.frame
	if not frame then
		return
	end
	local detailSize = math.max(10, math.floor(db.fontSize * 0.45 + 0.5))
	ns.Media.ApplyFont(frame.text, db.font, db.fontSize, db.fontOutline)
	ns.Media.ApplyFont(frame.detail, db.font, detailSize, "OUTLINE")
	frame.icon:SetSize(detailSize + 4, detailSize + 4)
	frame:SetSize(math.max(240, db.fontSize * 9), db.fontSize + detailSize + 20)
	frame:SetScale(db.scale)
	ns.Frames.UpdateMover(frame)
	ns.Frames.ApplyPosition(self, frame)
	self:Refresh()
end

function Tranq:OnOptionChanged()
	dirty = true
	self:ApplyLayout()
end

Tranq.OnUnlockChanged = Tranq.ApplyLayout
Tranq.OnSettingsReset = Tranq.ApplyLayout

function Tranq:SetPreview(enabled)
	preview = enabled
	self:Refresh()
end

function Tranq:GetOptionSections()
	if not self.known then
		return {} -- no page until you know the spell
	end
	local controls = {
		{ type = "toggle", label = L["Show the Tranq Shot callout"], key = "enabled", slash = "enabled" },
		{ type = "toggle", label = L["Watch enemy nameplates too"], key = "nameplates", slash = "nameplates" },
	}
	for _, spec in ipairs(ns.Frames.PositionOptions(self)) do
		controls[#controls + 1] = spec
	end
	for _, spec in ipairs({
		{ type = "select", label = L["Alert sound"], key = "sound", values = ns.Media.Sounds(), slash = "sound" },
		{ type = "button", label = L["Play the sound"], slash = "playsound", func = function()
			local sound = ns.Media.Sound(self.db.sound)
			if sound then
				PlaySound(sound, "Master")
			end
		end },
		{ type = "input", label = L["Callout text"], key = "text", slash = "text" },
		{ type = "select", label = L["Font"], key = "font", slash = "font", values = function() return ns.Media.List("font") end },
		{ type = "range", label = L["Font size"], key = "fontSize", min = 16, max = 64, step = 1, slash = "fontsize" },
		{ type = "select", label = L["Outline"], key = "fontOutline", values = OUTLINES, slash = "outline" },
		{ type = "toggle", label = L["Announce hits and misses in group chat"], key = "announce", slash = "announce" },
		{ type = "note", text = L["Watches bosses, your target and your focus. In combat the game hides what kind of buff appeared, so a magic buff a priest could purge sets it off too: its icon and name show under the callout. Nothing goes to group chat while the game blocks addon chat, as in boss fights."] },
	}) do
		controls[#controls + 1] = spec
	end
	return {
		{
			name = L["Tranq Shot"],
			keys = { "enabled", "nameplates", "position", "scale", "sound", "text", "font", "fontSize", "fontOutline", "announce" },
			controls = controls,
		},
	}
end

---------------------------------------------------------------------------
-- Starting up, and staying dormant without the spell
---------------------------------------------------------------------------
function Tranq:ShouldEnable()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

local FIGHT_EVENTS = {
	"PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"ENCOUNTER_START", "ENCOUNTER_END", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
	"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_AURA", "UI_ERROR_MESSAGE",
}
local CAST_EVENTS = { "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED" }

function Tranq:OnEnable()
	if self.freshSettings then
		self.db.position.y = math.floor(UIParent:GetHeight() * 0.3 + 0.5)
	end
	tranqName = ns.Readable(C_Spell.GetSpellName(TRANQ_SPELL_ID))
	local events = ns.CreateEventFrame(self)
	for _, event in ipairs({ "SPELLS_CHANGED", "LEARNED_SPELL_IN_SKILL_LINE", "PLAYER_ENTERING_WORLD" }) do
		events:RegisterEvent(event)
	end
	self.events = events
	self:UpdateKnown()
end

-- Wakes up once you learn the spell (and would go back to sleep without it).
function Tranq:UpdateKnown()
	local known = KnowsTranq()
	if known == (self.known == true) then
		return
	end
	self.known = known
	local events = self.events
	if known then
		ns.Debug("Tranq: you know", tranqName)
		tranqIcon = ns.Readable(C_Spell.GetSpellTexture(TRANQ_SPELL_ID))
		if not self.frame then
			self:BuildFrame()
		end
		for _, event in ipairs(FIGHT_EVENTS) do
			events:RegisterEvent(event)
		end
		for _, event in ipairs(CAST_EVENTS) do
			events:RegisterUnitEvent(event, "player")
		end
		events:SetScript("OnUpdate", function()
			self:OnUpdate()
		end)
		dirty = true
		self:ApplyLayout()
	else
		for _, event in ipairs(FIGHT_EVENTS) do
			events:UnregisterEvent(event)
		end
		for _, event in ipairs(CAST_EVENTS) do
			events:UnregisterEvent(event)
		end
		events:SetScript("OnUpdate", nil)
		ResetFight()
		self.result, self.failure = nil, nil
		if self.frame then
			self.frame:Hide()
		end
	end
end

Tranq.SPELLS_CHANGED = Tranq.UpdateKnown
Tranq.LEARNED_SPELL_IN_SKILL_LINE = Tranq.UpdateKnown

function Tranq:PLAYER_ENTERING_WORLD()
	encounter = false
	ResetFight()
	self:UpdateKnown()
	dirty = true
end

function Tranq:PLAYER_TARGET_CHANGED()
	Bump("target")
end

function Tranq:PLAYER_FOCUS_CHANGED()
	Bump("focus")
end

function Tranq:INSTANCE_ENCOUNTER_ENGAGE_UNIT()
	for _, unit in ipairs(BOSS_UNITS) do
		Bump(unit)
	end
end

function Tranq:ENCOUNTER_START()
	encounter = true
	self:INSTANCE_ENCOUNTER_ENGAGE_UNIT()
	if ns.db.debug then
		local names = {}
		for _, spellID in ipairs(ReadableFrenzies()) do
			names[#names + 1] = tostring(spellID)
		end
		ns.Debug("Tranq: known frenzies the game shows in combat:", #names > 0 and table.concat(names, ", ") or "none")
	end
end

function Tranq:ENCOUNTER_END()
	encounter = false
	dirty = true
end

function Tranq:NAME_PLATE_UNIT_ADDED(unit)
	if not ns.IsSecret(unit) and PLATES[unit] then
		Bump(unit)
	end
end
Tranq.NAME_PLATE_UNIT_REMOVED = Tranq.NAME_PLATE_UNIT_ADDED

-- Its payload is secret in combat; it only says that some aura changed.
function Tranq:UNIT_AURA()
	dirty = true
end

function Tranq:PLAYER_REGEN_DISABLED()
	dirty = true
end
Tranq.PLAYER_REGEN_ENABLED = Tranq.PLAYER_REGEN_DISABLED
