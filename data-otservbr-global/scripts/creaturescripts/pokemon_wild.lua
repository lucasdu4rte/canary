-- Wild pokemon: give them the health their level implies.
--
-- Canary has no spawn hook for monsters -- the creature events are death,
-- healthchange, think, preparedeath and kill -- so `onThink` is where this can
-- run. `Pokemon.applyWildStats` is written to be safe on every call because of
-- that, and it costs one comparison once the health is already right.
--
-- Kept apart from PokemonFollowTrainer, which returns early for anything
-- without a master and is about where a pokemon stands, not how much it can take.

local wildStats = CreatureEvent("PokemonWildStats")

function wildStats.onThink(creature, interval)
	Pokemon.applyWildStats(creature)
	return true
end

wildStats:register()
