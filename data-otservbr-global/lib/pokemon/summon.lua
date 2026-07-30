-- Summon e recall.
--
-- O vínculo entre o jogador, a criatura e a ball é **estado de sessão**, não
-- persistido. Isso é escolha, e ela paga: crash do servidor não deixa órfão,
-- porque não existe nada gravado dizendo "está summonado". Sobe limpo, todos
-- na ball — sem a normalização de boot que os desenhos anteriores exigiam.
--
-- Em troca, o HP só é gravado no item em três momentos: recolher, desmaiar e
-- logout. Dano **não** persiste durante o combate. O pior resultado de um
-- crash é o jogador ganhar vida de volta, e isso é barato demais para
-- justificar escrita a cada tick.

Pokemon = Pokemon or {}

-- [playerId] = { creature = <Monster>, item = <Item> }
local ativos = {}

--- O Pokémon que este jogador tem fora da ball, se houver.
function Pokemon.getActive(player)
	local reg = ativos[player:getId()]
	if not reg then
		return nil
	end
	-- A criatura pode ter morrido ou sumido sem passar por recall.
	if not reg.creature or reg.creature:isRemoved() then
		ativos[player:getId()] = nil
		return nil
	end
	return reg
end

--- Solta o Pokémon da ball.
-- @return criatura, ou nil + motivo
function Pokemon.summon(player, item)
	local mon = Pokemon.read(item)
	if not mon then
		return nil, "That is not a pokemon."
	end

	if mon.fainted then
		return nil, string.format("%s is fainted and cannot be sent out.", mon.species)
	end

	if Pokemon.getActive(player) then
		return nil, "You already have a pokemon out."
	end

	-- O portão de progressão do jogo: capturar acima do seu level é legítimo,
	-- usar não é. A checagem é do servidor, sempre.
	local exigido = mon.speciesData.minPlayerLevel
	if exigido and player:getLevel() < exigido then
		return nil, string.format("%s requires level %d; you are level %d.",
			mon.species, exigido, player:getLevel())
	end

	-- extended + force: `placeCreature` recusa em protection zone e em tile
	-- ocupado quando `force` é falso, e foi isso que fez o summon responder
	-- "could not send out" dentro do templo. Soltar o Pokémon é ação pedida
	-- pelo jogador — não pode falhar por causa do piso.
	--
	-- O master vai no 5º parâmetro em vez de `setMaster` depois: o C++ o aplica
	-- **antes** de posicionar, então a criatura já nasce como summon.
	local creature = Game.createMonster(
		Pokemon.monsterName(mon.species), player:getPosition(), true, true, player)
	if not creature then
		return nil, string.format("Could not send out %s.", mon.species)
	end

	-- O HP da criatura reflete a fração guardada no item, escalada pelo level
	-- de quem a está soltando agora.
	local maxHp = mon.stats and mon.stats.hp or mon.speciesData.baseStats.hp
	creature:setMaxHealth(maxHp)
	creature:addHealth(maxHp - creature:getHealth())
	local atual = math.max(1, math.floor(maxHp * mon.hpRatio))
	creature:addHealth(atual - creature:getHealth())

	ativos[player:getId()] = { creature = creature, item = item }
	return creature
end

--- Guarda o Pokémon de volta, gravando a vida com que ele voltou.
-- @return true se havia algo para recolher
function Pokemon.recall(player)
	local reg = Pokemon.getActive(player)
	if not reg then
		return false
	end

	local creature, item = reg.creature, reg.item
	ativos[player:getId()] = nil

	-- Único ponto de escrita do estado de combate, junto com recordFaint.
	if item then
		local maxHp = creature:getMaxHealth()
		local ratio = maxHp > 0 and (creature:getHealth() / maxHp) or 0
		Pokemon.recordReturn(item, math.max(0.0, math.min(1.0, ratio)))
	end

	creature:remove()
	return true
end

--- Desmaio: força o recall e marca o item.
function Pokemon.faint(player)
	local reg = Pokemon.getActive(player)
	if not reg then
		return false
	end
	local item = reg.item
	ativos[player:getId()] = nil

	if reg.creature and not reg.creature:isRemoved() then
		reg.creature:remove()
	end
	if item then
		Pokemon.recordFaint(item)
	end
	return true
end

--- Usado pela proteção do treinador: o jogador tem Pokémon em campo?
function Pokemon.hasActive(player)
	return Pokemon.getActive(player) ~= nil
end

--- Limpa o registro de um jogador que saiu.
function Pokemon.clearSession(player)
	ativos[player:getId()] = nil
end
