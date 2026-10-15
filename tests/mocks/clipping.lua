-- Casting, for the shot-clipping tests (see MOCK_FILES in tests/harness.lua):
-- the spells a hunter casts between shots, what C_Spell.GetSpellInfo lists for
-- them, and UnitCastingInfo / UnitChannelInfo for the cast in progress.
--
-- Forever's API docs flag the cast events and both cast-info functions
-- SecretWhenUnitSpellCastRestricted: secret for units other than the player
-- and their pet, and for spells flagged as always secret. W.StartCast(...,
-- true) casts such a spell, so its event payloads and cast info come back
-- secret. Only isTradeskill, castBarID and delayTimeMs are NeverSecret.
-- C_Spell.GetSpellInfo has no secret returns.
return function(W, env, M)
	local check, H = M.check, M.H

	for id, name in pairs({
		[19434] = "Aimed Shot", [20904] = "Aimed Shot", -- ranks 1 and 6
		[2643] = "Multi-Shot", [25294] = "Multi-Shot", -- ranks 1 and 5
		[1513] = "Scare Beast", [1510] = "Volley", [1978] = "Serpent Sting",
	}) do
		W.spellNames[id] = W.spellNames[id] or name
	end
	-- castTime as C_Spell.GetSpellInfo lists it, in ms. Classic lists Multi-Shot
	-- as instant; Volley is a channel.
	W.listedCastMs = { [19434] = 3000, [20904] = 3000, [2643] = 0, [25294] = 0, [1513] = 1500, [1510] = 0, [1978] = 0 }
	-- Spells you know, by name, with the rank you know: a lookup by name only finds these.
	W.knownSpells = {}
	W.cast = nil -- the cast or channel in progress (see W.StartCast)

	local function SpellInfo(id)
		return { name = W.spellNames[id], iconID = 135130, originalIconID = 135130, castTime = W.listedCastMs[id],
			minRange = 0, maxRange = 35, spellID = id }
	end

	local GetSpellInfo = env.C_Spell.GetSpellInfo
	env.C_Spell.GetSpellInfo = function(spell)
		if type(spell) == "string" then
			if W.knownSpells[spell] then
				return SpellInfo(W.knownSpells[spell])
			end
			for id in pairs(W.listedCastMs) do
				if W.spellNames[id] == spell then
					return nil -- not in your spellbook
				end
			end
		elseif M.isNumber(spell) and W.listedCastMs[spell] then
			return SpellInfo(spell)
		end
		if GetSpellInfo then
			return GetSpellInfo(spell)
		end
	end

	local function Hidden(cast, value)
		if cast.secret and value ~= nil then
			return H.Secret(value)
		end
		return value
	end

	-- Times are in ms on GetTime()'s clock, as the client gives them.
	local UnitCastingInfo, UnitChannelInfo = env.UnitCastingInfo, env.UnitChannelInfo
	env.UnitCastingInfo = function(unit)
		if unit ~= "player" then
			check(UnitCastingInfo, "UnitCastingInfo: only the player is mocked")
			return UnitCastingInfo(unit)
		end
		local cast = W.cast
		if not cast or cast.channel then
			return nil
		end
		local name = W.spellNames[cast.spellID]
		return Hidden(cast, name), Hidden(cast, name), Hidden(cast, 135130), Hidden(cast, cast.startMs),
			Hidden(cast, cast.endMs), false, Hidden(cast, cast.guid), Hidden(cast, false), Hidden(cast, cast.spellID),
			nil, cast.delayMs
	end
	env.UnitChannelInfo = function(unit)
		if unit ~= "player" then
			check(UnitChannelInfo, "UnitChannelInfo: only the player is mocked")
			return UnitChannelInfo(unit)
		end
		local cast = W.cast
		if not (cast and cast.channel) then
			return nil
		end
		local name = W.spellNames[cast.spellID]
		return Hidden(cast, name), Hidden(cast, name), Hidden(cast, 135130), Hidden(cast, cast.startMs),
			Hidden(cast, cast.endMs), false, Hidden(cast, false), Hidden(cast, cast.spellID), false, 0, nil
	end

	-- The cast events' castGUID and spellID.
	local function Payload(cast)
		if cast.secret then
			return H.Secret(cast.guid), H.Secret(cast.spellID)
		end
		return cast.guid, cast.spellID
	end

	local casts = 0
	local function Begin(spellID, ms, secret, channel)
		casts = casts + 1
		local startMs = W.now * 1000
		W.cast = { spellID = spellID, guid = "Cast-" .. casts, startMs = startMs, endMs = startMs + ms,
			delayMs = 0, secret = secret, channel = channel }
	end

	-- You start casting spellID. ms is how long the cast really takes (by default
	-- its listed cast time); secret makes it a spell flagged as always secret.
	function W.StartCast(spellID, ms, secret)
		Begin(spellID, ms or W.listedCastMs[spellID], secret, false)
		W.Fire("UNIT_SPELLCAST_START", "player", Payload(W.cast))
	end

	function W.StartChannel(spellID, ms)
		Begin(spellID, ms, false, true)
		W.Fire("UNIT_SPELLCAST_CHANNEL_START", "player", Payload(W.cast))
	end

	-- The cast completes (or the channel runs out).
	function W.FinishCast()
		local cast = W.cast
		W.cast = nil
		if cast.channel then
			W.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player", Payload(cast))
		else
			W.Fire("UNIT_SPELLCAST_STOP", "player", Payload(cast))
			W.Fire("UNIT_SPELLCAST_SUCCEEDED", "player", Payload(cast))
		end
	end

	-- Moving or a kick stops the cast.
	function W.InterruptCast()
		local cast = W.cast
		W.cast = nil
		W.Fire("UNIT_SPELLCAST_INTERRUPTED", "player", Payload(cast))
		W.Fire("UNIT_SPELLCAST_STOP", "player", Payload(cast))
	end

	-- A hit pushes the cast back by ms, or takes ms off a channel.
	function W.PushBack(ms)
		local cast = W.cast
		if cast.channel then
			cast.endMs = cast.endMs - ms
			W.Fire("UNIT_SPELLCAST_CHANNEL_UPDATE", "player", Payload(cast))
		else
			cast.endMs, cast.delayMs = cast.endMs + ms, cast.delayMs + ms
			W.Fire("UNIT_SPELLCAST_DELAYED", "player", Payload(cast))
		end
	end
end
