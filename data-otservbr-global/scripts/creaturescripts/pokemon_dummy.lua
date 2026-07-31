-- What a dummy does when something hits it: report, and refill.
--
-- The report is the whole point. A dummy that only absorbs damage answers
-- nothing an ordinary wild does not already answer; a dummy that names itself
-- and its offset every time it is hit turns "did the burst reach three
-- creatures" into three lines on screen you can count.
--
-- Registered per instance from `Pokemon.makeDummy`, not on the MonsterType --
-- all 154 species share those, and a normal pokemon must not pay for this.

local dummy = CreatureEvent("PokemonDummy")

--- "+2,0" -- offset with the sign always shown, so a column reads as a column.
local function offset(from, to)
	local dx, dy = to.x - from.x, to.y - from.y
	return string.format("%+d,%+d", dx, dy)
end

function dummy.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end

	-- Damage arrives negative (game.cpp:8333 takes positive to mean healing) and
	-- the engine runs std::abs over whatever we hand back, so the sign is ours to
	-- ignore in both directions.
	local total = math.abs(primaryDamage or 0) + math.abs(secondaryDamage or 0)

	-- Nothing to report on a zero: `PokemonDamageRules` runs first and flattens a
	-- trainer's own weapon to nothing, and printing "took 0 damage" for every
	-- sword swing would bury the numbers that matter.
	if total > 0 and attacker then
		local master = attacker:getMaster()
		local watcher = (master and master:isPlayer()) and master or nil
		if watcher then
			watcher:sendTextMessage(MESSAGE_STATUS, string.format(
				"Dummy %s at %s took %d.",
				creature:getName(), offset(attacker:getPosition(), creature:getPosition()), total))
		end
	end

	-- Refill AFTER the hit lands, which is why it is deferred rather than done
	-- here: this hook runs before the damage is applied, so healing inside it
	-- would only be spent by the blow that follows.
	--
	-- Cosmetic, strictly. `Pokemon.DUMMY_HEALTH` is already past any damage this
	-- game can produce; this is what keeps the bar reading full so a second test
	-- starts where the first one did.
	addEvent(function(id)
		local mon = Creature(id)
		if mon and not mon:isRemoved() then
			mon:addHealth(mon:getMaxHealth())
		end
	end, 0, creature:getId())

	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

dummy:register()
