-- The aspect reminder.
local H, ROOT = ...

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

local HAWK, MONKEY, CHEETAH, PACK = 13165, 13163, 5118, 13159

-- A hunter who knows their aspects, with an enemy in Auto Shot range targeted.
local function Setup(options)
	local W = H.NewWorld(options)
	W.knownSpells = { [HAWK] = true, [MONKEY] = true, [CHEETAH] = true, [PACK] = true }
	H.LoadAddon(W, ROOT)
	W.Slash("range markalert off")
	W.hasTarget, W.inRange = true, true
	W.Fire("PLAYER_TARGET_CHANGED")
	return W, W.ns.modules.Aspect, W.ns.modules.Range
end

local function Fight(W)
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Advance(0.12)
end

local function Text(Range)
	local text = Range.frame.text
	return text:IsShown() and text.text or nil
end

test("aspect: Cheetah in a fight gets a warning until you switch to Hawk", function()
	local W, Aspect, Range = Setup()
	W.CastAspect(CHEETAH)
	W.Advance(0.12)
	H.Equal(Text(Range), "Ranged", "out of combat: travel in Cheetah all you like")
	H.Equal(#W.sounds, 0, "no alert out of combat")
	Fight(W)
	H.True(W.Printed("You're fighting in Aspect of the Cheetah: you'll be dazed when hit."), "alert as the fight starts")
	H.Equal(#W.sounds, 1, "with a sound")
	H.Equal(Text(Range), "Aspect of the Cheetah is on", "the range text says so")
	H.SameColor(Range.frame.text.textColor, Aspect.db.color, "in the warning color")
	W.CastAspect(HAWK)
	W.Advance(0.12)
	H.Equal(Text(Range), "Ranged", "Hawk: nothing to say")
	W.CastAspect(PACK)
	W.Advance(0.12)
	H.Equal(Text(Range), "Aspect of the Pack is on", "Pack dazes too")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	W.Advance(0.12)
	H.Equal(Text(Range), "Ranged", "gone when the fight ends")
end)

test("aspect: no aspect in a fight gets a warning once you have one to use", function()
	local W, Aspect, Range = Setup()
	W.knownSpells = {}
	Fight(W)
	H.Equal(Text(Range), "Ranged", "a new hunter without aspects isn't nagged")
	H.Equal(#W.sounds, 0, "no alert")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	W.knownSpells = { [MONKEY] = true }
	Fight(W)
	H.True(W.Printed("You're fighting without an aspect."), "alert as the fight starts")
	H.Equal(Text(Range), "No aspect", "the range text says so")
	W.CastAspect(MONKEY)
	W.Advance(0.12)
	H.Equal(Text(Range), "Ranged", "any aspect but Cheetah or Pack is fine")
end)

test("aspect: in combat it follows the aura's ID when the game hides aura details", function()
	local W, Aspect, Range = Setup()
	W.CastAspect(CHEETAH)
	Fight(W)
	H.Equal(Text(Range), "Aspect of the Cheetah is on", "read before the fight")
	W.CancelBuff("Aspect of the Cheetah")
	W.Advance(0.12)
	H.Equal(Text(Range), "No aspect", "its aura ID left your buffs")
	W.CastAspect(PACK)
	W.Advance(0.12)
	H.Equal(Text(Range), "Aspect of the Pack is on", "cast in combat")
	W.AddBuff("Rapid Fire", 3045)
	W.Advance(0.12)
	H.Equal(Text(Range), "Aspect of the Pack is on", "other buffs don't matter")
	W.CancelBuff("Aspect of the Pack")
	W.Advance(0.12)
	H.Equal(Text(Range), "No aspect", "the aura learned from the cast went away")
end)

test("aspect: reads the aura directly in combat where the game allows it", function()
	local W, Aspect, Range = Setup()
	W.aspectsReadableInCombat = true
	W.auraIDsHidden = true
	W.AddBuff("Aspect of the Cheetah", CHEETAH)
	Fight(W)
	H.Equal(Text(Range), "Aspect of the Cheetah is on", "read in combat")
	W.CancelBuff("Aspect of the Cheetah")
	W.Advance(0.12)
	H.Equal(Text(Range), "No aspect", "and seen to go")
end)

test("aspect: with aura IDs hidden too, your casts still count", function()
	local W, Aspect, Range = Setup()
	W.auraIDsHidden = true
	W.CastAspect(CHEETAH)
	Fight(W)
	H.Equal(Text(Range), "Aspect of the Cheetah is on", "read before the fight")
	W.CastAspect(HAWK)
	W.Advance(0.12)
	H.Equal(Text(Range), "Ranged", "the cast was seen")
	W.CancelBuff("Aspect of the Hawk")
	W.Advance(0.12)
	H.Equal(Text(Range), "Ranged", "can't tell it went, so no false alarm")
	W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-x", H.Secret(CHEETAH))
	W.Advance(0.12)
	H.Equal(Text(Range), "Ranged", "a secret spell ID isn't read")
end)

test("aspect: attack problems still come first", function()
	local W, Aspect, Range = Setup()
	W.CastAspect(CHEETAH)
	Fight(W)
	W.Fire("UI_ERROR_MESSAGE", 1, "You are facing the wrong way!")
	W.Advance(0.12)
	H.Equal(Text(Range), "Face your target", "turning around comes first")
end)

test("aspect: the reminder and each warning can be turned off", function()
	local W, Aspect, Range = Setup()
	W.CastAspect(CHEETAH)
	W.Slash("aspect daze off")
	Fight(W)
	H.Equal(Text(Range), "Ranged", "no Cheetah warning")
	H.Equal(#W.sounds, 0, "no alert")
	W.CancelBuff("Aspect of the Cheetah")
	W.Advance(0.12)
	H.Equal(Text(Range), "No aspect", "the other warning still works")
	W.Slash("aspect none off")
	W.Advance(0.12)
	H.Equal(Text(Range), "Ranged", "both off")
	W.Slash("aspect none on")
	W.Slash("aspect off")
	W.Advance(0.12)
	H.Equal(Text(Range), "Ranged", "the whole reminder off")
	W.Slash("aspect on")
	W.Slash("aspect pull off")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	Fight(W)
	H.Equal(#W.sounds, 0, "no alert at the pull")
	H.Equal(Text(Range), "No aspect", "but the warning shows")
end)

return tests
