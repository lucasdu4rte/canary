-- Wild pokemon: the level they fight at.
--
-- A wild has no owner, so it inherits no level. Phase 7 gives the spawn areas
-- their own bands; until then one band covers the test area, which is what the
-- plan asks for at this stage.
--
-- Roxy does this per SPECIES instead (`wildLvl` in their `pokes` table: a wild
-- Blastoise is level 95 anywhere on the map). Simpler, and it takes the job of
-- distributing difficulty away from phase 7 -- at the cost of never having the
-- same species be easy in one region and hard in another. Recorded because the
-- swap is cheap if per-area distribution turns out to be too much work.

Pokemon = Pokemon or {}

-- Single band for the test area. Phase 7 replaces this with a lookup by
-- position; every caller already goes through the function below so that
-- change lands in one place.
local DEFAULT_WILD_LEVEL = 50

--- Level a wild pokemon fights at, given where it stands.
-- @param position ignored for now -- see above
function Pokemon.wildLevel(position)
	return DEFAULT_WILD_LEVEL
end

--- Give a masterless pokemon the health its level implies.
--
-- The MonsterType carries the species' BASE hp and says so: it is the design
-- ceiling, and a summon gets its real value from `Pokemon.calcStats` when it is
-- sent out. A wild never goes through that path -- the map's spawn system
-- creates it directly -- so without this it stands there with the raw base
-- stat. Measured: a wild Blastoise had 79 hp against a formula that computed
-- 139 for it, and a single Flamethrower deals 113. Every wild would die in one
-- hit, and the fight this phase exists to build would never happen.
--
-- Idempotent by comparison rather than by a flag: there is no spawn hook in
-- Canary, so this runs from `onThink` and has to be safe every time. Health is
-- carried across as a fraction, so a wild already in a fight does not get
-- healed by being corrected.
--
-- @return true if it changed anything
function Pokemon.applyWildStats(creature)
	if not creature or creature:isRemoved() then
		return false
	end
	local master = creature:getMaster()
	if master then
		return false -- a summon; summon.lua owns its stats
	end

	local species = PokemonSpecies[creature:getName()]
	if not species then
		return false
	end

	local wanted = Pokemon.calcStats(species, Pokemon.wildLevel(creature:getPosition())).hp
	local current = creature:getMaxHealth()
	if current == wanted then
		return false
	end

	local ratio = current > 0 and (creature:getHealth() / current) or 1.0
	-- setMaxHealth first: setHealth clamps to the maximum, so raising it second
	-- would cap the creature at the value we are trying to leave behind.
	creature:setMaxHealth(wanted)
	creature:setHealth(math.max(1, math.floor(wanted * math.min(1.0, ratio))))
	return true
end
