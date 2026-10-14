-- Range to your target the way a hunter cares about it: melee, Auto Shot
-- range, or neither (the dead zone, or too far away).
--
-- C_Spell.IsSpellInRange with Auto Shot and a melee ability stays readable in
-- combat. Out of combat, CheckInteractDistance also tells the dead zone (about
-- 10 yards) from too far. In combat Blizzard restricts that call on enemies, so
-- the text then just says you have no shot.
local _, ns = ...

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
		melee = "Melee",
		ranged = "Ranged",
		deadZone = "Dead zone",
		noShot = "No shot",
		tooFar = "Out of range",
		facing = "Face your target",
		lineOfSight = "No line of sight",
		noMark = "Mark your target",
	},
	colors = {
		melee = { 1, 0.82, 0 },
		ranged = { 0.35, 0.9, 0.35 },
		deadZone = { 1, 0.3, 0.3 },
		noShot = { 1, 0.5, 0.15 },
		tooFar = { 0.65, 0.65, 0.65 },
		facing = { 1, 0.3, 0.3 },
		lineOfSight = { 1, 0.3, 0.3 },
		noMark = { 1, 0.4, 0.8 },
	},
})
Range.title = "Range indicator"
Range.slashPrefix = "range"

local AUTO_SHOT_SPELL_ID = 75
local HUNTERS_MARK_SPELL_ID = 1130 -- checked by name, so any rank counts
local MARK_SECONDS = 120 -- how long a mark lasts
-- Raptor Strike, Wing Clip, Mongoose Bite. Checked by name, so any rank you know counts.
local MELEE_SPELL_IDS = { 2973, 2974, 1495 }
local CLOSE_DISTANCE_INDEX = 3 -- CheckInteractDistance: duel range, about 10 yards
local POLL_SECONDS = 0.1
local SAMPLE_STATUS = "ranged" -- shown while previewing or moving the frame

local SHOW_CHOICES = {
	{ value = "target", text = "With a hostile target" },
	{ value = "combat", text = "Only in combat" },
	{ value = "problems", text = "Only when I can't shoot" },
}
local ATTACH_CHOICES = {
	{ value = "BAR", text = "Above the Auto Shot bar" },
	{ value = "FREE", text = "Anywhere (drag it)" },
}
local STYLE_CHOICES = {
	{ value = "strip", text = "Color strip and text" },
	{ value = "text", text = "Text only" },
}
-- The strip, near to far, and how much of its width each band gets.
local BANDS = { "melee", "deadZone", "ranged", "tooFar" }
local BAND_SHARE = { melee = 0.15, deadZone = 0.15, ranged = 0.5, tooFar = 0.2 }
local LIT, UNSURE, DIM = 1, 0.6, 0.18
local OLD_DEFAULT_Y = -150 -- 0.2.0 beta builds put the text over the character
local OUTLINES = {
	{ value = "", text = "None" },
	{ value = "OUTLINE", text = "Outline" },
	{ value = "THICKOUTLINE", text = "Thick outline" },
}

local preview = false

local function InCombat()
	return ns.Readable(UnitAffectingCombat("player"), false)
end

local function MeleeInRange()
	for _, spellID in ipairs(MELEE_SPELL_IDS) do
		local name = C_Spell.GetSpellName(spellID)
		if name then
			local inRange = ns.Readable(C_Spell.IsSpellInRange(name, "target"))
			if inRange ~= nil then
				return inRange
			end
		end
	end
end

-- "melee", "ranged", "deadZone", "tooFar", "noShot", or nil without an attackable target.
function Range:Evaluate()
	local ranged = ns.Readable(C_Spell.IsSpellInRange(AUTO_SHOT_SPELL_ID, "target"))
	local melee = MeleeInRange()
	if ranged == nil and melee == nil then
		return nil
	end
	if melee then
		return "melee"
	end
	if ranged then
		return "ranged"
	end
	if CheckInteractDistance and not InCombatLockdown() then
		local ok, close = pcall(CheckInteractDistance, "target", CLOSE_DISTANCE_INDEX)
		if ok then
			close = ns.Readable(close)
			if close == true then
				return "deadZone"
			elseif close == false then
				return "tooFar"
			end
		end
	end
	-- In combat: a recent "too close" / "out of range" from Auto Shot settles it.
	local autoShot = ns.modules.AutoShot
	return autoShot.enabled and autoShot:GetRangeHint(GetTime()) or "noShot"
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

---------------------------------------------------------------------------
-- Hunter's Mark reminder
---------------------------------------------------------------------------
-- The target's debuffs can be read out of combat, but in combat they are
-- secret (the query returns nothing). So the module remembers what it saw
-- before the pull and the marks you cast on your current target since.
local markName -- localized "Hunter's Mark", looked up when the module starts
local marked, markedAt -- what is known about the current target's mark

local function TrackMark(now)
	local aura = C_UnitAuras.GetAuraDataBySpellName("target", markName, "HARMFUL")
	if aura then
		marked, markedAt = true, now
	elseif not InCombatLockdown() then
		marked, markedAt = false, nil -- readable out of combat, so no aura means no mark
	elseif marked and now - markedAt > MARK_SECONDS then
		marked = nil -- it has worn off by now
	end
end

-- "noMark" in combat while your target has no known Hunter's Mark.
function Range:MarkReminder(now)
	if not (self.db.markAlert and markName and InCombat()) then
		return nil
	end
	-- nil when you haven't learned the spell or the target can't be marked
	if ns.Readable(C_Spell.IsSpellInRange(markName, "target")) == nil then
		return nil
	end
	if marked ~= true then
		return "noMark"
	end
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
	local key = status and (AttackProblem() or (hasTarget and self:MarkReminder(now))) or status
	local visible = key and (sample or key ~= status or self:Wanted(status))
	if visible then
		local color = db.colors[key]
		frame.text:SetText(db.labels[key])
		frame.text:SetTextColor(color[1], color[2], color[3])
		frame.text:Show()
	else
		frame.text:Hide()
	end
	frame.strip:SetShown(visible and db.style == "strip")
	-- Light the band you are in; "no shot" could be either band next to Auto Shot range.
	for _, band in ipairs(BANDS) do
		local alpha = DIM
		if band == status then
			alpha = LIT
		elseif status == "noShot" and (band == "deadZone" or band == "tooFar") then
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
	local frame = CreateFrame("Frame", "ForeverHunterRangeFrame", UIParent)
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
	ns.Frames.MakeMovable(self, frame, "Range")
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
		{ type = "toggle", label = "Show the range indicator", key = "enabled", slash = "enabled" },
		{ type = "select", label = "Show it", key = "show", values = SHOW_CHOICES, slash = "show" },
		{ type = "select", label = "Where", key = "attach", values = ATTACH_CHOICES, slash = "attach",
			set = function(value)
				if value == "FREE" and self.db.attach ~= "FREE" then
					ns.Frames.SavePosition(self, self.frame) -- stay where it is now
				end
				self.db.attach = value
				self:ApplyLayout()
			end },
		{ type = "select", label = "Style", key = "style", values = STYLE_CHOICES, slash = "style" },
	}
	for _, spec in ipairs(ns.Frames.PositionOptions(self)) do
		general[#general + 1] = spec
	end
	for _, spec in ipairs({
		{ type = "range", label = "Strip width", key = "stripWidth", min = 60, max = 400, step = 1, slash = "stripwidth" },
		{ type = "range", label = "Strip height", key = "stripHeight", min = 3, max = 30, step = 1, slash = "stripheight" },
		{ type = "select", label = "Font", key = "font", slash = "font", values = function() return ns.Media.List("font") end },
		{ type = "range", label = "Font size", key = "fontSize", min = 8, max = 40, step = 1, slash = "fontsize" },
		{ type = "select", label = "Outline", key = "fontOutline", values = OUTLINES, slash = "outline" },
		{ type = "toggle", label = "Remind me to use Hunter's Mark in combat", key = "markAlert", slash = "markalert" },
		{ type = "note", text = "X/Y apply when it's not above the bar. In combat the dead zone and \"too far\" both read as no shot." },
	}) do
		general[#general + 1] = spec
	end
	return {
		{
			name = "Range",
			keys = { "enabled", "show", "attach", "style", "position", "scale", "stripWidth", "stripHeight", "font", "fontSize", "fontOutline", "markAlert" },
			controls = general,
		},
		{
			name = "Range: colors",
			keys = { "colors" },
			controls = {
				{ type = "color", label = "Melee range", key = "colors.melee", slash = "meleecolor" },
				{ type = "color", label = "Auto Shot range", key = "colors.ranged", slash = "rangedcolor" },
				{ type = "color", label = "Dead zone", key = "colors.deadZone", slash = "deadzonecolor" },
				{ type = "color", label = "No shot (in combat)", key = "colors.noShot", slash = "noshotcolor" },
				{ type = "color", label = "Too far", key = "colors.tooFar", slash = "toofarcolor" },
				{ type = "color", label = "Not facing the target", key = "colors.facing", slash = "facingcolor" },
				{ type = "color", label = "No line of sight", key = "colors.lineOfSight", slash = "loscolor" },
				{ type = "color", label = "No Hunter's Mark", key = "colors.noMark", slash = "markcolor" },
			},
		},
		{
			name = "Range: wording",
			keys = { "labels" },
			controls = {
				{ type = "input", label = "Melee range", key = "labels.melee", slash = "meleetext" },
				{ type = "input", label = "Auto Shot range", key = "labels.ranged", slash = "rangedtext" },
				{ type = "input", label = "Dead zone", key = "labels.deadZone", slash = "deadzonetext" },
				{ type = "input", label = "No shot (in combat)", key = "labels.noShot", slash = "noshottext" },
				{ type = "input", label = "Too far", key = "labels.tooFar", slash = "toofartext" },
				{ type = "input", label = "Not facing the target", key = "labels.facing", slash = "facingtext" },
				{ type = "input", label = "No line of sight", key = "labels.lineOfSight", slash = "lostext" },
				{ type = "input", label = "No Hunter's Mark", key = "labels.noMark", slash = "marktext" },
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
	self.events = events
	self:ApplyLayout()
end

function Range:PLAYER_TARGET_CHANGED()
	marked, markedAt = nil, nil -- a new target: nothing known about its mark yet
	self:Refresh()
end

-- Your own casts stay readable in combat, so a Hunter's Mark you cast counts.
function Range:UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	if markName and not ns.IsSecret(spellID) and C_Spell.GetSpellName(spellID) == markName then
		marked, markedAt = true, GetTime()
		self:Refresh()
	end
end

Range.PLAYER_ENTERING_WORLD = Range.Refresh
Range.PLAYER_REGEN_DISABLED = Range.Refresh
Range.PLAYER_REGEN_ENABLED = Range.Refresh
