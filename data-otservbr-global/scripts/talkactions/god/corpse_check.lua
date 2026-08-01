-- `/corpsecheck` -- what a real kill actually left on the ground.
--
-- The companion to `/throwball`: that one throws, this one only looks. Reading a
-- corpse without consuming it is what lets you check the setup before spending a
-- ball, and it is what answered the two things no headless probe could -- that a
-- corpse from a summoned pokemon's kill carries the species after the rename, and
-- that the owner we write is the one `mayTake` compares against.
--
-- Kept rather than deleted because the alternative is squinting at pixels: a
-- corpse is a few pixels of a tile, and "the capture is broken" looks exactly
-- like "there was no corpse on that tile".

local check = TalkAction("/corpsecheck")

local RADIUS = 5

function check.onSay(player, words, param)
	local origin = player:getPosition()
	local found = 0

	for dx = -RADIUS, RADIUS do
		for dy = -RADIUS, RADIUS do
			local pos = Position(origin.x + dx, origin.y + dy, origin.z)
			local tile = Tile(pos)
			if tile then
				for _, item in ipairs(tile:getItems() or {}) do
					local species = item:getCustomAttribute("pokemon_corpse_species")
					if species then
						found = found + 1
						local ours = item:getCustomAttribute("pokemon_corpse_owner")
						local engine = item:getAttribute("corpseowner")
						local catchable = Pokemon.isCatchable(species)
						local chance = catchable
							and Pokemon.catchChance(species, PokemonBallItems["Poke Ball"], {})
							or 0

						player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
							"corpse %d: %s at %d,%d id=%d",
							found, species, pos.x, pos.y, item:getId()))
						player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
							"  ours=%s engine=%s me=%d match=%s",
							tostring(ours), tostring(engine), player:getId(),
							tostring(ours == player:getId())))
						player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
							"  catchable=%s poke chance=%.4f",
							tostring(catchable), chance))

						logger.info(string.format(
							"[corpse-check] %s at %d,%d id=%d ours=%s engine=%s me=%d catchable=%s chance=%.4f",
							species, pos.x, pos.y, item:getId(), tostring(ours),
							tostring(engine), player:getId(), tostring(catchable), chance))
					end
				end
			end
		end
	end

	if found == 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "no pokemon corpse within 5 tiles")
		logger.info("[corpse-check] none found")
	end
	return true
end

check:separator(" ")
check:groupType("god")
check:register()
