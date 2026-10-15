-- Range to your target the way a hunter cares about it: melee, Auto Shot
-- range, or neither (the dead zone, or too far away).
--
-- C_Spell.IsSpellInRange with Auto Shot and a melee ability stays readable in
-- combat. Out of combat, CheckInteractDistance also tells the dead zone (about
-- 10 yards) from too far. In combat Blizzard restricts that call on enemies, so
-- the text then just says you have no shot. Without a melee check that works
-- (low level hunters only have Raptor Strike, whose check can't be trusted),
-- melee range and the dead zone read as one band: too close.
local _, ns = ...
local L = ns.L

local Range = ns:NewModule("Range", {
	enabled = true,
	attach = "BAR", -- "BAR": sits just above the Auto Shot bar and moves with it; "FREE": own position
	position = { x = 0, y = -195 }, -- used when attach is "FREE"
	scale = 1,
	show = "target", -- "target", "combat" or "problems" (only when you can't shoot)
	style = "strip", -- "strip": color-coded range bands under the text; "text": text only
	stripWidth = 220,
	stripHeight = 6,
	markAlert = true, -- "Mark your target" in combat when the target has no Hunter's Mark
	font = "Default",
	fontSize = 14,
	fontOutline = "OUTLINE",
	labels = {
		melee = L["Melee"],
		ranged = L["Ranged"],
		deadZone = L["Dead zone"],
		close = L["Too close"],
		noShot = L["No shot"],
		tooFar = L["Out of range"],
		facing = L["Face your target"],
		lineOfSight = L["No line of sight"],
		noMark = L["Mark your target"],
	},
	colors = {
		melee = { 1, 0.82, 0 },
		ranged = { 0.35, 0.9, 0.35 },
		deadZone = { 1, 0.3, 0.3 },
		close = { 1, 0.4, 0.25 },
		noShot = { 1, 0.5, 0.15 },
		tooFar = { 0.65, 0.65, 0.65 },
		facing = { 1, 0.3, 0.3 },
		lineOfSight = { 1, 0.3, 0.3 },
		noMark = { 1, 0.4, 0.8 },
	},
})
Range.title = L["Range indicator"]
Range.slashPrefix = "range"

local AUTO_SHOT_SPELL_ID = 75
local HUNTERS_MARK_SPELL_ID = 1130 -- checked by name, so any rank counts
local MARK_SECONDS = 120 -- how long a mark lasts
local AUTO_SHOT_YARDS = 35 -- Auto Shot's longest reach without talents
-- Wing Clip, Mongoose Bite, Auto Attack, Raptor Strike. Checked by name, so any
-- rank you know counts. Raptor Strike goes last: it waits for your next swing,
-- and its range check has been seen to call far-away targets in range.
local MELEE_SPELL_IDS = { 2974, 1495, 6603, 2973 }
local MELEE_SWING = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.MainHand or 0
local RANGED_SWING = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.Ranged or 2
local MELEE_SWING_SECONDS = 4 -- a melee swing this recent means you're still in melee range
local CLOSE_DISTANCE_INDEX = 3 -- CheckInteractDistance: duel range, about 10 yards
local POLL_SECONDS = 0.1
local SAMPLE_STATUS = "ranged" -- shown while previewing or moving the frame

local SHOW_CHOICES = {
	{ value = "target", text = L["With a hostile target"] },
	{ value = "combat", text = L["Only in combat"] },
	{ value = "problems", text = L["Only when I can't shoot"] },
}
local ATTACH_CHOICES = {
	{ value = "BAR", text = L["Above the Auto Shot bar"] },
	{ value = "FREE", text = L["Anywhere (drag it)"] },
}
local STYLE_CHOICES = {
	{ value = "strip", text = L["Color strip and text"] },
	{ value = "text", text = L["Text only"] },
}
-- The strip, near to far, and how much of its width each band gets.
local BANDS = { "melee", "deadZone", "ranged", "tooFar" }
local BAND_SHARE = { melee = 0.15, deadZone = 0.15, ranged = 0.5, tooFar = 0.2 }
local LIT, UNSURE, DIM = 1, 0.6, 0.18
local OLD_DEFAULT_Y = -150 -- 0.2.0 beta builds put the text over the character
local OUTLINES = {
	{ value = "", text = L["None"] },
	{ value = "OUTLINE", text = L["Outline"] },
	{ value = "THICKOUTLINE", text = L["Thick outline"] },
}

local preview = false

local function InCombat()
	return ns.Readable(UnitAffectingCombat("player"), false)
end

-- Duel range (about 10 yards) to the target, out of combat only: in combat
-- the game blocks this check on enemies. nil when unknown.
local function Close()
	if CheckInteractDistance and not InCombatLockdown() then
		local ok, close = pcall(CheckInteractDistance, "target", CLOSE_DISTANCE_INDEX)
		if ok then
			return ns.Readable(close)
		end
	end
end

-- Melee abilities whose range check called a target in range that can't be:
-- one Auto Shot can reach (its minimum range is past melee range), or one past
-- duel range. They are ignored from then on.
local unreliable = {}
local lastMeleeSwing -- when your last melee swing at this target landed

-- true or false, or nil when nothing can tell.
local function MeleeInRange(ranged, close, now)
	-- The game's own melee range check, where it works (it answered nothing on
	-- the beta builds that were tested).
	if C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange then
		local inRange = ns.Readable(C_SwingTimer.IsTargetWithinSwingRange(MELEE_SWING))
		if inRange ~= nil then
			return inRange
		end
	end
	for _, spellID in ipairs(MELEE_SPELL_IDS) do
		local name = not unreliable[spellID] and C_Spell.GetSpellName(spellID)
		if name then
			local inRange = ns.Readable(C_Spell.IsSpellInRange(name, "target"))
			if inRange and (ranged or close == false) then
				unreliable[spellID] = true
				ns.Debug("Range: ignoring", name, "from now on, its range check is wrong")
			elseif inRange ~= nil then
				return inRange
			end
		end
	end
	-- Melee swings only land in melee range.
	if lastMeleeSwing and now - lastMeleeSwing <= MELEE_SWING_SECONDS then
		return true
	end
end

-- "melee", "ranged", "deadZone", "close" (melee or dead zone), "tooFar",
-- "noShot", or nil without an attackable target.
function Range:Evaluate()
	local now = GetTime()
	local ranged = ns.Readable(C_Spell.IsSpellInRange(AUTO_SHOT_SPELL_ID, "target"))
	local close = Close()
	local melee = MeleeInRange(ranged, close, now)
	if ranged == nil and melee == nil then
		return nil
	end
	-- Auto Shot's own check comes first: anything it can reach is past melee range.
	if ranged then
		return "ranged"
	end
	if melee then
		return "melee"
	end
	-- Too close to shoot: the dead zone only if a melee check says you're past melee range.
	if close == true then
		return melee == false and "deadZone" or "close"
	elseif close == false then
		return "tooFar"
	end
	-- In combat: a recent "too close" / "out of range" from Auto Shot settles it.
	local autoShot = ns.modules.AutoShot
	local hint = autoShot.enabled and autoShot:GetRangeHint(now) or nil
	if hint == "deadZone" and melee == nil then
		return "close"
	end
	return hint or "noShot"
end

function Range:Wanted(status)
	local show = self.db.show
	if show == "combat" and not InCombat() then
		return false
	end
	if show == "problems" and status == "ranged" then
		return false
	end
	return true
end

-- "facing" or "lineOfSight" while your last attacks failed for that reason
-- (reported by the game; see AutoShot:UI_ERROR_MESSAGE).
local function AttackProblem()
	local autoShot = ns.modules.AutoShot
	return autoShot.enabled and autoShot:GetProblem(GetTime()) or nil
end

-- "aspect" in combat while your aspect needs changing (see Modules\Aspect.lua).
local function AspectWarning()
	local aspect = ns.modules.Aspect
	return aspect and aspect.enabled and aspect:Warning() or nil
end

---------------------------------------------------------------------------
-- Hunter's Mark reminder
---------------------------------------------------------------------------
-- You can only have one Hunter's Mark out, so the reminder asks "is my mark on
-- an enemy I can shoot?", not "is my target marked?". In combat the game hides
-- aura details from addons, so the mark is followed three ways:
--  1. Its aura on your target, read directly whenever the game allows: out of
--     combat, and in combat too if this client flags Hunter's Mark as never
--     secret (C_Secrets says so).
--  2. Its aura instance ID, a plain number even in combat. It is learned when
--     the aura is read directly, or as the one new debuff of yours on the
--     target right after you cast the mark. Then it is looked for on your
--     target and on enemy nameplates, which also tells whether the marked
--     enemy is alive and in Auto Shot range.
--  3. Its two minutes, when neither can see it (enemy nameplates hidden, or a
--     client that keeps aura IDs from addons in combat).
local MARK_FILTER = "HARMFUL|PLAYER" -- debuffs you (or your pet) put on a unit
local NAMEPLATE_SECONDS = 0.5 -- how often enemy nameplates are searched
local NAMEPLATE_UNITS = 40
local CAST_WINDOW_SECONDS = 1.5 -- how long after a cast its aura is looked for
local markName -- localized "Hunter's Mark", looked up when the module starts
local mark -- what is known about your mark (see ForgetMark)

-- A fight ended or the mark is gone: start over.
local function ForgetMark()
	mark = {
		id = nil, -- aura instance ID of your mark
		untilTime = nil, -- when it runs out at the latest
		onTarget = nil, -- your current target has it: true, false, or nil (can't tell)
		targetIDs = nil, -- your debuffs on the target at the last check
		baseline = nil, -- your debuffs on the target when you cast the mark
		baselineUntil = 0,
		idsWork = false, -- the ID was found in combat, so not finding it means something
		scanAt = -math.huge,
		where = nil, -- last nameplate search: "near", "far", "gone" or nil (can't tell)
	}
end
ForgetMark()

-- Your debuffs on a unit as a set of aura instance IDs, or nil if the game won't say.
local function MyDebuffs(unit)
	if not (C_UnitAuras.GetUnitAuraInstanceIDs and UnitExists(unit)) then
		return nil
	end
	local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, MARK_FILTER)
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

-- Whether a missing Hunter's Mark aura on the target really means it isn't there.
local function MarkAuraReadable()
	if not InCombatLockdown() then
		return true
	end
	return C_Secrets ~= nil and C_Secrets.ShouldSpellAuraBeSecret ~= nil
		and ns.Readable(C_Secrets.ShouldSpellAuraBeSecret(HUNTERS_MARK_SPELL_ID)) == false
end

local function TrackMark(now)
	if mark.untilTime and now > mark.untilTime then
		ForgetMark() -- it has run out (a direct read finds it again if it hasn't)
	end
	local onTarget
	local aura = ns.Readable(C_UnitAuras.GetAuraDataBySpellName("target", markName, "HARMFUL"))
	if aura then
		onTarget = true
		mark.id = ns.Readable(aura.auraInstanceID) or mark.id
		local expires = ns.Readable(aura.expirationTime)
		mark.untilTime = expires and expires > now and expires or now + MARK_SECONDS
	elseif MarkAuraReadable() then
		onTarget = false
	end
	local ids = MyDebuffs("target")
	if ids then
		if mark.baseline then
			-- Just cast: the one debuff of yours that wasn't on the target before is the mark.
			local new
			for id in pairs(ids) do
				if not mark.baseline[id] then
					new = new == nil and id or false
				end
			end
			if new then
				mark.id, mark.baseline = new, nil
				ns.Debug("Range: Hunter's Mark is aura", new)
			elseif now > mark.baselineUntil then
				mark.baseline = nil
			end
		end
		if mark.id and ids[mark.id] then
			onTarget = true
			mark.idsWork = mark.idsWork or InCombatLockdown()
		elseif onTarget == nil and mark.id then
			onTarget = false
		end
		mark.targetIDs = ids
	end
	if onTarget == nil then
		onTarget = mark.onTarget -- can't tell now: keep what was known about this target
	end
	if mark.onTarget and (onTarget == false or ns.Readable(UnitIsDead("target"))) then
		-- It was on this target and isn't any more: it ran out, or the target died with it.
		ns.Debug("Range: Hunter's Mark is gone")
		ForgetMark()
		return
	end
	mark.onTarget = onTarget
end

-- True when enemy nameplates reach as far as Auto Shot does, so an enemy missing
-- from them is out of range or dead.
local function NameplatesCoverAutoShot()
	local distance = tonumber(ns.Readable(C_CVar.GetCVar("nameplateMaxDistance")) or "")
	return distance ~= nil and distance >= AUTO_SHOT_YARDS
end

-- Where your mark is, from enemy nameplates: "near" (on a living enemy in Auto
-- Shot range), "far", "gone" (nameplates show enemies, none with your mark), or
-- nil when it can't tell.
local function FindMark(now)
	if now - mark.scanAt < NAMEPLATE_SECONDS then
		return mark.where
	end
	mark.scanAt, mark.where = now, nil
	local enemies = 0
	for i = 1, NAMEPLATE_UNITS do
		local unit = "nameplate" .. i
		if UnitExists(unit) and ns.Readable(UnitCanAttack("player", unit)) then
			enemies = enemies + 1
			local ids = MyDebuffs(unit)
			if ids and ids[mark.id] then
				mark.idsWork = mark.idsWork or InCombatLockdown()
				if ns.Readable(UnitIsDead(unit)) then
					mark.where = "gone"
				else
					local inRange = ns.Readable(C_Spell.IsSpellInRange(AUTO_SHOT_SPELL_ID, unit))
					mark.where = inRange == false and "far" or "near"
				end
				return mark.where
			end
		end
	end
	if enemies > 0 and mark.idsWork and NameplatesCoverAutoShot() then
		mark.where = "gone"
	end
	return mark.where
end

-- "noMark" in combat while your mark isn't on a living enemy you can shoot.
function Range:MarkReminder(now)
	if not (self.db.markAlert and markName and InCombat()) then
		return nil
	end
	-- nil when you haven't learned the spell or the target can't be marked
	if ns.Readable(C_Spell.IsSpellInRange(markName, "target")) == nil then
		return nil
	end
	if mark.onTarget then
		return nil
	end
	local where = mark.id and FindMark(now) or nil
	if where == "near" then
		return nil
	elseif where == nil and mark.untilTime and now < mark.untilTime then
		return nil -- out of sight, but it hasn't run out
	end
	return "noMark"
end

function Range:Update()
	local frame, db = self.frame, self.db
	local now = GetTime()
	local hasTarget = UnitExists("target")
	local status = hasTarget and self:Evaluate() or nil
	if hasTarget and markName then
		TrackMark(now)
	end
	local sample = preview or ns:IsUnlocked()
	if not status and sample then
		status = SAMPLE_STATUS
	end
	self.status = status
	-- Warnings take the text; the strip keeps showing the range band.
	local key = status and (AttackProblem() or AspectWarning() or (hasTarget and self:MarkReminder(now))) or status
	local visible = key and (sample or key ~= status or self:Wanted(status))
	if visible then
		local text, color
		if key == "aspect" then
			text, color = ns.modules.Aspect:WarningText()
		else
			text, color = db.labels[key], db.colors[key]
		end
		frame.text:SetText(text)
		frame.text:SetTextColor(color[1], color[2], color[3])
		frame.text:Show()
	else
		frame.text:Hide()
	end
	frame.strip:SetShown(visible and db.style == "strip")
	-- Light the band you are in. "No shot" could be either band next to Auto Shot
	-- range, "too close" either band below it.
	for _, band in ipairs(BANDS) do
		local alpha = DIM
		if band == status then
			alpha = LIT
		elseif status == "noShot" and (band == "deadZone" or band == "tooFar") then
			alpha = UNSURE
		elseif status == "close" and (band == "melee" or band == "deadZone") then
			alpha = UNSURE
		end
		frame.segments[band]:SetAlpha(alpha)
	end
end

-- The frame (and its polling) runs only while there is something to check.
function Range:Refresh()
	local frame = self.frame
	if not frame then
		return
	end
	local active = self.db.enabled and (UnitExists("target") or preview or ns:IsUnlocked())
	if active then
		frame:Show()
		self:Update()
	else
		frame:Hide()
	end
end

function Range:BuildFrame()
	local frame = CreateFrame("Frame", "DeadeyeRangeFrame", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.strip = CreateFrame("Frame", nil, frame)
	local stripBackground = frame.strip:CreateTexture(nil, "BACKGROUND")
	stripBackground:SetAllPoints()
	stripBackground:SetColorTexture(0, 0, 0, 0.6)
	frame.segments = {}
	for _, band in ipairs(BANDS) do
		frame.segments[band] = frame.strip:CreateTexture(nil, "ARTWORK")
	end
	frame.elapsed = 0
	frame:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = self.elapsed + elapsed
		if self.elapsed >= POLL_SECONDS then
			self.elapsed = 0
			Range:Update()
		end
	end)
	frame:Hide()
	ns.Frames.MakeMovable(self, frame, L["Range"])
	self.frame = frame
end

-- Attached, the text sits just above the Auto Shot bar (clear of its border,
-- text and icon) and follows it around; otherwise it has its own position.
function Range:ApplyAnchor()
	local frame, autoShot = self.frame, ns.modules.AutoShot
	if self.db.attach == "BAR" and autoShot.bar then
		frame:ClearAllPoints()
		frame:SetPoint("BOTTOM", autoShot.bar, "TOP", 0, 3 + autoShot:TopClearance())
	else
		ns.Frames.ApplyPosition(self, frame)
	end
end

function Range:ApplyLayout()
	local db, frame = self.db, self.frame
	ns.Media.ApplyFont(frame.text, db.font, db.fontSize, db.fontOutline)
	frame.text:ClearAllPoints()
	frame.strip:ClearAllPoints()
	if db.style == "strip" then
		local width, height = db.stripWidth, db.stripHeight
		frame:SetSize(math.max(width, db.fontSize * 7), db.fontSize + 6 + height)
		frame.strip:SetSize(width, height)
		frame.strip:SetPoint("BOTTOM")
		frame.text:SetPoint("BOTTOM", frame.strip, "TOP", 0, 2)
		local x = 0
		for _, band in ipairs(BANDS) do
			local segment, share = frame.segments[band], width * BAND_SHARE[band]
			local color = db.colors[band]
			segment:ClearAllPoints()
			segment:SetPoint("TOPLEFT", frame.strip, "TOPLEFT", x + 1, -1)
			segment:SetSize(math.max(share - 2, 1), math.max(height - 2, 1))
			segment:SetColorTexture(color[1], color[2], color[3], 1)
			x = x + share
		end
	else
		frame:SetSize(math.max(db.fontSize * 7, 60), db.fontSize + 10)
		frame.text:SetPoint("CENTER")
		frame.strip:Hide()
	end
	frame:SetScale(db.scale)
	ns.Frames.UpdateMover(frame)
	self:ApplyAnchor()
	self:Refresh()
end

-- Dragging the text away from the bar gives it a position of its own.
function Range:OnDragged()
	self.db.attach = "FREE"
end

function Range:OnOptionChanged()
	self:ApplyLayout()
end

Range.OnUnlockChanged = Range.ApplyLayout
Range.OnSettingsReset = Range.ApplyLayout

function Range:SetPreview(enabled)
	preview = enabled
	self:Refresh()
end

function Range:GetOptionSections()
	local general = {
		{ type = "toggle", label = L["Show the range indicator"], key = "enabled", slash = "enabled" },
		{ type = "select", label = L["Show it"], key = "show", values = SHOW_CHOICES, slash = "show" },
		{ type = "select", label = L["Where"], key = "attach", values = ATTACH_CHOICES, slash = "attach",
			set = function(value)
				if value == "FREE" and self.db.attach ~= "FREE" then
					ns.Frames.SavePosition(self, self.frame) -- stay where it is now
				end
				self.db.attach = value
				self:ApplyLayout()
			end },
		{ type = "select", label = L["Style"], key = "style", values = STYLE_CHOICES, slash = "style" },
	}
	for _, spec in ipairs(ns.Frames.PositionOptions(self)) do
		general[#general + 1] = spec
	end
	for _, spec in ipairs({
		{ type = "range", label = L["Strip width"], key = "stripWidth", min = 60, max = 400, step = 1, slash = "stripwidth" },
		{ type = "range", label = L["Strip height"], key = "stripHeight", min = 3, max = 30, step = 1, slash = "stripheight" },
		{ type = "toggle", label = L["Remind me to use Hunter's Mark in combat"], key = "markAlert", slash = "markalert" },
		{ type = "note", text = L["X/Y apply when it's not above the bar. In combat the dead zone and 'too far' both read as no shot."] },
	}) do
		general[#general + 1] = spec
	end
	return {
		{
			name = L["Range"],
			keys = { "enabled", "show", "attach", "style", "position", "scale", "stripWidth", "stripHeight", "markAlert" },
			controls = general,
		},
		{
			name = L["Range: colors"],
			keys = { "colors" },
			controls = {
				{ type = "color", label = L["Melee range"], key = "colors.melee", slash = "meleecolor" },
				{ type = "color", label = L["Auto Shot range"], key = "colors.ranged", slash = "rangedcolor" },
				{ type = "color", label = L["Dead zone"], key = "colors.deadZone", slash = "deadzonecolor" },
				{ type = "color", label = L["Too close (melee or dead zone)"], key = "colors.close", slash = "closecolor" },
				{ type = "color", label = L["No shot (in combat)"], key = "colors.noShot", slash = "noshotcolor" },
				{ type = "color", label = L["Too far"], key = "colors.tooFar", slash = "toofarcolor" },
				{ type = "color", label = L["Not facing the target"], key = "colors.facing", slash = "facingcolor" },
				{ type = "color", label = L["No line of sight"], key = "colors.lineOfSight", slash = "loscolor" },
				{ type = "color", label = L["No Hunter's Mark"], key = "colors.noMark", slash = "markcolor" },
			},
		},
		{
			name = L["Range: text"],
			keys = { "labels", "font", "fontSize", "fontOutline" },
			controls = {
				{ type = "input", label = L["Melee range"], key = "labels.melee", slash = "meleetext" },
				{ type = "input", label = L["Auto Shot range"], key = "labels.ranged", slash = "rangedtext" },
				{ type = "input", label = L["Dead zone"], key = "labels.deadZone", slash = "deadzonetext" },
				{ type = "input", label = L["Too close (melee or dead zone)"], key = "labels.close", slash = "closetext" },
				{ type = "input", label = L["No shot (in combat)"], key = "labels.noShot", slash = "noshottext" },
				{ type = "input", label = L["Too far"], key = "labels.tooFar", slash = "toofartext" },
				{ type = "input", label = L["Not facing the target"], key = "labels.facing", slash = "facingtext" },
				{ type = "input", label = L["No line of sight"], key = "labels.lineOfSight", slash = "lostext" },
				{ type = "input", label = L["No Hunter's Mark"], key = "labels.noMark", slash = "marktext" },
				{ type = "select", label = L["Font"], key = "font", slash = "font", values = function() return ns.Media.List("font") end },
				{ type = "range", label = L["Font size"], key = "fontSize", min = 8, max = 40, step = 1, slash = "fontsize" },
				{ type = "select", label = L["Outline"], key = "fontOutline", values = OUTLINES, slash = "outline" },
			},
		},
	}
end

function Range:ShouldEnable()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

function Range:OnEnable()
	-- 0.2.0 beta builds had no "attach": if you had dragged the text, keep it there.
	local db = self.db
	if not self.freshSettings and (db.layoutVersion or 1) < 2
		and not (db.position.x == 0 and db.position.y == OLD_DEFAULT_Y) then
		db.attach = "FREE"
	end
	db.layoutVersion = 2

	markName = C_Spell.GetSpellName(HUNTERS_MARK_SPELL_ID)
	self:BuildFrame()
	local events = ns.CreateEventFrame(self)
	for _, event in ipairs({ "PLAYER_TARGET_CHANGED", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		events:RegisterEvent(event)
	end
	events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
	pcall(events.RegisterEvent, events, "PLAYER_SWING") -- Forever's own swing event
	self.events = events
	self:ApplyLayout()
end

function Range:PLAYER_TARGET_CHANGED()
	-- A new target: nothing known about it yet. Your mark itself stays where it was.
	mark.onTarget, mark.targetIDs, mark.baseline = nil, nil, nil
	lastMeleeSwing = nil
	self:Refresh()
end

-- A melee swing (main or off hand) at your target proves you're in melee range.
function Range:PLAYER_SWING(_, swingType)
	swingType = ns.Readable(swingType)
	if swingType ~= nil and swingType ~= RANGED_SWING then
		lastMeleeSwing = GetTime()
	end
end

-- Your own casts stay readable in combat. A new mark replaces the old one
-- (you can only have one out); its aura is spotted on the next checks.
function Range:UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	if markName and not ns.IsSecret(spellID) and C_Spell.GetSpellName(spellID) == markName then
		local now, before = GetTime(), mark.targetIDs
		ForgetMark()
		mark.untilTime = now + MARK_SECONDS
		mark.baseline, mark.baselineUntil = before or {}, now + CAST_WINDOW_SECONDS
		self:Refresh()
	end
end

-- A new fight needs a new mark.
function Range:PLAYER_REGEN_ENABLED()
	ForgetMark()
	self:Refresh()
end

Range.PLAYER_ENTERING_WORLD = Range.Refresh
Range.PLAYER_REGEN_DISABLED = Range.Refresh
