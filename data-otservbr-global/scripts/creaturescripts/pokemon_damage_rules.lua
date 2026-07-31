-- Who is allowed to hurt a pokemon.
--
-- The trainer is not. Reported from play: a wild was taking ~110 a hit from
-- something that was not its opponent, and it was the player's own weapon --
-- targeting a creature makes a Tibia character swing at it. A level 500 knight
-- was out-damaging the Charizard it had sent out, which turns the pokemon into
-- decoration.
--
-- ⚠️ NOT `onTargetCombat`, even though the phase 3 trainer protection lives
-- there. That hook gates target SELECTION, and selecting a target is exactly
-- how a trainer says who their pokemon should fight -- refusing there would
-- take the order interface down with it. The phase 4 spec calls this out in
-- advance: the net is a damage hook, not a second targeting rule, which is also
-- where Roxy puts it.
--
-- Registered on the generated MonsterTypes, so it only ever sees pokemon. A
-- trainer swinging at a Tibia monster is untouched.

local damageRules = CreatureEvent("PokemonDamageRules")

function damageRules.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	-- Healing passes: the familiar flag lets a trainer use runes and potions on
	-- their pokemon, and that is a feature rather than an oversight.
	if primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end

	-- A pokemon attacking is the normal case, and reaches here as the pokemon
	-- rather than as its owner -- the log reads "an attack by a charizard".
	if attacker and attacker:isPlayer() then
		return 0, primaryType, 0, secondaryType
	end

	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

damageRules:register()
