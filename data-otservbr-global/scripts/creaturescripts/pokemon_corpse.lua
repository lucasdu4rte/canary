-- The corpse remembers which pokemon it was, and who earned it.
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

--- The PLAYER a kill belongs to, or nil when it belongs to nobody.
--
-- Same derivation the engine uses in `Monster::getCorpse`
-- (`src/creatures/monsters/monster.cpp:3304-3317`): the creature itself when it
-- is a player, otherwise its MASTER when that master is a player -- a summoned
-- pokemon's kill belongs to its trainer. Anything else (a monster killing a
-- monster, a field) owns nothing.
local function owningPlayer(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	if master and master:isPlayer() then
		return master
	end
	return nil
end

function corpseTag.onDeath(creature, corpse, killer, mostDamageKiller, unjustified, mostDamageUnjustified)
	-- No corpse when the body is not created -- a summon recalled to its ball
	-- at zero, for one. Nothing to label.
	--
	-- NOT `if not corpse`: `Lua::pushThing` (`lua_functions_loader.cpp:190-202`)
	-- pushes a 4-field TABLE for a null Thing, not nil, so `not corpse` is
	-- always false and execution would fall through into
	-- `corpse:setCustomAttribute(...)` -- a method call on a plain table,
	-- "attempt to call a nil value". And this is not a rare path: it is the
	-- common one. `Creature::dropCorpse` (`creature.cpp:733-742`) calls this
	-- event with a null corpse whenever `!lootDrop && getMonster() &&
	-- getMaster()` -- every summoned pokemon, because `setMaster` with
	-- `reloadCreature` sets `setDropLoot(false)`. So a trainer's pokemon
	-- fainting -- which never drops loot -- hit this every single time.
	if type(corpse) ~= "userdata" then
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

	-- Deliberately NOT `pokemon_species`: that key is what `Pokemon.read` uses
	-- to decide an item is a pokemon, and a corpse carrying it reads as a
	-- malformed ball -- past the first check, refused at the `required`
	-- `pokemon_ot`, with a logger.error on the way out. Two different things
	-- that both know a species, so two different keys.
	corpse:setCustomAttribute("pokemon_corpse_species", species)

	-- And WHO earned it -- our own copy, because the engine's does not last.
	--
	-- `Monster::getCorpse` (`monster.cpp:3304-3317`) writes `CORPSEOWNER` with
	-- the most-damage killer's runtime id, or its master's. Then
	-- `Creature::dropCorpse` (`creature.cpp:786-788`) starts the corpse decaying;
	-- item 6079 carries `duration="10" decayTo="5934"` (`data/items/items.xml`);
	-- the transform takes the in-place path through `Tile::updateThing` into
	-- `Item::setID`; and `Item::setID` (`src/items/item.cpp:822-824`) does
	-- `removeAttribute(CORPSEOWNER)`. Ten seconds after the kill the engine's
	-- owner reads 0, and `throw_ball.lua` treats an ownerless corpse as fair game
	-- -- so a stranger who simply waits walks through the guard.
	--
	-- Custom attributes are NOT touched by `setID`, which is precisely why the
	-- species above survives the whole corpse chain. This one rides along with
	-- it. It is NOT redundant with the engine's field: by the time capture reads
	-- it, the engine's field is gone.
	--
	-- `mostDamageKiller` first, `killer` (the last hit) only as fallback, so the
	-- value matches what the engine would have written and what `mayTake`
	-- compares against: a player's runtime `getId()`, not the guid.
	local earner = owningPlayer(mostDamageKiller) or owningPlayer(killer)
	if earner then
		corpse:setCustomAttribute("pokemon_corpse_owner", earner:getId())
	end

	return true
end

corpseTag:register()
