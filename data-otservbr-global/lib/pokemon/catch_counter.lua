-- How many balls this trainer has burnt on this species since the last catch.
--
-- Telemetry, not pity: it informs the player and feeds nothing back into the
-- chance. It exists now so that the day anti-frustration is worth having, the
-- number it would need is already on disk.
--
-- One key per species per ball type. The legacy base kept all seven ball types
-- concatenated into one string and re-parsed it with `gsub` on every read; the
-- lessons doc has what that cost, including a line in that base that sums the
-- wrong field.

Pokemon = Pokemon or {}

local function scope(player, species)
	return player:kv():scoped("pokemon"):scoped("catch-spent"):scoped(species)
end

--- One more ball of this kind, thrown at this species and lost.
function Pokemon.recordThrow(player, species, ballItemId)
	local store = scope(player, species)
	local key = tostring(ballItemId)
	store:set(key, (store:get(key) or 0) + 1)
end

--- What has been spent on this species so far, by ball item id.
function Pokemon.spentOn(player, species)
	local store = scope(player, species)
	local out = {}
	for _, key in ipairs(store:keys() or {}) do
		local count = store:get(key)
		if count and count > 0 then
			out[tonumber(key)] = count
		end
	end
	return out
end

--- Wipe the tally. Called on a successful catch, and only there.
function Pokemon.clearSpent(player, species)
	local store = scope(player, species)
	for _, key in ipairs(store:keys() or {}) do
		store:remove(key)
	end
end

--- "3 poke balls and 1 great ball", or nil when nothing was spent.
--
-- ASCII only and no accents: the client renders anything else as rubbish.
-- Ordered by the ball table's multiplier so the sentence always reads cheapest
-- first, rather than in whatever order the kv store hands the keys back.
function Pokemon.describeSpent(spent)
	local parts = {}
	local ordered = {}
	for itemId in pairs(spent) do
		ordered[#ordered + 1] = itemId
	end
	table.sort(ordered, function(a, b)
		local ba, bb = Pokemon.BALLS[a], Pokemon.BALLS[b]
		return (ba and ba.multiplier or 0) < (bb and bb.multiplier or 0)
	end)

	for _, itemId in ipairs(ordered) do
		local ball = Pokemon.BALLS[itemId]
		local count = spent[itemId]
		local name = ball and ball.name or "ball"
		parts[#parts + 1] = string.format("%d %s%s", count, name, count > 1 and "s" or "")
	end

	if #parts == 0 then
		return nil
	end
	if #parts == 1 then
		return parts[1]
	end
	return table.concat(parts, ", ", 1, #parts - 1) .. " and " .. parts[#parts]
end
