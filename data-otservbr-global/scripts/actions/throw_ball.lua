-- Throwing an empty ball at a pokemon corpse.
--
-- The corpse is the contested resource and the ORDER below is the whole
-- design: remove it before rolling. Rolling first would let two players roll
-- on the same body, and the loser of the race would still get a pokemon.
--
-- That ordering is also what saves us the flag the legacy base needed. The
-- Roxy rolls inside an addEvent after the ball's flight animation, so the
-- corpse sits on the ground during the flight and it writes `catching = 1` on
-- it to cover the window. Here the flight effect is cosmetic and comes AFTER
-- the decision, so there is no window to cover.

local SUCCESS_EFFECT = CONST_ME_MAGIC_GREEN
local FAILURE_EFFECT = CONST_ME_POFF
local THROW_EFFECT = CONST_ANI_SMALLSTONE

-- Six is how many a trainer carries. The seventh is the one that gets routed
-- to the depot -- counted BEFORE the capture, so the sixth still lands in the
-- bag. Phase 6 draws this as the Pokemon Team; here it is just a count.
local CARRY_LIMIT = 6

-- WHY a pokemon ended up in the depot, carried through the branch instead of
-- recomputed at the bottom. Two genuinely different causes reach the same
-- place, and the player is owed the true one: a trainer holding three pokemon
-- with a stuffed backpack who is told "you already have 6 pokemons with you"
-- reads it as the carry limit being broken, and reports a bug that is not there.
local DEPOT_CARRY_LIMIT = "carry-limit"
local DEPOT_BAG_FULL = "bag-full"

local throwBall = Action()

-- Forward-declared, and both things about that line matter.
--
-- LOCAL rather than fields on `throwBall`: an Action is userdata, and its
-- `__newindex` (`data/libs/functions/revscriptsys.lua:88`) special-cases
-- `onUse` and falls through to `rawset(self, key, value)` for everything else
-- -- which throws on userdata. Measured 2026-07-31: `function
-- throwBall.mayTake(...)` aborted the file at that line, so `register()` at
-- the bottom never ran, the action never registered, and the boot log showed
-- one error line while the server came up perfectly healthy.
--
-- FORWARD-declared because `onUse` below closes over these names lexically.
-- Defined after it, they would compile as global lookups and be nil at call
-- time -- the same silent hole one layer down.
local mayTake, succeed

function throwBall.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local ball = Pokemon.BALLS[item:getId()]
	if not ball then
		return false
	end

	-- 1. Is it a pokemon corpse, and of what?
	if not target or type(target) ~= "userdata" or not target:isItem() then
		player:sendCancelMessage("You can only throw this at a defeated pokemon.")
		return true
	end

	local species = target:getCustomAttribute("pokemon_corpse_species")
	if not species or not PokemonSpecies[species] then
		player:sendCancelMessage("You can only throw this at a defeated pokemon.")
		return true
	end

	-- 2. Impossible refuses before anything is consumed.
	if not Pokemon.isCatchable(species) then
		player:sendCancelMessage("You cannot catch this pokemon.")
		return true
	end

	-- 3. Owner, or someone in their party. Without this, camping other
	-- people's corpses is free and the whole fight becomes work someone else
	-- harvests. An ownerless corpse (the attribute is dropped when the item
	-- decays a stage) is fair game rather than an error.
	local owner = target:getAttribute("corpseowner")
	if owner and owner ~= 0 and not mayTake(player, owner) then
		player:sendCancelMessage("You did not defeat this pokemon.")
		return true
	end

	-- 4. Remove the corpse. This is what serialises the race: whoever gets the
	-- successful removal is the only one who rolls. A failure here means
	-- somebody was ahead of us, and the ball is NOT spent.
	if not target:remove() then
		player:sendCancelMessage("There is nothing left here.")
		return true
	end

	-- 5. Only now is the ball consumed and the dice thrown.
	local ballItemId = item:getId()
	item:remove(1)
	player:getPosition():sendDistanceEffect(toPosition, THROW_EFFECT)

	local chance = Pokemon.catchChance(species, ballItemId, {})
	if math.random() >= chance then
		Pokemon.recordThrow(player, species, ballItemId)
		toPosition:sendMagicEffect(FAILURE_EFFECT)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("The %s broke free!", species))
		return true
	end

	succeed(player, species, ballItemId, toPosition)
	return true
end

--- The thrower is the corpse owner, or in their party.
--
-- `corpseowner` holds the runtime creature id (`monster.cpp:3309`), so this
-- compares against `getId()`. Comparing against `getGuid()` looks right and
-- refuses everyone.
function mayTake(player, ownerId)
	if player:getId() == ownerId then
		return true
	end

	local party = player:getParty()
	if not party then
		return false
	end
	for _, member in ipairs(party:getMembers() or {}) do
		if member:getId() == ownerId then
			return true
		end
	end
	-- The leader is not in getMembers() on every build; check separately
	-- rather than trust it.
	local leader = party:getLeader()
	return leader ~= nil and leader:getId() == ownerId
end

--- Catch: make the instance, place it, say what it cost.
--
-- The capture NORMALISES the specimen, and that is a design decision rather
-- than an omission: nothing about the wild pokemon it came from -- its region,
-- its wild level, the HP it had -- enters the item. It is born standard, with
-- stats deriving from species plus the owner's level like every other. Carry
-- any of it across and the game grows region arbitrage: players farming the
-- hard zone for a "better" specimen of the same species.
--- The player's depot chest, or nil when the town cannot be resolved.
--
-- `getTown()` is the one statement on this path that can strand the whole
-- transaction. It runs AFTER the corpse and the ball are already gone, so a nil
-- town raises a Lua error right there and the player loses both with no message
-- at all -- the worst outcome the function has available. Returning nil instead
-- lets the caller take the same loud path a place-failure already takes.
local function depotChestFor(player)
	local town = player:getTown()
	if not town then
		return nil
	end
	return player:getDepotChest(town:getId(), true)
end

--- The catch happened and the pokemon could not be placed anywhere.
--
-- `recordThrow` runs here for the same reason it runs on a break-free: the ball
-- was consumed either way. Without it this is the one branch that spends a ball
-- and tallies it nowhere, in the phase whose whole point is keeping that count.
local function stranded(player, species, ballItemId, reason)
	Pokemon.recordThrow(player, species, ballItemId)
	logger.error(string.format(
		"[throw-ball] caught %s for %s but could not place it: %s",
		species, player:getName(), tostring(reason)))
	player:sendCancelMessage("You caught it, but there was nowhere to put it. Contact a gamemaster.")
end

function succeed(player, species, ballItemId, position)
	-- Counted BEFORE creating, so the seventh is the one that diverts.
	local carried = #Pokemon.carriedBalls(player)
	local depotReason = carried >= CARRY_LIMIT and DEPOT_CARRY_LIMIT or nil

	local destination = nil
	if depotReason then
		destination = depotChestFor(player)
		if not destination then
			return stranded(player, species, ballItemId, "no town, so no depot to divert to")
		end
	end

	local created, reason = Pokemon.create(player, species, {
		destination = destination,
		ballItemId = ballItemId,
	})

	-- A full bag is a real case and losing the pokemon to it would be losing
	-- property to a limit the player could not see when they threw. Depot is
	-- the valve, for a full bag just as much as for the sixth pokemon.
	if not created and not depotReason then
		local chest = depotChestFor(player)
		if not chest then
			return stranded(player, species, ballItemId, "no town, so no depot to divert to")
		end
		depotReason = DEPOT_BAG_FULL
		created, reason = Pokemon.create(player, species, {
			destination = chest,
			ballItemId = ballItemId,
		})
	end

	if not created then
		return stranded(player, species, ballItemId, reason)
	end

	position:sendMagicEffect(SUCCESS_EFFECT)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("You have caught %s!", species))

	local spent = Pokemon.spentOn(player, species)
	spent[ballItemId] = (spent[ballItemId] or 0) + 1
	-- Unguarded: `spent` always carries at least the ball that just won, so
	-- `describeSpent` cannot return nil here. The `if sentence then` that used to
	-- wrap this could not be false.
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"You have spent %s to catch it.", Pokemon.describeSpent(spent)))
	Pokemon.clearSpent(player, species)

	if depotReason == DEPOT_CARRY_LIMIT then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
			"Your pokemon has been sent to your depot since you already have %d pokemons with you.", CARRY_LIMIT))
	elseif depotReason == DEPOT_BAG_FULL then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
			"Your pokemon has been sent to your depot since your backpack is full.")
	end
end

-- Hard failure rather than `PokemonBallItems or {}`. An empty table would
-- register no ids at all, and the only trace would be one `missing id` warning
-- in a long boot log plus every ball answering "cannot use this object" in the
-- game. A ball library that did not load is a broken install, not a case to
-- degrade quietly through.
assert(PokemonBallItems,
	"throw_ball: PokemonBallItems is missing -- lib/pokemon/ball_ids.lua did not load")

for _, itemId in pairs(PokemonBallItems) do
	throwBall:id(itemId)
end

-- Far use, and this is a rule change rather than decoration.
--
-- Without it `Action::canExecuteAction` (actions.cpp:536) falls through to
-- `Actions::canUse`, which demands `areInRange<1, 1>`. So clicking a ball on a
-- corpse across the room throws nothing: `Game::playerUseItemEx`
-- (game.cpp:4594-4614) sees TOOFARAWAY and auto-walks the character onto the
-- body before using it. That walk is where two players actually contend for one
-- corpse -- reopening on the client side the race that removing-before-rolling
-- closes on the server side. It also made the flight effect a lie, since it
-- would only ever travel a single tile.
--
-- What this turns on, all from `Actions::canUseFar` (actions.cpp:201-221):
--   * range becomes `areInRange<7, 5>` -- 7 tiles on x, 5 on y, the visible
--     screen. Beyond that it is still TOOFARAWAY and still auto-walks, but only
--     until the corpse is on screen, not until the player is standing on it.
--   * `checkFloor` stays true, so a corpse one floor down answers "first go
--     downstairs" instead of being caught through the ceiling.
--   * `checkLineOfSight` stays true, so a wall between thrower and corpse
--     answers "You cannot throw there." It is settable from Lua -- the method is
--     named `blockWalls`, not `checkLineOfSight` -- and is deliberately not
--     called: a throw that needs sight of its target is exactly right here.
throwBall:allowFarUse(true)
throwBall:register()
