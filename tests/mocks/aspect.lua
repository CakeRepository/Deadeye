-- Your buffs and aspects (Modules\Aspect.lua). See MOCK_FILES in tests/harness.lua.
--   W.buffs                    your buffs: { name =, spellID =, auraInstanceID = }
--   W.aspectsReadableInCombat  true: the client lets addons read aspect auras in combat
--   W.knownSpells[spellID]     spells you know (none by default, so other tests get no warnings)
--   W.CastAspect(spellID)      casts an aspect, which replaces the one you had
--   W.AddBuff(name, spellID), W.CancelBuff(name)
-- In combat, aura details come back empty (secret), unless allowed above; aura
-- instance IDs stay plain numbers unless W.auraIDsHidden.
local ASPECTS = {
	[13165] = "Aspect of the Hawk", [13163] = "Aspect of the Monkey", [5118] = "Aspect of the Cheetah",
	[13159] = "Aspect of the Pack", [13161] = "Aspect of the Beast", [20043] = "Aspect of the Wild",
	[14322] = "Aspect of the Hawk", -- a higher rank
}

return function(W, env, M)
	local check = M.check
	for spellID, name in pairs(ASPECTS) do
		W.spellNames[spellID] = name
	end
	W.buffs = {}
	W.aspectsReadableInCombat = false
	W.knownSpells = {}
	local nextAuraID = 500

	local function IsAspect(name)
		for _, aspect in pairs(ASPECTS) do
			if aspect == name then
				return true
			end
		end
		return false
	end

	function W.AddBuff(name, spellID)
		nextAuraID = nextAuraID + 1
		W.buffs[#W.buffs + 1] = { name = name, spellID = spellID, auraInstanceID = nextAuraID }
		W.Fire("UNIT_AURA", "player", {})
		return nextAuraID
	end

	function W.CancelBuff(name)
		for i = #W.buffs, 1, -1 do
			if W.buffs[i].name == name then
				table.remove(W.buffs, i)
			end
		end
		W.Fire("UNIT_AURA", "player", {})
	end

	-- The cast event, then its aura in place of the old aspect's.
	function W.CastAspect(spellID)
		W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-" .. spellID, spellID)
		for i = #W.buffs, 1, -1 do
			if IsAspect(W.buffs[i].name) then
				table.remove(W.buffs, i)
			end
		end
		return W.AddBuff(ASPECTS[spellID], spellID)
	end

	local baseByName = env.C_UnitAuras.GetAuraDataBySpellName
	env.C_UnitAuras.GetAuraDataBySpellName = function(unit, name, filter)
		if unit ~= "player" then
			return baseByName(unit, name, filter)
		end
		check(filter == "HELPFUL", "GetAuraDataBySpellName: unexpected filter for the player")
		if W.inCombat and not (IsAspect(name) and W.aspectsReadableInCombat) then
			return nil -- RequiresNonSecretAura: nothing while the aura is secret
		end
		for _, buff in ipairs(W.buffs) do
			if buff.name == name then
				return { name = buff.name, spellId = buff.spellID, auraInstanceID = buff.auraInstanceID }
			end
		end
		return nil
	end

	local baseIDs = env.C_UnitAuras.GetUnitAuraInstanceIDs
	env.C_UnitAuras.GetUnitAuraInstanceIDs = function(unit, filter)
		if unit ~= "player" then
			return baseIDs(unit, filter)
		end
		check(filter == "HELPFUL|PLAYER", "GetUnitAuraInstanceIDs: unexpected filter for the player " .. tostring(filter))
		local ids = {}
		if W.inCombat and W.auraIDsHidden then
			return ids
		end
		for i, buff in ipairs(W.buffs) do
			ids[i] = buff.auraInstanceID
		end
		return ids
	end

	local baseSecret = env.C_Secrets.ShouldSpellAuraBeSecret
	env.C_Secrets.ShouldSpellAuraBeSecret = function(spell)
		if ASPECTS[spell] then
			return W.inCombat and not W.aspectsReadableInCombat
		end
		return baseSecret(spell)
	end

	env.C_SpellBook = {
		IsSpellKnown = function(spellID)
			check(M.isNumber(spellID), "C_SpellBook.IsSpellKnown: spell id expected")
			return W.knownSpells[spellID] == true
		end,
	}
end
