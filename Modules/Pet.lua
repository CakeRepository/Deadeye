-- Your pet at a glance: happiness (and the damage bonus or penalty that comes
-- with it), loyalty, health and diet, with alerts when it needs feeding or is
-- missing at the start of a fight, and a button that feeds it. Hover the panel
-- for the details.
--
-- Pet health is a secret value for addons, so it is only ever handed to the
-- status bar, never read. Happiness, loyalty and diet come from C_PetInfo,
-- which stays readable.
--
-- Feeding casts a spell, which only Blizzard's secure templates may do for an
-- addon. The feed button is a SecureActionButtonTemplate: it casts Feed Pet and
-- then uses the food at its target-bag / target-slot attributes. A secure frame
-- cannot be shown, moved or reconfigured in combat, so those changes wait for
-- the end of the fight. It is kept apart from the panel (anchored to the screen,
-- not to the panel) so the panel itself stays free to change in combat.
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
	feedButton = true,
	skipFoods = {}, -- [itemID] = name: food the feed button leaves alone (right-click on it)
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
local BACKGROUND_COLOR = { 0, 0, 0, 0.55 }
local HUNGRY_COLOR = { 1, 0.82, 0, 0.9 } -- behind the feed button while the pet isn't happy
local PULSE_SECONDS = 6
local FEED_PET_SPELL_ID = 6991
local FEED_PET_ICON = "Interface\\Icons\\Ability_Hunter_BeastTraining"
local WELL_FED_SPELL_ID = 19705 -- the "Well Fed" buff, for its name in the game's language
local BAGS = { 0, 1, 2, 3, 4 } -- backpack and the four bag slots
local FOOD_LEVEL_STEP = 10 -- see FoodTier
local FEED_BUTTON_GAP = 3
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
local food, kept -- what the feed button uses, and the food it leaves alone (see FindFood)

local function PetName(fallback)
	return ns.Readable(UnitName("pet"), fallback or "Your pet")
end

local function Diet()
	local foods = C_PetInfo.GetPetFoodTypes()
	if foods and #foods > 0 then
		return table.concat(foods, ", ")
	end
end

-- Feed Pet gives the most happiness for food close to the pet's level. Every
-- FOOD_LEVEL_STEP levels below the pet gives less, and three steps down the pet
-- won't eat it. Returns 3 (the most happiness) down to 0 (probably not eaten).
local function FoodTier(level, petLevel)
	if not (level and petLevel) then
		return 1 -- not known yet: worth a try, after any food known to be good
	end
	return math.max(0, 3 - math.floor(math.max(0, petLevel - level) / FOOD_LEVEL_STEP))
end

-- Food that makes you "well fed" is worth more to you than to your pet. Only the
-- item's tooltip says so.
local function GivesBuff(itemID)
	local data = C_TooltipInfo and ns.Readable(C_TooltipInfo.GetItemByID(itemID))
	if not data then
		return false
	end
	local wellFed = ns.Readable(C_Spell.GetSpellName(WELL_FED_SPELL_ID))
	for _, line in ipairs(data.lines or {}) do
		local text = ns.Readable(line.leftText)
		if type(text) == "string" then
			text = text:lower()
			if text:find("well fed", 1, true) or (wellFed and text:find(wellFed:lower(), 1, true)) then
				return true
			end
		end
	end
	return false
end

local function BetterFood(a, b)
	if a.tier ~= b.tier then
		return a.tier > b.tier
	elseif a.level ~= b.level then
		return a.level < b.level -- so your better food lasts
	end
	return a.count < b.count -- frees a bag slot sooner
end

-- The food the feed button uses: the food in your bags your pet eats that gives
-- it the most happiness, lowest level first, then the smallest stack. Food that
-- makes you well fed, and food you skipped, are left alone and returned in the
-- second table (lists of names) so the tooltip can say why.
local function FindFood(skipped)
	local petLevel = ns.Readable(UnitLevel("pet"))
	local best
	local items, totals = {}, {}
	local spared = { buff = {}, skipped = {} }
	for _, bag in ipairs(BAGS) do
		for slot = 1, ns.Readable(C_Container.GetContainerNumSlots(bag), 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local itemID = info and ns.Readable(info.itemID)
			if itemID and ns.Readable(C_PetInfo.CanPetEatItem(itemID)) then
				local item = items[itemID]
				if not item then
					local itemName, _, _, level = C_Item.GetItemInfo(itemID)
					item = { name = ns.Readable(info.itemName) or ns.Readable(itemName), level = ns.Readable(level) }
					if skipped[itemID] then
						item.spared = spared.skipped
					elseif GivesBuff(itemID) then
						item.spared = spared.buff
					end
					if item.spared then
						item.spared[#item.spared + 1] = item.name or ("item " .. itemID)
					end
					items[itemID] = item
				end
				if not item.spared then
					local count = ns.Readable(info.stackCount, 1)
					totals[itemID] = (totals[itemID] or 0) + count
					local candidate = {
						bag = bag, slot = slot, itemID = itemID, count = count, name = item.name,
						level = item.level or 0, tier = FoodTier(item.level, petLevel), icon = ns.Readable(info.iconFileID),
					}
					if not best or BetterFood(candidate, best) then
						best = candidate
					end
				end
			end
		end
	end
	if best then
		best.total = totals[best.itemID]
	end
	return best, spared
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
		local alpha = remaining <= 0 and 1 or 0.55 + 0.45 * math.abs(math.cos(remaining * 4))
		frame:SetAlpha(alpha)
		if self.feedButton then
			self.feedButton:SetAlpha(alpha) -- unlike moving it, allowed in combat
		end
		if remaining <= 0 then
			frame:SetScript("OnUpdate", nil)
		end
	end)
end

-- Updates the panel and returns the status it shows, or nil when it is hidden.
function Pet:RefreshPanel()
	local frame, db = self.frame, self.db
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
	return status
end

function Pet:Refresh()
	if self.frame then
		self:UpdateFeedButton(self:RefreshPanel())
	end
end

-- The feed button's looks follow the pet at once, even in combat. Its place,
-- whether it shows and the food it uses are protected, so in combat they wait
-- until PLAYER_REGEN_ENABLED, which scans the bags and comes back here.
function Pet:UpdateFeedButton(status)
	local button = self.feedButton
	if not button then
		return
	end
	local alive = status ~= nil and status.kind == "alive"
	button.icon:SetTexture(food and food.icon or button.feedPetIcon)
	button.icon:SetDesaturated(not (food and alive))
	button.count:SetText(food and tostring(food.total) or "")
	local color = alive and status.happiness and status.happiness < HAPPY and HUNGRY_COLOR or BACKGROUND_COLOR
	button.background:SetColorTexture(color[1], color[2], color[3], color[4])
	if InCombatLockdown() then
		return
	end
	button:SetAttribute("target-bag", food and food.bag)
	button:SetAttribute("target-slot", food and food.slot)
	local db = self.db
	if not (db.feedButton and alive) then
		button:Hide()
		return
	end
	-- Beside the panel, on the side away from the middle of the screen (where the
	-- Auto Shot bar is). Like the panel, it is anchored to the screen's center.
	local size, scale = self.frame:GetHeight(), db.scale
	local side = db.position.x > 0 and 1 or -1
	button:SetScale(scale)
	button:SetSize(size, size)
	button:ClearAllPoints()
	button:SetPoint("CENTER", UIParent, "CENTER",
		db.position.x / scale + side * ((db.width + size) / 2 + FEED_BUTTON_GAP), db.position.y / scale)
	button:Show()
end

-- Scans the bags for the feed button's food. Every arrow fired changes your
-- bags, and the button can't change in combat anyway, so a fight waits for
-- PLAYER_REGEN_ENABLED.
function Pet:ScanFood()
	if not InCombatLockdown() then
		food, kept = FindFood(self.db.skipFoods)
	end
	self:Refresh()
end

-- Right-click on the feed button: leave this food alone from now on.
function Pet:SkipFood()
	if not food then
		return
	end
	self.db.skipFoods[food.itemID] = food.name or true
	ns.Print(string.format("The feed button will leave %s alone. /deadeye pet unskip undoes this.", food.name or "that food"))
	self:ScanFood()
end

function Pet:UnskipFoods()
	local names = {}
	for _, name in pairs(self.db.skipFoods) do
		if type(name) == "string" then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	self.db.skipFoods = {}
	if #names > 0 then
		ns.Print("The feed button can use " .. table.concat(names, ", ") .. " again.")
	else
		ns.Print("The feed button isn't skipping any food.")
	end
	self:ScanFood()
end

function Pet:ShowFeedTooltip(owner)
	local pet = PetName("your pet")
	local muted = 0.6
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText("Feed " .. pet)
	if food then
		GameTooltip:AddLine(string.format("%s (%d in your bags)", food.name or "Food", food.total), 1, 1, 1)
		if food.tier == 0 then
			GameTooltip:AddLine("Probably too low level for " .. pet .. " to eat.", ALERT_COLOR[1], ALERT_COLOR[2], ALERT_COLOR[3], true)
		elseif food.tier < 3 then
			GameTooltip:AddLine("Well below " .. pet .. "'s level, so it gives less happiness.", 1, 0.82, 0, true)
		end
		GameTooltip:AddLine("Right-click: skip this food", muted, muted, muted)
	else
		GameTooltip:AddLine("No food in your bags that " .. pet .. " eats.", ALERT_COLOR[1], ALERT_COLOR[2], ALERT_COLOR[3], true)
		local diet = Diet()
		if diet then
			GameTooltip:AddLine("Eats: " .. diet, 1, 1, 1)
		end
		GameTooltip:AddLine("Click to cast Feed Pet and pick a food yourself.", muted, muted, muted, true)
	end
	if kept and #kept.buff > 0 then
		GameTooltip:AddLine("Saved for you (well fed): " .. table.concat(kept.buff, ", "), muted, muted, muted, true)
	end
	if kept and #kept.skipped > 0 then
		GameTooltip:AddLine("Skipped: " .. table.concat(kept.skipped, ", ") .. ". /deadeye pet unskip uses them again.", muted, muted, muted, true)
	end
	GameTooltip:Show()
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
	local frame = CreateFrame("Frame", "DeadeyePetFrame", UIParent)
	frame:SetFrameStrata("MEDIUM")
	frame.background = frame:CreateTexture(nil, "BACKGROUND")
	frame.background:SetAllPoints()
	frame.background:SetColorTexture(BACKGROUND_COLOR[1], BACKGROUND_COLOR[2], BACKGROUND_COLOR[3], BACKGROUND_COLOR[4])

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

-- Secure frames are made out of combat: after a reload mid-fight this waits for
-- PLAYER_REGEN_ENABLED.
function Pet:BuildFeedButton()
	if self.feedButton or InCombatLockdown() then
		return
	end
	local button = CreateFrame("Button", "DeadeyeFeedButton", UIParent, "SecureActionButtonTemplate")
	button:SetFrameStrata("MEDIUM")
	-- Up and down, so a click works whichever way "cast on key down" is set.
	-- Right-clicks are left out: they skip the food (OnMouseUp) instead.
	button:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
	button:SetAttribute("type", "spell")
	button:SetAttribute("spell", FEED_PET_SPELL_ID)
	button.feedPetIcon = C_Spell.GetSpellTexture(FEED_PET_SPELL_ID) or FEED_PET_ICON

	button.background = button:CreateTexture(nil, "BACKGROUND")
	button.background:SetAllPoints()
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetPoint("TOPLEFT", 2, -2)
	button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
	button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	button.count = button:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
	button.count:SetPoint("BOTTOMRIGHT", -3, 3)
	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetPoint("TOPLEFT", 2, -2)
	highlight:SetPoint("BOTTOMRIGHT", -2, 2)
	highlight:SetColorTexture(1, 1, 1, 0.2)

	button:SetScript("OnEnter", function(owner)
		self:ShowFeedTooltip(owner)
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button:SetScript("OnMouseUp", function(_, mouseButton)
		if mouseButton == "RightButton" then
			self:SkipFood()
		end
	end)
	button:Hide()
	self.feedButton = button
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

-- The panel was dragged: the feed button follows (after the fight, if in one).
function Pet:OnDragged()
	self:Refresh()
end

Pet.OnUnlockChanged = Pet.ApplyLayout

function Pet:OnSettingsReset()
	self:ApplyLayout()
	self:ScanFood() -- skipped food may be allowed again
end

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
			name = "Pet: feeding",
			keys = { "feedButton", "feedAlert", "skipFoods" },
			controls = {
				{ type = "toggle", label = "Feed button next to the panel", key = "feedButton", slash = "feedbutton" },
				{ type = "toggle", label = "Tell me when my pet needs feeding", key = "feedAlert", slash = "feedalert" },
				{ type = "button", label = "Use skipped food again", slash = "unskip", func = function()
					self:UnskipFoods()
				end },
				{ type = "note", height = 120, text = "Click the button to feed your pet the food it shows. It picks food close to your pet's level, lowest level first so your better food lasts, and leaves food that makes you well fed alone. Right-click it to skip a food. With no food shown, a click casts Feed Pet so you can pick one in your bags.\n\nThe button can't change during a fight. It catches up when the fight ends." },
			},
		},
		{
			name = "Pet: alerts & text",
			keys = { "missingAlert", "alertSound", "font", "fontSize", "fontOutline" },
			controls = {
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
	self:BuildFeedButton()
	local events = ns.CreateEventFrame(self)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PET_UI_UPDATE", "BAG_UPDATE_DELAYED" }) do
		events:RegisterEvent(event)
	end
	events:RegisterUnitEvent("UNIT_PET", "player")
	for _, event in ipairs({ "UNIT_HAPPINESS", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_NAME_UPDATE", "UNIT_LEVEL" }) do
		events:RegisterUnitEvent(event, "pet")
	end
	self.events = events
	lastHappiness = ns.Readable((C_PetInfo.GetPetHappiness()))
	self:ApplyLayout()
	self:ScanFood()
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
	self:ScanFood() -- a different pet may eat different food
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

-- The fight is over: make the feed button if a reload mid-fight held it back,
-- then catch up on the food and place it waited with.
function Pet:PLAYER_REGEN_ENABLED()
	self:BuildFeedButton()
	self:ScanFood()
end

Pet.PLAYER_ENTERING_WORLD = Pet.UNIT_PET
Pet.PET_UI_UPDATE = Pet.ScanFood
Pet.BAG_UPDATE_DELAYED = Pet.ScanFood
Pet.UNIT_LEVEL = Pet.ScanFood -- food tiers follow the pet's level
Pet.UNIT_HEALTH = Pet.Refresh
Pet.UNIT_MAXHEALTH = Pet.Refresh
Pet.UNIT_NAME_UPDATE = Pet.Refresh
