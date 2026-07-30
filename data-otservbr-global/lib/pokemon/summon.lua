-- Sending a pokemon out and calling it back.
--
-- The link between player, creature and ball is **session state**, not
-- persisted. That is a choice, and it pays: a server crash leaves no orphan,
-- because nothing on disk ever claims a pokemon is out. It comes back up
-- clean, everyone in their ball -- without the boot-time normalisation the
-- earlier designs needed.
--
-- In exchange, HP only reaches the item at three moments: recall, faint and
-- logout. Damage does **not** persist mid-combat. The worst outcome of a
-- crash is the player getting health back, which is far too cheap to justify
-- a write per tick.

Pokemon = Pokemon or {}

-- [playerId] = { creature = <Monster>, item = <Item> }
local active = {}

--- The pokemon this player currently has out of its ball, if any.
function Pokemon.getActive(player)
	local entry = active[player:getId()]
	if not entry then
		return nil
	end
	-- The creature may have died or vanished without going through recall.
	if not entry.creature or entry.creature:isRemoved() then
		active[player:getId()] = nil
		return nil
	end
	return entry
end

--- Send the pokemon out of its ball.
-- @return the creature, or nil plus a reason
function Pokemon.summon(player, item)
	local mon = Pokemon.read(item)
	if not mon then
		return nil, "That is not a pokemon."
	end

	if mon.fainted then
		return nil, string.format("%s is fainted and cannot be sent out.", mon.species)
	end

	if Pokemon.getActive(player) then
		return nil, "You already have a pokemon out."
	end

	-- The game's progression gate: catching above your level is legitimate,
	-- using it is not. The check belongs to the server, always.
	local required = mon.speciesData.minPlayerLevel
	if required and player:getLevel() < required then
		return nil, string.format("%s requires level %d; you are level %d.",
			mon.species, required, player:getLevel())
	end

	-- extended + force: `placeCreature` refuses a protection zone and an
	-- occupied tile when `force` is false, and that is what made summoning
	-- answer "could not send out" inside a temple. Sending a pokemon out is
	-- something the player asked for -- it should not fail because of the
	-- floor.
	--
	-- The master goes in the fifth argument rather than a `setMaster` call
	-- afterwards: the C++ applies it **before** placing, so the creature
	-- exists as a summon from the first moment.
	local creature = Game.createMonster(
		Pokemon.monsterName(mon.species), player:getPosition(), true, true, player)
	if not creature then
		return nil, string.format("Could not send out %s.", mon.species)
	end

	-- The creature's health mirrors the fraction stored on the item, scaled by
	-- the level of whoever is sending it out now.
	local maxHp = mon.stats and mon.stats.hp or mon.speciesData.baseStats.hp
	creature:setMaxHealth(maxHp)
	creature:addHealth(maxHp - creature:getHealth())
	local current = math.max(1, math.floor(maxHp * mon.hpRatio))
	creature:addHealth(current - creature:getHealth())

	-- The ball is empty now, and it has to look empty. `syncVisual` can hand
	-- back a different object, so the session keeps what it returns rather
	-- than the reference we were passed.
	active[player:getId()] = { creature = creature, item = Pokemon.syncVisual(item, true) }
	return creature
end

--- Put the pokemon back, storing the health it returned with.
-- @return true if there was anything to recall
function Pokemon.recall(player)
	local entry = Pokemon.getActive(player)
	if not entry then
		return false
	end

	local creature, item = entry.creature, entry.item
	active[player:getId()] = nil

	-- The only write point for combat state, together with recordFaint.
	if item then
		local maxHp = creature:getMaxHealth()
		local ratio = maxHp > 0 and (creature:getHealth() / maxHp) or 0
		Pokemon.recordReturn(item, math.max(0.0, math.min(1.0, ratio)))
		-- Occupied again, so the icon goes back to colour.
		Pokemon.syncVisual(item, false)
	end

	creature:remove()
	return true
end

--- Fainting: drop the session and mark the item.
--
-- Two callers with opposite needs, which is why the removal is conditional
-- rather than unconditional:
--   * the pokemon died -- the engine is already disposing of it, and calling
--     `remove()` from inside its own `onDeath` is asking for trouble
--   * something forced the faint while it was still standing -- then this is
--     the one that has to take it off the map
--
-- Zero health is what tells the two apart, and it is the truth of the
-- situation rather than a flag a caller could get wrong.
function Pokemon.faint(player)
	local entry = Pokemon.getActive(player)
	if not entry then
		return false
	end
	local item = entry.item
	active[player:getId()] = nil

	local creature = entry.creature
	if creature and not creature:isRemoved() and creature:getHealth() > 0 then
		creature:remove()
	end
	if item then
		Pokemon.recordFaint(item)
	end
	return true
end

--- Used by the trainer protection: does this player have a pokemon in play?
function Pokemon.hasActive(player)
	return Pokemon.getActive(player) ~= nil
end

--- Drop the entry for a player who left.
function Pokemon.clearSession(player)
	active[player:getId()] = nil
end
