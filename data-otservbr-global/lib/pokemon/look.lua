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
-- Nada é gravado: HP máximo depende do level do portador, então texto
-- congelado mente no primeiro level up.
function Pokemon.describe(mon)
	local linhas = { string.format("You see %s.", mon.species) }

	if mon.fainted then
		linhas[#linhas + 1] = "It is fainted."
	end

	if mon.hp then
		-- Com portador: números absolutos fazem sentido.
		linhas[#linhas + 1] = string.format("HP: %d / %d", mon.hp, mon.stats.hp)
	else
		-- Sem portador (chão, depot): HP absoluto seria um número inventado,
		-- porque não há level de quem o carregue. Fração é honesta.
		linhas[#linhas + 1] = string.format("HP: %d%%", math.floor(mon.hpRatio * 100 + 0.5))
	end

	linhas[#linhas + 1] = string.format("Original trainer: %s.", trainerName(mon.ot))
	return table.concat(linhas, "\n")
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
