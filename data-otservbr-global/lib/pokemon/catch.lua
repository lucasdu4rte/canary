-- How likely a ball is to hold, and which balls exist.
--
-- The chance is a per-species TABLE, not a formula over `captureRate`: 55 of
-- the 154 species share `captureRate = 45`, and among the 44 of those with
-- solid measurement the real rate runs from 0.3% (Eevee) to 27.8% (Omanyte).
-- The field cannot tell them apart. `PokemonCatch` was seeded from the Roxy
-- production statistics -- see the phase 5 spec for the measurement.

Pokemon = Pokemon or {}

-- One dial for the whole economy. 1.0 means literally "the economy the Roxy
-- ran": one capture every 11.2 balls, measured over 106,490 attempts.
Pokemon.CATCH_SCALE = 1.0

-- 3.5x from the worst ball to the best, which is the range both legacy bases
-- ran in (Roxy 2.2x, PokeMonster 8x). The value stored per species is the
-- GREAT ball's rate, not the Poke's: the measurement is aggregated over the
-- mix of balls players actually used, so anchoring it at the cheapest ball and
-- then multiplying up would count the good ball twice.
--
-- No `guaranteed` field: the Master Ball is out of the alpha, and a field no
-- row uses is the dead scaffolding the lessons doc says not to leave behind.
Pokemon.BALLS = {
	[PokemonBallItems["Poke Ball"]] = { name = "poke ball", multiplier = 0.7 },
	[PokemonBallItems["Great Ball"]] = { name = "great ball", multiplier = 1.0 },
	[PokemonBallItems["Super Ball"]] = { name = "super ball", multiplier = 1.5 },
	[PokemonBallItems["Ultra Ball"]] = { name = "ultra ball", multiplier = 2.5 },
}

--- Is this species catchable at all?
--
-- Impossible is a STATE, not a very small number. Legendaries are event
-- content and the baby forms come from Oak in phase 7; both refuse before
-- anything is consumed. Reading the state rather than testing `rate == 0`
-- matters because a measured zero is a different thing: `Aerodactyl` really
-- did go 0 for 326 on the Roxy, and it is meant to be brutal, not forbidden.
function Pokemon.isCatchable(species)
	local entry = PokemonCatch and PokemonCatch[species]
	if not entry then
		return false
	end
	return entry.source ~= "impossible"
end

--- Chance of this ball holding this species, from 0 to 1.
--
-- @param bonuses list of fractions, e.g. {0.1} for +10%. Empty today; Premium
--        and the future equipment and mastery bonuses land here. It is a
--        parameter and not a flag on purpose -- an empty list that gets
--        iterated cannot become the "read but never written" bug the lessons
--        doc catalogues.
function Pokemon.catchChance(species, ballItemId, bonuses)
	local entry = PokemonCatch and PokemonCatch[species]
	if not entry then
		error("unknown species in the catch table: " .. tostring(species))
	end

	local ball = Pokemon.BALLS[ballItemId]
	if not ball then
		error("unknown ball item: " .. tostring(ballItemId))
	end

	local chance = entry.rate * ball.multiplier * Pokemon.CATCH_SCALE
	for _, b in ipairs(bonuses or {}) do
		chance = chance * (1 + b)
	end

	return math.min(1.0, math.max(0.0, chance))
end
