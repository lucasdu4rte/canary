-- Stats de combate, derivados na hora de espécie + level do dono.
--
-- Nada aqui é persistido. É decisão de desenho, não economia: stat gravado
-- envelhece quando a fórmula muda, e um ajuste de balance deixaria todos os
-- Pokémon existentes com números velhos e nenhum aviso.

Pokemon = Pokemon or {}

-- "Porcentagem do level do player" — a constante mais sensível do jogo.
-- Mexer aqui move o poder de todo Pokémon do servidor de uma vez.
local LEVEL_SCALE = 1.0

local SCALED_STATS = { "atk", "def", "spatk", "spdef", "speed" }

local function effectiveLevel(playerLevel)
	return math.floor(playerLevel * LEVEL_SCALE)
end

--- Stats de um Pokémon na mão de um treinador daquele level.
-- @param species tabela do PokemonSpecies (não o nome)
-- @param playerLevel level do dono atual
-- @return { hp, atk, def, spatk, spdef, speed }
function Pokemon.calcStats(species, playerLevel)
	local lvl = effectiveLevel(playerLevel)
	local base = species.baseStats

	-- HP tem fórmula própria: em geração nenhuma ele recebeu o modificador
	-- que os outros cinco recebiam.
	local out = { hp = math.floor(2 * base.hp * lvl / 100) + lvl + 10 }

	for _, stat in ipairs(SCALED_STATS) do
		out[stat] = math.floor(2 * base[stat] * lvl / 100) + 5
	end

	return out
end

--- Exposto para quem precisa registrar com que escala um teste rodou.
function Pokemon.levelScale()
	return LEVEL_SCALE
end
