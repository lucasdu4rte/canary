-- Registers one MonsterType per catalogue species, at boot.
--
-- Without this, `Game.createMonster("Bulbasaur", pos)` fails: the otservbr
-- datapack only ships Tibia monsters. Generating from here rather than
-- committing 154 files is the same choice as `catalog.lua` -- the species list
-- has exactly one owner, and it is phase 2.
--
-- NOTE: **Combat numbers here are placeholders.** Damage is governed by
-- `Pokemon.calcStats` on the item side, and phase 4 is what will wire the two
-- together. What this task needs from a monster is to exist, carry the right
-- name and follow its owner.
--
-- The `lookType` is a placeholder too: the real Roxy outfits are only valid
-- once converted to the 15.x format (art track).

local PLACEHOLDER_LOOKTYPE = 226 -- azure frog; goes away when the art lands

local registrar = GlobalEvent("Pokemon MonsterTypes")

function registrar.onStartup()
	local total, failed = 0, 0

	for name, species in pairs(PokemonSpecies) do
		-- Variant "pokemon": registers under the key "pokemon|<name>" and
		-- keeps the display name clean. Without it, any species sharing a name
		-- with a Tibia monster brings the registration down -- today that is
		-- only Haunter, but the datapack carries 1,655 monsters and upstream
		-- keeps adding.
		local mType = Game.createMonsterType(name, Pokemon.MONSTER_VARIANT)
		if not mType then
			failed = failed + 1
		else
			local m = {}
			m.description = "a " .. name:lower()
			m.experience = 0
			m.outfit = { lookType = PLACEHOLDER_LOOKTYPE, lookAddons = 0, lookMount = 0 }

			-- HP here is only the design ceiling; the real per-owner value
			-- comes from Pokemon.calcStats at the moment of the summon.
			local base = species.baseStats
			m.health = base.hp
			m.maxHealth = base.hp
			m.race = "blood"
			m.corpse = 0
			m.speed = 100
			m.manaCost = 0

			m.changeTarget = { interval = 4000, chance = 0 }
			m.strategiesTarget = { nearest = 100 }

			m.flags = {
				summonable = false, -- only our own code sends these out
				attackable = true,
				hostile = false, -- does not attack players on its own
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

			-- Death has to reach the ball. Declared on the type so every
			-- instance carries it, whatever created the creature.
			m.events = { "PokemonFaint" }

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

	logger.info(string.format("[pokemon] %d MonsterTypes registered%s",
		total, failed > 0 and (" (" .. failed .. " failed)") or ""))
	return true
end

registrar:register()
