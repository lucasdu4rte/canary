-- Orders that are not attacks: stand still, and face that way.
--
-- Both exist in the source game and both are about POSITIONING, which is the
-- half of a pokemon fight the move commands cannot reach. A beam runs along the
-- line its caster is facing and a burst is centred on where it stands, so
-- "stay there" and "look east" are the two inputs that decide where 191 of the
-- 360 moves actually land.
--
-- They also make the shapes testable, which is why they arrive now: a pokemon
-- that chases and re-faces its target on its own cannot be asked to fire a beam
-- in a chosen direction twice in a row.

Pokemon = Pokemon or {}

--- How long `!pokestop` holds, in seconds.
Pokemon.STOP_SECONDS = 120

--- Is this pokemon parked?
--
-- Rooted and owned. The rooting has to sit at the default subId or the engine
-- ignores it entirely (see `Pokemon.isDummy`), so ownership is what separates a
-- parked summon from a training dummy -- a dummy is ownerless by construction
-- and `!pokestop` only ever reaches a pokemon its trainer sent out.
function Pokemon.isStopped(creature)
	if not creature or creature:isRemoved() then
		return false
	end
	return creature:hasCondition(CONDITION_ROOTED) and creature:getMaster() ~= nil
end

--- Park a pokemon where it stands, or release it if it is already parked.
--
-- The same `CONDITION_ROOTED` the training dummy uses, and for the same reason:
-- it is the engine's own answer to "cannot take a step". `internalMoveCreature`
-- refuses for a rooted creature, and both the follow nudge
-- (`Pokemon.keepDistance`, which calls `creature:move`) and the engine's pathing
-- go through there. Nothing has to be taught to respect it.
--
-- ⚠️ Three things it does NOT do, all of them deliberate:
--
--   * It does not stop the pokemon FIGHTING. It keeps its target, keeps
--     swinging and keeps taking orders -- from one tile. That is the point, and
--     it is why the dummy's early-out in `Pokemon.autoAttack` had to learn to
--     tell a parked pokemon from a dummy first.
--   * It does not stop it FOLLOWING. The trainer walking off screen still
--     teleports it along (`PokemonFollowTrainer`), because rooting is enforced
--     in `internalMoveCreature` and `teleportTo` does not go through there.
--     Parking means it will not walk, not that it will be left behind.
--   * It does not survive the ball. The condition lives on the creature, and
--     `Pokemon.recall` removes the creature -- so `!back` then `!go` comes back
--     free to move, with nothing needed here to arrange it.
--
-- @return true if it is now parked, false if this released it
function Pokemon.stop(creature, seconds)
	if not creature or creature:isRemoved() then
		return false
	end

	if Pokemon.isStopped(creature) then
		creature:removeCondition(CONDITION_ROOTED)
		return false
	end

	local rooted = Condition(CONDITION_ROOTED)
	rooted:setTicks((seconds or Pokemon.STOP_SECONDS) * 1000)
	creature:addCondition(rooted)
	return true
end

--- The four the source game binds, in its own order.
--
-- t1 north, t2 east, t3 south, t4 west -- clockwise from the top, which is the
-- order a player has already learned elsewhere. Not alphabetical, not the
-- engine's enum order, and worth writing down because both of those are
-- plausible enough to "fix" by accident.
Pokemon.FACING = {
	[1] = DIRECTION_NORTH,
	[2] = DIRECTION_EAST,
	[3] = DIRECTION_SOUTH,
	[4] = DIRECTION_WEST,
}

Pokemon.FACING_NAME = {
	[1] = "north",
	[2] = "east",
	[3] = "south",
	[4] = "west",
}

--- Point a pokemon in one of the four directions.
--
-- ⚠️ It holds only while nothing else turns it. A creature with a target faces
-- that target every time it acts, so turning a pokemon mid-fight is a single
-- instant unless it is parked as well. The pairing is the point: `!pokestop`
-- then `t2` is what gives a beam a direction you chose rather than one the
-- engine picked.
--
-- @return true if it turned
function Pokemon.face(creature, slot)
	local direction = Pokemon.FACING[slot]
	if not creature or creature:isRemoved() or not direction then
		return false
	end
	creature:setDirection(direction)
	return true
end
