-- The automatic attack: the second of the two clocks a fight runs on.
--
-- The MonsterType declares `attacks = {}` and keeps it that way. A MonsterType
-- attack carries a damage written into the type, so it could not scale with the
-- trainer's level -- the same reason the generated health is only a ceiling and
-- summon.lua sets the real value. Running it from here instead means the
-- automatic attack goes through Pokemon.damage like everything else and picks
-- up level, stats, STAB and effectiveness for free.
--
-- Throttled here rather than by the think interval: `onThink` fires far more
-- often than a pokemon should swing, and the interval is not something this
-- script gets to choose.

local lastAttack = {}

-- Purely a timer, cleared when the creature goes. Nothing here is state a
-- pokemon owns -- the item stays the source of truth for everything that
-- survives, and losing this on a restart costs at most one swing.
local autoAttack = CreatureEvent("PokemonAutoAttack")

function autoAttack.onThink(creature, interval)
	local id = creature:getId()

	if creature:isRemoved() then
		lastAttack[id] = nil
		return true
	end

	local now = os.time()
	local last = lastAttack[id]
	if last and now - last < Pokemon.AUTO_ATTACK_INTERVAL then
		return true
	end

	if Pokemon.autoAttack(creature) then
		lastAttack[id] = now
	end
	return true
end

autoAttack:register()
