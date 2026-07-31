-- /heal-pokemon [player]  --  every ball in the bag back to full, and revived
--
-- A testing tool, and it earned its place: a fainted pokemon cannot be sent out
-- again, so one bad fight ends a session until something heals it. Phase 8 owns
-- the pokemon center that will do this for a player; until then a GM is the
-- only route back, and doing it by hand means editing custom attributes on
-- every ball one at a time.
--
-- Heals the one in play too. `revive` writes the ratio the ball will restore
-- from, which is what the pokemon comes back with -- it does not touch the
-- creature already standing on the map, and leaving it wounded while its own
-- ball reads full is exactly the kind of split state that reads as a bug later.

local healPokemon = TalkAction("/heal-pokemon")

function healPokemon.onSay(player, words, param)
	logCommand(player, words, param)

	local input = param:trim()
	local target = player
	if input ~= "" then
		target = Player(input)
		if not target then
			player:sendCancelMessage(string.format("Player %s is not online.", input))
			return true
		end
	end

	-- ⚠️ Gathered before anything is written. `revive` goes through syncVisual,
	-- which calls `transform`, and transform's destructive path replaces the
	-- item -- so healing during the walk would be reshaping the containers being
	-- walked. `Pokemon.carriedBalls` returns a finished list for this reason.
	local balls = Pokemon.carriedBalls(target)
	local healed, revived = 0, 0
	for _, item in ipairs(balls) do
		local mon = Pokemon.read(item)
		if mon then
			if mon.fainted then
				revived = revived + 1
			end
			Pokemon.revive(item)
			healed = healed + 1
		end
	end

	-- The one on the map, if any: the ball now says full and the creature should
	-- agree with it.
	local entry = Pokemon.getActive(target)
	if entry and entry.creature and not entry.creature:isRemoved() then
		entry.creature:addHealth(entry.creature:getMaxHealth())
		entry.creature:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	end

	if healed == 0 then
		player:sendCancelMessage(string.format("%s is not carrying any pokemon.",
			target == player and "You are" or target:getName()))
		return true
	end

	player:sendTextMessage(MESSAGE_ADMINISTRATOR, string.format(
		"%d pokemon healed%s%s.",
		healed,
		revived > 0 and string.format(" (%d revived)", revived) or "",
		target == player and "" or (" for " .. target:getName())))

	if target ~= player then
		target:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Your pokemon have been healed.")
	end
	target:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	return true
end

healPokemon:separator(" ")
healPokemon:groupType("god")
healPokemon:register()
