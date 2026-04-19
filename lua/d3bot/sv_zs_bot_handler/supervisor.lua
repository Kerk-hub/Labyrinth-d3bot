local roundStartTime = CurTime()
local NextNemesisRefresh = CurTime()
hook.Add("PreRestartRound", D3bot.BotHooksId.."PreRestartRoundSupervisor", function() roundStartTime, D3bot.NodeZombiesCountAddition = CurTime(), nil end)

function D3bot.ToDenseArray(items)
	local dense = {}
	for _, item in pairs(items or {}) do
		if item ~= nil then
			table.insert(dense, item)
		end
	end
	return dense
end

function D3bot.GetAliveHumanTargets()
	local humans = D3bot.ToDenseArray(D3bot.RemoveObsDeadTgts(team.GetPlayers(TEAM_HUMAN)))
	if TEAM_SURVIVOR then
		for _, survivor in ipairs(D3bot.ToDenseArray(D3bot.RemoveObsDeadTgts(team.GetPlayers(TEAM_SURVIVOR)))) do
			if not table.HasValue(humans, survivor) then
				table.insert(humans, survivor)
			end
		end
	end
	return humans
end

function D3bot.RefreshZombieNemesisAssignments(forceRefresh)
	if not forceRefresh and NextNemesisRefresh > CurTime() then return end
	NextNemesisRefresh = CurTime() + 0.75 + math.random() * 0.25

	local humans = D3bot.GetAliveHumanTargets()
	local humanLookup = {}
	for _, human in ipairs(humans) do
		humanLookup[human] = true
	end

	local zombieBots = {}
	for _, bot in ipairs(D3bot.GetBots()) do
		if IsValid(bot) and bot:Team() == TEAM_UNDEAD and bot:Alive() then
			table.insert(zombieBots, bot)
		end
	end
	table.sort(zombieBots, function(a, b)
		if not IsValid(a) then return false end
		if not IsValid(b) then return true end
		return a:EntIndex() < b:EntIndex()
	end)

	local assignedHumans = {}
	for _, bot in ipairs(zombieBots) do
		local mem = bot.D3bot_Mem
		if mem and (not IsValid(mem.NemesisTarget) or not humanLookup[mem.NemesisTarget]) then
			mem.NemesisTarget = nil
		end
		if mem and IsValid(mem.NemesisTarget) and not assignedHumans[mem.NemesisTarget] then
			assignedHumans[mem.NemesisTarget] = true
		elseif mem then
			mem.NemesisTarget = nil
		end
	end

	for _, human in ipairs(humans) do
		if not assignedHumans[human] then
			local bestBot, bestDist
			for _, bot in ipairs(zombieBots) do
				local mem = bot.D3bot_Mem
				if mem and not IsValid(mem.NemesisTarget) then
					local dist = bot:GetPos():DistToSqr(human:GetPos())
					if not bestDist or dist < bestDist then
						bestBot, bestDist = bot, dist
					end
				end
			end

			if bestBot and bestBot.D3bot_Mem then
				bestBot.D3bot_Mem.NemesisTarget = human
				assignedHumans[human] = true
			end
		end
	end
end

function D3bot.GetZombieNemesis(bot)
	local mem = IsValid(bot) and bot.D3bot_Mem
	local nemesis = mem and mem.NemesisTarget or nil
	if IsValid(nemesis) and nemesis:Alive() and nemesis:GetObserverMode() == OBS_MODE_NONE and not nemesis:IsFlagSet(FL_NOTARGET) and nemesis:Team() ~= TEAM_UNDEAD then
		return nemesis
	end
end

function D3bot.SelectZombieTarget(bot, potTargets, canBeTgt, options)
	if not IsValid(bot) then return end
	options = options or {}
	D3bot.RefreshZombieNemesisAssignments()

	local mem = bot.D3bot_Mem or {}
	local botPos = bot:GetPos()
	local nemesis = D3bot.GetZombieNemesis(bot)
	local bestTarget
	local bestWeightedDistance
	local denseTargets = D3bot.ToDenseArray(potTargets)

	for _, target in ipairs(denseTargets) do
		if canBeTgt(bot, target) then
			local targetPos = target:GetPos()
			local distSqr = botPos:DistToSqr(targetPos)
			if (not options.MaxDistSqr or distSqr <= options.MaxDistSqr) and (not options.VisibleOnly or bot:D3bot_CanSeeTarget(nil, target)) then
				local weight = target:IsPlayer() and 1 or (options.EntityWeight or 0.35)
				if target == nemesis then
					weight = weight * (D3bot.NemesisTargetWeight or 4)
				end

				local weightedDistance = math.max(botPos:Distance(targetPos), 1) / math.max(weight, 0.001)
				if target == mem.TgtOrNil then
					weightedDistance = weightedDistance * 0.85
				end

				if not bestWeightedDistance or weightedDistance < bestWeightedDistance then
					bestTarget, bestWeightedDistance = target, weightedDistance
				end
			end
		end
	end

	return bestTarget, nemesis
end

function D3bot.GetDesiredBotCount()
	local totalHumanCount = #player.GetHumans()
	local livingHumanCount = #D3bot.GetAliveHumanTargets()
	local allowedTotal = game.MaxPlayers() - 2
	local allowedBots = math.max(allowedTotal - totalHumanCount, 0)
	local mapParams = D3bot.MapNavMesh.Params

	-- Default rule: keep zombie bot count equal to the number of living valid humans.
	-- Only the admin botmod offset changes that baseline.
	local zombiesCount = math.Clamp(
		livingHumanCount + (D3bot.ZombiesCountAddition or 0),
		0,
		allowedBots)

	local survivorFormula = (mapParams.SPP or D3bot.SurvivorsPerPlayer) * totalHumanCount
	local survivorsCount = math.Clamp(
		math.ceil(survivorFormula + D3bot.SurvivorCountAddition + (mapParams.SCA or 0)),
		0,
		math.max(allowedBots - zombiesCount, 0))
	return zombiesCount, (GAMEMODE.ZombieEscape or GAMEMODE.ObjectiveMap) and 0 or survivorsCount, allowedTotal
end

local spawnAsTeam
hook.Add("PlayerInitialSpawn", D3bot.BotHooksId, function(pl)
	-- Initialize mem when console bots are used
	if D3bot.UseConsoleBots and D3bot.IsEnabledCached and pl:IsBot() then
		pl:D3bot_InitializeOrReset()
	end

	if spawnAsTeam == TEAM_UNDEAD then
		GAMEMODE.PreviouslyDied[pl:UniqueID()] = CurTime()
		GAMEMODE:PlayerInitialSpawn(pl)
	elseif spawnAsTeam == TEAM_SURVIVOR then
		GAMEMODE.PreviouslyDied[pl:UniqueID()] = nil
		GAMEMODE:PlayerInitialSpawn(pl)
	end
end)

function D3bot.MaintainBotRoles()
	local desiredCountByTeam = {}
	local allowedTotal
	desiredCountByTeam[TEAM_UNDEAD], desiredCountByTeam[TEAM_SURVIVOR], allowedTotal = D3bot.GetDesiredBotCount()
	local bots = player.GetBots()
	local botsByTeam = {}
	for k, v in ipairs(bots) do
		local team = v:Team()
		botsByTeam[team] = botsByTeam[team] or {}
		table.insert(botsByTeam[team], v)
	end
	local players = player.GetAll()
	local playersByTeam = {}
	for k, v in ipairs(players) do
		local team = v:Team()
		playersByTeam[team] = playersByTeam[team] or {}
		table.insert(playersByTeam[team], v)
	end

	-- Check if any zombie bot is in barricade ghosting mode.
	-- This can happen in some gamemodes, we fix that here.
	-- See https://github.com/Dadido3/D3bot/issues/99 for details.
	for _, bot in ipairs(bots) do
		if bot:GetBarricadeGhosting() and bot:Team() == TEAM_UNDEAD and bot:Alive() then
			--bot:Say(string.format("I was a nasty bot that noclips through barricades! (%s)", bot))
			bot:SetBarricadeGhosting(false)
		end
	end

	-- TODO: Fix invisible bots when CLASS.OverrideModel is used (most common with Frigid Revenant and other OverrideModel zombies in 2018 ZS if they have a low opacity OverrideModel)
	
	-- Sort by frags and being boss zombie
	if botsByTeam[TEAM_UNDEAD] then
		table.sort(botsByTeam[TEAM_UNDEAD], function(a, b) return (a:GetZombieClassTable().Boss and 1 or 0) > (b:GetZombieClassTable().Boss and 1 or 0) end)
	end
	for team, botByTeam in pairs(botsByTeam) do
		table.sort(botByTeam, function(a, b) return a:Frags() < b:Frags() end)
	end
	
	-- Stop managing survivor bots, after round started. Except on ZE or obj maps, where survivors are managed to be 0
	if GAMEMODE:GetWave() > 0 and not GAMEMODE.ZombieEscape and not GAMEMODE.ObjectiveMap then
		desiredCountByTeam[TEAM_SURVIVOR] = nil
	end
	
	-- Manage survivor bot count to 0, if they are disabled
	if not D3bot.SurvivorsEnabled then
		desiredCountByTeam[TEAM_SURVIVOR] = 0
	end
	
	-- Move (kill) survivors to undead if possible
	if desiredCountByTeam[TEAM_SURVIVOR] and desiredCountByTeam[TEAM_UNDEAD] then
		if #(botsByTeam[TEAM_SURVIVOR] or {}) > desiredCountByTeam[TEAM_SURVIVOR] and #(botsByTeam[TEAM_UNDEAD] or {}) < desiredCountByTeam[TEAM_UNDEAD] and botsByTeam[TEAM_SURVIVOR] then
			local randomBot = table.remove(botsByTeam[TEAM_SURVIVOR], 1)
			randomBot:StripWeapons()
			--randomBot:KillSilent()
			randomBot:Kill()
			return
		end
	end
	-- Add bots out of managed teams to maintain desired counts
	if player.GetCount() < allowedTotal then
		for team, desiredCount in pairs(desiredCountByTeam) do
			if #(botsByTeam[team] or {}) < desiredCount then
				if D3bot.UseConsoleBots then
					spawnAsTeam = team
					RunConsoleCommand("bot")
					spawnAsTeam = nil
				else
					spawnAsTeam = team
					---@type GPlayer|table
					local bot = player.CreateNextBot(D3bot.GetUsername())
					spawnAsTeam = nil
					if IsValid(bot) then
						bot:D3bot_InitializeOrReset()
					end
				end
				return
			end
		end
	end
	-- Remove bots out of managed teams to maintain desired counts
	for team, desiredCount in pairs(desiredCountByTeam) do
		if #(botsByTeam[team] or {}) > desiredCount and botsByTeam[team] then
			local randomBot = table.remove(botsByTeam[team], 1)
			randomBot:StripWeapons()
			return randomBot and randomBot:Kick(D3bot.BotKickReason)
		end
	end
	-- Remove bots out of non managed teams if the server is getting too full
	if player.GetCount() > allowedTotal then
		for team, desiredCount in pairs(desiredCountByTeam) do
			if not desiredCountByTeam[team] and botsByTeam[team] then
				local randomBot = table.remove(botsByTeam[team], 1)
				randomBot:StripWeapons()
				return randomBot and randomBot:Kick(D3bot.BotKickReason)
			end
		end
	end
end

local NextNodeDamage = CurTime()
local NextMaintainBotRoles = CurTime()

function D3bot.QueueBotRoleRefresh()
	NextMaintainBotRoles = 0
	NextNemesisRefresh = 0
end

hook.Add("PlayerInitialSpawn", D3bot.BotHooksId.."PlayerInitialSpawnSupervisorRefresh", function(pl)
	if D3bot.IsEnabledCached and not pl.D3bot_Mem then
		D3bot.QueueBotRoleRefresh()
	end
end)

hook.Add("PlayerSpawn", D3bot.BotHooksId.."PlayerSpawnSupervisorRefresh", function(pl)
	if D3bot.IsEnabledCached and not pl.D3bot_Mem then
		D3bot.QueueBotRoleRefresh()
	end
end)

hook.Add("PlayerDeath", D3bot.BotHooksId.."PlayerDeathSupervisorRefresh", function(pl)
	if D3bot.IsEnabledCached and not pl.D3bot_Mem then
		D3bot.QueueBotRoleRefresh()
	end
end)

hook.Add("PlayerDisconnected", D3bot.BotHooksId.."PlayerDisconnectedSupervisorRefresh", function()
	if D3bot.IsEnabledCached then
		D3bot.QueueBotRoleRefresh()
	end
end)

function D3bot.SupervisorThinkFunction()
	if NextMaintainBotRoles < CurTime() then
		NextMaintainBotRoles = CurTime() + (D3bot.BotUpdateDelay or 1)
		D3bot.MaintainBotRoles()
		D3bot.RefreshZombieNemesisAssignments()
	end
	if (NextNodeDamage or 0) < CurTime() then
		NextNodeDamage = CurTime() + (D3bot.NodeDamageInterval or 2)
		D3bot.DoNodeTrigger()
	end
end

function D3bot.DoNodeTrigger()
	local players = D3bot.RemoveObsDeadTgts(player.GetAll())
	players = D3bot.From(players):Where(function(k, v) return v:Team() ~= TEAM_UNDEAD end).R
	local ents = table.Add(players, D3bot.GetEntsOfClss(D3bot.NodeDamageEnts))
	for i, ent in pairs(ents) do
		local nodeOrNil = D3bot.MapNavMesh:GetNearestNodeOrNil(ent:GetPos()) -- TODO: Don't call GetNearestNodeOrNil that often
		if nodeOrNil then
			if not D3bot.DisableNodeDamage and type(nodeOrNil.Params.DMGPerSecond) == "number" and nodeOrNil.Params.DMGPerSecond > 0 then
				ent:TakeDamage(nodeOrNil.Params.DMGPerSecond * (D3bot.NodeDamageInterval or 2), game.GetWorld(), game.GetWorld())
			end
			if ent:IsPlayer() and not ent.D3bot_Mem and nodeOrNil.Params.BotMod then
				D3bot.NodeZombiesCountAddition = nodeOrNil.Params.BotMod
			end
		end
	end
end

-- TODO: Detect situations and coordinate bots accordingly (Attacking cades, hunt down runners, spawncamping prevention)
-- TODO: If needed force one bot to flesh creeper and let him build a nest at a good place
