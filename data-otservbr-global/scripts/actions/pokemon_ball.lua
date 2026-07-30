-- Using the ball sends the pokemon out; using it again calls it back.
--
-- The ball **stays in the inventory** while the pokemon is out. What changes
-- is session state, not the item's position.

local ball = Action()

function ball.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local mon = Pokemon.read(item)
	if not mon then
		return false -- empty ball or any item: let Canary handle it
	end

	local entry = Pokemon.getActive(player)

	-- Using the ball of the pokemon already in play means recall.
	if entry and entry.item == item then
		Pokemon.recall(player)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s comes back.", mon.species))
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		return true
	end

	local creature, reason = Pokemon.summon(player, item)
	if not creature then
		player:sendCancelMessage(reason)
		return true
	end

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Go, %s!", mon.species))
	creature:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

-- Every minted id, plus the placeholder the two species without art keep.
--
-- Enumerated one by one because `Action:id(...)` is a **list**, not a range:
-- `luaActionItemId` walks its arguments and `emplace_back`s each
-- (`action_functions.cpp`). The "in range from id: X, to id: Y" in the
-- duplicate warning is only the first and last entry of that vector, which
-- reads like a range and is not one.
for _, entry in pairs(PokemonVisual or {}) do
	ball:id(entry.alive)
	ball:id(entry.fainted)
end
ball:id(Pokemon.PLACEHOLDER_BALL_ID)
ball:register()
