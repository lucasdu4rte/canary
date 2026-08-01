-- `/throwball <ball> [species]` -- throw at the nearest corpse, without aiming.
--
-- A testing channel, not a game mechanic. It exists because aiming a "use with"
-- click at a corpse is the one part of this phase that cannot be driven reliably
-- from a script: the corpse is a few pixels of a tile, a miss walks the character
-- instead, and the difference between "the capture is broken" and "the click
-- landed on grass" is invisible from the outside.
--
-- ⚠️ It calls `Pokemon.attemptCapture`, the SAME function the ball's Action calls,
-- and deliberately reimplements none of it. A test command with its own copy of
-- the rules tests the copy -- it would pass while the real path was broken, which
-- is worse than having no command at all. Everything here is target SELECTION.
--
-- Examples:
--     /throwball poke              -- nearest corpse of any species
--     /throwball ultra Pidgey      -- nearest Pidgey corpse
--     /throwball great             -- nearest, with a great ball

local test = TalkAction("/throwball")

-- How far to look. Matches the far-use box the Action itself allows
-- (`areInRange<7, 5>`), so the command cannot reach a corpse a real throw could
-- not -- otherwise it would "prove" captures at ranges the game refuses.
local RANGE_X, RANGE_Y = 7, 5

local BALL_ALIASES = {
	poke = "Poke Ball",
	pokeball = "Poke Ball",
	great = "Great Ball",
	greatball = "Great Ball",
	super = "Super Ball",
	superball = "Super Ball",
	ultra = "Ultra Ball",
	ultraball = "Ultra Ball",
}

--- Every pokemon corpse in range, nearest first.
local function corpsesNear(player, wantedSpecies)
	local origin = player:getPosition()
	local found = {}

	for dx = -RANGE_X, RANGE_X do
		for dy = -RANGE_Y, RANGE_Y do
			local tile = Tile(Position(origin.x + dx, origin.y + dy, origin.z))
			if tile then
				for _, item in ipairs(tile:getItems() or {}) do
					local species = item:getCustomAttribute("pokemon_corpse_species")
					if species and (not wantedSpecies or species:lower() == wantedSpecies:lower()) then
						found[#found + 1] = {
							item = item,
							species = species,
							-- Chebyshev: the same shape the range box uses, so
							-- "nearest" means nearest in the metric that decides
							-- whether the throw is legal at all.
							distance = math.max(math.abs(dx), math.abs(dy)),
						}
					end
				end
			end
		end
	end

	table.sort(found, function(a, b) return a.distance < b.distance end)
	return found
end

function test.onSay(player, words, param)
	local ballWord, speciesWord = param:match("^%s*(%S+)%s*(.-)%s*$")
	if not ballWord then
		player:sendCancelMessage("Usage: /throwball <poke|great|super|ultra> [species]")
		return true
	end
	if speciesWord == "" then
		speciesWord = nil
	end

	local ballName = BALL_ALIASES[ballWord:lower()]
	if not ballName then
		player:sendCancelMessage("Unknown ball '" .. ballWord .. "'. Use poke, great, super or ultra.")
		return true
	end

	local ballItemId = PokemonBallItems[ballName]
	local ballItem = player:getItemById(ballItemId, false)
	if not ballItem then
		player:sendCancelMessage(string.format(
			"You have no %s. Get some with /i %d, 10", ballName:lower(), ballItemId))
		return true
	end

	local corpses = corpsesNear(player, speciesWord)
	if #corpses == 0 then
		player:sendCancelMessage(speciesWord
			and string.format("No %s corpse within reach.", speciesWord)
			or "No pokemon corpse within reach.")
		return true
	end

	local pick = corpses[1]
	local outcome = Pokemon.attemptCapture(player, pick.item, ballItem)

	-- The outcome goes to the server log as well as the screen: an agent driving
	-- this reads the log, and `sendCancelMessage` never reaches it.
	logger.info(string.format(
		"[throwball] %s threw a %s at %s (%d tiles, %d candidates) -> %s",
		player:getName(), ballName, pick.species, pick.distance, #corpses, outcome))
	return true
end

test:separator(" ")
test:groupType("god")
test:register()
