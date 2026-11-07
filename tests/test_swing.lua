-- Your melee swing in the Auto Shot bar: a lane of its own beside Auto Shot's,
-- the lane for where you fight taking most of the bar.
local H, ROOT = ...

local RANGED, MAIN_HAND, OFF_HAND = 2, 0, 1

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

local function Setup(options)
	local W = H.NewWorld(options)
	H.LoadAddon(W, ROOT)
	local AS = W.ns.modules.AutoShot
	return W, AS, AS.bar
end

-- An enemy in melee range (the game's own melee check says so).
local function MeleeTarget(W)
	W.hasTarget, W.inRange, W.swingMeleeInRange = true, false, true
	W.Fire("PLAYER_TARGET_CHANGED")
end

local function Swing(W, speed)
	W.Fire("PLAYER_SWING", speed or 2.6, MAIN_HAND)
end

test("swing lane: melee swings split the bar, the swing taking most of it in melee", function()
	local W, AS, bar = Setup()
	MeleeTarget(W)
	H.False(bar:IsVisible(), "nothing to show yet")
	Swing(W)
	W.Advance(0.3)
	H.True(bar:IsVisible(), "the bar shows while you swing")
	H.True(bar.swing:IsShown(), "with a swing lane")
	H.Equal(bar.shot:GetHeight(), 5, "Auto Shot's lane: 30% of the 16 pixel bar")
	H.Equal(bar.label.text, "Swing", "the big lane's label")
	H.Equal(bar.time.text, "2.3", "and its time to the next swing")
	H.Near(bar.swing.value, 0.3 / 2.6, 0.02, "filling as the swing comes due")
	H.Equal(bar.spark.height, 5, "Auto Shot's spark fits its lane")
	-- Back out at range, before Auto Shot is on again: its lane grows already.
	W.inRange, W.swingMeleeInRange = true, false
	W.Advance(0.3)
	H.Equal(bar.shot:GetHeight(), 11, "out of melee: Auto Shot's lane")
	W.inRange, W.swingMeleeInRange = false, true
	W.Advance(0.3)
	H.Equal(bar.shot:GetHeight(), 5, "and back in")
	-- Stepping back out to shoot: Auto Shot's lane grows.
	W.inRange, W.swingMeleeInRange = true, false
	W.Fire("START_AUTOREPEAT_SPELL")
	W.Fire("PLAYER_SWING", 2.0, RANGED)
	W.Advance(0.3)
	H.Equal(bar.shot:GetHeight(), 11, "Auto Shot's lane: 70% at range")
	H.Equal(bar.label.text, "Reload", "its label")
	H.True(bar.swing:IsShown(), "the swing still in sight")
	-- No more swings: the lane goes after two swings' time.
	W.Advance(5.0)
	H.False(bar.swing:IsShown(), "gone")
	H.Equal(bar.shot:GetHeight(), 16, "Auto Shot has the whole bar again")
	H.Equal(#W.blocked, 0, "nothing blocked")
end)

test("swing lane: in combat too, off-hand swings and secret speeds are left out", function()
	local W, AS, bar = Setup()
	MeleeTarget(W)
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Fire("PLAYER_SWING", 2.6, OFF_HAND)
	W.Advance(0.1)
	H.False(bar.swing:IsShown(), "off hand: no lane")
	W.Fire("PLAYER_SWING", H.Secret(2.6), MAIN_HAND)
	W.Advance(0.1)
	H.False(bar.swing:IsShown(), "a speed the game keeps secret: no lane")
	Swing(W, 3.0)
	W.Advance(0.3)
	H.True(bar.swing:IsShown(), "a readable swing: the lane")
	Swing(W, 3.0)
	W.Advance(0.1)
	H.Near(bar.swing.value, 0.1 / 3.0, 0.02, "each swing starts it over")
end)

test("swing lane: a tall bar splits side by side, and the setting turns it off", function()
	local W, AS, bar = Setup()
	W.Slash("orientation vertical")
	MeleeTarget(W)
	Swing(W)
	W.Advance(0.3)
	H.Equal(bar.shot:GetWidth(), 5, "Auto Shot's lane: 30% of the 16 pixel width")
	H.Equal(bar.spark.width, 5, "its spark too")
	W.Slash("swing off")
	Swing(W)
	W.Advance(0.3)
	H.False(bar.swing:IsShown(), "turned off")
	H.Equal(bar.shot:GetWidth(), 16, "Auto Shot has the whole bar")
	H.False(bar:IsVisible(), "and the bar doesn't show for swings")
	W.Fire("START_AUTOREPEAT_SPELL")
	W.Fire("PLAYER_SWING", 2.0, RANGED)
	Swing(W)
	W.Advance(0.3)
	H.True(bar:IsVisible(), "shooting")
	H.False(bar.swing:IsShown(), "no swing lane while shooting either")
end)

test("swing lane: the options preview shows one beside the fake shots", function()
	local W, AS, bar = Setup()
	AS:SetPreview(true)
	W.Advance(0.3)
	H.True(bar.swing:IsShown(), "a fake swing in the preview")
	H.Equal(bar.shot:GetHeight(), 11, "Auto Shot's lane the big one")
	H.Equal(bar.label.text, "Reload", "and its label")
	AS:SetPreview(false)
	W.Advance(0.1)
	H.False(bar.swing:IsVisible(), "gone with the preview")
	H.Equal(AS.state.swingStart, nil, "the fake swing forgotten")
end)

return tests
