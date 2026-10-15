-- Ammo: how many arrows or bullets you have left (and for how many minutes of
-- fighting), warnings before you run out or head out of town short, and a
-- button below vendor windows that restocks you: it fills your quiver or ammo
-- pouch, switching to better ammo when the vendor has some you can use, and
-- buys food your pet eats (see Pet:FoodOffer). By default it does all that by
-- itself when such a vendor opens, spending at most half your money. When your
-- ammo runs out, the best other ammo you carry goes in the ammo slot.
--
-- The ammo slot holds the ammo you shoot, and GetInventoryItemCount on that
-- slot counts all of it in your bags. A bag's family
-- (C_Container.GetContainerNumFreeSlots) says what it holds: quivers take
-- arrows, ammo pouches take bullets (C_Item.GetItemFamily). Vendors sell ammo
-- in batches of 200. BuyMerchantItem takes a number of items that is a whole
-- number of batches and at most GetMerchantItemMaxStack, the way the game's
-- merchant frame buys several stacks. C_Item.EquipItemByName puts ammo in the
-- ammo slot; at a vendor, using an item would sell it instead.
local _, ns = ...
local L = ns.L

local Ammo = ns:NewModule("Ammo", {
	enabled = true,
	attach = "BAR", -- "BAR": right of the Auto Shot bar, moving with it; "FREE": its own position
	position = { x = 165, y = -324 }, -- used when attach is "FREE"
	scale = 1,
	show = "always", -- "always", or "low": only while you're running low
	lowAmount = 200, -- running low below this many
	lowAlert = true, -- warn as I drop below it, run out, start a fight or leave town short
	alertSound = "RAID_WARNING",
	vendorButton = true, -- the restock button below vendor windows
	autoRestock = true, -- restock by itself when such a vendor opens
	autoSpend = 50, -- restocking by itself spends at most this much of your money, in percent
	upgrade = true, -- better ammo than yours, when a vendor has it, replaces yours
	autoSwap = true, -- your ammo ran out: the best other ammo you carry goes in the slot
	bagStacks = 4, -- without a quiver or ammo pouch: stacks to carry in your bags
	usage = { seconds = 0, used = 0 }, -- combat time and ammo shot in it, for the forecast
	restockNoticeShown = false, -- the first restock by itself says how to stop it
})
Ammo.title = L["Ammo"]
Ammo.slashPrefix = "ammo"

local RANGED_SLOT, AMMO_SLOT = 18, 0 -- the game's slot numbers, if it doesn't say
-- Item classes (Enum.ItemClass) and subclasses from the game's item data.
local WEAPON, PROJECTILE, QUIVER_CLASS = 2, 6, 11
local ARROW, BULLET = 2, 3
local WEAPON_AMMO = { [2] = ARROW, [18] = ARROW, [3] = BULLET } -- bows, crossbows, guns
local AMMO_FAMILY = { [ARROW] = 1, [BULLET] = 2 } -- quivers hold arrows, ammo pouches bullets
local AMMO_BAG = { [ARROW] = 2, [BULLET] = 3 } -- quiver class subclasses: quiver, ammo pouch
local BAGS = { 0, 1, 2, 3, 4 } -- backpack and the four bag slots
local DEFAULT_STACK = 200
local BUY_SECONDS = 0.3 -- between purchases, so the vendor keeps up
local AUTO_BUY_SECONDS = 0.5 -- after a vendor opens, so its items have loaded
local EQUIP_SECONDS, EQUIP_TRIES = 0.5, 4 -- waiting for ammo to reach your bags and slot
local SWAP_RETRY_SECONDS = 10 -- an ammo swap that didn't take is tried again after this
local USAGE_SECONDS = 3600 -- the forecast follows your last hour of fighting
local FORECAST_MIN_SECONDS = 60 -- of fighting seen before there's a forecast
local LEAVING_MINUTES = 15 -- leaving town with less fighting than this left gets a warning
local LEAVING_QUIET_SECONDS = 300 -- one leaving-town warning per this long
local ICON_SIZE = 20
local PULSE_SECONDS = 3
local SAMPLE_COUNT, SAMPLE_ICON = 1400, 132382 -- shown while previewing or moving the counter
local EMPTY_ICONS = { [ARROW] = 132382, [BULLET] = 132384 }
local COLORS = {
	normal = { 1, 1, 1 },
	low = { 1, 0.82, 0 },
	empty = { 1, 0.25, 0.25 },
}

local SHOW_CHOICES = {
	{ value = "always", text = L["Always"] },
	{ value = "low", text = L["Only when I'm running low"] },
}
local ATTACH_CHOICES = {
	{ value = "BAR", text = L["Next to the Auto Shot bar"] },
	{ value = "FREE", text = L["Anywhere (drag it)"] },
}

local preview = false

---------------------------------------------------------------------------
-- What you shoot and carry
---------------------------------------------------------------------------
local function SlotID(name, fallback)
	local getSlot = C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo
	if getSlot then
		local ok, slot = pcall(getSlot, name)
		slot = ok and ns.Readable(slot)
		if type(slot) == "number" then
			return slot
		end
	end
	return fallback
end

local function ItemClass(itemID)
	local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
	return classID, subclassID
end

-- ARROW or BULLET for the ranged weapon you have on; nil when it takes no ammo.
local function AmmoKind()
	local weapon = ns.Readable(GetInventoryItemID("player", SlotID("RangedSlot", RANGED_SLOT)))
	if not weapon then
		return nil
	end
	local classID, subclassID = ItemClass(weapon)
	return classID == WEAPON and WEAPON_AMMO[subclassID] or nil
end

-- The ammo in your ammo slot (nil when it's empty) and how many of it you
-- carry. The count is passed on as it is if the game keeps it secret.
local function EquippedAmmo()
	local slot = SlotID("AmmoSlot", AMMO_SLOT)
	local itemID = ns.Readable(GetInventoryItemID("player", slot))
	if not itemID then
		return nil, 0
	end
	return itemID, GetInventoryItemCount("player", slot)
end

-- flag is a power of two.
local function HasFlag(flags, flag)
	return flags % (flag * 2) >= flag
end

local function StackSize(itemID, fallback)
	return select(8, C_Item.GetItemInfo(itemID)) or fallback or DEFAULT_STACK
end

-- Free room for an item, as numbers of items: in bags made for its family
-- (quivers, ammo pouches; family 0 for none), in plain bags, and on part
-- stacks of it anywhere. Also whether you have a bag made for it, and the
-- item's stack size.
local function FreeRoom(itemID, family, stack)
	local special, plain, part, hasSpecial = 0, 0, 0, false
	for _, bag in ipairs(BAGS) do
		local free, bagFamily = C_Container.GetContainerNumFreeSlots(bag)
		free, bagFamily = ns.Readable(free, 0), ns.Readable(bagFamily, 0)
		if bagFamily == 0 then
			plain = plain + free * stack
		elseif family ~= 0 and HasFlag(bagFamily, family) then
			hasSpecial = true
			special = special + free * stack
		end
		for slot = 1, ns.Readable(C_Container.GetContainerNumSlots(bag), 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and ns.Readable(info.itemID) == itemID then
				part = part + math.max(0, stack - ns.Readable(info.stackCount, stack))
			end
		end
	end
	return special, plain, part, hasSpecial
end

-- How many more of an ammo item fit, and whether you have a quiver or ammo
-- pouch for it. With one, that's its free space plus room on part stacks of
-- the item anywhere. Without, the item goes in your other bags, up to
-- bagStacks stacks in all; the third value is how many that still wants.
function Ammo:Room(itemID, kind)
	local stack = StackSize(itemID)
	local family = ns.Readable(C_Item.GetItemFamily(itemID)) or AMMO_FAMILY[kind] or 0
	local special, plain, part, hasAmmoBag = FreeRoom(itemID, family, stack)
	if hasAmmoBag then
		return special + part, true
	end
	local carried = ns.Readable(C_Item.GetItemCount(itemID), 0)
	local wanted = math.max(0, self.db.bagStacks * stack - carried)
	return math.min(wanted, plain + part), false, wanted
end

-- The best ammo of a kind in your bags that you can use, other than `except`.
local function BestCarried(kind, except)
	local level = ns.Readable(UnitLevel("player"), 1)
	local best, bestLevel
	for _, bag in ipairs(BAGS) do
		for slot = 1, ns.Readable(C_Container.GetContainerNumSlots(bag), 0) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local itemID = info and ns.Readable(info.itemID)
			if itemID and itemID ~= except then
				local classID, subclassID = ItemClass(itemID)
				if classID == PROJECTILE and subclassID == kind then
					local name, _, _, itemLevel, minLevel = C_Item.GetItemInfo(itemID)
					if (minLevel or 0) <= level and (not best or (itemLevel or 0) > bestLevel) then
						best, bestLevel = { itemID = itemID, name = name or "" }, itemLevel or 0
					end
				end
			end
		end
	end
	return best
end

---------------------------------------------------------------------------
-- Forecast: how long your ammo lasts
---------------------------------------------------------------------------
-- Ammo shot per second of fighting, from your recent fights, or nil.
function Ammo:ShotsPerSecond()
	local usage = self.db.usage
	if usage.seconds >= FORECAST_MIN_SECONDS and usage.used > 0 then
		return usage.used / usage.seconds
	end
end

-- Whole minutes of fighting your ammo lasts at that rate, or nil.
function Ammo:MinutesLeft(count)
	local rate = count and self:ShotsPerSecond()
	return rate and math.floor(count / rate / 60)
end

-- A fight ended: the ammo it used (same ammo throughout, nothing bought).
function Ammo:RecordFight(now)
	local fight = self.fight
	self.fight = nil
	if not (fight and self.count and self.itemID == fight.itemID) then
		return
	end
	local seconds, used = now - fight.start, fight.count - self.count
	if seconds <= 0 or used < 0 then
		return
	end
	local usage = self.db.usage
	usage.seconds, usage.used = usage.seconds + seconds, usage.used + used
	if usage.seconds > USAGE_SECONDS then
		local scale = USAGE_SECONDS / usage.seconds
		usage.seconds, usage.used = USAGE_SECONDS, usage.used * scale
	end
end

---------------------------------------------------------------------------
-- The counter
---------------------------------------------------------------------------
function Ammo:Alert(message)
	ns.Print(message)
	local sound = ns.Media.Sound(self.db.alertSound)
	if sound then
		PlaySound(sound, "Master")
	end
	self.pulseUntil = GetTime() + PULSE_SECONDS
	self.frame:SetScript("OnUpdate", function(frame)
		local remaining = self.pulseUntil - GetTime()
		if remaining <= 0 then
			frame:SetAlpha(1)
			frame:SetScript("OnUpdate", nil)
			return
		end
		frame:SetAlpha(0.55 + 0.45 * math.abs(math.cos(remaining * 4)))
	end)
end

-- Warns once as you drop below the low mark and when you run out. Counts are
-- compared for the same kind of ammo only, so swapping weapons doesn't warn.
function Ammo:CheckLow(kind, count)
	local db, last = self.db, self.lastCount
	if kind ~= self.lastKind then
		last = nil
	end
	self.lastKind, self.lastCount = kind, count
	if not (db.lowAlert and last) or count >= last then
		return
	end
	if count == 0 then
		self:Alert(L["You're out of ammo."])
	elseif count < db.lowAmount and last >= db.lowAmount then
		self:Alert(L["Running low on ammo: %d left."]:format(count))
	end
end

-- Puts ammo in your ammo slot once it's in your bags (after buying it), and
-- says whether that worked. Out of combat only.
function Ammo:EquipAmmo(itemID, name, tries)
	tries = tries or 0
	if (EquippedAmmo()) == itemID then
		ns.Print(L["%s is in your ammo slot now."]:format(name))
		return
	end
	if tries >= EQUIP_TRIES or InCombatLockdown() then
		ns.Print(L["Put %s in your ammo slot to shoot it."]:format(name))
		return
	end
	if ns.Readable(C_Item.GetItemCount(itemID), 0) > 0 then
		C_Item.EquipItemByName(itemID)
	end
	C_Timer.After(EQUIP_SECONDS, function()
		self:EquipAmmo(itemID, name, tries + 1)
	end)
end

-- Your ammo ran out (or the slot is empty): the best other ammo you carry goes in.
function Ammo:SwapIfEmpty(kind, itemID, count)
	if not (self.db.autoSwap and count == 0) or InCombatLockdown() or self.vendorOpen then
		return
	end
	local now = GetTime()
	if self.swapAt and now < self.swapAt then
		return
	end
	local best = BestCarried(kind, itemID)
	if best then
		self.swapAt = now + SWAP_RETRY_SECONDS
		self:EquipAmmo(best.itemID, best.name)
	end
end

function Ammo:Update()
	local frame = self.frame
	if not frame then
		return
	end
	local db = self.db
	local kind = AmmoKind()
	local itemID, count = EquippedAmmo()
	local readable = not ns.IsSecret(count)
	self.kind, self.itemID, self.count = kind, itemID, readable and count or nil
	if kind and readable then
		self:CheckLow(kind, count)
		self:SwapIfEmpty(kind, itemID, count)
	end
	local sample = preview or ns:IsUnlocked()
	local low = kind and readable and count < db.lowAmount
	if not (db.enabled and (sample or (kind and (db.show == "always" or low)))) then
		frame:Hide()
		return
	end
	local icon
	if kind then
		icon = itemID and select(5, C_Item.GetItemInfoInstant(itemID)) or EMPTY_ICONS[kind]
	else
		icon, count, readable, low = SAMPLE_ICON, SAMPLE_COUNT, true, false
	end
	frame.icon:SetTexture(icon)
	frame.count:SetText(count) -- a secret count can be shown, not compared
	if readable then
		local color = count == 0 and COLORS.empty or low and COLORS.low or COLORS.normal
		frame.count:SetTextColor(color[1], color[2], color[3])
		frame.icon:SetDesaturated(count == 0)
	end
	frame:Show()
end

function Ammo:ShowTooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	local name = self.itemID and C_Item.GetItemInfo(self.itemID)
	GameTooltip:SetText(name or L["Ammo"])
	if self.kind and not self.itemID then
		GameTooltip:AddLine(L["Your ammo slot is empty."], 1, 0.3, 0.3)
	elseif self.kind and self.count then
		GameTooltip:AddLine(L["%d left"]:format(self.count), 1, 1, 1)
		local minutes = self:MinutesLeft(self.count)
		if minutes then
			GameTooltip:AddLine(L["Enough for about %d minutes of fighting."]:format(minutes), 1, 1, 1)
		end
		local room, hasAmmoBag = self:Room(self.itemID, self.kind)
		if hasAmmoBag then
			GameTooltip:AddLine(L["Room for %d more in your quiver or ammo pouch."]:format(room), 1, 1, 1)
		end
	end
	GameTooltip:AddLine(L["Vendors that sell your ammo or pet food get a button that restocks you."], 0.7, 0.7, 0.7, true)
	GameTooltip:Show()
end

function Ammo:BuildFrame()
	local frame = CreateFrame("Frame", "DeadeyeAmmoFrame", UIParent)
	frame:SetSize(ICON_SIZE + 46, ICON_SIZE)
	frame:SetFrameStrata("MEDIUM")
	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetSize(ICON_SIZE, ICON_SIZE)
	frame.icon:SetPoint("LEFT")
	frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	frame.count:SetPoint("LEFT", frame.icon, "RIGHT", 4, 0)
	frame.count:SetJustifyH("LEFT")
	frame:SetScript("OnEnter", function(owner)
		self:ShowTooltip(owner)
	end)
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	frame:Hide()
	ns.Frames.MakeMovable(self, frame, L["Ammo"], true)
	self.frame = frame
end

-- Attached, the counter sits just right of the Auto Shot bar (past its border
-- and an icon on that side) and follows it around.
function Ammo:ApplyAnchor()
	local frame, autoShot = self.frame, ns.modules.AutoShot
	frame:ClearAllPoints()
	if self.db.attach == "BAR" and autoShot.bar then
		local barDB = autoShot.db
		if barDB.icon == "RIGHT" then
			frame:SetPoint("LEFT", autoShot.bar.icon, "RIGHT", 4, 0)
		else
			frame:SetPoint("LEFT", autoShot.bar, "RIGHT", barDB.borderSize + 4, 0)
		end
	else
		ns.Frames.ApplyPosition(self, frame)
	end
end

function Ammo:ApplyLayout()
	self.frame:SetScale(self.db.scale)
	ns.Frames.UpdateMover(self.frame)
	self:ApplyAnchor()
	self:Update()
end

-- Dragging the counter away from the bar gives it a position of its own.
function Ammo:OnDragged()
	self.db.attach = "FREE"
end

function Ammo:OnOptionChanged()
	self:ApplyLayout()
	self:UpdateVendorButton()
end

Ammo.OnUnlockChanged = Ammo.ApplyLayout
Ammo.OnSettingsReset = Ammo.ApplyLayout

function Ammo:SetPreview(enabled)
	preview = enabled
	self:Update()
end

---------------------------------------------------------------------------
-- Vendors: restocking ammo and pet food
---------------------------------------------------------------------------
-- A job is one item to buy: what the vendor sells (index, itemID, name, price
-- for a batch of `batch` items, stock `available` or -1, at most `maxStack`
-- per purchase), how many to buy (count, cost, quantities: one purchase per
-- stack), and why it buys nothing (reason) or what the tooltip says about it.
local function Money(copper)
	return GetMoneyString(math.floor(copper + 0.5), true)
end

-- What a vendor's item costs and how it's sold. Pet:FoodOffer uses it too.
function ns.VendorOffer(index, info, itemID)
	local itemName, _, _, level = C_Item.GetItemInfo(itemID)
	return {
		index = index,
		itemID = itemID,
		name = info.name or itemName or "",
		price = info.price,
		batch = math.max(1, info.stackCount or 1),
		available = info.numAvailable or -1,
		maxStack = ns.Readable(GetMerchantItemMaxStack(index), 1),
		level = level or 0,
	}
end

local function ForSale(info)
	return info and info.isPurchasable and not info.hasExtendedCost and (info.price or 0) > 0 and info.numAvailable ~= 0
end

-- The vendor's ammo for your weapon: what's in your ammo slot, if it sells
-- that, and the best (highest item level) of the right kind you can use. Also
-- a quiver or ammo pouch for that ammo, if it sells one.
local function FindOffers(kind, equippedID)
	local current, best, bag
	for index = 1, ns.Readable(GetMerchantNumItems(), 0) do
		local itemID = ns.Readable(GetMerchantItemID(index))
		local classID, subclassID
		if itemID then
			classID, subclassID = ItemClass(itemID)
		end
		local info = itemID and C_MerchantFrame.GetItemInfo(index)
		if classID == PROJECTILE and subclassID == kind and ForSale(info) and info.isUsable then
			local offer = ns.VendorOffer(index, info, itemID)
			if itemID == equippedID then
				current = offer
			end
			if not best or offer.level > best.level then
				best = offer
			end
		elseif classID == QUIVER_CLASS and subclassID == AMMO_BAG[kind] and ForSale(info) and info.isUsable then
			bag = info.name or C_Item.GetItemInfo(itemID)
		end
	end
	return current, best, bag
end

-- Sets a job's count from `batches`, with one purchase per stack (or as many
-- batches as one purchase may hold).
local function Schedule(job, batches)
	job.count, job.cost = batches * job.batch, batches * job.price
	local perPurchase = math.max(job.batch, math.floor(job.maxStack / job.batch) * job.batch)
	job.quantities = {}
	local left = job.count
	while left > 0 do
		local quantity = math.min(perPurchase, left)
		job.quantities[#job.quantities + 1] = quantity
		left = left - quantity
	end
	return job
end

-- Batches of an offer to buy: as many as fit in `room` items, within the
-- budget and the vendor's stock. Also how many would fit.
local function Batches(offer, room, budget)
	local fit = math.floor(room / offer.batch)
	local count = math.min(fit, math.floor(budget / offer.price))
	if offer.available > 0 then
		count = math.min(count, math.floor(offer.available))
	end
	return math.max(count, 0), fit
end

-- Ammo to buy: better ammo than yours if the vendor has some you can use
-- (unless keepCurrent, or upgrades are off), otherwise yours, or the best it
-- has when it doesn't sell yours. job.upgrade: better than yours; job.worse:
-- not as good; job.equip: put it in the ammo slot afterwards.
function Ammo:AmmoJob(keepCurrent, budget)
	local kind = AmmoKind()
	if not kind then
		return nil
	end
	local equippedID, carried = EquippedAmmo()
	local current, best, bagForSale = FindOffers(kind, equippedID)
	if not best then
		return nil
	end
	local equippedName, _, _, equippedLevel
	if equippedID then
		equippedName, _, _, equippedLevel = C_Item.GetItemInfo(equippedID)
	end
	equippedLevel = equippedLevel or 0
	local job, upgrade, equip, worse = current, false, false, false
	if not equippedID then
		job, equip = best, true
	elseif best ~= current and best.level > equippedLevel and self.db.upgrade and not keepCurrent then
		job, upgrade, equip = best, true, true
	elseif not current then
		-- Yours isn't for sale here: the best it has, in your slot once yours runs out.
		job, equip, worse = best, ns.Readable(carried, 1) == 0, best.level < equippedLevel
	end
	local room, hasAmmoBag, wanted = self:Room(job.itemID, kind)
	local count, fit = Batches(job, room, budget)
	Schedule(job, count)
	job.kind, job.hasAmmoBag, job.stack = kind, hasAmmoBag, StackSize(job.itemID)
	job.upgrade, job.equip, job.worse = upgrade, equip, worse
	job.currentName, job.currentForSale = equippedName or L["Ammo"], current ~= nil
	job.bagForSale = not hasAmmoBag and bagForSale or nil
	if count == 0 then
		if fit > 0 then
			job.reason = "money"
		elseif hasAmmoBag or wanted < job.batch then
			job.reason = "full"
		else
			job.reason = "bags"
		end
	end
	return job
end

-- Pet food to buy, up to the stacks the pet settings ask for, in the plain bag
-- room left after `slotsTaken` slots.
function Ammo:FoodJob(budget, slotsTaken)
	local pet = ns.modules.Pet
	local job = pet and pet.enabled and pet:FoodOffer()
	if not job then
		return nil
	end
	local stack = StackSize(job.itemID, 20)
	local _, plain, part = FreeRoom(job.itemID, 0, stack)
	local wanted = math.max(0, pet.db.foodStacks * stack - pet:FoodCarried(job.tier))
	local room = math.min(wanted, math.max(0, plain - slotsTaken * stack) + part)
	local count, fit = Batches(job, room, budget)
	Schedule(job, count)
	job.food, job.petName = true, ns.Readable(UnitName("pet"), L["Your pet"])
	if count == 0 then
		job.reason = fit > 0 and "money" or wanted < job.batch and "stocked" or "bags"
	end
	return job
end

-- Everything the button would buy now. auto: the vendor just opened, so stay
-- within autoSpend and leave weaker ammo than yours alone.
function Ammo:Jobs(keepCurrent, auto)
	local jobs = {}
	if not self.vendorOpen then
		return jobs
	end
	local money = ns.Readable(GetMoney(), 0)
	local budget = auto and math.floor(money * self.db.autoSpend / 100) or money
	local ammo = self:AmmoJob(keepCurrent, budget)
	if ammo and not (auto and ammo.worse and not ammo.equip) then
		jobs[#jobs + 1] = ammo
		budget = budget - ammo.cost
	else
		ammo = nil
	end
	local slotsTaken = ammo and not ammo.hasAmmoBag and math.ceil(ammo.count / ammo.stack) or 0
	local food = self:FoodJob(budget, slotsTaken)
	if food then
		jobs[#jobs + 1] = food
	end
	return jobs
end

local function ReasonText(job)
	if job.reason == "money" then
		return L["Not enough money for %s."]:format(job.name)
	elseif job.reason == "bags" then
		return L["Your bags are full."]
	elseif job.food then
		return L["You carry enough food for %s."]:format(job.petName)
	elseif job.hasAmmoBag then
		return job.kind == BULLET and L["Your ammo pouch is full."] or L["Your quiver is full."]
	end
	return L["You already carry the number of stacks set in /deadeye."]
end

-- The button's text: what a click does.
local function ButtonText(jobs)
	local ammo, food, reasons = nil, nil, {}
	for _, job in ipairs(jobs) do
		if job.count > 0 then
			if job.food then
				food = job
			else
				ammo = job
			end
		elseif job.reason then
			reasons[job.reason] = true
		end
	end
	if ammo and food then
		return L["Restock"]
	elseif food then
		return L["Buy pet food"]
	elseif ammo then
		if ammo.upgrade then
			return L["Upgrade ammo"]
		elseif ammo.hasAmmoBag then
			return ammo.kind == BULLET and L["Fill ammo pouch"] or L["Fill quiver"]
		end
		return L["Buy ammo"]
	elseif reasons.money then
		return L["Not enough money"]
	elseif reasons.bags then
		return L["Bags full"]
	end
	return L["Fully stocked"]
end

function Ammo:BuyNext()
	local buying = self.buying
	if not buying then
		return
	end
	local step = table.remove(buying.queue, 1)
	if step then
		local job, quantity = step.job, step.quantity
		local cost = quantity / job.batch * job.price
		-- Stop if the vendor closed, its list changed or the money ran out.
		if self.vendorOpen and ns.Readable(GetMerchantItemID(job.index)) == job.itemID and ns.Readable(GetMoney(), 0) >= cost then
			BuyMerchantItem(job.index, quantity)
			job.bought, job.spent = job.bought + quantity, job.spent + cost
			C_Timer.After(BUY_SECONDS, function()
				self:BuyNext()
			end)
			return
		end
	end
	self.buying = nil
	for _, job in ipairs(buying.jobs) do
		if job.bought > 0 then
			ns.Print(L["Bought %d %s for %s."]:format(job.bought, job.name, Money(job.spent)))
			if job.equip then
				self:EquipAmmo(job.itemID, job.name)
			end
		end
	end
	self:UpdateVendorButton()
end

-- Buys what the jobs say, a stack at a time. auto: opening the vendor did it,
-- so say nothing when there's nothing to buy. keepCurrent: buy your own ammo
-- even if the vendor has better.
function Ammo:Fill(auto, keepCurrent)
	if self.buying then
		return
	end
	local jobs = self:Jobs(keepCurrent, auto)
	local queue = {}
	for _, job in ipairs(jobs) do
		job.bought, job.spent = 0, 0
		for _, quantity in ipairs(job.quantities) do
			queue[#queue + 1] = { job = job, quantity = quantity }
		end
	end
	if #queue == 0 then
		if not auto then
			for _, job in ipairs(jobs) do
				ns.Print(ReasonText(job))
			end
		end
		return
	end
	if auto and not self.db.restockNoticeShown then
		self.db.restockNoticeShown = true
		ns.Print(L["Deadeye restocks your ammo and pet food by itself at vendors. Right-click the button below the vendor window to stop that."])
	end
	self.buying = { jobs = jobs, queue = queue }
	self:UpdateVendorButton()
	self:BuyNext()
end

function Ammo:SetAutoRestock(enabled)
	self.db.autoRestock = enabled
	ns.Print(enabled and L["Deadeye now restocks you by itself at vendors."] or L["Deadeye no longer restocks you by itself."])
	ns.OptionsChanged()
end

function Ammo:ShowVendorTooltip(owner)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(owner:GetText())
	local jobs = self.jobs or {}
	if self.buying then
		GameTooltip:AddLine(L["Buying..."], 1, 1, 1)
	end
	for _, job in ipairs(self.buying and {} or jobs) do
		if job.count > 0 then
			if job.upgrade then
				GameTooltip:AddLine(L["%s does more damage than your %s."]:format(job.name, job.currentName), 0.35, 0.9, 0.35, true)
			elseif job.worse then
				GameTooltip:AddLine(L["%s does less damage than your %s."]:format(job.name, job.currentName), 1, 0.82, 0, true)
			end
			GameTooltip:AddLine(L["Buys %d %s for %s."]:format(job.count, job.name, Money(job.cost)), 1, 1, 1, true)
			if job.equip then
				GameTooltip:AddLine(L["Then puts it in your ammo slot."], 1, 1, 1, true)
			elseif job.food then
				GameTooltip:AddLine(L["Food for %s, close to its level."]:format(job.petName), 0.7, 0.7, 0.7, true)
			end
		else
			GameTooltip:AddLine(ReasonText(job), 1, 0.3, 0.3, true)
		end
		if job.bagForSale then
			GameTooltip:AddLine(L["%s is for sale here: quivers and ammo pouches make you shoot faster."]:format(job.bagForSale), 0.35, 0.9, 0.35, true)
		end
		if job.upgrade and job.currentForSale then
			GameTooltip:AddLine(L["Shift-click: buy %s instead"]:format(job.currentName), 0.7, 0.7, 0.7)
		end
	end
	if self.db.autoRestock then
		GameTooltip:AddLine(L["Restocks by itself, spending at most %d%% of your money."]:format(self.db.autoSpend), 0.7, 0.7, 0.7, true)
		GameTooltip:AddLine(L["Right-click: stop restocking by itself"], 0.7, 0.7, 0.7)
	else
		GameTooltip:AddLine(L["Right-click: restock by itself at vendors"], 0.7, 0.7, 0.7)
	end
	GameTooltip:Show()
end

-- A button below the vendor window, next to its Merchant and Buyback tabs. It
-- stays clickable with nothing to buy, so a right-click always works.
function Ammo:CreateVendorButton()
	if self.vendorButtonFrame or not MerchantFrame then
		return
	end
	local button = CreateFrame("Button", nil, MerchantFrame, "UIPanelButtonTemplate")
	button:SetSize(140, 22)
	button:SetPoint("TOPRIGHT", MerchantFrame, "BOTTOMRIGHT", -8, -4)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:SetScript("OnClick", function(_, mouseButton)
		if mouseButton == "RightButton" then
			self:SetAutoRestock(not self.db.autoRestock)
		else
			self:Fill(false, IsShiftKeyDown())
		end
		self:UpdateVendorButton()
	end)
	button:SetScript("OnEnter", function(owner)
		self:ShowVendorTooltip(owner)
	end)
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	button:Hide()
	self.vendorButtonFrame = button
end

function Ammo:UpdateVendorButton()
	local button = self.vendorButtonFrame
	if not button then
		return
	end
	local jobs = self.db.vendorButton and self:Jobs() or {}
	self.jobs = jobs
	button:SetShown(#jobs > 0)
	if #jobs > 0 then
		button:SetText(ButtonText(jobs))
		button:SetEnabled(not self.buying)
	end
end

---------------------------------------------------------------------------
-- Options
---------------------------------------------------------------------------
function Ammo:GetOptionSections()
	local controls = {
		{ type = "toggle", label = L["Show the ammo counter"], key = "enabled", slash = "enabled" },
		{ type = "select", label = L["Show it"], key = "show", values = SHOW_CHOICES, slash = "show" },
		{ type = "select", label = L["Where"], key = "attach", values = ATTACH_CHOICES, slash = "attach",
			set = function(value)
				if value == "FREE" and self.db.attach ~= "FREE" then
					ns.Frames.SavePosition(self, self.frame) -- stay where it is now
				end
				self.db.attach = value
				self:ApplyLayout()
			end },
	}
	for _, spec in ipairs(ns.Frames.PositionOptions(self)) do
		controls[#controls + 1] = spec
	end
	for _, spec in ipairs({
		{ type = "range", label = L["Running low below"], key = "lowAmount", min = 0, max = 2000, step = 50, slash = "low" },
		{ type = "toggle", label = L["Warn me when I'm running low"], key = "lowAlert", slash = "lowalert" },
		{ type = "toggle", label = L["Swap in other ammo when mine runs out"], key = "autoSwap", slash = "swap" },
		{ type = "header", label = L["At vendors"] },
		{ type = "toggle", label = L["Restock button at vendors"], key = "vendorButton", slash = "button" },
		{ type = "toggle", label = L["Restock by itself"], key = "autoRestock", slash = "autobuy" },
		{ type = "range", label = L["Restock spending limit (percent of my money)"], key = "autoSpend", min = 5, max = 100, step = 5, slash = "spend" },
		{ type = "toggle", label = L["Switch to better ammo when a vendor has it"], key = "upgrade", slash = "upgrade" },
		{ type = "range", label = L["Stacks to carry without a quiver"], key = "bagStacks", min = 1, max = 10, step = 1, slash = "stacks" },
	}) do
		controls[#controls + 1] = spec
	end
	return {
		{
			name = L["Ammo"],
			keys = { "enabled", "show", "attach", "position", "scale", "lowAmount", "lowAlert", "autoSwap",
				"vendorButton", "autoRestock", "autoSpend", "upgrade", "bagStacks" },
			controls = controls,
		},
	}
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
function Ammo:ShouldEnable()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

function Ammo:OnEnable()
	self:BuildFrame()
	local events = ns.CreateEventFrame(self)
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
		"PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING", "MERCHANT_SHOW",
		"MERCHANT_CLOSED", "MERCHANT_UPDATE", "PLAYER_MONEY" }) do
		events:RegisterEvent(event)
	end
	events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
	self.events = events
	self:ApplyLayout()
end

function Ammo:BAG_UPDATE_DELAYED()
	self:Update()
	if not self.buying then
		self:UpdateVendorButton()
	end
end

Ammo.PLAYER_ENTERING_WORLD = Ammo.Update
Ammo.PLAYER_EQUIPMENT_CHANGED = Ammo.BAG_UPDATE_DELAYED
Ammo.UNIT_INVENTORY_CHANGED = Ammo.BAG_UPDATE_DELAYED

-- A fight starting short of ammo gets a warning; the fight's ammo use feeds
-- the forecast.
function Ammo:PLAYER_REGEN_DISABLED()
	self:Update()
	if self.kind and self.count then
		self.fight = { start = GetTime(), count = self.count, itemID = self.itemID }
	end
	if not (self.db.lowAlert and self.kind) then
		return
	end
	if not self.itemID then
		self:Alert(L["Your ammo slot is empty."])
	elseif self.count == 0 then
		self:Alert(L["You're out of ammo."])
	elseif self.count and self.count < self.db.lowAmount then
		self:Alert(L["Running low on ammo: %d left."]:format(self.count))
	end
end

function Ammo:PLAYER_REGEN_ENABLED()
	self:Update() -- (and an ammo swap that waited for the fight to end)
	self:RecordFight(GetTime())
end

-- Leaving an inn or a city: a last chance to restock.
function Ammo:PLAYER_UPDATE_RESTING()
	if IsResting() or not (self.db.lowAlert and self.kind) then
		return
	end
	local now = GetTime()
	if self.leftTownAt and now - self.leftTownAt < LEAVING_QUIET_SECONDS then
		return
	end
	self:Update()
	local count = self.count
	local minutes = self:MinutesLeft(count)
	if count and count < self.db.lowAmount then
		self.leftTownAt = now
		self:Alert(L["You're heading out with only %d ammo."]:format(count))
	elseif minutes and minutes < LEAVING_MINUTES then
		self.leftTownAt = now
		self:Alert(L["You're heading out with about %d minutes of ammo."]:format(minutes))
	end
end

function Ammo:MERCHANT_SHOW()
	self.vendorOpen = true
	self:CreateVendorButton()
	self:UpdateVendorButton()
	if self.db.autoRestock then
		C_Timer.After(AUTO_BUY_SECONDS, function()
			if self.vendorOpen and not self.autoBought then
				self.autoBought = true
				self:Fill(true)
			end
		end)
	end
end

-- A purchase in progress stops on its next step and reports what it bought.
function Ammo:MERCHANT_CLOSED()
	self.vendorOpen, self.autoBought = false, nil
	self:UpdateVendorButton()
	self:Update() -- an ammo swap waits until you leave the vendor
end

function Ammo:MERCHANT_UPDATE()
	if not self.buying then
		self:UpdateVendorButton()
	end
end

Ammo.PLAYER_MONEY = Ammo.MERCHANT_UPDATE
