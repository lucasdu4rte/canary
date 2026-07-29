-- Ciclo de vida do Pokémon summonado: logout, morte do dono e morte do próprio.
--
-- Estes são os pontos em que o HP tem que ir para o item. Fora deles, dano não
-- persiste — decisão fechada na spec.

-- Logout: recolhe. Nada pode ficar em campo sem dono online, e o recall já
-- grava a vida com que ele voltou.
local aoSair = CreatureEvent("PokemonOnLogout")

function aoSair.onLogout(player)
	Pokemon.recall(player)
	Pokemon.clearSession(player)
	return true
end

aoSair:register()

-- Dono morreu: o Pokémon não fica órfão em campo.
local aoMorrer = CreatureEvent("PokemonOnPlayerDeath")

function aoMorrer.onDeath(player)
	Pokemon.recall(player)
	return true
end

aoMorrer:register()

-- Registro dos dois no login, que é como o Canary liga creaturescript a
-- jogador.
local aoEntrar = CreatureEvent("PokemonOnLogin")

function aoEntrar.onLogin(player)
	player:registerEvent("PokemonOnLogout")
	player:registerEvent("PokemonOnPlayerDeath")
	-- Sessão nova: nada em campo. Cinto de segurança caso o id seja reusado.
	Pokemon.clearSession(player)
	return true
end

aoEntrar:register()
