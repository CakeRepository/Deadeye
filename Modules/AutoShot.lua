-- Auto Shot reload / aim bar.
--
-- How Auto Shot works on WoW: Forever (Classic hunter rules on the modern client):
--  * Each shot starts a cycle as long as your ranged speed. The last ~0.5s of
--    it is the aim window: you have to stand still and not be casting for the
--    shot to go off. Everything before that is reload, where you can move freely.
--  * Every shot fires PLAYER_SWING(swingDuration, Enum.PlayerSwingType.Ranged).
--    swingDuration is the current (hasted) ranged speed and stays readable in
--    combat, while UnitAttackSpeed / UnitRangedDamage return secret values there.
--  * If you are still moving when the shot is due, the client reports
--    UNIT_SPELLCAST_FAILED_QUIET for Auto Shot and retries about every 0.5s.
--  * The combat log is closed to addons, so nothing here depends on it.
local _, ns = ...
local L = ns.L

local AutoShot = ns:NewModule("AutoShot", {
	position = { x = 0, y = -220 }, -- bar center relative to the screen center, in UI units
	width = 220,
	height = 16,
	scale = 1,
	orientation = "HORIZONTAL",
	reverseFill = false,
	texture = "Blizzard",
	background = { 0, 0, 0, 0.55 },
	borderSize = 1,
	borderColor = { 0, 0, 0, 1 },
	showSpark = true,
	showMarker = true,
	showAimZone = true,
	aimZoneAlpha = 0.3,
	icon = "NONE",
	font = "Default",
	fontSize = 10,
	fontOutline = "OUTLINE",
	labelPosition = "LEFT",
	timerPosition = "RIGHT",
	timerDecimals = 1,
	labels = {
		reload = L["Reload"],
		aim = L["Aim"],
		moving = L["Moving"],
		casting = L["Casting"],
		outOfRange = L["Out of range"],
		facing = L["Face your target"],
		lineOfSight = L["No line of sight"],
		idle = L["Auto Shot"],
	},
	colors = {
		reload = { 0.95, 0.60, 0.15 },
		aim = { 0.25, 0.85, 0.30 },
		blocked = { 0.90, 0.20, 0.20 },
		idle = { 0.45, 0.45, 0.45 },
		text = { 1, 1, 1 },
		outOfRangeText = { 1, 0.35, 0.35 },
	},
	outOfRangeAlpha = 0.5,
	aimTime = 0.5, -- seconds you must stand still before each shot
	latency = true, -- start the aim window earlier by your world latency
	rangeCheck = true,
	show = "auto", -- "auto" (shooting or reloading), "always" or "combat"
	sound = "NONE", -- alert when the aim window starts (see Media.lua)
	soundOnlyMoving = true, -- ...but only once you are moving in it
	reportDelays = false, -- print how much Auto Shot time was lost after each fight
})
AutoShot.title = L["Auto Shot bar"]

local AUTO_SHOT_SPELL_ID = 75
local AUTO_SHOT_ICON = "Interface\\Icons\\Ability_Whirlwind"
local RANGED_SWING = Enum and Enum.PlayerSwingType and Enum.PlayerSwingType.Ranged or 2
local RETRY_INTERVAL = 0.5 -- the client retries a blocked Auto Shot about this often
local SAME_SHOT_WINDOW = 0.25 -- PLAYER_SWING and UNIT_SPELLCAST_SUCCEEDED report the same shot
local MAX_LATENCY = 0.4
local LATENCY_POLL = 5
local RANGE_POLL = 0.2
local FALLBACK_SPEED = 2.5 -- only used for drawing before the first shot is seen
local TEST_SPEED = 2.4
local OLD_DEFAULT_Y = -180 -- 0.1 and the 0.2.0 betas put the bar over the character
-- Why an attack failed, from the game's error messages (GetGameMessageInfo names).
-- Auto Shot retries about every 0.5s, so a problem that persists keeps refreshing.
local ATTACK_PROBLEMS = {
	ERR_BADATTACKFACING = "facing",
	SPELL_FAILED_UNIT_NOT_INFRONT = "facing",
	SPELL_FAILED_NOT_INFRONT = "facing",
	SPELL_FAILED_LINE_OF_SIGHT = "lineOfSight",
}
-- The same messages also say whether a target was too close or too far, which
-- the range indicator cannot otherwise tell apart in combat.
local RANGE_HINTS = {
	SPELL_FAILED_TOO_CLOSE = "deadZone",
	SPELL_FAILED_OUT_OF_RANGE = "tooFar",
	ERR_OUT_OF_RANGE = "tooFar",
}
local PROBLEM_SECONDS = 1.2
local DELAY_TOLERANCE = 0.15 -- shot-to-shot jitter that does not count as a delay
local MAX_DELAY = 10 -- longer gaps are breaks between pulls, not delays

-- point on the text, point on the bar, x, y, justification
local TEXT_ANCHORS = {
	LEFT = { "LEFT", "LEFT", 4, 0, "LEFT" },
	CENTER = { "CENTER", "CENTER", 0, 0, "CENTER" },
	RIGHT = { "RIGHT", "RIGHT", -4, 0, "RIGHT" },
	ABOVE = { "BOTTOM", "TOP", 0, 3, "CENTER" },
	BELOW = { "TOP", "BOTTOM", 0, -3, "CENTER" },
}

local CHOICES = {
	orientation = {
		{ value = "HORIZONTAL", text = L["Horizontal"] },
		{ value = "VERTICAL", text = L["Vertical"] },
	},
	textPosition = {
		{ value = "LEFT", text = L["Inside, left"] },
		{ value = "CENTER", text = L["Inside, center"] },
		{ value = "RIGHT", text = L["Inside, right"] },
		{ value = "ABOVE", text = L["Above the bar"] },
		{ value = "BELOW", text = L["Below the bar"] },
		{ value = "HIDDEN", text = L["Hidden"] },
	},
	icon = {
		{ value = "NONE", text = L["No icon"] },
		{ value = "LEFT", text = L["Left of the bar"] },
		{ value = "RIGHT", text = L["Right of the bar"] },
		{ value = "TOP", text = L["Above the bar"] },
		{ value = "BOTTOM", text = L["Below the bar"] },
	},
	outline = {
		{ value = "", text = L["None"] },
		{ value = "OUTLINE", text = L["Outline"] },
		{ value = "THICKOUTLINE", text = L["Thick outline"] },
	},
	decimals = {
		{ value = 0, text = "2" },
		{ value = 1, text = "1.6" },
		{ value = 2, text = "1.62" },
	},
	show = {
		{ value = "auto", text = L["While shooting or reloading"] },
		{ value = "combat", text = L["In combat"] },
		{ value = "always", text = L["Always"] },
	},
}

local IsPlayerMoving, IsFalling = IsPlayerMoving, IsFalling

local state = {
	shooting = false, -- Auto Shot is toggled on
	start = nil, -- GetTime() when the current cycle started (the last shot)
	duration = nil, -- length of the current cycle (ranged speed at that shot)
	synthetic = false, -- cycle made up for the first shot after turning Auto Shot on
	fake = false, -- cycle made up by test mode or the options preview
	due = false, -- the client already tried to fire this cycle's shot
	retryAt = nil, -- when the client retries a blocked shot
	lastSwing = nil, -- time of the last PLAYER_SWING for ranged
	lastDuration = nil, -- its swing duration
	countFrom = nil, -- last shot while Auto Shot stayed on (for the delay report)
	speed = nil, -- last known ranged speed (always a plain number)
	castGUID = nil, -- set while casting or channeling anything but Auto Shot
	moving = false, -- event-tracked fallback if IsPlayerMoving is unavailable
	inRange = nil, -- true, false or nil (unknown / no target)
	nextRangeCheck = 0,
	problem = nil, -- "facing" or "lineOfSight" after an attack failed for that reason
	problemUntil = 0,
	rangeHint = nil, -- "deadZone" or "tooFar" after an attack failed for that reason
	rangeHintUntil = 0,
	latency = 0,
	nextLatencyCheck = 0,
	cueFor = nil, -- cycle the stop-moving sound already played for
	test = false, -- /deadeye test
	preview = false, -- the options window is open
	fight = { shots = 0, delayed = 0, lost = 0 }, -- Auto Shot delays this fight
	lastFight = nil,
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function IsAutoShot(spellID)
	return not ns.IsSecret(spellID) and spellID == AUTO_SHOT_SPELL_ID
end

-- The stat APIs return secret values in combat; callers then keep the cached speed.
local function ReadRangedSpeed()
	local _, _, ranged = UnitAttackSpeed("player")
	ranged = ns.Readable(ranged)
	if ranged and ranged > 0 then
		return ranged
	end
	local speed = ns.Readable((UnitRangedDamage("player")))
	if speed and speed > 0 then
		return speed
	end
end

local function RefreshSpeed()
	state.speed = ReadRangedSpeed() or state.speed
end

local function IsMoving()
	if IsPlayerMoving then
		if IsPlayerMoving() then
			return true
		end
	elseif state.moving then
		return true
	end
	return IsFalling ~= nil and IsFalling() or false
end

local function IsBlocked()
	return state.castGUID ~= nil or IsMoving()
end

local function InCombat()
	return ns.Readable(UnitAffectingCombat("player"), false)
end

local function UpdateLatency(now)
	if now < state.nextLatencyCheck then
		return
	end
	state.nextLatencyCheck = now + LATENCY_POLL
	local world = GetNetStats and ns.Readable((select(4, GetNetStats())))
	state.latency = world and math.min(world / 1000, MAX_LATENCY) or 0
end

local function AimWindow()
	local db = AutoShot.db
	return db.aimTime + (db.latency and state.latency or 0)
end

local function CheckRange(now)
	if now < state.nextRangeCheck then
		return
	end
	state.nextRangeCheck = now + RANGE_POLL
	local inRange
	if AutoShot.db.rangeCheck then
		if C_Spell and C_Spell.IsSpellInRange then
			inRange = ns.Readable(C_Spell.IsSpellInRange(AUTO_SHOT_SPELL_ID, "target"))
		end
		if inRange == nil and C_SwingTimer and C_SwingTimer.IsTargetWithinSwingRange then
			inRange = ns.Readable(C_SwingTimer.IsTargetWithinSwingRange(RANGED_SWING))
		end
	end
	state.inRange = inRange
end

local function StartCycle(start, duration, synthetic)
	state.start, state.duration = start, duration
	state.synthetic, state.fake, state.due = synthetic or false, false, false
	state.retryAt = nil
end

local function ClearCycle()
	state.start, state.duration = nil, nil
	state.synthetic, state.fake, state.due = false, false, false
	state.retryAt = nil
end

local function CycleActive(now)
	return state.start ~= nil and not state.due and now < state.start + state.duration
end

-- Test mode and the options preview loop fake shots, unless you are really shooting.
local function Simulating()
	return (state.test or state.preview) and not state.shooting
end

local function AdvanceSimulation(now)
	if not state.start or (now >= state.start + state.duration and not IsBlocked()) then
		StartCycle(now, state.speed or TEST_SPEED)
		state.fake = true
	end
end

-- Returns phase ("reload", "aim", "blocked" or "idle"), bar fill (0-1),
-- seconds until the shot (or nil) and the cycle length used for drawing.
local function Evaluate(now)
	if CycleActive(now) then
		local duration = state.duration
		local elapsed = now - state.start
		if elapsed < duration - AimWindow() then
			return "reload", elapsed / duration, duration - elapsed, duration
		end
		return IsBlocked() and "blocked" or "aim", elapsed / duration, duration - elapsed, duration
	end
	if state.shooting or Simulating() then
		-- The cycle is over but the shot has not gone off yet.
		local left = state.retryAt and state.retryAt > now and state.retryAt - now or nil
		return IsBlocked() and "blocked" or "aim", 1, left, state.duration or state.speed
	end
	return "idle", 0, nil, state.speed
end

---------------------------------------------------------------------------
-- Bar
---------------------------------------------------------------------------
function AutoShot:CreateBar()
	local bar = CreateFrame("Frame", "DeadeyeAutoShotBar", UIParent)
	bar:SetFrameStrata("MEDIUM")
	bar:SetScript("OnUpdate", function(frame)
		local now = GetTime()
		if Simulating() then
			AdvanceSimulation(now)
		end
		if self:ShouldShow(now) then
			self:Render(now)
		else
			frame:Hide()
		end
	end)
	bar:Hide()

	bar.background = bar:CreateTexture(nil, "BACKGROUND")
	bar.background:SetAllPoints()

	bar.edges = {}
	for i = 1, 4 do
		bar.edges[i] = bar:CreateTexture(nil, "BORDER")
	end

	-- Tinted zone at the end of the bar: the aim window, where you stand still.
	bar.aimZone = bar:CreateTexture(nil, "ARTWORK")

	bar.icon = bar:CreateTexture(nil, "ARTWORK")
	bar.icon:SetTexture(C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(AUTO_SHOT_SPELL_ID) or AUTO_SHOT_ICON)
	bar.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

	local status = CreateFrame("StatusBar", nil, bar)
	status:SetAllPoints()
	status:SetMinMaxValues(0, 1)
	status:SetValue(0)
	bar.status = status

	bar.marker = status:CreateTexture(nil, "OVERLAY")
	bar.marker:SetColorTexture(1, 1, 1, 0.85)

	bar.spark = status:CreateTexture(nil, "OVERLAY")
	bar.spark:SetColorTexture(1, 1, 1, 0.9)
	bar.spark:SetBlendMode("ADD")

	bar.label = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
	bar.time = status:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")

	ns.Frames.MakeMovable(self, bar, L["Auto Shot"])
	self.bar = bar
end

function AutoShot:ApplyBorder()
	local bar, size, color = self.bar, self.db.borderSize, self.db.borderColor
	local top, bottom, left, right = bar.edges[1], bar.edges[2], bar.edges[3], bar.edges[4]
	for _, edge in ipairs(bar.edges) do
		edge:ClearAllPoints()
		edge:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
		edge:SetShown(size > 0)
	end
	if size <= 0 then
		return
	end
	top:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", -size, 0)
	top:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", size, 0)
	top:SetHeight(size)
	bottom:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", -size, 0)
	bottom:SetPoint("TOPRIGHT", bar, "BOTTOMRIGHT", size, 0)
	bottom:SetHeight(size)
	left:SetPoint("TOPRIGHT", bar, "TOPLEFT")
	left:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT")
	left:SetWidth(size)
	right:SetPoint("TOPLEFT", bar, "TOPRIGHT")
	right:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT")
	right:SetWidth(size)
end

function AutoShot:ApplyText(fontString, position)
	local db = self.db
	local anchor = TEXT_ANCHORS[position]
	fontString:ClearAllPoints()
	if not anchor then
		fontString:Hide()
		return
	end
	ns.Media.ApplyFont(fontString, db.font, db.fontSize, db.fontOutline)
	local y = anchor[4]
	if position == "ABOVE" then
		y = y + db.borderSize
	elseif position == "BELOW" then
		y = y - db.borderSize
	end
	fontString:SetPoint(anchor[1], self.bar, anchor[2], anchor[3], y)
	fontString:SetJustifyH(anchor[5])
	fontString:Show()
end

function AutoShot:ApplyIcon()
	local db, bar = self.db, self.bar
	local icon = bar.icon
	icon:ClearAllPoints()
	if db.icon == "NONE" then
		icon:Hide()
		return
	end
	local size = db.orientation == "VERTICAL" and db.width or db.height
	local gap = db.borderSize + 2
	icon:SetSize(size, size)
	if db.icon == "LEFT" then
		icon:SetPoint("RIGHT", bar, "LEFT", -gap, 0)
	elseif db.icon == "RIGHT" then
		icon:SetPoint("LEFT", bar, "RIGHT", gap, 0)
	elseif db.icon == "TOP" then
		icon:SetPoint("BOTTOM", bar, "TOP", 0, gap)
	else
		icon:SetPoint("TOP", bar, "BOTTOM", 0, -gap)
	end
	icon:Show()
end

function AutoShot:ApplyLayout()
	local db, bar = self.db, self.bar
	local vertical, reverse = db.orientation == "VERTICAL", db.reverseFill
	bar:SetSize(db.width, db.height)
	bar:SetScale(db.scale)

	local background = db.background
	bar.background:SetColorTexture(background[1], background[2], background[3], background[4] or 1)
	self:ApplyBorder()

	local status = bar.status
	status:SetStatusBarTexture(ns.Media.Texture(db.texture))
	status:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
	status:SetReverseFill(reverse)

	-- The aim window sits where the fill ends; the marker is its inner edge.
	local aimZone, marker, spark = bar.aimZone, bar.marker, bar.spark
	aimZone:ClearAllPoints()
	marker:ClearAllPoints()
	spark:ClearAllPoints()
	if vertical then
		local outer, inner = reverse and "BOTTOM" or "TOP", reverse and "TOP" or "BOTTOM"
		aimZone:SetPoint(outer .. "LEFT")
		aimZone:SetPoint(outer .. "RIGHT")
		marker:SetPoint("LEFT", aimZone, inner .. "LEFT")
		marker:SetPoint("RIGHT", aimZone, inner .. "RIGHT")
		marker:SetHeight(1)
		spark:SetSize(db.width, 2)
	else
		local outer, inner = reverse and "LEFT" or "RIGHT", reverse and "RIGHT" or "LEFT"
		aimZone:SetPoint("TOP" .. outer)
		aimZone:SetPoint("BOTTOM" .. outer)
		marker:SetPoint("TOP", aimZone, "TOP" .. inner)
		marker:SetPoint("BOTTOM", aimZone, "BOTTOM" .. inner)
		marker:SetWidth(1)
		spark:SetSize(2, db.height)
	end
	local aim = db.colors.aim
	aimZone:SetColorTexture(aim[1], aim[2], aim[3], db.aimZoneAlpha)
	aimZone:SetShown(db.showAimZone)
	marker:SetShown(db.showMarker)

	self:ApplyText(bar.label, db.labelPosition)
	self:ApplyText(bar.time, db.timerPosition)
	self.timerFormat = "%." .. db.timerDecimals .. "f"
	self:ApplyIcon()

	ns.Frames.UpdateMover(bar)
	ns.Frames.ApplyPosition(self, bar)
	local range = ns.modules.Range
	if range and range.frame then
		range:ApplyAnchor() -- the range text can sit on top of the bar
	end
	self:Refresh()
end

-- Space above the bar taken by its border, text placed above it and an icon on top.
function AutoShot:TopClearance()
	local db = self.db
	local clearance = db.borderSize
	if db.labelPosition == "ABOVE" or db.timerPosition == "ABOVE" then
		clearance = clearance + db.fontSize + 4
	end
	if db.icon == "TOP" then
		clearance = clearance + (db.orientation == "VERTICAL" and db.width or db.height) + 2
	end
	return clearance
end

-- "facing" or "lineOfSight" while recent attacks failed for that reason.
function AutoShot:GetProblem(now)
	if state.problem and now < state.problemUntil then
		return state.problem
	end
end

-- "deadZone" or "tooFar" while recent attacks failed for being too close or too far.
function AutoShot:GetRangeHint(now)
	if state.rangeHint and now < state.rangeHintUntil then
		return state.rangeHint
	end
end

function AutoShot:OnUnlockChanged()
	self:ApplyLayout()
end

function AutoShot:ShouldShow(now)
	local db = self.db
	if state.test or state.preview or ns:IsUnlocked() or db.show == "always" then
		return true
	end
	if state.shooting or CycleActive(now) then
		return true
	end
	return db.show == "combat" and InCombat()
end

-- The stop-moving alert: once per real cycle, as the aim window starts (or,
-- with soundOnlyMoving, the first moment you are moving inside it).
function AutoShot:PlayCue(now, phase)
	if phase == "reload" or phase == "idle" or state.fake or state.cueFor == state.start or not CycleActive(now) then
		return
	end
	local sound = ns.Media.Sound(self.db.sound)
	if not sound or (self.db.soundOnlyMoving and not IsMoving()) then
		return
	end
	state.cueFor = state.start
	PlaySound(sound, "Master")
end

function AutoShot:Render(now)
	UpdateLatency(now)
	CheckRange(now)
	local db, bar = self.db, self.bar
	local phase, fill, left, duration = Evaluate(now)
	local outOfRange = state.inRange == false and phase ~= "idle"

	local color = db.colors[phase]
	bar.status:SetStatusBarColor(color[1], color[2], color[3], outOfRange and db.outOfRangeAlpha or 1)
	bar.status:SetValue(fill)

	local vertical = db.orientation == "VERTICAL"
	local length = vertical and db.height or db.width
	local aimLength = math.max(length * math.min(AimWindow() / (duration or FALLBACK_SPEED), 1), 1)
	if vertical then
		bar.aimZone:SetHeight(aimLength)
	else
		bar.aimZone:SetWidth(aimLength)
	end

	local spark = bar.spark
	if db.showSpark and fill > 0 and fill < 1 then
		local offset = length * fill
		if vertical then
			if db.reverseFill then
				spark:SetPoint("CENTER", bar.status, "TOP", 0, -offset)
			else
				spark:SetPoint("CENTER", bar.status, "BOTTOM", 0, offset)
			end
		elseif db.reverseFill then
			spark:SetPoint("CENTER", bar.status, "RIGHT", -offset, 0)
		else
			spark:SetPoint("CENTER", bar.status, "LEFT", offset, 0)
		end
		spark:Show()
	else
		spark:Hide()
	end

	self:PlayCue(now, phase)

	local textColor = db.colors.text
	if bar.label:IsShown() then
		local problem = phase ~= "idle" and self:GetProblem(now)
		local key = phase
		if problem then
			key = problem
		elseif outOfRange then
			key = "outOfRange"
		elseif phase == "blocked" then
			key = state.castGUID and "casting" or "moving"
		end
		local labelColor = (problem or outOfRange) and db.colors.outOfRangeText or textColor
		bar.label:SetText(db.labels[key])
		bar.label:SetTextColor(labelColor[1], labelColor[2], labelColor[3])
	end
	if bar.time:IsShown() then
		if left then
			bar.time:SetFormattedText(self.timerFormat, left)
		elseif phase == "idle" and duration then
			bar.time:SetFormattedText("%.2fs", duration)
		else
			bar.time:SetText("")
		end
		bar.time:SetTextColor(textColor[1], textColor[2], textColor[3])
	end
end

function AutoShot:Refresh()
	local bar = self.bar
	if not bar then
		return
	end
	local now = GetTime()
	if Simulating() and not CycleActive(now) and not state.fake then
		AdvanceSimulation(now)
	end
	if self:ShouldShow(now) then
		bar:Show()
		self:Render(now)
	else
		bar:Hide()
	end
end

function AutoShot:SetOrientation(orientation)
	local db = self.db
	if db.orientation == orientation then
		return
	end
	-- Keep the bar long along its new direction.
	local vertical = orientation == "VERTICAL"
	if (vertical and db.width > db.height) or (not vertical and db.height > db.width) then
		db.width, db.height = db.height, db.width
	end
	db.orientation = orientation
	self:ApplyLayout()
end

local function EndSimulation()
	if not Simulating() and state.fake then
		ClearCycle()
	end
end

function AutoShot:SetTestMode(enabled)
	state.test = enabled
	EndSimulation()
	self:Refresh()
	if enabled then
		ns.Print(L["Test mode on: a fake Auto Shot loops. Move during the green aim window to see it turn red. /deadeye test to stop."])
	else
		ns.Print(L["Test mode off."])
	end
end

function AutoShot:SetPreview(enabled)
	if state.preview == enabled then
		return
	end
	state.preview = enabled
	EndSimulation()
	self:Refresh()
end

---------------------------------------------------------------------------
-- Delay report: how much Auto Shot time moving and casting cost this fight
---------------------------------------------------------------------------
local function CountShot(now, previousStart, previousDuration)
	local fight = state.fight
	fight.shots = fight.shots + 1
	if not (previousStart and previousDuration) then
		return
	end
	local late = (now - previousStart) - previousDuration
	if late > DELAY_TOLERANCE and late < MAX_DELAY then
		fight.delayed = fight.delayed + 1
		fight.lost = fight.lost + late
	end
end

local function DescribeFight(fight)
	return string.format(L["%d shots, %d held back, %.1fs of Auto Shot lost to moving or casting."],
		fight.shots, fight.delayed, fight.lost)
end

function AutoShot:ReportFight()
	local fight = state.fight
	state.lastFight = fight
	state.fight = { shots = 0, delayed = 0, lost = 0 }
	if self.db.reportDelays and fight.shots >= 3 then
		ns.Print(L["Last fight: %s"]:format(DescribeFight(fight)))
	end
end

---------------------------------------------------------------------------
-- Options window pages
---------------------------------------------------------------------------
function AutoShot:OnOptionChanged()
	self:ApplyLayout()
end

-- slash is the name used by /deadeye <name> <value> (see Options\Slash.lua).
function AutoShot:GetOptionSections()
	local function PlayChosenSound()
		local sound = ns.Media.Sound(self.db.sound)
		if sound then
			PlaySound(sound, "Master")
		end
	end
	local position = ns.Frames.PositionOptions(self)
	for _, spec in ipairs({
		{ type = "range", label = L["Width"], key = "width", min = 4, max = 800, step = 1, slash = "width" },
		{ type = "range", label = L["Height"], key = "height", min = 4, max = 400, step = 1, slash = "height" },
		{ type = "select", label = L["Orientation"], key = "orientation", values = CHOICES.orientation, slash = "orientation",
			set = function(value) self:SetOrientation(value) end },
		{ type = "toggle", label = L["Reverse the fill direction"], key = "reverseFill", slash = "reverse" },
		{ type = "note", text = L["You can also drag the bar while Blizzard's Edit Mode is open."] },
	}) do
		position[#position + 1] = spec
	end
	return {
		{
			name = L["Position & Size"],
			keys = { "position", "width", "height", "scale", "orientation", "reverseFill" },
			controls = position,
		},
		{
			name = L["Bar"],
			keys = { "texture", "background", "borderSize", "borderColor", "showSpark", "showMarker", "showAimZone", "aimZoneAlpha", "icon" },
			controls = {
				{ type = "select", label = L["Texture"], key = "texture", slash = "texture",
					values = function() return ns.Media.List("statusbar") end },
				{ type = "color", label = L["Background"], key = "background", alpha = true, slash = "background" },
				{ type = "range", label = L["Border size"], key = "borderSize", min = 0, max = 6, step = 1, slash = "border" },
				{ type = "color", label = L["Border color"], key = "borderColor", alpha = true, slash = "bordercolor" },
				{ type = "select", label = L["Auto Shot icon"], key = "icon", values = CHOICES.icon, slash = "icon" },
				{ type = "toggle", label = L["Spark at the fill edge"], key = "showSpark", slash = "spark" },
				{ type = "toggle", label = L["Line where the aim window starts"], key = "showMarker", slash = "marker" },
				{ type = "toggle", label = L["Shade the aim window"], key = "showAimZone", slash = "shade" },
				{ type = "range", label = L["Aim window shading"], key = "aimZoneAlpha", min = 0, max = 1, step = 0.05, slash = "shadealpha" },
			},
		},
		{
			name = L["Colors"],
			keys = { "colors", "outOfRangeAlpha" },
			controls = {
				{ type = "header", label = L["Bar fill"] },
				{ type = "color", label = L["Reloading (move freely)"], key = "colors.reload", slash = "reloadcolor" },
				{ type = "color", label = L["Aim window (stand still)"], key = "colors.aim", slash = "aimcolor" },
				{ type = "color", label = L["Moving or casting in the aim window"], key = "colors.blocked", slash = "blockedcolor" },
				{ type = "color", label = L["Idle"], key = "colors.idle", slash = "idlecolor" },
				{ type = "range", label = L["Fill opacity when out of range"], key = "outOfRangeAlpha", min = 0.1, max = 1, step = 0.05, slash = "rangealpha" },
				{ type = "header", label = L["Text"] },
				{ type = "color", label = L["Text"], key = "colors.text", slash = "textcolor" },
				{ type = "color", label = L["Warnings (range, facing, line of sight)"], key = "colors.outOfRangeText", slash = "warningcolor" },
			},
		},
		{
			name = L["Text"],
			keys = { "font", "fontSize", "fontOutline", "labelPosition", "timerPosition", "timerDecimals" },
			controls = {
				{ type = "select", label = L["Font"], key = "font", slash = "font",
					values = function() return ns.Media.List("font") end },
				{ type = "range", label = L["Font size"], key = "fontSize", min = 6, max = 32, step = 1, slash = "fontsize" },
				{ type = "select", label = L["Outline"], key = "fontOutline", values = CHOICES.outline, slash = "outline" },
				{ type = "select", label = L["Phase label"], key = "labelPosition", values = CHOICES.textPosition, slash = "label" },
				{ type = "select", label = L["Timer"], key = "timerPosition", values = CHOICES.textPosition, slash = "timer" },
				{ type = "select", label = L["Timer decimals"], key = "timerDecimals", values = CHOICES.decimals, slash = "decimals" },
			},
		},
		{
			name = L["Wording"],
			keys = { "labels" },
			controls = {
				{ type = "input", label = L["While reloading"], key = "labels.reload", slash = "reloadtext" },
				{ type = "input", label = L["In the aim window"], key = "labels.aim", slash = "aimtext" },
				{ type = "input", label = L["Moving in the aim window"], key = "labels.moving", slash = "movingtext" },
				{ type = "input", label = L["Casting in the aim window"], key = "labels.casting", slash = "castingtext" },
				{ type = "input", label = L["Target out of range"], key = "labels.outOfRange", slash = "rangetext" },
				{ type = "input", label = L["Not facing the target"], key = "labels.facing", slash = "facingtext" },
				{ type = "input", label = L["No line of sight"], key = "labels.lineOfSight", slash = "lostext" },
				{ type = "input", label = L["Idle"], key = "labels.idle", slash = "idletext" },
			},
		},
		{
			name = L["Timing & Alerts"],
			keys = { "show", "aimTime", "latency", "rangeCheck", "sound", "soundOnlyMoving", "reportDelays" },
			controls = {
				{ type = "select", label = L["Show the bar"], key = "show", values = CHOICES.show, slash = "show" },
				{ type = "range", label = L["Aim window (seconds)"], key = "aimTime", min = 0, max = 1.5, step = 0.05, slash = "aim" },
				{ type = "toggle", label = L["Add my latency to the aim window"], key = "latency", slash = "latency" },
				{ type = "toggle", label = L["Dim the bar when out of range"], key = "rangeCheck", slash = "rangecheck" },
				{ type = "toggle", label = L["Report lost Auto Shot time after fights"], key = "reportDelays", slash = "report" },
				{ type = "header", label = L["Stop-moving alert"] },
				{ type = "select", label = L["Sound when the aim window starts"], key = "sound", values = ns.Media.Sounds(), slash = "sound" },
				{ type = "toggle", label = L["Only if I'm moving in it"], key = "soundOnlyMoving", slash = "soundmoving" },
				{ type = "button", label = L["Play the sound"], func = PlayChosenSound, slash = "playsound" },
				{ type = "note", text = L["The aim window is the stretch where you must stand still for Auto Shot to fire."] },
			},
		},
	}
end

---------------------------------------------------------------------------
-- Module hooks and slash commands
---------------------------------------------------------------------------
local function BarCommand(handler)
	return function(arg)
		if not AutoShot.bar then
			ns.Print(L["The Auto Shot bar only runs on hunters."])
			return
		end
		handler(arg)
	end
end

-- Most bar settings are changed with /deadeye <setting> <value> (Options\Slash.lua);
-- these are the extra commands.
function AutoShot:OnInitialize()
	ns:RegisterCommand("test", "test", L["Loop a fake Auto Shot to preview the bar."], BarCommand(function()
		self:SetTestMode(not state.test)
	end))
	ns:RegisterCommand("stats", "stats", L["Show how much Auto Shot time the last fight lost to moving or casting."], BarCommand(function()
		local fight = state.lastFight
		if state.fight.shots > 0 and InCombat() then
			fight = state.fight
		end
		if not fight or fight.shots == 0 then
			ns.Print(L["No Auto Shots recorded yet."])
			return
		end
		ns.Print((fight == state.fight and L["This fight: %s"] or L["Last fight: %s"]):format(DescribeFight(fight)))
	end))
	ns:RegisterCommand("text", "text on|off", nil, BarCommand(function(arg)
		arg = arg:lower()
		local db = self.db
		local show = arg == "on" or (arg ~= "off" and db.labelPosition == "HIDDEN" and db.timerPosition == "HIDDEN")
		db.labelPosition = show and "LEFT" or "HIDDEN"
		db.timerPosition = show and "RIGHT" or "HIDDEN"
		self:ApplyLayout()
		ns.OptionsChanged()
		ns.Print(show and L["Bar text on."] or L["Bar text off."])
	end))
end

function AutoShot:ShouldEnable()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

-- Settings saved by version 0.1: the bar was anchored by an arbitrary point,
-- text had one on/off switch and the bar had its own lock.
function AutoShot:MigrateSettings()
	local db = self.db
	if db.showText == false then
		db.labelPosition, db.timerPosition = "HIDDEN", "HIDDEN"
	end
	db.showText, db.locked = nil, nil
	local position = db.position
	if position.point then
		local bar = self.bar
		bar:SetSize(db.width, db.height)
		bar:SetScale(db.scale)
		bar:ClearAllPoints()
		bar:SetPoint(position.point, UIParent, position.relativePoint or position.point, position.x or 0, position.y or 0)
		position.point, position.relativePoint = nil, nil
		if not ns.Frames.SavePosition(self, bar) then
			position.x, position.y = 0, ns.Frames.DefaultHudY()
		end
	end
	-- New installs, and earlier versions' spot over the character unless you moved
	-- the bar: put it below the character.
	if self.freshSettings or ((db.layoutVersion or 1) < 2 and position.x == 0 and position.y == OLD_DEFAULT_Y) then
		position.y = ns.Frames.DefaultHudY()
	end
	db.layoutVersion = 2
end

function AutoShot:OnEnable()
	self:CreateBar()
	self:MigrateSettings()

	local events = ns.CreateEventFrame(self)
	-- PLAYER_SWING is Forever's native swing event. pcall in case a later build
	-- renames it; Auto Shot's cast event is the fallback (see UNIT_SPELLCAST_SUCCEEDED).
	local ok, registered = pcall(events.RegisterEvent, events, "PLAYER_SWING")
	self.hasSwingEvent = ok and registered ~= false
	for _, event in ipairs({
		"START_AUTOREPEAT_SPELL", "STOP_AUTOREPEAT_SPELL",
		"PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_TARGET_CHANGED",
		"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
		"PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING", "WEAPON_SLOT_CHANGED",
		"UI_ERROR_MESSAGE",
	}) do
		events:RegisterEvent(event)
	end
	for _, event in ipairs({
		"UNIT_ATTACK_SPEED", "UNIT_RANGEDDAMAGE",
		"UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_FAILED_QUIET",
		"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
		"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
	}) do
		events:RegisterUnitEvent(event, "player")
	end
	self.events = events

	RefreshSpeed()
	self:ApplyLayout()
end

function AutoShot:OnSettingsReset()
	self:ApplyLayout()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function AutoShot:PLAYER_SWING(duration, swingType)
	if ns.IsSecret(swingType) or swingType ~= RANGED_SWING then
		return
	end
	duration = ns.Readable(duration, state.speed)
	if not duration or duration <= 0 then
		return
	end
	local now = GetTime()
	if state.lastSwing then
		ns.Debug("Auto Shot: speed", duration, "| since last shot", now - state.lastSwing)
	else
		ns.Debug("Auto Shot: speed", duration)
	end
	CountShot(now, state.countFrom, state.lastDuration)
	state.lastSwing, state.countFrom, state.lastDuration = now, now, duration
	state.speed = duration
	state.castGUID = nil -- a shot cannot go off mid-cast, so any cast is over
	state.problem, state.rangeHint = nil, nil -- and nothing is in the way any more
	StartCycle(now, duration)
	self:Refresh()
end

function AutoShot:AnchorFromCast(shotAt)
	local speed = ReadRangedSpeed() or state.speed
	if not speed then
		return
	end
	ns.Debug("Auto Shot (cast event): speed", speed)
	state.speed = speed
	StartCycle(shotAt, speed)
	self:Refresh()
end

function AutoShot:UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
	if not IsAutoShot(spellID) then
		return
	end
	local shotAt = GetTime()
	if not self.hasSwingEvent then
		self:AnchorFromCast(shotAt)
		return
	end
	-- PLAYER_SWING reports the same shot with an exact speed. Only use this
	-- event if PLAYER_SWING does not show up for it.
	C_Timer.After(SAME_SHOT_WINDOW, function()
		if not (state.lastSwing and math.abs(state.lastSwing - shotAt) < SAME_SHOT_WINDOW) then
			self:AnchorFromCast(shotAt)
		end
	end)
end

function AutoShot:UNIT_SPELLCAST_FAILED_QUIET(_, _, spellID)
	if not IsAutoShot(spellID) then
		return
	end
	local now = GetTime()
	if CycleActive(now) and now < state.start + state.duration - AimWindow() then
		return -- still reloading, so this was not the client trying to fire
	end
	ns.Debug("Auto Shot blocked", IsMoving() and "(moving)" or "")
	state.due = true
	state.retryAt = now + RETRY_INTERVAL
	self:Refresh()
end

function AutoShot:START_AUTOREPEAT_SPELL()
	state.shooting = true
	local now = GetTime()
	UpdateLatency(now)
	if state.fake then
		ClearCycle()
	end
	if not CycleActive(now) then
		-- Nothing to reload, so the first shot only needs the aim window. (On the
		-- beta it fires instantly instead; PLAYER_SWING then replaces this cycle.)
		-- The extra millisecond keeps float rounding from landing on the reload side.
		local speed = state.speed or ReadRangedSpeed() or FALLBACK_SPEED
		StartCycle(now - math.max(speed - AimWindow(), 0) - 0.001, speed, true)
	end
	ns.Debug("Auto Shot on")
	self:Refresh()
end

function AutoShot:STOP_AUTOREPEAT_SPELL()
	state.shooting = false
	state.retryAt = nil
	state.countFrom = nil -- a pause you chose is not a delay
	if state.synthetic then
		ClearCycle() -- nothing was fired, so there is no reload to finish
	end
	ns.Debug("Auto Shot off")
	self:Refresh()
end

function AutoShot:UNIT_SPELLCAST_START(_, castGUID, spellID)
	if not IsAutoShot(spellID) then
		state.castGUID = ns.Readable(castGUID, true)
	end
end
AutoShot.UNIT_SPELLCAST_CHANNEL_START = AutoShot.UNIT_SPELLCAST_START

function AutoShot:UNIT_SPELLCAST_STOP()
	state.castGUID = nil
end
AutoShot.UNIT_SPELLCAST_CHANNEL_STOP = AutoShot.UNIT_SPELLCAST_STOP
AutoShot.UNIT_SPELLCAST_INTERRUPTED = AutoShot.UNIT_SPELLCAST_STOP

-- Trying to cast something else mid-cast fails without ending the cast in
-- progress, so only a failure of that cast counts. (A secret GUID was stored
-- as true; then any failure ends it.)
function AutoShot:UNIT_SPELLCAST_FAILED(_, castGUID)
	if state.castGUID == true or ns.Readable(castGUID) == state.castGUID then
		state.castGUID = nil
	end
end

-- The game's error messages are the only way to learn that an attack failed
-- because you face the wrong way, lack line of sight, or stand too close or far.
function AutoShot:UI_ERROR_MESSAGE(errorType)
	if ns.IsSecret(errorType) or not GetGameMessageInfo then
		return
	end
	local name = ns.Readable((GetGameMessageInfo(errorType)), "")
	local now = GetTime()
	if ATTACK_PROBLEMS[name] then
		state.problem, state.problemUntil = ATTACK_PROBLEMS[name], now + PROBLEM_SECONDS
		ns.Debug("Attack failed:", name)
		self:Refresh()
	elseif RANGE_HINTS[name] then
		state.rangeHint, state.rangeHintUntil = RANGE_HINTS[name], now + PROBLEM_SECONDS
	end
end

function AutoShot:PLAYER_STARTED_MOVING()
	state.moving = true
end

function AutoShot:PLAYER_STOPPED_MOVING()
	state.moving = false
end

function AutoShot:PLAYER_TARGET_CHANGED()
	state.nextRangeCheck = 0
end

function AutoShot:UNIT_ATTACK_SPEED()
	RefreshSpeed() -- only succeeds out of combat; PLAYER_SWING keeps it current in combat
end
AutoShot.UNIT_RANGEDDAMAGE = AutoShot.UNIT_ATTACK_SPEED
AutoShot.WEAPON_SLOT_CHANGED = AutoShot.UNIT_ATTACK_SPEED

function AutoShot:PLAYER_REGEN_DISABLED()
	self:Refresh()
end

function AutoShot:PLAYER_REGEN_ENABLED()
	RefreshSpeed()
	self:ReportFight()
	self:Refresh()
end

function AutoShot:PLAYER_ENTERING_WORLD()
	state.shooting = false
	state.castGUID, state.countFrom = nil, nil
	ClearCycle()
	RefreshSpeed()
	self:Refresh()
end

function AutoShot:PLAYER_DEAD()
	state.shooting = false
	state.castGUID, state.countFrom = nil, nil
	ClearCycle()
	self:Refresh()
end

-- Exposed for the test harness and for future modules.
AutoShot.state = state
