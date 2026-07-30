-- Descrição da ball ocupada.
--
-- Sobrescreve `Item.getDescription` em vez de registrar outro `playerOnLook`.
-- O motivo é que o C++ não manda texto nenhum no look: quem monta e envia é
-- `data/scripts/eventcallbacks/player/on_look.lua`, chamando
-- `inspectedThing:getDescription(distance)`. Registrar um segundo callback
-- mandaria uma **segunda** mensagem em vez de substituir a primeira.
--
-- Que dá para sobrescrever método registrado no C++ foi testado em 2026-07-29.

Pokemon = Pokemon or {}

local originalGetDescription = Item.getDescription

-- O C++ tem `Game::getPlayerNameByGUID` com cache próprio, mas ele **não está
-- exposto ao Lua**. A única via daqui é `Game.getOfflinePlayer`, que carrega o
-- jogador inteiro do banco — caro demais para rodar a cada look, ainda mais
-- porque query síncrona trava o game loop inteiro, não só quem olhou.
--
-- Daí o memo: uma ida ao banco por treinador, por boot. Nome que mudou depois
-- fica velho até o próximo restart, e isso é cosmético.
local nameCache = {}

local function trainerName(guid)
	local cached = nameCache[guid]
	if cached then
		return cached
	end
	local p = Game.getOfflinePlayer(guid)
	local nome = (p and p:getName()) or ("#" .. tostring(guid))
	nameCache[guid] = nome
	return nome
end

--- Monta a descrição a partir do item, sempre na hora.
--
-- ⚠️ **Não começa com "You see"**: quem prefixa isso é o `on_look.lua` do
-- datapack (`return "You see " .. descriptionText`). Incluir aqui produz
-- "You see You see Charizard." — foi o que aconteceu na primeira versão.
--
-- HP ficou de fora de propósito: número de vida no look não ajuda a decidir
-- nada, e o valor útil (quem é o dono) fica enterrado no meio.
function Pokemon.describe(mon)
	-- "a pokeball" é fixo enquanto só existe um tipo de ball. Quando a Fase 5
	-- trouxer great/super/ultra, é aqui que entra o nome do tipo — e é por
	-- isso que a frase nomeia o recipiente antes do conteúdo em vez de dizer
	-- "You see Charizard": a ball é o item, o Pokémon é o que vai dentro.
	local conteudo = mon.fainted and ("a fainted " .. mon.species) or mon.species
	local frase = "a pokeball with " .. conteudo

	if mon.holder then
		-- Dono atual é simplesmente quem está com o item — no modelo de
		-- item-guarda-tudo não existe coluna de dono para divergir disso.
		frase = frase .. string.format(", belonging to %s.", mon.holder:getName())

		-- Só vale dizer o treinador original quando ele **não** é o dono
		-- atual: aí a frase conta uma história (mudou de mão). Repetir o mesmo
		-- nome duas vezes é ruído.
		if mon.holder:getGuid() ~= mon.ot then
			frase = frase .. string.format(" Originally caught by %s.", trainerName(mon.ot))
		end
	else
		-- Sem portador (chão, depot): não há dono a apontar, então o único
		-- nome honesto é o do treinador original.
		frase = frase .. string.format(", originally caught by %s.", trainerName(mon.ot))
	end

	return frase
end

function Item.getDescription(self, distance)
	local mon = Pokemon.read(self)
	if not mon then
		-- Delegar é obrigatório, não cortesia: sem isto **todo** item do jogo
		-- perde a descrição.
		return originalGetDescription(self, distance)
	end
	return Pokemon.describe(mon)
end
