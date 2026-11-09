-- How far away the target is, after the range text: a band of yards from item
-- and spell range checks (Modules\Range.lua).
local H, ROOT = ...

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

local DOT = " \194\183 "

local function Setup(options)
	local W = H.NewWorld(options)
	H.LoadAddon(W, ROOT)
	W.Slash("range markalert off")
	return W, W.ns.modules.Range
end

local function Text(Range)
	local text = Range.frame.text
	return text:IsShown() and text.text or nil
end

-- A target this many yards away. Auto Shot reaches 8 yards to reach (35 by
-- default), Hunter's Mark 100, the duel-range check 10 (out of combat only),
-- Raptor Strike 5.
local function At(W, yards, reach)
	W.hasTarget, W.targetYards = true, yards
	W.inRange = yards >= 8 and yards <= (reach or 35)
	W.markable = yards <= 100
	W.close = yards <= 10
	W.meleeInRange = yards <= 5
	W.Fire("PLAYER_TARGET_CHANGED")
	W.Advance(0.12)
end

local function Fight(W)
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
end

test("distance: item checks give the band, in range and past it", function()
	local W, Range = Setup()
	At(W, 32)
	H.Equal(Text(Range), "Ranged" .. DOT .. "30-35 yd", "in Auto Shot range")
	At(W, 12)
	H.Equal(Text(Range), "Ranged" .. DOT .. "10-15 yd", "near its minimum")
	At(W, 42)
	H.Equal(Text(Range), "Out of range" .. DOT .. "40-45 yd", "just too far")
	At(W, 60)
	H.Equal(Text(Range), "Out of range" .. DOT .. "45-100 yd", "no item between 45 and 100 yards")
	At(W, 150)
	H.Equal(Text(Range), "Out of range" .. DOT .. "100+ yd", "past Hunter's Mark")
	At(W, 3)
	H.Equal(Text(Range), "Melee", "melee keeps its word")
	At(W, 6)
	H.Equal(Text(Range), "Dead zone", "and so does the dead zone")
end)

test("distance: in combat too, where only the range checks answer", function()
	local W, Range = Setup()
	Fight(W)
	At(W, 50)
	H.Equal(Text(Range), "No shot" .. DOT .. "45-100 yd", "item checks still answer for enemies")
	At(W, 20)
	H.Equal(Text(Range), "Ranged" .. DOT .. "15-20 yd", "in range")
	H.Equal(#W.blocked, 0, "nothing blocked")
end)

test("distance: without item checks, Auto Shot's reach and Hunter's Mark", function()
	local W, Range = Setup()
	W.itemRangeBlocked = true
	At(W, 20)
	H.Equal(Text(Range), "Ranged" .. DOT .. "8-35 yd", "Auto Shot's range")
	At(W, 60)
	H.Equal(Text(Range), "Out of range" .. DOT .. "35-100 yd", "between Auto Shot and Hunter's Mark")
	Fight(W)
	At(W, 60)
	H.Equal(Text(Range), "No shot", "nothing says how far at least: no band")
	-- No ranged weapon: past duel range doesn't say past Auto Shot's reach.
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	At(W, 20)
	W.inRange = nil -- the game's answer without a ranged weapon
	W.Advance(0.12)
	H.Equal(Text(Range), "Out of range", "no Auto Shot band without Auto Shot")
end)

test("distance: a longer reach from talents such as Hawk Eye", function()
	local W, Range = Setup()
	local spell = W.env.C_Spell
	local listed = spell.GetSpellInfo
	spell.GetSpellInfo = function(id)
		if id == 75 then
			return { name = "Auto Shot", minRange = 8, maxRange = 41, castTime = 0, spellID = 75 }
		end
		return listed and listed(id)
	end
	W.itemRangeBlocked = true
	At(W, 39, 41)
	H.Equal(Text(Range), "Ranged" .. DOT .. "8-41 yd", "the range the game lists, talents included")
	At(W, 44, 41)
	H.Equal(Text(Range), "Out of range" .. DOT .. "41-100 yd", "and past it")
	-- A game listing the range without talents: the items know better.
	spell.GetSpellInfo = listed
	W.itemRangeBlocked = false
	W.Advance(1.1)
	At(W, 38, 41)
	H.Equal(Text(Range), "Ranged" .. DOT .. "35-40 yd", "the items' band, past the listed 35")
end)

test("distance: only when asked for, and not over warnings", function()
	local W, Range = Setup()
	At(W, 32)
	W.Slash("range distance off")
	H.Equal(Text(Range), "Ranged", "turned off")
	W.Slash("range distance on")
	H.Equal(Text(Range), "Ranged" .. DOT .. "30-35 yd", "back on")
	W.hasTarget = false
	W.Fire("PLAYER_TARGET_CHANGED")
	W.Slash("move")
	W.Advance(0.12)
	H.Equal(Text(Range), "Ranged" .. DOT .. "30-35 yd", "a sample band while unlocked")
	W.Slash("lock")
	At(W, 32)
	Fight(W)
	W.Fire("UI_ERROR_MESSAGE", 1, "You are facing the wrong way!")
	W.Advance(0.12)
	H.Equal(Text(Range), "Face your target", "a warning keeps the text to itself")
end)

return tests
