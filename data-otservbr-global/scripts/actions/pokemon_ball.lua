-- Usar a ball solta o Pokémon; usar de novo recolhe.
--
-- A ball **continua no inventário** enquanto ele está fora. O que muda é o
-- estado de sessão, não a posição do item.

local ball = Action()

function ball.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local mon = Pokemon.read(item)
	if not mon then
		return false -- ball vazia ou item qualquer: deixa o Canary tratar
	end

	local ativo = Pokemon.getActive(player)

	-- Usar a ball do Pokémon que já está em campo = recolher.
	if ativo and ativo.item == item then
		Pokemon.recall(player)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s comes back.", mon.species))
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		return true
	end

	local creature, motivo = Pokemon.summon(player, item)
	if not creature then
		player:sendCancelMessage(motivo)
		return true
	end

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Go, %s!", mon.species))
	creature:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	return true
end

ball:id(Pokemon.PLACEHOLDER_BALL_ID)
ball:register()
