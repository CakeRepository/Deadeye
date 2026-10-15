-- The ammo counter, its warnings and forecast, and restocking at vendors.
local H, ROOT = ...

local tests = {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

local BOW, GUN, CROSSBOW, THROWN = 2504, 2508, 15807, 2947
local ROUGH, SHARP, RAZOR, LIGHT_SHOT, HEAVY_SHOT = 2512, 2515, 3030, 2516, 2519
local SMALL_QUIVER = 5439
local JERKY, HAUNCH = 117, 2287 -- pet food: levels 5 and 15

-- A level 20 hunter with a bow, Rough Arrows in the ammo slot, a backpack and
-- (unless options.quiver is false) a 6-slot quiver holding `arrows` of them.
-- Restocking by itself is off unless options.auto.
local function Setup(options)
	options = options or {}
	local W = H.NewWorld(options)
	W.bags[0] = { size = 16 }
	if options.quiver ~= false then
		W.bags[1] = { size = 6, family = 1 }
	end
	W.equipped[18] = options.weapon or BOW
	W.equipped[0] = options.ammo == nil and ROUGH or options.ammo or nil
	local arrows = options.arrows or 600
	if arrows > 0 then
		W.AddItem(options.ammo or ROUGH, arrows)
	end
	H.LoadAddon(W, ROOT)
	if not options.auto then
		W.Slash("ammo autobuy off")
	end
	W.printed = {}
	return W, W.ns.modules.Ammo
end

local function CountText(Ammo)
	return Ammo.frame:IsShown() and tostring(Ammo.frame.count.text) or nil
end

local function Shoot(W, count)
	W.UseItem(W.equipped[0], count)
end

local function Tooltip(W, frame)
	frame.scripts.OnEnter(frame)
	return table.concat(W.env.GameTooltip.lines, "\n")
end

-- Sells Rough Arrows and Light Shot (and something that isn't in the item data).
local VENDOR = {
	{ itemID = 2101, price = 100, batch = 1 },
	{ itemID = ROUGH, price = 10 },
	{ itemID = LIGHT_SHOT, price = 10 },
}
-- Sells Sharp Arrows too.
local BETTER = {
	{ itemID = ROUGH, price = 10 },
	{ itemID = SHARP, price = 50 },
}

---------------------------------------------------------------------------
-- The counter
---------------------------------------------------------------------------
test("ammo: the counter shows your ammo beside the Auto Shot bar", function()
	local W, Ammo = Setup()
	local AS = W.ns.modules.AutoShot
	H.Equal(CountText(Ammo), "600", "count of the ammo in the ammo slot")
	H.Equal(Ammo.frame.icon.texture, 132382, "its icon")
	local point, relativeTo, relativePoint, x = Ammo.frame:GetPoint(1)
	H.Equal(point, "LEFT", "anchored by its left")
	H.Equal(relativeTo, AS.bar, "to the Auto Shot bar")
	H.Equal(relativePoint, "RIGHT", "on its right")
	H.Equal(x, AS.db.borderSize + 4, "just past the border")
	H.SameColor(Ammo.frame.count.textColor, { 1, 1, 1 }, "plenty: white")
	-- An Auto Shot icon on the right goes between them, as the bar's layout changes.
	W.Slash("icon right")
	_, relativeTo = Ammo.frame:GetPoint(1)
	H.Equal(relativeTo, AS.bar.icon, "next to the bar's icon")
end)

test("ammo: no counter without a weapon that fires ammo", function()
	local W, Ammo = Setup()
	W.equipped[18] = THROWN
	W.Fire("PLAYER_EQUIPMENT_CHANGED", 18, true)
	H.Equal(CountText(Ammo), nil, "thrown weapons don't use the ammo slot")
	W.equipped[18] = nil
	W.Fire("PLAYER_EQUIPMENT_CHANGED", 18, false)
	H.Equal(CountText(Ammo), nil, "no ranged weapon")
	W.equipped[18] = CROSSBOW
	W.Fire("PLAYER_EQUIPMENT_CHANGED", 18, true)
	H.Equal(CountText(Ammo), "600", "crossbows fire arrows")
end)

test("ammo: warns once as you drop below the low mark, and when you run out", function()
	local W, Ammo = Setup({ arrows = 400 })
	Shoot(W, 150)
	H.Equal(CountText(Ammo), "250", "counts down as you shoot")
	H.Equal(#W.sounds, 0, "no warning yet")
	Shoot(W, 100)
	H.True(W.Printed("Running low on ammo: 150 left."), "warned at the low mark")
	H.Equal(#W.sounds, 1, "with a sound")
	H.SameColor(Ammo.frame.count.textColor, { 1, 0.82, 0 }, "low: yellow")
	Shoot(W, 50)
	H.Equal(#W.sounds, 1, "only once")
	Shoot(W, 100)
	H.True(W.Printed("You're out of ammo."), "warned when it ran out")
	H.Equal(CountText(Ammo), "0", "none left")
	H.SameColor(Ammo.frame.count.textColor, { 1, 0.25, 0.25 }, "empty: red")
	H.True(Ammo.frame.icon.desaturated, "gray icon")
	-- Buying more and dropping again warns again.
	W.AddItem(ROUGH, 400)
	W.Fire("BAG_UPDATE_DELAYED")
	H.Equal(#W.sounds, 2, "nothing new while it goes up")
	Shoot(W, 250)
	H.Equal(#W.sounds, 3, "warned again on the way down")
	W.Slash("ammo lowalert off")
	Shoot(W, 150)
	H.Equal(#W.sounds, 3, "warnings can be turned off")
end)

test("ammo: a fight that starts short of ammo, or with an empty ammo slot, gets a warning", function()
	local W = Setup({ arrows = 120 })
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	H.True(W.Printed("Running low on ammo: 120 left."), "low at the pull")
	local W2 = Setup({ ammo = false, arrows = 0 })
	W2.inCombat = true
	W2.Fire("PLAYER_REGEN_DISABLED")
	H.True(W2.Printed("Your ammo slot is empty."), "nothing to shoot")
	H.Equal(CountText(W2.ns.modules.Ammo), "0", "shown as none")
	local W3 = Setup({ arrows = 1000 })
	W3.inCombat = true
	W3.Fire("PLAYER_REGEN_DISABLED")
	H.Equal(#W3.sounds, 0, "plenty: no warning")
end)

test("ammo: can show only while you're running low, or not at all", function()
	local W, Ammo = Setup({ arrows = 600 })
	W.Slash("ammo show low")
	H.Equal(CountText(Ammo), nil, "hidden with plenty")
	Shoot(W, 450)
	H.Equal(CountText(Ammo), "150", "shown when low")
	W.Slash("ammo off")
	H.Equal(CountText(Ammo), nil, "turned off")
	W.Slash("move")
	H.Equal(CountText(Ammo), nil, "stays off while frames are unlocked")
end)

test("ammo: shown to be dragged while unlocked, even without a bow", function()
	local W, Ammo = Setup()
	W.equipped[18] = nil
	W.Fire("PLAYER_EQUIPMENT_CHANGED", 18, false)
	H.Equal(CountText(Ammo), nil, "hidden without a bow")
	W.Slash("move")
	H.Equal(CountText(Ammo), "1400", "sample while unlocked")
	H.True(Ammo.frame.mover:IsShown(), "blue overlay")
	W.dropPoint = { "CENTER", "CENTER", 300, -200 }
	Ammo.frame.scripts.OnDragStop(Ammo.frame)
	H.Equal(Ammo.db.attach, "FREE", "detached by dragging")
	local _, relativeTo, _, x, y = Ammo.frame:GetPoint(1)
	H.Equal(relativeTo, W.env.UIParent, "anchored to the screen")
	H.Equal(x, 300, "where it was dropped")
	H.Equal(y, -200, "where it was dropped")
	W.Slash("ammo attach bar")
	_, relativeTo = Ammo.frame:GetPoint(1)
	H.Equal(relativeTo, W.ns.modules.AutoShot.bar, "back beside the bar")
end)

test("ammo: a count the game keeps secret is shown, never compared", function()
	local W, Ammo = Setup({ arrows = 400 })
	W.ammoCountSecret = true
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	Shoot(W, 300)
	H.True(Ammo.frame:IsShown(), "still shown")
	H.True(W.ns.IsSecret(Ammo.frame.count.text), "the secret count goes to the text as it is")
	H.Equal(#W.sounds, 0, "no warnings from a count it can't read")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	H.Equal(Ammo.db.usage.seconds, 0, "nothing learned from a fight it couldn't count")
end)

test("ammo: forecasts the minutes of fighting your ammo lasts", function()
	local W, Ammo = Setup({ arrows = 1200 })
	H.False(Tooltip(W, Ammo.frame):find("minutes", 1, true), "no forecast before any fighting")
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Advance(61)
	Shoot(W, 120)
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	H.Equal(Ammo.db.usage.used, 120, "the fight's ammo")
	H.True(Tooltip(W, Ammo.frame):find("Enough for about 9 minutes of fighting.", 1, true), "1080 left at about 2 a second")
	-- Buying mid-fight (or swapping ammo) isn't counted as shooting.
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	W.Advance(30)
	W.AddItem(ROUGH, 120)
	W.Fire("BAG_UPDATE_DELAYED")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	H.Equal(Ammo.db.usage.used, 120, "more ammo after a fight doesn't count")
end)

test("ammo: leaving town short of ammo gets a warning", function()
	local W = Setup({ arrows = 150 })
	W.resting = false
	W.Fire("PLAYER_UPDATE_RESTING")
	H.True(W.Printed("You're heading out with only 150 ammo."), "below the low mark")
	W.resting = true
	W.Fire("PLAYER_UPDATE_RESTING")
	W.resting = false
	W.Fire("PLAYER_UPDATE_RESTING")
	H.Equal(#W.sounds, 1, "once, not at every step in and out")
	-- Plenty of arrows, but few minutes of fighting at the rate you shoot.
	local W2, Ammo2 = Setup({ arrows = 1000 })
	Ammo2.db.usage.seconds, Ammo2.db.usage.used = 600, 6000
	W2.resting = false
	W2.Fire("PLAYER_UPDATE_RESTING")
	H.True(W2.Printed("You're heading out with about 1 minutes of ammo."), "by the forecast")
	local W3 = Setup({ arrows = 1000 })
	W3.resting = false
	W3.Fire("PLAYER_UPDATE_RESTING")
	H.Equal(#W3.sounds, 0, "plenty: nothing to say")
end)

test("ammo: when your ammo runs out, the best other ammo you carry goes in the slot", function()
	local W, Ammo = Setup({ ammo = SHARP, arrows = 200 })
	W.playerLevel = 15
	W.AddItem(ROUGH, 400)
	W.AddItem(RAZOR, 200) -- needs level 20
	W.inCombat = true
	W.Fire("PLAYER_REGEN_DISABLED")
	Shoot(W, 200)
	W.Advance(1)
	H.Equal(W.equipped[0], SHARP, "nothing changes in combat")
	W.inCombat = false
	W.Fire("PLAYER_REGEN_ENABLED")
	W.Advance(1)
	H.Equal(W.equipped[0], ROUGH, "after the fight: the best you can use")
	H.True(W.Printed("Rough Arrow is in your ammo slot now."), "and says so")
	H.Equal(CountText(Ammo), "400", "the counter follows")
	W.Slash("ammo swap off")
	Shoot(W, 400)
	W.Advance(1)
	H.Equal(W.equipped[0], ROUGH, "can be turned off")
end)

---------------------------------------------------------------------------
-- Vendors
---------------------------------------------------------------------------
test("ammo: the vendor button fills your quiver with the ammo in your ammo slot", function()
	local W, Ammo = Setup({ arrows = 120 })
	W.OpenVendor(VENDOR)
	local button = Ammo.vendorButtonFrame
	H.True(button and button:IsShown(), "button on the vendor window")
	H.Equal(button:GetText(), "Fill quiver", "says what it does")
	local _, relativeTo, relativePoint = button:GetPoint(1)
	H.Equal(relativeTo, W.env.MerchantFrame, "on the vendor window")
	H.Equal(relativePoint, "BOTTOMRIGHT", "below it, by the tabs")
	H.True(Tooltip(W, button):find("Buys 1000 Rough Arrow for 50c.", 1, true), "tooltip: 5 empty slots, the part stack can't take a batch")
	W.Click(button)
	W.Advance(3)
	H.Equal(#W.purchases, 5, "one purchase per stack")
	for _, purchase in ipairs(W.purchases) do
		H.Equal(purchase.itemID, ROUGH, "the ammo in the ammo slot")
		H.Equal(purchase.quantity, 200, "a stack at a time")
		H.Equal(purchase.failed, nil, "every purchase went through")
	end
	H.Equal(W.CountItem(ROUGH), 1120, "quiver full")
	H.Equal(W.money, 10000 - 50, "paid")
	H.True(W.Printed("Bought 1000 Rough Arrow for 50c."), "says what it bought")
	H.Equal(button:GetText(), "Fully stocked", "nothing more fits")
	H.True(button:IsEnabled(), "still clickable, so right-click works")
	H.True(Tooltip(W, button):find("Your quiver is full.", 1, true), "and says why")
	W.Click(button, "RightButton")
	H.True(Ammo.db.autoRestock, "right-click turned restocking by itself on")
	H.Equal(CountText(Ammo), "1120", "the counter follows")
	W.CloseVendor()
	H.False(button:IsVisible(), "gone with the vendor window")
end)

test("ammo: switches to better ammo the vendor sells and puts it in your ammo slot", function()
	local W, Ammo = Setup({ arrows = 600 })
	W.OpenVendor(BETTER)
	local button = Ammo.vendorButtonFrame
	H.Equal(button:GetText(), "Upgrade ammo", "says so")
	local tooltip = Tooltip(W, button)
	H.True(tooltip:find("Sharp Arrow does more damage than your Rough Arrow.", 1, true), "says why")
	H.True(tooltip:find("Buys 600 Sharp Arrow for 1s 50c.", 1, true), "the 3 empty quiver slots")
	H.True(tooltip:find("Then puts it in your ammo slot.", 1, true), "and equips it")
	H.True(tooltip:find("Shift-click: buy Rough Arrow instead", 1, true), "the old way is a shift-click away")
	W.Click(button)
	W.Advance(3)
	H.Equal(W.CountItem(SHARP), 600, "bought")
	H.Equal(W.equipped[0], SHARP, "in the ammo slot")
	H.True(W.Printed("Sharp Arrow is in your ammo slot now."), "says so")
	H.Equal(CountText(Ammo), "600", "the counter counts the new ammo")
	W.CloseVendor()

	-- Shift-click, or turning upgrades off, buys your own ammo.
	local W2, Ammo2 = Setup({ arrows = 600 })
	W2.OpenVendor(BETTER)
	W2.shiftDown = true
	W2.Click(Ammo2.vendorButtonFrame)
	W2.Advance(3)
	H.Equal(W2.CountItem(ROUGH), 1200, "Rough Arrows")
	H.Equal(W2.equipped[0], ROUGH, "your ammo stays")
	local W3, Ammo3 = Setup({ arrows = 600 })
	W3.Slash("ammo upgrade off")
	W3.OpenVendor(BETTER)
	H.Equal(Ammo3.vendorButtonFrame:GetText(), "Fill quiver", "no upgrade")
	-- Better ammo you can't use yet isn't offered.
	local W4, Ammo4 = Setup({ arrows = 600 })
	W4.OpenVendor({ { itemID = ROUGH, price = 10 }, { itemID = SHARP, price = 50, usable = false } })
	H.Equal(Ammo4.vendorButtonFrame:GetText(), "Fill quiver", "too high level")
end)

test("ammo: with an empty ammo slot it buys the best ammo for your weapon and equips it", function()
	local W, Ammo = Setup({ ammo = false, arrows = 0 })
	local vendor = {
		{ itemID = LIGHT_SHOT, price = 10 },
		{ itemID = ROUGH, price = 10 },
		{ itemID = SHARP, price = 50 },
		{ itemID = RAZOR, price = 100, usable = false }, -- too high level
	}
	W.OpenVendor(vendor)
	W.Click(Ammo.vendorButtonFrame)
	W.Advance(3)
	H.Equal(W.purchases[1].itemID, SHARP, "the best arrows you can use")
	H.Equal(W.CountItem(SHARP), 1200, "6 empty quiver slots")
	H.Equal(W.equipped[0], SHARP, "in the ammo slot")
	W.CloseVendor()

	local W2, Ammo2 = Setup({ weapon = GUN, ammo = false, arrows = 0, quiver = false })
	W2.bags[1] = { size = 6, family = 2 } -- an ammo pouch
	W2.OpenVendor({ { itemID = ROUGH, price = 10 }, { itemID = LIGHT_SHOT, price = 10 }, { itemID = HEAVY_SHOT, price = 50 } })
	H.Equal(Ammo2.vendorButtonFrame:GetText(), "Fill ammo pouch", "bullets go in an ammo pouch")
	W2.Click(Ammo2.vendorButtonFrame)
	W2.Advance(3)
	H.Equal(W2.purchases[1].itemID, HEAVY_SHOT, "guns get bullets")
	H.Equal(W2.CountItem(HEAVY_SHOT), 1200, "pouch full")
end)

test("ammo: a vendor that only has weaker ammo than yours", function()
	local W, Ammo = Setup({ ammo = SHARP, arrows = 400, auto = true })
	W.OpenVendor({ { itemID = ROUGH, price = 10 } })
	W.Advance(2)
	H.Equal(#W.purchases, 0, "not bought by itself")
	local button = Ammo.vendorButtonFrame
	H.True(Tooltip(W, button):find("Rough Arrow does less damage than your Sharp Arrow.", 1, true), "the button says so")
	W.Click(button)
	W.Advance(3)
	H.Equal(W.CountItem(ROUGH), 800, "bought when you ask: the 4 empty quiver slots")
	H.Equal(W.equipped[0], SHARP, "your better ammo stays in the slot")
end)

test("ammo: without a quiver it buys up to the stacks you set, as bag space allows", function()
	local W, Ammo = Setup({ quiver = false, arrows = 100 })
	W.OpenVendor(VENDOR)
	local button = Ammo.vendorButtonFrame
	H.Equal(button:GetText(), "Buy ammo", "nothing to fill")
	W.Click(button)
	W.Advance(3)
	H.Equal(W.CountItem(ROUGH), 700, "4 stacks wanted: 700 more fit in whole batches of 200 -> 600 bought")
	H.Equal(button:GetText(), "Fully stocked", "less than a batch short")
	W.Slash("ammo stacks 6")
	H.Equal(button:GetText(), "Buy ammo", "a higher setting buys more")
	-- Bags with no room left.
	for slot = 1, 16 do
		W.bags[0][slot] = W.bags[0][slot] or { itemID = 117, count = 1 }
	end
	W.Fire("BAG_UPDATE_DELAYED")
	H.Equal(button:GetText(), "Bags full", "no room")
	H.True(Tooltip(W, button):find("Your bags are full.", 1, true), "says why")
end)

test("ammo: a vendor's quiver gets a tip when you have none", function()
	local W, Ammo = Setup({ quiver = false, arrows = 100 })
	W.OpenVendor({ { itemID = SMALL_QUIVER, price = 100, batch = 1 }, { itemID = ROUGH, price = 10 } })
	H.True(Tooltip(W, Ammo.vendorButtonFrame):find("Small Quiver is for sale here: quivers and ammo pouches make you shoot faster.", 1, true), "tip")
	local W2, Ammo2 = Setup()
	W2.OpenVendor({ { itemID = SMALL_QUIVER, price = 100, batch = 1 }, { itemID = ROUGH, price = 10 } })
	H.False(Tooltip(W2, Ammo2.vendorButtonFrame):find("for sale here", 1, true), "no tip with a quiver")
end)

test("ammo: buys only what you can afford, and says when that's nothing", function()
	local W, Ammo = Setup({ arrows = 0 })
	W.money = 25
	W.OpenVendor(VENDOR)
	W.Click(Ammo.vendorButtonFrame)
	W.Advance(3)
	H.Equal(W.CountItem(ROUGH), 400, "two batches of 10c")
	H.Equal(W.money, 5, "change left")
	H.Equal(Ammo.vendorButtonFrame:GetText(), "Not enough money", "can't afford another")
	Ammo:Fill()
	H.True(W.Printed("Not enough money for Rough Arrow."), "says why")
end)

test("ammo: restocks by itself when a vendor opens, within its spending limit", function()
	local W, Ammo = Setup({ arrows = 200, auto = true })
	local vendor = { { itemID = ROUGH, price = 20 } }
	W.money = 100
	W.OpenVendor(vendor)
	W.Advance(3)
	H.Equal(W.CountItem(ROUGH), 600, "half of 1s buys 2 batches of 20c")
	H.Equal(W.money, 60, "at least half kept")
	H.True(W.Printed("Deadeye restocks your ammo and pet food by itself at vendors."), "the first time, it says how to stop it")
	local bought = #W.purchases
	W.Fire("MERCHANT_SHOW")
	W.Advance(2)
	H.Equal(#W.purchases, bought, "once per visit")
	W.CloseVendor()
	W.printed = {}
	W.money = 10000
	W.OpenVendor(vendor)
	W.Advance(3)
	H.Equal(W.CountItem(ROUGH), 1200, "the rest on the next visit")
	H.False(W.Printed("Deadeye restocks your ammo"), "the notice comes once")
	W.CloseVendor()
	W.Click(Ammo.vendorButtonFrame, "RightButton")
	H.False(Ammo.db.autoRestock, "right-click turns it off")
	Shoot(W, 600)
	W.OpenVendor(VENDOR)
	W.Advance(2)
	H.Equal(W.CountItem(ROUGH), 600, "off now")
end)

test("ammo: closing the vendor mid-purchase stops it and reports what was bought", function()
	local W, Ammo = Setup({ arrows = 0 })
	W.OpenVendor(VENDOR)
	W.Click(Ammo.vendorButtonFrame)
	W.Advance(0.4)
	W.CloseVendor()
	W.Advance(2)
	H.Equal(#W.purchases, 2, "two stacks before it closed")
	H.True(W.Printed("Bought 400 Rough Arrow for 20c."), "reports the two")
end)

test("ammo: no button where neither your ammo nor pet food is sold, or when it's turned off", function()
	local W, Ammo = Setup()
	W.OpenVendor({ { itemID = LIGHT_SHOT, price = 10 } })
	H.False(Ammo.vendorButtonFrame:IsShown(), "bullets only: nothing for a bow")
	W.CloseVendor()
	W.Slash("ammo button off")
	W.OpenVendor(VENDOR)
	H.False(Ammo.vendorButtonFrame:IsShown(), "turned off")
	W.CloseVendor()
	local W2, Ammo2 = Setup()
	W2.equipped[18] = nil
	W2.OpenVendor(VENDOR)
	H.False(Ammo2.vendorButtonFrame:IsShown(), "no ranged weapon")
end)

---------------------------------------------------------------------------
-- Pet food
---------------------------------------------------------------------------
local function WithPet(W)
	W.pet = { name = "Boar", level = 20, health = 500, healthMax = 500, happiness = 3, damage = 125, loyaltyRate = 1, loyalty = "Loyalty Level 2", diet = { "Meat" } }
	W.Fire("UNIT_PET", "player")
end

local FOOD_VENDOR = {
	{ itemID = JERKY, price = 25, batch = 1, maxStack = 20 },
	{ itemID = HAUNCH, price = 50, batch = 1, maxStack = 20 },
	{ itemID = 159, price = 25, batch = 1, maxStack = 20 }, -- water: no pet eats it
	{ itemID = ROUGH, price = 10 },
}

test("pet food: the button restocks food your pet eats, close to its level", function()
	local W, Ammo = Setup({ arrows = 1000 })
	WithPet(W)
	W.OpenVendor(FOOD_VENDOR)
	local button = Ammo.vendorButtonFrame
	H.Equal(button:GetText(), "Restock", "ammo and pet food")
	local tooltip = Tooltip(W, button)
	H.True(tooltip:find("Buys 200 Rough Arrow for 10c.", 1, true), "the ammo")
	H.True(tooltip:find("Buys 20 Haunch of Meat for 10s 0c.", 1, true), "a stack of the food closest to the pet's level")
	H.True(tooltip:find("Food for Boar, close to its level.", 1, true), "says who it's for")
	W.Click(button)
	W.Advance(3)
	H.Equal(W.CountItem(HAUNCH), 20, "a stack")
	H.Equal(W.CountItem(JERKY), 0, "the low level food left alone")
	H.Equal(button:GetText(), "Fully stocked", "done")
	H.True(Tooltip(W, button):find("You carry enough food for Boar.", 1, true), "says why")
	W.Slash("pet foodstacks 2")
	H.Equal(button:GetText(), "Buy pet food", "a second stack wanted")
	W.Slash("pet buyfood off")
	H.Equal(button:GetText(), "Fully stocked", "turned off")
end)

test("pet food: no pet, or food it won't eat, means no food bought", function()
	local W, Ammo = Setup({ arrows = 1200 })
	W.OpenVendor(FOOD_VENDOR)
	H.Equal(Ammo.vendorButtonFrame:GetText(), "Fully stocked", "no pet: just the full quiver")
	W.CloseVendor()
	WithPet(W)
	W.pet.diet = { "Fish" }
	W.OpenVendor(FOOD_VENDOR)
	H.Equal(Ammo.vendorButtonFrame:GetText(), "Fully stocked", "a fish eater")
	W.CloseVendor()
	-- A food vendor without ammo still gets the button.
	W.pet.diet = { "Meat" }
	W.OpenVendor({ { itemID = HAUNCH, price = 50, batch = 1, maxStack = 20 } })
	H.Equal(Ammo.vendorButtonFrame:GetText(), "Buy pet food", "food only")
end)

test("pet food: leaving town without food your pet eats gets a warning", function()
	local W = Setup()
	WithPet(W)
	W.resting = false
	W.Fire("PLAYER_UPDATE_RESTING")
	H.True(W.Printed("You're heading out with no food Boar eats."), "warned")
	local W2 = Setup()
	WithPet(W2)
	W2.bags[0][1] = { itemID = HAUNCH, count = 5 }
	W2.resting = false
	W2.Fire("PLAYER_UPDATE_RESTING")
	H.False(W2.Printed("heading out with no food"), "carrying some")
end)

test("ammo: options page and chat settings", function()
	local W, Ammo = Setup()
	W.Slash("ammo low 400")
	H.Equal(Ammo.db.lowAmount, 400, "low mark set by chat")
	H.SameColor(Ammo.frame.count.textColor, { 1, 1, 1 }, "600 is still plenty")
	W.Slash("ammo low 800")
	H.SameColor(Ammo.frame.count.textColor, { 1, 0.82, 0 }, "now it's low")
	W.Slash("ammo spend 30")
	H.Equal(Ammo.db.autoSpend, 30, "spending limit by chat")
	W.Slash("")
	local window = W.ns.OptionsWindow
	local found
	for index, section in ipairs(window.sections) do
		if section.name == "Ammo" then
			found = index
		end
	end
	H.True(found, "an Ammo page in the options window")
end)

return tests
