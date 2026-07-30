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
