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

-- Both are registered at login, which is how Canary binds a creaturescript to
-- a player.
local onLoginEvent = CreatureEvent("PokemonOnLogin")

function onLoginEvent.onLogin(player)
	player:registerEvent("PokemonOnLogout")
	player:registerEvent("PokemonOnPlayerDeath")
	-- Fresh session: nothing in play. A safety belt in case the id is reused.
	Pokemon.clearSession(player)
	return true
end

onLoginEvent:register()
