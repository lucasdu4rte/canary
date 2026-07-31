-- Combat stats, derived on demand from species plus the owner's level.
--
-- Nothing here is persisted. That is a design decision rather than thrift: a
-- stored stat goes stale the moment the formula moves, so a balance tweak
-- would leave every existing pokemon carrying old numbers with nothing to
-- signal it.

Pokemon = Pokemon or {}

-- "Percentage of the player's level" -- the most sensitive constant in the
-- game. Changing it moves the power of every pokemon on the server at once.
local LEVEL_SCALE = 1.0

-- The scale the fight is played at.
--
-- The formulas below are the canonical Pokemon ones, and canonical Pokemon
-- numbers are small: a Venusaur at level 95 comes out at 257 HP, against a
-- Tibia character of that level carrying thousands. Next to the rest of the
-- server it reads as broken even though it is not.
--
-- 🔴 It multiplies HP **and** damage, and that pairing is the whole point.
-- Scaling health alone would multiply the length of every fight by the same 60:
-- measured before this existed, a neutral ordered move took 23% of the target's
-- health and an automatic attack 3%, which are the shares we want. Scaling one
-- side would turn them into 0.4% and 0.05% -- 250 hits to end a fight.
--
-- So nothing about the balance moves here. Only the digits do.
--
-- 60 rather than a rounder number because it is what lands the reference case:
-- Venusaur at its wild level of 95 reaches 15,420, and Roxy -- the base these
-- expectations come from -- puts the same pokemon at 12,350 wild and 16,500 in
-- the hands of a level 150 trainer.
--
-- ⚠️ Attack and defence are deliberately NOT scaled. They meet as A/D inside the
-- damage formula, so a common factor cancels and scaling them would be a pair
-- of larger numbers that change nothing. Speed is left alone because it drives
-- movement, not damage.
Pokemon.STAT_SCALE = 60

local SCALED_STATS = { "atk", "def", "spatk", "spdef", "speed" }

local function effectiveLevel(playerLevel)
	return math.floor(playerLevel * LEVEL_SCALE)
end

--- The level the damage formula uses. Exposed because phase 4 needs it and
--- LEVEL_SCALE must stay in one place: a second copy is a balance constant that
--- drifts without anyone editing it twice on purpose.
function Pokemon.effectiveLevel(playerLevel)
	return effectiveLevel(playerLevel)
end

--- Stats for a pokemon in the hands of a trainer of the given level.
-- @param species entry from PokemonSpecies (the table, not the name)
-- @param playerLevel level of the current owner
-- @return { hp, atk, def, spatk, spdef, speed }
function Pokemon.calcStats(species, playerLevel)
	local level = effectiveLevel(playerLevel)
	local base = species.baseStats

	-- HP has its own formula: no generation ever applied to it the modifier
	-- the other five stats took. STAT_SCALE rides on top -- see above for why it
	-- has to be matched by the same factor on damage.
	local out = { hp = (math.floor(2 * base.hp * level / 100) + level + 10) * Pokemon.STAT_SCALE }

	for _, stat in ipairs(SCALED_STATS) do
		out[stat] = math.floor(2 * base[stat] * level / 100) + 5
	end

	return out
end

--- Exposed so tests can record which scale they ran at.
function Pokemon.levelScale()
	return LEVEL_SCALE
end
