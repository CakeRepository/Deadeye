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

test("mark: reminds you in combat until you mark the target", function()
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
	W.Fire("PLAYER_TARGET_CHANGED")
	H.Equal(RangeText(Range), "Mark your target", "a new target needs a mark")
	CastMark(W)
	W.Advance(121)
	H.Equal(RangeText(Range), "Mark your target", "the mark has worn off after two minutes")
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
	local saved = W.env.ForeverHunterDB
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
local function SummonPet(W, overrides)
	W.pet = {
		name = "Grrl", health = 800, healthMax = 1000, happiness = 3, damage = 125, loyaltyRate = 1,
		loyalty = "Loyalty Level 3 (Faithful)", diet = { "Meat", "Fish" }, training = { 120, 85 },
	}
	for key, value in pairs(overrides or {}) do
		W.pet[key] = value
	end
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
	W.Advance(6)
	H.Equal(Pet.frame.alpha, 1, "pulse ends")
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
	W.Slash("pet width 200")
	H.True(W.Printed("Pet panel only runs on hunters."), "explains")
end)

return tests
