-- `/pokecheck` -- what the trainer is actually carrying, read off the items.
--
-- The third of the testing family, beside `/corpsecheck` and `/throwball`. Those
-- two are about the corpse; this one is about what the capture produced.
--
-- It exists for one question the others cannot answer: does `pokemon_ball`
-- survive a logout? Every proof of that field so far has been in memory -- the
-- creation log line, a probe reading it back in the same boot -- and the phase 4
-- cooldown bug was exactly "survived in memory, wiped on the path nobody ran".
-- Reading it after a relog is the only thing that settles it, and reading it
-- needs a command.
--
-- Also prints the carried count, which is what decides whether the seventh
-- capture goes to the bag or the depot.

local check = TalkAction("/pokecheck")

function check.onSay(player, words, param)
	local carried = Pokemon.carriedBalls(player)

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"carrying %d pokemon (limit for the depot split is 6)", #carried))

	for i, item in ipairs(carried) do
		local mon = Pokemon.read(item)
		if mon then
			local ballName = Pokemon.BALLS[mon.ball] and Pokemon.BALLS[mon.ball].name or "none"
			local line = string.format(
				"%d. %s uid=%.0f ball=%d (%s) hp=%.2f%s",
				i, mon.species, mon.uid, mon.ball, ballName, mon.hpRatio,
				mon.fainted and " FAINTED" or "")
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, line)
			logger.info("[pokecheck] " .. player:getName() .. " " .. line)
		end
	end

	if #carried == 0 then
		logger.info("[pokecheck] " .. player:getName() .. " carries nothing")
	end
	return true
end

check:separator(" ")
check:groupType("god")
check:register()
