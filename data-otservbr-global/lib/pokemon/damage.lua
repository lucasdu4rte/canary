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

	local stab = 1.0
	for _, attackerType in ipairs(attacker.speciesData.types) do
		if attackerType == move.type then
			stab = 1.5
			break
		end
	end

	local effectiveness = Pokemon.multiplier(move.type, defender.speciesData.types)

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
