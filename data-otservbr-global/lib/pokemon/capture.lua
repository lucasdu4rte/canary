-- The capture itself: everything that happens between a ball and a corpse.
--
-- Lives in a lib rather than inside the Action because there is more than one
-- way to point a ball at a corpse -- the player's click today, a GM test command
-- beside it, a client UI in phase 6 -- and every one of them has to take the
-- same path. A second copy of these rules is a second set of rules, and the one
-- that gets tested is never the one that ships.
--
-- The ORDER below is the design, not an implementation detail. See
-- `attemptCapture`.

Pokemon = Pokemon or {}

local SUCCESS_EFFECT = CONST_ME_MAGIC_GREEN
local FAILURE_EFFECT = CONST_ME_POFF
local THROW_EFFECT = CONST_ANI_SMALLSTONE

-- Six is how many a trainer carries. The seventh is the one that gets routed to
-- the depot -- counted BEFORE the capture, so the sixth still lands in the bag.
local CARRY_LIMIT = 6

local DEPOT_CARRY_LIMIT = "carry-limit"
local DEPOT_BAG_FULL = "bag-full"

--- The thrower is the corpse owner, or in their party.
--
-- The owner is a runtime creature id -- that is what the engine stores in
-- `corpseowner` (`monster.cpp:3309`) and what `pokemon_corpse.lua` copies into
-- `pokemon_corpse_owner` -- so this compares against `getId()`. Comparing
-- against `getGuid()` looks right and refuses everyone.
local function mayTake(player, ownerId)
	if player:getId() == ownerId then
		return true
	end

	local party = player:getParty()
	if not party then
		return false
	end
	for _, member in ipairs(party:getMembers() or {}) do
		if member:getId() == ownerId then
			return true
		end
	end
	-- The leader is not in getMembers() on every build; check separately rather
	-- than trust it.
	local leader = party:getLeader()
	return leader ~= nil and leader:getId() == ownerId
end

--- The player's depot chest, or nil when the town cannot be resolved.
--
-- `getTown()` is the one statement on this path that can strand the whole
-- transaction. It runs AFTER the corpse and the ball are already gone, so a nil
-- town raises a Lua error right there and the player loses both with no message
-- at all -- the worst outcome the function has available. Returning nil instead
-- lets the caller take the same loud path a place-failure already takes.
local function depotChestFor(player)
	local town = player:getTown()
	if not town then
		return nil
	end
	return player:getDepotChest(town:getId(), true)
end

--- The catch happened and the pokemon could not be placed anywhere.
--
-- `recordThrow` runs here for the same reason it runs on a break-free: the ball
-- was consumed either way. Without it this is the one branch that spends a ball
-- and tallies it nowhere, in the phase whose whole point is keeping that count.
local function stranded(player, species, ballItemId, reason)
	Pokemon.recordThrow(player, species, ballItemId)
	logger.error(string.format(
		"[capture] caught %s for %s but could not place it: %s",
		species, player:getName(), tostring(reason)))
	player:sendCancelMessage("You caught it, but there was nowhere to put it. Contact a gamemaster.")
	return "stranded"
end

--- Catch: make the instance, place it, say what it cost.
--
-- The capture NORMALISES the specimen, and that is a design decision rather than
-- an omission: nothing about the wild pokemon it came from -- its region, its
-- wild level, the HP it had -- enters the item. It is born standard, with stats
-- deriving from species plus the owner's level like every other. Carry any of it
-- across and the game grows region arbitrage: players farming the hard zone for a
-- "better" specimen of the same species.
local function succeed(player, species, ballItemId, position)
	-- Counted BEFORE creating, so the seventh is the one that diverts.
	local carried = #Pokemon.carriedBalls(player)
	local depotReason = carried >= CARRY_LIMIT and DEPOT_CARRY_LIMIT or nil

	local destination = nil
	if depotReason then
		destination = depotChestFor(player)
		if not destination then
			return stranded(player, species, ballItemId, "no town, so no depot to divert to")
		end
	end

	local created, reason = Pokemon.create(player, species, {
		destination = destination,
		ballItemId = ballItemId,
	})

	-- A full bag is a real case and losing the pokemon to it would be losing
	-- property to a limit the player could not see when they threw. Depot is the
	-- valve, for a full bag just as much as for the sixth pokemon.
	if not created and not depotReason then
		local chest = depotChestFor(player)
		if not chest then
			return stranded(player, species, ballItemId, "no town, so no depot to divert to")
		end
		depotReason = DEPOT_BAG_FULL
		created, reason = Pokemon.create(player, species, {
			destination = chest,
			ballItemId = ballItemId,
		})
	end

	if not created then
		return stranded(player, species, ballItemId, reason)
	end

	position:sendMagicEffect(SUCCESS_EFFECT)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("You have caught %s!", species))

	local spent = Pokemon.spentOn(player, species)
	spent[ballItemId] = (spent[ballItemId] or 0) + 1
	-- Unguarded: `spent` always carries at least the ball that just won, so
	-- `describeSpent` cannot return nil here.
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"You have spent %s to catch it.", Pokemon.describeSpent(spent)))
	Pokemon.clearSpent(player, species)

	if depotReason == DEPOT_CARRY_LIMIT then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
			"Your pokemon has been sent to your depot since you already have %d pokemons with you.", CARRY_LIMIT))
	elseif depotReason == DEPOT_BAG_FULL then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
			"Your pokemon has been sent to your depot since your backpack is full.")
	end

	return "caught"
end

--- Throw one ball at one corpse.
--
-- **The corpse is REMOVED before the dice are rolled, and that ordering is the
-- whole design.** A successful removal is what serialises two players racing for
-- the same body: whoever gets it is the only one who rolls. Roll first and both
-- racers roll on the same corpse, and the loser still gets a pokemon.
--
-- It also dispenses with the flag the legacy base needed. The Roxy rolls inside
-- an addEvent after the ball's flight animation, so the corpse sits on the ground
-- during the flight and it writes `catching = 1` on it to cover the window. Here
-- the flight effect is cosmetic and comes AFTER the decision, so there is no
-- window to cover.
--
-- @param corpse the item being thrown at -- caller has already established it is
--        an item, but nothing else about it
-- @param ballItem the empty ball, consumed only once the corpse is gone
-- @return one of "not-a-corpse", "impossible", "not-yours", "gone", "broke-free",
--         "caught", "stranded". The player-facing message is sent from here; the
--         return value is for the caller's log.
function Pokemon.attemptCapture(player, corpse, ballItem)
	local ball = Pokemon.BALLS[ballItem:getId()]
	if not ball then
		player:sendCancelMessage("You cannot throw that.")
		return "not-a-ball"
	end

	-- Captured before the removal: after it, the item may be invalid.
	local position = corpse:getPosition()

	-- 1. Is it a pokemon corpse, and of what?
	local species = corpse:getCustomAttribute("pokemon_corpse_species")
	if not species or not PokemonSpecies[species] then
		player:sendCancelMessage("You can only throw this at a defeated pokemon.")
		return "not-a-corpse"
	end

	-- 2. Impossible refuses before anything is consumed.
	if not Pokemon.isCatchable(species) then
		player:sendCancelMessage("You cannot catch this pokemon.")
		return "impossible"
	end

	-- 3. Owner, or someone in their party. Without this, camping other people's
	-- corpses is free and the whole fight becomes work someone else harvests.
	--
	-- OUR attribute first. The engine's `corpseowner` is dropped by `Item::setID`
	-- (`src/items/item.cpp:822-824`) on the corpse's first decay stage, ten
	-- seconds after the kill, so reading only that one meant a stranger who waited
	-- was let straight through. `pokemon_corpse.lua` writes `pokemon_corpse_owner`
	-- at death with the same value the engine would have written, and custom
	-- attributes survive the transform.
	--
	-- The engine's field stays as FALLBACK, for a corpse made by a path
	-- `pokemon_corpse.lua` never saw. Absent on BOTH is still fair game rather
	-- than a refusal -- a wild pokemon killed by another monster is owned by
	-- nobody, and reading that as "no" would make it uncatchable for everyone.
	local owner = corpse:getCustomAttribute("pokemon_corpse_owner")
		or corpse:getAttribute("corpseowner")
	if owner and owner ~= 0 and not mayTake(player, owner) then
		player:sendCancelMessage("You did not defeat this pokemon.")
		return "not-yours"
	end

	-- 4. Remove the corpse. A failure here means somebody was ahead of us, and
	-- the ball is NOT spent.
	if not corpse:remove() then
		player:sendCancelMessage("There is nothing left here.")
		return "gone"
	end

	-- 5. Only now is the ball consumed and the dice thrown.
	local ballItemId = ballItem:getId()
	ballItem:remove(1)
	player:getPosition():sendDistanceEffect(position, THROW_EFFECT)

	if math.random() >= Pokemon.catchChance(species, ballItemId, {}) then
		Pokemon.recordThrow(player, species, ballItemId)
		position:sendMagicEffect(FAILURE_EFFECT)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("The %s broke free!", species))
		return "broke-free"
	end

	return succeed(player, species, ballItemId, position)
end
