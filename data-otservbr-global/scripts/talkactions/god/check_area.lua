-- /check-area [move name]
--
-- Checks the geometry that shaped moves are delivered through, and optionally
-- fires one with NO TARGET to prove an area move no longer needs somebody to be
-- standing there.
--
-- Why a command at all: the shape used to live inside the engine, behind
-- `createCombatArea`, and nothing could ask it what it covered. That is how 191
-- area moves spent weeks being delivered as single target with the move firing,
-- the damage landing and the message printing exactly as they should. The
-- footprint is Lua now, so it can be counted -- and a count is what would have
-- caught that in an afternoon.
--
-- Expected output is OK on every line.

local EXPECTED = {
	-- The 7x7 circle, corners cut: 3 + 5 + 7 + 7 + 7 + 5 + 3.
	aoe = 37,
	self = 37,
	-- Four tiles ahead, plus the one it lands on.
	beam = 5,
}

local DIRECTIONS = {
	{ DIRECTION_NORTH, "north", 0, -1 },
	{ DIRECTION_EAST, "east", 1, 0 },
	{ DIRECTION_SOUTH, "south", 0, 1 },
	{ DIRECTION_WEST, "west", -1, 0 },
}

local BEAM_LENGTH = 4

local function key(offset)
	return offset[1] .. ":" .. offset[2]
end

local function keySet(offsets)
	local set = {}
	for _, offset in ipairs(offsets) do
		set[key(offset)] = true
	end
	return set
end

local function sameSet(a, b)
	for k in pairs(a) do
		if not b[k] then
			return false
		end
	end
	for k in pairs(b) do
		if not a[k] then
			return false
		end
	end
	return true
end

local checkArea = TalkAction("/check-area")

function checkArea.onSay(player, words, param)
	logCommand(player, words, param)

	local failures = {}
	local function check(ok, complaint)
		if not ok then
			failures[#failures + 1] = complaint
		end
	end

	-- 1. Every shape covers what it is meant to, in every direction. A rotation
	-- that drops or duplicates a tile changes the size, so the count catches it
	-- without anyone having to picture the matrix.
	for behavior, expected in pairs(EXPECTED) do
		for _, entry in ipairs(DIRECTIONS) do
			local offsets = Pokemon.shapeOffsets(behavior, entry[1])
			check(#offsets == expected, string.format(
				"%s facing %s covers %d tiles, expected %d",
				behavior, entry[2], #offsets, expected))
		end
	end

	-- 2. The burst is symmetric, so turning it must not move it. This is what
	-- says the rotation is a rotation rather than an arbitrary shuffle that
	-- happens to preserve the count.
	local base = keySet(Pokemon.shapeOffsets("aoe", DIRECTION_NORTH))
	for _, entry in ipairs(DIRECTIONS) do
		check(sameSet(base, keySet(Pokemon.shapeOffsets("aoe", entry[1]))),
			string.format("burst facing %s is not the burst facing north", entry[2]))
	end

	-- 3. The beam points where it is aimed. The count above holds even if a beam
	-- comes out backwards -- which is the failure that matters, because a move
	-- firing behind the pokemon looks like a move that missed.
	for _, entry in ipairs(DIRECTIONS) do
		local stepX, stepY = entry[3], entry[4]
		local onAxis, far = true, 0
		for _, offset in ipairs(Pokemon.shapeOffsets("beam", entry[1])) do
			-- Every tile is `n` steps along the aimed axis and nowhere else.
			local along = offset[1] * stepX + offset[2] * stepY
			if offset[1] ~= stepX * along or offset[2] ~= stepY * along or along < 0 then
				onAxis = false
			end
			far = math.max(far, along)
		end
		check(onAxis, string.format("beam facing %s leaves the axis or runs backwards", entry[2]))
		check(far == BEAM_LENGTH, string.format(
			"beam facing %s reaches %d tiles, expected %d", entry[2], far, BEAM_LENGTH))
	end

	for _, complaint in ipairs(failures) do
		player:sendTextMessage(MESSAGE_ADMINISTRATOR, "FAIL: " .. complaint)
	end
	if #failures == 0 then
		local shapes = 0
		for _ in pairs(EXPECTED) do
			shapes = shapes + 1
		end
		player:sendTextMessage(MESSAGE_ADMINISTRATOR, string.format(
			"OK - %d shapes, 4 directions each, all correct.", shapes))
	end

	-- 4. The live half, and the reason this file exists: fire a shaped move with
	-- nobody nominated. Centred on the pokemon, pointing wherever it faces --
	-- the exact path a trainer takes when no target is selected. Before this
	-- change the executor refused here rather than firing.
	if param and param ~= "" then
		local move = PokemonMoves[param]
		if not move then
			player:sendTextMessage(MESSAGE_ADMINISTRATOR, "No such move: " .. param)
			return true
		end
		if move.behavior == "target" then
			player:sendTextMessage(MESSAGE_ADMINISTRATOR, string.format(
				"%s is single target - nothing to check here.", param))
			return true
		end

		local entry = Pokemon.getActive(player)
		if not entry then
			player:sendTextMessage(MESSAGE_ADMINISTRATOR, "Send a pokemon out first.")
			return true
		end

		local attacker = Pokemon.combatantOf(entry.creature)
		if not attacker then
			player:sendTextMessage(MESSAGE_ADMINISTRATOR, "That pokemon cannot fight.")
			return true
		end

		local hits = Pokemon.deliverArea(attacker, move, entry.creature:getPosition(),
			entry.creature:getDirection(), nil)
		player:sendTextMessage(MESSAGE_ADMINISTRATOR, string.format(
			"%s (%s) fired with no target and hit %d.", param, move.behavior, hits))
	end

	player:getPosition():sendMagicEffect(
		#failures == 0 and CONST_ME_MAGIC_GREEN or CONST_ME_POFF)
	return true
end

checkArea:separator(" ")
checkArea:groupType("god")
checkArea:register()
