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

-- Pokemon type -> Tibia combat type and hit effect.
--
-- Cosmetic only. The generated MonsterTypes carry `elements = {}`,
-- `immunities = {}` and zero armor/defense/mitigation, so the engine applies no
-- resistance of its own and `Pokemon.multiplier` remains the only multiplier in
-- play. Were that to change, this table would start double-counting.
--
-- Eighteen types map onto the eight damage types Tibia has, so the collisions
-- are unavoidable and only affect the colour of the splash.
local COMBAT_BY_TYPE = {
	normal = { COMBAT_PHYSICALDAMAGE, CONST_ME_HITAREA },
	fighting = { COMBAT_PHYSICALDAMAGE, CONST_ME_BLACKSMOKE },
	flying = { COMBAT_PHYSICALDAMAGE, CONST_ME_STONES },
	poison = { COMBAT_EARTHDAMAGE, CONST_ME_POISONAREA },
	ground = { COMBAT_EARTHDAMAGE, CONST_ME_CARNIPHILA },
	rock = { COMBAT_PHYSICALDAMAGE, CONST_ME_STONES },
	bug = { COMBAT_EARTHDAMAGE, CONST_ME_GREEN_RINGS },
	ghost = { COMBAT_DEATHDAMAGE, CONST_ME_MORTAREA },
	steel = { COMBAT_PHYSICALDAMAGE, CONST_ME_BLOCKHIT },
	fire = { COMBAT_FIREDAMAGE, CONST_ME_FIREAREA },
	water = { COMBAT_ICEDAMAGE, CONST_ME_WATERSPLASH },
	grass = { COMBAT_EARTHDAMAGE, CONST_ME_PLANTATTACK },
	electric = { COMBAT_ENERGYDAMAGE, CONST_ME_ENERGYAREA },
	psychic = { COMBAT_ENERGYDAMAGE, CONST_ME_MAGIC_RED },
	ice = { COMBAT_ICEDAMAGE, CONST_ME_ICEATTACK },
	dragon = { COMBAT_ENERGYDAMAGE, CONST_ME_DRAGONHEAD },
	dark = { COMBAT_DEATHDAMAGE, CONST_ME_MORTAREA },
	fairy = { COMBAT_HOLYDAMAGE, CONST_ME_HOLYDAMAGE },
}

local FALLBACK_COMBAT = { COMBAT_PHYSICALDAMAGE, CONST_ME_HITAREA }

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
		or Pokemon.wildLevel(creature:getPosition())

	return {
		creature = creature,
		speciesData = species,
		stats = Pokemon.calcStats(species, level),
		effectiveLevel = level,
	}
end

local function combatFor(move, damage)
	local flavour = COMBAT_BY_TYPE[move.type] or FALLBACK_COMBAT

	local combat = Combat()
	combat:setParameter(COMBAT_PARAM_TYPE, flavour[1])
	combat:setParameter(COMBAT_PARAM_EFFECT, flavour[2])
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
	combat:setFormula(COMBAT_FORMULA_DAMAGE, -damage, 0, -damage, 0)

	-- Shape comes from the table, never from the move's name.
	if move.behavior == "aoe" then
		combat:setArea(createCombatArea(AREA_CIRCLE3X3))
	end

	return combat
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
--   out of range              -> refused, with the reach in the message
--   on cooldown               -> refused, with the time left
--   then and only then        -> consume the cooldown and deal the damage
--
-- The `power == 0` refusal covers 102 of the 360 moves. Without it, better than
-- one button in four does nothing at all and is indistinguishable from a broken
-- move. There is no accuracy roll in this phase, so every use that gets past
-- these checks lands -- which is what makes consuming the cooldown here fair.
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

	local target = player:getTarget()
	if not target or target:isRemoved() then
		return false, "Choose a target first."
	end

	local defender = Pokemon.combatantOf(target)
	if not defender then
		return false, "Pokemon moves only work on other pokemon."
	end

	local distance = entry.creature:getPosition():getDistance(target:getPosition())
	if distance > move.range then
		return false, string.format("%s only reaches %d square%s away.",
			known.name, move.range, move.range == 1 and "" or "s")
	end

	local left = Pokemon.moveCooldownLeft(entry.item, known.name)
	if left > 0 then
		return false, string.format("%s is not ready: %d second%s left.",
			known.name, left, left == 1 and "" or "s")
	end

	Pokemon.markMoveUsed(entry.item, known.name, known.cooldown)

	local damage, effectiveness = Pokemon.damage(attacker, defender, move)
	combatFor(move, damage):execute(entry.creature, Variant(target:getId()))

	local note = EFFECTIVENESS_TEXT[tostring(effectiveness)]
	player:sendTextMessage(MESSAGE_STATUS, string.format(
		"%s used %s.%s", mon.species, known.name, note and (" " .. note .. "!") or ""))

	return true
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
