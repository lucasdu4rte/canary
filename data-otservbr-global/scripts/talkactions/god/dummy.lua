-- /dummy [count] [species]  --  put targets down that stay put
-- /dummy clear              --  take them away again
--
-- Sibling of /create-wild, and the difference is the point: a wild moves, hits
-- back and dies, which is exactly what you do not want when the thing being
-- measured is where a move landed.
--
-- The row runs east so a burst and a beam can be told apart with one setup:
-- the burst is centred on whatever you targeted and should reach its
-- neighbours, while a beam runs along the line your pokemon is facing. Stand
-- west of the row and both shapes report their own footprint.

-- Pure Normal, and passive. Only Fighting is super effective against it and
-- only Ghost is immune, so a damage number measured here is the neutral one --
-- which is what you want from a default. Ask for another species when the
-- matchup IS the measurement.
local DEFAULT_SPECIES = "Chansey"

local MAX_COUNT = 8

local dummy = TalkAction("/dummy")

local function resolveSpecies(input)
	local wanted = input:lower()
	for name in pairs(PokemonSpecies) do
		if name:lower() == wanted then
			return name
		end
	end
	return nil
end

function dummy.onSay(player, words, param)
	logCommand(player, words, param)

	local position = player:getPosition()
	local args = {}
	for word in param:trim():gmatch("%S+") do
		args[#args + 1] = word
	end

	if args[1] and args[1]:lower() == "clear" then
		local removed = Pokemon.clearDummies(position)
		player:sendTextMessage(MESSAGE_ADMINISTRATOR, string.format(
			"%d dummy removed.", removed))
		return true
	end

	local count = tonumber(args[1])
	if count then
		table.remove(args, 1)
		count = math.max(1, math.min(MAX_COUNT, math.floor(count)))
	else
		count = 1
	end

	-- Joined rather than taken as one word: Mr. Mime and Farfetch'd have spaces
	-- and apostrophes in them, and a species argument that silently drops the
	-- second half reads as "there is no pokemon named Mr.".
	local input = table.concat(args, " ")
	local species = input == "" and DEFAULT_SPECIES or resolveSpecies(input)
	if not species then
		player:sendCancelMessage(string.format("There is no pokemon named '%s'.", input))
		return true
	end

	local placed, first = 0, nil
	for i = 1, count do
		-- From two tiles out, so the row is clear of the tile you stand on and a
		-- contact move still has somewhere to walk to.
		local spot = Position(position.x + 1 + i, position.y, position.z)
		local monster = Game.createMonster(Pokemon.monsterName(species), spot, false, true)
		if monster and Pokemon.makeDummy(monster) then
			placed = placed + 1
			first = first or monster
			spot:sendMagicEffect(CONST_ME_TELEPORT)
		end
	end

	if placed == 0 then
		player:sendCancelMessage(string.format("Could not place a %s dummy here.", species))
		return true
	end

	player:sendTextMessage(MESSAGE_ADMINISTRATOR, string.format(
		"%d %s dummy placed to the east, level %d. They report every hit.",
		placed, species, Pokemon.wildLevel(species, position)))

	if placed < count then
		player:sendTextMessage(MESSAGE_ADMINISTRATOR, string.format(
			"%d of %d could not be placed - something is in the way.", count - placed, count))
	end

	-- 🔴 The confound that has already cost this phase a wrong conclusion once:
	-- inside a protection zone every move refuses, and the refusal reads like a
	-- broken command rather than a rule. Worth a line before the test, not after.
	local tile = Tile(position)
	if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		player:sendTextMessage(MESSAGE_ADMINISTRATOR,
			"WARNING: you are in a protection zone. Moves refuse to fire here - walk out first.")
	end

	return true
end

dummy:separator(" ")
dummy:groupType("god")
dummy:register()
