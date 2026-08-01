-- Throwing an empty ball at a pokemon corpse.
--
-- The rules live in `lib/pokemon/capture.lua`. This file is only the input
-- channel: it says which items are throwable, checks that the click landed on
-- an item at all, and hands over. Phase 6's UI becomes a second channel into the
-- same function.

local throwBall = Action()

function throwBall.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	-- Only the emptiness of this lookup is used. `false` rather than `true` so an
	-- id registered here but missing from the table falls through to the engine's
	-- default use handling instead of silently doing nothing.
	if not Pokemon.BALLS[item:getId()] then
		return false
	end

	-- Everything past here needs an item to read attributes off. A creature or a
	-- tile reaches this same handler, and `isItem` is how the datapack's other
	-- "use with" actions tell them apart (`falcon_shield.lua:4`).
	if not target or type(target) ~= "userdata" or not target:isItem() then
		player:sendCancelMessage("You can only throw this at a defeated pokemon.")
		return true
	end

	Pokemon.attemptCapture(player, target, item)
	return true
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
-- (game.cpp:4594-4614) sees TOOFARAWAY and auto-walks the character onto the body
-- before using it. That walk is where two players actually contend for one corpse
-- -- reopening on the client side the race that removing-before-rolling closes on
-- the server side.
--
-- With it the path becomes `Actions::canUseFar`: range `areInRange<7, 5>` (the
-- visible screen), `checkFloor` on, and `checkLineOfSight` on -- a wall answers
-- "You cannot throw there." Both of those defaults are left alone; `blockWalls`
-- would turn line of sight off and is deliberately not called.
throwBall:allowFarUse(true)
throwBall:register()
