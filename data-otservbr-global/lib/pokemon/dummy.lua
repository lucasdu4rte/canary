-- A target that stands still, cannot die, and reports what hit it.
--
-- Built for the one measurement this phase could not otherwise make: whether an
-- area move reaches more than one creature. That question needs creatures
-- standing where you put them and staying there, and a live wild does none of
-- it -- it wanders, it hits back, and it dies before the second attempt.
--
-- ⚠️ A dummy is NOT a new species. It is a real pokemon in a state, and it has
-- to be: `Pokemon.combatantOf` resolves a creature through the catalogue by
-- name, so a "Training Dummy" MonsterType would be turned away by `useMove`
-- with "Pokemon moves only work on other pokemon", and effectiveness would have
-- no type to consult. Being a real species is also the point -- /dummy Gastly
-- measures an immunity, /dummy Chansey measures neutral, same command.

-- ⚠️ A dummy can only be hit by a POKEMON THAT HAS A TRAINER. That is an engine
-- rule, not ours: `Combat::canDoCombat` refuses when a masterless monster
-- attacks another masterless monster (combat.cpp:435-441), so a wild cannot
-- fight a dummy and no headless probe can stand one wild in front of another to
-- measure a move. Send yours out and order it; that path is allowed because the
-- attacker's master is a player.
--
-- Worth knowing before reading a zero as a broken move: the refusal is silent.

Pokemon = Pokemon or {}

--- Health a dummy carries.
--
-- Large enough that nothing empties it: the hardest hit measured at
-- STAT_SCALE 60 is in the tens of thousands, so this absorbs some thirty
-- thousand of them. Below int32, which is what the engine stores health in.
--
-- It does NOT distort the numbers being measured. `Pokemon.combatantOf` builds
-- the defender's stats from species and level through `calcStats` and never
-- reads the creature's health, so the damage printed is the real damage that
-- species would take. Only the health bar is fiction.
Pokemon.DUMMY_HEALTH = 1000000000

--- Is this creature a dummy?
--
-- The mark IS the condition, deliberately -- no registry keyed by creature id.
-- An id outlives the creature it named, so a stale entry would eventually
-- christen some unrelated monster a dummy; a condition is carried by the
-- creature itself and cannot go stale.
--
-- `CONDITION_ROOTED` is also the mechanism rather than a flag sitting next to
-- it: `Game::internalMoveCreature` refuses outright for a rooted creature
-- (game.cpp:1950), and every step a monster takes -- follow, random, walk-back
-- -- passes through there (creature.cpp:243).
--
-- 🔴 **The rooting must sit at subId 0, and the ownership is what tells a dummy
-- from a parked pokemon.** `!pokestop` roots too, so the obvious move was to
-- separate them by subId -- and that quietly breaks both. Every engine check
-- reads `hasCondition(CONDITION_ROOTED)` with the DEFAULT subId (game.cpp:1950,
-- creature.cpp:503), so a rooting under any other subId is a decoration: it
-- stops nothing. Measured in play -- a parked Charizard walked off after its
-- trainer, and the dummies would have gone back to wandering with it.
--
-- So both root at 0, and they are told apart by what they are: a dummy is
-- ownerless by construction (it is a wild that `/dummy` marked) and a parked
-- pokemon is always a summon. Nothing else in the datapack roots anything.
function Pokemon.isDummy(creature)
	if not creature or creature:isRemoved() then
		return false
	end
	return creature:hasCondition(CONDITION_ROOTED) and not creature:getMaster()
end

--- Turn a pokemon into a dummy, in place.
--
-- Why rooting is needed at all, since a passive species never picks a fight:
-- `Monster::isOpponent` counts any player as an opponent regardless of
-- `hostile` (monster.cpp:865), so a player on screen fills the target list, the
-- monster stops being idle, and `doRandomStep` walks it off the tile you put it
-- on. Three dummies lined up for an area test would not stay lined up.
--
-- @return true if it took
function Pokemon.makeDummy(creature)
	if not creature or creature:isRemoved() then
		return false
	end
	if not PokemonSpecies[creature:getName()] then
		return false
	end

	-- Default subId, and it has to be: see `Pokemon.isDummy` above for what
	-- happens to a rooting the engine cannot see.
	local rooted = Condition(CONDITION_ROOTED)
	rooted:setTicks(-1)
	creature:addCondition(rooted)

	-- setMaxHealth first: setHealth clamps to the maximum, so raising it second
	-- would cap the creature at the value we are trying to leave behind. Same
	-- order, and the same reason, as Pokemon.applyWildStats.
	creature:setMaxHealth(Pokemon.DUMMY_HEALTH)
	creature:setHealth(Pokemon.DUMMY_HEALTH)

	-- Per instance rather than on the MonsterType: every pokemon shares the
	-- generated type, and a normal one must not pay for this.
	creature:registerEvent("PokemonDummy")
	return true
end

--- Clear the dummies standing around a position.
--
-- Scoped to what you can see rather than to the whole map, because that is the
-- honest scope available: there is no `Game.getMonsters()`, only spectators
-- around a point. It is also the scope you want -- you clear the row in front
-- of you, not someone else's test on the other side of the map.
--
-- @return how many were removed
function Pokemon.clearDummies(position)
	local removed = 0
	for _, creature in ipairs(Game.getSpectators(position, false, false, 30, 30, 30, 30)) do
		if creature:isMonster() and Pokemon.isDummy(creature) then
			creature:remove()
			removed = removed + 1
		end
	end
	return removed
end
