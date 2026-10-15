-- The Tranquilizing Shot callout (Modules\Tranq.lua). Enemies and their buffs
-- come from tests/mocks/tranq.lua.
local H, ROOT = ...

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

local FRENZY = 19451 -- Magmadar's
local DEADEN_MAGIC = 19714 -- Shazzrah's magic buff, which a priest purges
local RAID_WARNING_SOUND = 8959
local OUT_OF_RANGE, NOTHING_TO_DISPEL = 5, 20 -- GetGameMessageInfo indexes

local function Setup(options)
	options = options or {}
	if options.tranqKnown == nil then
		options.tranqKnown = true
	end
	local W = H.NewWorld(options)
	H.LoadAddon(W, ROOT)
	return W, W.ns.modules.Tranq
end

-- The callout's big text while it shows, else nil.
local function Callout(Tranq)
	local frame = Tranq.frame
	return frame ~= nil and frame:IsShown() and frame.text.text or nil
end

-- The line under it, while it shows.
local function Detail(Tranq)
	local detail = Tranq.frame.detail
	return Tranq.frame:IsShown() and detail:IsShown() and detail.text or nil
end

-- What a secret value holds: tests may look, addon code can't.
local SECRET_MT = getmetatable(H.Secret(0))
local function Inside(value)
	H.True(type(value) == "table" and getmetatable(value) == SECRET_MT, "a secret value")
	return rawget(value, 1)
end

-- Starts a fight with enemy key as your target.
local function Pull(W, key, fields)
	if not W.mobs[key] then
		W.AddMob(key, fields)
	end
	W.ShowMob("target", key)
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Advance(0.3)
end

local function EndFight(W)
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	W.Advance(6)
end

---------------------------------------------------------------------------
-- Dormant without the spell
---------------------------------------------------------------------------
test("tranq: dormant for hunters who don't know Tranquilizing Shot, awake once they learn it", function()
	local W, Tranq = Setup({ tranqKnown = false })
	H.True(Tranq.enabled, "runs on hunters")
	H.Equal(Tranq.frame, nil, "no callout frame")
	H.Equal(#Tranq:GetOptionSections(), 0, "no options page")
	H.False(Tranq.events:IsEventRegistered("UNIT_AURA"), "not watching auras")
	H.Equal(Tranq.events:GetScript("OnUpdate"), nil, "not checking enemies")
	local sounds = #W.sounds
	Pull(W, "magmadar")
	local id = W.Buff("magmadar", FRENZY)
	W.Advance(0.5)
	H.Equal(#W.sounds, sounds, "no callout")
	W.Unbuff("magmadar", id)
	EndFight(W)

	W.tranqKnown = true
	W.Fire("SPELLS_CHANGED")
	H.True(Tranq.frame ~= nil, "frame made once you know it")
	H.Equal(#Tranq:GetOptionSections(), 1, "one options page")
	H.True(Tranq.events:IsEventRegistered("UNIT_AURA"), "watching auras")
	Pull(W, "magmadar")
	W.Buff("magmadar", FRENZY)
	W.Advance(0.3)
	H.Equal(Callout(Tranq), "Tranq Shot!", "the next frenzy gets a callout")
	H.Equal(#W.sounds, sounds + 1, "and a sound")

	local W2, Tranq2 = Setup({ class = "MAGE", tranqKnown = true })
	H.False(Tranq2.enabled, "other classes don't run it")
	H.Equal(Tranq2.frame, nil, "and get no frame")
	W2.Slash("tranq fontsize 40")
	H.True(W2.Printed("Tranq Shot callout only runs on hunters."), "says so")
end)

---------------------------------------------------------------------------
-- Detection
---------------------------------------------------------------------------
test("tranq: a frenzy on your target in a fight brings a big callout with a sound", function()
	local W, Tranq = Setup()
	Pull(W, "magmadar")
	H.Equal(Callout(Tranq), nil, "nothing yet")
	local sounds = #W.sounds
	local id = W.Buff("magmadar", FRENZY) -- secret in combat: the game won't say it's an enrage
	W.Advance(0.3)
	H.Equal(Callout(Tranq), "Tranq Shot!", "callout")
	H.Equal(#W.sounds, sounds + 1, "one sound")
	H.Equal(W.sounds[#W.sounds].id, RAID_WARNING_SOUND, "the raid warning sound by default")
	H.SameColor(Tranq.frame.text.textColor, { 1, 0.45, 0.1 }, "alert color")
	H.Equal(Inside(Detail(Tranq)), "Frenzy", "the buff's own name, handed over secret")
	H.Equal(Inside(Tranq.frame.icon.texture), 136224, "and its icon")
	H.True(Tranq.frame.alpha < 1, "it pulses")
	local _, _, _, _, y = Tranq.frame:GetPoint(1)
	H.True(y > 150, "near the top of the screen")
	W.Advance(3)
	H.Equal(Tranq.frame.alpha, 1, "then holds steady")
	H.Equal(#W.sounds, sounds + 1, "no repeated sound")
	W.Unbuff("magmadar", id)
	W.Advance(0.3)
	H.Equal(Callout(Tranq), nil, "gone with the frenzy")
	H.Equal(#W.blocked, 0, "nothing the game would block: " .. table.concat(W.blocked, ", "))
end)

test("tranq: buffs read before the pull are sorted out, so only the enrage counts in the fight", function()
	local W, Tranq = Setup()
	W.AddMob("shazzrah")
	W.Buff("shazzrah", DEADEN_MAGIC, { dispelName = "Magic" })
	local frenzy = W.Buff("shazzrah", FRENZY)
	W.ShowMob("target", "shazzrah")
	W.Advance(0.3) -- out of combat: read directly
	H.Equal(Callout(Tranq), nil, "no callout out of a fight")
	H.Equal(Tranq.frame:IsShown(), false, "hidden")
	Pull(W, "shazzrah")
	H.Equal(Callout(Tranq), "Tranq Shot!", "the frenzy was known to be one")
	H.Equal(Inside(Detail(Tranq)), "Frenzy", "about the frenzy, not the magic buff")
	W.Unbuff("shazzrah", frenzy)
	W.Advance(0.3)
	H.Equal(Callout(Tranq), nil, "the magic buff alone doesn't count")
end)

test("tranq: in a fight a new buff the game won't name counts, one already there doesn't", function()
	local W, Tranq = Setup()
	Pull(W, "shazzrah")
	W.Buff("shazzrah", DEADEN_MAGIC, { dispelName = "Magic" })
	W.Advance(0.3)
	H.Equal(Callout(Tranq), "Tranq Shot!", "can't be told from an enrage in combat")
	H.Equal(Inside(Detail(Tranq)), "Deaden Magic", "but its name shows, so you can")
	-- Another enemy already had its buff when you first look at it.
	W.AddMob("imp")
	W.Buff("imp", DEADEN_MAGIC, { dispelName = "Magic" })
	W.ShowMob("target", "imp")
	W.Advance(0.3)
	H.Equal(Callout(Tranq), nil, "not news")
	-- Buffs nobody in your group can remove never count.
	W.Buff("imp", 16170, { dispelName = "Magic", removable = false })
	W.Advance(0.3)
	H.Equal(Callout(Tranq), nil, "left out by the game's filter")
end)

test("tranq: in combat a hidden enrage and a hidden magic buff look the same to the addon", function()
	-- The addon never reads secrets, so what it does can't depend on what they hold.
	local function Run(dispelName)
		local W, Tranq = Setup()
		W.group = "raid"
		W.Slash("tranq announce on")
		Pull(W, "boss")
		local sounds = #W.sounds
		W.Buff("boss", FRENZY, { dispelName = dispelName })
		W.Advance(0.3)
		local shown, detail = Callout(Tranq), Inside(Detail(Tranq))
		W.CastTranq()
		W.Advance(2.5)
		return { shown, #W.sounds - sounds, Callout(Tranq), #W.chat, W.chat[1] and W.chat[1].text, detail }
	end
	local enrage, magic = Run(""), Run("Magic")
	for i = 1, 5 do
		H.Equal(enrage[i], magic[i], "step " .. i .. " is the same")
	end
	H.Equal(enrage[1], "Tranq Shot!", "both called out")
	H.Equal(enrage[3], "Still enraged!", "both judged by what stays")
	H.Equal(enrage[6], "Frenzy", "the secrets were different")
end)

test("tranq: frenzies the game flags as never secret are read directly, even without aura IDs", function()
	local W, Tranq = Setup()
	W.readableInCombat[FRENZY] = true
	W.auraIDsHidden = true
	Pull(W, "magmadar")
	W.Buff("magmadar", FRENZY)
	W.Advance(0.3)
	H.Equal(Callout(Tranq), "Tranq Shot!", "found by its spell ID")
	H.Equal(Detail(Tranq), "Frenzy", "readable")

	-- Without that flag, a client that hides aura IDs leaves nothing to go on.
	local W2, Tranq2 = Setup()
	W2.auraIDsHidden = true
	Pull(W2, "magmadar")
	W2.Buff("magmadar", FRENZY)
	W2.Advance(0.3)
	H.Equal(Callout(Tranq2), nil, "nothing to see")
end)

test("tranq: aura data that comes back as one secret value still gets a callout", function()
	local W, Tranq = Setup()
	W.auraDataOpaque = true
	Pull(W, "magmadar")
	W.Buff("magmadar", FRENZY)
	W.Advance(0.3)
	H.Equal(Callout(Tranq), "Tranq Shot!", "callout")
	H.Equal(Detail(Tranq), nil, "no name to show")
end)

test("tranq: bosses and focus are watched, nameplates when you ask, enemies you don't fight never", function()
	local W, Tranq = Setup()
	W.AddMob("chromaggus")
	W.ShowMob("boss1", "chromaggus")
	W.Fire("ENCOUNTER_START", 615, "Chromaggus", 9, 40)
	Pull(W, "whelp")
	W.Buff("chromaggus", 23128)
	W.Advance(0.3)
	H.Equal(Callout(Tranq), "Tranq Shot!", "the boss, though you target something else")
	W.playerDead, W.inCombat = true, false -- the encounter goes on without you
	W.mobs.chromaggus.combat = true
	W.Advance(0.3)
	H.Equal(Callout(Tranq), nil, "not while you're dead")
	W.playerDead = false -- a battle res: still out of combat, but the encounter goes on
	W.Advance(0.3)
	H.Equal(Callout(Tranq), "Tranq Shot!", "back once you're up")

	local W2, Tranq2 = Setup()
	W2.AddMob("hound")
	W2.ShowMob("focus", "hound")
	Pull(W2, "whelp")
	W2.Buff("hound", FRENZY)
	W2.Advance(0.3)
	H.Equal(Callout(Tranq2), "Tranq Shot!", "your focus")

	local W3, Tranq3 = Setup()
	Pull(W3, "whelp")
	W3.AddMob("raptor")
	W3.ShowMob("nameplate3", "raptor")
	W3.Advance(0.3)
	local id = W3.Buff("raptor", FRENZY)
	W3.Advance(0.3)
	H.Equal(Callout(Tranq3), nil, "nameplates aren't watched by default")
	W3.Unbuff("raptor", id)
	W3.Slash("tranq nameplates on")
	W3.Advance(0.3)
	W3.Buff("raptor", FRENZY)
	W3.Advance(0.3)
	H.Equal(Callout(Tranq3), "Tranq Shot!", "they are once you ask")
	W3.mobs.raptor.threat = false
	W3.Advance(0.3)
	H.Equal(Callout(Tranq3), nil, "not an enemy you're fighting (you aren't on its threat list)")

	local W4, Tranq4 = Setup()
	Pull(W4, "whelp", { combat = false })
	W4.Buff("whelp", FRENZY)
	W4.Advance(0.3)
	H.Equal(Callout(Tranq4), nil, "a target that isn't in the fight")
	W4.mobs.whelp.dead = true
	W4.mobs.whelp.combat = nil
	W4.Advance(0.3)
	H.Equal(Callout(Tranq4), nil, "or is dead")

	-- Tranquilizing Shot is for creatures: a priest's shield on an enemy player doesn't count.
	local W5, Tranq5 = Setup()
	Pull(W5, "rogue", { player = true })
	W5.Buff("rogue", 16170, { dispelName = "Magic" })
	W5.Advance(0.3)
	H.Equal(Callout(Tranq5), nil, "enemy players are left out")
end)

---------------------------------------------------------------------------
-- After your shot
---------------------------------------------------------------------------
test("tranq: your shot clears the callout, and the enrage going away confirms it", function()
	local W, Tranq = Setup()
	Pull(W, "magmadar")
	local id = W.Buff("magmadar", FRENZY)
	W.Advance(0.3)
	H.Equal(Callout(Tranq), "Tranq Shot!", "callout")
	W.CastTranq()
	H.Equal(Callout(Tranq), nil, "cleared at once")
	W.Advance(0.5)
	H.Equal(Callout(Tranq), nil, "the shot is on its way")
	W.Unbuff("magmadar", id)
	W.Advance(0.3)
	H.Equal(Callout(Tranq), "Enrage removed!", "confirmed")
	H.SameColor(Tranq.frame.text.textColor, { 0.35, 0.9, 0.35 }, "in green")
	W.Advance(3)
	H.Equal(Callout(Tranq), nil, "then gone")
end)

test("tranq: an enrage still there after your shot missed; it's called out again when your shot is ready", function()
	local W, Tranq = Setup()
	Pull(W, "huhuran")
	W.Buff("huhuran", 26051)
	W.Advance(0.3)
	local sounds = #W.sounds
	W.CastTranq()
	W.Advance(2.5)
	H.Equal(Callout(Tranq), "Still enraged!", "missed or resisted")
	H.Equal(Detail(Tranq), "Your Tranquilizing Shot missed or was resisted.", "says so")
	H.SameColor(Tranq.frame.text.textColor, { 1, 0.25, 0.25 }, "in red")
	W.Advance(5)
	H.Equal(Callout(Tranq), nil, "no callout while your shot is cooling down")
	W.Advance(13)
	H.Equal(Callout(Tranq), "Tranq Shot!", "called out again after 20 seconds")
	H.Equal(#W.sounds, sounds + 1, "with the sound")
end)

test("tranq: a failed cast keeps the callout and says why; nothing to dispel means it wasn't an enrage", function()
	local W, Tranq = Setup()
	Pull(W, "shazzrah")
	W.Buff("shazzrah", DEADEN_MAGIC, { dispelName = "Magic" })
	W.Advance(0.3)
	W.FailTranq(OUT_OF_RANGE, "Out of range.")
	W.Advance(0.1)
	H.Equal(Callout(Tranq), "Tranq Shot!", "still needed")
	H.Equal(Detail(Tranq), "Out of range.", "the game's own words")
	W.Advance(3)
	H.Equal(Inside(Detail(Tranq)), "Deaden Magic", "then the buff again")
	-- The failed cast first, then its message.
	W.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-Tranq", 19801)
	W.Fire("UI_ERROR_MESSAGE", NOTHING_TO_DISPEL, "Nothing to dispel")
	W.Advance(0.3)
	H.Equal(Callout(Tranq), nil, "not something Tranquilizing Shot removes")
	-- Errors from other spells don't count.
	local W2, Tranq2 = Setup()
	Pull(W2, "shazzrah")
	W2.Buff("shazzrah", DEADEN_MAGIC, { dispelName = "Magic" })
	W2.Advance(0.3)
	W2.Fire("UI_ERROR_MESSAGE", NOTHING_TO_DISPEL, "Nothing to dispel")
	W2.Advance(1)
	W2.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-Tranq", 19801)
	W2.Advance(0.3)
	H.Equal(Callout(Tranq2), "Tranq Shot!", "an old message isn't this cast's")
end)

test("tranq: a Feign Death doesn't end the fight; leaving combat for good does", function()
	local W, Tranq = Setup()
	Pull(W, "magmadar")
	W.Buff("magmadar", FRENZY)
	W.Advance(0.3)
	H.Equal(Callout(Tranq), "Tranq Shot!", "callout")
	W.inCombat = false -- Feign Death
	W.Fire("PLAYER_REGEN_ENABLED")
	W.Advance(1)
	H.Equal(Callout(Tranq), nil, "out of combat for a moment")
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Advance(0.3)
	H.Equal(Callout(Tranq), "Tranq Shot!", "back, read as an enrage while you were out of combat")
	EndFight(W)
	H.Equal(Callout(Tranq), nil, "after the fight")
end)

---------------------------------------------------------------------------
-- Announcements
---------------------------------------------------------------------------
local function ShootAndResolve(W, key, hit)
	local id = W.Buff(key, FRENZY)
	W.Advance(0.3)
	W.CastTranq()
	W.Advance(0.5)
	if hit then
		W.Unbuff(key, id)
		W.Advance(0.3)
	else
		W.Advance(2)
		W.Unbuff(key, id)
		W.Advance(0.3)
	end
end

test("tranq: announcements go to party or raid chat only when you turn them on", function()
	local W, Tranq = Setup()
	W.group = "raid"
	Pull(W, "magmadar")
	ShootAndResolve(W, "magmadar", true)
	H.Equal(#W.chat, 0, "off by default")
	H.False(Tranq.db.announce, "off by default")

	W.Slash("tranq announce on")
	ShootAndResolve(W, "magmadar", true)
	H.Equal(#W.chat, 1, "one message")
	H.Equal(W.chat[1].text, "My Tranquilizing Shot removed the enrage.", "a hit")
	H.Equal(W.chat[1].channel, "RAID", "to the raid")
	W.Advance(3)
	ShootAndResolve(W, "magmadar", false)
	H.Equal(W.chat[2].text, "My Tranquilizing Shot missed or was resisted. Next hunter, go!", "a miss")

	W.group = "party"
	W.Advance(3)
	ShootAndResolve(W, "magmadar", true)
	H.Equal(W.chat[3].channel, "PARTY", "to the party")
	W.group = nil
	W.Advance(3)
	ShootAndResolve(W, "magmadar", true)
	H.Equal(#W.chat, 3, "nothing when you're on your own")
end)

test("tranq: nothing is sent while the game locks addon chat, and it says so once", function()
	local W, Tranq = Setup()
	W.group = "raid"
	W.chatLockdown = true
	W.Slash("tranq announce on")
	Pull(W, "magmadar")
	ShootAndResolve(W, "magmadar", true)
	H.Equal(#W.chat, 0, "not sent")
	H.Equal(#W.blocked, 0, "not even tried: " .. table.concat(W.blocked, ", "))
	H.True(W.Printed("Not announced: the game doesn't let addons send chat messages right now."), "explained")
	local printed = #W.printed
	ShootAndResolve(W, "magmadar", false)
	H.Equal(#W.chat, 0, "still not sent")
	H.Equal(#W.printed, printed, "said only once a fight")
	H.Equal(Callout(Tranq), "Still enraged!", "the callout itself still works")
	-- Once the game allows chat again, announcements go out.
	EndFight(W)
	W.chatLockdown = false
	Pull(W, "magmadar")
	ShootAndResolve(W, "magmadar", true)
	H.Equal(#W.chat, 1, "sent")
end)

---------------------------------------------------------------------------
-- Display and options
---------------------------------------------------------------------------
test("tranq: a preview while the options are open or frames are unlocked, and it can be moved", function()
	local W, Tranq = Setup()
	H.False(Tranq.frame:IsShown(), "hidden at first")
	W.Slash("")
	H.Equal(Callout(Tranq), "Tranq Shot!", "sample in the options preview")
	H.Equal(Detail(Tranq), "Frenzy", "with a sample buff")
	H.Equal(Tranq.frame.icon.texture, 136224, "and its icon")
	local _, bottom = Tranq.frame:GetRect()
	local _, windowBottom, _, windowHeight = W.ns.OptionsWindow.frame:GetRect()
	H.True(bottom > windowBottom + windowHeight, "above the options window, so the preview shows")
	W.Slash("")
	H.False(Tranq.frame:IsShown(), "hidden when the window closes")
	W.Slash("move")
	H.Equal(Callout(Tranq), "Tranq Shot!", "shown to be dragged")
	H.True(Tranq.frame.mover:IsShown(), "blue overlay")
	W.dropPoint = { "CENTER", "CENTER", -200, 300 }
	Tranq.frame.scripts.OnDragStop(Tranq.frame)
	H.Equal(Tranq.db.position.x, -200, "position saved")
	H.Equal(Tranq.db.position.y, 300, "position saved")
	W.Slash("move")
	H.False(Tranq.frame:IsShown(), "hidden when locked again")
	W.Slash("tranq off")
	W.Slash("move")
	H.False(Tranq.frame:IsShown(), "turned off: no preview either")
end)

test("tranq: one options page, in two columns, and every setting from chat", function()
	local W, Tranq = Setup()
	local sections = Tranq:GetOptionSections()
	H.Equal(#sections, 1, "one page")
	H.Equal(sections[1].name, "Tranq Shot", "named Tranq Shot")
	W.Slash("")
	local window = W.ns.OptionsWindow
	local found
	for index, section in ipairs(window.sections) do
		if section.module == Tranq then
			found = true
			window:SelectSection(index)
			for _, widget in ipairs(window.pages[index].controls) do
				local _, _, _, x, y = widget:GetPoint(1)
				local label = tostring(widget.spec.label or widget.spec.text)
				H.True(x < 300, "'" .. label .. "' is in a third column")
				H.True(-y + widget.height <= 408, "'" .. label .. "' runs past the bottom")
			end
		end
	end
	H.True(found, "the page is in the window")
	W.Slash("")

	W.Slash("tranq fontsize 48")
	H.Equal(Tranq.frame.text.font[2], 48, "font size")
	W.Slash("tranq text TRANQ NOW")
	W.Slash("tranq sound alarm")
	Pull(W, "magmadar")
	local sounds = #W.sounds
	W.Buff("magmadar", FRENZY)
	W.Advance(0.3)
	H.Equal(Callout(Tranq), "TRANQ NOW", "your own wording")
	H.Equal(W.sounds[sounds + 1].id, 12889, "your sound")
	W.Slash("tranq playsound")
	H.Equal(#W.sounds, sounds + 2, "the sound plays from chat")
	W.Slash("tranq off")
	H.Equal(Callout(Tranq), nil, "turned off")
	W.Slash("settings tranq")
	H.True(W.Printed("Tranq Shot callout settings"), "listed")
end)

test("tranq: its page fits in every language", function()
	for _, locale in ipairs({ "deDE", "esES", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
		local W, Tranq = Setup({ locale = locale })
		W.Slash("")
		local window = W.ns.OptionsWindow
		for index, section in ipairs(window.sections) do
			if section.module == Tranq then
				window:SelectSection(index)
				for _, widget in ipairs(window.pages[index].controls) do
					local _, _, _, x, y = widget:GetPoint(1)
					local label = locale .. ": '" .. tostring(widget.spec.label or widget.spec.text) .. "'"
					H.True(x < 300, label .. " is in a third column")
					H.True(-y + widget.height <= 408, label .. " runs past the bottom")
				end
			end
		end
	end
end)

return tests
