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

-- Walking speed, from the species' own `speed`.
--
-- It is a trait of the pokemon, not of its trainer: a Scyther is meant to
-- outrun a Slowpoke, and a pokemon too slow to keep up is supposed to fall
-- behind -- which is what `PokemonFollowTrainer` exists to catch.
--
-- The catalogue's speed runs 15 to 150 across our 154, median 68. Tibia's own
-- monsters sit around 75 to 200, with familiars at 154, so a flat offset lands
-- the whole roster inside that band while keeping the order intact: the
-- slowest walks like a slow monster, the fastest like a quick one.
--
-- NOTE: **not** level-scaled, unlike `Pokemon.calcStats().speed`. That one is
-- the battle stat and decides who strikes first; a trainer levelling up should
-- not make their Slowpoke walk faster.
local SPEED_FLOOR = 60

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
			m.speed = SPEED_FLOOR + base.speed
			m.manaCost = 0

			m.changeTarget = { interval = 4000, chance = 0 }
			m.strategiesTarget = { nearest = 100 }

			m.flags = {
				-- Tibia's "familiar" is much closer to a pokemon than its
				-- generic summon is, and the engine hands over five behaviours
				-- at once (`tile.cpp:664`, `creature.cpp:472-490`, `:1015`,
				-- `player.cpp:1419`, `:1463`, `game.cpp:4898`):
				--
				--   * it may walk into a protection zone -- but only while its
				--     trainer is not attacking anything, so it can follow you
				--     into a depot and cannot camp there mid-fight
				--   * it cannot start attacking while standing in one
				--   * more than 15 tiles away or a floor apart it **teleports
				--     to its trainer** instead of being despawned at 30, which
				--     is what a plain summon does. A pokemon should not vanish
				--     for falling behind
				--   * players walk through it, so it never body-blocks
				--   * its trainer can use runes and potions on it
				--
				-- ⚠️ One thing it also enables: `Creature:onChangeOutfit` in
				-- `data/events/scripts/creature.lua` overwrites a familiar's
				-- outfit with `player:getFamiliarLooktype()` when that is not
				-- zero. It is zero for everyone here because we do not use
				-- Tibia's familiar system -- but if that ever changes, it would
				-- silently repaint every pokemon.
				familiar = true,
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

			-- Declared on the type so every instance carries them, whatever
			-- created the creature: death has to reach the ball, and a pokemon
			-- must not wander off screen.
			m.events = {
				"PokemonFaint",
				"PokemonFollowTrainer",
				"PokemonWildStats",
				"PokemonAutoAttack",
				"PokemonDamageRules",
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

	logger.info(string.format("[pokemon] %d MonsterTypes registered%s",
		total, failed > 0 and (" (" .. failed .. " failed)") or ""))
	return true
end

registrar:register()
