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

-- Backpacks nest, and a player who keeps balls in a pouch inside their bag is
-- not doing anything strange. Bounded so a pathological container tree cannot
-- turn one command into a long walk.
local MAX_DEPTH = 4

--- Walk a container, and its containers, handing every item to `visit`.
-- @return the first truthy thing `visit` returns
local function walk(container, visit, depth)
	if not container or depth > MAX_DEPTH then
		return nil
	end
	-- 0-based: `Container:getItem` goes through getItemByIndex.
	for i = 0, container:getSize() - 1 do
		local item = container:getItem(i)
		if item then
			local hit = visit(item)
			if hit then
				return hit
			end
			if item:isContainer() then
				local nested = walk(item, visit, depth + 1)
				if nested then
					return nested
				end
			end
		end
	end
	return nil
end

--- Every equipped slot, plus everything inside anything in them.
local function search(player, visit)
	for slot = CONST_SLOT_FIRST, CONST_SLOT_LAST do
		local item = player:getSlotItem(slot)
		if item then
			local hit = visit(item)
			if hit then
				return hit
			end
			if item:isContainer() then
				local nested = walk(item, visit, 1)
				if nested then
					return nested
				end
			end
		end
	end
	return nil
end

--- The ball holding this species, or nil.
local function findBall(player, wanted)
	local lowered = wanted:lower()
	return search(player, function(item)
		local mon = Pokemon.read(item)
		-- `read` returns nil for anything that is not a pokemon ball, which is
		-- what makes this safe to run over a whole inventory.
		if mon and mon.species:lower() == lowered then
			return item
		end
		return nil
	end)
end

--- What the player is actually carrying, for when the name does not match.
local function carried(player)
	local names, seen = {}, {}
	search(player, function(item)
		local mon = Pokemon.read(item)
		if mon and not seen[mon.species] then
			seen[mon.species] = true
			names[#names + 1] = mon.species .. (mon.fainted and " (fainted)" or "")
		end
		return nil -- never stop early: this is a census, not a lookup
	end)
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
