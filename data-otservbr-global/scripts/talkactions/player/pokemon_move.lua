-- !m1 .. !mN, !moves, and !move <name>
--
-- The order channel for phase 4. Phase 6 replaces it with a client UI; the
-- executor it calls does not change, because the rules live in the server and
-- this only carries the intent.
--
-- Slots, not names, because that is how the source game plays and because it is
-- what a fight can actually keep up with: `!m3` is one keystroke under pressure,
-- `!move Hydro Pump` is not. The numbering is the position in the species' move
-- list, which is also what the PxG wiki labels M1..M14.
--
-- Every refusal comes back as a message. Silence is what makes a working move
-- and a broken one look the same, and 102 of the 360 moves deal no damage yet.

-- One registration per slot: TalkAction matches the whole word, so there is no
-- prefix form. Bounded by KEYBOUND_SLOTS -- the moves get bound to F1..F12 and
-- there is no F13, so a thirteenth command would be one nothing can press.
for slot = 1, Pokemon.KEYBOUND_SLOTS do
	local command = TalkAction("!m" .. slot)

	function command.onSay(player, words, param)
		local ok, reason = Pokemon.useMoveSlot(player, slot)
		if not ok then
			player:sendCancelMessage(reason)
		end
		return true
	end

	command:separator(" ")
	command:groupType("normal")
	command:register()
end

-- `!cd`, in the source game's own layout and under the source game's own name.
--
-- Was `!moves`, and the rename is the point rather than a detail: the list is
-- read mid-fight to find out what is off cooldown, not to browse a movepool, and
-- the name should say which question it answers.
--
-- The shape is PxG's, given verbatim by the player who plays it:
--
--     Pokemon: Dodrio.
--     Sand Attack - m1 10/10 seconds; ready.
--     Aerial Ace - m7: wait 35/40 seconds.
--
-- Move name first because that is what the eye scans for; the slot second
-- because it is what the hand types. `left/total` on both branches so the wait
-- is legible against the whole cooldown instead of as a bare number.
--
-- ⚠️ "Pokemon", not "Pokémon". The client does not decode UTF-8 in these
-- messages -- the accent arrives on screen as mojibake -- so player-facing text
-- is ASCII throughout. This is the one place the difference is visible against
-- the format as it was written down.
local listMoves = TalkAction("!cd")

function listMoves.onSay(player, words, param)
	local entry = Pokemon.getActive(player)
	if not entry then
		player:sendCancelMessage("You have no pokemon at your side.")
		return true
	end

	local mon = Pokemon.read(entry.item)
	local species = mon and PokemonSpecies[Pokemon.effectiveSpecies(mon)]
	if not species then
		player:sendCancelMessage("That pokemon cannot be read.")
		return true
	end

	local known = species.moves or {}
	if #known == 0 then
		player:sendTextMessage(MESSAGE_STATUS, string.format("%s knows no moves.", mon.species))
		return true
	end

	player:sendTextMessage(MESSAGE_STATUS, string.format("Pokemon: %s.", mon.species))
	for slot, item in ipairs(known) do
		local move = PokemonMoves[item.name]
		-- Past F12 there is no key to bind, so the slot gets no number. Saying so
		-- is the point: a move listed as `m13` that nothing can press would look
		-- broken, and one hidden entirely would look like it does not exist.
		local label = slot <= Pokemon.KEYBOUND_SLOTS and string.format("m%d", slot) or "--"
		local line
		if not move then
			line = string.format("%s - %s; unavailable.", item.name, label)
		else
			local left = Pokemon.moveCooldownLeft(entry.item, item.name)
			if left > 0 then
				line = string.format("%s - %s: wait %d/%d seconds.", item.name, label, left, item.cooldown)
			elseif move.power <= 0 then
				-- Ready, and still does nothing. Both halves are true and the
				-- player needs both: it is not on cooldown, and pressing it will
				-- refuse. Hiding either one turns a known gap into a mystery.
				line = string.format("%s - %s %d/%d seconds; no effect yet.",
					item.name, label, item.cooldown, item.cooldown)
			else
				line = string.format("%s - %s %d/%d seconds; ready.",
					item.name, label, item.cooldown, item.cooldown)
			end
		end
		player:sendTextMessage(MESSAGE_STATUS, line)
	end

	if #known > Pokemon.KEYBOUND_SLOTS then
		player:sendTextMessage(MESSAGE_STATUS, string.format(
			"The last %d have no key: only F1-F%d can be bound.",
			#known - Pokemon.KEYBOUND_SLOTS, Pokemon.KEYBOUND_SLOTS))
	end
	return true
end

listMoves:separator(" ")
listMoves:groupType("normal")
listMoves:register()

-- Debug only, and god-only on purpose: naming a move directly skips the slot,
-- which is the whole interface a player has. Handy for reproducing one specific
-- move without hunting for a species that carries it in a given position.
local useByName = TalkAction("!move")

function useByName.onSay(player, words, param)
	local wanted = param:trim()
	if wanted == "" then
		player:sendCancelMessage("Usage: !move <name> -- debug, and the only way to reach a slot past !m"
			.. Pokemon.KEYBOUND_SLOTS .. ".")
		return true
	end

	local entry = Pokemon.getActive(player)
	if not entry then
		player:sendCancelMessage("You have no pokemon at your side.")
		return true
	end

	local mon = Pokemon.read(entry.item)
	local species = mon and PokemonSpecies[Pokemon.effectiveSpecies(mon)]
	if not species then
		player:sendCancelMessage("That pokemon cannot be read.")
		return true
	end

	-- Resolved case-insensitively against what this pokemon knows. Typing
	-- "Hydro Pump" with exact capitals is not a skill worth testing.
	local resolved = nil
	local lowered = wanted:lower()
	for _, item in ipairs(species.moves or {}) do
		if item.name:lower() == lowered then
			resolved = item.name
			break
		end
	end

	local ok, reason = Pokemon.useMove(player, resolved or wanted)
	if not ok then
		player:sendCancelMessage(reason)
	end
	return true
end

useByName:separator(" ")
useByName:groupType("god")
useByName:register()
