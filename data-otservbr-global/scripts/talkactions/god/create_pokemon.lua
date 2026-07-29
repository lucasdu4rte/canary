-- /create-pokemon <espécie>
--
-- A captura só chega na Fase 5. Sem isto, nada nesta fase chama
-- `Pokemon.create` e o gate G3 fica sem sujeito.
--
-- Genérico por desenho: a espécie é argumento, validada contra o catálogo.
-- Um comando serve as 154 — nada de script por espécie nem lista paralela
-- para manter em dia.

local createPokemon = TalkAction("/create-pokemon")

function createPokemon.onSay(player, words, param)
	logCommand(player, words, param)

	local especie = param:trim()
	if especie == "" then
		player:sendCancelMessage("Usage: /create-pokemon <species>")
		return true
	end

	-- Aceita "bulbasaur" e "BULBASAUR" resolvendo para a chave do catálogo,
	-- que é capitalizada. Digitar o nome exato de 154 espécies com a caixa
	-- certa não é um teste de habilidade que valha a pena aplicar.
	local chave = nil
	local alvo = especie:lower()
	for nome in pairs(PokemonSpecies) do
		if nome:lower() == alvo then
			chave = nome
			break
		end
	end

	if not chave then
		player:sendCancelMessage(string.format("There is no pokemon named '%s'.", especie))
		return true
	end

	local item, erro = Pokemon.create(player, chave)
	if not item then
		player:sendCancelMessage(string.format("Could not create %s: %s", chave, erro or "unknown"))
		return true
	end

	local mon = Pokemon.read(item)
	player:sendTextMessage(MESSAGE_ADMINISTRATOR, string.format(
		"Created %s (uid %.0f) — HP %d/%d at your level %d.",
		mon.species, mon.uid, mon.hp, mon.stats.hp, mon.holderLevel))
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN)
	return true
end

createPokemon:separator(" ")
createPokemon:groupType("god")
createPokemon:register()
