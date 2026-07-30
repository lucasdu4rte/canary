-- Description of an occupied ball.
--
-- Overrides `Item.getDescription` instead of registering another
-- `playerOnLook`. The reason is that the C++ sends no text on look: the one
-- who builds and sends it is `data/scripts/eventcallbacks/player/on_look.lua`,
-- calling `inspectedThing:getDescription(distance)`. Registering a second
-- callback would send a **second** message rather than replace the first.
--
-- That a C++-registered method can be overridden was tested on 2026-07-29.

Pokemon = Pokemon or {}

local originalGetDescription = Item.getDescription

-- The C++ has `Game::getPlayerNameByGUID` with a cache of its own, but it is
-- **not exposed to Lua**. The only route from here is `Game.getOfflinePlayer`,
-- which loads the whole player from the database -- far too expensive to run
-- on every look, all the more so because a synchronous query stalls the entire
-- game loop, not just the player who looked.
--
-- Hence the memo: one database trip per trainer, per boot. A name changed
-- afterwards stays stale until the next restart, and that is cosmetic.
local nameCache = {}

local function trainerName(guid)
	local cached = nameCache[guid]
	if cached then
		return cached
	end
	local player = Game.getOfflinePlayer(guid)
	local name = (player and player:getName()) or ("#" .. tostring(guid))
	nameCache[guid] = name
	return name
end

--- Build the description from the item, always on the spot.
--
-- NOTE: **Does not start with "You see"**: the datapack's `on_look.lua` prefixes
-- that before sending (`return "You see " .. descriptionText`). Including it
-- here produces "You see You see Charizard." -- which is what the first
-- version did.
--
-- HP is deliberately left out: a health figure in a look does not help decide
-- anything, and it buried the line that does.
function Pokemon.describe(mon)
	-- "a pokeball" is fixed while only one ball type exists. When phase 5
	-- brings great and ultra, the type name goes here -- which is why the
	-- sentence names the container before its contents instead of saying "You
	-- see Charizard". The ball is the item; the pokemon is what goes inside.
	local contents = mon.fainted and ("a fainted " .. mon.species) or mon.species
	local sentence = "a pokeball with " .. contents

	if mon.holder then
		-- The current owner is simply whoever carries the item -- in this
		-- model there is no owner column that could disagree.
		sentence = sentence .. string.format(", belonging to %s.", mon.holder:getName())

		-- The original trainer is only worth naming when it is **not** the
		-- current holder: that is when the line tells a story (it changed
		-- hands). Repeating the same name twice is noise.
		if mon.holder:getGuid() ~= mon.ot then
			sentence = sentence .. string.format(" Originally caught by %s.", trainerName(mon.ot))
		end
	else
		-- With no holder -- ground, depot -- there is no owner to point at, so
		-- the only honest name is the original trainer's.
		sentence = sentence .. string.format(", originally caught by %s.", trainerName(mon.ot))
	end

	return sentence
end

function Item.getDescription(self, distance)
	local mon = Pokemon.read(self)
	if not mon then
		-- Delegating is mandatory, not a courtesy: without it **every** item
		-- in the game loses its description.
		return originalGetDescription(self, distance)
	end
	return Pokemon.describe(mon)
end
