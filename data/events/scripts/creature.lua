function Creature:onTargetCombat(target)
	if not self then
		return true
	end

	if (target:isMonster() and self:isPlayer() and target:getMaster() == self) or (self:isMonster() and target:isPlayer() and self:getMaster() == target) then
		return RETURNVALUE_YOUMAYNOTATTACKTHISCREATURE
	end

	-- Proteção do treinador: enquanto ele tem Pokémon em campo, a briga é do
	-- Pokémon. É a mesma forma da regra acima, virada do outro lado — lá o
	-- dono não ataca o próprio summon; aqui ninguém ataca o dono.
	--
	-- Fica no legado (`Creature:onTargetCombat`) e não no EventCallback novo
	-- porque só o legado lê o retorno como número: dá para devolver o motivo
	-- exato, e o jogador vê "you may not attack this creature" em vez de um
	-- "sorry, not possible" genérico.
	if target:isPlayer() and Pokemon and Pokemon.hasActive and Pokemon.hasActive(target) then
		-- O próprio Pokémon dele não é barrado por isto: um summon atacando o
		-- dono já caiu na regra acima.
		if self ~= target then
			return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
		end
	end

	if not IsRetroPVP() or PARTY_PROTECTION ~= 0 then
		if self:isPlayer() and target:isPlayer() then
			local party = self:getParty()
			if party then
				local targetParty = target:getParty()
				if targetParty and targetParty == party then
					return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
				end
			end
		end
	end

	if not IsRetroPVP() or ADVANCED_SECURE_MODE ~= 0 then
		if self:isPlayer() and target:isPlayer() then
			if self:hasSecureMode() then
				return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
			end
		end
	end

	self:addEventStamina(target)
	return true
end

function Creature:onChangeOutfit(outfit)
	if self:isPlayer() then
		local familiarLookType = self:getFamiliarLooktype()
		if familiarLookType ~= 0 then
			for _, summon in pairs(self:getSummons()) do
				if summon:getType():familiar() then
					if summon:getOutfit().lookType ~= familiarLookType then
						summon:setOutfit({ lookType = familiarLookType })
					end
					break
				end
			end
		end
	end
	return true
end

function Creature:onDrainHealth(attacker, typePrimary, damagePrimary, typeSecondary, damageSecondary, colorPrimary, colorSecondary)
	if not self then
		return typePrimary, damagePrimary, typeSecondary, damageSecondary, colorPrimary, colorSecondary
	end

	if not attacker then
		return typePrimary, damagePrimary, typeSecondary, damageSecondary, colorPrimary, colorSecondary
	end

	return typePrimary, damagePrimary, typeSecondary, damageSecondary, colorPrimary, colorSecondary
end
