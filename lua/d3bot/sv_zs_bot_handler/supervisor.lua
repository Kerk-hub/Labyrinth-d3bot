local roundStartTime = CurTime()
local NextNemesisRefresh = CurTime()
local spawnAsZombieMain = false
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

function D3bot.IsZombieMainBot(bot)
	return IsValid(bot) and bot:IsBot() and bot.D3bot_Mem and bot.D3bot_Mem.IsZombieMain == true
end

local function kickBotIfBot(bot)
	if IsValid(bot) and bot:IsBot() then
		bot:StripWeapons()
		return bot:Kick(D3bot.BotKickReason)
	end
end

function D3bot.GetZombieMainBot()
	for _, bot in ipairs(D3bot.GetBots()) do
		if D3bot.IsZombieMainBot(bot) then
			return bot
		end
	end
end

function D3bot.GetZombieMainBotOnZombieTeam()
	for _, bot in ipairs(D3bot.GetBots()) do
		if D3bot.IsZombieMainBot(bot) and bot:Team() == TEAM_UNDEAD then
			return bot
		end
	end
end

function D3bot.GetZombieTeamPlayers()
	local zombiePlayers = {}
	for _, pl in ipairs(player.GetAll()) do
		if IsValid(pl) and not pl.D3bot_Mem and pl:Team() == TEAM_UNDEAD then
			table.insert(zombiePlayers, pl)
		end
	end
	return zombiePlayers
end

function D3bot.HasZombieVolunteerPlayer()
	local initialVolunteers = GAMEMODE and GAMEMODE.InitialVolunteers
	if type(initialVolunteers) ~= "table" then return false end

	for _, pl in ipairs(player.GetAll()) do
		if IsValid(pl) and not pl.D3bot_Mem and pl:Team() == TEAM_UNDEAD and initialVolunteers[pl:UniqueID()] then
			return true
		end
	end

	return false
end

function D3bot.SelectLegacyZombieTarget(bot, potTargets, canBeTgt, options)
	options = options or {}
	local validTargets = {}
	local botPos = bot:GetPos()

	for _, target in ipairs(D3bot.ToDenseArray(potTargets)) do
		if canBeTgt(bot, target) then
			local distSqr = botPos:DistToSqr(target:GetPos())
			if (not options.MaxDistSqr or distSqr <= options.MaxDistSqr) and (not options.VisibleOnly or bot:D3bot_CanSeeTarget(nil, target)) then
				table.insert(validTargets, {Target = target, DistSqr = distSqr})
			end
		end
	end

	if #validTargets == 0 then return end
	if options.VisibleOnly then
		table.sort(validTargets, function(a, b) return a.DistSqr < b.DistSqr end)
		return validTargets[1].Target
	end

	return validTargets[math.random(#validTargets)].Target
end

function D3bot.RefreshZombieNemesisAssignments(forceRefresh)
	if not forceRefresh and NextNemesisRefresh > CurTime() then return end
	NextNemesisRefresh = CurTime() + 0.75 + math.random() * 0.25

	local humans = D3bot.GetAliveHumanTargets()
	local humanLookup = {}
	for _, human in ipairs(humans) do
		humanLookup[human] = true
	end

	for _, bot in ipairs(D3bot.GetBots()) do
		if D3bot.IsZombieMainBot(bot) and bot.D3bot_Mem then
			bot.D3bot_Mem.NemesisTarget = nil
		end
	end

	local zombieBots = {}
	for _, bot in ipairs(D3bot.GetBots()) do
		if IsValid(bot) and bot:Team() == TEAM_UNDEAD and bot:Alive() and not D3bot.IsZombieMainBot(bot) then
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

			if bestBot and bestBot.D3bot_Mem and not D3bot.IsZombieMainBot(bestBot) then
				bestBot.D3bot_Mem.NemesisTarget = human
				assignedHumans[human] = true
			end
		end
	end
end

function D3bot.GetZombieNemesis(bot)
	if D3bot.IsZombieMainBot(bot) then return end
	local mem = IsValid(bot) and bot.D3bot_Mem
	local nemesis = mem and mem.NemesisTarget or nil
	if IsValid(nemesis) and nemesis:Alive() and nemesis:GetObserverMode() == OBS_MODE_NONE and not nemesis:IsFlagSet(FL_NOTARGET) and nemesis:Team() ~= TEAM_UNDEAD then
		return nemesis
	end
end

function D3bot.SelectZombieTarget(bot, potTargets, canBeTgt, options)
	if not IsValid(bot) then return end
	options = options or {}
	if D3bot.IsZombieMainBot(bot) then
		return D3bot.SelectLegacyZombieTarget(bot, potTargets, canBeTgt, options), nil
	end
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

function D3bot.TrySetNemesisSpawn(bot)
	local success, result = pcall(function()
		if not IsValid(bot) or D3bot.IsZombieMainBot(bot) then return false end

		local nemesis = D3bot.GetZombieNemesis(bot)
		if not IsValid(nemesis) then return false end

		local nemesisPos = nemesis:GetPos()
		local candidateSpawns = {}

		for _, spawnEnt in ipairs(team.GetValidSpawnPoint(TEAM_UNDEAD) or {}) do
			if IsValid(spawnEnt) and spawnEnt:GetClass() == "zombiegasses" then
				table.insert(candidateSpawns, spawnEnt)
			end
		end

		if GAMEMODE.GetDynamicSpawns then
			for _, spawnEnt in ipairs(GAMEMODE:GetDynamicSpawns(bot) or {}) do
				if IsValid(spawnEnt) and spawnEnt:GetClass() == "prop_creepernest" then
					table.insert(candidateSpawns, spawnEnt)
				end
			end
		end

		local bestSpawn, bestDist
		for _, spawnEnt in ipairs(candidateSpawns) do
			local dist = spawnEnt:GetPos():DistToSqr(nemesisPos)
			if not bestDist or dist < bestDist then
				bestSpawn, bestDist = spawnEnt, dist
			end
		end

		if not IsValid(bestSpawn) then return false end

		bot.ForceDynamicSpawn = bestSpawn
		bot.ForceSpawnAngles = bestSpawn.GetAngles and bestSpawn:GetAngles() or bot:EyeAngles()
		return true
	end)

	if success and result then
		return true
	end

	if IsValid(bot) then
		bot.ForceDynamicSpawn = nil
		bot.ForceSpawnAngles = nil
	end

	return false
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
local function spawnManagedBot(team, forcedName, isZombieMain)
	if isZombieMain and team == TEAM_UNDEAD and IsValid(D3bot.GetZombieMainBotOnZombieTeam()) then
		return false
	end

	spawnAsTeam = team
	spawnAsZombieMain = isZombieMain == true
	if D3bot.UseConsoleBots then
		RunConsoleCommand("bot")
	else
		---@type GPlayer|table
		local bot = player.CreateNextBot(D3bot.GetUsername(forcedName))
		if IsValid(bot) then
			bot:D3bot_InitializeOrReset()
			bot.D3bot_Mem.IsZombieMain = spawnAsZombieMain
		end
	end
	spawnAsTeam = nil
	spawnAsZombieMain = false
	return true
end

hook.Add("PlayerInitialSpawn", D3bot.BotHooksId, function(pl)
	-- Initialize mem when console bots are used
	if D3bot.UseConsoleBots and D3bot.IsEnabledCached and pl:IsBot() then
		pl:D3bot_InitializeOrReset()
		pl.D3bot_Mem.IsZombieMain = spawnAsZombieMain
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
	local zombieMainBot = D3bot.GetZombieMainBot()
	local zombieMainCount = IsValid(zombieMainBot) and 1 or 0
	local hasZombieVolunteerPlayer = D3bot.HasZombieVolunteerPlayer()
	local effectivePlayerCount = player.GetCount() - zombieMainCount
	for k, v in ipairs(bots) do
		if D3bot.IsZombieMainBot(v) then continue end
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

	if IsValid(zombieMainBot) and (hasZombieVolunteerPlayer or #player.GetHumans() == 0) then
		return kickBotIfBot(zombieMainBot)
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
	if effectivePlayerCount < allowedTotal then
		for team, desiredCount in pairs(desiredCountByTeam) do
			if #(botsByTeam[team] or {}) < desiredCount then
				spawnManagedBot(team)
				return
			end
		end
	end

	if not hasZombieVolunteerPlayer and not IsValid(zombieMainBot) and #player.GetHumans() > 0 and effectivePlayerCount < game.MaxPlayers() then
		spawnManagedBot(TEAM_UNDEAD, D3bot.ZombieMainBotName, true)
		return
	end

	-- Remove bots out of managed teams to maintain desired counts
	for team, desiredCount in pairs(desiredCountByTeam) do
		if #(botsByTeam[team] or {}) > desiredCount and botsByTeam[team] then
			local randomBot = table.remove(botsByTeam[team], 1)
			return kickBotIfBot(randomBot)
		end
	end
	-- Remove bots out of non managed teams if the server is getting too full
	if effectivePlayerCount > allowedTotal then
		for team, desiredCount in pairs(desiredCountByTeam) do
			if not desiredCountByTeam[team] and botsByTeam[team] then
				local randomBot = table.remove(botsByTeam[team], 1)
				return kickBotIfBot(randomBot)
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
