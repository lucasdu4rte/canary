-- Registra um MonsterType por espécie do catálogo, no boot.
--
-- Sem isto, `Game.createMonster("Bulbasaur", pos)` falha: o datapack do
-- otservbr só traz monstro de Tibia. Gerar daqui em vez de commitar 154
-- arquivos é a mesma escolha do `catalog.lua` — a lista de espécies tem um
-- dono só, e é a Fase 2.
--
-- ⚠️ **Estatísticas de combate aqui são placeholder.** Quem manda no dano é
-- `Pokemon.calcStats`, do lado do item, e a Fase 4 é que vai ligar os dois.
-- O que esta task precisa do monstro é existir, ter nome e seguir o dono.
--
-- O `lookType` também é placeholder: os outfits reais da Roxy só valem depois
-- da conversão para o formato 15.x (trilha de arte).

local PLACEHOLDER_LOOKTYPE = 226 -- azure frog; some quando a arte entrar

local registrar = GlobalEvent("Pokemon MonsterTypes")

function registrar.onStartup()
	local total, falhas = 0, 0

	for nome, especie in pairs(PokemonSpecies) do
		-- Variant "pokemon": registra sob a chave "pokemon|<nome>" e mantém o
		-- nome de exibição limpo. Sem isto, qualquer espécie homônima de um
		-- monstro do Tibia derruba o registro — hoje é só Haunter, mas são
		-- 1.655 monstros no datapack e o upstream adiciona mais.
		local mType = Game.createMonsterType(nome, Pokemon.MONSTER_VARIANT)
		if not mType then
			falhas = falhas + 1
		else
			local m = {}
			m.description = "a " .. nome:lower()
			m.experience = 0
			m.outfit = { lookType = PLACEHOLDER_LOOKTYPE, lookAddons = 0, lookMount = 0 }

			-- HP aqui é só o teto do desenho; o valor real por dono vem de
			-- Pokemon.calcStats no momento do summon.
			local base = especie.baseStats
			m.health = base.hp
			m.maxHealth = base.hp
			m.race = "blood"
			m.corpse = 0
			m.speed = 100
			m.manaCost = 0

			m.changeTarget = { interval = 4000, chance = 0 }
			m.strategiesTarget = { nearest = 100 }

			m.flags = {
				summonable = false, -- só o nosso código summona
				attackable = true,
				hostile = false, -- não ataca jogador por conta própria
				convinceable = false,
				pushable = false,
				rewardBoss = false,
				illusionable = false,
				canPushItems = false,
				canPushCreatures = false,
				staticAttackChance = 90,
				targetDistance = 1,
				healthHidden = false,
				canWalkOnEnergy = true,
				canWalkOnFire = true,
				canWalkOnPoison = true,
			}

			m.voices = { interval = 5000, chance = 0 }
			m.loot = {}
			m.attacks = {}
			m.defenses = { defense = 0, armor = 0, mitigation = 0 }
			m.elements = {}
			m.immunities = {}

			mType:register(m)
			total = total + 1
		end
	end

	logger.info(string.format("[pokemon] %d MonsterTypes registrados%s",
		total, falhas > 0 and (" (" .. falhas .. " falharam)") or ""))
	return true
end

registrar:register()
