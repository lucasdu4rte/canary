-- A wild throwing its own moves: the clock the map never had.
--
-- Kept apart from `PokemonAutoAttack` even though both hang off `onThink` and
-- both throttle themselves. They are two different cadences answering to two
-- different constants, and folding them together would mean one `if` deciding
-- which of two unrelated timers applies -- the kind of shared helper that makes
-- both harder to change later.
--
-- The throttle lives inside `Pokemon.wildMove`, with the per-move cooldowns it
-- has to agree with. This script only decides how often to ask.

local wildMoves = CreatureEvent("PokemonWildMoves")

function wildMoves.onThink(creature, interval)
	if creature:isRemoved() then
		-- The one thing this script owns: making sure a dead creature's timers
		-- do not outlive it. `wildMove` cannot do it, because it is never called
		-- again for a creature that is gone.
		Pokemon.forgetWild(creature:getId())
		return true
	end

	Pokemon.wildMove(creature)
	return true
end

wildMoves:register()
