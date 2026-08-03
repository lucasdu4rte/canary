-- Using a move: one executor, driven by the table.
--
-- The counter-example is Roxy's `docastspell`: an if/elseif some 3,000 lines
-- long over move NAME, one hand-written branch per attack. It works and it is
-- impossible to maintain -- the same disease phase 3 diagnosed in item ids
-- navigated by `itemid +- 1`.
--
-- With 360 moves that is not a style preference. It is the difference between a
-- table the build emits and three thousand lines nobody reviews. So: no move
-- name appears in an `if` below. Shape, element and effect all come from the
-- catalogue, and a new behaviour is a row in the table rather than a branch here.

Pokemon = Pokemon or {}

-- Pokemon type -> Tibia combat type, hit effect and projectile.
--
-- Cosmetic only. The generated MonsterTypes carry `elements = {}`,
-- `immunities = {}` and zero armor/defense/mitigation, so the engine applies no
-- resistance of its own and `Pokemon.multiplier` remains the only multiplier in
-- play. Were that to change, this table would start double-counting.
--
-- Eighteen types map onto the eight damage types Tibia has, so the collisions
-- are unavoidable and only affect the colour of the splash.
--
-- 🔴 Per TYPE and not per move, deliberately. Roxy has one per move, but only
-- for 71 of 335, and their ids point at their own client's custom sprites --
-- carrying those over would put an arbitrary picture on four moves in five. The
-- spec settles it: while the art is placeholder the effects are vanilla Tibia.
-- When real art arrives this becomes a column in the move table, and the shape
-- of this file does not change.
local COMBAT_BY_TYPE = {
	normal = { COMBAT_PHYSICALDAMAGE, CONST_ME_HITAREA, CONST_ANI_LARGEROCK },
	fighting = { COMBAT_PHYSICALDAMAGE, CONST_ME_BLACKSMOKE, CONST_ANI_WHIRLWINDCLUB },
	flying = { COMBAT_PHYSICALDAMAGE, CONST_ME_STONES, CONST_ANI_ETHEREALSPEAR },
	poison = { COMBAT_EARTHDAMAGE, CONST_ME_POISONAREA, CONST_ANI_POISONARROW },
	ground = { COMBAT_EARTHDAMAGE, CONST_ME_CARNIPHILA, CONST_ANI_EARTH },
	rock = { COMBAT_PHYSICALDAMAGE, CONST_ME_STONES, CONST_ANI_LARGEROCK },
	bug = { COMBAT_EARTHDAMAGE, CONST_ME_GREEN_RINGS, CONST_ANI_ENVENOMEDARROW },
	ghost = { COMBAT_DEATHDAMAGE, CONST_ME_MORTAREA, CONST_ANI_SUDDENDEATH },
	steel = { COMBAT_PHYSICALDAMAGE, CONST_ME_BLOCKHIT, CONST_ANI_SPEAR },
	fire = { COMBAT_FIREDAMAGE, CONST_ME_FIREAREA, CONST_ANI_FIRE },
	water = { COMBAT_ICEDAMAGE, CONST_ME_WATERSPLASH, CONST_ANI_ICE },
	grass = { COMBAT_EARTHDAMAGE, CONST_ME_PLANTATTACK, CONST_ANI_LEAFSTAR },
	electric = { COMBAT_ENERGYDAMAGE, CONST_ME_ENERGYAREA, CONST_ANI_ENERGYBALL },
	psychic = { COMBAT_ENERGYDAMAGE, CONST_ME_MAGIC_RED, CONST_ANI_ENERGY },
	ice = { COMBAT_ICEDAMAGE, CONST_ME_ICEATTACK, CONST_ANI_ICE },
	dragon = { COMBAT_ENERGYDAMAGE, CONST_ME_DRAGONHEAD, CONST_ANI_ENERGYBALL },
	dark = { COMBAT_DEATHDAMAGE, CONST_ME_MORTAREA, CONST_ANI_SUDDENDEATH },
	fairy = { COMBAT_HOLYDAMAGE, CONST_ME_HOLYDAMAGE, CONST_ANI_HOLY },
}

local FALLBACK_COMBAT = { COMBAT_PHYSICALDAMAGE, CONST_ME_HITAREA, CONST_ANI_LARGEROCK }

-- "draw nothing", written as the number it is.
--
-- ⚠️ `CONST_ME_NONE` exists in C++ (utils_definitions.hpp:59, first in the enum,
-- so 0) but is NOT registered in Lua -- lua_enums.cpp:429 registers its
-- projectile counterpart CONST_ANI_NONE and not this one. Spelling the name here
-- would pass **nil**, and `Lua::getNumber` turns nil into 0, which happens to be
-- the right value: correct behaviour, no error, and nothing anywhere to say the
-- constant was never real. Exactly the shape of the silent nil that cost this
-- file 191 area moves once already.
local NO_EFFECT = 0

--- The species whose move list applies to this pokemon.
--
-- Today it is simply its own species, and the indirection still earns its keep:
-- Ditto has no moves until it transforms, and afterwards has the moves of
-- whatever it copied. Phase 4 does not implement Transform, but every consumer
-- reading `PokemonSpecies[mon.species].moves` directly would have to be
-- rewritten when it arrives. Roxy has this exact seam, resolving Ditto to the
-- copied species before looking a move up.
--
-- It also settles today's case for free: a species with zero moves cannot break
-- combat. Ditto is the only one, and it is real data rather than a gap.
function Pokemon.effectiveSpecies(mon)
	return mon.species
end

--- Highest slot any species fills, so callers can size a UI or a command set.
--
-- Computed rather than written down: the roster tops out at 14 today and the
-- number is a property of the data, not a decision. A hardcoded ceiling would
-- silently swallow the fifteenth move the day one appears.
--
-- It agrees with the source: the PxG wiki labels the rows M1..M14, and those
-- labels follow row order inside the PvE table. That is what makes position the
-- slot -- the labels confirm the order rather than define it, which matters
-- because a few are mistyped (Butterfree's third row is labelled M1).
Pokemon.MAX_MOVE_SLOTS = (function()
	local most = 0
	for _, species in pairs(PokemonSpecies) do
		local count = #(species.moves or {})
		if count > most then
			most = count
		end
	end
	return most
end)()

--- Slots a player can actually reach from the keyboard.
--
-- Twelve, because the moves get bound to F1..F12 and there is no F13. This is a
-- limit of the input device, not of the data -- which is why it is a second
-- constant rather than a smaller MAX_MOVE_SLOTS.
--
-- ⚠️ Three species carry more than this: Articuno, Zapdos and Moltres have 14,
-- so their last two moves have no key. That is a real gap and it is left
-- VISIBLE -- `!moves` marks them, and the god-only `!move <name>` still reaches
-- them. Trimming the catalogue instead would mean choosing which two legendary
-- moves to delete, which is a balance decision and not one to make silently in
-- a UI constant.
Pokemon.KEYBOUND_SLOTS = 12

--- Name of the move in a slot, or nil when the slot is empty for this species.
function Pokemon.moveInSlot(mon, slot)
	local species = PokemonSpecies[Pokemon.effectiveSpecies(mon)]
	if not species then
		return nil
	end
	local entry = (species.moves or {})[slot]
	return entry and entry.name or nil
end

--- The catalogue entry for a move this pokemon knows, or nil.
-- Carries the per-species cooldown, which is why it is not read from PokemonMoves.
function Pokemon.knownMove(mon, moveName)
	local species = PokemonSpecies[Pokemon.effectiveSpecies(mon)]
	if not species then
		return nil
	end
	for _, entry in ipairs(species.moves or {}) do
		if entry.name == moveName then
			return entry
		end
	end
	return nil
end

--- A creature as the damage formula needs it, or nil if it is not a pokemon.
--
-- The display name of a generated MonsterType is the clean species name, so it
-- is the catalogue key. A summoned pokemon takes its owner's level; a wild one
-- takes the level of where it stands.
function Pokemon.combatantOf(creature)
	if not creature then
		return nil
	end
	local species = PokemonSpecies[creature:getName()]
	if not species then
		return nil
	end

	local master = creature:getMaster()
	local level = (master and master:isPlayer())
		and Pokemon.effectiveLevel(master:getLevel())
		or Pokemon.wildLevel(creature:getName(), creature:getPosition())

	return {
		creature = creature,
		speciesData = species,
		stats = Pokemon.calcStats(species, level),
		effectiveLevel = level,
	}
end

-- One Combat, BUILT AT LOAD TIME, and it carries no area at all.
--
-- 🔴 There used to be four -- one per behaviour -- with `createCombatArea` on
-- three of them, and the engine delivered a whole blast as ONE number. That is
-- what made an area move need a defender before it could fire: `Combat` applies
-- a single value to everything it touches, so the executor had to nominate
-- somebody for the formula, and with nobody in reach it refused outright --
-- "Fire Blast has nothing in reach", for a move that detonates around the
-- pokemon and does not care who was picked.
--
-- The shape is walked here now and each victim is hit on its own, so the formula
-- runs once per victim against that victim's defence and its own type chart.
-- Two things fall out of that: a move no longer needs anybody to be there, and
-- the collateral stops inheriting the primary target's effectiveness -- a
-- Flamethrower aimed at a grass pokemon beside a water one used to hit BOTH for
-- the super-effective number.
--
-- Roxy reaches the same place from the other side: `doMoveInArea2` walks the
-- area's tiles and calls the damage per creature it finds, and the tiles with
-- nobody standing on them still get the effect.
--
-- ⚠️ `createCombatArea` and `Combat:setArea` still refuse to run outside script
-- loading -- `env->getScriptId() != EVENT_ID_LOADING` in global_functions.cpp:272
-- and combat_functions.cpp:91 -- and still fail by logging a line and returning
-- nil rather than raising, which is how 191 area moves once spent weeks being
-- delivered as single target with nothing in play to show it. Nothing below
-- calls either of them any more, so that trap is closed rather than avoided.
--
-- Mutating the one shared object is safe for the same reason it always was: a
-- hit is set up and executed inside one call with no yield in between. The area
-- loop does that once per victim, in sequence.
local HIT = Combat()

-- The three shapes the plan asked to start from -- single target, a burst
-- centred on the target, a beam in a direction -- plus `self`, which the wiki
-- marks and 5 damaging moves carry. `target` gets no shape: it lands on one
-- creature and there is no geometry to walk for that.
--
-- ⚠️ The matrices are written out here rather than taken from the core's
-- AREA_CIRCLE3X3 and AREA_BEAM5, because those live in
-- `data/scripts/lib/register_spells.lua`, which the engine loads AFTER `lib.lua`
-- -- so referencing them from here passes nil, and a nil shape now means a move
-- that covers nothing instead of one that quietly falls back to single target.
--
-- `3` marks the origin, and the matrices are written pointing NORTH; `rotated`
-- below turns them, which is what makes one beam serve all four ways.
local BURST = {
	{ 0, 0, 1, 1, 1, 0, 0 },
	{ 0, 1, 1, 1, 1, 1, 0 },
	{ 1, 1, 1, 1, 1, 1, 1 },
	{ 1, 1, 1, 3, 1, 1, 1 },
	{ 1, 1, 1, 1, 1, 1, 1 },
	{ 0, 1, 1, 1, 1, 1, 0 },
	{ 0, 0, 1, 1, 1, 0, 0 },
}

local BEAM = {
	{ 1 },
	{ 1 },
	{ 1 },
	{ 1 },
	{ 3 },
}

--- Offsets a matrix covers, relative to its origin cell.
--
-- The same reading the engine does: `3` marks the origin, anything non-zero is
-- covered, and the cell at (row y, column x) lands at (x - originX, y - originY)
-- from the point of impact -- `AreaCombat::getList`, combat.cpp:1393.
--
-- Derived from the matrix rather than written out a second time, because the
-- effect the player sees and the set of creatures that get hit both come from
-- this list. Two lists would be two chances to disagree, and a blast that draws
-- one shape while damaging another is invisible until somebody counts.
local function offsetsOf(matrix)
	local originX, originY
	for y, row in ipairs(matrix) do
		for x, cell in ipairs(row) do
			if cell == 3 then
				originX, originY = x, y
			end
		end
	end

	local offsets = {}
	for y, row in ipairs(matrix) do
		for x, cell in ipairs(row) do
			if cell ~= 0 then
				offsets[#offsets + 1] = { x - originX, y - originY }
			end
		end
	end
	return offsets
end

-- ⚠️ Keep the keys in step with `Behavior` in tools/pxg.ts and with
-- VALID_BEHAVIORS in scripts/talkactions/god/check_moves.lua. A behaviour
-- missing from here is a move that covers no tiles at all.
local SHAPE = {
	aoe = offsetsOf(BURST),
	beam = offsetsOf(BEAM),
	self = offsetsOf(BURST),
}

--- Zero, and not the other zero.
--
-- 🔴 The engine runs LuaJIT (vcpkg.json, cmake/modules/BaseConfig.cmake:46), so
-- every number is a double and `-0` is a value in its own right: negating a zero
-- offset produces negative zero. It compares equal to 0 and adds like 0, so the
-- tiles come out right -- but it PRINTS as "-0", and anything that keys an
-- offset by its text sees "-0:0" and "0:0" as two different tiles.
--
-- Measured rather than guessed: /check-area reported the burst asymmetric in
-- three directions out of four with the shape perfectly correct, because three
-- of the four rotations negate. A validator that cries wolf is worse than none,
-- so the zero is normalised here, once, where the negation happens.
local function zeroed(n)
	return n == 0 and 0 or n
end

--- Turn a north-facing offset to point `direction`.
local function rotated(offset, direction)
	local dx, dy = offset[1], offset[2]
	if direction == DIRECTION_EAST then
		return zeroed(-dy), zeroed(dx)
	elseif direction == DIRECTION_SOUTH then
		return zeroed(-dx), zeroed(-dy)
	elseif direction == DIRECTION_WEST then
		return zeroed(dy), zeroed(-dx)
	end
	return zeroed(dx), zeroed(dy)
end

--- The footprint of a shape, as {dx, dy} offsets from where it lands.
--
-- Public so the geometry can be checked without a fight: /check-area counts it
-- and walks it in all four directions. Everything that draws or damages a blast
-- goes through here, so a footprint that reads right there is the one that
-- fires -- which is the property the old engine-side area could not be asked
-- about at all, and why it went 191 moves wrong in silence.
--
-- @return a list of {dx, dy}, empty for a behaviour with no shape
function Pokemon.shapeOffsets(behavior, direction)
	local offsets = SHAPE[behavior]
	if not offsets then
		return {}
	end

	local turned = {}
	for i, offset in ipairs(offsets) do
		local dx, dy = rotated(offset, direction)
		turned[i] = { dx, dy }
	end
	return turned
end

--- Which way a blast points, by the engine's own rule.
--
-- Copied from `AreaCombat::getArea` (combat.cpp:1424) rather than approximated,
-- so a beam comes out where it used to: x decides first, and only a dead heat on
-- x lets y speak. A blast centred on the caster itself is dx = dy = 0 and falls
-- through to SOUTH there -- which is exactly why a move with no target reads the
-- pokemon's own facing instead of calling this.
local function directionOfBlast(from, centre)
	local dx, dy = centre.x - from.x, centre.y - from.y
	if dx < 0 then
		return DIRECTION_WEST
	elseif dx > 0 then
		return DIRECTION_EAST
	elseif dy < 0 then
		return DIRECTION_NORTH
	end
	return DIRECTION_SOUTH
end

--- How far a shaped move reaches, in tiles from its centre.
--
-- The burst matrix is 7x7 and the beam runs 4, so 3 is what the shape actually
-- covers. It is what an area move reaches, INSTEAD of `move.range` -- 191 of the
-- 360 moves carry range 1 from Roxy while exploding across half a screen, and
-- reading the range there would understate them by half a screen.
--
-- Nothing refuses a trainer's shaped move over this any more. What it still
-- decides is WHERE: a target further than this leaves the blast centred on the
-- pokemon, and a wild only considers the moves whose reach covers the distance.
Pokemon.AREA_RADIUS = 3

--- Is this creature standing on a protection-zone tile?
local function inProtectionZone(creature)
	local tile = creature and creature:getTile()
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

-- @param quiet  a hit inside a blast that has already drawn itself
local function combatFor(move, damage, quiet)
	local flavour = COMBAT_BY_TYPE[move.type] or FALLBACK_COMBAT

	HIT:setParameter(COMBAT_PARAM_TYPE, flavour[1])

	-- `quiet` exists because the blast draws every tile it covers, occupied or
	-- not. Letting each victim's hit draw again would make the crowded part of
	-- an area flash twice and the empty part once, which reads as two attacks.
	HIT:setParameter(COMBAT_PARAM_EFFECT, quiet and NO_EFFECT or flavour[2])

	-- Fixed both ends: the roll already happened in Pokemon.damage, and letting
	-- the engine roll again would stack two sources of variance -- one of them
	-- invisible from the formula that is supposed to own it.
	--
	-- ⚠️ The signature is (type, mina, minb, maxa, maxb), and COMBAT_FORMULA_DAMAGE
	-- reads **mina and maxa** -- `normal_random(mina, maxa)` in combat.cpp:80.
	-- The b arguments are ignored for this formula type. Passing the damage as
	-- b, which is the shape most datapack spells use, rolls normal_random(0, 0)
	-- and every move lands for nothing: the effect plays, the message prints,
	-- the cooldown starts, and the target does not lose a hitpoint.
	HIT:setFormula(COMBAT_FORMULA_DAMAGE, -damage, 0, -damage, 0)

	-- A projectile only when there is a distance for it to cross. 59 of the 360
	-- moves reach past the next square, and without this the hit simply appeared
	-- on a target ten squares away with nothing having travelled there.
	--
	-- Always set, never left alone: the object is shared, so a contact move
	-- following a ranged one would inherit its projectile and throw a spear at
	-- something it is standing next to. A blast fires one projectile at the
	-- place it lands, so the per-victim hits inside it carry none.
	HIT:setParameter(
		COMBAT_PARAM_DISTANCEEFFECT,
		(not quiet and move.range and move.range > 1) and flavour[3] or CONST_ANI_NONE
	)

	return HIT
end

--- Deliver a hit, and let the target hit back.
--
-- Public because it is the one place a move's damage reaches a creature: the
-- projectile and the retaliation both live here, so anything that wants to land
-- a move goes through it rather than building its own combat.
--
-- The one place damage reaches a creature, so it is the one place that knows a
-- fight just started. A wild has `hostile = false` -- it does not pick a fight
-- -- and nothing else ever hands it a target, so without this it stands there
-- being hit and never swings: reported from play, and true of every wild.
--
-- Retaliation only. It takes the attacker as its target if it has none, which
-- leaves a wild already fighting someone else alone, and never touches a
-- summon, whose target belongs to its trainer.
--
-- ⚠️ The engine still owns whether the hit is ALLOWED. `Combat::doCombatHealth`
-- gates a single target on `canDoCombat` (combat.cpp:1520), and the trainer
-- guard rides `onHealthChange` in creaturescripts/pokemon_damage_rules.lua
-- rather than target selection. Both hold for every victim the area loop below
-- proposes, which is why walking a shape in Lua does not hand a pokemon a way
-- past protection zones, PvP rules or its own trainer.
function Pokemon.deliver(attacker, target, move, damage, quiet)
	combatFor(move, damage, quiet):execute(attacker, Variant(target:getId()))

	-- A dummy is the exception, and the only one: giving it a target is what
	-- would make it chase, and a target that chases is not a measurement.
	if not target:isRemoved() and not target:getMaster() and not target:getTarget()
		and not Pokemon.isDummy(target) then
		target:setTarget(attacker)
	end
end

--- The tiles a shaped move covers, given where it lands and which way it points.
local function coveredBy(behavior, from, centre, direction)
	local covered = {}
	for _, offset in ipairs(Pokemon.shapeOffsets(behavior, direction)) do
		local pos = Position(centre.x + offset[1], centre.y + offset[2], centre.z)
		local tile = pos:getTile()

		-- The same two rules the engine applies while building an area
		-- (`AreaCombat::getList`, combat.cpp:1400-1410): a floor change is not
		-- part of the blast, and neither is anything the caster cannot see.
		-- Without the second one a burst reaches straight through a wall.
		if tile and not tile:hasFlag(TILESTATE_FLOORCHANGE) and from:isSightClear(pos, true) then
			covered[#covered + 1] = pos
		end
	end
	return covered
end

--- Every pokemon standing on the covered tiles, the caster excluded.
--
-- Only pokemon, because a pokemon move works on pokemon -- the same rule the
-- single-target path states as "Pokemon moves only work on other pokemon", and
-- it is what keeps a blast from mowing down the Tibia content standing nearby.
-- Players fail the test for free: no player is a catalogue species.
--
-- Summons are NOT filtered out, unlike the target-picking this replaces. That
-- one excluded them so a trainer standing beside a friend never had their
-- pokemon choose the friend's as the thing to explode on -- a rule about
-- CHOOSING. Being inside a blast is not a choice, and whether a summon may be
-- hurt is the engine's call, made per victim in Pokemon.deliver.
local function victimsUnder(attacker, covered)
	local victims = {}
	for _, pos in ipairs(covered) do
		local tile = pos:getTile()
		for _, creature in ipairs(tile and tile:getCreatures() or {}) do
			if creature:getId() ~= attacker:getId() and PokemonSpecies[creature:getName()] then
				victims[#victims + 1] = creature
			end
		end
	end
	return victims
end

--- Fire a shaped move: draw it, then hit each pokemon under it on its own terms.
--
-- Nobody has to be standing there. That is the whole point of the shape living
-- in Lua: the tiles are drawn from the matrix, the formula runs per victim, and
-- a blast with an empty area is simply a blast that hit nothing -- it still
-- fires, still draws and still goes on cooldown.
--
-- @param attacker  a combatant, from Pokemon.combatantOf
-- @param primary   the creature the trainer picked, when there was one
-- @return how many were hit, and the effectiveness against `primary` if it was
--         among them
function Pokemon.deliverArea(attacker, move, centre, direction, primary)
	local from = attacker.creature:getPosition()
	local flavour = COMBAT_BY_TYPE[move.type] or FALLBACK_COMBAT
	local covered = coveredBy(move.behavior, from, centre, direction)

	-- One projectile, to where the blast lands. Per victim it would read as
	-- several attacks rather than one, and a blast centred on the pokemon has
	-- nothing to cross at all.
	if move.range and move.range > 1 and from:getDistance(centre) > 0 then
		from:sendDistanceEffect(centre, flavour[3])
	end

	for _, pos in ipairs(covered) do
		pos:sendMagicEffect(flavour[2])
	end

	local hits, primaryEffectiveness = 0, nil
	for _, victim in ipairs(victimsUnder(attacker.creature, covered)) do
		local defender = Pokemon.combatantOf(victim)
		if defender then
			local damage, effectiveness = Pokemon.damage(attacker, defender, move)
			Pokemon.deliver(attacker.creature, victim, move, damage, true)
			hits = hits + 1
			if primary and victim:getId() == primary:getId() then
				primaryEffectiveness = effectiveness
			end
		end
	end
	return hits, primaryEffectiveness
end

local EFFECTIVENESS_TEXT = {
	["0"] = "It has no effect",
	["0.25"] = "It is barely effective",
	["0.5"] = "It is not very effective",
	["2"] = "It is super effective",
	["4"] = "It is devastating",
}

--- Order of refusal, and the reason for it.
--
--   not yours / nothing out   -> no pokemon to give the order to
--   move unknown to species   -> a trainer error
--   move missing from table   -> a DATA error, logged loud, never silent
--   power == 0                -> refused with a message, cooldown NOT consumed
--   caster in a protection zone -> refused, whatever the shape
--   on cooldown               -> refused, with the time left
--   then and only then        -> consume the cooldown and deal the damage
--
-- The `power == 0` refusal covers 102 of the 360 moves. Without it, better than
-- one button in four does nothing at all and is indistinguishable from a broken
-- move. There is no accuracy roll in this phase, so every use that gets past
-- these checks lands -- which is what makes consuming the cooldown here fair.
--
-- 🔴 A SHAPED move is not on that list past the cooldown, and that is the point.
-- It used to be refused for having no target, for a target that was not a
-- pokemon, for a target inside a temple and for a target out of range -- four
-- ways to be told no about a move that detonates around the pokemon and does not
-- consult the target for anything but where to centre. Reported from play as
-- "Fire Blast has nothing in reach" with the trainer standing in the open. All
-- four are now the same thing: the blast centres on the pokemon instead, and
-- fires. What the target still decides is WHERE, never WHETHER.
--
-- @return true, or false plus a message for the player
function Pokemon.useMove(player, moveName)
	local entry = Pokemon.getActive(player)
	if not entry then
		return false, "You have no pokemon at your side."
	end

	local mon = Pokemon.read(entry.item)
	if not mon then
		return false, "That pokemon cannot be read."
	end

	local known = Pokemon.knownMove(mon, moveName)
	if not known then
		return false, string.format("%s does not know %s.", mon.species, moveName)
	end

	local move = PokemonMoves[known.name]
	if not move then
		-- Data error, not a player error: the catalogue references a move it
		-- does not describe. /check-moves exists to catch this before a player does.
		logger.error(string.format(
			"[Pokemon.useMove] '%s' is in %s's move list but missing from PokemonMoves",
			tostring(known.name), tostring(mon.species)))
		return false, "That move is not available."
	end

	if move.power <= 0 then
		return false, string.format("%s has no effect yet.", known.name)
	end

	local attacker = Pokemon.combatantOf(entry.creature)
	if not attacker then
		return false, "That pokemon cannot fight."
	end

	-- No fighting in a protection zone. Checked on the CASTER only, and for
	-- every shape.
	--
	-- The engine already half-enforces it -- a familiar cannot start attacking
	-- while it stands in one -- but only half, and silently: the order would be
	-- accepted, the cooldown consumed, and nothing would happen.
	--
	-- The other half, hitting something that stepped into a temple, used to be a
	-- refusal here too. It still holds, but the engine is what holds it now:
	-- `canDoCombat` runs per victim inside Pokemon.deliver, so a blast covering
	-- a temple tile leaves whoever stands on it alone without the whole move
	-- having to be called off for their sake.
	if inProtectionZone(entry.creature) then
		return false, string.format("%s cannot fight inside a protection zone.", mon.species)
	end

	-- What the move actually reaches. A shaped move covers the shape, not the
	-- one-tile `range` the table carries for it.
	local shaped = move.behavior ~= "target"
	local reach = shaped and math.max(move.range, Pokemon.AREA_RADIUS) or move.range

	local target = player:getTarget()
	if target and target:isRemoved() then
		target = nil
	end

	local from = entry.creature:getPosition()
	local defender, centre, direction, primary

	-- Point the pokemon at what its trainer picked, BEFORE anything can refuse.
	--
	-- Nothing in Canary does this: `Player::setAttackedCreature` moves the
	-- player alone, and no summon path propagates a target. Ours are
	-- `hostile = false` besides, so they never pick one up on their own --
	-- measured, the summon sat at `target = nil` with a wild two squares away.
	--
	-- Ahead of the range check so the first press starts the approach rather
	-- than being a wasted keystroke: 237 of the 323 moves the range table
	-- covers reach one square, so refusing without engaging would mean the
	-- normal case is press, nothing, walk yourself, press again.
	if target then
		entry.creature:setTarget(target)
	end

	if shaped then
		-- Centred on the pokemon, pointing wherever it faces, unless the trainer
		-- picked something a blast can usefully land on. Every condition below
		-- that fails is a REASON TO RECENTRE, never a reason to refuse.
		centre, direction = from, entry.creature:getDirection()

		-- `self` is centred on the caster by definition -- Rage, Shadow Claw,
		-- Furious Legs, Clear Smog and Vital Spirit -- so it never reads the
		-- target at all.
		if target and move.behavior ~= "self"
			and Pokemon.combatantOf(target)
			and not inProtectionZone(target)
			and from:getDistance(target:getPosition()) <= reach then
			centre = target:getPosition()
			direction = directionOfBlast(from, centre)
			primary = target
		end
	else
		-- A single target move still asks for one: "attack that one" is the
		-- order itself, and guessing which would be the command deciding the
		-- fight.
		if not target then
			return false, "Choose a target first."
		end

		defender = Pokemon.combatantOf(target)
		if not defender then
			return false, "Pokemon moves only work on other pokemon."
		end

		if inProtectionZone(target) then
			return false, string.format("%s is inside a protection zone.", target:getName())
		end

		if from:getDistance(target:getPosition()) > reach then
			return false, string.format("%s only reaches %d square%s away - %s is closing in.",
				known.name, reach, reach == 1 and "" or "s", mon.species)
		end
	end

	local left = Pokemon.moveCooldownLeft(entry.item, known.name)
	if left > 0 then
		return false, string.format("%s is not ready: %d second%s left.",
			known.name, left, left == 1 and "" or "s")
	end

	Pokemon.markMoveUsed(entry.item, known.name, known.cooldown)

	local effectiveness
	if shaped then
		_, effectiveness = Pokemon.deliverArea(attacker, move, centre, direction, primary)
	else
		local damage
		damage, effectiveness = Pokemon.damage(attacker, defender, move)
		Pokemon.deliver(entry.creature, target, move, damage)
	end

	-- Only when there is somebody the note is ABOUT. A blast that hit nothing,
	-- or one centred on the pokemon with no target picked, has no effectiveness
	-- to report, and inventing "It is super effective!" over an empty field
	-- would be the message lying about a fight that did not happen.
	local note = effectiveness and EFFECTIVENESS_TEXT[tostring(effectiveness)]
	player:sendTextMessage(MESSAGE_STATUS, string.format(
		"%s used %s.%s", mon.species, known.name, note and (" " .. note .. "!") or ""))

	return true
end

-- ─── the second clock ────────────────────────────────────────────────────────
--
-- Roxy runs two cadences and we only had one: an automatic attack every
-- 2.6-5.6s from the MonsterType, and the trainer's ordered move every 20-40s.
-- With only the ordered move, a fight is a handful of hits separated by half a
-- minute of standing still -- which is also what made raising HP impossible,
-- since every extra point of health became more waiting rather than more fight.
--
-- Ours is not a MonsterType attack but a synthetic move run through the same
-- Pokemon.damage and the same combat delivery. That keeps one damage path
-- instead of two, so effectiveness, STAB and the stat split apply here exactly
-- as they do to an ordered move.

--- Seconds between automatic attacks. Roxy's monsters sit at 2.6-5.6s.
Pokemon.AUTO_ATTACK_INTERVAL = 3

--- Power of the automatic attack.
--
-- Filler between ordered moves, not a substitute for them: at 3s a piece, ten of
-- these land inside one 30s cooldown.
--
-- 🔴 Was 10, and 10 was measured on one pair rather than on the roster. Swept
-- across all 23,562 matchups at matched levels, power 10 carried **41% of the
-- target's health per 30s** at the median -- against roughly 23% for an ordered
-- move, so the filler was doing about two thirds of all damage in a game whose
-- whole point is the moves. Power 5 puts the median at 24% and the melee at 20%
-- of total output, which is the share it should have.
Pokemon.AUTO_ATTACK_POWER = 5

--- Ceiling on one automatic attack, as a fraction of the defender's health.
--
-- The median was never the real complaint; the tail was. Reported from play as
-- "80k in a melee", and measured, the spread runs to **299% of the target's
-- health per 30s** -- an automatic attack that ends a fight on its own. It comes
-- from the physical/special split: Chansey has 5 base defence against 105 base
-- special defence, so a physical melee against it is amplified some twentyfold
-- and no amount of tuning `power` reaches that without flattening everything.
--
-- 4% is chosen to cut the tail and leave the body alone: it binds in 17% of
-- matchups, holds the worst case to 40% of health per 30s, and moves the median
-- not at all. A clamp that bit the median would turn the melee into a flat
-- fraction of health and delete the stat interaction it exists to express.
--
-- ⚠️ Measured against `defender.stats.hp` -- the health the FORMULA gives that
-- species at that level -- and not against `getMaxHealth()`. A training dummy
-- carries an absurd maximum on purpose, and reading the creature would quietly
-- lift the ceiling off exactly where the number is being watched.
Pokemon.AUTO_ATTACK_MAX_SHARE = 0.04

--- The automatic attack, as a move.
local AUTO_ATTACK_MOVE = {
	power = Pokemon.AUTO_ATTACK_POWER,
	-- No type, and that is the point: no STAB, no effectiveness, no immunity.
	-- Element belongs to moves. Measured with the attacker's own first type
	-- instead, 74 of the 154 species had a matchup where their melee did
	-- nothing -- Snorlax against a ghost, Pikachu against a ground -- which is
	-- half the roster losing one of its two clocks in silence. Roxy arrives at
	-- the same place: their melee is physical and never consults a type.
	type = nil,
	damageClass = "physical",
	range = 1,
	behavior = "target",
}

--- Run one automatic attack if this creature has a target it can reach.
-- @return true if it attacked
function Pokemon.autoAttack(creature)
	if not creature or creature:isRemoved() then
		return false
	end

	-- A dummy never swings, whatever species it wears. Retaliation is already
	-- suppressed for it, but a hostile species picks its own target through
	-- `searchTarget` and would melee anything that walked up -- so /dummy
	-- Charizard would behave differently from /dummy Chansey, which defeats
	-- choosing the species freely.
	if Pokemon.isDummy(creature) then
		return false
	end

	local target = creature:getTarget()
	if not target or target:isRemoved() then
		return false
	end

	-- Same protection-zone rule as an ordered move, and for the same reason:
	-- a safe tile has to be safe from both directions.
	if inProtectionZone(creature) or inProtectionZone(target) then
		return false
	end

	local attacker = Pokemon.combatantOf(creature)
	local defender = Pokemon.combatantOf(target)
	if not attacker or not defender then
		return false
	end

	local move = AUTO_ATTACK_MOVE
	if creature:getPosition():getDistance(target:getPosition()) > move.range then
		return false
	end

	local damage = Pokemon.damage(attacker, defender, move)

	-- Clamped after the formula rather than inside it, so the cap applies to this
	-- attack alone. An ordered move that lands for half a health bar is a move
	-- doing its job; the same number ten times a cycle is not.
	local ceiling = math.floor(defender.stats.hp * Pokemon.AUTO_ATTACK_MAX_SHARE)
	if ceiling > 0 and damage > ceiling then
		damage = ceiling
	end

	Pokemon.deliver(creature, target, move, damage)
	return true
end

-- ─── the wild's own moves ────────────────────────────────────────────────────
--
-- 🔴 A wild had ONE clock. `Pokemon.useMove` is the trainer's interface and
-- nothing else ever reached the move table, so every wild on the map -- whatever
-- species, whatever movepool -- could only ever headbutt. Reported from play,
-- and it is half the fight missing: a Dragonite and a Caterpie fought
-- identically apart from their stats.
--
-- Same executor as an ordered move, deliberately. `Pokemon.damage` and
-- `Pokemon.deliver` do not care who asked, so effectiveness, STAB, the stat
-- split, the shapes and the projectiles all arrive here for free. A second
-- implementation is how the two sides drift apart.

--- Seconds a wild waits between one move and the next.
--
-- Measured against what the interface allows a player: 9 moves at a median
-- cooldown of 25s means a trainer pressing everything the moment it lights up
-- gets a move out roughly every 3 seconds. 12 makes the wild four times
-- steadier than a player at full tilt -- present in every exchange, never the
-- one setting the pace. The per-move cooldowns still apply underneath.
Pokemon.WILD_MOVE_INTERVAL = 12

-- Cooldowns for creatures that have no ball to keep them in.
--
-- A trainer's cooldowns live in the item, because they have to survive a recall
-- -- that is the exploit the ball-storage design exists to close. A wild has no
-- item and no reason to outlive the fight, so memory is the honest place.
--
-- ⚠️ Keyed by creature id, which outlives the creature. Worst case a fresh wild
-- inherits a dead one's timers and waits, which is why it is only ever a delay
-- and never a free hit. `Pokemon.forgetWild` clears it when the creature goes.
local wildReadyAt = {}
local wildNextMove = {}

--- Drop a departed wild's timers.
function Pokemon.forgetWild(id)
	wildReadyAt[id] = nil
	wildNextMove[id] = nil
end

--- Let a wild throw one of its own moves, if it has one ready and in reach.
-- @return true plus the move's name if it fired
function Pokemon.wildMove(creature)
	if not creature or creature:isRemoved() then
		return false
	end

	-- Only the ownerless. A summon's moves belong to its trainer's keyboard, and
	-- a pokemon that cast on its own would be taking the fight out of their hands.
	if creature:getMaster() then
		return false
	end
	if Pokemon.isDummy(creature) then
		return false
	end

	local target = creature:getTarget()
	if not target or target:isRemoved() then
		return false
	end

	-- Same protection-zone rule as everything else: a safe tile is safe from
	-- both directions.
	if inProtectionZone(creature) or inProtectionZone(target) then
		return false
	end

	local attacker = Pokemon.combatantOf(creature)
	local defender = Pokemon.combatantOf(target)
	if not attacker or not defender then
		return false
	end

	local id, now = creature:getId(), os.time()
	if (wildNextMove[id] or 0) > now then
		return false
	end

	local ready = wildReadyAt[id]
	if not ready then
		ready = {}
		wildReadyAt[id] = ready
	end

	local distance = creature:getPosition():getDistance(target:getPosition())

	-- Everything it could throw this instant. Built fresh each time because
	-- reach depends on where the target is standing right now.
	local options = {}
	for _, entry in ipairs(attacker.speciesData.moves or {}) do
		local move = PokemonMoves[entry.name]
		-- `power > 0` skips the 102 moves that have no damage yet. They would
		-- refuse with a message a wild has nobody to send, so a wild picking one
		-- would read as a turn where it simply did nothing.
		if move and move.power > 0 and (ready[entry.name] or 0) <= now then
			local reach = move.behavior ~= "target"
				and math.max(move.range, Pokemon.AREA_RADIUS)
				or move.range
			if distance <= reach then
				options[#options + 1] = entry
			end
		end
	end
	if #options == 0 then
		return false
	end

	-- Uniform among what is ready, rather than best-first. A wild that always
	-- opened with its heaviest move would be a script to memorise; this way the
	-- same species fights differently twice.
	local pick = options[math.random(#options)]
	local move = PokemonMoves[pick.name]

	ready[pick.name] = now + (pick.cooldown or 20)
	wildNextMove[id] = now + Pokemon.WILD_MOVE_INTERVAL

	-- Same two paths a trainer's order takes, and for the same reason: a second
	-- implementation is how the two sides drift apart. A wild always has a
	-- target to centre on -- it is how it got here -- so the no-target case
	-- never arises, but the shape and the per-victim damage do.
	local effectiveness
	if move.behavior ~= "target" then
		local from = creature:getPosition()
		local centre = move.behavior == "self" and from or target:getPosition()
		_, effectiveness = Pokemon.deliverArea(
			attacker, move, centre,
			move.behavior == "self" and creature:getDirection() or directionOfBlast(from, centre),
			target)
	else
		local damage
		damage, effectiveness = Pokemon.damage(attacker, defender, move)
		Pokemon.deliver(creature, target, move, damage)
	end

	-- Tell the trainer on the other side. Without this a wild's move is
	-- indistinguishable from its melee except by the number, and the whole point
	-- of giving wilds a movepool is that you can see what you are fighting.
	local watcher = target:getMaster()
	if watcher and watcher:isPlayer() then
		local note = effectiveness and EFFECTIVENESS_TEXT[tostring(effectiveness)]
		watcher:sendTextMessage(MESSAGE_STATUS, string.format(
			"Wild %s used %s.%s", creature:getName(), pick.name,
			note and (" " .. note .. "!") or ""))
	end

	return true, pick.name
end

--- Order a move by its slot -- the way a trainer actually gives it.
--
-- Separate entry point rather than a second argument to `useMove` so the empty
-- slot gets its own message. "Charizard does not know slot 9" would be nonsense,
-- and "does not know nil" is how a UI bug reaches the player as gibberish.
function Pokemon.useMoveSlot(player, slot)
	local entry = Pokemon.getActive(player)
	if not entry then
		return false, "You have no pokemon at your side."
	end

	local mon = Pokemon.read(entry.item)
	if not mon then
		return false, "That pokemon cannot be read."
	end

	local moveName = Pokemon.moveInSlot(mon, slot)
	if not moveName then
		return false, string.format("%s has no move %d.", mon.species, slot)
	end

	return Pokemon.useMove(player, moveName)
end
