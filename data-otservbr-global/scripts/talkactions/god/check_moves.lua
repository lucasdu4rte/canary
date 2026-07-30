-- /check-moves
--
-- Walks every move every species references and reports the ones the catalogue
-- cannot describe. Expected output is zero.
--
-- A gap here does not raise: it deals no damage, silently, and reads exactly
-- like a broken button. `tools/data/moves.ts` already refuses to build with a
-- hole in it, but that guards the builder -- this guards what actually shipped,
-- which is the emitted Lua the server loaded.
--
-- `power == 0` is NOT a gap: 102 of the 360 moves have no damage yet, and those
-- are meant to refuse with a message. Counted apart so the two never get
-- confused for one another.

local VALID_CLASSES = { physical = true, special = true, status = true }
local VALID_BEHAVIORS = { target = true, aoe = true, self = true }

local checkMoves = TalkAction("/check-moves")

function checkMoves.onSay(player, words, param)
	logCommand(player, words, param)

	local missing, malformed = {}, {}
	local seen, references, zeroPower = {}, 0, 0

	for species, data in pairs(PokemonSpecies) do
		for _, entry in ipairs(data.moves or {}) do
			references = references + 1
			local move = PokemonMoves[entry.name]
			if not move then
				missing[#missing + 1] = string.format("%s: %s", species, entry.name)
			elseif not seen[entry.name] then
				seen[entry.name] = true
				local why = nil
				if type(move.power) ~= "number" then
					why = "power is not a number"
				elseif not move.type or move.type == "" then
					why = "no type"
				elseif not VALID_CLASSES[move.damageClass] then
					why = "bad damageClass " .. tostring(move.damageClass)
				elseif not VALID_BEHAVIORS[move.behavior] then
					why = "bad behavior " .. tostring(move.behavior)
				elseif type(move.range) ~= "number" or move.range < 1 then
					why = "bad range " .. tostring(move.range)
				end
				if why then
					malformed[#malformed + 1] = string.format("%s: %s", entry.name, why)
				elseif move.power == 0 then
					zeroPower = zeroPower + 1
				end
			end
		end
	end

	local distinct = 0
	for _ in pairs(seen) do
		distinct = distinct + 1
	end

	player:sendTextMessage(MESSAGE_ADMINISTRATOR, string.format(
		"Moves: %d references, %d distinct, %d without damage (these refuse with a message).",
		references, distinct, zeroPower))

	-- Capped because sendTextMessage is one line per call and a broken build
	-- would flood the client with hundreds. The count is the real answer; the
	-- list is only there to point at where to look.
	for _, list in ipairs({ { "MISSING FROM CATALOGUE", missing }, { "MALFORMED", malformed } }) do
		local label, entries = list[1], list[2]
		if #entries > 0 then
			player:sendTextMessage(MESSAGE_ADMINISTRATOR, string.format("%s: %d", label, #entries))
			for i = 1, math.min(#entries, 20) do
				player:sendTextMessage(MESSAGE_ADMINISTRATOR, "  " .. entries[i])
			end
			if #entries > 20 then
				player:sendTextMessage(MESSAGE_ADMINISTRATOR, string.format("  ... and %d more", #entries - 20))
			end
		end
	end

	if #missing == 0 and #malformed == 0 then
		player:sendTextMessage(MESSAGE_ADMINISTRATOR, "OK - every referenced move is fully described.")
		player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	else
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
	end
	return true
end

checkMoves:separator(" ")
checkMoves:groupType("god")
checkMoves:register()
