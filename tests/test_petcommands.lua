-- The pet commands: the pet panel as a remote, key bindings, macros and the
-- duel button (Modules\PetCommands.lua).
local H, ROOT = ...

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

local CHARGE_ICON, DASH_ICON = 132337, 132242 -- the harness's spell textures
local SEND_IN = "/petdefensive\n/petattack\n/cast Charge"
local CALL_BACK = "/petpassive\n/petfollow"

local function Setup(options)
	local W = H.NewWorld(options)
	H.LoadAddon(W, ROOT)
	return W, W.ns.modules.PetCommands, W.ns.modules.Pet
end

-- A boar on this stance, with Charge on its bar.
local function Boar(W, stanceToken)
	W.pet = {
		name = "Boar", level = 20, health = 500, healthMax = 500, happiness = 3, damage = 125, loyaltyRate = 1,
		loyalty = "Loyalty Level 2", diet = { "Meat" },
	}
	W.petActions = {
		{ name = "PET_ACTION_ATTACK", token = true },
		{ name = "PET_ACTION_FOLLOW", token = true, active = true },
		{ name = "PET_ACTION_WAIT", token = true },
		{ name = "Bite", spellID = 17253 },
		{ name = "Charge", spellID = 7371 },
		{ name = "PET_MODE_AGGRESSIVE", token = true, active = stanceToken == "PET_MODE_AGGRESSIVE" },
		{ name = "PET_MODE_DEFENSIVE", token = true, active = stanceToken == "PET_MODE_DEFENSIVE" },
		{ name = "PET_MODE_PASSIVE", token = true, active = stanceToken == "PET_MODE_PASSIVE" },
	}
	W.Fire("UNIT_PET", "player")
end

-- The game reports the pet's stance changed.
local function SetStance(W, token)
	for _, action in ipairs(W.petActions) do
		if action.name:find("^PET_MODE_") then
			action.active = action.name == token
		end
	end
	W.Fire("PET_BAR_UPDATE")
end

local function Enemy(W)
	W.hasTarget, W.targetDead = true, false
	W.Fire("PLAYER_TARGET_CHANGED")
end

local function LastMacro(W)
	return W.macros[#W.macros]
end

local function TooltipHas(W, text)
	for _, line in ipairs(W.env.GameTooltip.lines) do
		if line == text then
			return true
		end
	end
	return false
end

test("pet commands: click the pet panel to send your pet in with Charge, again to call it back", function()
	local W, Commands, Pet = Setup()
	local remote = Commands.remote
	H.False(remote:IsShown(), "no pet, no remote")
	Boar(W, "PET_MODE_DEFENSIVE")
	H.True(remote:IsShown(), "over the panel while the pet lives")
	local _, relativeTo, _, x, y = remote:GetPoint(1)
	H.Equal(relativeTo, W.env.UIParent, "anchored to the screen, not to the panel")
	H.Equal(x, Pet.db.position.x, "on the panel")
	H.Equal(y, Pet.db.position.y, "on the panel")
	H.Equal(remote:GetWidth(), Pet.frame:GetWidth(), "as big as the panel")
	H.Equal(remote:GetHeight(), Pet.frame:GetHeight(), "as big as the panel")
	H.True(remote:GetFrameLevel() > Pet.frame:GetFrameLevel(), "on top of it")
	Enemy(W)
	W.Click(remote)
	H.Equal(LastMacro(W), SEND_IN, "in, opening with Charge, on its own stance")
	W.Click(remote)
	H.Equal(LastMacro(W), CALL_BACK, "a second click calls it back, on passive, even before it got there")
	W.Click(remote)
	H.Equal(LastMacro(W), SEND_IN, "in again, back on defensive")
	W.Click(remote, "RightButton")
	H.Equal(LastMacro(W), "/petpassive\n/petstay", "right-click parks it")
	W.shiftDown = true
	W.Click(remote, "RightButton")
	W.shiftDown = false
	H.Equal(LastMacro(W), "/petpassive\n/petmoveto", "shift-right-click: the game's Move To, which asks where")
	W.Click(remote)
	H.Equal(LastMacro(W), SEND_IN, "parked, a click sends it in")
	W.cvars.ActionButtonUseKeyDown = "0"
	W.Click(remote)
	H.Equal(LastMacro(W), CALL_BACK, "with 'cast on key down' off too")
	H.Equal(#W.macros, 7, "one command per click")
	H.Equal(#W.blocked, 0, "nothing blocked")
end)

test("pet commands: a pet that's fighting gets called back, and one done fighting gets sent in", function()
	local W, Commands = Setup()
	Boar(W, "PET_MODE_DEFENSIVE")
	Enemy(W)
	local remote = Commands.remote
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	-- On defensive it went in by itself: the click calls it back.
	W.petTarget = true
	W.UpdateDrivers()
	W.Click(remote)
	H.Equal(LastMacro(W), CALL_BACK, "called back")
	W.petTarget = false
	W.UpdateDrivers()
	W.Click(remote)
	H.Equal(LastMacro(W), SEND_IN, "sent back in")
	-- It made the kill: the next click sends it at the next enemy.
	W.petTarget = true
	W.UpdateDrivers()
	W.petTarget = false
	W.UpdateDrivers()
	W.Click(remote)
	H.Equal(LastMacro(W), SEND_IN, "in at the next one")
	-- With no enemy targeted, a click that sends it in doesn't count.
	W.Click(remote, "RightButton")
	W.hasTarget = false
	W.Fire("PLAYER_TARGET_CHANGED")
	W.Click(remote)
	H.Equal(LastMacro(W), SEND_IN, "sent in at nothing")
	W.Click(remote)
	H.Equal(LastMacro(W), SEND_IN, "so the next click sends it in, not back")
	H.Equal(#W.blocked, 0, "all in combat, nothing blocked")
end)

test("pet commands: key bindings and macros give one command per press", function()
	local W = Setup()
	Boar(W, "PET_MODE_PASSIVE")
	Enemy(W)
	local keys = W.env.DeadeyePetKeys
	H.Equal(keys:GetAlpha(), 0, "the keys button is never seen")
	H.False(keys.mouseEnabled, "nor clicked by the mouse")
	W.Key(keys, "LeftButton")
	H.Equal(#W.macros, 1, "one command per key press")
	H.Equal(LastMacro(W), "/petpassive\n/petattack\n/cast Charge", "in, on passive as it was")
	W.cvars.ActionButtonUseKeyDown = "0"
	W.Key(keys, "LeftButton")
	H.Equal(#W.macros, 2, "with 'cast on key down' off too")
	H.Equal(LastMacro(W), CALL_BACK, "and back")
	W.Key(keys, "Button5")
	H.Equal(LastMacro(W), CALL_BACK, "hold back, whatever it was doing")
	W.Key(keys, "RightButton")
	H.Equal(LastMacro(W), "/petpassive\n/petstay", "park")
	W.Key(keys, "Button4")
	H.Equal(LastMacro(W), "/petpassive\n/petmoveto", "move to")
	W.shiftDown = true
	W.Key(keys, "LeftButton")
	W.shiftDown = false
	H.Equal(LastMacro(W), "/petpassive\n/petattack\n/cast Charge", "a key with shift in it still sends it in")
	W.Key(keys, "MiddleButton")
	H.Equal(LastMacro(W), "/petdefensive", "next stance")
	H.Equal(W.env["BINDING_NAME_CLICK DeadeyePetKeys:LeftButton"], "Pet: send in or call back", "named in Key Bindings")
	H.Equal(W.env["BINDING_NAME_CLICK DeadeyePetKeys:Button4"], "Pet: move to where you click", "named in Key Bindings")
	H.Equal(W.env.BINDING_HEADER_DEADEYE, W.ns.title, "under Deadeye")
	-- A macro's /click works like the key, whichever way the setting is.
	W.RunMacroText("/click DeadeyePetKeys LeftButton 1")
	H.Equal(LastMacro(W), CALL_BACK, "a macro clicks it like a key")
	W.cvars.ActionButtonUseKeyDown = "1"
	W.RunMacroText("/click DeadeyePetKeys LeftButton 1")
	H.Equal(LastMacro(W), "/petdefensive\n/petattack\n/cast Charge", "in again, on the stance it was given")
	H.Equal(#W.blocked, 0, "nothing blocked")
end)

test("pet commands: shift-click picks the stance, shown on the panel, and the one it gets back", function()
	local W, Commands, Pet = Setup()
	Boar(W, "PET_MODE_DEFENSIVE")
	Enemy(W)
	local remote, badge = Commands.remote, Commands.display.badge
	H.True(badge:IsShown(), "the stance is on the panel")
	H.Equal(badge.texture, "Interface\\Icons\\Ability_Defend", "defensive")
	local _, _, _, moodX = Pet.frame.mood:GetPoint(1)
	H.True(moodX <= -20, "the mood text makes room for it")
	W.shiftDown = true
	W.Click(remote)
	W.shiftDown = false
	H.Equal(LastMacro(W), "/petaggressive", "shift-click: the next stance")
	SetStance(W, "PET_MODE_AGGRESSIVE")
	H.Equal(badge.texture, "Interface\\Icons\\Ability_Racial_BloodRage", "shown as the game confirms it")
	W.Click(remote, "MiddleButton")
	H.Equal(LastMacro(W), "/petpassive", "middle-click too, round to passive")
	W.Click(remote, "MiddleButton")
	H.Equal(LastMacro(W), "/petdefensive", "and on")
	SetStance(W, "PET_MODE_DEFENSIVE")
	W.Advance(1.2)
	-- Called back to passive, it gets its stance back when it's sent in again.
	W.Click(remote)
	W.Click(remote)
	SetStance(W, "PET_MODE_PASSIVE")
	W.Advance(1.2)
	W.Click(remote)
	H.Equal(LastMacro(W), SEND_IN, "defensive again")
	-- The pet bar can update before the game has caught up with a command.
	SetStance(W, "PET_MODE_DEFENSIVE")
	W.Advance(1.2)
	W.Click(remote)
	W.Fire("PET_BAR_UPDATE") -- still defensive
	W.Advance(0.5)
	SetStance(W, "PET_MODE_PASSIVE")
	W.Advance(1.2)
	W.Click(remote)
	H.Equal(LastMacro(W), SEND_IN, "a pet bar that lagged behind doesn't lose its stance")
	-- A stance picked on Blizzard's pet bar is the one to give back from then on.
	W.Click(remote, "RightButton")
	W.Advance(1.2)
	SetStance(W, "PET_MODE_AGGRESSIVE")
	W.Click(remote)
	H.Equal(LastMacro(W), "/petaggressive\n/petattack\n/cast Charge", "the pet bar's pick")
	-- Turned off: no remote, no stance on the panel.
	W.Slash("commands enabled off")
	H.False(remote:IsShown(), "no remote")
	H.False(badge:IsShown(), "no stance shown")
	local _, _, _, moodBack = Pet.frame.mood:GetPoint(1)
	H.Equal(moodBack, -5, "the mood text back in its corner")
	W.Slash("commands enabled on")
	H.True(remote:IsShown(), "back")
	H.Equal(#W.blocked, 0, "nothing blocked")
end)

test("pet commands: the panel lights up while Charge would land", function()
	local W, Commands = Setup()
	Boar(W, "PET_MODE_PASSIVE")
	Enemy(W)
	local glow, charge = Commands.display.glow, W.petActions[5]
	W.Advance(0.3)
	H.False(glow:IsShown(), "dark out of range")
	charge.checksRange, charge.inRange = true, true
	W.Advance(0.3)
	H.True(glow:IsShown(), "lit in range")
	charge.cooldown = { W.now, 25 }
	W.Advance(0.3)
	H.False(glow:IsShown(), "dark while Charge cools down")
	charge.cooldown = { W.now, 1 }
	W.Advance(0.3)
	H.True(glow:IsShown(), "the pet's global cooldown doesn't count")
	W.Click(Commands.remote)
	W.Advance(0.3)
	H.False(glow:IsShown(), "dark once it's sent in: the next click calls it back")
	W.Click(Commands.remote)
	W.Advance(0.3)
	H.True(glow:IsShown(), "lit again once it's back")
	charge.inRange = false
	W.Advance(0.3)
	H.False(glow:IsShown(), "dark once out of range")
	charge.inRange = true
	W.Slash("commands glow off")
	W.Advance(0.3)
	H.False(glow:IsShown(), "turned off")
end)

test("pet commands: the opener follows the pet, and a new pet in a fight waits for it to end", function()
	local W, Commands = Setup()
	Boar(W, "PET_MODE_PASSIVE")
	Enemy(W)
	local remote = Commands.remote
	remote.scripts.OnEnter(remote)
	H.True(TooltipHas(W, "Click: send Boar in with Charge"), "the tooltip says what a click does")
	H.True(TooltipHas(W, "Shift-click: next stance (now Passive)"), "and the stance")
	H.True(TooltipHas(W, "Happy: doing 125% damage"), "under the panel's own tooltip")
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	W.petActions[5] = { name = "Dash", spellID = 23099 }
	W.Fire("PET_BAR_UPDATE")
	W.Click(remote)
	H.Equal(LastMacro(W), "/petpassive\n/petattack\n/cast Charge", "unchanged in combat")
	remote.scripts.OnEnter(remote)
	H.True(TooltipHas(W, "Click: call Boar back"), "the tooltip follows")
	H.Equal(#W.blocked, 0, "nothing blocked")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	W.Click(remote)
	W.Click(remote)
	H.Equal(LastMacro(W), "/petpassive\n/petattack\n/cast Dash", "Dash after the fight")
	W.petActions[5] = { name = "Bite", spellID = 17253 }
	W.Fire("PET_BAR_UPDATE")
	W.Click(remote)
	W.Click(remote)
	H.Equal(LastMacro(W), "/petpassive\n/petattack", "no opener: it just attacks")
	W.Click(remote, "RightButton")
	remote.scripts.OnEnter(remote)
	H.True(TooltipHas(W, "Click: send Boar in"), "the tooltip too")
end)

test("pet commands: in a language whose game data has no name for Charge, it's found by its icon", function()
	local W, Commands = Setup()
	W.spellNames[7371] = ""
	Boar(W, "PET_MODE_PASSIVE")
	W.petActions[5] = { name = "Carica", spellID = 7371, texture = CHARGE_ICON }
	W.Fire("PET_BAR_UPDATE")
	Enemy(W)
	local remote = Commands.remote
	W.Click(remote)
	H.Equal(LastMacro(W), "/petpassive\n/petattack\n/cast Carica", "cast by the name the pet bar shows")
	-- No name on the pet bar either: it just attacks, and the panel still lights up.
	W.Click(remote)
	W.petActions[5] = { name = "", spellID = 7371, texture = CHARGE_ICON, checksRange = true, inRange = true }
	W.Fire("PET_BAR_UPDATE")
	W.Click(remote)
	H.Equal(LastMacro(W), "/petpassive\n/petattack", "nothing to cast it by")
	W.Click(remote)
	W.Advance(0.3)
	H.True(Commands.display.glow:IsShown(), "lit while it would land")
	remote.scripts.OnEnter(remote)
	H.True(TooltipHas(W, "Click: send Boar in"), "the tooltip names no opener")
end)

test("pet commands: the remote stays off while the panel drags, comes and goes, or its pet is dead", function()
	local W, Commands, Pet = Setup()
	Boar(W, "PET_MODE_DEFENSIVE")
	local remote = Commands.remote
	W.Slash("move")
	H.False(remote:IsShown(), "unlocked: the panel drags instead")
	W.Slash("move")
	H.True(remote:IsShown(), "locked again")
	W.Slash("pet show attention")
	H.False(remote:IsShown(), "a panel that only shows for attention is no remote")
	W.Slash("pet show always")
	H.True(remote:IsShown(), "back")
	W.Slash("pet enabled off")
	H.False(remote:IsShown(), "no panel, no remote")
	W.Slash("pet enabled on")
	-- A dead pet: a click revives it. Gone: a click calls it.
	W.pet.dead = true
	W.Fire("UNIT_HEALTH", "pet")
	H.True(remote:IsShown(), "still over the panel")
	W.Click(remote)
	H.Equal(W.macros[#W.macros], "/cast [@pet,dead] Revive Pet; Call Pet", "Revive Pet, or Call Pet if it's gone")
	remote.scripts.OnEnter(remote)
	H.True(TooltipHas(W, "Click: Revive Pet"), "the tooltip says so")
	local keys = W.env.DeadeyePetKeys
	W.Key(keys, "LeftButton")
	H.Equal(W.macros[#W.macros], "/cast [@pet,dead] Revive Pet; Call Pet", "the key too")
	local pet = W.pet
	W.pet = nil
	W.Fire("UNIT_PET", "player")
	W.Click(remote)
	H.Equal(W.macros[#W.macros], "/cast [@pet,dead] Revive Pet; Call Pet", "dismissed: Call Pet")
	remote.scripts.OnEnter(remote)
	H.True(TooltipHas(W, "Click: Call Pet"), "the tooltip says so")
	W.pet = pet
	W.pet.dead = false
	W.Fire("UNIT_PET", "player")
	W.Click(remote)
	H.Equal(W.macros[#W.macros], "/petdefensive\n/petattack\n/cast Charge", "back: a click sends it in again")
	W.Click(remote, "RightButton")
	W.Slash("pet x -300")
	local _, _, _, x = remote:GetPoint(1)
	H.Equal(x, -300, "follows the panel")
	W.Slash("pet width 220")
	H.Equal(remote:GetWidth(), 220, "and its size")
	-- Moved in a fight: it catches up when the fight ends.
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	Pet.db.position.x = -350
	Commands:ApplyLayout()
	H.Equal(#W.blocked, 0, "nothing blocked")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	local _, _, _, later = remote:GetPoint(1)
	H.Equal(later, -350, "caught up")
end)

test("pet commands: a duel asked for brings up a button that holds your pet back", function()
	local W, Commands, Pet = Setup()
	Boar(W, "PET_MODE_DEFENSIVE")
	local prep = Commands.prep
	H.False(prep:IsShown(), "not before a duel")
	W.Fire("DUEL_REQUESTED", "Rival")
	H.True(prep:IsShown(), "a duel asked for")
	H.Equal(prep.text.text, "Duel: hold Boar back", "says what it does")
	local _, relativeTo, _, x, y = prep:GetPoint(1)
	H.Equal(relativeTo, W.env.UIParent, "anchored to the screen")
	H.Equal(x, Pet.db.position.x, "over the panel")
	H.True(y > Pet.db.position.y + Pet.frame:GetHeight() / 2, "above it")
	prep.scripts.OnEnter(prep)
	H.True(TooltipHas(W, "Then click the pet panel to send it in."), "the tooltip says what's next")
	W.bindings["CLICK DeadeyePetKeys:LeftButton"] = "F"
	prep.scripts.OnEnter(prep)
	H.True(TooltipHas(W, "Then press F to send it in."), "with your key, if you bound one")
	W.Click(prep)
	H.Equal(LastMacro(W), CALL_BACK, "held back: passive, by your side")
	H.False(prep:IsShown(), "gone once used")
	-- The duel starts: in with Charge, on its own stance.
	Enemy(W)
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Click(Commands.remote)
	H.Equal(LastMacro(W), SEND_IN, "in with Charge, back on defensive")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	W.Fire("DUEL_FINISHED")
	-- Your own challenge too; right-click parks it instead.
	W.env.StartDuel("target")
	H.True(prep:IsShown(), "you asked for a duel")
	W.Click(prep, "RightButton")
	H.Equal(LastMacro(W), "/petpassive\n/petstay", "parked")
	H.False(prep:IsShown(), "gone once used")
	-- Declined, or over before you used it.
	W.Fire("DUEL_REQUESTED", "Rival")
	W.Fire("DUEL_FINISHED")
	H.False(prep:IsShown(), "gone when the duel is off")
	-- A duel asked for and never started.
	W.Fire("DUEL_REQUESTED", "Rival")
	W.Advance(121, 1)
	H.False(prep:IsShown(), "gone after a while")
	-- Over in a fight: gone when the fight is.
	W.Fire("DUEL_REQUESTED", "Rival")
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Fire("DUEL_FINISHED")
	H.True(prep:IsShown(), "can't hide in a fight")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	H.False(prep:IsShown(), "gone after it")
	-- On passive it stays out anyway.
	SetStance(W, "PET_MODE_PASSIVE")
	W.Fire("DUEL_REQUESTED", "Rival")
	H.False(prep:IsShown(), "nothing to hold back on passive")
	SetStance(W, "PET_MODE_DEFENSIVE")
	W.Slash("commands duel off")
	W.Fire("DUEL_REQUESTED", "Rival")
	H.False(prep:IsShown(), "turned off")
	H.Equal(#W.blocked, 0, "nothing blocked")
end)

local SUMMON = "/cast [@pet,dead] Revive Pet; Call Pet"
local TOGGLE_MACRO = SUMMON .. "\n/stopmacro [@pet,dead][nopet]\n"
	.. "/petfollow [@pettarget,exists]\n/petpassive [@pettarget,exists]\n/stopmacro [@pettarget,exists]\n"

test("pet commands: make pet macros for your own bars, holding the commands themselves", function()
	local W = Setup()
	Boar(W, "PET_MODE_DEFENSIVE")
	W.Slash("commands macros")
	local list = W.macroList.character
	H.Equal(#list, 5, "five macros, for this character")
	local byName = {}
	for _, macro in ipairs(list) do
		byName[macro.name] = macro
		H.False(macro.body:find("/click", 1, true), macro.name .. ": no /click, which the game doesn't run")
	end
	local toggle = byName["Pet in/out"]
	H.Equal(toggle.body, TOGGLE_MACRO .. "/petdefensive\n/petattack\n/cast Charge",
		"in/out: back on passive if it's fighting, else in on its stance with Charge")
	H.Equal(toggle.icon, CHARGE_ICON, "with Charge's icon")
	H.Equal(byName["Pet hold"].body, CALL_BACK, "hold back")
	H.Equal(byName["Pet park"].body, "/petpassive\n/petstay", "park")
	H.Equal(byName["Pet park"].icon, W.iconIDs["Interface\\Icons\\Spell_Nature_TimeStop"], "with the pet bar's Stay icon")
	H.Equal(byName["Pet move"].body, "/petpassive\n/petmoveto", "move to")
	H.Equal(byName["Pet stance"].body, "/petpassive [nomod]\n/petdefensive [mod:shift]\n/petaggressive [mod:ctrl]", "stance by modifier")
	H.True(W.Printed("Pet macros ready. Type /macro and drag them onto your bars."), "says where they are")
	H.True(W.Printed("Pet stance macro: Passive. With shift: Defensive. With ctrl: Aggressive."), "and how the stance one works")
	-- Made again: brought up to date, not doubled.
	W.Slash("commands macros")
	H.Equal(#list, 5, "not doubled")
	-- They follow the pet: a cat's Dash, and the stance it gets back.
	W.petActions[5] = { name = "Dash", spellID = 23099 }
	SetStance(W, "PET_MODE_AGGRESSIVE")
	H.Equal(toggle.icon, DASH_ICON, "Dash's icon for a cat")
	H.Equal(toggle.body, TOGGLE_MACRO .. "/petaggressive\n/petattack\n/cast Dash", "and its stance and opener")
	-- Not in a fight.
	W.inCombat = true
	W.Slash("commands macros")
	H.True(W.Printed("Macros can't be made during a fight. Try again after it."), "after the fight")
	W.petActions[5] = { name = "Charge", spellID = 7371 }
	W.Fire("PET_BAR_UPDATE")
	H.Equal(toggle.icon, DASH_ICON, "no macro changes in combat either")
	H.Equal(#W.blocked, 0, "nothing tried")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	H.Equal(toggle.icon, CHARGE_ICON, "caught up after it")

	-- This character's macros are full: the shared ones.
	local W2 = Setup()
	Boar(W2, "PET_MODE_DEFENSIVE")
	for i = 1, 30 do
		W2.macroList.character[i] = { name = string.format("Mine %02d", i), icon = 1, body = "/dance" }
	end
	W2.Slash("commands macros")
	H.Equal(#W2.macroList.account, 5, "in the shared macros")
	-- Both full.
	local W3 = Setup()
	Boar(W3, "PET_MODE_DEFENSIVE")
	for i = 1, 120 do
		W3.macroList.account[i] = { name = string.format("Shared %03d", i), icon = 1, body = "/dance" }
	end
	for i = 1, 30 do
		W3.macroList.character[i] = { name = string.format("Mine %02d", i), icon = 1, body = "/dance" }
	end
	W3.Slash("commands macros")
	H.True(W3.Printed("Your macros are full. Delete one and try again."), "says so")
end)

test("pet commands: macros from a test build that clicked the keys button are brought up to date", function()
	local W = Setup()
	local inOut = { name = "Pet in/out", icon = 1, body = "/click DeadeyePetKeys LeftButton 1" }
	local renamed = { name = "My park", icon = 1, body = "/click DeadeyePetKeys RightButton 1" }
	local mine = { name = "Pet hold", icon = 1, body = "/say hold!" } -- the player's own, named like ours
	W.macroList.character = { inOut, mine, renamed }
	Boar(W, "PET_MODE_PASSIVE")
	H.Equal(inOut.body, TOGGLE_MACRO .. "/petpassive\n/petattack\n/cast Charge", "the in/out macro holds its commands now")
	H.Equal(renamed.body, "/petpassive\n/petstay", "a renamed one too")
	H.Equal(renamed.name, "My park", "keeping its name")
	H.Equal(mine.body, "/say hold!", "a macro of the player's with one of the names is left alone")
end)

test("pet commands: made when the fight ends after a reload mid-fight", function()
	local W = H.NewWorld()
	W.inCombat = true
	H.LoadAddon(W, ROOT)
	local Commands = W.ns.modules.PetCommands
	H.Equal(Commands.remote, nil, "not made in combat")
	H.Equal(#W.blocked, 0, "nothing blocked")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	H.True(Commands.remote ~= nil, "made after the fight")
	Boar(W, "PET_MODE_DEFENSIVE")
	H.True(Commands.remote:IsShown(), "and on the panel")
end)

test("pet commands: other classes don't get them", function()
	local W = H.NewWorld({ class = "MAGE" })
	H.LoadAddon(W, ROOT)
	H.Equal(W.ns.modules.PetCommands.enabled, nil, "off")
	H.Equal(rawget(W.env, "DeadeyePetKeys"), nil, "no buttons")
end)

return tests
