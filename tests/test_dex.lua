-- Pet abilities: the beasts you find with Beast Lore, taming and rare sightings,
-- the dex window and the map (Modules\Dex.lua).
local H, ROOT = ...

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

local function Setup(options)
	local W = H.NewWorld(options)
	H.LoadAddon(W, ROOT)
	return W, W.ns.modules.Dex
end

local function Beasts(W)
	return W.env.DeadeyeDB.dex.beasts
end

local BEAR = { id = 822, name = "Young Forest Bear", level = 8, family = "Bear", lines = { "Level 8 Beast (Bear)" },
	lore = { "Abilities: Claw 2, Bite (Rank 1)" } }

local function Copy(beast, changes)
	local copy = {}
	for key, value in pairs(beast) do
		copy[key] = value
	end
	for key, value in pairs(changes or {}) do
		copy[key] = value
	end
	return copy
end

local function Target(W, beast)
	W.units.target = beast
	W.hasTarget = beast ~= nil
	W.Fire("PLAYER_TARGET_CHANGED")
end

-- A pet trainer's window, listing Growl.
local function PetTrainer(W)
	W.trainerServices = { { "Growl", "Rank 3" }, { "Growl", "Rank 4", "unavailable" } }
	W.Fire("TRAINER_SHOW")
end

local function Lore(W)
	W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 1462)
	W.Advance(2)
end

local function Pet(changes)
	local pet = { name = "Grrl", level = 20, health = 800, healthMax = 1000, happiness = 3, damage = 125,
		loyaltyRate = 1, loyalty = "Loyalty Level 3", diet = { "Meat" }, family = "Cat",
		spells = { { "Claw", "Rank 2" }, { "Bite", "Rank 3" }, { "Growl", "Rank 2" } } }
	for key, value in pairs(changes or {}) do
		pet[key] = value
	end
	return pet
end

-- The window's rows, scrolled to the first entry that matches.
local function Row(Dex, match)
	for index, entry in ipairs(Dex.entries) do
		if match(entry) then
			Dex.offset = index - 1
			Dex:DrawRows()
			return Dex.rows[1]
		end
	end
end

local function RankRow(Dex, ability, rank)
	return Row(Dex, function(entry)
		return entry.kind == "rank" and entry.ability == ability and entry.rank == rank
	end)
end

local function BeastRow(Dex, name)
	return Row(Dex, function(entry)
		return entry.kind == "beast" and entry.beast.name == name
	end)
end

test("dex: Beast Lore saves what a beast teaches and where you found it", function()
	local W = Setup()
	Target(W, Copy(BEAR, { loreAt = W.now + 0.4 })) -- the game fills the tooltip in a moment later
	Lore(W)
	H.True(W.Printed("Saved Young Forest Bear: teaches Bite 1, Claw 2."), "told what it teaches")
	local bear = Beasts(W)[822]
	H.True(bear ~= nil, "saved by its NPC ID")
	H.Equal(bear.abilities.Claw, 2, "Claw 2")
	H.Equal(bear.abilities.Bite, 1, "Bite 1 from \"Bite (Rank 1)\"")
	H.Equal(bear.family, "Bear", "its family")
	H.Equal(bear.minLevel, 8, "its level")
	H.Equal(#bear.spots, 1, "one spot")
	H.Equal(bear.spots[1].map, 1429, "on your map")
	H.Equal(bear.spots[1].x, 0.5, "where you stood")
	H.Equal(bear.zone, "Elwynn Forest", "the zone")
	-- Again from nearly the same place, then elsewhere, at another level.
	W.printed = {}
	W.position = { 0.51, 0.61 }
	Target(W, Copy(BEAR, { level = 9 }))
	Lore(W)
	H.Equal(#bear.spots, 1, "nearly the same spot isn't saved twice")
	H.False(W.Printed("Saved"), "nothing new to say")
	W.position = { 0.3, 0.2 }
	Lore(W)
	H.Equal(#bear.spots, 2, "a second spot")
	H.Equal(bear.maxLevel, 9, "its level range")
end)

test("dex: Beast Lore is known by its name too, in case Forever numbers it differently", function()
	local W = Setup()
	W.spellNames[999462] = "Beast Lore"
	Target(W, Copy(BEAR))
	W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-9", 999462)
	W.Advance(2)
	H.True(Beasts(W)[822] ~= nil, "saved")
	-- Pins for every beast show on a map you open yourself.
	W.Slash("dex allpins on")
	W.env.ShowUIPanel(W.env.WorldMapFrame)
	W.env.WorldMapFrame:SetMapID(1429)
	H.True(W.ns.modules.Dex.pins[1]:IsShown(), "a pin, without clicking a beast first")
end)

test("dex: a beast's name isn't read as an ability, and unread lore says how to report it", function()
	local W = Setup()
	Target(W, { id = 1196, name = "Ice Claw Bear", level = 7, family = "Bear", lines = { "Level 7 Beast" },
		lore = { "Resists Frostbite 4" } })
	Lore(W)
	local bear = Beasts(W)[1196]
	H.True(bear ~= nil, "saved where you found it")
	H.Equal(next(bear.abilities), nil, "no Claw from its name, nor Bite from \"Frostbite\"")
	H.True(W.Printed("/deadeye dex lore"), "how to report what Beast Lore shows")
	W.printed = {}
	W.Slash("dex lore")
	H.True(W.Printed("2: Level 7 Beast"), "the diagnostic prints the tooltip's lines")
	H.True(W.Printed("3: Resists Frostbite 4"), "every line")
	Target(W, { id = 4000, name = "Shell Shield Snapjaw", level = 20, family = "Turtle", lore = { "Abilities: Bite 3" } })
	Lore(W)
	H.Equal(Beasts(W)[4000].abilities["Shell Shield"], nil, "a one-rank ability's name in the beast's name isn't one")
	H.True(W.Printed("No abilities read."), "and what it read")
	-- Players and their pets aren't beasts to save.
	Target(W, { id = 0, name = "Otherhunter's Cat", level = 30, family = "Cat", player = true, lore = { "Claw 5" } })
	Lore(W)
	H.Equal(Beasts(W)[0], nil, "a player's pet isn't saved")
end)

test("dex: taming reads the ranks your new pet brought along", function()
	local W = Setup()
	local boar = { id = 1125, name = "Elder Mottled Boar", level = 9, family = "Boar", lines = {} }
	PetTrainer(W)
	Target(W, boar)
	W.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-2", 1515)
	W.Advance(20)
	Target(W, nil)
	W.pet = Pet({ name = "Elder Mottled Boar", family = "Boar", level = 9, spells = {
		{ "Charge", "Rank 2" }, { "Bite", "Rank 1" }, { "Growl", "Rank 1" }, { "Shell Shield", "" } } })
	W.Fire("UNIT_PET", "player")
	local saved = Beasts(W)[1125]
	H.True(saved ~= nil, "the tamed beast is saved")
	H.Equal(saved.abilities.Charge, 2, "Charge 2")
	H.Equal(saved.abilities.Growl, nil, "pet trainers sell Growl: the boar came with it, it doesn't teach it")
	H.Equal(saved.abilities["Shell Shield"], 1, "a one-rank ability without a rank text")
	H.True(W.Printed("Saved Elder Mottled Boar: teaches"), "told")
	-- Calling another pet while taming isn't taken for the tamed beast.
	local W2 = Setup()
	Target(W2, boar)
	W2.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", "Cast-2", 1515)
	W2.pet = Pet()
	W2.Fire("UNIT_PET", "player")
	H.Equal(Beasts(W2)[1125], nil, "your old pet's spells aren't the boar's")
end)

test("dex: rare beasts are saved where you see them", function()
	local W, Dex = Setup()
	W.units.mouseover = { id = 1130, name = "Bjarn", level = 12, family = "Bear", classification = "rare" }
	W.Fire("UPDATE_MOUSEOVER_UNIT")
	local bjarn = Beasts(W)[1130]
	H.True(bjarn ~= nil and bjarn.rare, "saved as rare")
	H.True(W.Printed("Rare beast saved: Bjarn (Bear)."), "told")
	H.Equal(bjarn.spots[1].x, 0.5, "where you saw it")
	W.units.nameplate1 = { id = 2, name = "Young Wolf", level = 3, family = "Wolf" }
	W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
	H.Equal(Beasts(W)[2], nil, "an ordinary beast isn't saved by sight")
	W.units.nameplate2 = { id = 3, name = "Rare Kobold", level = 10, classification = "rare" }
	W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
	H.Equal(Beasts(W)[3], nil, "nor a rare that isn't a beast you could tame")
	W.Slash("dex rares off")
	W.units.nameplate3 = { id = 4, name = "Mazzranache", level = 26, family = "Cat", classification = "rare" }
	W.Fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
	H.Equal(Beasts(W)[4], nil, "with the setting off")
	-- Settings reset leaves your finds alone.
	W.ns:ResetSettings()
	H.True(Beasts(W)[1130] ~= nil, "a settings reset keeps the beasts")
	H.True(Dex.db.rares, "and resets the setting")
end)

test("dex: the window shows your pet's ranks, what you know and what you've found", function()
	local W, Dex = Setup()
	Target(W, { id = 2959, name = "Prairie Stalker", level = 16, family = "Cat", lore = { "Claw 3, Dash 1" } })
	Lore(W)
	W.pet = Pet()
	W.Fire("UNIT_PET", "player")
	W.craft = { { "Bite", "Rank 1" }, { "Bite", "Rank 2" }, { "Claw", "Rank 1" }, { "Cower", "Rank 1" } }
	W.Fire("CRAFT_SHOW")
	-- A class trainer's spells aren't pet abilities, even with a pet ability's name.
	W.trainerServices, W.trainerLine = { { "Dash", "Rank 1" } }, "Marksmanship"
	W.Fire("TRAINER_SHOW")
	W.trainerLine = nil
	PetTrainer(W)
	W.Slash("dex")
	H.True(Dex.frame:IsShown(), "/deadeye dex opens it")
	H.Equal(Dex.view, "pet", "on your pet's page")
	H.Equal(Dex.heading.text, "Grrl: Cat, level 20", "your pet")
	H.Equal(Dex.progressText.text, "13 of 155 ranks found", "found: Bite 1-2, Claw 1, Cower 1 learned; Claw 3, Dash 1 seen; Growl 1-7 sold")
	local row = RankRow(Dex, "Claw", 2)
	H.Equal(row.right.text, "Your pet has it", "Claw 2")
	row = RankRow(Dex, "Claw", 3)
	H.Equal(row.right.text, "1 found", "Claw 3")
	H.Equal(row.middle.text, "pet level 16  \194\183  7 TP", "its pet level and cost")
	row = RankRow(Dex, "Cower", 1)
	H.Equal(row.right.text, "Learned", "learned in Beast Training")
	row = RankRow(Dex, "Dash", 1)
	H.Equal(row.right.text, "1 found", "Dash 1")
	H.SameColor(row.middle.textColor, { 1, 0.35, 0.35 }, "pet level 30: your pet is too low")
	row = RankRow(Dex, "Prowl", 2)
	H.Equal(row.right.text, "Not found yet", "Prowl 2")
	row = RankRow(Dex, "Growl", 3)
	H.Equal(row.right.text, "Pet trainer", "trainer abilities")
	H.Equal(RankRow(Dex, "Swipe", 1), nil, "bears' Swipe isn't on a cat's page")
	row = BeastRow(Dex, "Prairie Stalker")
	H.Equal(row.left.text, "      Prairie Stalker  16", "the beast under its ranks")
	H.Equal(row.right.text, "Elwynn Forest", "and where")
	-- Every ability, scrolling, and the rares page.
	W.Click(Dex.tabs[2])
	H.Equal(Dex.view, "all", "all abilities")
	H.True(RankRow(Dex, "Swipe", 5) ~= nil, "Swipe is there")
	Dex.offset = 0
	Dex:Scroll(3)
	H.Equal(Dex.offset, 3, "the wheel scrolls")
	H.True(Dex.moreText.text:find("more below", 1, true) ~= nil, "says there's more")
	Dex:Scroll(1000)
	H.Equal(Dex.offset, #Dex.entries - 18, "not past the end")
	H.Equal(Dex.moreText.text, "", "nothing more below")
	W.Click(Dex.tabs[3])
	H.Equal(Dex.rows[1].left.text, "No rare beasts yet. Target or mouse over one and Deadeye saves where you saw it.", "no rares yet")
	W.units.mouseover = { id = 1130, name = "Bjarn", level = 12, family = "Bear", classification = "rare" }
	W.Fire("UPDATE_MOUSEOVER_UNIT")
	H.Equal(Dex.rows[1].left.text, "      Bjarn  12  (rare)", "a rare beast, as soon as it's seen")
	H.Equal(Dex.rows[1].right.text, "Elwynn Forest  \194\183  1 min ago", "where and when")
	-- Without a pet, your pet's page shows everything.
	W.pet = nil
	W.Fire("UNIT_PET", "player")
	W.Click(Dex.tabs[1])
	H.Equal(Dex.rows[1].left.text, "No pet out: showing every ability.", "says so")
	W.Slash("dex")
	H.False(Dex.frame:IsShown(), "/deadeye dex closes it")
end)

test("dex: clicking a beast shows it on the map", function()
	local W, Dex = Setup()
	Target(W, Copy(BEAR))
	Lore(W)
	W.mapID, W.position = 1426, { 0.4, 0.4 } -- you're in Dun Morogh now
	W.Slash("dex")
	W.Click(Dex.tabs[2])
	local row = BeastRow(Dex, "Young Forest Bear")
	W.Click(row)
	local map = W.env.WorldMapFrame
	H.True(map:IsShown(), "the map opens")
	H.Equal(map.mapID, 1429, "on Elwynn Forest")
	H.Equal(W.userWaypoint.uiMapID, 1429, "with the game's map pin")
	H.Near(W.userWaypoint.position.x, 0.5, 1e-9, "where the bear was")
	H.True(W.superTracked, "tracked")
	local pin = Dex.pins[1]
	H.True(pin:IsShown(), "a pin on the canvas")
	local _, _, _, x, y = pin:GetPoint(1)
	H.Near(x, 0.5 * 1002, 1e-6, "pin x")
	H.Near(y, -0.6 * 668, 1e-6, "pin y")
	-- Zoomed in, pins keep their size.
	W.mapZoom = 2
	map:OnCanvasScaleChanged()
	H.Near(pin:GetScale(), 0.5, 1e-9, "scaled against the zoom")
	_, _, _, x = pin:GetPoint(1)
	H.Near(x, 0.5 * 1002 * 2, 1e-6, "same place on the canvas")
	-- Another map: no pin there.
	map:SetMapID(1411)
	H.False(pin:IsShown(), "no pin on Durotar")
	-- TomTom, when it's installed.
	local waypoints = {}
	rawset(W.env, "TomTom", { AddWaypoint = function(_, mapID, x2, y2, opts)
		waypoints[#waypoints + 1] = { mapID, x2, y2, opts.title }
	end })
	W.userWaypoint = nil
	W.Click(row)
	H.Equal(#waypoints, 1, "a TomTom arrow")
	H.Equal(waypoints[1][4], "Young Forest Bear", "named")
	H.Equal(W.userWaypoint, nil, "instead of the game's pin")
	W.Slash("dex tomtom off")
	W.Click(row)
	H.Equal(#waypoints, 1, "not with the setting off")
	-- In combat the map isn't opened for you.
	map:Hide()
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Click(row)
	H.False(map:IsShown(), "the map stays closed")
	H.True(W.Printed("can't open it for you in combat"), "says so")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	-- Pins for every beast you've found.
	Target(W, { id = 99, name = "Elmpaw", level = 12, family = "Bear", lore = { "Claw 2" } })
	W.mapID, W.position = 1429, { 0.2, 0.8 }
	Lore(W)
	W.Click(row)
	H.True(Dex.pins[1]:IsShown() and not (Dex.pins[2] and Dex.pins[2]:IsShown()), "only the clicked beast")
	W.Slash("dex allpins on")
	H.True(Dex.pins[1]:IsShown() and Dex.pins[2]:IsShown(), "every beast on this map")
	-- A beast found in a dungeon, with no position.
	W.position = nil
	Target(W, { id = 3653, name = "Kresh", level = 20, family = "Turtle", classification = "elite",
		lore = { "Abilities: Shell Shield, Bite 3" } })
	Lore(W)
	H.Equal(Beasts(W)[3653].abilities["Shell Shield"], 1, "a one-rank ability listed without its rank")
	H.Equal(Beasts(W)[3653].abilities.Bite, 3, "Bite 3")
	W.Click(Dex.tabs[2])
	W.Click(BeastRow(Dex, "Kresh"))
	H.True(W.Printed("No map position saved for Kresh (found in Elwynn Forest)."), "says where it was found")
end)

test("dex: your pet's level-ups name the ranks it can learn", function()
	local W = Setup()
	Target(W, { id = 2959, name = "Prairie Stalker", level = 16, family = "Cat", lore = { "Claw 3" } })
	Lore(W)
	W.pet = Pet({ level = 15 })
	W.Fire("UNIT_PET", "player")
	W.printed = {}
	W.pet.level = 16
	W.Fire("UNIT_LEVEL", "pet")
	H.True(W.Printed("Grrl can learn Claw 3 now. 1 of the beasts you've found teach it (/deadeye dex)."), "Claw 3, found")
	H.False(W.Printed("Bite 3"), "Bite 3: your pet has it")
	W.printed = {}
	W.pet.level = 24
	W.Fire("UNIT_LEVEL", "pet")
	H.True(W.Printed("Grrl can learn Bite 4 now. You haven't found where to learn it yet."), "Bite 4, not found")
	H.True(W.Printed("Grrl can learn Claw 4 now."), "Claw 4")
	H.True(W.Printed("Grrl can learn Natural Armor 4 now. You haven't found where to learn it yet."), "an ability no trainer was seen selling")
	PetTrainer(W)
	W.printed = {}
	W.pet.level = 30
	W.Fire("UNIT_LEVEL", "pet")
	H.True(W.Printed("Grrl can learn Growl 4 now. Pet trainers sell it."), "one a pet trainer was seen selling")
	W.Slash("dex upgrades off")
	W.printed = {}
	W.pet.level = 32
	W.Fire("UNIT_LEVEL", "pet")
	H.Equal(#W.printed, 0, "quiet with the setting off")
end)

test("dex: the Beast Lore key casts on your mouseover target", function()
	local W, Dex = Setup()
	local key = W.env.DeadeyeBeastLore
	H.True(key ~= nil, "a button for the key binding")
	W.Key(key)
	H.Equal(W.macros[#W.macros], "/cast [@mouseover,exists,nodead][] Beast Lore", "Beast Lore on the mouseover, or the target")
	H.Equal(Dex.loreKey, key, "kept")
	-- Loaded in combat: made after the fight.
	local W2 = H.NewWorld()
	W2.inCombat = true
	H.LoadAddon(W2, ROOT)
	H.Equal(rawget(W2.env, "DeadeyeBeastLore"), nil, "not in combat")
	W2.inCombat = false
	W2.Fire("PLAYER_REGEN_ENABLED")
	H.True(rawget(W2.env, "DeadeyeBeastLore") ~= nil, "after it")
end)

test("dex: forgetting every beast asks twice", function()
	local W, Dex = Setup()
	Target(W, Copy(BEAR))
	Lore(W)
	W.Slash("dex forget")
	H.True(Beasts(W)[822] ~= nil, "not yet")
	H.True(W.Printed("Click again within 3 seconds"), "asks")
	W.Advance(4)
	W.Slash("dex forget")
	H.True(Beasts(W)[822] ~= nil, "too slow: asks again")
	W.Advance(1)
	W.Slash("dex forget")
	H.Equal(next(Beasts(W)), nil, "forgotten")
	H.True(Dex.db.record, "settings untouched")
	-- Saving off: nothing's saved.
	W.Slash("dex record off")
	Target(W, Copy(BEAR))
	Lore(W)
	H.Equal(next(Beasts(W)), nil, "with saving off")
end)

test("dex: in other languages, the game's names are matched", function()
	-- The names come from the game as the addon starts.
	local W = H.NewWorld({ locale = "deDE" })
	W.spellNames[16827] = "Klaue"
	W.spellNames[17253] = "Beißen"
	W.familyNames[4] = "Bär"
	W.familyNames[2] = "Katze"
	H.LoadAddon(W, ROOT)
	local Dex = W.ns.modules.Dex
	Target(W, { id = 822, name = "Junger Waldbär", level = 8, family = "Bär", lore = { "Fähigkeiten: Klaue 2, Beißen 1" } })
	Lore(W)
	local bear = Beasts(W)[822]
	H.Equal(bear.abilities.Claw, 2, "Klaue is Claw")
	H.Equal(bear.abilities.Bite, 1, "Beißen is Bite")
	H.Equal(bear.family, "Bear", "Bär is Bear")
	W.pet = Pet({ family = "Katze", spells = { { "Klaue", "Rang 2" } } })
	W.Fire("UNIT_PET", "player")
	H.Equal(Dex.petAbilities.Claw, 2, "the pet's Klaue, Rang 2")
	W.Slash("dex")
	H.True(RankRow(Dex, "Claw", 2) ~= nil, "a cat's page has Claw")
	H.Equal(Row(Dex, function(entry)
		return entry.kind == "ability" and entry.ability == "Claw"
	end).left.text, "Klaue", "in German")
end)

return tests
