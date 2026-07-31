-- Per-move cooldown, stored on the ball.
--
-- WHY THE BALL AND NOT A TABLE IN MEMORY
--
-- A memory table cleared on recall has a hole in it: recalling and re-summoning
-- would reset every cooldown at once. With 20-40s cooldowns that is not an edge
-- case, it is the dominant way to play -- send out, land the big move, recall,
-- send out again. Roxy stores it on the ball for exactly this reason.
--
-- It is also the architecture phase 3 already settled: the item is the source
-- of truth, and a side table keyed by pokemon is the "parallel cache" that
-- phase 3's constraint rules out.
--
-- WHY ONE ATTRIBUTE AND NOT ONE PER MOVE
--
-- 🔴 A key per move was the first design, and it did not survive its own test.
-- Measured 2026-07-30 in the client: use a move, recall, send out again, and
-- every cooldown was back to zero -- the exact exploit the ball was chosen to
-- close, reproduced by the fix for it.
--
-- The cause is that sending a pokemon out swaps the ball's sprite, and
-- `syncVisual` does that with `snapshot` -> `transform` -> `restore`. Both of
-- those walk `FIELDS`, so anything outside that schema is dropped. Per-move
-- keys were deliberately outside it, on the reasoning that they are disposable
-- and that putting them in would make `read` walk hundreds of possible keys.
-- The first half was wrong: they are not disposable, they are the rule the
-- server enforces. The second half is answered by serialising all of them into
-- ONE schema field -- `read` walks one key, and snapshot carries it for free.
--
-- Format: `Name:expiry|Name:expiry`. Move names carry no `:` or `|` (checked
-- against all 360), and the worst case -- fourteen moves at the longest name --
-- is under 500 characters.
--
-- Expiry is an ABSOLUTE instant, not a remaining duration. A duration would
-- need something to decrement it, and there is no tick here to do so: it would
-- freeze while the ball sat in a depot and resume on pickup.
--
-- Whole seconds are enough: the shortest cooldown in the roster is 2s.

Pokemon = Pokemon or {}

local FIELD = "pokemon_cds"

local function load(item)
	local out = {}
	local raw = item and item:getCustomAttribute(FIELD)
	if type(raw) ~= "string" then
		return out
	end
	for entry in raw:gmatch("[^|]+") do
		local name, expiry = entry:match("^(.-):(%d+)$")
		if name then
			out[name] = tonumber(expiry)
		end
	end
	return out
end

-- Expired entries are dropped on every write, so the string cannot grow past
-- the number of moves currently on cooldown.
local function save(item, entries)
	local now = os.time()
	local parts = {}
	for name, expiry in pairs(entries) do
		if expiry > now then
			parts[#parts + 1] = name .. ":" .. expiry
		end
	end
	item:setCustomAttribute(FIELD, table.concat(parts, "|"))
end

--- Seconds left on a move, or 0 when it is ready.
function Pokemon.moveCooldownLeft(item, moveName)
	if not item then
		return 0
	end
	local expiry = load(item)[moveName]
	if not expiry then
		return 0
	end
	local left = expiry - os.time()
	return left > 0 and left or 0
end

--- Whether a move can be used right now.
function Pokemon.moveReady(item, moveName)
	return Pokemon.moveCooldownLeft(item, moveName) <= 0
end

--- Starts the cooldown for a move.
-- @param seconds cooldown for this move on this species (from the catalogue)
function Pokemon.markMoveUsed(item, moveName, seconds)
	if not item or not seconds or seconds <= 0 then
		return
	end
	local entries = load(item)
	entries[moveName] = os.time() + seconds
	save(item, entries)
end

--- Cooldown this species has for this move, or nil if it does not know it.
function Pokemon.moveCooldownFor(species, moveName)
	local data = PokemonSpecies[species]
	if not data then
		return nil
	end
	for _, entry in ipairs(data.moves or {}) do
		if entry.name == moveName then
			return entry.cooldown
		end
	end
	return nil
end
