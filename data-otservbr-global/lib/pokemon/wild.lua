-- Wild pokemon: the level they fight at.
--
-- A wild has no owner, so it inherits no level and something has to say what it
-- fights at. It is PER SPECIES, from the catalogue -- the same shape Roxy uses
-- (`wildLvl` in their `pokes` table, so a wild Blastoise is the same anywhere on
-- the map), and the alternative the spec registered against its own per-area
-- choice.
--
-- What it buys: the number lives with the rest of the catalogue, and phase 7
-- does not have to distribute difficulty across the whole map before anything
-- can be balanced. What it costs, and this is real: the same species can never
-- be easy in one region and hard in another.
--
-- 🔴 It replaced a single constant of 50 for the entire roster, which is worth
-- recording because of how badly that read. Against a level 500 trainer, a wild
-- Chansey stood at level 50 with a defence of 10 while the attacker had 845 --
-- an automatic attack of power 10 removed its whole health bar. Every damage
-- number measured in that state was fiction, and the constant, not the formula,
-- was what made it so.

Pokemon = Pokemon or {}

--- Level a wild pokemon of this species fights at.
--
-- Takes the position because phase 7 may want to shift a band by region, and
-- every caller already routes through here so that change lands in one place.
--
-- @param position where it stands -- unused today
function Pokemon.wildLevel(species, position)
	local data = PokemonSpecies[species]
	if not data then
		return 1
	end
	-- minPlayerLevel is the fallback the builder already applies for the three
	-- baby forms Roxy has no entry for; repeated here so a catalogue written by
	-- something else cannot produce a level of nil.
	return data.wildLevel or data.minPlayerLevel or 1
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

	local level = Pokemon.wildLevel(creature:getName(), creature:getPosition())
	local wanted = Pokemon.calcStats(species, level).hp
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
