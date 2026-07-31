-- The corpse remembers which pokemon it was.
--
-- Phase 5 throws a ball at a corpse, and a corpse in Tibia is an item that does
-- not know what killed to make it. Its own plan names the two ways out -- one
-- corpse item per species (154 items, and 154 sprites we do not have) or an
-- attribute written at the moment of death -- picks the second, and says in as
-- many words that phase 4 is where it has to be written.
--
-- 🔴 It was not. The whole roster shares corpse 6079, matching the placeholder
-- outfit, so without this every pokemon leaves the same anonymous body and
-- capture has nothing to resolve a species from. The `corpse` parameter has been
-- sitting in `PokemonFaint`'s signature unused since the phase began.
--
-- Kept apart from `PokemonFaint`, which is about a TRAINER's pokemon going down
-- and returns early for anything ownerless. This is the opposite case and would
-- have made that event's name a lie.

local corpseTag = CreatureEvent("PokemonCorpse")

function corpseTag.onDeath(creature, corpse, killer, mostDamageKiller, unjustified, mostDamageUnjustified)
	-- No corpse when the body is not created -- a summon recalled to its ball
	-- at zero, for one. Nothing to label.
	if not corpse then
		return true
	end

	-- The display name of a generated MonsterType is the clean species name, so
	-- it is already the catalogue key -- the same fact `Pokemon.combatantOf`
	-- relies on. Stored as the name rather than the dex number because every
	-- other table in this datapack is keyed by name, and one lookup that is
	-- keyed differently is the one that goes stale.
	local species = creature:getName()
	if not PokemonSpecies[species] then
		return true
	end

	corpse:setCustomAttribute("pokemon_species", species)
	return true
end

corpseTag:register()
