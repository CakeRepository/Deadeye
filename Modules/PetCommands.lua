-- Pet commands: the pet panel doubles as a remote for the calls a hunter makes
-- in a hurry, and the same calls get key bindings and macros for your bars.
--   Click the panel: your pet goes in, opening with its gap closer (Charge for
--   a boar, Dash, Dive). Click again: it comes back on passive, so it stays
--   out. Sent in again, it gets back the stance it had.
--   Right-click: park it where it stands. Shift-right-click: the game's Move To
--   (a targeting circle: click the ground where it should wait).
--   Shift-click: its next stance, shown at the panel's top right.
-- The panel lights up while the opener would land. A duel request, yours or
-- theirs, brings up a button above the panel that holds your pet back, so it
-- doesn't run in when the duel starts.
--
-- Pet commands are protected: an addon can't give them, only a click or key
-- press of yours can, through Blizzard's secure buttons. Which command a press
-- gives is picked by a secure snippet (restricted code, which runs in combat
-- too) from what a secure header keeps: whether the next press sends your pet
-- in or calls it back, the stance to give back, and the commands for the pet
-- you have. A state driver on [@pettarget,exists] keeps the first honest: a
-- pet that's fighting gets called back. Addon code only changes the header out
-- of combat, so a new pet's opener waits for the fight to end.
local _, ns = ...
local L = ns.L

local PetCommands = ns:NewModule("PetCommands", {
	enabled = true, -- the pet panel as a remote, with the stance at its top right
	glow = true, -- the panel lights up while the opener would land
	duelPrep = true, -- a button to hold your pet back when a duel is asked for
})
PetCommands.title = L["Pet commands"]
PetCommands.slashPrefix = "commands"

-- Openers: pet abilities that close the distance, found by name on the pet bar
-- so any rank counts. Charge needs some room (8 yards in Classic): park your
-- boar away from the fight first.
local OPENERS = {
	7371, -- Charge (boar)
	23099, -- Dash (cat, wolf, raptor, hyena)
	23145, -- Dive (bat, owl, carrion bird, wind serpent)
}
-- In the order shift-click goes through them. Only the ones on the pet bar count.
local STANCES = {
	{ token = "PET_MODE_PASSIVE", command = "/petpassive", text = L["Passive"], icon = "Interface\\Icons\\Ability_Seal" },
	{ token = "PET_MODE_DEFENSIVE", command = "/petdefensive", text = L["Defensive"], icon = "Interface\\Icons\\Ability_Defend" },
	{ token = "PET_MODE_DEFENSIVEASSIST", command = "/petdefensiveassist", text = L["Defensive"], icon = "Interface\\Icons\\Ability_Defend" },
	{ token = "PET_MODE_ASSIST", command = "/petassist", text = L["Assist"], icon = "Interface\\Icons\\Ability_Hunter_Pet_Assist" },
	{ token = "PET_MODE_AGGRESSIVE", command = "/petaggressive", text = L["Aggressive"], icon = "Interface\\Icons\\Ability_Racial_BloodRage" },
}
local STANCE_BY_TOKEN = {}
for _, stance in ipairs(STANCES) do
	STANCE_BY_TOKEN[stance.token] = stance
end
-- Back on passive, so a pet on defensive or aggressive doesn't run straight
-- back in. /petmoveto brings up the game's targeting circle.
local COMMANDS = {
	back = "/petpassive\n/petfollow",
	hold = "/petpassive\n/petfollow",
	park = "/petpassive\n/petstay",
	spot = "/petpassive\n/petmoveto",
}
local ATTACK = "/petattack"
-- The pet bar's own icons (PetActionBar.lua).
local ICONS = {
	toggle = "Interface\\Icons\\Ability_GhoulFrenzy",
	hold = "Interface\\Icons\\Ability_Tracking",
	park = "Interface\\Icons\\Spell_Nature_TimeStop",
	spot = "Interface\\Icons\\Ability_Hunter_Pet_Goto",
	stance = "Interface\\Icons\\Ability_Defend",
}
local QUESTION_MARK_ICON = 134400
-- What key bindings (Bindings.xml) and macros click: the keys button, one
-- mouse button per command.
local KEYS = {
	{ button = "LeftButton", action = "toggle", binding = L["Pet: send in or call back"], macro = L["Pet in/out"] },
	{ button = "Button5", action = "hold", binding = L["Pet: hold back"], macro = L["Pet hold"] },
	{ button = "RightButton", action = "park", binding = L["Pet: park"], macro = L["Pet park"] },
	{ button = "Button4", action = "spot", binding = L["Pet: move to where you click"], macro = L["Pet move"] },
	{ button = "MiddleButton", action = "stance", binding = L["Pet: next stance"], macro = L["Pet stance"] },
}
-- Your own macros hold the commands themselves: the game doesn't run what an
-- addon button gives when a macro's /click presses it (seen in game).
local OLD_MACRO_BODY = "/click DeadeyePetKeys %s 1" -- 0.5.1 test builds' macros, brought up to date
local TOGGLE_CHECK = "/stopmacro [@pettarget,exists]"
local STANCE_MACRO = "/petpassive [nomod]\n/petdefensive [mod:shift]\n/petaggressive [mod:ctrl]"
local PET_SLOTS = 10
-- No pet out, or a dead one: a press calls it or revives it. A pet with a
-- target is fighting: a press calls it back. Otherwise a press sends it in.
local FIGHTING = "[nopet][@pet,dead] none; [@pettarget,exists] fight; calm"
local CALL_PET_SPELL_ID, REVIVE_PET_SPELL_ID = 883, 982
-- Whether your target is an enemy, which a press that sends your pet in needs
-- to count. A state driver works it out, so the snippet only reads it.
local ENEMY_TARGET = "[@target,harm,nodead] yes; no"
local UPDATE_SECONDS = 0.2
local SETTLE_SECONDS = 1 -- the game's word on a stance, after one of these commands
local PREP_HEIGHT, PREP_GAP = 24, 4
local PREP_SECONDS = 120 -- a duel asked for and never started
local BADGE_SIZE = 16
local GLOW_COLOR = { 0.35, 0.9, 0.35, 0.9 }

BINDING_HEADER_DEADEYE = ns.title
for _, key in ipairs(KEYS) do
	_G["BINDING_NAME_CLICK DeadeyePetKeys:" .. key.button] = key.binding
end

-- Picks the command for each press. A press is a down and an up click and only
-- one of them acts, so an up after a down is dropped. Restricted code can't
-- define new functions: the keyword may not appear in it, not even in a comment.
--   self: the button pressed; control: the header; button: the mouse button.
local PRE_CLICK = [[
	if not down and self:GetAttribute("deadeye-down") then
		self:SetAttribute("deadeye-down", false)
		return false
	end
	self:SetAttribute("deadeye-down", down)
	local action = self:GetAttribute("deadeye-" .. button)
	if IsShiftKeyDown() then
		action = self:GetAttribute("deadeye-shift-" .. button) or action
	end
	if action == "toggle" then
		if control:GetAttribute("state-fight") == "none" then
			action = "summon"
		else
			action = control:GetAttribute("deadeye-next") == "back" and "back" or "attack"
		end
	end
	local text
	if action == "attack" then
		local home = control:GetAttribute("deadeye-home") or 0
		text = (control:GetAttribute("deadeye-stance" .. home) or "") .. "\n" .. control:GetAttribute("deadeye-attack")
		control:SetAttribute("deadeye-stance", home)
		if control:GetAttribute("state-enemy") == "yes" then
			control:SetAttribute("deadeye-next", "back")
		end
	elseif action == "summon" then
		text = control:GetAttribute("deadeye-summon")
	elseif action == "stance" then
		local count = control:GetAttribute("deadeye-stances") or 0
		if count == 0 then
			return false
		end
		local index = (control:GetAttribute("deadeye-stance") or 0) % count + 1
		control:SetAttribute("deadeye-stance", index)
		control:SetAttribute("deadeye-home", index)
		text = control:GetAttribute("deadeye-stance" .. index)
	elseif action then
		text = control:GetAttribute("deadeye-" .. action)
		control:SetAttribute("deadeye-next", "in")
		control:SetAttribute("deadeye-stance", control:GetAttribute("deadeye-passive") or 0)
	end
	if not text then
		return false
	end
	self:SetAttribute("macrotext", text)
	if self:GetAttribute("deadeye-hide") then
		return button, "hide"
	end
]]
local POST_CLICK = [[
	if message == "hide" then
		self:Hide()
	end
]]
-- The state driver's word: a pet with a target is fighting, so the next press
-- calls it back. Without one, the next press sends it in.
local ON_FIGHT_STATE = [[
	self:SetAttribute("deadeye-next", newstate == "fight" and "back" or "in")
]]

local opener -- { name =, slot =, icon = } of the pet's opener, or nil
local stance -- the pet's stance token (PET_MODE_*), or nil

local function PetName()
	return ns.Readable(UnitName("pet"), L["your pet"])
end

local function SpellName(spellID, fallback)
	local name = ns.Readable(C_Spell.GetSpellName(spellID))
	return name ~= nil and name ~= "" and name or fallback
end

-- Revive Pet for a dead pet, Call Pet when there's none, by the game's names.
local function SummonCommand()
	return "/cast [@pet,dead] " .. SpellName(REVIVE_PET_SPELL_ID, "Revive Pet") .. "; " .. SpellName(CALL_PET_SPELL_ID, "Call Pet")
end

local function FileID(path)
	return GetFileIDFromPath and ns.Readable(GetFileIDFromPath(path)) or QUESTION_MARK_ICON
end

-- The pet bar: its opener, its stance, and the stances on it. Out of combat or
-- in, what it says is only read, never compared while secret. The opener is
-- found by name, so any rank counts, or by its icon in a language whose game
-- data has no name for it; /cast takes the name the pet bar shows.
local function ReadPetBar()
	local wanted = {} -- [opener name, or its icon where there's no name] = spell ID
	for _, spellID in ipairs(OPENERS) do
		local name = ns.Readable(C_Spell.GetSpellName(spellID))
		if name and name ~= "" then
			wanted[name] = spellID
		else
			local icon = ns.Readable((C_Spell.GetSpellTexture(spellID)))
			if icon then
				wanted[icon] = spellID
			end
		end
	end
	local stances = {}
	stance, opener = nil, nil
	for slot = 1, PET_SLOTS do
		local name, icon, isToken, isActive = GetPetActionInfo(slot)
		name, icon, isToken, isActive = ns.Readable(name), ns.Readable(icon), ns.Readable(isToken), ns.Readable(isActive)
		if isToken and STANCE_BY_TOKEN[name] then
			stances[name] = true
			if isActive then
				stance = name
			end
		elseif name and not isToken and not opener and (wanted[name] or (icon and wanted[icon])) then
			opener = {
				name = name ~= "" and name or nil, -- nil: nothing to /cast it by
				slot = slot,
				icon = C_Spell.GetSpellTexture(wanted[name] or wanted[icon]),
			}
		end
	end
	return stances
end

-- Whether the opener is ready: its cooldown, not counting the pet's global one.
local function OpenerReady()
	local start, duration = GetPetActionCooldown(opener.slot)
	start, duration = ns.Readable(start), ns.Readable(duration)
	if not (start and duration) then
		return true -- the game won't say: the range is the better hint
	end
	return duration <= 1.5 or start + duration <= GetTime()
end

---------------------------------------------------------------------------
-- The header and its buttons
---------------------------------------------------------------------------

-- The commands and stances for the pet you have, and the stance to give back.
-- Out of combat only: a fight leaves the header as it was until it ends.
function PetCommands:UpdateHeader()
	local available = ReadPetBar()
	local header = self.header
	if not header then
		return
	end
	if InCombatLockdown() then
		self.pending = true
		return
	end
	self.pending = nil
	local count, current, passive = 0, 0, 0
	for _, entry in ipairs(STANCES) do
		if available[entry.token] then
			count = count + 1
			header:SetAttribute("deadeye-stance" .. count, entry.command)
			if entry.token == stance then
				current = count
			end
			if entry.token == "PET_MODE_PASSIVE" then
				passive = count
			end
		end
	end
	header:SetAttribute("deadeye-stances", count)
	header:SetAttribute("deadeye-passive", passive)
	-- A stance these commands didn't give came from somewhere else (the pet
	-- bar, another pet): it's the one to give back. Right after a command the
	-- game may not have caught up yet, so that waits a moment.
	if current ~= 0 and current ~= header:GetAttribute("deadeye-stance")
		and GetTime() - (self.commandAt or -SETTLE_SECONDS) >= SETTLE_SECONDS then
		header:SetAttribute("deadeye-stance", current)
		header:SetAttribute("deadeye-home", current)
	end
	header:SetAttribute("deadeye-attack", opener and opener.name and (ATTACK .. "\n/cast " .. opener.name) or ATTACK)
	header:SetAttribute("deadeye-summon", SummonCommand())
	self:UpdateMacros()
end

-- A press of one of the buttons: the display follows at once, and the stance
-- it gave is checked against the game's once that has caught up.
function PetCommands:AfterCommand()
	self.commandAt = GetTime()
	self:UpdateDisplay()
	C_Timer.After(SETTLE_SECONDS + 0.1, function()
		self:UpdateHeader()
		self:UpdateDisplay()
	end)
end

-- An addon's secure button acts on the press or the release of a click, key or
-- macro's /click as "cast on key down" says (SecureActionButton_OnClick), so it
-- listens to both and is told to act on the press. The snippet drops the release.
local function SecureButton(self, name)
	local button = CreateFrame("Button", name, UIParent, "SecureActionButtonTemplate")
	button:SetFrameStrata("MEDIUM")
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetAttribute("useOnKeyDown", true)
	button:SetAttribute("type", "macro")
	SecureHandlerWrapScript(button, "OnClick", self.header, PRE_CLICK, POST_CLICK)
	button:SetScript("PostClick", function()
		self:AfterCommand()
	end)
	return button
end

-- Secure frames are made out of combat: after a reload mid-fight this waits for
-- PLAYER_REGEN_ENABLED.
function PetCommands:Build()
	if self.header or InCombatLockdown() then
		return
	end
	local header = CreateFrame("Frame", "DeadeyePetCommands", UIParent, "SecureHandlerStateTemplate")
	header:SetAttribute("deadeye-next", "in")
	header:SetAttribute("deadeye-attack", ATTACK)
	header:SetAttribute("deadeye-summon", SummonCommand())
	for action, text in pairs(COMMANDS) do
		header:SetAttribute("deadeye-" .. action, text)
	end
	header:SetAttribute("_onstate-fight", ON_FIGHT_STATE)
	RegisterStateDriver(header, "fight", FIGHTING)
	RegisterStateDriver(header, "enemy", ENEMY_TARGET) -- read as state-enemy by the snippet
	self.header = header

	-- Key bindings and macros click this one. Never seen: it's shown, so nothing
	-- keeps a key press from it, but see-through and deaf to the mouse.
	local keys = SecureButton(self, "DeadeyePetKeys")
	for _, key in ipairs(KEYS) do
		keys:SetAttribute("deadeye-" .. key.button, key.action)
	end
	keys:SetSize(1, 1)
	keys:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
	keys:SetAlpha(0)
	keys:EnableMouse(false)
	self.keys = keys

	-- Over the pet panel, anchored to the screen like the feed button, so the
	-- panel itself stays free to change in combat.
	local remote = SecureButton(self, "DeadeyePetRemote")
	remote:SetAttribute("deadeye-LeftButton", "toggle")
	remote:SetAttribute("deadeye-shift-LeftButton", "stance")
	remote:SetAttribute("deadeye-MiddleButton", "stance")
	remote:SetAttribute("deadeye-RightButton", "park")
	remote:SetAttribute("deadeye-shift-RightButton", "spot")
	local highlight = remote:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetColorTexture(1, 1, 1, 0.08)
	remote:SetScript("OnEnter", function(owner)
		self:ShowRemoteTooltip(owner)
	end)
	remote:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	remote:Hide()
	self.remote = remote

	-- Above the panel while a duel is asked for. A click hides it, in combat too.
	local prep = SecureButton(self, "DeadeyeDuelPrep")
	prep:SetAttribute("deadeye-LeftButton", "hold")
	prep:SetAttribute("deadeye-RightButton", "park")
	prep:SetAttribute("deadeye-hide", true)
	prep.background = prep:CreateTexture(nil, "BACKGROUND")
	prep.background:SetAllPoints()
	prep.background:SetColorTexture(0.1, 0.1, 0.1, 0.85)
	prep.icon = prep:CreateTexture(nil, "ARTWORK")
	prep.icon:SetSize(PREP_HEIGHT - 4, PREP_HEIGHT - 4)
	prep.icon:SetPoint("LEFT", 2, 0)
	prep.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	prep.icon:SetTexture(ICONS.hold)
	prep.text = prep:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	prep.text:SetPoint("LEFT", PREP_HEIGHT + 2, 0)
	prep.text:SetPoint("RIGHT", -4, 0)
	prep.text:SetJustifyH("LEFT")
	local prepHighlight = prep:CreateTexture(nil, "HIGHLIGHT")
	prepHighlight:SetAllPoints()
	prepHighlight:SetColorTexture(1, 1, 1, 0.12)
	prep:SetScript("OnEnter", function(owner)
		self:ShowPrepTooltip(owner)
	end)
	prep:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	prep:Hide()
	self.prep = prep

	self:UpdateHeader()
	self:ApplyLayout()
end

---------------------------------------------------------------------------
-- On the pet panel: the stance, the glow and the remote's place
---------------------------------------------------------------------------

-- The stance at the panel's top right, and a border that lights up. Both are
-- plain textures on the panel, so they change in combat too.
function PetCommands:AttachDisplay()
	local pet = ns.modules.Pet
	local frame = pet.frame
	if self.display or not frame then
		return
	end
	local display = CreateFrame("Frame", nil, frame)
	display:SetAllPoints()
	local badge = display:CreateTexture(nil, "OVERLAY")
	badge:SetSize(BADGE_SIZE, BADGE_SIZE)
	badge:SetPoint("TOPRIGHT", -4, -4)
	badge:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	display.badge = badge
	local glow = CreateFrame("Frame", nil, frame)
	glow:SetPoint("TOPLEFT", -2, 2)
	glow:SetPoint("BOTTOMRIGHT", 2, -2)
	local edges = {
		{ "TOPLEFT", "TOPRIGHT", nil, 2 },
		{ "BOTTOMLEFT", "BOTTOMRIGHT", nil, 2 },
		{ "TOPLEFT", "BOTTOMLEFT", 2, nil },
		{ "TOPRIGHT", "BOTTOMRIGHT", 2, nil },
	}
	for _, edge in ipairs(edges) do
		local texture = glow:CreateTexture(nil, "OVERLAY")
		texture:SetPoint(edge[1])
		texture:SetPoint(edge[2])
		if edge[3] then
			texture:SetWidth(edge[3])
		else
			texture:SetHeight(edge[4])
		end
		texture:SetColorTexture(GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], GLOW_COLOR[4])
	end
	glow:Hide()
	display.glow = glow
	-- The range check, a few times a second while the panel shows.
	local elapsedSum = 0
	display:SetScript("OnUpdate", function(_, elapsed)
		elapsedSum = elapsedSum + elapsed
		if elapsedSum >= UPDATE_SECONDS then
			elapsedSum = 0
			self:UpdateDisplay()
		end
	end)
	self.display = display
end

function PetCommands:NextIsBack()
	return self.header ~= nil and self.header:GetAttribute("deadeye-next") == "back"
end

function PetCommands:UpdateDisplay()
	local display = self.display
	if not display then
		return
	end
	local entry = stance and STANCE_BY_TOKEN[stance]
	display.badge:SetTexture(entry and entry.icon or STANCES[1].icon)
	display.badge:SetDesaturated(entry == nil)
	display.badge:SetShown(self.db.enabled)
	local lit = false
	if self.db.glow and opener and UnitExists("pet") and not self:NextIsBack() then
		local _, _, _, _, _, _, _, checksRange, inRange = GetPetActionInfo(opener.slot)
		lit = ns.Readable(checksRange) == true and ns.Readable(inRange) == true and OpenerReady()
	end
	display.glow:SetShown(lit)
end

-- The panel's mood text makes room for the stance.
function PetCommands:PlaceMood()
	local frame = ns.modules.Pet.frame
	frame.mood:ClearAllPoints()
	frame.mood:SetPoint("TOPRIGHT", self.db.enabled and -(BADGE_SIZE + 8) or -5, -6)
end

-- The remote over the panel, and the duel button above it. Out of combat only;
-- a fight's changes wait for PLAYER_REGEN_ENABLED.
function PetCommands:ApplyLayout()
	local pet = ns.modules.Pet
	local frame = pet.frame
	if not frame then
		return
	end
	self:AttachDisplay()
	self:PlaceMood()
	self:UpdateDisplay()
	local remote, prep = self.remote, self.prep
	if not remote then
		return
	end
	if InCombatLockdown() then
		self.layoutPending = true
		return
	end
	self.layoutPending = nil
	local petDB = pet.db
	local scale = petDB.scale
	local x, y = petDB.position.x / scale, petDB.position.y / scale
	remote:SetScale(scale)
	remote:SetSize(frame:GetWidth(), frame:GetHeight())
	remote:ClearAllPoints()
	remote:SetPoint("CENTER", UIParent, "CENTER", x, y)
	remote:SetFrameLevel(frame:GetFrameLevel() + 20) -- above the panel and its drag overlay
	prep:SetScale(scale)
	prep:SetSize(petDB.width, PREP_HEIGHT)
	prep:ClearAllPoints()
	prep:SetPoint("CENTER", UIParent, "CENTER", x, y + frame:GetHeight() / 2 + PREP_GAP + PREP_HEIGHT / 2)
	-- Only while the panel is always there to click (your pet alive, dead or
	-- away): not when it shows only to ask for attention, before your first pet,
	-- nor while it's unlocked for dragging.
	remote:SetShown(self.db.enabled and petDB.enabled and petDB.show == "always" and petDB.hadPet
		and not ns:IsUnlocked())
end

function PetCommands:ShowRemoteTooltip(owner)
	local pet = ns.modules.Pet
	if not pet.status then
		return
	end
	pet:ShowTooltip(owner)
	local name, muted = PetName(), 0.7
	GameTooltip:AddLine(" ")
	if pet.status.kind ~= "alive" then
		local spell = pet.status.kind == "dead" and SpellName(REVIVE_PET_SPELL_ID, "Revive Pet") or SpellName(CALL_PET_SPELL_ID, "Call Pet")
		GameTooltip:AddLine(L["Click: %s"]:format(spell), 1, 1, 1)
		GameTooltip:Show()
		return
	elseif self:NextIsBack() then
		GameTooltip:AddLine(L["Click: call %s back"]:format(name), 1, 1, 1)
	elseif opener and opener.name then
		GameTooltip:AddLine(L["Click: send %s in with %s"]:format(name, opener.name), 1, 1, 1)
	else
		GameTooltip:AddLine(L["Click: send %s in"]:format(name), 1, 1, 1)
	end
	local entry = stance and STANCE_BY_TOKEN[stance]
	GameTooltip:AddLine(L["Shift-click: next stance (now %s)"]:format(entry and entry.text or L["Unknown"]), muted, muted, muted)
	GameTooltip:AddLine(L["Right-click: park it. Shift-right-click: move it to a spot you click."], muted, muted, muted, true)
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Duels
---------------------------------------------------------------------------

-- A duel was asked for, by you or of you. A pet that isn't on passive would
-- run in as soon as the duel starts: offer to hold it back.
function PetCommands:OfferDuelPrep()
	local prep = self.prep
	if not (self.db.duelPrep and prep) or InCombatLockdown() then
		return
	end
	if not UnitExists("pet") or ns.Readable(UnitIsDead("pet")) then
		return
	end
	ReadPetBar()
	if stance == "PET_MODE_PASSIVE" then
		return -- it stays out by itself
	end
	prep.text:SetText(L["Duel: hold %s back"]:format(PetName()))
	self:ApplyLayout()
	prep:Show()
	self.prepToken = (self.prepToken or 0) + 1
	local token = self.prepToken
	C_Timer.After(PREP_SECONDS, function()
		if self.prepToken == token then
			self:HideDuelPrep()
		end
	end)
end

function PetCommands:HideDuelPrep()
	if not (self.prep and self.prep:IsShown()) then
		return
	end
	if InCombatLockdown() then
		self.prepPending = true
		return
	end
	self.prepPending = nil
	self.prep:Hide()
end

function PetCommands:ShowPrepTooltip(owner)
	local muted = 0.7
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(L["Duel: hold %s back"]:format(PetName()))
	GameTooltip:AddLine(L["Passive and by your side, so it doesn't run in when the duel starts. Right-click: park it where it stands instead."], 1, 1, 1, true)
	local key = GetBindingKey("CLICK DeadeyePetKeys:LeftButton")
	if key then
		GameTooltip:AddLine(L["Then press %s to send it in."]:format(key), muted, muted, muted, true)
	elseif self.db.enabled then
		GameTooltip:AddLine(L["Then click the pet panel to send it in."], muted, muted, muted, true)
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Macros for your own bars
---------------------------------------------------------------------------

local function MacroLimits()
	local consts = Constants and Constants.MacroConsts
	return consts and consts.MAX_ACCOUNT_MACROS or 120, consts and consts.MAX_CHARACTER_MACROS or 18
end

-- What a macro holds. The in/out one asks the game whether the pet has a target
-- (it's fighting: back on passive), and otherwise sends it in on the stance it
-- had with its opener, as known out of combat.
function PetCommands:MacroBody(key)
	if key.action == "toggle" then
		local lines = {
			SummonCommand(), "/stopmacro [@pet,dead][nopet]",
			"/petfollow [@pettarget,exists]", "/petpassive [@pettarget,exists]", TOGGLE_CHECK,
		}
		local header = self.header
		local home = header and header:GetAttribute("deadeye-stance" .. (header:GetAttribute("deadeye-home") or 0))
		if home then
			lines[#lines + 1] = home
		end
		lines[#lines + 1] = ATTACK
		if opener and opener.name then
			lines[#lines + 1] = "/cast " .. opener.name
		end
		return table.concat(lines, "\n")
	elseif key.action == "stance" then
		return STANCE_MACRO
	end
	return COMMANDS[key.action]
end

function PetCommands:MacroIcon(key)
	if key.action == "toggle" and opener and ns.Readable(opener.icon) then
		return opener.icon
	end
	return FileID(ICONS[key.action])
end

-- The index, name, icon and body of the macro of yours that holds this command:
-- one a 0.5.1 test build made (a /click of the keys button), or one with the
-- command's name holding what Deadeye puts there (the in/out one changes with
-- the pet, so its /stopmacro line is enough). A macro of yours that only shares
-- the name is left alone. Nil when there's none.
function PetCommands:FindMacro(key)
	local maxAccount = MacroLimits()
	local numAccount, numCharacter = GetNumMacros()
	local old, wanted = OLD_MACRO_BODY:format(key.button), self:MacroBody(key)
	for index = 1, maxAccount + numCharacter do
		if index <= numAccount or index > maxAccount then
			local name, icon, body = GetMacroInfo(index)
			if body and (body:find(old, 1, true) or (name == key.macro
				and (body == wanted or (key.action == "toggle" and body:find(TOGGLE_CHECK, 1, true))))) then
				return index, name, icon, body
			end
		end
	end
end

-- Puts the commands in your macros (for this character, or the shared ones
-- when those are full), or brings the ones already there up to date.
function PetCommands:MakeMacros()
	if InCombatLockdown() then
		ns.Print(L["Macros can't be made during a fight. Try again after it."])
		return
	end
	ReadPetBar()
	local maxAccount, maxCharacter = MacroLimits()
	for _, key in ipairs(KEYS) do
		local index, name = self:FindMacro(key)
		if index then
			EditMacro(index, name, self:MacroIcon(key), self:MacroBody(key))
		else
			local numAccount, numCharacter = GetNumMacros()
			if numCharacter < maxCharacter then
				CreateMacro(key.macro, self:MacroIcon(key), self:MacroBody(key), true)
			elseif numAccount < maxAccount then
				CreateMacro(key.macro, self:MacroIcon(key), self:MacroBody(key), false)
			else
				ns.Print(L["Your macros are full. Delete one and try again."])
				return
			end
		end
	end
	ns.Print(L["Pet macros ready. Type /macro and drag them onto your bars."])
	ns.Print(L["Pet stance macro: %s. With shift: %s. With ctrl: %s."]:format(L["Passive"], L["Defensive"], L["Aggressive"]))
end

-- Your pet macros follow the pet: its opener, and the stance the in/out one
-- gives back. Out of combat: UpdateHeader calls this after its own check.
function PetCommands:UpdateMacros()
	for _, key in ipairs(KEYS) do
		local index, name, icon, body = self:FindMacro(key)
		if index then
			local wantedIcon, wantedBody = self:MacroIcon(key), self:MacroBody(key)
			if ns.Readable(icon) ~= wantedIcon or body ~= wantedBody then
				EditMacro(index, name, wantedIcon, wantedBody)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Options and events
---------------------------------------------------------------------------

function PetCommands:OnOptionChanged()
	self:ApplyLayout()
	self:UpdateDisplay()
end

PetCommands.OnSettingsReset = PetCommands.OnOptionChanged

function PetCommands:GetOptionSections()
	return {
		{
			name = L["Pet: commands"],
			keys = { "enabled", "glow", "duelPrep" },
			controls = {
				{ type = "toggle", label = L["Pet commands on the pet panel"], key = "enabled", slash = "enabled" },
				{ type = "toggle", label = L["Light up the panel when Charge would land"], key = "glow", slash = "glow" },
				{ type = "toggle", label = L["Hold button when a duel is asked for"], key = "duelPrep", slash = "duel" },
				{ type = "button", label = L["Make pet macros"], slash = "macros", func = function()
					self:MakeMacros()
				end },
				{ type = "note", height = 150, text = L["Click the pet panel to send your pet in, opening with Charge (boar), Dash or Dive. Click again to call it back, on passive so it stays out. Sent in again, it gets its stance back. Right-click parks it, shift-right-click moves it to a spot you click, shift-click changes its stance.\n\nThe same commands are in Key Bindings, under AddOns > Deadeye. Make pet macros puts them in your macros too, to drag onto your bars."] },
			},
		},
	}
end

function PetCommands:ShouldEnable()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

function PetCommands:OnEnable()
	local events = ns.CreateEventFrame(self)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PET_BAR_UPDATE",
		"DUEL_REQUESTED", "DUEL_FINISHED" }) do
		events:RegisterEvent(event)
	end
	events:RegisterUnitEvent("UNIT_PET", "player")
	self.events = events
	-- Challenging someone yourself (/duel, or the player menu) has no event.
	hooksecurefunc("StartDuel", function()
		self:OfferDuelPrep()
	end)
	self:Build()
end

function PetCommands:Refresh()
	self:UpdateHeader()
	self:UpdateDisplay()
end

PetCommands.PLAYER_ENTERING_WORLD = PetCommands.Refresh
PetCommands.PET_BAR_UPDATE = PetCommands.Refresh
PetCommands.UNIT_PET = PetCommands.Refresh

-- A fight started: the duel button stays until the duel is over.
function PetCommands:PLAYER_REGEN_DISABLED()
	self.prepToken = (self.prepToken or 0) + 1
end

-- The fight is over: make the buttons if a reload mid-fight held them back, and
-- catch up on what it held up.
function PetCommands:PLAYER_REGEN_ENABLED()
	self:Build()
	if self.pending then
		self:UpdateHeader()
	end
	if self.layoutPending then
		self:ApplyLayout()
	end
	if self.prepPending then
		self:HideDuelPrep()
	end
	self:UpdateDisplay()
end

function PetCommands:DUEL_REQUESTED()
	self:OfferDuelPrep()
end

function PetCommands:DUEL_FINISHED()
	self:HideDuelPrep()
end
