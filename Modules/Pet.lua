-- Your pet at a glance: happiness (and the damage bonus or penalty that comes
-- with it), loyalty, health and diet, with alerts when it needs feeding or is
-- missing at the start of a fight. Hover the panel for the details.
--
-- Pet health is a secret value for addons, so it is only ever handed to the
-- status bar, never read. Happiness, loyalty and diet come from C_PetInfo,
-- which stays readable.
local _, ns = ...

local Pet = ns:NewModule("Pet", {
	enabled = true,
	position = { x = -220, y = -220 }, -- left of the Auto Shot bar (y follows the screen size on first use)
	scale = 1,
	width = 170,
	show = "always", -- "always" or "attention" (only when something needs doing)
	showHealth = true,
	showLoyalty = true,
	feedAlert = true,
	missingAlert = true,
	alertSound = "PING",
	font = "Default",
	fontSize = 11,
	fontOutline = "",
	hadPet = false, -- set once a pet is seen, so hunters too low for a pet are not nagged
})
Pet.title = "Pet panel"
Pet.slashPrefix = "pet"

local HAPPY = 3
-- C_PetInfo.GetPetHappiness: 1 unhappy, 2 content, 3 happy (atlases from Blizzard's PetHappiness.lua)
local HAPPINESS = {
	{ text = "Unhappy", atlas = "UI-PetMad", color = { 1, 0.3, 0.3 } },
	{ text = "Content", atlas = "UI-PetNeutral", color = { 1, 0.82, 0 } },
	{ text = "Happy", atlas = "UI-PetHappiness", color = { 0.35, 0.9, 0.35 } },
}
local ALERT_COLOR = { 1, 0.3, 0.3 }
local PULSE_SECONDS = 6
local SAMPLE = { kind = "alive", name = "Your pet", happiness = HAPPY, damage = 125, loyaltyRate = 1, loyalty = "Loyalty Level 6 (Best Friend)" }

local SHOW_CHOICES = {
	{ value = "always", text = "Always" },
	{ value = "attention", text = "Only when it needs attention" },
}
local OUTLINES = {
	{ value = "", text = "None" },
	{ value = "OUTLINE", text = "Outline" },
	{ value = "THICKOUTLINE", text = "Thick outline" },
}

local preview = false
local lastHappiness

local function PetName(fallback)
	return ns.Readable(UnitName("pet"), fallback or "Your pet")
end

local function Diet()
	local foods = C_PetInfo.GetPetFoodTypes()
	if foods and #foods > 0 then
		return table.concat(foods, ", ")
	end
end

-- What the panel should show, or nil when there is nothing to show (no pet yet).
function Pet:Status()
	if UnitExists("pet") then
		self.db.hadPet = true
		if UnitIsDead("pet") then
			return { kind = "dead", name = UnitName("pet") }
		end
		local happiness, damage, loyaltyRate = C_PetInfo.GetPetHappiness()
		return {
			kind = "alive",
			name = UnitName("pet"),
			happiness = ns.Readable(happiness),
			damage = ns.Readable(damage),
			loyaltyRate = ns.Readable(loyaltyRate),
			loyalty = ns.Readable((C_PetInfo.GetPetLoyalty())),
		}
	end
	if self.db.hadPet then
		return { kind = "none" }
	end
end

function Pet:NeedsAttention(status)
	return status.kind ~= "alive" or (status.happiness ~= nil and status.happiness < HAPPY)
end

function Pet:Alert(message)
	ns.Print(message)
	local sound = ns.Media.Sound(self.db.alertSound)
	if sound then
		PlaySound(sound, "Master")
	end
	self.pulseUntil = GetTime() + PULSE_SECONDS
	self.frame:SetScript("OnUpdate", function(frame)
		local remaining = self.pulseUntil - GetTime()
		if remaining <= 0 then
			frame:SetAlpha(1)
			frame:SetScript("OnUpdate", nil)
		else
			frame:SetAlpha(0.55 + 0.45 * math.abs(math.cos(remaining * 4)))
		end
	end)
end

function Pet:Refresh()
	local frame, db = self.frame, self.db
	if not frame then
		return
	end
	local status = self:Status()
	local sample = preview or ns:IsUnlocked()
	if not db.enabled or not (status or sample) then
		frame:Hide()
		return
	end
	if not status or (sample and status.kind == "none") then
		status = SAMPLE
	elseif not sample and db.show == "attention" and not self:NeedsAttention(status) then
		frame:Hide()
		return
	end
	self.status = status

	local happiness = status.happiness and HAPPINESS[status.happiness]
	if happiness then
		frame.icon:SetAtlas(happiness.atlas)
		frame.icon:Show()
	else
		frame.icon:Hide()
	end

	local health = frame.health
	if status.kind == "alive" then
		frame.name:SetText(status.name)
		frame.name:SetTextColor(1, 1, 1)
		if happiness then
			frame.mood:SetText(status.damage and string.format("%s %d%%", happiness.text, status.damage) or happiness.text)
			frame.mood:SetTextColor(happiness.color[1], happiness.color[2], happiness.color[3])
		else
			frame.mood:SetText("")
		end
		if status == SAMPLE then
			health:SetMinMaxValues(0, 1)
			health:SetValue(0.8)
		else
			health:SetMinMaxValues(0, UnitHealthMax("pet"))
			health:SetValue(UnitHealth("pet")) -- secret: passed straight to the bar
		end
		health:SetStatusBarColor(0.2, 0.75, 0.25)
		local loyalty = status.loyalty or ""
		if status.loyaltyRate and status.loyaltyRate < 0 then
			loyalty = loyalty .. " (losing loyalty)"
		end
		frame.loyalty:SetText(loyalty)
	else
		frame.name:SetText(status.kind == "dead" and "Your pet is dead" or "No pet")
		frame.name:SetTextColor(ALERT_COLOR[1], ALERT_COLOR[2], ALERT_COLOR[3])
		frame.mood:SetText("")
		health:SetMinMaxValues(0, 1)
		health:SetValue(0)
		frame.loyalty:SetText(status.kind == "dead" and "Cast Revive Pet" or "Cast Call Pet")
	end
	frame:Show()
end

function Pet:ShowTooltip(owner)
	local status = self.status
	if not status then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if status.kind == "none" then
		GameTooltip:SetText("No pet")
		GameTooltip:AddLine("Cast Call Pet to bring it out.", 1, 1, 1)
	elseif status.kind == "dead" then
		GameTooltip:SetText(PetName())
		GameTooltip:AddLine("Dead. Cast Revive Pet.", 1, 1, 1)
	else
		GameTooltip:SetText(status == SAMPLE and SAMPLE.name or PetName())
		local happiness = status.happiness and HAPPINESS[status.happiness]
		if happiness then
			local line = happiness.text
			if status.damage then
				line = line .. string.format(": doing %d%% damage", status.damage)
			end
			GameTooltip:AddLine(line, happiness.color[1], happiness.color[2], happiness.color[3])
		end
		if status.loyalty then
			GameTooltip:AddLine(status.loyalty, 1, 1, 1)
		end
		if status.loyaltyRate and status.loyaltyRate ~= 0 then
			GameTooltip:AddLine(status.loyaltyRate > 0 and "Gaining loyalty" or "Losing loyalty: keep it happy", 1, 1, 1)
		end
		if status ~= SAMPLE then
			local total, used = C_PetInfo.GetPetTrainingPoints()
			total, used = ns.Readable(total), ns.Readable(used)
			if total and used then
				GameTooltip:AddLine(string.format("Training points: %d free of %d", total - used, total), 1, 1, 1)
			end
			local diet = Diet()
			if diet then
				GameTooltip:AddLine("Eats: " .. diet, 1, 1, 1)
			end
		end
	end
	GameTooltip:Show()
end

function Pet:BuildFrame()
	local frame = CreateFrame("Frame", "ForeverHunterPetFrame", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame.background = frame:CreateTexture(nil, "BACKGROUND")
	frame.background:SetAllPoints()
	frame.background:SetColorTexture(0, 0, 0, 0.55)

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(18, 18)
	frame.icon:SetPoint("TOPLEFT", 3, -3)

	frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.name:SetPoint("TOPLEFT", 25, -6)
	frame.name:SetJustifyH("LEFT")
	frame.mood = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.mood:SetPoint("TOPRIGHT", -5, -6)
	frame.mood:SetJustifyH("RIGHT")

	frame.health = CreateFrame("StatusBar", nil, frame)
	frame.health:SetStatusBarTexture(ns.Media.Texture("Blizzard"))
	frame.health:SetHeight(8)

	frame.loyalty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	frame.loyalty:SetJustifyH("LEFT")

	frame:Hide()
	frame:SetScript("OnEnter", function(owner)
		self:ShowTooltip(owner)
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	ns.Frames.MakeMovable(self, frame, "Pet", true)
	self.frame = frame
end

function Pet:ApplyLayout()
	local db, frame = self.db, self.frame
	for _, text in ipairs({ frame.name, frame.mood, frame.loyalty }) do
		ns.Media.ApplyFont(text, db.font, db.fontSize, db.fontOutline)
	end
	local y = -24
	frame.health:ClearAllPoints()
	frame.health:SetShown(db.showHealth)
	if db.showHealth then
		frame.health:SetPoint("TOPLEFT", 3, y)
		frame.health:SetPoint("TOPRIGHT", -3, y)
		y = y - 11
	end
	frame.loyalty:ClearAllPoints()
	frame.loyalty:SetShown(db.showLoyalty)
	if db.showLoyalty then
		frame.loyalty:SetPoint("TOPLEFT", 5, y - 1)
		frame.loyalty:SetPoint("TOPRIGHT", -5, y - 1)
		y = y - db.fontSize - 4
	end
	frame:SetSize(db.width, -y + 3)
	frame:SetScale(db.scale)
	ns.Frames.UpdateMover(frame)
	ns.Frames.ApplyPosition(self, frame)
	self:Refresh()
end

function Pet:OnOptionChanged()
	self:ApplyLayout()
end

Pet.OnUnlockChanged = Pet.ApplyLayout
Pet.OnSettingsReset = Pet.ApplyLayout

function Pet:SetPreview(enabled)
	preview = enabled
	self:Refresh()
end

function Pet:GetOptionSections()
	local general = {
		{ type = "toggle", label = "Show the pet panel", key = "enabled", slash = "enabled" },
		{ type = "select", label = "Show it", key = "show", values = SHOW_CHOICES, slash = "show" },
	}
	for _, spec in ipairs(ns.Frames.PositionOptions(self)) do
		general[#general + 1] = spec
	end
	for _, spec in ipairs({
		{ type = "range", label = "Width", key = "width", min = 100, max = 400, step = 1, slash = "width" },
		{ type = "toggle", label = "Health bar", key = "showHealth", slash = "health" },
		{ type = "toggle", label = "Loyalty line", key = "showLoyalty", slash = "loyalty" },
	}) do
		general[#general + 1] = spec
	end
	return {
		{
			name = "Pet",
			keys = { "enabled", "show", "position", "scale", "width", "showHealth", "showLoyalty" },
			controls = general,
		},
		{
			name = "Pet: alerts & text",
			keys = { "feedAlert", "missingAlert", "alertSound", "font", "fontSize", "fontOutline" },
			controls = {
				{ type = "toggle", label = "Tell me when my pet needs feeding", key = "feedAlert", slash = "feedalert" },
				{ type = "toggle", label = "Warn me in combat without my pet", key = "missingAlert", slash = "missingalert" },
				{ type = "select", label = "Alert sound", key = "alertSound", values = ns.Media.Sounds(), slash = "sound" },
				{ type = "button", label = "Play the sound", slash = "playsound", func = function()
					local sound = ns.Media.Sound(self.db.alertSound)
					if sound then
						PlaySound(sound, "Master")
					end
				end },
				{ type = "select", label = "Font", key = "font", slash = "font", values = function() return ns.Media.List("font") end },
				{ type = "range", label = "Font size", key = "fontSize", min = 8, max = 24, step = 1, slash = "fontsize" },
				{ type = "select", label = "Outline", key = "fontOutline", values = OUTLINES, slash = "outline" },
				{ type = "note", text = "A pet that isn't happy deals less damage and slowly loses loyalty. Hover the panel to see what it eats." },
			},
		},
	}
end

function Pet:ShouldEnable()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

function Pet:OnEnable()
	-- New installs, and 0.2.0 betas' spot unless you moved it: next to the Auto Shot bar.
	local position = self.db.position
	if self.freshSettings or ((self.db.layoutVersion or 1) < 2 and position.x == -260 and position.y == -180) then
		position.x, position.y = -220, ns.Frames.DefaultHudY()
	end
	self.db.layoutVersion = 2

	self:BuildFrame()
	local events = ns.CreateEventFrame(self)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PET_UI_UPDATE" }) do
		events:RegisterEvent(event)
	end
	events:RegisterUnitEvent("UNIT_PET", "player")
	for _, event in ipairs({ "UNIT_HAPPINESS", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE" }) do
		events:RegisterUnitEvent(event, "pet")
	end
	self.events = events
	lastHappiness = ns.Readable((C_PetInfo.GetPetHappiness()))
	self:ApplyLayout()
end

function Pet:UNIT_HAPPINESS()
	local happiness = ns.Readable((C_PetInfo.GetPetHappiness()))
	if self.db.enabled and self.db.feedAlert and happiness and lastHappiness and happiness < lastHappiness and happiness < HAPPY then
		local diet = Diet()
		self:Alert(string.format("%s is %s. Time to feed it%s.", PetName(), HAPPINESS[happiness].text:lower(), diet and " (eats " .. diet .. ")" or ""))
	end
	lastHappiness = happiness
	self:Refresh()
end

function Pet:UNIT_PET()
	lastHappiness = ns.Readable((C_PetInfo.GetPetHappiness()))
	self:Refresh()
end

function Pet:PLAYER_REGEN_DISABLED()
	if self.db.enabled and self.db.missingAlert and self.db.hadPet then
		if not UnitExists("pet") then
			self:Alert("You're in combat without your pet.")
		elseif UnitIsDead("pet") then
			self:Alert("Your pet is dead. Cast Revive Pet when you can.")
		end
	end
	self:Refresh()
end

Pet.PLAYER_ENTERING_WORLD = Pet.UNIT_PET
Pet.PET_UI_UPDATE = Pet.Refresh
Pet.UNIT_HEALTH = Pet.Refresh
Pet.UNIT_MAXHEALTH = Pet.Refresh
Pet.UNIT_NAME_UPDATE = Pet.Refresh
