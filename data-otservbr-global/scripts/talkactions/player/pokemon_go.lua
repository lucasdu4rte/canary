-- !go <species> / !back  --  send one out and call it back, by name
--
-- The ball itself already does both (scripts/actions/pokemon_ball.lua) and
-- keeps doing them. This is the same two operations reached by typing, which is
-- how the source game plays it and what a bag of thirty balls needs: finding the
-- right sprite among thirty identical ones is not a skill worth testing.
--
-- Deliberately NOT a second implementation. Both commands resolve an item and
-- hand it to `Pokemon.summon` / `Pokemon.recall`, so every rule those own --
-- ownership, faint, level gate, one at a time -- applies here without being
-- restated. The only thing this file knows how to do is find a ball.

--- The ball holding this species, or nil.
--
-- ⚠️ A healthy one wins over a fainted one, and that is not a nicety. Carrying
-- two of a species is normal, and the first match wins otherwise -- so a trainer
-- with a fainted Charizard in the top slot and a fit one below would be told
-- "Charizard is unable to battle" while holding a Charizard that is perfectly
-- able. The refusal would be true about the ball and a lie about the bag.
--
-- Still returns the fainted one when it is the only one, because "unable to
-- battle" is the right answer then, and better than "you are not carrying a
-- Charizard" when you plainly are.
local function findBall(player, wanted)
	local lowered = wanted:lower()
	local fallback = nil
	for _, item in ipairs(Pokemon.carriedBalls(player)) do
		local mon = Pokemon.read(item)
		if mon and mon.species:lower() == lowered then
			if not mon.fainted then
				return item
			end
			fallback = fallback or item
		end
	end
	return fallback
end

--- What the player is actually carrying, for when the name does not match.
local function carried(player)
	local names, seen = {}, {}
	for _, item in ipairs(Pokemon.carriedBalls(player)) do
		local mon = Pokemon.read(item)
		if mon and not seen[mon.species] then
			seen[mon.species] = true
			names[#names + 1] = mon.species .. (mon.fainted and " (fainted)" or "")
		end
	end
	return names
end

local go = TalkAction("!go")

function go.onSay(player, words, param)
	local wanted = param:trim()

	-- No argument lists the bag rather than refusing. A player who cannot
	-- remember which of thirty balls they are carrying is exactly the player
	-- this command exists for.
	if wanted == "" then
		local names = carried(player)
		if #names == 0 then
			player:sendCancelMessage("You are not carrying any pokemon.")
		else
			player:sendTextMessage(MESSAGE_STATUS, "You are carrying: " .. table.concat(names, ", ") .. ".")
			player:sendTextMessage(MESSAGE_STATUS, "Usage: !go <species>")
		end
		return true
	end

	local item = findBall(player, wanted)
	if not item then
		player:sendCancelMessage(string.format("You are not carrying a %s.", wanted))
		return true
	end

	local mon = Pokemon.read(item)
	local creature, reason = Pokemon.summon(player, item)
	if not creature then
		player:sendCancelMessage(reason)
		return true
	end

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s, I choose you!", mon.species))
	creature:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

go:separator(" ")
go:groupType("normal")
go:register()

-- The other half. No argument: there is only ever one out, so naming it would
-- be asking the player to repeat something the server already knows.
local back = TalkAction("!back")

function back.onSay(player, words, param)
	local entry = Pokemon.getActive(player)
	if not entry then
		player:sendCancelMessage("You have no pokemon at your side.")
		return true
	end

	local mon = Pokemon.read(entry.item)
	Pokemon.recall(player)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
		string.format("%s, come back!", mon and mon.species or "Pokemon"))
	player:getPosition():sendMagicEffect(CONST_ME_POFF)
	return true
end

back:separator(" ")
back:groupType("normal")
back:register()
