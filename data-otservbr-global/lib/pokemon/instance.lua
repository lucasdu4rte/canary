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

-- Bump when a change is NOT backward-readable by both old and new code: a
-- field renamed, removed, given a new meaning, or made `required`. An
-- additive field with a declared default and no `required` -- like
-- `pokemon_ball` below -- is readable either way and does not need one:
-- `read` already fills it in from the default on an item that predates it.
-- Bumping such a field anyway would be actively harmful here, since
-- `pokemon_v`'s own default IS `SCHEMA_VERSION` (see FIELDS) -- a bump would
-- silently relabel every old item as current instead of separating the
-- populations. When a bump IS needed, there is no repair beyond `read`
-- migrating on the way in: the old data is spread across players'
-- inventories and there is no database to run a migration against.
Pokemon.SCHEMA_VERSION = 1

-- Fallback for the species the artwork does not cover. Every other species is
-- born on its own minted id -- see `visual.lua`.
--
-- 23488 "surprise cube": you use it and something comes out, which is at least
-- the right idea. What matters are four requirements, and each one killed a
-- candidate:
--   take = true         -> without it no container accepts it  (killed 10340)
--   usable = true       -> this is what makes "Use" appear
--   multiuse = false    -> with it the client only offers "Use with ..."
--   no script on the id -> a claimed id makes one of the two Actions be
--                          **rejected silently**, and the item answers
--                          "cannot use this object"
--
-- Scripts claim ids through **tables** as well, with no `:id()` at all --
-- `decay_to.lua` has `[37111] = 37112`, which killed 37111. Counting those,
-- 28,428 datapack ids are taken, and of the 224 that are take and usable
-- without multiuse, **none of them look like a ball**.
--
-- NOTE: this comment used to claim `:id(a, b)` was a range and that it killed
-- 19065. It is not: `luaActionItemId` walks its arguments and `emplace_back`s
-- each one, so it is a plain list. The misreading came from the duplicate
-- warning, which prints `"in range from id: X, to id: Y"` while X and Y are
-- only the first and last entry of that vector (`actions.cpp:51-59`).
Pokemon.PLACEHOLDER_BALL_ID = 23488

-- Namespace for the MonsterTypes. Canary registers them as "<variant>|<name>"
-- while keeping the display name clean, which avoids colliding with a Tibia
-- monster of the same name without handling species case by case.
--
-- 🔴 This string is a CONTRACT with the map generator, and the other side of it
-- cannot see this file. `tools/build-spawns.ts` writes `pokemon|<Species>` into
-- all 82,986 spawn entries of `world/otservbr-monster.xml`, and
-- `SpawnMonster::addMonster` resolves each one as `variant + name` while the
-- map loads. Change the value here and every one of them fails with
-- "Can not find pokemon|X" -- the server still boots, the world is just empty,
-- and nothing on the TypeScript side notices. `tools/build-spawns.test.ts`
-- reads this very line and fails when the two stop matching.
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
	-- Move cooldowns, all of them, in one serialised string -- see cooldown.lua
	-- for the format. One key rather than one per move: a key per move would
	-- make `read` walk up to 14 of them per call and, worse, would leave them
	-- outside this schema, which is what `snapshot`/`restore` carries across a
	-- sprite swap. Measured 2026-07-30: outside the schema they were wiped on
	-- every single summon, since sending a pokemon out transforms the ball.
	{ key = "pokemon_cds",      kind = "string",  default = "" },
	-- Which empty ball caught this pokemon. Born without `required` and with a
	-- declared default so the balls made by `/create-pokemon` before this field
	-- existed still read back: a migration is only needed when a field is
	-- mandatory, and none of these ever left a test machine.
	{ key = "pokemon_ball",     kind = "number",  default = 0 },
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

	-- `required` was declared on the fields above and never enforced, which
	-- meant a ball missing `pokemon_ot` read back fine and then took the look
	-- down inside `nameCache[nil]`. Checking here keeps the failure in the one
	-- place that knows the schema, instead of in whichever caller happens to
	-- touch the missing field first.
	for _, field in ipairs(FIELDS) do
		if field.required and raw[field.key] == nil then
			logger.error(string.format(
				"[Pokemon.read] item is missing the required '%s' -- species=%s uid=%s",
				field.key, tostring(speciesName), tostring(raw.pokemon_uid)))
			return nil
		end
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
		ball = raw.pokemon_ball,
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
-- @param opts optional table:
--        overrideItemId -- force the item id, and therefore the SPRITE. Not the
--                          ball that caught it: passing a pokeball here wipes
--                          the species icon. Left nil by every normal caller.
--        destination    -- container to put it in. Without it the item goes to
--                          the player's inventory. Phase 5 passes the depot
--                          chest when the trainer is already carrying six.
--        ballItemId     -- the empty ball that caught it, recorded as an
--                          attribute. Nothing to do with the sprite.
-- @return the item, or nil plus a reason
function Pokemon.create(player, speciesName, opts)
	-- A stale-style call like `Pokemon.create(player, species, nil, container)`
	-- would otherwise pass silently: `opts` is nil, becomes `{}` below, and
	-- Lua just discards the fourth positional argument -- the pokemon lands
	-- in the main inventory instead of the intended destination, with nothing
	-- to say so. No caller does this today; this closes the trap before
	-- phase 5's depot-chest case opens it.
	assert(opts == nil or type(opts) == "table",
		"Pokemon.create: opts must be a table -- the old positional " ..
		"(player, speciesName, ballItemId, destination) is gone; use " ..
		"opts.ballItemId / opts.destination / opts.overrideItemId")
	opts = opts or {}

	-- `setCustomAttribute` silently writes nothing for anything but a
	-- number/string/boolean (item_functions.cpp:619-636), and the log line's
	-- `%d` further down would then throw on a bad `ballItemId` -- AFTER the
	-- item already exists in the bag with every other attribute set. Checking
	-- here, before the item is created, is what keeps a bad caller from
	-- leaving a half-written pokemon behind instead of just failing empty-handed.
	assert(opts.ballItemId == nil or type(opts.ballItemId) == "number",
		"Pokemon.create: opts.ballItemId must be a number, got " .. type(opts.ballItemId))

	local species = PokemonSpecies[speciesName]
	if not species then
		return nil, "unknown species: " .. tostring(speciesName)
	end

	-- Born with the species' own sprite. The placeholder is the fallback for
	-- the two species the artwork does not cover, not the normal case.
	local id = opts.overrideItemId or Pokemon.visualId(speciesName, "alive") or Pokemon.PLACEHOLDER_BALL_ID

	local item
	if opts.destination then
		item = opts.destination:addItem(id, 1)
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
	item:setCustomAttribute("pokemon_ball", opts.ballItemId or 0)

	-- The only audit trail this phase ships. Without it, "handle duplication
	-- by hand" has nowhere to start: two instances of a species are
	-- numerically identical.
	logger.info(string.format(
		"[pokemon] created uid=%.0f species=%s player=%s(%d) ball=%d",
		uid, speciesName, player:getName(), player:getGuid(), opts.ballItemId or 0))

	return item
end

--- Every attribute, as a plain table.
--
-- Exists for `syncVisual`, which changes the item's id and then puts the
-- attributes back. It lives here rather than there because the field list
-- lives here: a snapshot that reads a different set of keys than `read` does
-- is a Pokemon that loses whatever was added last.
function Pokemon.snapshot(item)
	local out = {}
	for _, field in ipairs(FIELDS) do
		out[field.key] = item:getCustomAttribute(field.key)
	end
	return out
end

--- Put a snapshot back, skipping absent keys so a default is not frozen in.
function Pokemon.restore(item, snapshot)
	for _, field in ipairs(FIELDS) do
		local value = snapshot[field.key]
		if value ~= nil then
			item:setCustomAttribute(field.key, value)
		end
	end
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
--
-- @return the item, **possibly a different object**: the sprite changes with
--         the state, and `transform` can replace rather than mutate. Callers
--         must use the return value.
function Pokemon.recordFaint(item)
	item:setCustomAttribute("pokemon_fainted", true)
	item:setCustomAttribute("pokemon_hp_ratio", 0.0)
	return Pokemon.syncVisual(item)
end

--- Full heal. Same return contract as `recordFaint`.
function Pokemon.revive(item)
	item:setCustomAttribute("pokemon_fainted", false)
	item:setCustomAttribute("pokemon_hp_ratio", 1.0)
	return Pokemon.syncVisual(item)
end

-- Backpacks nest, and a trainer who keeps balls in a pouch inside their bag is
-- not doing anything strange. Bounded so a pathological container tree cannot
-- turn one command into a long walk.
local MAX_CONTAINER_DEPTH = 4

local function descend(container, out, depth)
	if not container or depth > MAX_CONTAINER_DEPTH then
		return
	end
	-- 0-based: `Container:getItem` goes through getItemByIndex.
	for i = 0, container:getSize() - 1 do
		local item = container:getItem(i)
		if item then
			if Pokemon.read(item) then
				out[#out + 1] = item
			elseif item:isContainer() then
				descend(item, out, depth + 1)
			end
		end
	end
end

--- Every pokemon ball the player is carrying, equipped or bagged.
--
-- ⚠️ Returns a LIST, gathered before anything touches it, and that is the whole
-- reason it is not a callback that visits items as it finds them. `revive` and
-- `recordFaint` go through `syncVisual`, which calls `transform` -- and
-- transform's destructive path hands back a **different object**, so mutating
-- during the walk would be reshaping the containers being walked. Gather first,
-- act second.
--
-- `Pokemon.read` returns nil for anything that is not a ball, which is what
-- makes this safe to run over a whole inventory.
function Pokemon.carriedBalls(player)
	local out = {}
	for slot = CONST_SLOT_FIRST, CONST_SLOT_LAST do
		local item = player:getSlotItem(slot)
		if item then
			if Pokemon.read(item) then
				out[#out + 1] = item
			elseif item:isContainer() then
				descend(item, out, 1)
			end
		end
	end
	return out
end
