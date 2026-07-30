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

local SCALED_STATS = { "atk", "def", "spatk", "spdef", "speed" }

local function effectiveLevel(playerLevel)
	return math.floor(playerLevel * LEVEL_SCALE)
end

--- Stats for a pokemon in the hands of a trainer of the given level.
-- @param species entry from PokemonSpecies (the table, not the name)
-- @param playerLevel level of the current owner
-- @return { hp, atk, def, spatk, spdef, speed }
function Pokemon.calcStats(species, playerLevel)
	local level = effectiveLevel(playerLevel)
	local base = species.baseStats

	-- HP has its own formula: no generation ever applied to it the modifier
	-- the other five stats took.
	local out = { hp = math.floor(2 * base.hp * level / 100) + level + 10 }

	for _, stat in ipairs(SCALED_STATS) do
		out[stat] = math.floor(2 * base[stat] * level / 100) + 5
	end

	return out
end

--- Exposed so tests can record which scale they ran at.
function Pokemon.levelScale()
	return LEVEL_SCALE
end
