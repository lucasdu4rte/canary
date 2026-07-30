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

-- How far from the trainer a pokemon comes out, best first. Two tiles leaves a
-- gap; one puts it shoulder to shoulder, which reads as if it were stuck to
-- them but still beats the last resort of coming out *inside* the trainer.
--
-- The second entry earns its place when a trainer is surrounded: cornered by
-- wild pokemon the ring at two tiles can be full while a neighbouring tile is
-- free, and standing next to someone looks far better than overlapping them.
local SUMMON_DISTANCES = { 2, 1 }

-- Offsets in the order `Direction_t` declares them, so a direction indexes
-- straight into this.
local STEP = {
	[DIRECTION_NORTH] = { x = 0, y = -1 },
	[DIRECTION_EAST] = { x = 1, y = 0 },
	[DIRECTION_SOUTH] = { x = 0, y = 1 },
	[DIRECTION_WEST] = { x = -1, y = 0 },
	[DIRECTION_SOUTHWEST] = { x = -1, y = 1 },
	[DIRECTION_SOUTHEAST] = { x = 1, y = 1 },
	[DIRECTION_NORTHWEST] = { x = -1, y = -1 },
	[DIRECTION_NORTHEAST] = { x = 1, y = -1 },
}

--- Can a pokemon stand here?
--
-- Checked before the creature exists, so it cannot use `queryAdd` -- these are
-- the conditions that would make `placeCreature` refuse, asked of the tile
-- directly.
local function standable(pos)
	local tile = Tile(pos)
	return tile ~= nil
		and tile:getGround() ~= nil
		and not tile:hasProperty(CONST_PROP_BLOCKSOLID)
		and not tile:hasFlag(TILESTATE_FLOORCHANGE)
		and not tile:hasFlag(TILESTATE_TELEPORT)
		and tile:getCreatureCount() == 0
end

--- Where to put a pokemon that its trainer is sending out.
--
-- Two tiles away, starting with the direction the trainer is facing so it
-- appears in front of them, and walking round the compass from there. If that
-- whole ring is taken it tries one tile out before giving up.
--
-- Sight is checked as well as footing: two tiles out can be on the far side of
-- a wall, and a pokemon materialising in the next room is worse than one
-- standing close.
--
-- @return a free position, or the trainer's own when every side is blocked --
--         in which case it comes out on top of them rather than not at all.
local function spotFor(player)
	local origin = player:getPosition()
	local facing = player:getDirection()

	-- Facing first, then everything else. `pairs` would do neither in a
	-- predictable order, and "wherever the table felt like" is not a rule.
	local order = { facing }
	for direction in pairs(STEP) do
		if direction ~= facing then
			order[#order + 1] = direction
		end
	end

	-- Distance is the outer loop: a free tile two away is preferred over every
	-- tile one away, whichever direction each happens to be in.
	for _, distance in ipairs(SUMMON_DISTANCES) do
		for _, direction in ipairs(order) do
			local step = STEP[direction]
			if step then
				local candidate = Position(origin.x + step.x * distance, origin.y + step.y * distance, origin.z)
				if standable(candidate) and origin:isSightClear(candidate, true) then
					return candidate
				end
			end
		end
	end

	return origin
end

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

	-- It has to be yours, and you have to be carrying it.
	--
	-- Without this a ball lying on the floor could be used where it lay --
	-- including someone else's, dropped a moment ago. `read` resolves the
	-- holder by walking the item up to whichever player is carrying it, so a
	-- ball on the ground, in a depot or inside a container on the ground all
	-- come back with no holder at all.
	--
	-- The check lives here rather than in the Action so that phase 5's capture,
	-- and anything else that ever sends a pokemon out, inherits it.
	if not mon.holder or mon.holder:getId() ~= player:getId() then
		return nil, "You can only choose a pokemon you are carrying."
	end

	if mon.fainted then
		return nil, string.format("%s is unable to battle.", mon.species)
	end

	local out = Pokemon.getActive(player)
	local outMon = out and Pokemon.read(out.item)
	if out then
		return nil, string.format("%s is already at your side.", outMon and outMon.species or "A pokemon")
	end

	-- The game's progression gate: catching above your level is legitimate,
	-- using it is not. The check belongs to the server, always.
	local required = mon.speciesData.minPlayerLevel
	if required and player:getLevel() < required then
		return nil, string.format("%s will not obey a trainer below level %d. You are level %d.",
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
		Pokemon.monsterName(mon.species), spotFor(player), true, true, player)
	if not creature then
		return nil, string.format("There is no room for %s here.", mon.species)
	end

	-- The creature's health mirrors the fraction stored on the item, scaled by
	-- the level of whoever is sending it out now.
	--
	-- `setHealth`, not `addHealth`. `addHealth` builds a CombatDamage and runs
	-- it through `Game::combatChangeHealth`, which announces itself -- sending
	-- a pokemon out printed "A bulbasaur was healed for 915 hitpoints" at the
	-- owner, which is a lie about something that never happened. `setHealth`
	-- writes the field and refreshes the bar, and says nothing.
	--
	-- Order matters: `setHealth` clamps to `healthMax`, so the maximum has to
	-- be raised first or a pokemon comes out capped at the placeholder value
	-- from its MonsterType.
	local maxHp = mon.stats and mon.stats.hp or mon.speciesData.baseStats.hp
	creature:setMaxHealth(maxHp)
	creature:setHealth(math.max(1, math.floor(maxHp * mon.hpRatio)))

	-- Walking speed is the trainer's, not the species'.
	--
	-- The MonsterType carries 100, which is ordinary for a monster and hopeless
	-- for a companion: a level 500 knight outruns it in a couple of steps, and
	-- what the player sees is a pokemon that falls off the screen and teleports
	-- back over and over. Measured in game on 2026-07-30 -- it was following
	-- the whole time, just losing ground every step.
	--
	-- This is **not** the `speed` stat from the catalogue. That one decides who
	-- strikes first and belongs to phase 4; this one only decides whether the
	-- thing can keep up while walking. Sharing a name is the whole reason to
	-- say so here.
	--
	-- Read once, at the summon. A haste on the trainer afterwards will outpace
	-- it again until the pokemon is recalled -- acceptable while nothing in the
	-- game hastes anyone, and the place to fix it is a condition on the summon
	-- rather than polling.
	creature:setSpeed(player:getSpeed())

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

--- Does this item, or anything inside it, hold the pokemon that is out?
--
-- The question every rule about a pokemon in play ends up asking: it cannot be
-- traded, and it cannot be moved. Both need to see through a bag, because
-- offering or dropping the backpack the ball sits in reaches the same place by
-- a longer road.
--
-- Compares `pokemon_uid` rather than the item reference. The uid is the
-- identity this phase already maintains, and it survives the object being
-- replaced underneath us -- which matters here, because sending a pokemon out
-- runs `transform` and `transform` can hand back a different object.
--
-- @return the pokemon that is out, or nil. Returning it rather than a boolean
--         is what lets the refusals name it: "Charizard is at your side" says
--         more than "your pokemon is out", and costs nothing here.
function Pokemon.holdsActive(player, item)
	if not item then
		return nil
	end

	local entry = Pokemon.getActive(player)
	local mon = entry and entry.item and Pokemon.read(entry.item)
	if not mon then
		return nil
	end

	if item:getCustomAttribute("pokemon_uid") == mon.uid then
		return mon
	end
	if not item:isContainer() then
		return nil
	end
	-- `getItems(true)` is recursive, so a bag inside a bag is covered.
	for _, inner in ipairs(item:getItems(true) or {}) do
		if inner:getCustomAttribute("pokemon_uid") == mon.uid then
			return mon
		end
	end
	return nil
end

--- Drop the entry for a player who left.
function Pokemon.clearSession(player)
	active[player:getId()] = nil
end
