-- Enemies and their buffs, for the Tranquilizing Shot callout (Modules\Tranq.lua).
-- See MOCK_FILES in tests/harness.lua.
--   W.tranqKnown           you know Tranquilizing Shot (not by default, so other tests don't get its page)
--   W.mobs[key]            an enemy: { buffs = { aura, ... }, combat =, threat =, dead =, player = } (W.AddMob)
--   W.unitMob[unit]        the enemy target, focus, boss1..5 or nameplateN shows (W.ShowMob)
--   aura                   { auraInstanceID =, spellId =, name =, icon =, dispelName =, removable = }
--                            (W.Buff); dispelName "" is the enrage type; removable = false
--                            leaves it out of the RAID_PLAYER_DISPELLABLE filter
--   W.readableInCombat[id] spell IDs the client flags as never secret
--   W.auraDataOpaque       in combat, aura data comes back as one secret value
--   W.playerDead           UnitIsDeadOrGhost("player")
--   W.chatLockdown         C_ChatInfo.InChatMessagingLockdown()
--   W.group                nil, "party" or "raid"; W.chat lists the messages sent
-- As the API docs say: in combat the aura data and UNIT_AURA's payload are
-- secret (SecretWhenUnitAuraRestricted, SecretWhenAurasRestricted) unless a
-- spell is flagged never secret, and lookups that need a readable aura return
-- nothing (RequiresNonSecretAura). Aura instance IDs stay plain numbers unless
-- W.auraIDsHidden. Chat events aren't mocked: their text is secret in raids.
local TRANQ = 19801
local SPELLS = {
	[TRANQ] = { "Tranquilizing Shot", 136020 },
	[19451] = { "Frenzy", 136224 }, -- Magmadar
	[23342] = { "Frenzy", 136224 }, -- Flamegor
	[23128] = { "Frenzy", 136224 }, -- Chromaggus
	[26051] = { "Frenzy", 136224 }, -- Princess Huhuran
	[28371] = { "Frenzy", 136224 }, -- Gluth
	[19714] = { "Deaden Magic", 136070 }, -- Shazzrah's, a magic buff a priest purges
	[16170] = { "Bloodlust", 136012 }, -- another magic buff
}
local DISPELLABLE_FILTER = "HELPFUL|RAID_PLAYER_DISPELLABLE"
local GAME_ERRORS = { [20] = "SPELL_FAILED_NOTHING_TO_DISPEL" }

return function(W, env, M)
	local check, H = M.check, M.H
	for spellID, spell in pairs(SPELLS) do
		W.spellNames[spellID] = W.spellNames[spellID] or spell[1]
		W.spellTextures[spellID] = W.spellTextures[spellID] or spell[2]
	end
	W.tranqKnown = M.options.tranqKnown == true
	W.mobs = {}
	W.unitMob = {}
	W.readableInCombat = {}
	W.auraDataOpaque = false
	W.chatLockdown = false
	W.group = nil
	W.chat = {}
	local nextAuraID = 900

	local function Mob(unit)
		local key = type(unit) == "string" and W.unitMob[unit]
		return key and W.mobs[key]
	end

	local function Hidden(aura)
		return W.inCombat and not W.readableInCombat[aura.spellId]
	end

	local function FindAura(unit, id)
		local mob = Mob(unit)
		for _, aura in ipairs(mob and mob.buffs or {}) do
			if aura.auraInstanceID == id then
				return aura
			end
		end
	end

	local function AuraData(aura)
		local data = {}
		for key, value in pairs(aura) do
			if key ~= "removable" then
				data[key] = value
			end
		end
		data.isHelpful, data.isHarmful = true, false
		if not Hidden(aura) then
			return data
		end
		if W.auraDataOpaque then
			return H.Secret(data)
		end
		for key, value in pairs(data) do
			if key ~= "auraInstanceID" then
				data[key] = H.Secret(value)
			end
		end
		return data
	end

	-- Every unit that shows this enemy gets a UNIT_AURA, secret in combat.
	local function AurasChanged(key)
		for unit, shown in pairs(W.unitMob) do
			if shown == key then
				if W.inCombat then
					W.Fire("UNIT_AURA", H.Secret(unit), H.Secret({ isFullUpdate = true }))
				else
					W.Fire("UNIT_AURA", unit, { isFullUpdate = true })
				end
			end
		end
	end

	function W.AddMob(key, fields)
		local mob = { buffs = {} }
		for field, value in pairs(fields or {}) do
			mob[field] = value
		end
		W.mobs[key] = mob
		return mob
	end

	-- unit starts showing the enemy key (nil: nothing), with the client's event for it.
	function W.ShowMob(unit, key)
		W.unitMob[unit] = key
		if unit == "target" then
			W.hasTarget = key ~= nil
			W.Fire("PLAYER_TARGET_CHANGED")
		elseif unit == "focus" then
			W.Fire("PLAYER_FOCUS_CHANGED")
		elseif unit:find("^boss") then
			W.Fire("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
		else
			local index = tonumber(unit:match("^nameplate(%d+)$"))
			check(index, "ShowMob: unexpected unit " .. unit)
			W.plates[index] = W.plates[index] or { debuffs = {} }
			W.Fire(key and "NAME_PLATE_UNIT_ADDED" or "NAME_PLATE_UNIT_REMOVED", unit)
		end
	end

	-- The enemy gains a buff (by default one your group can remove); returns its aura instance ID.
	function W.Buff(key, spellID, fields)
		nextAuraID = nextAuraID + 1
		local aura = { auraInstanceID = nextAuraID, spellId = spellID, name = W.spellNames[spellID],
			icon = W.spellTextures[spellID], dispelName = "" }
		for field, value in pairs(fields or {}) do
			aura[field] = value
		end
		table.insert(W.mobs[key].buffs, aura)
		AurasChanged(key)
		return nextAuraID
	end

	function W.Unbuff(key, id)
		local buffs = W.mobs[key].buffs
		for i = #buffs, 1, -1 do
			if buffs[i].auraInstanceID == id then
				table.remove(buffs, i)
			end
		end
		AurasChanged(key)
	end

	function W.CastTranq()
		W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-Tranq", TRANQ)
	end

	-- The client refuses the cast: its error message, then the failed cast.
	function W.FailTranq(errorIndex, message)
		W.Fire("UI_ERROR_MESSAGE", errorIndex, message)
		W.Fire("UNIT_SPELLCAST_FAILED", "player", "Cast-Tranq", TRANQ)
	end

	-- Units. target and nameplates keep the harness's own state unless they show a mob.
	local UnitExists, UnitCanAttack, UnitIsDead = env.UnitExists, env.UnitCanAttack, env.UnitIsDead
	local UnitAffectingCombat = env.UnitAffectingCombat
	env.UnitExists = function(unit)
		if Mob(unit) then
			return true
		elseif unit == "focus" or (type(unit) == "string" and unit:find("^boss%d$")) then
			return false
		end
		return UnitExists(unit)
	end
	env.UnitCanAttack = function(unit, other)
		if Mob(other) then
			check(unit == "player", "UnitCanAttack: only the player attacks")
			return Mob(other).friendly ~= true
		end
		return UnitCanAttack(unit, other)
	end
	env.UnitIsDead = function(unit)
		if Mob(unit) then
			return Mob(unit).dead == true
		end
		return UnitIsDead(unit)
	end
	-- An enemy is in combat while you are, unless its combat field says otherwise.
	env.UnitAffectingCombat = function(unit)
		local mob = Mob(unit)
		if mob then
			if mob.combat ~= nil then
				return mob.combat
			end
			return W.inCombat
		end
		return UnitAffectingCombat(unit)
	end
	local UnitIsDeadOrGhost = env.UnitIsDeadOrGhost
	env.UnitIsDeadOrGhost = function(unit)
		if unit == "player" then
			return W.playerDead == true
		end
		check(UnitIsDeadOrGhost, "UnitIsDeadOrGhost: only the player is mocked")
		return UnitIsDeadOrGhost(unit)
	end
	local UnitPlayerControlled = env.UnitPlayerControlled
	env.UnitPlayerControlled = function(unit)
		local mob = Mob(unit)
		if mob then
			return mob.player == true -- an enemy player
		elseif UnitPlayerControlled then
			return UnitPlayerControlled(unit)
		end
		return unit == "player" or unit == "pet"
	end
	-- nil when you aren't on the enemy's threat list; readable for the player
	-- against an enemy (SecretWhenUnitThreatStateRestricted).
	env.UnitThreatSituation = function(unit, mobUnit)
		check(unit == "player", "UnitThreatSituation: only the player's threat is mocked")
		local mob = Mob(mobUnit)
		if not (mob and W.inCombat) or mob.threat == false then
			return nil
		end
		return mob.threat or 1
	end

	-- Looking a spell up by name only finds it once you know it.
	local GetSpellName = env.C_Spell.GetSpellName
	env.C_Spell.GetSpellName = function(spell)
		if type(spell) == "string" and spell == W.spellNames[TRANQ] then
			return W.tranqKnown and spell or nil
		end
		return GetSpellName(spell)
	end

	local GetUnitAuraInstanceIDs = env.C_UnitAuras.GetUnitAuraInstanceIDs
	env.C_UnitAuras.GetUnitAuraInstanceIDs = function(unit, filter)
		if filter ~= DISPELLABLE_FILTER then
			return GetUnitAuraInstanceIDs(unit, filter)
		end
		local ids = {}
		if W.inCombat and W.auraIDsHidden then
			return ids
		end
		local mob = Mob(unit)
		for _, aura in ipairs(mob and mob.buffs or {}) do
			if aura.removable ~= false then
				ids[#ids + 1] = aura.auraInstanceID
			end
		end
		return ids
	end
	env.C_UnitAuras.GetAuraDataByAuraInstanceID = function(unit, id)
		check(M.isNumber(id), "GetAuraDataByAuraInstanceID: plain aura instance ID expected")
		local aura = FindAura(unit, id)
		return aura and AuraData(aura)
	end
	env.C_UnitAuras.GetUnitAuraBySpellID = function(unit, spellID)
		check(M.isNumber(spellID), "GetUnitAuraBySpellID: spell id expected")
		local mob = Mob(unit)
		for _, aura in ipairs(mob and mob.buffs or {}) do
			if aura.spellId == spellID and not Hidden(aura) then
				return AuraData(aura)
			end
		end
		return nil
	end

	local ShouldSpellAuraBeSecret = env.C_Secrets.ShouldSpellAuraBeSecret
	env.C_Secrets.ShouldSpellAuraBeSecret = function(spell)
		if SPELLS[spell] then
			return W.inCombat and not W.readableInCombat[spell]
		end
		return ShouldSpellAuraBeSecret(spell)
	end
	env.C_Secrets.ShouldUnitAuraInstanceBeSecret = function(unit, id)
		check(M.isNumber(id), "ShouldUnitAuraInstanceBeSecret: plain aura instance ID expected")
		local aura = FindAura(unit, id)
		if aura then
			return Hidden(aura)
		end
		return W.inCombat
	end

	local GetGameMessageInfo = env.GetGameMessageInfo
	env.GetGameMessageInfo = function(index)
		return GAME_ERRORS[index] or GetGameMessageInfo(index)
	end

	env.IsInRaid = function()
		return W.group == "raid"
	end
	env.IsInGroup = function()
		return W.group ~= nil
	end
	env.C_ChatInfo = env.C_ChatInfo or {}
	env.C_ChatInfo.InChatMessagingLockdown = function()
		return W.chatLockdown
	end
	env.C_ChatInfo.SendChatMessage = function(message, chatType)
		check(type(message) == "string", "SendChatMessage: plain text expected (secret arguments aren't allowed for addons)")
		check(chatType == "PARTY" or chatType == "RAID", "SendChatMessage: only group chat is expected, got " .. tostring(chatType))
		if W.chatLockdown then
			W.blocked[#W.blocked + 1] = "SendChatMessage during chat messaging lockdown"
			return
		end
		W.chat[#W.chat + 1] = { text = message, channel = chatType }
	end

	-- The callout's icon gets the buff's own icon, which is secret in combat:
	-- Texture:SetTexture takes secret values (SecretArguments = "AllowedWhenTainted").
	local CreateFrame = env.CreateFrame
	env.CreateFrame = function(frameType, name, ...)
		local frame = CreateFrame(frameType, name, ...)
		if name == "DeadeyeTranqFrame" then
			local CreateTexture = frame.CreateTexture
			function frame:CreateTexture(...)
				local texture = CreateTexture(self, ...)
				local SetTexture = texture.SetTexture
				function texture:SetTexture(asset)
					if M.isSecret(asset) then
						self.texture = asset
						return
					end
					SetTexture(self, asset)
				end
				return texture
			end
		end
		return frame
	end
end
