-- !pokestop, and t1..t4  --  the positioning half of a fight
--
-- Both are the source game's, names included. They matter more here than they
-- look: a beam runs along the line its caster faces and a burst is centred on
-- where it stands, so these two commands are what decide where 191 of the 360
-- moves land. Without them a trainer can choose the move and nothing else.
--
-- Registered `groupType("normal")`: these are how the game is played, not
-- debugging aids that happen to be useful.

local pokestop = TalkAction("!pokestop")

function pokestop.onSay(player, words, param)
	local entry = Pokemon.getActive(player)
	if not entry or not entry.creature or entry.creature:isRemoved() then
		player:sendCancelMessage("You have no pokemon at your side.")
		return true
	end

	local mon = Pokemon.read(entry.item)
	local name = mon and mon.species or entry.creature:getName()

	-- Pressing it again releases, rather than refusing or silently restarting
	-- the two minutes. A parked pokemon is the state you can see on screen, so
	-- one command toggling it is what the screen already implies.
	if Pokemon.stop(entry.creature) then
		player:sendTextMessage(MESSAGE_STATUS, string.format(
			"%s will hold this spot for %d seconds.", name, Pokemon.STOP_SECONDS))
		entry.creature:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	else
		player:sendTextMessage(MESSAGE_STATUS, string.format("%s is free to move again.", name))
		entry.creature:getPosition():sendMagicEffect(CONST_ME_POFF)
	end
	return true
end

pokestop:separator(" ")
pokestop:groupType("normal")
pokestop:register()

-- t1 north, t2 east, t3 south, t4 west.
--
-- Registered bare AND with a bang. The source game's players type `t1`, and a
-- command they have to spell differently here is a command they will get wrong
-- under pressure; `!t1` is there because every other pokemon command in this
-- datapack carries the bang and reaching for it is the obvious mistake.
for slot = 1, 4 do
	for _, word in ipairs({ "t" .. slot, "!t" .. slot }) do
		local turn = TalkAction(word)

		function turn.onSay(player, words, param)
			local entry = Pokemon.getActive(player)
			if not entry or not entry.creature or entry.creature:isRemoved() then
				player:sendCancelMessage("You have no pokemon at your side.")
				return true
			end

			Pokemon.face(entry.creature, slot)

			-- 🔴 Always confirms, and the first version did not: it stayed silent
			-- when the pokemon was parked, on the reasoning that the turn had
			-- stuck and needed no explanation. That is backwards. The placeholder
			-- outfit makes facing nearly unreadable on screen, so silence left
			-- the ONE case that works looking identical to a command that did
			-- nothing -- and telling those two apart is the whole discipline of
			-- this phase.
			--
			-- The caveat rides along only when it applies: a pokemon that is free
			-- to move re-faces its target the next time it acts, so the turn is a
			-- single instant unless it is parked.
			local caveat = Pokemon.isStopped(entry.creature)
				and ""
				or " It will turn back when it acts - !pokestop holds it."
			player:sendTextMessage(MESSAGE_STATUS, string.format(
				"%s faces %s.%s", entry.creature:getName(), Pokemon.FACING_NAME[slot], caveat))
			return true
		end

		turn:separator(" ")
		turn:groupType("normal")
		turn:register()
	end
end
