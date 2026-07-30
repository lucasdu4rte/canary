-- Lifecycle of a pokemon that is out: logout, owner death, and its own death.
--
-- These are the moments HP has to reach the item. Outside them damage does not
-- persist -- a decision settled in the spec.

-- Logout: recall. Nothing may stay in play with no owner online, and the
-- recall already stores the health it came back with.
local onLogoutEvent = CreatureEvent("PokemonOnLogout")

function onLogoutEvent.onLogout(player)
	Pokemon.recall(player)
	Pokemon.clearSession(player)
	return true
end

onLogoutEvent:register()

-- Owner died: the pokemon is not left orphaned in play.
--
-- Note the capital D. With `ondeath`, revscriptsys cannot map the name, falls
-- through to `rawset` on the userdata and **the whole file fails to load** --
-- not just this one event.
local onDeathEvent = CreatureEvent("PokemonOnPlayerDeath")

function onDeathEvent.onDeath(player)
	Pokemon.recall(player)
	return true
end

onDeathEvent:register()

-- A pokemon that reaches the edge of what its trainer can see comes back to
-- them, rather than walking out of view and being followed by nothing.
--
-- The engine already teleports a familiar to its master, but only past 15
-- tiles or a floor apart (`creature.cpp:472`) -- which is well outside the
-- screen, so the pokemon would spend that whole stretch invisible. This fires
-- first and the engine's rule never gets the chance.
--
-- The trigger is the **second to last** visible tile, so it happens while the
-- pokemon is still on screen: the client shows 8 tiles either side and 6 above
-- and below (`map_const.hpp:12-13`), and one in from that is 7 and 5. Waiting
-- for the very edge would make it blink out and reappear.
local VIEW_X = 8 - 1
local VIEW_Y = 6 - 1

local onThinkEvent = CreatureEvent("PokemonFollowTrainer")

function onThinkEvent.onThink(creature, interval)
	local master = creature:getMaster()
	if not master or not master:isPlayer() then
		return true
	end

	local here, there = creature:getPosition(), master:getPosition()
	if here.z == there.z
		and math.abs(here.x - there.x) < VIEW_X
		and math.abs(here.y - there.y) < VIEW_Y then
		return true
	end

	-- pushMovement: land beside the trainer rather than inside them, and let
	-- the engine find the free tile.
	creature:teleportTo(there, true)
	creature:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

onThinkEvent:register()

-- The pokemon itself died: mark the ball fainted.
--
-- Registered on the MonsterType rather than on each creature after the summon,
-- so a pokemon that reaches the map by any other route still faints properly.
--
-- Without this the ball keeps the health it had before the fight: the session
-- entry vanishes on its own when `getActive` finds the creature removed, and
-- nothing ever writes to the item. Faint would exist only as an API nobody
-- calls.
local onFaintEvent = CreatureEvent("PokemonFaint")

function onFaintEvent.onDeath(creature, corpse, killer, mostDamageKiller, unjustified, mostDamageUnjustified)
	local master = creature:getMaster()
	if master and master:isPlayer() then
		Pokemon.faint(master)
	end
	return true
end

onFaintEvent:register()

-- Both player events are registered at login, which is how Canary binds a
-- creaturescript to a player.
local onLoginEvent = CreatureEvent("PokemonOnLogin")

function onLoginEvent.onLogin(player)
	player:registerEvent("PokemonOnLogout")
	player:registerEvent("PokemonOnPlayerDeath")
	-- Fresh session: nothing in play. A safety belt in case the id is reused.
	Pokemon.clearSession(player)

	-- And since nothing is in play, no ball should be wearing the empty
	-- sprite. Only a crash with a pokemon out can leave one that way -- the
	-- id is on disk, the session that explained it is not.
	local fixed = Pokemon.normalizeVisuals(player)
	if fixed > 0 then
		logger.info(string.format("[pokemon] %s: %d ball(s) put back in colour after an unclean shutdown",
			player:getName(), fixed))
	end
	return true
end

onLoginEvent:register()
