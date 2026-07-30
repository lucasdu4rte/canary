-- Dropping a pokemon on the ground asks first.
--
-- The ground is the one place a pokemon is lost for good: anyone standing
-- there can take it, and the server clean removes what is left lying around.
-- That is the designed behaviour and there is deliberately no clean hook --
-- which is exactly why getting there has to be a decision and not a slip of
-- the mouse.
--
-- House floor is exempt. It is storage, the clean does not touch it, and
-- asking there would fire on every furniture rearrangement.

local PROMPT_TITLE = "Drop pokemon"

-- Upper bound on how long a prompt nobody answered can block the next one.
-- The window itself has no deadline on the client, so a player who logs out
-- with it open would otherwise never be able to drop anything again.
local PROMPT_TIMEOUT = 60

-- Deliberately tighter than the engine's own reach check (`Game::playerMoveItem`,
-- game.cpp:2207-2216: throw range 15 for a pickupable item, bounded by the 8x6
-- client viewport). Between question and answer the player can walk away, and
-- re-running the original check would let a late "Yes" land the ball where the
-- player no longer is. Refusing is cheap -- they drag again.
local MAX_CONFIRM_RANGE = 6

-- One prompt per player. Dragging repeatedly would otherwise stack windows,
-- each carrying its own captured destination, and answering them out of order
-- puts the ball somewhere the player has long stopped thinking about.
local prompting = {}

--- The ground rules the datapack applies in `Player:onMoveItem`
--- (`data/events/scripts/player.lua:246-290`).
--
-- They have to be repeated because a confirmed drop goes through `item:moveTo`,
-- which lands in `Game::internalMoveItem` -- the C++ move, below the Lua event
-- that holds these rules. Without them "Yes" becomes a way to put a ball on a
-- teleport, or on a tile already stuffed with 20 items, which a plain drag
-- cannot do.
local function groundRefuses(tile)
	if tile:getItemCount() > 20 then
		return true
	end

	if tile:getItemByType(ITEM_TYPE_TELEPORT) then
		return true
	end

	local topDownItem = tile:getTopDownItem()
	if topDownItem then
		local id = topDownItem:getId()
		if id == BATHTUB_EMPTY or id == BATHTUB_FILLED then
			return true
		end
		if ItemType(id):isPodium() then
			return true
		end
	end

	return false
end

--- Carry out the drop the player just agreed to.
--
-- Everything is revalidated. Between the question and the answer the player
-- can have walked off, stowed the ball elsewhere, or traded it away; without
-- rechecking, the modal is a delayed teleport for an item that may not even be
-- theirs any more.
local function dropConfirmed(player, item, uid, toPosition)
	local function refuse(message)
		player:sendTextMessage(MESSAGE_FAILURE, message)
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
	end

	local mon = Pokemon.read(item)
	-- The uid comparison is what makes this an identity check and not just a
	-- shape check: it fails if the userdata now points at a different pokemon.
	if not mon or mon.uid ~= uid then
		return refuse("That pokemon is no longer there.")
	end

	-- No holder also covers a removed item -- `Item::isRemoved` is exactly
	-- "the parent chain is gone" (item.cpp:873), and the chain is what
	-- `Pokemon.read` walks to find the holder.
	if not mon.holder or mon.holder:getId() ~= player:getId() then
		return refuse("That pokemon is not yours to drop any more.")
	end

	if player:getPosition():getDistance(toPosition) > MAX_CONFIRM_RANGE then
		return refuse("You are too far from that spot now.")
	end

	local tile = Tile(toPosition)
	if not tile or groundRefuses(tile) then
		return refuse("You cannot drop it there.")
	end

	-- Flags 0 on purpose. `moveTo` defaults to
	-- FLAG_NOLIMIT|FLAG_IGNOREBLOCKITEM|FLAG_IGNOREBLOCKCREATURE|FLAG_IGNORENOTMOVABLE
	-- (item_functions.cpp:733), which is a god move: through walls, past tile
	-- limits, onto anything. Zero asks the same question the engine asks for an
	-- ordinary drag.
	if not item:moveTo(tile, 0) then
		return refuse("You cannot drop it there.")
	end

	toPosition:sendMagicEffect(CONST_ME_POFF)

	-- Same reason as the creation log: when a pokemon goes missing, this is the
	-- only record that says it was the owner who let it go.
	logger.info(string.format(
		"[pokemon] uid=%.0f species=%s dropped at %d,%d,%d by %s(%d)",
		mon.uid, mon.species, toPosition.x, toPosition.y, toPosition.z,
		player:getName(), player:getGuid()))
end

local callback = EventCallback("PlayerOnMoveItemPokemonDropConfirm")

function callback.playerOnMoveItem(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	-- Inventory and container windows both address themselves as 0xFFFF
	-- (game.cpp:2227); a map position is anything else.
	if toPosition.x == CONTAINER_POSITION then
		return true
	end

	local mon = Pokemon.read(item)
	if not mon then
		return true
	end

	-- The question is about the ball leaving the player's hands. A ball already
	-- lying on the ground is past that point, so pushing it from one tile to
	-- the next asks nothing.
	if not mon.holder or mon.holder:getId() ~= player:getId() then
		return true
	end

	local tile = Tile(toPosition)
	if not tile then
		-- Let the engine refuse it with its own message rather than invent one.
		return true
	end

	if tile:getHouse() then
		return true
	end

	local playerId = player:getId()
	local openedAt = prompting[playerId]
	if openedAt and os.time() - openedAt < PROMPT_TIMEOUT then
		player:sendCancelMessage("Answer the question about the pokemon first.")
		return false
	end
	prompting[playerId] = os.time()

	local window = ModalWindow({
		title = PROMPT_TITLE,
		message = string.format(
			"Drop %s on the ground?\n\nAnyone can pick it up, and the server clean removes what is left lying around.",
			mon.species),
	})

	window:addButton("Yes")
	window:addButton("No")

	-- Both Enter and Escape answer "No" -- button id 2, the ids being the ones
	-- `addButton` handed out in order. The only way through is a click on
	-- "Yes": losing a pokemon to a stray keypress is not a trade worth making.
	window:setDefaultEnterButton(2)
	window:setDefaultEscapeButton(2)

	-- One callback for the whole window instead of one per button, so the
	-- branch is on the name that came back. A button id the helper cannot
	-- resolve arrives as an empty table, and an empty table is not "Yes" --
	-- which is the failure mode worth being careful about here.
	window:setDefaultCallback(function(answeringPlayer, button)
		prompting[playerId] = nil
		if button.name ~= "Yes" then
			return true
		end
		dropConfirmed(answeringPlayer, item, mon.uid, toPosition)
		return true
	end)

	window:sendToPlayer(player)

	-- Aborts the move: `checkCallback` stops at the first falsy return
	-- (events_callbacks.hpp) and `Game::playerMoveItem` returns without a
	-- message of its own, which is what leaves the modal as the only thing the
	-- player sees.
	return false
end

callback:register()
