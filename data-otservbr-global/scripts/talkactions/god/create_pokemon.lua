-- /create-pokemon <species>
--
-- Capture only arrives in phase 5. Without this, nothing in this phase calls
-- `Pokemon.create` and the G3 gate has no subject.
--
-- Generic by design: the species is an argument, validated against the
-- catalogue. One command serves all 154 -- no script per species, no parallel
-- list to keep in sync.

local createPokemon = TalkAction("/create-pokemon")

function createPokemon.onSay(player, words, param)
	logCommand(player, words, param)

	local input = param:trim()
	if input == "" then
		player:sendCancelMessage("Usage: /create-pokemon <species>")
		return true
	end

	-- Accepts "bulbasaur" and "BULBASAUR" by resolving to the catalogue key,
	-- which is capitalised. Typing 154 species names with exact casing is not
	-- a skill test worth running.
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

	local item, reason = Pokemon.create(player, key)
	if not item then
		player:sendCancelMessage(string.format("Could not create %s: %s", key, reason or "unknown"))
		return true
	end

	local mon = Pokemon.read(item)
	player:sendTextMessage(MESSAGE_ADMINISTRATOR, string.format(
		"Created %s (uid %.0f) - HP %d/%d at your level %d.",
		mon.species, mon.uid, mon.hp, mon.stats.hp, mon.holderLevel))
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	return true
end

createPokemon:separator(" ")
createPokemon:groupType("god")
createPokemon:register()
