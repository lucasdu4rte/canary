-- Per-move cooldown, stored on the ball.
--
-- WHY THE BALL AND NOT A TABLE IN MEMORY
--
-- A memory table cleared on recall has a hole in it: recalling and re-summoning
-- would reset every cooldown at once. With 20-40s cooldowns that is not an edge
-- case, it is the dominant way to play -- send out, land the big move, recall,
-- send out again. Roxy stores it on the ball for exactly this reason.
--
-- It is also the architecture phase 3 already settled: the item is the source
-- of truth, and a side table keyed by pokemon is the "parallel cache" that
-- phase 3's constraint rules out.
--
-- WHY THESE KEYS ARE NOT IN THE `FIELDS` SCHEMA
--
-- They are of another kind: disposable, and no part of the pokemon's identity.
-- Putting them in the schema would make `read` walk 360 possible keys on every
-- call. The cost is deliberate and bounded: a destructive sprite swap
-- (`syncVisual`) drops the cooldowns. That is a rare, benign loss -- the same
-- trade phase 3 already accepted for HP.
--
-- Whole seconds are enough: the shortest cooldown in the roster is 2s.

Pokemon = Pokemon or {}

local function key(moveName)
	return "pokemon_cd_" .. moveName
end

--- Seconds left on a move, or 0 when it is ready.
function Pokemon.moveCooldownLeft(item, moveName)
	if not item then
		return 0
	end
	local expiresAt = item:getCustomAttribute(key(moveName))
	if not expiresAt then
		return 0
	end
	local left = expiresAt - os.time()
	return left > 0 and left or 0
end

--- Whether a move can be used right now.
function Pokemon.moveReady(item, moveName)
	return Pokemon.moveCooldownLeft(item, moveName) <= 0
end

--- Starts the cooldown for a move.
--
-- Stored as an ABSOLUTE expiry instant rather than a remaining duration: a
-- duration would have to be decremented by something, and there is no tick in
-- this design to decrement it -- it would silently freeze while the ball sat in
-- a depot, then resume on pickup.
--
-- @param seconds cooldown for this move on this species (from the catalogue)
function Pokemon.markMoveUsed(item, moveName, seconds)
	if not item or not seconds or seconds <= 0 then
		return
	end
	item:setCustomAttribute(key(moveName), os.time() + seconds)
end

--- Cooldown this species has for this move, or nil if it does not know it.
--
-- Reads through `Pokemon.effectiveSpecies` rather than the stored species: see
-- move.lua for why Ditto makes that indirection necessary.
function Pokemon.moveCooldownFor(species, moveName)
	local data = PokemonSpecies[species]
	if not data then
		return nil
	end
	for _, entry in ipairs(data.moves or {}) do
		if entry.name == moveName then
			return entry.cooldown
		end
	end
	return nil
end
