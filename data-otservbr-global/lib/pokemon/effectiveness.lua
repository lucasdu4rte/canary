-- Type effectiveness.
--
-- The multiplier a move of one type gets against a defender's types. No clamp:
-- 4x and 0.25x are real values here. Roxy clamps both (4->2, 0.25->0.5) and
-- that is a live counter-example rather than an oversight, so if the gate's
-- calibration asks for it, this is the one place it would go.

Pokemon = Pokemon or {}

-- `PokemonTypes` stores each relation as a LIST, not a lookup:
--
--   ["normal"] = { superEffective = {}, notVeryEffective = { "rock", "steel" } }
--
-- so `rel.notVeryEffective["rock"]` is nil and every match would come out
-- neutral -- in silence, with nothing in the log. Indexing once at load is what
-- makes the lookups below mean what they read like.
--
-- Built here rather than emitted this way by the generator because catalog.lua
-- has more than one consumer, and reshaping it for this one would be a phase 2
-- change made for a phase 4 convenience.
local INDEX = {}

for attackType, relation in pairs(PokemonTypes) do
	local entry = { superEffective = {}, notVeryEffective = {}, immune = {} }
	for group, list in pairs(relation) do
		for _, defenderType in ipairs(list) do
			entry[group][defenderType] = true
		end
	end
	INDEX[attackType] = entry
end

--- Multiplier of an attack against a defender.
-- @param attackType type of the move
-- @param defenderTypes list of the defender's types (one or two)
-- @return number -- 0, 0.25, 0.5, 1, 2 or 4
function Pokemon.multiplier(attackType, defenderTypes)
	local relation = INDEX[attackType]
	if not relation then
		error("unknown attack type: " .. tostring(attackType))
	end

	local multiplier = 1.0
	for _, defenderType in ipairs(defenderTypes or {}) do
		-- Returning here is the rule, not a shortcut: an immunity on one type
		-- beats anything on the other. Multiplying through would reach 0 by
		-- accident (0 * 2) instead of by decision, and the two are only
		-- indistinguishable until someone adds an ability that overrides one.
		if relation.immune[defenderType] then
			return 0.0
		end
		if relation.superEffective[defenderType] then
			multiplier = multiplier * 2.0
		elseif relation.notVeryEffective[defenderType] then
			multiplier = multiplier * 0.5
		end
	end
	return multiplier
end

--- The pinned matrix, as data. Read by /check-effectiveness and by the G4 gate.
-- Each row is { attack type, defender types, expected }.
Pokemon.EFFECTIVENESS_PINS = {
	{ "water", { "fire" }, 2.0 },
	{ "rock", { "fire", "flying" }, 4.0 },
	{ "normal", { "ghost", "poison" }, 0.0 },
	{ "electric", { "ground" }, 0.0 },
	{ "fire", { "water", "rock" }, 0.25 },
	{ "normal", { "normal" }, 1.0 },
}

--- Runs the pinned matrix. Returns a list of failures, empty when all pass.
--
-- Two failure shapes are worth telling apart, and the list makes it possible:
-- `rock` against fire/flying coming out 2.0 means the loop stopped at the first
-- type; all six coming out 1.0 means INDEX above was never built.
function Pokemon.checkEffectiveness()
	local failures = {}
	for _, pin in ipairs(Pokemon.EFFECTIVENESS_PINS) do
		local attack, defenders, expected = pin[1], pin[2], pin[3]
		local got = Pokemon.multiplier(attack, defenders)
		if got ~= expected then
			failures[#failures + 1] = string.format(
				"%s vs %s: expected %.2f, got %.2f",
				attack, table.concat(defenders, "/"), expected, got)
		end
	end
	return failures
end
