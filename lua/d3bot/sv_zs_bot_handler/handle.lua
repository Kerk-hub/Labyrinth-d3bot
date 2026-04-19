D3bot.Handlers = {}

-- TODO: Make search path relative
for i, filename in pairs(file.Find("d3bot/sv_zs_bot_handler/handlers/*.lua", "LUA")) do
	include("handlers/"..filename)
end

local handlerLookup = {}

function findHandler(zombieClass, team)
	if handlerLookup[team] and handlerLookup[team][zombieClass] then -- TODO: Put cached handler into bot object
		return handlerLookup[team][zombieClass]
	end
	
	for _, fallback in ipairs({false, true}) do
		for _, handler in pairs(D3bot.Handlers) do
			if handler.Fallback == fallback and handler.SelectorFunction(GAMEMODE.ZombieClasses[zombieClass].Name, team) then
				handlerLookup[team] = {}
				handlerLookup[team][zombieClass] = handler
				return handler
			end
		end
	end
end
local findHandler = findHandler

hook.Add("StartCommand", D3bot.BotHooksId .. "StartCommand", function(pl, cmd)
	if D3bot.IsEnabledCached and pl.D3bot_Mem then
		
		local handler = findHandler(pl:GetZombieClass(), pl:Team())
		if handler then
			handler.UpdateBotCmdFunction(pl, cmd)
		end
	end
end)

D3bot.Generation = 1
D3bot.GenerationTargets = {}

local NextSupervisorThink = CurTime()
local NextStorePos = CurTime()
local NextSpawnInterval = 0
hook.Add("Think", D3bot.BotHooksId .. "Think", function()
	if not D3bot.IsEnabledCached then return end
	
	local time = CurTime()

	-- General bot handler think function
	if NextSpawnInterval < time then
		NextSpawnInterval = time + 1 + math.random(0, 1)

		local generation = D3bot.Generation

		for _, bot in ipairs(D3bot.GetBots()) do
			if not bot:OldAlive() then
				bot.BotGeneration = generation

				if not D3bot.UseConsoleBots then
				-- Hackish method to get bots back into game. (player.CreateNextBot created bots do not trigger the StartCommand hook while they are dead)
					gamemode.Call("PlayerDeathThink", bot)
					if (not bot.StartSpectating or bot.StartSpectating <= time) and not (GAMEMODE.RoundEnded or bot.Revive or bot.NextSpawnTime) and bot:GetObserverMode() ~= OBS_MODE_NONE then
						if GAMEMODE:GetWaveActive() then
							bot:RefreshDynamicSpawnPoint()
							bot:UnSpectateAndSpawn()
						else
							bot:ChangeToCrow()
						end
					end
				end
			end
			
			local handler = findHandler(bot:GetZombieClass(), bot:Team())
			if handler then
				handler.ThinkFunction(bot)
			end
		end

		generation = generation + 1
		
		D3bot.GenerationTargets[generation] = NULL
		D3bot.Generation = generation
	end
	
	-- Supervisor think function
	if NextSupervisorThink < time then
		NextSupervisorThink = time + 0.05 + math.random() * 0.1
		D3bot.SupervisorThinkFunction()
	end
	
	-- Store history of all players (For behaviour classification, stuck checking)
	if NextStorePos < time then
		NextStorePos = time + 0.9 + math.random() * 0.2
		for _, ply in ipairs(player.GetAll()) do
			ply:D3bot_StorePos()
		end
	end
end)

hook.Add("EntityTakeDamage", D3bot.BotHooksId .. "TakeDamage", function(ent, dmg)
	if D3bot.IsEnabledCached then
		if ent:IsPlayer() and ent.D3bot_Mem then
			-- Bot got damaged or damaged itself
			local handler = findHandler(ent:GetZombieClass(), ent:Team())
			if handler then
				handler.OnTakeDamageFunction(ent, dmg)
			end
		end
		local attacker = dmg:GetAttacker()
		if attacker ~= ent and attacker:IsPlayer() and attacker.D3bot_Mem then
			-- A Bot did damage something
			-- local handler = findHandler(attacker:GetZombieClass(), attacker:Team())
			-- if handler then
				-- handler.OnDoDamageFunction(attacker, dmg)
				attacker.D3bot_LastDamage = CurTime()
			-- end
		end
	end
end)

hook.Add("PlayerSpawn", D3bot.BotHooksId .. "PlayerSpawn", function(pl)
	if D3bot.IsEnabledCached and pl.D3bot_Mem and GAMEMODE:GetWaveActive() then
		local handler = findHandler(pl:GetZombieClass(), pl:Team())
		if handler then
			handler.OnRespawnFunction(pl)
		end
	end
end)

hook.Add("PlayerDeath", D3bot.BotHooksId .. "PlayerDeath", function(pl)
	if D3bot.IsEnabledCached and pl.D3bot_Mem then
		local handler = findHandler(pl:GetZombieClass(), pl:Team())
		if handler then
			handler.OnDeathFunction(pl)
		end
		-- Add death cost to the current link
		--[[local mem = pl.D3bot_Mem
		local nodeOrNil = mem.NodeOrNil
		local nextNodeOrNil = mem.NextNodeOrNil
		if nodeOrNil and nextNodeOrNil then
			local link
			if D3bot.UsingSourceNav then
				link = nodeOrNil:SharesLink( nextNodeOrNil )
			else
				link = nodeOrNil.LinkByLinkedNode[nextNodeOrNil]
			end
			if link then D3bot.LinkMetadata_ZombieDeath(link, D3bot.LinkDeathCostRaise) end
		end]]
	end
end)