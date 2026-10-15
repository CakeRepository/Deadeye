-- Ammo, quivers, the ammo slot and vendors (Modules\Ammo.lua). See MOCK_FILES
-- in tests/harness.lua.
--   W.equipped[slot] = itemID   18: ranged weapon, 0: ammo slot (empty by default)
--   W.bags[bag].family          1: quiver (arrows), 2: ammo pouch (bullets)
--   W.money                     copper
--   W.OpenVendor(items)         a vendor selling { itemID =, price = (per batch),
--                               batch =, available =, usable =, maxStack = }
--   W.purchases                 BuyMerchantItem calls, with .failed when refused
-- Real Classic item IDs, levels and icons.
local AMMO_ITEMS = {
	[2512] = { name = "Rough Arrow", level = 5, icon = 132382, classID = 6, subclassID = 2, family = 1, stack = 200 },
	[2515] = { name = "Sharp Arrow", level = 15, icon = 132382, classID = 6, subclassID = 2, family = 1, stack = 200 },
	[3030] = { name = "Razor Arrow", level = 25, icon = 132382, classID = 6, subclassID = 2, family = 1, stack = 200 },
	[2516] = { name = "Light Shot", level = 5, icon = 132384, classID = 6, subclassID = 3, family = 2, stack = 200 },
	[2519] = { name = "Heavy Shot", level = 15, icon = 132384, classID = 6, subclassID = 3, family = 2, stack = 200 },
	[2504] = { name = "Worn Shortbow", level = 5, icon = 135489, classID = 2, subclassID = 2 },
	[2508] = { name = "Old Blunderbuss", level = 5, icon = 135610, classID = 2, subclassID = 3 },
	[15807] = { name = "Light Crossbow", level = 20, icon = 135530, classID = 2, subclassID = 18 },
	[2947] = { name = "Small Throwing Knife", level = 5, icon = 135419, classID = 2, subclassID = 16 },
	[5439] = { name = "Small Quiver", level = 5, icon = 134407, classID = 11, subclassID = 2 },
}
local SLOTS = { AmmoSlot = 0, RangedSlot = 18 }

return function(W, env, M)
	local check, isNumber = M.check, M.isNumber
	for itemID, item in pairs(AMMO_ITEMS) do
		local copy = {}
		for key, value in pairs(item) do
			copy[key] = value
		end
		W.items[itemID] = copy
	end
	W.equipped = {}
	W.money = 10000
	W.vendor = nil
	W.purchases = {}
	W.ammoCountSecret = false -- true: the ammo slot's count comes back secret
	W.playerLevel = 20
	W.resting = true -- in an inn or a city
	W.shiftDown = false

	local function Count(itemID)
		local total = 0
		for _, bag in pairs(W.bags) do
			for slot = 1, bag.size do
				local entry = bag[slot]
				if entry and entry.itemID == itemID then
					total = total + (entry.count or 1)
				end
			end
		end
		return total
	end
	W.CountItem = Count

	-- A bag made for some items (quiver, ammo pouch) takes only those.
	local function Fits(bag, item)
		local family = bag.family or 0
		return family == 0 or (item.family ~= nil and family % (item.family * 2) >= item.family)
	end

	-- Puts items in bags the way the game does: onto part stacks first, then
	-- into empty slots of bags made for them, then plain bags. Adds nothing and
	-- returns false if they don't all fit.
	function W.AddItem(itemID, count)
		local item = W.items[itemID]
		local stack = item.stack or 20
		local room = 0
		for _, bag in pairs(W.bags) do
			for slot = 1, bag.size do
				local entry = bag[slot]
				if entry and entry.itemID == itemID then
					room = room + stack - entry.count
				elseif not entry and Fits(bag, item) then
					room = room + stack
				end
			end
		end
		if room < count then
			return false
		end
		local left = count
		for bagIndex = 0, 4 do
			local bag = W.bags[bagIndex]
			for slot = 1, bag and bag.size or 0 do
				local entry = bag[slot]
				if left > 0 and entry and entry.itemID == itemID and entry.count < stack then
					local add = math.min(stack - entry.count, left)
					entry.count, left = entry.count + add, left - add
				end
			end
		end
		for _, special in ipairs({ true, false }) do
			for bagIndex = 0, 4 do
				local bag = W.bags[bagIndex]
				if bag and Fits(bag, item) and ((bag.family or 0) ~= 0) == special then
					for slot = 1, bag.size do
						if left > 0 and not bag[slot] then
							local add = math.min(stack, left)
							bag[slot], left = { itemID = itemID, count = add }, left - add
						end
					end
				end
			end
		end
		return true
	end

	-- Shooting: takes ammo from the bags, last bag first.
	function W.UseItem(itemID, count)
		for bagIndex = 4, 0, -1 do
			local bag = W.bags[bagIndex]
			for slot = bag and bag.size or 0, 1, -1 do
				local entry = bag[slot]
				if count > 0 and entry and entry.itemID == itemID then
					local take = math.min(entry.count, count)
					entry.count, count = entry.count - take, count - take
					if entry.count == 0 then
						bag[slot] = nil
					end
				end
			end
		end
		W.Fire("BAG_UPDATE_DELAYED")
	end

	env.GetInventoryItemID = function(unit, slot)
		check(unit == "player" and isNumber(slot), "GetInventoryItemID: unexpected arguments")
		return W.equipped[slot]
	end
	-- For the ammo slot, the game counts that ammo in all your bags.
	env.GetInventoryItemCount = function(unit, slot)
		check(unit == "player" and isNumber(slot), "GetInventoryItemCount: unexpected arguments")
		local itemID = W.equipped[slot]
		if slot == 0 then
			local count = itemID and Count(itemID) or 0
			return W.ammoCountSecret and M.H.Secret(count) or count
		end
		return itemID and 1 or 0
	end
	env.C_PaperDollInfo = {
		GetInventorySlotInfo = function(name)
			check(SLOTS[name], "GetInventorySlotInfo: unexpected slot " .. tostring(name))
			return SLOTS[name], 136520, false
		end,
	}
	local baseItemInfo = env.C_Item.GetItemInfo
	env.C_Item.GetItemInfo = function(itemID)
		local item = W.items[itemID]
		if item and item.classID and not item.uncached then
			return item.name, "|Hitem:" .. itemID .. "|h", 1, item.level, math.max(1, item.level - 5), "", "",
				item.stack or 1, "", item.icon
		end
		return baseItemInfo(itemID)
	end
	env.C_Item.GetItemInfoInstant = function(itemID)
		check(isNumber(itemID), "C_Item.GetItemInfoInstant: item id expected")
		local item = W.items[itemID]
		if not item then
			return nil
		end
		return itemID, "", "", "", item.icon or 134400, item.classID or 0, item.subclassID or 0
	end
	env.C_Item.GetItemFamily = function(itemID)
		check(isNumber(itemID), "C_Item.GetItemFamily: item id expected")
		local item = W.items[itemID]
		return item and item.family or 0
	end
	env.C_Item.GetItemCount = function(itemID)
		check(isNumber(itemID), "C_Item.GetItemCount: item id expected")
		return Count(itemID)
	end
	env.C_Container.GetContainerNumFreeSlots = function(bag)
		check(isNumber(bag), "GetContainerNumFreeSlots: bag index expected")
		local contents = W.bags[bag]
		if not contents then
			return 0, 0
		end
		local free = 0
		for slot = 1, contents.size do
			if not contents[slot] then
				free = free + 1
			end
		end
		return free, contents.family or 0
	end
	local baseLevel = env.UnitLevel
	env.UnitLevel = function(unit)
		if unit == "player" then
			return W.playerLevel
		end
		return baseLevel(unit)
	end
	env.IsResting = function()
		return W.resting
	end
	env.IsShiftKeyDown = function()
		return W.shiftDown
	end
	-- Ammo goes to the ammo slot a moment later, if you carry it (and not in combat).
	env.C_Item.EquipItemByName = function(itemID)
		check(isNumber(itemID), "C_Item.EquipItemByName: item id expected")
		check(not W.inCombat, "C_Item.EquipItemByName: called in combat")
		W.equips = (W.equips or 0) + 1
		local item = W.items[itemID]
		if item and item.classID == 6 and Count(itemID) > 0 then
			W.timers[#W.timers + 1] = { at = W.now + 0.1, callback = function()
				W.equipped[0] = itemID
				W.Fire("PLAYER_EQUIPMENT_CHANGED", 0, true)
			end }
		end
	end
	env.GetMoney = function()
		return W.money
	end
	env.GetMoneyString = function(copper)
		check(isNumber(copper) and copper == math.floor(copper), "GetMoneyString: whole copper expected")
		local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
		if gold > 0 then
			return string.format("%dg %ds %dc", gold, silver, rest)
		elseif silver > 0 then
			return string.format("%ds %dc", silver, rest)
		end
		return string.format("%dc", rest)
	end

	-- The vendor window and its API.
	M.NewFrame("Frame", "MerchantFrame", env.UIParent):Hide()
	local function VendorItem(index)
		check(W.vendor ~= nil, "merchant API used with no vendor open")
		check(isNumber(index), "merchant API: index expected")
		return W.vendor.items[index]
	end
	env.GetMerchantNumItems = function()
		return W.vendor and #W.vendor.items or 0
	end
	env.GetMerchantItemID = function(index)
		local entry = VendorItem(index)
		return entry and entry.itemID
	end
	env.GetMerchantItemMaxStack = function(index)
		local entry = VendorItem(index)
		return entry and (entry.maxStack or W.items[entry.itemID].stack or 1)
	end
	env.C_MerchantFrame = {
		GetItemInfo = function(index)
			local entry = VendorItem(index)
			local item = W.items[entry.itemID] or { name = "Item " .. entry.itemID }
			return {
				name = item.name, texture = item.icon, price = entry.price, stackCount = entry.batch or 200,
				numAvailable = entry.available or -1, isPurchasable = entry.purchasable ~= false,
				isUsable = entry.usable ~= false, hasExtendedCost = entry.extendedCost == true, isQuestStartItem = false,
			}
		end,
	}
	-- Buys quantity items: a whole number of batches, no more than one purchase allows.
	env.BuyMerchantItem = function(index, quantity)
		local entry = VendorItem(index)
		check(isNumber(quantity) and quantity > 0, "BuyMerchantItem: quantity expected")
		local batch = entry.batch or 200
		check(quantity % batch == 0, "BuyMerchantItem: not a whole number of batches")
		check(quantity <= env.GetMerchantItemMaxStack(index), "BuyMerchantItem: more than one purchase allows")
		local cost = quantity / batch * entry.price
		local purchase = { itemID = entry.itemID, quantity = quantity, cost = cost }
		W.purchases[#W.purchases + 1] = purchase
		if W.money < cost then
			purchase.failed = "money"
		elseif not W.AddItem(entry.itemID, quantity) then
			purchase.failed = "bags"
		else
			W.money = W.money - cost
			-- The server answers a moment later.
			W.timers[#W.timers + 1] = { at = W.now + 0.05, callback = function()
				W.Fire("BAG_UPDATE_DELAYED")
				W.Fire("PLAYER_MONEY")
			end }
		end
	end
	function W.OpenVendor(items)
		W.vendor = { items = items }
		env.MerchantFrame:Show()
		W.Fire("MERCHANT_SHOW")
	end
	function W.CloseVendor()
		env.MerchantFrame:Hide()
		W.Fire("MERCHANT_CLOSED")
		W.vendor = nil
	end
end
