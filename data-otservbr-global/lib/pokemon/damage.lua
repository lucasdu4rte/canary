-- The damage formula.
--
-- A pure function over numbers that are already computed: it reads stats, it
-- does not fetch them, and it touches no item and no creature. That is what
-- makes it testable from a talkaction without a fight in progress.
--
-- Modern-generation shape, which is a deliberate divergence from Roxy: there,
-- damage is `spatk * power * 0.1` and defence is applied later in a stats hook,
-- so defence never scales with level and fights get faster as a trainer grows.
-- Here D is in the divisor and scales alongside A.

Pokemon = Pokemon or {}

--- A combatant, as this formula needs it.
-- @field stats          from Pokemon.calcStats
-- @field speciesData    entry from PokemonSpecies (for types, and so STAB)
-- @field effectiveLevel attacker only -- Pokemon.effectiveLevel(ownerLevel),
--                       or the spawn area's level for a wild one

--- Damage of `move` from `attacker` to `defender`.
-- @return damage (integer >= 0), effectiveness multiplier
function Pokemon.damage(attacker, defender, move)
	-- A move with no power deals nothing, and says so by returning neutral
	-- effectiveness. Phase 4 has 102 of these and the executor refuses them
	-- before reaching this point -- but arriving here anyway must not produce
	-- the 2 that the formula's trailing `+ 2` would otherwise hand back.
	if not move.power or move.power <= 0 then
		return 0, 1.0
	end

	local physical = move.damageClass == "physical"
	local a = physical and attacker.stats.atk or attacker.stats.spatk
	local d = physical and defender.stats.def or defender.stats.spdef

	local level = attacker.effectiveLevel
	local base = math.floor(math.floor(math.floor(2 * level / 5 + 2) * move.power * a / d) / 50) + 2

	-- A move with no type is elemental in neither direction: no STAB, no
	-- effectiveness, no immunity. The melee auto-attack is the only one, and it
	-- is a property of the move rather than a name checked here -- nothing in
	-- this file knows what a move is called.
	--
	-- 🔴 Why melee has no type. It carried the attacker's own first type at
	-- first, for free STAB and no branch. Measured: 74 of the 154 species have a
	-- first type that something is immune to -- Snorlax's melee did nothing to a
	-- ghost, Pikachu's nothing to a ground, Machamp's nothing to a ghost. Half
	-- the roster lost half its damage output in specific matchups, silently,
	-- because the automatic attack is one of the two clocks a fight runs on.
	--
	-- Roxy reaches the same place from the other side: their melee is physical
	-- and never consults a type at all. Element belongs to moves.
	local stab = 1.0
	local effectiveness = 1.0

	if move.type then
		for _, attackerType in ipairs(attacker.speciesData.types) do
			if attackerType == move.type then
				stab = 1.5
				break
			end
		end
		effectiveness = Pokemon.multiplier(move.type, defender.speciesData.types)
	end

	-- Ahead of the `max(1, ...)` below, and that order is the whole point.
	-- After it, an immunity would deal 1, and "Normal hit the Gengar for 1" is
	-- the kind of wrong that survives for weeks because it looks like a graze.
	if effectiveness == 0.0 then
		return 0, effectiveness
	end

	local roll = 0.85 + math.random() * 0.15

	-- The other half of Pokemon.STAT_SCALE. Health carries the same factor, so
	-- the two cancel and the number of hits a fight takes is exactly what it was
	-- before the scale existed -- which is the point: the scale moves the digits
	-- into the range the rest of the server plays at, and moves nothing else.
	--
	-- Applied here rather than to atk/spatk because those meet defence as A/D
	-- inside the formula above, where a common factor cancels out.
	local scaled = base * stab * effectiveness * roll * Pokemon.STAT_SCALE

	-- Minimum of 1 so a weak move against high defence lands for something.
	-- "Hit and did nothing" reads as a bug; immunity above is the only real 0.
	return math.max(1, math.floor(scaled)), effectiveness
end

--- Runs the formula `rounds` times on one pair and reports the spread.
--
-- The roll is 0.85..1.00, so max/min should sit near 1.18. Far above means the
-- roll is wrong; exactly 1.00 means it is not being applied at all -- which is
-- invisible in play, because damage that never varies still looks like damage.
function Pokemon.damageSpread(attacker, defender, move, rounds)
	local min, max, total = math.huge, -math.huge, 0
	rounds = rounds or 100
	for _ = 1, rounds do
		local dealt = Pokemon.damage(attacker, defender, move)
		min = math.min(min, dealt)
		max = math.max(max, dealt)
		total = total + dealt
	end
	return { min = min, max = max, avg = total / rounds, ratio = min > 0 and (max / min) or 0 }
end
