-- !move <name> and !moves
--
-- The order channel for phase 4. Phase 6 replaces it with a client UI; the
-- executor it calls does not change, because the rules live in the server and
-- this only carries the intent.
--
-- Every refusal comes back as a message. Silence is what makes a working move
-- and a broken one look the same, and 102 of the 360 moves deal no damage yet.

local useMove = TalkAction("!move")

function useMove.onSay(player, words, param)
	local wanted = param:trim()
	if wanted == "" then
		player:sendCancelMessage("Usage: !move <name> -- see !moves for the list.")
		return true
	end

	-- Resolved case-insensitively against what this pokemon knows. Typing
	-- "Hydro Pump" with exact capitals is not a skill worth testing.
	local entry = Pokemon.getActive(player)
	if not entry then
		player:sendCancelMessage("You have no pokemon at your side.")
		return true
	end

	local mon = Pokemon.read(entry.item)
	local species = mon and PokemonSpecies[Pokemon.effectiveSpecies(mon)]
	if not species then
		player:sendCancelMessage("That pokemon cannot be read.")
		return true
	end

	local resolved = nil
	local lowered = wanted:lower()
	for _, known in ipairs(species.moves or {}) do
		if known.name:lower() == lowered then
			resolved = known.name
			break
		end
	end

	local ok, reason = Pokemon.useMove(player, resolved or wanted)
	if not ok then
		player:sendCancelMessage(reason)
	end
	return true
end

useMove:separator(" ")
useMove:groupType("normal")
useMove:register()

-- Listing what a pokemon knows, with cooldowns, is the difference between
-- trying moves at random and playing. It also surfaces the two refusals a
-- player would otherwise only meet by hitting them.
local listMoves = TalkAction("!moves")

function listMoves.onSay(player, words, param)
	local entry = Pokemon.getActive(player)
	if not entry then
		player:sendCancelMessage("You have no pokemon at your side.")
		return true
	end

	local mon = Pokemon.read(entry.item)
	local species = mon and PokemonSpecies[Pokemon.effectiveSpecies(mon)]
	if not species then
		player:sendCancelMessage("That pokemon cannot be read.")
		return true
	end

	local known = species.moves or {}
	if #known == 0 then
		player:sendTextMessage(MESSAGE_STATUS, string.format("%s knows no moves.", mon.species))
		return true
	end

	player:sendTextMessage(MESSAGE_STATUS, string.format("%s knows:", mon.species))
	for _, item in ipairs(known) do
		local move = PokemonMoves[item.name]
		local state
		if not move then
			state = "unavailable"
		elseif move.power <= 0 then
			state = "no effect yet"
		else
			local left = Pokemon.moveCooldownLeft(entry.item, item.name)
			state = left > 0
				and string.format("%ds left", left)
				or string.format("pw %d, %s, reach %d, %s",
					move.power, move.type, move.range, move.behavior)
		end
		player:sendTextMessage(MESSAGE_STATUS, string.format("  %s - %s", item.name, state))
	end
	return true
end

listMoves:separator(" ")
listMoves:groupType("normal")
listMoves:register()
