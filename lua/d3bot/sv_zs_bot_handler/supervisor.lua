local roundStartTime = CurTime()
hook.Add("PreRestartRound", D3bot.BotHooksId.."PreRestartRoundSupervisor", function()
	roundStartTime, D3bot.NodeZombiesCountAddition = CurTime(), nil 
	D3bot.ZombiesCountAddition = 0
	GAMEMODE.ShouldPopBlock = false
end)

local player_GetHumansActiveCount
local team_equalizer
hook.Add("Initialize", "D3Bot.LocalizeSomeVariables.Supervisor", function()
	if not GAMEMODE then
		GAMEMODE = GM or _G.GAMEMODE
	end

	team_equalizer = GAMEMODE.TeamRatiosByWave
	player_GetHumansActiveCount = player.GetHumansActiveCount

	--prevent errors when testing without fwkzt version of the gamemode.
	if not GAMEMODE.ZombiePlayers then
		GAMEMODE.ZombiePlayers = team.GetPlayers(TEAM_UNDEAD)
	end
	if not GAMEMODE.HumanPlayers then
		GAMEMODE.HumanPlayers = team.GetPlayers(TEAM_HUMAN)
	end
end)

local player_GetAll = player.GetAll
local player_GetCount = player.GetCount
local player_GetHumans = player.GetHumans
local game_MaxPlayers = game.MaxPlayers
local math_Clamp = math.Clamp
local math_max = math.max
local math_min = math.min
local math_ceil = math.ceil
local table_insert = table.insert
local table_sort = table.sort

local M_Entity = FindMetaTable("Entity")
local E_IsValid = M_Entity.IsValid

local M_Player = FindMetaTable("Player")
local P_Team = M_Player.Team
local P_IsBot = M_Player.IsBot

local forced_player_zombies = 0

local count_target = 0
local bots_to_keep = 0

local humans_dead = 0
local max_humans_dead = 0
local curwave = 0
local bot_per_wave = 0

local finalized_starting_zombies
local onethird_of_starting_zombies

local function EvaluateOverstackCount(numofhumans, numofzombies)
	local target_team_ratio = math_ceil(numofhumans * (team_equalizer[curwave] or 0.20))
	local overstackcount = 0
	if numofzombies > target_team_ratio and not GAMEMODE.ObjectiveMap then
		overstackcount = numofzombies - target_team_ratio
	end
	return overstackcount
end

hook.Add("OnWaveStateChanged", "D3Bot.OnWaveStateChanged.Supervisor", function()
	--mainly to save some perf on things that are being ran 5 times or more per second
	local active = GAMEMODE:GetWaveActive()
	if active then
		curwave = GAMEMODE:GetWave() 
		if not finalized_starting_zombies and curwave > 0 then
			finalized_starting_zombies = GAMEMODE:GetDesiredStartingZombies() --dont calculate this all game long. Late joiners and leavers....
			onethird_of_starting_zombies = math_ceil(0.33 * finalized_starting_zombies)
		end
		bot_per_wave = math_max(curwave, 1) - 1

		timer.Simple(2.5, function()
			local overstack_count = EvaluateOverstackCount(#GAMEMODE.HumanPlayers, #GAMEMODE.ZombiePlayers)
			GAMEMODE.OverstackedZombies = overstack_count
			net.Start("zs_overstackedzombies")
				net.WriteUInt(overstack_count, 8)
			net.Broadcast()
		end)
	end
end)

hook.Add("DoPlayerDeath","D3Bot.DoPlayerDeath.Supervisor", function(pl, attacker, dmginfo)
	local is_human = P_Team(pl) == TEAM_HUMAN
	--[[if is_human and (GAMEMODE.RoundEnded or GAMEMODE:GetWave() <= 1) and humans_dead < forced_player_zombies then
		humans_dead = humans_dead + 1
	end]]

	if not is_human or P_IsBot(pl) or GAMEMODE.RoundEnded then return end
	
	--local wave = GAMEMODE:GetWave()
	local added_bot_per_wave = (bot_per_wave or (math_max(curwave, 1) - 1))
	local starting_zombies = (finalized_starting_zombies or GAMEMODE:GetDesiredStartingZombies())
	max_humans_dead = (onethird_of_starting_zombies or math_ceil( 0.33 * starting_zombies)) + added_bot_per_wave --keep 1/3rd of the starting zombies, and 1 more per wave, as bots.

	local num_bot_zombies = 0
	for _, pl in ipairs(GAMEMODE.ZombiePlayers) do 
		if E_IsValid(pl) and P_IsBot(pl) then
			num_bot_zombies = num_bot_zombies + 1
		end
	end

	timer.Simple(2.5, function()
		local overstack_count = EvaluateOverstackCount(#GAMEMODE.HumanPlayers, #GAMEMODE.ZombiePlayers)
		GAMEMODE.OverstackedZombies = overstack_count
		net.Start("zs_overstackedzombies")
			net.WriteUInt(overstack_count, 8)
		net.Broadcast()
	end)

	humans_dead = (num_bot_zombies >= max_humans_dead and humans_dead or humans_dead + 1)
end)

hook.Add("PlayerDisconnected", "D3Bot.PlayerDisconnected.Supervisor", function(pl)
	if P_Team(pl) == TEAM_UNDEAD then
		if forced_player_zombies > 0 and curwave > 0 then
			forced_player_zombies = forced_player_zombies - 1
		end
	end
	timer.Simple(2.5, function()
		local overstack_count = EvaluateOverstackCount(#GAMEMODE.HumanPlayers, #GAMEMODE.ZombiePlayers)
		GAMEMODE.OverstackedZombies = overstack_count
		net.Start("zs_overstackedzombies")
			net.WriteUInt(overstack_count, 8)
		net.Broadcast()
	end)
end)

hook.Add("PostPlayerRedeemed","D3Bot.PostPlayerRedeemed.Supervisor", function(pl, silent, noequip)
	if GAMEMODE.RoundEnded --[[or GAMEMODE:GetWave() <= 1 --[[or player.GetCount() <= GAMEMODE.LowPopulationLimit]] then return end

	timer.Simple(2.5, function()
		local overstack_count = EvaluateOverstackCount(#GAMEMODE.HumanPlayers, #GAMEMODE.ZombiePlayers)
		GAMEMODE.OverstackedZombies = overstack_count
		net.Start("zs_overstackedzombies")
			net.WriteUInt(overstack_count, 8)
		net.Broadcast()
	end)

	humans_dead = math_max(humans_dead - 1, 0)
end)

hook.Add("PostEndRound", "D3Bot.ResetHumansDead.Supervisor", function(winnerteam)
	humans_dead = 0
end)

--[[
current reference from sh_options
gammod.TeamRatiosByWave = {
	[1] = 0.20,
	[2] = 0.35,
	[3] = 0.50,
	[4] = 0.65,
	[5] = 0.85,
	[6] = 1.0
}
]]
local tempcheck = 0
local apocalypse_bots = 0
function D3bot.GetDesiredBotCount()
	--If no active players then don't add any bots.
	if #player_GetHumans() == 0 then return 0 end

	if GAMEMODE.PVB then return 0 end

	local maxpl_minus2 = game_MaxPlayers() - 2 --50
	local allowedTotal = maxpl_minus2

	local botmod = D3bot.ZombiesCountAddition
	
	--Override if wanted for events or extreme lag.
	if GAMEMODE.ShouldPopBlock then
		return humans_dead + botmod, allowedTotal
	end
	local hteam_count = #GAMEMODE.HumanPlayers
	local ct = CurTime()

	if tempcheck < ct then
		tempcheck = ct + 5
		if GAMEMODE.Apocalypse then
			apocalypse_bots = math_ceil(hteam_count * (0.25 + math_max(1, curwave) * 0.035))
			local allowed_bots_in_apocalypse = math_min(60, hteam_count * 1.25)
			allowedTotal = allowed_bots_in_apocalypse
		else
			apocalypse_bots = 0
			allowedTotal = maxpl_minus2
		end
	end

	local force_players = 0 --not GAMEMODE.ZombieEscape and volunteers > 3 and forced_player_zombies or 0

	local starting_zombies = (finalized_starting_zombies or GAMEMODE:GetDesiredStartingZombies())

	local volunteers = math_max(starting_zombies, 1)
	--local wave = GAMEMODE:GetWave()
	local added_bot_per_wave = (bot_per_wave or (math_max(curwave, 1) - 1))

	local needed = 0
	local desired_zperc = 0
	if curwave > 1 then
		local zteam_count = #GAMEMODE.ZombiePlayers
		desired_zperc = math_ceil(hteam_count * team_equalizer[curwave])
		
		if desired_zperc > zteam_count then --if zteam doesnt make up a **wave relative** percent of hteam, request more
			needed = math_max(desired_zperc - zteam_count, 0)
		end
	end
	local base_bots = (onethird_of_starting_zombies or math_ceil( 0.33 * starting_zombies )) --keep 33% of the starting zombies as bots
	bots_to_keep = (base_bots + needed + added_bot_per_wave) --used below to prevent bots from getting kicked out of the match

	local desired_zombie_count = (needed + volunteers + humans_dead)

	return math_max(desired_zperc, desired_zombie_count) + botmod + added_bot_per_wave + apocalypse_bots, allowedTotal
end

local spawnAsTeam
hook.Add("PlayerInitialSpawn", D3bot.BotHooksId, function(pl)
	--local wave = GAMEMODE:GetWave()
	if P_IsBot(pl) and spawnAsTeam == TEAM_UNDEAD then
		GAMEMODE.PreviouslyDied[pl:UniqueID()] = CurTime()
		GAMEMODE:PlayerInitialSpawn(pl)
	end
end)

D3bot.BotZombies = D3bot.BotZombies or {}
function D3bot.MaintainBotRoles()
	if #player_GetHumans() == 0 or GAMEMODE.RoundEnded then return end

	if #GAMEMODE.ZombiePlayers < D3bot.GetDesiredBotCount() then
		local bot = player.CreateNextBot(D3bot.GetUsername() or "BOT")
		
		spawnAsTeam = TEAM_UNDEAD

		if IsValid(bot) then
			bot:D3bot_InitializeOrReset()

			table_insert(D3bot.BotZombies, bot)

			if curwave <= 1 then
				bot:Kill()
			end
		end

		spawnAsTeam = nil
		
		return
	end
	if #GAMEMODE.ZombiePlayers > D3bot.GetDesiredBotCount() then 
		for i=1, #GAMEMODE.ZombiePlayers-D3bot.GetDesiredBotCount() do
			if #D3bot.BotZombies > ( (D3bot.ZombiesCountAddition or 0) + bots_to_keep ) then --if num of bots is greater than (botmod + bots to equalize then remove some)
				local randomBot = table.remove(D3bot.BotZombies, 1)
				if IsValid(randomBot) then
					local zWeapon = randomBot:GetActiveWeapon()
					if IsValid(zWeapon) and zWeapon.StopMoaning then
						zWeapon:StopMoaning()
					end
					randomBot:StripWeapons()
				end	
				return randomBot and ( randomBot:IsValid() and randomBot:Kick(D3bot.BotKickReason) )
			end
		end
	end
end

local NextNodeDamage = CurTime()
local NextMaintainBotRoles = CurTime()
function D3bot.SupervisorThinkFunction()
	if NextMaintainBotRoles < CurTime() then
		NextMaintainBotRoles = CurTime() + D3bot.BotUpdateDelay
		D3bot.MaintainBotRoles()
	end
	--[[if game.GetMap() == "gm_construct" then return end
	if (NextNodeDamage or 0) < CurTime() then
		NextNodeDamage = CurTime() + 2
		D3bot.DoNodeTrigger()
	end]]
end

function D3bot.DoNodeTrigger()
	local players = D3bot.RemoveObsDeadTgts(player_GetAll())
	players = D3bot.From(players):Where(function(k, v) return P_Team(v) ~= TEAM_UNDEAD end).R
	local ents = table.Add(players, D3bot.GetEntsOfClss(D3bot.NodeDamageEnts))
	for i, ent in pairs(ents) do
		local nodeOrNil = D3bot.MapNavMesh:GetNearestNodeOrNil(ent:GetPos()) -- TODO: Don't call GetNearestNodeOrNil that often
		if nodeOrNil then
			if type(nodeOrNil.Params.DMGPerSecond) == "number" and nodeOrNil.Params.DMGPerSecond > 0 then
				ent:TakeDamage(nodeOrNil.Params.DMGPerSecond*2, game.GetWorld(), game.GetWorld())
			end
			if ent:IsPlayer() and not ent.D3bot_Mem and nodeOrNil.Params.BotMod then
				D3bot.NodeZombiesCountAddition = nodeOrNil.Params.BotMod
			end
		end
	end
end
-- TODO: Detect situations and coordinate bots accordingly (Attacking cades, hunt down runners, spawncamping prevention)
-- TODO: If needed force one bot to flesh creeper and let him build a nest at a good place
