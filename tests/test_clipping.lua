-- Casting between Auto Shots: the safe-to-cast window on the bar, where a cast
-- in progress ends and how long it holds back the shot, and the delay report's
-- share for casting. Casts are driven through tests/mocks/clipping.lua.
local H, ROOT = ...

local RANGED = 2
local AIMED, MULTI, SCARE, VOLLEY = 20904, 25294, 1513, 1510 -- Aimed Shot rank 6, Multi-Shot rank 5
local WIDTH = 220 -- default bar width
-- Default world: 80ms world latency, so the aim window is 0.58s: on a 2.0s
-- cycle it opens 1.42s after the shot, on a 3.0s one 2.42s, on 4.0s 3.42s.

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

local function Setup(options)
	local W = H.NewWorld(options)
	H.LoadAddon(W, ROOT)
	local AS = W.ns.modules.AutoShot
	return W, AS, AS.bar, AS.state
end

local function Shot(W, speed)
	W.Fire("PLAYER_SWING", speed or 2.0, RANGED)
end

-- Turns Auto Shot on and fires the first shot, starting a cycle of this length.
local function Shooting(W, speed)
	W.Fire("START_AUTOREPEAT_SPELL")
	Shot(W, speed)
end

-- Pixels along the bar for a moment of the cycle (seconds after the shot).
local function At(seconds, speed)
	return WIDTH * seconds / speed
end

-- A piece's center, in pixels from the left end of a bar filling left to right.
local function Along(piece)
	local point, _, relativePoint, x = piece:GetPoint(1)
	H.Equal(point .. " of " .. relativePoint, "CENTER of LEFT", "measured from the bar's left end")
	return x
end

-- Where a shaded stretch starts and ends, in pixels from the bar's left end.
local function Span(piece)
	local x = Along(piece)
	return x - piece.width / 2, x + piece.width / 2
end

---------------------------------------------------------------------------
-- The safe-to-cast window
---------------------------------------------------------------------------
test("a slow bow leaves room for Aimed Shot: the window runs from the shot to its last safe start", function()
	local W, AS, bar = Setup()
	W.knownSpells["Aimed Shot"] = AIMED
	Shooting(W, 4.0) -- the aim window opens at 3.42, so a 3s cast must start by 0.42
	H.True(bar.safeZone:IsShown(), "window shown")
	local from, to = Span(bar.safeZone)
	H.Near(from, 0, 1e-6, "from the shot")
	H.Near(to, At(0.42, 4.0), 1e-6, "to the last safe start")
	H.SameColor(bar.safeZone.color, AS.db.colors.safe, "in the safe color")
	H.Equal(bar.safeZone.color[4], 0.5, "with that color's opacity")
	H.True(bar.safeLine:IsShown(), "line shown")
	H.Near(Along(bar.safeLine), At(0.42, 4.0), 1e-6, "line at the last safe start")
	H.Equal(bar.safeLine.width, 2, "a 2 pixel line")
	H.SameColor(bar.safeLine.color, AS.db.colors.safe, "line in the safe color")
	H.Equal(bar.safeLine.color[4], 1, "drawn solid")
	H.False(bar.clipText:IsShown(), "nothing to warn about")
	H.False(bar.castLine:IsShown(), "no cast")
	W.Advance(1.0)
	H.Near(Along(bar.safeLine), At(0.42, 4.0), 1e-6, "the line stays while the fill moves past it")
end)

test("when Aimed Shot can't fit, the line marks right after the shot and the bar says the least it costs", function()
	local W, AS, bar = Setup()
	W.knownSpells["Aimed Shot"] = AIMED
	Shooting(W) -- the aim window opens at 1.42, 1.58s too soon for a 3s cast
	H.False(bar.safeZone:IsShown(), "no safe stretch")
	H.True(bar.safeLine:IsShown(), "line shown")
	H.Near(Along(bar.safeLine), 1, 1e-6, "right after the shot, inside the bar")
	H.SameColor(bar.safeLine.color, AS.db.colors.clip, "in the clip color")
	H.True(bar.clipText:IsShown(), "the cost is shown")
	H.Equal(bar.clipText.text, "+1.6", "the least the cast costs")
	H.SameColor(bar.clipText.textColor, AS.db.colors.clip, "in the clip color")
	local point, relativeTo, relativePoint, x = bar.clipText:GetPoint(1)
	H.Equal(relativeTo, bar.marker, "beside the line where the aim window starts")
	H.Equal(point .. " of " .. relativePoint, "RIGHT of LEFT", "on the reload side")
	H.Equal(x, -2, "just clear of it")
	W.Advance(0.5)
	Shot(W, 1.5) -- Rapid Fire: the aim window now opens at 0.92
	H.Equal(bar.clipText.text, "+2.1", "a faster cycle costs more")
	W.Slash("decimals 2")
	H.Equal(bar.clipText.text, "+2.08", "decimals follow the timer's")
	W.Slash("decimals 0")
	H.Equal(bar.clipText.text, "+2.1", "but never fewer than one")
end)

test("Multi-Shot gets a window only once it turns out to have a cast", function()
	local W, AS, bar, S = Setup()
	Shooting(W)
	H.False(bar.safeLine:IsShown(), "no cast-time shot known: nothing extra")
	W.knownSpells["Multi-Shot"] = MULTI
	W.Advance(0.6)
	H.False(bar.safeLine:IsShown(), "the game lists Multi-Shot as instant")
	W.StartCast(MULTI, 500) -- but Forever gives it a short cast
	W.Advance(0.5)
	W.FinishCast()
	W.Advance(0.02)
	H.Near(S.learned["Multi-Shot"].seconds, 0.5, 1e-6, "its real cast time is remembered")
	H.True(bar.safeZone:IsShown(), "now it has a window")
	local _, to = Span(bar.safeZone)
	H.Near(to, At(1.42 - 0.5, 2.0), 1e-6, "for a 0.5s cast")
	H.SameColor(bar.safeLine.color, AS.db.colors.safe, "it fits")
	W.Slash("weavespell aimed")
	H.Equal(AS.db.weaveSpell, "AIMED", "spell picked by chat")
	H.False(bar.safeLine:IsShown(), "Aimed Shot isn't known")
	W.knownSpells["Aimed Shot"] = AIMED
	W.Advance(0.6)
	H.SameColor(bar.safeLine.color, AS.db.colors.clip, "learning it shows its line (it can't fit)")
	W.Slash("weavespell multi")
	H.SameColor(bar.safeLine.color, AS.db.colors.safe, "Multi-Shot picked")
	W.Slash("weavespell auto")
	H.SameColor(bar.safeLine.color, AS.db.colors.clip, "automatic: Aimed Shot first")
end)

test("the window follows your real Aimed Shot, until the game lists a new cast time", function()
	local W, AS, bar, S = Setup()
	W.knownSpells["Aimed Shot"] = AIMED
	Shooting(W, 4.0)
	local _, to = Span(bar.safeZone)
	H.Near(to, At(3.42 - 3.0, 4.0), 1e-6, "from the listed 3s")
	W.StartCast(AIMED, 2600) -- quicker than listed: haste the listing doesn't show
	W.Advance(2.6)
	W.FinishCast()
	W.Advance(0.02)
	_, to = Span(bar.safeZone)
	H.Near(to, At(3.42 - 2.6, 4.0), 1e-6, "from your real 2.6s cast")
	W.listedCastMs[AIMED] = 2143 -- the game lists a quicker cast now (Rapid Fire, say)
	W.Advance(0.6)
	_, to = Span(bar.safeZone)
	H.Near(to, At(3.42 - 2.143, 4.0), 1e-6, "a changed listing wins over your older cast")
end)

test("the options preview and test mode show a sample window until you know a cast-time shot", function()
	local W, AS, bar, S = Setup()
	W.Slash("")
	H.True(S.fake, "the preview loops fake shots")
	H.True(bar.safeZone:IsShown(), "sample window")
	local _, to = Span(bar.safeZone)
	H.Near(to, At(1.42 - 1.0, 2.0), 1e-6, "for a 1s sample cast")
	W.knownSpells["Aimed Shot"] = AIMED
	W.Advance(0.6)
	H.False(bar.safeZone:IsShown(), "your own Aimed Shot instead, which can't fit")
	H.Equal(bar.clipText.text, "+1.6", "and what it costs")
	W.Slash("")
	H.False(bar:IsVisible(), "preview over")

	-- Test mode: a real cast on the fake shots shows where it lands, and isn't counted.
	W.Slash("test")
	W.Advance(0.1)
	W.StartCast(AIMED) -- done 3.1s into the fake cycle
	W.Advance(0.02)
	H.True(bar.castLine:IsShown(), "the cast's end")
	H.Equal(bar.clipText.text, "+1.7", "and how far it runs into the aim window")
	W.Advance(3.0)
	W.FinishCast()
	H.Equal(S.heldCasting, 0, "fake shots count nothing")
	W.Slash("test")
end)

---------------------------------------------------------------------------
-- While casting
---------------------------------------------------------------------------
test("a cast that ends before the aim window shows where it ends, in the safe color", function()
	local W, AS, bar = Setup()
	W.knownSpells["Aimed Shot"] = AIMED
	Shooting(W, 3.0) -- the aim window opens at 2.42
	W.StartCast(SCARE) -- 1.5s
	W.Advance(0.02)
	H.True(bar.castLine:IsShown(), "the cast's end is shown")
	H.Near(Along(bar.castLine), At(1.5, 3.0), 1e-6, "where it ends")
	H.SameColor(bar.castLine.color, AS.db.colors.safe, "it ends in time")
	H.False(bar.clipZone:IsShown(), "nothing runs into the aim window")
	H.False(bar.clipText:IsShown(), "no delay")
	H.False(bar.safeLine:IsShown(), "the safe window steps aside while you cast")
	W.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-other", 1978) -- another spell, tried mid-cast
	W.Advance(0.02)
	H.True(bar.castLine:IsShown(), "still casting")
	W.Advance(1.46)
	W.FinishCast()
	W.Advance(0.02)
	H.False(bar.castLine:IsShown(), "gone once the cast is done")
	H.True(bar.safeLine:IsShown(), "the safe window is back")
	H.Equal(bar.label.text, "Reload", "nothing held back")
end)

test("a cast that runs into the aim window shades the overlap and says how long it holds back the shot", function()
	local W, AS, bar = Setup()
	Shooting(W, 3.0) -- the aim window opens at 2.42
	W.Advance(0.2)
	W.StartCast(AIMED, 2600) -- done at 2.8, 0.38s into the aim window
	W.Advance(0.02)
	H.Near(Along(bar.castLine), At(2.8, 3.0), 1e-6, "where it ends")
	H.SameColor(bar.castLine.color, AS.db.colors.clip, "it runs into the aim window")
	H.True(bar.clipZone:IsShown(), "the overlap is shaded")
	local from, to = Span(bar.clipZone)
	H.Near(from, At(2.42, 3.0), 1e-6, "from the start of the aim window")
	H.Near(to, At(2.8, 3.0), 1e-6, "to the end of the cast")
	H.SameColor(bar.clipZone.color, AS.db.colors.clip, "in the clip color")
	H.Equal(bar.clipText.text, "+0.4", "it holds the shot back 0.38s")
	W.PushBack(500) -- a hit: done at 3.3 now, past the end of the cycle
	W.Advance(0.02)
	H.Near(Along(bar.castLine), WIDTH - 1, 1e-6, "kept at the end of the bar")
	H.Near(select(2, Span(bar.clipZone)), WIDTH, 1e-6, "shaded to the end of the bar")
	H.Equal(bar.clipText.text, "+0.9", "the delay grows")
	W.Advance(2.3) -- in the aim window, still casting
	H.Equal(bar.label.text, "Casting", "the bar warns as before")
	H.Equal(bar.clipText.text, "+0.9", "the delay stays put")
	W.Advance(0.76)
	W.FinishCast()
	W.Advance(0.02)
	H.False(bar.clipText:IsShown(), "gone with the cast")
	H.False(bar.clipZone:IsShown(), "gone with the cast")
	H.False(bar.castLine:IsShown(), "gone with the cast")
	H.Equal(bar.label.text, "Aim", "the shot can go")
end)

test("channels show their end too, and pushback cuts them short", function()
	local W, AS, bar = Setup()
	Shooting(W, 3.0)
	W.Advance(1.0)
	W.StartChannel(VOLLEY, 6000) -- until 7.0
	W.Advance(0.02)
	H.Near(Along(bar.castLine), WIDTH - 1, 1e-6, "past the end of the cycle")
	H.Equal(bar.clipText.text, "+4.6", "4.58s into the aim window")
	W.PushBack(1000) -- until 6.0
	W.Advance(0.02)
	H.Equal(bar.clipText.text, "+3.6", "a shorter channel")
	W.FinishCast()
	W.Advance(0.02)
	H.False(bar.castLine:IsShown(), "channel over")
end)

test("an interrupted cast is gone at once; one started before Auto Shot shows how late the first shot is", function()
	local W, AS, bar, S = Setup()
	Shooting(W, 3.0)
	W.StartCast(AIMED)
	W.Advance(0.5)
	W.InterruptCast()
	W.Advance(0.02)
	H.False(bar.castLine:IsShown(), "interrupted")
	H.Equal(S.castEnds, nil, "forgotten")
	W.Fire("STOP_AUTOREPEAT_SPELL")
	W.Advance(3.0)

	W.StartCast(AIMED) -- 3s
	W.Advance(1.0)
	W.Fire("START_AUTOREPEAT_SPELL") -- the first shot only needs the aim window...
	H.Equal(bar.label.text, "Casting", "...but you are casting")
	H.Equal(bar.clipText.text, "+2.0", "for 2s more")
	W.Fire("PLAYER_DEAD")
	H.Equal(S.castGUID, nil, "dying ends the cast")
	H.Equal(S.castEnds, nil, "and its end")
end)

test("without readable cast info a cast's end comes from its listed cast time", function()
	local W, AS, bar = Setup({ missingGlobals = { UnitCastingInfo = true, UnitChannelInfo = true } })
	Shooting(W, 3.0)
	W.StartCast(SCARE) -- the game lists 1.5s
	W.Advance(0.02)
	H.Near(Along(bar.castLine), At(1.5, 3.0), 1e-6, "1.5s after it started")
	W.FinishCast()
	W.StartChannel(VOLLEY, 6000) -- channels list no cast time
	W.Advance(0.02)
	H.False(bar.castLine:IsShown(), "so its end is unknown")
	W.Advance(2.4) -- into the aim window
	H.Equal(bar.label.text, "Casting", "but it still holds the shot back")
end)

---------------------------------------------------------------------------
-- Combat, secrets and the delay report
---------------------------------------------------------------------------
test("a spell the game keeps secret: its end isn't drawn or guessed, and nothing is compared", function()
	local W, AS, bar, S = Setup()
	W.knownSpells["Aimed Shot"] = AIMED
	W.inCombat = true
	W.statsSecret = true
	W.Fire("PLAYER_REGEN_DISABLED")
	Shooting(W, 3.0)
	W.Advance(0.2)
	W.StartCast(AIMED, 2600, true) -- payloads and cast info all secret
	W.Advance(0.02)
	H.Equal(S.castGUID, true, "kept as 'a cast is on'")
	H.Equal(S.castEnds, nil, "its end is unknown")
	H.False(bar.castLine:IsShown(), "so it isn't drawn")
	H.False(bar.clipText:IsShown(), "or guessed")
	H.False(bar.safeLine:IsShown(), "the safe window steps aside while you cast")
	W.PushBack(500) -- a secret pushback
	W.Advance(2.3) -- into the aim window
	H.Equal(bar.label.text, "Casting", "it still blocks the aim window")
	W.FinishCast()
	W.Advance(0.02)
	H.Equal(S.learned["Aimed Shot"], nil, "nothing learned from it")
	H.Equal(bar.label.text, "Aim", "cast over")
	H.True(bar.safeLine:IsShown(), "the safe window is back, from the listed cast time")
end)

test("the delay report says how much of the lost time casting cost", function()
	local W, AS, bar, S = Setup()
	W.knownSpells["Aimed Shot"] = AIMED
	W.Slash("report on")
	W.inCombat = true
	W.statsSecret = true
	W.Fire("PLAYER_REGEN_DISABLED")
	Shooting(W) -- 1: 2.0s cycles, the aim window opens 1.42s after each shot
	W.Advance(0.1)
	W.StartCast(AIMED) -- 3s: done at 3.1, 1.68s into the aim window
	W.Advance(0.04)
	H.Equal(bar.clipText.text, "+1.7", "in combat the cast's end is still readable")
	W.Advance(2.96)
	W.FinishCast()
	W.Advance(0.58) -- the shot goes off a full aim window after the cast
	Shot(W) -- 2: 1.68s late, all of it casting
	W.Advance(0.5)
	W.StartCast(SCARE, 900) -- done before the aim window
	W.Advance(0.9)
	W.FinishCast()
	W.Advance(0.6)
	Shot(W) -- 3: on time
	W.Advance(2.6)
	Shot(W) -- 4: 0.6s late, moving
	H.Equal(S.fight.shots, 4, "shots")
	H.Equal(S.fight.delayed, 2, "held back")
	H.Near(S.fight.lost, 2.28, 1e-6, "lost in all")
	H.Equal(S.fight.castDelayed, 1, "held back by casting")
	H.Near(S.fight.castLost, 1.68, 1e-6, "lost to casting")
	W.Slash("stats")
	H.True(W.Printed("This fight: 4 shots, 2 held back, 2.3s of Auto Shot lost to moving or casting. Casting held back 1 of them and cost 1.7s."), "stats mid-fight")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	H.True(W.Printed("Last fight: 4 shots, 2 held back, 2.3s of Auto Shot lost to moving or casting. Casting held back 1 of them and cost 1.7s."), "report after the fight")
	H.Equal(S.fight.castDelayed, 0, "counter reset for the next fight")
end)

test("casting only takes the blame for the time it overlapped the aim window", function()
	local W, AS, bar, S = Setup()
	Shooting(W) -- the aim window opens at 1.42
	W.Advance(0.3)
	W.StartCast(SCARE) -- done at 1.8, 0.38s into the aim window
	W.Advance(1.5)
	W.FinishCast()
	W.moving = true -- then you move for half a second
	W.Advance(0.5)
	W.moving = false
	W.Advance(0.58)
	Shot(W) -- at 2.88: 0.88s late
	H.Near(S.fight.lost, 0.88, 1e-6, "lost in all")
	H.Near(S.fight.castLost, 0.38, 1e-6, "of it casting")
	W.Advance(0.5)
	W.StartCast(SCARE, 1000) -- 0.08s into the next aim window: within the jitter
	W.Advance(1.0)
	W.FinishCast()
	W.moving = true
	W.Advance(0.3)
	W.moving = false
	W.Advance(0.58)
	Shot(W) -- 0.38s late
	H.Equal(S.fight.delayed, 2, "both shots held back")
	H.Equal(S.fight.castDelayed, 1, "but only the first by casting")
	H.Near(S.fight.castLost, 0.38, 1e-6, "the second was moving")
end)

test("a shot seen before its cast's stop event still charges the cast, once", function()
	local W, AS, bar, S = Setup()
	Shooting(W) -- the aim window opens at 1.42
	W.Advance(0.5)
	W.StartCast(SCARE) -- done at 2.0, 0.58s into the aim window
	W.Advance(2.08)
	Shot(W) -- 0.58s late; a shot can't go off mid-cast, so the cast is over
	H.Equal(S.castGUID, nil, "the shot ended the cast")
	H.Equal(S.fight.castDelayed, 1, "held back by casting")
	H.Near(S.fight.castLost, 0.58, 1e-6, "no more than the shot was late")
	W.FinishCast() -- the stop event arrives late
	W.Advance(2.0)
	Shot(W)
	H.Equal(S.fight.castDelayed, 1, "not counted twice")
end)

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------
test("each part can be turned off and recolored, from chat or the Bar page", function()
	local W, AS, bar = Setup()
	W.knownSpells["Aimed Shot"] = AIMED
	Shooting(W)
	H.True(bar.clipText:IsShown(), "cost shown")
	W.Slash("clipdelay off")
	H.False(bar.clipText:IsShown(), "cost off")
	H.True(bar.safeLine:IsShown(), "the line stays")
	W.Slash("safewindow off")
	H.False(bar.safeLine:IsShown(), "safe window off")
	W.StartCast(AIMED)
	W.Advance(0.02)
	H.True(bar.castLine:IsShown(), "a cast's end has its own switch")
	H.True(bar.clipZone:IsShown(), "and so does its overlap")
	H.False(bar.clipText:IsShown(), "the delay stays off")
	W.Slash("castend off")
	H.False(bar.castLine:IsShown(), "cast end off")
	H.False(bar.clipZone:IsShown(), "overlap off")
	W.Slash("clipdelay on")
	H.True(bar.clipText:IsShown(), "the delay works without the line")
	W.Slash("clipcolor ff00ff80")
	H.SameColor(bar.clipText.textColor, { 1, 0, 1 }, "clip color")
	W.Slash("castend on")
	H.Near(bar.clipZone.color[4], 128 / 255, 1e-6, "with its opacity")
	W.Slash("safecolor 00ff00")
	H.SameColor(AS.db.colors.safe, { 0, 1, 0 }, "safe color")
	H.SameColor(bar.safeZone.color, { 0, 1, 0 }, "on the bar")

	W.Slash("")
	local window = W.ns.OptionsWindow
	local toggle = window:GetControl("Bar", "Show where it's safe to start it")
	H.False(toggle.check:GetChecked(), "the checkbox shows the setting")
	toggle.check:Click()
	H.True(AS.db.showSafeWindow, "turned on from the window")
	window:GetControl("Bar", "Spell to fit between shots").dropdown:Pick("Multi-Shot")
	H.Equal(AS.db.weaveSpell, "MULTI", "spell picked from the window")
	W.Slash("castend off")
	window.resetPageButton:Click()
	H.True(AS.db.showCastEnd, "the Bar page's reset turns it back on")
	H.Equal(AS.db.weaveSpell, "AUTO", "and the spell")
	H.SameColor(AS.db.colors.safe, { 0.35, 0.75, 1 }, "and its colors")
	W.Slash("clipcolor 00ffff")
	window:GetControl("Colors", "Idle")
	window.resetPageButton:Click()
	H.SameColor(AS.db.colors.clip, { 0, 1, 1 }, "the Colors page leaves them alone")
end)

test("vertical and reversed bars put the window on the fill's side and the cost beside the aim window", function()
	local W, AS, bar = Setup()
	W.knownSpells["Aimed Shot"] = AIMED
	W.Slash("orientation vertical") -- 16 wide, 220 tall, filling upwards
	Shooting(W, 4.0)
	local _, _, relativePoint, x, y = bar.safeZone:GetPoint(1)
	H.Equal(relativePoint, "BOTTOM", "measured from the bottom")
	H.Near(y, At(0.42, 4.0) / 2, 1e-6, "centered halfway up the window")
	H.Equal(bar.safeZone.width, 16, "as wide as the bar")
	H.Near(bar.safeZone.height, At(0.42, 4.0), 1e-6, "as tall as the window")
	H.Equal(bar.safeLine.height, 2, "a 2 pixel line")
	local point
	point, _, relativePoint, x, y = bar.clipText:GetPoint(1)
	H.Equal(point .. " of " .. relativePoint, "TOP of BOTTOM", "the cost goes below the aim window's line")
	H.Equal(y, -2, "just clear of it")
	W.Slash("reverse on") -- filling downwards from the top
	_, _, relativePoint, x, y = bar.safeLine:GetPoint(1)
	H.Equal(relativePoint, "TOP", "measured from the top")
	H.Near(y, -At(0.42, 4.0), 1e-6, "below the top")
	point, _, relativePoint, x, y = bar.clipText:GetPoint(1)
	H.Equal(point .. " of " .. relativePoint, "BOTTOM of TOP", "the cost goes above the aim window's line")
	H.Equal(y, 2, "just clear of it")
	W.Slash("orientation horizontal") -- filling right to left
	_, _, relativePoint, x = bar.safeLine:GetPoint(1)
	H.Equal(relativePoint, "RIGHT", "measured from the right")
	H.Near(x, -At(0.42, 4.0), 1e-6, "left of the right end")
	point, _, relativePoint, x = bar.clipText:GetPoint(1)
	H.Equal(point .. " of " .. relativePoint, "LEFT of RIGHT", "the cost goes right of the aim window's line")
	H.Equal(x, 2, "just clear of it")
end)

return tests
