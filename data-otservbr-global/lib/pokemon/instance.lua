-- The pokemon item: create, read and change state.
--
-- The item **is** the pokemon. There is no table, no row, no second source of
-- truth. Everything that survives a logout lives in the custom attributes
-- written here.
--
-- Every write goes through one of the named operations below. There is no
-- generic setter on purpose: the structural failure of the legacy bases was
-- twenty files writing to the ball with nobody owning the invariants, and a
-- `write(item, fields)` is that same hole with a single door.

Pokemon = Pokemon or {}

-- Bump when the attribute layout changes; `read` migrates on the way in.
-- Without it there is no repair: the old data is spread across players'
-- inventories and there is no database to run a migration against.
Pokemon.SCHEMA_VERSION = 1

-- Placeholder until the art track delivers the 308 ids, one per species and
-- state.
--
-- 23488 "surprise cube": you use it and something comes out, which is at least
-- the right idea. The sprite is still wrong -- that is Task 4's job. What
-- matters here are four requirements, and each one killed a candidate:
--   take = true         -> without it no container accepts it  (killed 10340)
--   usable = true       -> this is what makes "Use" appear
--   multiuse = false    -> with it the client only offers "Use with ..."
--   no script on the id -> a claimed id makes one of the two Actions be
--                          **rejected silently**, and the item answers
--                          "cannot use this object"
--
-- Finding a free id is harder than it looks, for two reasons that cost three
-- attempts:
--   1. `:id(a, b)` in Canary is a **range**, not two ids       (killed 19065)
--   2. scripts also claim ids through **tables**, with no `:id()` at all --
--      `decay_to.lua` has `[37111] = 37112`                    (killed 37111)
-- Counting both, 28,428 datapack ids are taken. Of the 224 that are take and
-- usable without multiuse, **none of them look like a ball**.
Pokemon.PLACEHOLDER_BALL_ID = 23488

-- Namespace for the MonsterTypes. Canary registers them as "<variant>|<name>"
-- while keeping the display name clean, which avoids colliding with a Tibia
-- monster of the same name without handling species case by case.
Pokemon.MONSTER_VARIANT = "pokemon"

--- MonsterType key for a species.
function Pokemon.monsterName(species)
	return Pokemon.MONSTER_VARIANT .. "|" .. species
end

-- Field, type and default in one place. Half the crashes measured in the
-- legacy bases were an absent attribute read without a default, handled
-- inconsistently between files of the same project -- `or 0` scattered across
-- callers is how that gets reproduced.
local FIELDS = {
	{ key = "pokemon_v",        kind = "number",  default = Pokemon.SCHEMA_VERSION },
	{ key = "pokemon_species",  kind = "string",  required = true },
	{ key = "pokemon_hp_ratio", kind = "number",  default = 1.0 },
	{ key = "pokemon_ot",       kind = "number",  required = true, immutable = true },
	{ key = "pokemon_uid",      kind = "number",  required = true, immutable = true },
	{ key = "pokemon_fainted",  kind = "boolean", default = false },
}

-- 2^53: measured ceiling of a custom attribute.
local MAX_SAFE_INT = 9007199254740992

local function readField(item, field)
	local raw = item:getCustomAttribute(field.key)
	if raw == nil then
		return field.default
	end
	return raw
end

--- Identity of a capture. It only serves manual investigation of duplication:
-- a clone carries the same uid, so it says where something came from, not
-- that it is fake.
local function newUid()
	-- ~1.7e14, comfortably under the 2^53 ceiling.
	local uid = os.time() * 100000 + math.random(0, 99999)
	assert(uid < MAX_SAFE_INT, "pokemon_uid exceeded the 2^53 ceiling")
	return uid
end

-- Container inside container; eight is generous.
local MAX_DEPTH = 8

--- The player carrying the item, or nil if nobody is.
-- A ball on the ground has no holder, and that is a normal case, not an error.
--
-- Walks the `getParent` chain and **not** `getTopParent`: measured on
-- 2026-07-29, `getTopParent()` on a backpack returns the backpack itself, not
-- the player. `getParent` is what crosses over to the Player.
local function holderOf(item)
	local node = item
	for _ = 1, MAX_DEPTH do
		local parent = node.getParent and node:getParent() or nil
		if not parent then
			return nil
		end
		if parent.isPlayer and parent:isPlayer() then
			return parent
		end
		node = parent
	end
	return nil
end

--- Read the pokemon out of an item.
-- @return table with the attributes and, when there is a holder, the derived
--         stats. `nil` if the item is not a pokemon (empty ball, any item).
function Pokemon.read(item)
	if not item then
		return nil
	end
	local speciesName = item:getCustomAttribute("pokemon_species")
	if not speciesName then
		return nil
	end

	local raw = {}
	for _, field in ipairs(FIELDS) do
		raw[field.key] = readField(item, field)
	end

	local species = PokemonSpecies[speciesName]
	if not species then
		-- Species left the catalogue. Loud on purpose: staying quiet here
		-- turns into "my pokemon became nothing" with no clue when it started.
		logger.error(string.format(
			"[Pokemon.read] unknown species '%s' on item uid=%s -- catalogue changed without a migration?",
			tostring(speciesName), tostring(raw.pokemon_uid)))
		return nil
	end

	local out = {
		item = item,
		v = raw.pokemon_v,
		species = speciesName,
		speciesData = species,
		hpRatio = raw.pokemon_hp_ratio,
		ot = raw.pokemon_ot,
		uid = raw.pokemon_uid,
		fainted = raw.pokemon_fainted,
	}

	-- Stats only exist relative to a trainer. With no holder -- on the ground,
	-- in a depot -- we return the ratio and nothing else: an absolute HP with
	-- no owner is a made-up number.
	local holder = holderOf(item)
	if holder then
		out.holder = holder
		out.holderLevel = holder:getLevel()
		out.stats = Pokemon.calcStats(species, out.holderLevel)
		out.hp = math.floor(out.stats.hp * out.hpRatio)
	end

	return out
end

--- Create a pokemon in the player's bag.
-- @param destination optional container. Without it the item goes to the
--        player's inventory. Phase 5 uses this to place straight into the
--        Capture Bag.
-- @return the item, or nil plus a reason
function Pokemon.create(player, speciesName, ballItemId, destination)
	local species = PokemonSpecies[speciesName]
	if not species then
		return nil, "unknown species: " .. tostring(speciesName)
	end

	local id = ballItemId or Pokemon.PLACEHOLDER_BALL_ID

	local item
	if destination then
		item = destination:addItem(id, 1)
	else
		-- canDropOnMap = false: with `true`, a full bag drops the ball on the
		-- ground, and a ball on the ground is removed by the clean. Losing one
		-- to a full bag is a bug; losing one you dropped is a rule.
		item = player:addItem(id, 1, false)
	end
	if not item or item == false then
		return nil, "no room to carry it"
	end

	local uid = newUid()
	item:setCustomAttribute("pokemon_v", Pokemon.SCHEMA_VERSION)
	item:setCustomAttribute("pokemon_species", speciesName)
	item:setCustomAttribute("pokemon_hp_ratio", 1.0)
	item:setCustomAttribute("pokemon_ot", player:getGuid())
	item:setCustomAttribute("pokemon_uid", uid)
	item:setCustomAttribute("pokemon_fainted", false)

	-- The only audit trail this phase ships. Without it, "handle duplication
	-- by hand" has nowhere to start: two instances of a species are
	-- numerically identical.
	logger.info(string.format(
		"[pokemon] created uid=%.0f species=%s player=%s(%d)",
		uid, speciesName, player:getName(), player:getGuid()))

	return item
end

--- Recall: store the health fraction the pokemon came back with.
function Pokemon.recordReturn(item, hpRatio)
	assert(hpRatio >= 0.0 and hpRatio <= 1.0, "hpRatio out of 0..1: " .. tostring(hpRatio))
	item:setCustomAttribute("pokemon_hp_ratio", hpRatio)
	return item
end

--- Faint. `fainted` and a zero ratio always travel together, which is why they
-- live inside one operation rather than in the goodwill of the caller.
function Pokemon.recordFaint(item)
	item:setCustomAttribute("pokemon_fainted", true)
	item:setCustomAttribute("pokemon_hp_ratio", 0.0)
	return item
end

--- Full heal.
function Pokemon.revive(item)
	item:setCustomAttribute("pokemon_fainted", false)
	item:setCustomAttribute("pokemon_hp_ratio", 1.0)
	return item
end
