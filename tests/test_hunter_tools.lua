-- The range indicator and the pet panel.
local H, ROOT = ...

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

local function Setup(options)
	local W = H.NewWorld(options)
	H.LoadAddon(W, ROOT)
	return W, W.ns.modules.Range, W.ns.modules.Pet
end

local function Target(W, ranged, melee, close)
	W.hasTarget = true
	W.inRange, W.meleeInRange, W.close = ranged, melee, close
	W.Fire("PLAYER_TARGET_CHANGED")
end

local function RangeText(Range)
	local text = Range.frame.text
	return text:IsShown() and text.text or nil
end

---------------------------------------------------------------------------
-- Range indicator
---------------------------------------------------------------------------
test("range: hidden without a target, then melee / ranged / dead zone / too far", function()
	local W, Range = Setup()
	H.False(Range.frame:IsVisible(), "hidden without a target")
	Target(W, true, false)
	H.True(Range.frame:IsVisible(), "shown with a target")
	H.Equal(RangeText(Range), "Ranged", "in Auto Shot range")
	H.SameColor(Range.frame.text.textColor, Range.db.colors.ranged, "ranged color")
	W.inRange, W.meleeInRange = false, true
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Melee", "melee range")
	W.inRange, W.meleeInRange, W.close = false, false, true
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Dead zone", "close but neither in melee nor Auto Shot range")
	W.close = false
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Out of range", "too far")
	W.hasTarget = false
	W.Fire("PLAYER_TARGET_CHANGED")
	H.False(Range.frame:IsVisible(), "hidden when the target is gone")
end)

test("range: a melee ability whose check calls every target in range doesn't make far targets read as melee", function()
	-- Seen in game: at level 10 (Raptor Strike, no Wing Clip yet) a target well inside
	-- Auto Shot range read as "Melee".
	local W, Range = Setup()
	Target(W, true, true)
	H.Equal(RangeText(Range), "Ranged", "Auto Shot reaches it, so it isn't in melee range")
	H.Equal(Range.frame.segments.melee.alpha < 0.5, true, "melee band dim")
	W.inRange, W.close = false, true
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Dead zone", "the broken check is ignored from then on")
	W.close = false
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Out of range", "too far")

	-- Out of combat it's caught even before Auto Shot can reach: past duel range isn't melee.
	local W2, Range2 = Setup()
	Target(W2, false, true, false)
	H.Equal(RangeText(Range2), "Out of range", "past duel range")
end)

test("range: in combat it never calls the restricted distance check", function()
	local W, Range = Setup()
	W.Slash("range markalert off")
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	Target(W, false, false, true)
	W.Advance(0.5)
	H.Equal(RangeText(Range), "No shot", "dead zone or too far: can't tell in combat")
	H.Equal(#W.blocked, 0, "no blocked distance checks")
end)

test("range: friendly targets and dead targets show nothing", function()
	local W, Range = Setup()
	Target(W, nil, nil)
	H.True(Range.frame:IsVisible(), "frame polls while there is a target")
	H.Equal(RangeText(Range), nil, "no text for a target you can't attack")
end)

test("range: show modes", function()
	local W, Range = Setup()
	W.Slash("range markalert off")
	W.Slash("range show problems")
	H.Equal(Range.db.show, "problems", "set by chat")
	Target(W, true, false)
	H.Equal(RangeText(Range), nil, "hidden while you can shoot")
	W.inRange, W.meleeInRange = false, true
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Melee", "shown when you can't")
	W.Slash("range show combat")
	H.Equal(RangeText(Range), nil, "only in combat")
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	H.Equal(RangeText(Range), "Melee", "in combat")
end)

test("range: wording, colors, disabling and moving", function()
	local W, Range = Setup()
	W.Slash("range deadzonetext TOO CLOSE")
	W.Slash("range deadzonecolor ff00ff")
	Target(W, false, false, true)
	H.Equal(RangeText(Range), "TOO CLOSE", "custom wording")
	H.SameColor(Range.frame.text.textColor, { 1, 0, 1 }, "custom color")
	W.Slash("range off")
	H.False(Range.frame:IsVisible(), "disabled")
	W.Slash("range on")
	W.hasTarget = false
	W.Fire("PLAYER_TARGET_CHANGED")
	W.Slash("move")
	H.True(Range.frame:IsVisible(), "shown to be dragged")
	H.True(Range.frame.mover:IsShown(), "blue overlay")
	H.Equal(RangeText(Range), "Ranged", "sample text while unlocked")
	W.Slash("range attach free")
	W.Slash("range y -120")
	local _, _, _, _, y = Range.frame:GetPoint(1)
	H.Equal(y, -120, "positioned by chat")
end)

test("range: sits on top of the Auto Shot bar and follows it until dragged off", function()
	local W, Range = Setup()
	local bar = W.ns.modules.AutoShot.bar
	local point, relativeTo, relativePoint, _, y = Range.frame:GetPoint(1)
	H.Equal(point, "BOTTOM", "anchored by its bottom")
	H.Equal(relativeTo, bar, "to the Auto Shot bar")
	H.Equal(relativePoint, "TOP", "on top of it")
	H.Equal(y, 4, "just clear of the bar's border")
	W.Slash("label above")
	_, _, _, _, y = Range.frame:GetPoint(1)
	H.Equal(y, 18, "moves up to clear text placed above the bar")
	-- Dropping it somewhere else gives it its own position.
	W.Slash("move")
	W.dropPoint = { "CENTER", "CENTER", 300, 100 }
	Range.frame.scripts.OnDragStop(Range.frame)
	H.Equal(Range.db.attach, "FREE", "detached by dragging")
	_, relativeTo, _, _, y = Range.frame:GetPoint(1)
	H.Equal(relativeTo, W.env.UIParent, "anchored to the screen now")
	H.Equal(y, 100, "where it was dropped")
	W.Slash("range attach bar")
	_, relativeTo = Range.frame:GetPoint(1)
	H.Equal(relativeTo, bar, "back on the bar")
end)

test("range: the color strip lights the band you are in", function()
	local W, Range = Setup()
	local segments = Range.frame.segments
	Target(W, true, false)
	H.True(Range.frame.strip:IsShown(), "strip shown")
	H.Equal(segments.ranged.alpha, 1, "Auto Shot band lit")
	H.True(segments.melee.alpha < 0.5, "melee band dim")
	W.inRange, W.meleeInRange, W.close = false, false, true
	W.Advance(0.12)
	H.Equal(segments.deadZone.alpha, 1, "dead zone lit")
	H.SameColor(segments.deadZone.color, Range.db.colors.deadZone, "band colors come from the settings")
	W.Slash("range markalert off")
	W.inCombat = true
	W.Advance(0.12)
	H.Equal(RangeText(Range), "No shot", "in combat without a hint")
	H.True(segments.deadZone.alpha > 0.5 and segments.tooFar.alpha > 0.5, "both possible bands half lit")
	H.True(segments.ranged.alpha < 0.5, "Auto Shot band dim")
	W.Slash("range style text")
	H.False(Range.frame.strip:IsShown(), "text only")
end)

test("range: Auto Shot's own errors settle too close or too far in combat", function()
	local W, Range = Setup()
	W.Slash("range markalert off")
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	Target(W, false, false)
	H.Equal(RangeText(Range), "No shot", "unknown at first")
	W.Fire("UI_ERROR_MESSAGE", 4, "Target too close")
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Dead zone", "the game said too close")
	W.Advance(1.3)
	H.Equal(RangeText(Range), "No shot", "the hint wears off")
	W.Fire("UI_ERROR_MESSAGE", 5, "Out of range.")
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Out of range", "the game said too far")
end)

test("facing and line of sight warnings come from the game's error messages", function()
	local W, Range = Setup()
	local AS = W.ns.modules.AutoShot
	W.Slash("range markalert off")
	Target(W, true, false)
	W.Fire("START_AUTOREPEAT_SPELL")
	W.Fire("PLAYER_SWING", 2.0, 2)
	W.Advance(2.1)
	W.Fire("UI_ERROR_MESSAGE", 2, "Target needs to be in front of you.")
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Face your target", "range text warns")
	H.Equal(AS.bar.label.text, "Face your target", "bar label warns")
	H.SameColor(AS.bar.label.textColor, AS.db.colors.outOfRangeText, "in the warning color")
	H.Equal(Range.frame.segments.ranged.alpha, 1, "the strip still shows the range")
	W.Fire("PLAYER_SWING", 2.0, 2)
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Ranged", "a shot clears the warning")
	W.Fire("UI_ERROR_MESSAGE", 3, "Target not in line of sight")
	W.Advance(0.12)
	H.Equal(RangeText(Range), "No line of sight", "line of sight")
	W.Advance(1.3)
	H.Equal(RangeText(Range), "Ranged", "the warning wears off")
	W.Fire("UI_ERROR_MESSAGE", 7, "Spell is not ready yet.")
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Ranged", "other errors are ignored")
end)

---------------------------------------------------------------------------
-- Hunter's Mark reminder
---------------------------------------------------------------------------
local function CastMark(W)
	W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-HM", 14325)
end

test("mark: reminds you in combat until your mark is out, and one mark is enough", function()
	local W, Range = Setup()
	Target(W, true, false)
	H.Equal(RangeText(Range), "Ranged", "no reminder out of combat")
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	H.Equal(RangeText(Range), "Mark your target", "reminder in combat")
	H.SameColor(Range.frame.text.textColor, Range.db.colors.noMark, "mark color")
	H.Equal(Range.frame.segments.ranged.alpha, 1, "the strip still shows the range")
	CastMark(W)
	H.Equal(RangeText(Range), "Ranged", "marked (any rank counts)")
	W.Advance(30)
	H.Equal(RangeText(Range), "Ranged", "still marked")
	-- Without enemy nameplates to look at, the mark is trusted for its two minutes.
	W.Fire("PLAYER_TARGET_CHANGED")
	H.Equal(RangeText(Range), "Ranged", "switching targets doesn't nag: you can only have one mark out")
	W.Advance(91)
	H.Equal(RangeText(Range), "Mark your target", "the mark has worn off after two minutes")
	CastMark(W)
	H.Equal(RangeText(Range), "Ranged", "marked again")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	H.Equal(RangeText(Range), "Mark your target", "a new fight needs a new mark")
end)

test("mark: follows your mark on enemy nameplates by its aura ID", function()
	local W, Range = Setup()
	W.cvars.nameplateMaxDistance = "41"
	-- Two enemies with nameplates. Your Serpent Sting (aura 300) is already on the first.
	W.plates = { { debuffs = { 300 }, inRange = true }, { debuffs = {}, inRange = true } }
	W.targetDebuffs = { 300 }
	Target(W, true, false)
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	H.Equal(RangeText(Range), "Mark your target", "no mark yet")
	CastMark(W)
	W.targetDebuffs = { 300, 512 } -- the mark lands as aura 512
	W.plates[1].debuffs = { 300, 512 }
	W.Advance(0.2)
	H.Equal(RangeText(Range), "Ranged", "marked")

	-- Shooting the other enemy: the mark is still on an enemy you can shoot.
	W.targetDebuffs = {}
	W.Fire("PLAYER_TARGET_CHANGED")
	W.Advance(0.6)
	H.Equal(RangeText(Range), "Ranged", "no nag while your mark is on an enemy in range")
	W.plates[1].inRange = false
	W.Advance(0.6)
	H.Equal(RangeText(Range), "Mark your target", "the marked enemy ran out of range")
	W.plates[1].inRange = true
	W.Advance(0.6)
	H.Equal(RangeText(Range), "Ranged", "and came back")
	-- The marked enemy dies: its nameplate goes, and the reminder comes back well
	-- before the mark's two minutes are up.
	table.remove(W.plates, 1)
	W.Advance(0.6)
	H.Equal(RangeText(Range), "Mark your target", "the marked enemy is gone")
end)

test("mark: nameplates that don't reach Auto Shot range can't rule a mark out", function()
	local W, Range = Setup()
	W.cvars.nameplateMaxDistance = "20" -- the Classic default
	W.plates = { { debuffs = {}, inRange = true } }
	Target(W, true, false)
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	CastMark(W)
	W.targetDebuffs = { 512 }
	W.Advance(0.2)
	-- Switch to the enemy with a nameplate; the marked one has none (past 20 yards).
	W.targetDebuffs = {}
	W.Fire("PLAYER_TARGET_CHANGED")
	W.Advance(0.6)
	H.Equal(RangeText(Range), "Ranged", "maybe just past nameplate range: no nag")
end)

test("mark: when your marked target dies, the next target needs a mark", function()
	local W, Range = Setup()
	W.auraIDsHidden = true -- even without aura IDs, the death of the marked target is seen
	Target(W, true, false)
	W.targetMarked = true -- marked before the pull
	W.Advance(0.2)
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	H.Equal(RangeText(Range), "Ranged", "marked")
	W.targetDead = true
	W.Advance(0.2)
	W.targetDead, W.targetMarked = false, false
	W.Fire("PLAYER_TARGET_CHANGED")
	H.Equal(RangeText(Range), "Mark your target", "the mark died with the target")
end)

test("mark: a mark seen before the pull counts in combat", function()
	local W, Range = Setup()
	W.targetMarked = true
	Target(W, true, false)
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Ranged", "remembered from before the pull")
end)

test("mark: reads the debuff directly when the game allows it, and can be turned off", function()
	local W, Range = Setup()
	W.markReadableInCombat = true
	W.inCombat = true
	Target(W, true, false)
	H.Equal(RangeText(Range), "Mark your target", "unmarked")
	W.targetMarked = true
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Ranged", "seen on the target")
	W.targetMarked = false
	W.Slash("range markalert off")
	H.Equal(RangeText(Range), "Ranged", "reminder off")
	W.markable = false
	W.Slash("range markalert on")
	W.Advance(0.12)
	H.Equal(RangeText(Range), "Ranged", "no reminder for targets you can't mark (or before you learn it)")
end)

---------------------------------------------------------------------------
-- Camera
---------------------------------------------------------------------------
test("camera: max distance is only touched when you turn it on", function()
	local W = H.NewWorld()
	W.cvars.cameraDistanceMaxZoomFactor = "2.3" -- set by hand with /console
	H.LoadAddon(W, ROOT)
	H.Equal(W.cvars.cameraDistanceMaxZoomFactor, "2.3", "your own setting is left alone")
	W.Slash("camera on")
	H.Equal(W.cvars.cameraDistanceMaxZoomFactor, "2.6", "max distance")
	W.Slash("camera zoom 2.2")
	H.Equal(W.cvars.cameraDistanceMaxZoomFactor, "2.2", "chosen distance")
	W.Slash("camera zoom 9")
	H.Equal(W.cvars.cameraDistanceMaxZoomFactor, "2.6", "capped at the game's limit")
	W.inCombat = true
	W.Slash("camera off")
	H.Equal(W.cvars.cameraDistanceMaxZoomFactor, "2.6", "waits for the end of combat")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	H.Equal(W.cvars.cameraDistanceMaxZoomFactor, "1.9", "game default restored")
	local saved = W.env.DeadeyeDB
	saved.modules.Camera.enabled = true
	local W2 = H.NewWorld({ savedVariables = saved })
	H.LoadAddon(W2, ROOT)
	H.Equal(W2.cvars.cameraDistanceMaxZoomFactor, "2.6", "applied again at login")
end)

---------------------------------------------------------------------------
-- Layout and upgrades
---------------------------------------------------------------------------
test("every options page fits in its two columns", function()
	local W = Setup()
	local window = W.ns.OptionsWindow
	W.Slash("")
	for index, section in ipairs(window.sections) do
		window:SelectSection(index)
		for _, widget in ipairs(window.pages[index].controls) do
			local _, _, _, x, y = widget:GetPoint(1)
			H.True(x < 300, section.name .. ": '" .. tostring(widget.spec.label or widget.spec.text) .. "' is in a third column")
			H.True(-y + widget.height <= 408, section.name .. ": a control runs past the bottom")
		end
	end
end)

test("upgrading moves the old default spots off the character, but not frames you moved", function()
	local saved = {
		modules = {
			AutoShot = { position = { x = 0, y = -180 } },
			Pet = { position = { x = -260, y = -180 } },
			Range = { position = { x = 120, y = -40 } }, -- you had dragged the range text
		},
	}
	local W, Range, Pet = Setup({ savedVariables = saved })
	local AS = W.ns.modules.AutoShot
	H.Equal(AS.db.position.y, -324, "bar lowered")
	H.Equal(Pet.db.position.x, -220, "pet panel next to the bar")
	H.Equal(Pet.db.position.y, -324, "pet panel lowered")
	H.Equal(Range.db.attach, "FREE", "your dragged range text stays put")
	local _, _, _, x = Range.frame:GetPoint(1)
	H.Equal(x, 120, "at its old spot")

	local moved = { modules = { AutoShot = { position = { x = 40, y = -180 } } } }
	local W2 = Setup({ savedVariables = moved })
	H.Equal(W2.ns.modules.AutoShot.db.position.x, 40, "a bar you moved stays")
	H.Equal(W2.ns.modules.AutoShot.db.position.y, -180, "a bar you moved stays")
end)

---------------------------------------------------------------------------
-- Pet panel
---------------------------------------------------------------------------
local function PetData(overrides)
	local pet = {
		name = "Grrl", level = 30, health = 800, healthMax = 1000, happiness = 3, damage = 125, loyaltyRate = 1,
		loyalty = "Loyalty Level 3 (Faithful)", diet = { "Meat", "Fish" }, training = { 120, 85 },
	}
	for key, value in pairs(overrides or {}) do
		pet[key] = value
	end
	return pet
end

local function SummonPet(W, overrides)
	W.pet = PetData(overrides)
	W.Fire("UNIT_PET", "player")
end

test("pet: nothing shown for a hunter who never had a pet", function()
	local W, _, Pet = Setup()
	H.False(Pet.frame:IsVisible(), "hidden")
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	H.False(W.Printed("without your pet"), "no nagging before you have a pet")
end)

test("pet: shows name, happiness, damage, health and loyalty", function()
	local W, _, Pet = Setup()
	SummonPet(W)
	local frame = Pet.frame
	H.True(frame:IsVisible(), "shown")
	H.True(Pet.db.hadPet, "remembers you have a pet")
	H.Equal(frame.name.text, "Grrl", "name")
	H.Equal(frame.mood.text, "Happy 125%", "happiness and damage")
	H.Equal(frame.icon.atlas, "UI-PetHappiness", "Blizzard's happy icon")
	H.Equal(frame.health.max, 1000, "health bar max")
	H.True(W.env.issecretvalue(frame.health.value), "secret health handed straight to the bar")
	H.Equal(frame.loyalty.text, "Loyalty Level 3 (Faithful)", "loyalty line")
end)

test("pet: tooltip lists damage, loyalty, training points and diet", function()
	local W, _, Pet = Setup()
	SummonPet(W)
	Pet.frame.scripts.OnEnter(Pet.frame)
	local lines = table.concat(W.env.GameTooltip.lines, " | ")
	H.True(lines:find("Grrl", 1, true), "name")
	H.True(lines:find("Happy: doing 125% damage", 1, true), "damage")
	H.True(lines:find("Gaining loyalty", 1, true), "loyalty trend")
	H.True(lines:find("Training points: 35 free of 120", 1, true), "training points")
	H.True(lines:find("Eats: Meat, Fish", 1, true), "diet")
	Pet.frame.scripts.OnLeave(Pet.frame)
	H.False(W.env.GameTooltip:IsShown(), "tooltip hidden")
end)

test("pet: alerts when happiness drops, with sound and a pulse", function()
	local W, _, Pet = Setup()
	SummonPet(W)
	W.pet.happiness, W.pet.damage = 2, 100
	W.Fire("UNIT_HAPPINESS", "pet")
	H.True(W.Printed("Grrl is content. Time to feed it (eats Meat, Fish)."), "feed alert")
	H.Equal(#W.sounds, 1, "alert sound")
	H.Equal(Pet.frame.mood.text, "Content 100%", "mood updated")
	H.Equal(Pet.frame.icon.atlas, "UI-PetNeutral", "content icon")
	W.Advance(0.5)
	H.True(Pet.frame.alpha < 1, "panel pulses")
	H.True(Pet.feedButton.alpha < 1, "and the feed button with it")
	H.SameColor(Pet.feedButton.background.color, { 1, 0.82, 0 }, "the feed button lights up while the pet isn't happy")
	W.Advance(6)
	H.Equal(Pet.frame.alpha, 1, "pulse ends")
	H.Equal(Pet.feedButton.alpha, 1, "pulse ends")
	W.pet.happiness = 3
	W.Fire("UNIT_HAPPINESS", "pet")
	H.Equal(#W.sounds, 1, "no alert when it gets happier")
	W.Slash("pet feedalert off")
	W.pet.happiness = 1
	W.Fire("UNIT_HAPPINESS", "pet")
	H.Equal(#W.sounds, 1, "feed alert can be turned off")
	H.Equal(Pet.frame.icon.atlas, "UI-PetMad", "unhappy icon")
end)

test("pet: dead, dismissed and missing in combat", function()
	local W, _, Pet = Setup()
	SummonPet(W)
	W.pet.dead = true
	W.Fire("UNIT_HEALTH", "pet")
	H.Equal(Pet.frame.name.text, "Your pet is dead", "dead")
	H.Equal(Pet.frame.loyalty.text, "Cast Revive Pet", "what to do")
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	H.True(W.Printed("Your pet is dead. Cast Revive Pet when you can."), "dead pet warning")
	W.inCombat = false
	W.pet = nil
	W.Fire("UNIT_PET", "player")
	H.Equal(Pet.frame.name.text, "No pet", "dismissed")
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	H.True(W.Printed("You're in combat without your pet."), "missing pet warning")
end)

test("pet: 'only when it needs attention' hides a happy pet", function()
	local W, _, Pet = Setup()
	SummonPet(W)
	W.Slash("pet show attention")
	H.False(Pet.frame:IsVisible(), "happy pet hidden")
	W.pet.happiness = 2
	W.Fire("UNIT_HAPPINESS", "pet")
	H.True(Pet.frame:IsVisible(), "shown when content")
end)

test("pet: layout options and the preview sample", function()
	local W, _, Pet = Setup()
	W.Slash("")
	H.True(Pet.frame:IsVisible(), "sample shown in the options preview")
	H.Equal(Pet.frame.name.text, "Your pet", "sample pet")
	W.Slash("")
	H.False(Pet.frame:IsVisible(), "hidden again without a pet")
	SummonPet(W)
	local tall = Pet.frame.height
	W.Slash("pet loyalty off")
	H.False(Pet.frame.loyalty:IsShown(), "loyalty line off")
	H.True(Pet.frame.height < tall, "panel shrinks")
	W.Slash("pet health off")
	H.False(Pet.frame.health:IsShown(), "health bar off")
	W.Slash("pet width 250")
	H.Equal(Pet.frame.width, 250, "width")
	W.Slash("pet off")
	H.False(Pet.frame:IsVisible(), "disabled")
end)

test("pet and range stay off for other classes", function()
	local W, Range, Pet = Setup({ class = "MAGE" })
	H.Equal(Range.frame, nil, "no range frame")
	H.Equal(Pet.frame, nil, "no pet frame")
	H.Equal(Pet.feedButton, nil, "no feed button")
	W.Slash("pet width 200")
	H.True(W.Printed("Pet panel only runs on hunters."), "explains")
end)

---------------------------------------------------------------------------
-- Feed button
---------------------------------------------------------------------------
local JERKY, MUTTON, SHANK, QUAIL, RAPTOR, MACKEREL, BREAD = 117, 3770, 3771, 8952, 12210, 787, 4540

-- Fills the bags with { bag, slot, itemID, count } entries, then fires the
-- client's bag event.
local function Bags(W, contents)
	W.bags = { [0] = { size = 16 }, [1] = { size = 12 }, [2] = { size = 12 }, [3] = { size = 12 }, [4] = { size = 12 } }
	for _, entry in ipairs(contents) do
		W.bags[entry[1]][entry[2]] = { itemID = entry[3], count = entry[4] }
	end
	W.Fire("BAG_UPDATE_DELAYED")
end

local function FeedTooltip(W, Pet)
	Pet.feedButton.scripts.OnEnter(Pet.feedButton)
	return table.concat(W.env.GameTooltip.lines, " | ")
end

test("feed button: feeds food close to the pet's level, lowest level and smallest stack first", function()
	local W, _, Pet = Setup()
	SummonPet(W) -- level 30, eats meat and fish
	Bags(W, {
		{ 0, 1, JERKY, 20 }, -- 25 levels below the pet: little happiness
		{ 0, 2, QUAIL, 10 }, -- above it: full happiness, but better food to keep
		{ 1, 3, MUTTON, 5 }, -- close to its level
		{ 2, 7, MUTTON, 3 }, -- the same, in a smaller stack
		{ 0, 3, BREAD, 20 }, -- not in its diet
	})
	local button = Pet.feedButton
	H.True(button:IsShown(), "shown next to a live pet")
	H.Equal(button:GetAttribute("type"), "spell", "casts a spell")
	H.Equal(button:GetAttribute("spell"), 6991, "Feed Pet")
	H.Equal(button:GetAttribute("target-bag"), 2, "on the smaller mutton stack")
	H.Equal(button:GetAttribute("target-slot"), 7, "on the smaller mutton stack")
	H.Equal(button.icon.texture, 133974, "shows the food")
	H.False(button.icon.desaturated, "in color")
	H.Equal(button.count.text, "8", "mutton left in all your bags")
	H.True(FeedTooltip(W, Pet):find("Feed Grrl | Mutton Chop (8 in your bags)", 1, true), "tooltip")

	W.Click(button)
	H.Equal(#W.casts, 1, "one cast per click")
	H.Equal(W.casts[1], 6991, "Feed Pet")
	H.Equal(W.used[1].bag, 2, "then the food")
	H.Equal(W.used[1].slot, 7, "then the food")
	W.cvars.ActionButtonUseKeyDown = "0"
	W.Click(button)
	H.Equal(#W.casts, 2, "one cast per click with 'cast on key down' off too")

	Bags(W, { { 0, 1, JERKY, 20 }, { 0, 2, QUAIL, 10 } })
	H.Equal(button:GetAttribute("target-slot"), 2, "quail once the mutton is gone, not the far lower jerky")
	Bags(W, { { 0, 1, JERKY, 20 } })
	H.True(FeedTooltip(W, Pet):find("Well below Grrl's level, so it gives less happiness.", 1, true), "warns about low food")
	W.pet.level = 40
	W.Fire("UNIT_LEVEL", "pet")
	H.True(FeedTooltip(W, Pet):find("Probably too low level for Grrl to eat.", 1, true), "warns about food that's too low")
	H.Equal(button:GetAttribute("target-slot"), 1, "still offered: the game has the last word")
end)

test("feed button: leaves food that makes you well fed, and food you skip, alone", function()
	local W, _, Pet = Setup()
	SummonPet(W)
	-- Roast Raptor would win (the same level, a smaller stack) but it's buff food.
	Bags(W, { { 0, 1, RAPTOR, 2 }, { 0, 2, SHANK, 10 }, { 0, 3, MACKEREL, 20 } })
	local button = Pet.feedButton
	H.Equal(button:GetAttribute("target-slot"), 2, "the wild hog shank, not the buff food")
	H.True(FeedTooltip(W, Pet):find("Saved for you (well fed): Roast Raptor", 1, true), "the tooltip says why")

	W.Click(button, "RightButton")
	H.Equal(#W.casts, 0, "a right-click doesn't feed")
	H.True(W.Printed("The feed button will leave Wild Hog Shank alone."), "says what it skips")
	H.Equal(button:GetAttribute("target-slot"), 3, "the mackerel instead")
	H.Equal(Pet.db.skipFoods[SHANK], "Wild Hog Shank", "remembered")
	H.True(FeedTooltip(W, Pet):find("Skipped: Wild Hog Shank. /deadeye pet unskip uses them again.", 1, true), "tooltip lists it")

	W.Slash("pet unskip")
	H.True(W.Printed("The feed button can use Wild Hog Shank again."), "unskipped")
	H.Equal(button:GetAttribute("target-slot"), 2, "back to the shank")
end)

test("feed button: with no food the pet eats, a click casts Feed Pet so you can pick", function()
	local W, _, Pet = Setup()
	SummonPet(W)
	Bags(W, { { 0, 1, BREAD, 5 } })
	local button = Pet.feedButton
	H.True(button:IsShown(), "still shown")
	H.Equal(button:GetAttribute("target-slot"), nil, "no food to use")
	H.Equal(button.icon.texture, 132165, "Feed Pet's own icon")
	H.True(button.icon.desaturated, "greyed out")
	H.Equal(button.count.text, "", "no count")
	local tooltip = FeedTooltip(W, Pet)
	H.True(tooltip:find("No food in your bags that Grrl eats.", 1, true), "says so")
	H.True(tooltip:find("Eats: Meat, Fish", 1, true), "and what it eats")
	W.Click(button)
	H.Equal(W.casts[1], 6991, "Feed Pet cast")
	H.Equal(#W.used, 0, "no food picked for you")
end)

test("feed button: sits beside the panel, away from the middle, and hides with it", function()
	local W, _, Pet = Setup()
	SummonPet(W)
	local button, panel = Pet.feedButton, Pet.frame
	local function Gap()
		local left, _, width = panel:GetRect()
		local buttonLeft, _, buttonWidth = button:GetRect()
		if buttonLeft < left then
			return left - (buttonLeft + buttonWidth)
		end
		return buttonLeft - (left + width)
	end
	H.Equal(button.height, panel.height, "as tall as the panel")
	H.True(select(1, button:GetRect()) < select(1, panel:GetRect()), "left of a panel left of center")
	H.Equal(Gap(), 3, "a small gap")
	W.Slash("pet x 300")
	H.True(select(1, button:GetRect()) > select(1, panel:GetRect()), "right of a panel right of center")
	H.Equal(Gap(), 3, "a small gap")
	W.Slash("pet scale 1.5")
	H.Equal(button.scale, 1.5, "scaled with the panel")
	H.Equal(Gap(), 3, "a small gap")
	W.Slash("move")
	W.dropPoint = { "CENTER", "CENTER", -500, 0 }
	panel.scripts.OnDragStop(panel)
	H.True(select(1, button:GetRect()) < select(1, panel:GetRect()), "follows a dragged panel")
	H.Equal(Gap(), 3, "a small gap")
	W.Slash("move")

	W.Slash("pet feedbutton off")
	H.False(button:IsShown(), "turned off")
	W.Slash("pet feedbutton on")
	W.Slash("pet show attention")
	H.False(button:IsShown(), "hidden with the panel while the pet is happy")
	W.Slash("pet show always")
	W.pet.dead = true
	W.Fire("UNIT_HEALTH", "pet")
	H.False(button:IsShown(), "hidden while the pet is dead")
end)

test("feed button: in combat only its looks change, the rest waits for the fight to end", function()
	local W, _, Pet = Setup()
	SummonPet(W)
	Bags(W, { { 0, 1, MUTTON, 5 }, { 0, 2, QUAIL, 10 } })
	local button = Pet.feedButton
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	Bags(W, { { 0, 2, QUAIL, 10 } })
	W.pet.happiness = 2
	W.Fire("UNIT_HAPPINESS", "pet")
	W.Slash("pet x 300")
	W.Slash("pet feedbutton off")
	W.Advance(1)
	H.Equal(#W.blocked, 0, "nothing the game would block: " .. table.concat(W.blocked, ", "))
	H.SameColor(button.background.color, { 1, 0.82, 0 }, "lights up as the pet gets hungry")
	H.Equal(button:GetAttribute("target-slot"), 1, "keeps its food until the fight ends")
	H.Equal(button.icon.texture, 133974, "and shows the food a click would use")
	H.True(button:IsShown(), "and stays")
	local _, _, _, x = Pet.frame:GetPoint(1)
	H.Equal(x, 300, "the panel itself still moves in combat")
	H.False(W.IsProtected(Pet.frame), "the panel never becomes protected")

	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	H.False(button:IsShown(), "turned off after the fight")
	W.Slash("pet feedbutton on")
	H.Equal(button:GetAttribute("target-slot"), 2, "bags looked at again after the fight")
	H.True(select(1, button:GetRect()) > select(1, Pet.frame:GetRect()), "on the panel's new side")
end)

test("feed button: after a reload mid-fight it is made when the fight ends", function()
	local W = H.NewWorld()
	W.pet = PetData()
	W.inCombat = true
	H.LoadAddon(W, ROOT)
	local Pet = W.ns.modules.Pet
	H.Equal(Pet.feedButton, nil, "not made in combat")
	H.True(Pet.frame:IsShown(), "the panel works meanwhile")
	H.Equal(#W.blocked, 0, "nothing the game would block: " .. table.concat(W.blocked, ", "))
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	H.True(Pet.feedButton ~= nil and Pet.feedButton:IsShown(), "made once the fight is over")
end)

return tests
