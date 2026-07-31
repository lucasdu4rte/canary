-- /create-wild <species>
--
-- Puts a wild pokemon next to you. Phase 7 owns real spawns; this is what
-- gives phase 4 something to fight in the meantime.
--
-- Not `/m` from the core datapack: our MonsterTypes register under the variant
-- key "pokemon|<Name>", and asking a GM to type the namespace is asking them to
-- learn an implementation detail. This resolves the species the same way
-- /create-pokemon does, so the two commands take the same argument.

local createWild = TalkAction("/create-wild")

function createWild.onSay(player, words, param)
	logCommand(player, words, param)

	local input = param:trim()
	if input == "" then
		player:sendCancelMessage("Usage: /create-wild <species>")
		return true
	end

	local key = nil
	local wanted = input:lower()
	for name in pairs(PokemonSpecies) do
		if name:lower() == wanted then
			key = name
			break
		end
	end

	if not key then
		player:sendCancelMessage(string.format("There is no pokemon named '%s'.", input))
		return true
	end

	-- forced = true: the test areas are not spawn zones, and refusing there
	-- would make the command look broken rather than restricted.
	local position = player:getPosition()
	local monster = Game.createMonster(Pokemon.monsterName(key), position, false, true)
	if not monster then
		player:sendCancelMessage(string.format("Could not place a wild %s here.", key))
		return true
	end

	-- Straight away rather than waiting for the first think: the GM who typed
	-- this is about to attack it, and a wild carrying the MonsterType's base hp
	-- dies in one hit and teaches the wrong thing about the damage formula.
	Pokemon.applyWildStats(monster)

	player:sendTextMessage(MESSAGE_ADMINISTRATOR, string.format(
		"Wild %s at level %d - %d HP.",
		key, Pokemon.wildLevel(position), monster:getMaxHealth()))
	monster:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

createWild:separator(" ")
createWild:groupType("god")
createWild:register()
