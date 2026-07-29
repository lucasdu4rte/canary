-- O item Pokémon: criar, ler e mudar de estado.
--
-- O item **é** o Pokémon. Não há tabela, não há linha, não há segunda fonte de
-- verdade. Tudo que sobrevive a um logout está nos custom attributes daqui.
--
-- Toda escrita passa por uma das operações nomeadas abaixo. Não existe setter
-- genérico de propósito: o problema estrutural das bases legadas foi vinte
-- arquivos escrevendo na bola sem dono, e um `write(item, campos)` é o mesmo
-- buraco com uma porta só.

Pokemon = Pokemon or {}

-- Sobe quando o layout de atributos mudar. `read` migra na leitura.
-- Sem isto não há conserto: o dado velho está espalhado pelo inventário dos
-- jogadores, e não existe banco onde rodar uma migração.
Pokemon.SCHEMA_VERSION = 1

-- Placeholder até a trilha de arte entregar os 308 ids por espécie.
-- 43901 "toy ball": tem a flag `take` no appearances e não é stackable, que
-- são os dois requisitos. Escolher por nome não basta — 10340 "heavy ball"
-- parece servir e **não é pegável**, então nenhum container aceita.
Pokemon.PLACEHOLDER_BALL_ID = 43901

-- Namespace dos MonsterTypes. O Canary registra como "<variant>|<nome>" e
-- mantém o nome de exibição, o que evita colisão com monstro do Tibia de
-- mesmo nome sem precisar tratar espécie por espécie.
Pokemon.MONSTER_VARIANT = "pokemon"

--- Chave do MonsterType de uma espécie.
function Pokemon.monsterName(species)
	return Pokemon.MONSTER_VARIANT .. "|" .. species
end

-- Campo, tipo e default num lugar só. Metade dos crashes medidos nas bases
-- legadas é atributo ausente lido sem default, de forma inconsistente entre
-- arquivos do mesmo projeto — `or 0` espalhado por quem chama é como se
-- reproduz isso.
local FIELDS = {
	{ key = "pokemon_v",         kind = "number",  default = Pokemon.SCHEMA_VERSION },
	{ key = "pokemon_species",   kind = "string",  required = true },
	{ key = "pokemon_hp_ratio",  kind = "number",  default = 1.0 },
	{ key = "pokemon_ot",        kind = "number",  required = true, immutable = true },
	{ key = "pokemon_uid",       kind = "number",  required = true, immutable = true },
	{ key = "pokemon_fainted",   kind = "boolean", default = false },
}

local MAX_SAFE_INT = 9007199254740992 -- 2^53: teto medido do custom attribute

local function readField(item, field)
	local raw = item:getCustomAttribute(field.key)
	if raw == nil then
		return field.default
	end
	return raw
end

--- Identidade da captura. Só serve para investigação manual de duplicação:
-- um clone carrega o mesmo uid, então ele diz de onde a coisa veio, não que
-- ela é falsa.
local function newUid()
	-- ~1.7e14, folgado abaixo do teto de 2^53.
	local uid = os.time() * 100000 + math.random(0, 99999)
	assert(uid < MAX_SAFE_INT, "pokemon_uid estourou o teto de 2^53")
	return uid
end

--- Level do jogador que está com o item, ou nil se não houver um.
-- Ball no chão não tem portador — e é caso normal, não erro.
--
-- Sobe pela cadeia de `getParent`, e **não** por `getTopParent`: medido em
-- 2026-07-29, `getTopParent()` numa mochila devolve a própria mochila, não o
-- jogador. Quem atravessa para o Player é `getParent`.
local MAX_DEPTH = 8 -- container dentro de container; oito é folgado

local function holderOf(item)
	local node = item
	for _ = 1, MAX_DEPTH do
		local parent = node.getParent and node:getParent() or nil
		if not parent then
			return nil
		end
		if parent.isPlayer and parent:isPlayer() then
			return parent
		end
		node = parent
	end
	return nil
end

--- Lê o Pokémon de um item.
-- @return tabela com os atributos e, quando há portador, os stats derivados.
--         `nil` se o item não for um Pokémon (ball vazia ou item qualquer).
function Pokemon.read(item)
	if not item then
		return nil
	end
	local speciesName = item:getCustomAttribute("pokemon_species")
	if not speciesName then
		return nil
	end

	local mon = {}
	for _, field in ipairs(FIELDS) do
		mon[field.key] = readField(item, field)
	end

	local species = PokemonSpecies[speciesName]
	if not species then
		-- Espécie saiu do catálogo. Erro visível: silenciar aqui vira "meu
		-- Pokémon virou nada" sem nenhuma pista de quando começou.
		logger.error(string.format(
			"[Pokemon.read] espécie desconhecida '%s' no item uid=%s — catálogo mudou sem migração?",
			tostring(speciesName), tostring(mon.pokemon_uid)))
		return nil
	end

	local out = {
		item = item,
		v = mon.pokemon_v,
		species = speciesName,
		speciesData = species,
		hpRatio = mon.pokemon_hp_ratio,
		ot = mon.pokemon_ot,
		uid = mon.pokemon_uid,
		fainted = mon.pokemon_fainted,
	}

	-- Stats só existem em relação a um treinador. Sem portador — ball no chão,
	-- no depot — devolvemos a fração e mais nada: HP absoluto sem dono é um
	-- número inventado.
	local holder = holderOf(item)
	if holder then
		out.holder = holder
		out.holderLevel = holder:getLevel()
		out.stats = Pokemon.calcStats(species, out.holderLevel)
		out.hp = math.floor(out.stats.hp * out.hpRatio)
	end

	return out
end

--- Cria um Pokémon na bag do jogador.
-- @param destino container opcional. Sem ele, vai para o inventário do
--        jogador. A Fase 5 usa isto para mandar direto à Capture Bag.
-- @return o item, ou nil + motivo
function Pokemon.create(player, speciesName, ballItemId, destino)
	local species = PokemonSpecies[speciesName]
	if not species then
		return nil, "unknown species: " .. tostring(speciesName)
	end

	local id = ballItemId or Pokemon.PLACEHOLDER_BALL_ID

	local item
	if destino then
		item = destino:addItem(id, 1)
	else
		-- canDropOnMap = false: com `true`, bag cheia faz a ball cair no chão,
		-- e ball no chão some no clean. Perder por bag cheia é bug; perder por
		-- ter largado é regra.
		item = player:addItem(id, 1, false)
	end
	if not item or item == false then
		return nil, "no room to carry it"
	end

	local uid = newUid()
	item:setCustomAttribute("pokemon_v", Pokemon.SCHEMA_VERSION)
	item:setCustomAttribute("pokemon_species", speciesName)
	item:setCustomAttribute("pokemon_hp_ratio", 1.0)
	item:setCustomAttribute("pokemon_ot", player:getGuid())
	item:setCustomAttribute("pokemon_uid", uid)
	item:setCustomAttribute("pokemon_fainted", false)

	-- O único rastro de auditoria que esta fase entrega. Sem ele, "tratar
	-- duplicação manualmente" não tem por onde começar: duas instâncias da
	-- mesma espécie são numericamente idênticas.
	logger.info(string.format(
		"[pokemon] criado uid=%.0f species=%s player=%s(%d)",
		uid, speciesName, player:getName(), player:getGuid()))

	return item
end

--- Recolher: grava a fração de vida com que o Pokémon voltou.
function Pokemon.recordReturn(item, hpRatio)
	assert(hpRatio >= 0.0 and hpRatio <= 1.0, "hpRatio fora de 0..1: " .. tostring(hpRatio))
	item:setCustomAttribute("pokemon_hp_ratio", hpRatio)
	return item
end

--- Desmaiar. `fainted` e `hp_ratio = 0` andam juntos, sempre — por isso moram
-- dentro da mesma operação, e não na boa vontade de quem chama.
function Pokemon.recordFaint(item)
	item:setCustomAttribute("pokemon_fainted", true)
	item:setCustomAttribute("pokemon_hp_ratio", 0.0)
	return item
end

--- Cura total.
function Pokemon.revive(item)
	item:setCustomAttribute("pokemon_fainted", false)
	item:setCustomAttribute("pokemon_hp_ratio", 1.0)
	return item
end
