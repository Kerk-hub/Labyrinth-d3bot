D3bot.Handlers.Undead_Fallback = D3bot.Handlers.Undead_Fallback or {}
local HANDLER = D3bot.Handlers.Undead_Fallback

HANDLER.AngOffshoot = 7 --how close to the navmesh lines/links bots will follow. 0 = no straying from lines/links. 45 = vanilla/'realistic' zombies
HANDLER.RateOfViewmodelChange = 0.1 --0.4 = 9/5/2024 bots(roughly 2-3 times per second)
HANDLER.BotTgtFixationDistMin = 125
HANDLER.BotTgtFixationDistMinSqr = HANDLER.BotTgtFixationDistMin ^ 2
local BotClasses = {
	[1] = {
		"Fresh Infected", "Fresh Infected", "Ghoul", "Stalker"
	},
	[2] = {
		"Zombie", "Zombie", "Rotten Ghoul", "Wraith", "Stalker", "Bloated Zombie"
	},
	[3] = {
		"Zombie", "Zombie", "Tarnisher", "Poison Zombie", "Fast Zombie", "Bloated Zombie"
	},
	[4] = {
		"Zombie", "Zombie", "Zombie", "Scrapper", "Tarnisher", "Vile Bloated Zombie", "Rebel Poison Zombie", "Fast Zombie"
	},
	[5] = {
		"Zombie", "Zombie", "Scrapper", "Charred Ghoul", "Vile Bloated Zombie", "Volatile Poison Zombie", "Lacerator"
	},
	[6] = {
		"Zombine", "Zombine", "Scrapper", "Charred Ghoul", "Putrid Bloated Zombie", "Elite Poison Zombine", "Lacerator"
	},
}

local ObjBotClasses = {[1] = {"Zombie", "Ghoul", "Stalker", "Bloated Zombie", "Fast Zombie", "Poison Zombie"}}
HANDLER.ObjBotClasses = ObjBotClasses

BotClasses[7] = BotClasses[6]
BotClasses[8] = BotClasses[6]
BotClasses[9] = BotClasses[6]
HANDLER.BotClasses = BotClasses

--[[HANDLER.HvH_BotClasses = {
	"Nightmare", "Nightmare", 
	"The Reaper", "The Reaper", "The Reaper",
	"The Reaper", "The Reaper", "The Reaper",
	"Angry Hobo", "Angry Hobo", "Angry Hobo",
	"The Butcher", "The Butcher", "The Butcher", "Tank"
}]]


HANDLER.RandomSecondaryAttack = {
	--["Zombine"] = {MinTime = 5, MaxTime = 30}, --Useless to do since there isn't a distance check, zombines just kill themselves too early.
	["Ghoul"] = {MinTime = 5, MaxTime = 10},
	["Rotten Ghoul"] = {MinTime = 5, MaxTime = 15},
	["Charred Ghoul"] = {MinTime = 5, MaxTime = 20},
	["Tarnisher"] = {MinTime = 10, MaxTime = 25},
	["Poison Zombie"] = {MinTime = 10, MaxTime = 30},
	["Rebel Poison Zombie"] = {MinTime = 10, MaxTime = 30},
	["Volatile Poison Zombie"] = {MinTime = 10, MaxTime = 30},
	["Elite Poison Zombine"] = {MinTime = 10, MaxTime = 30},
	["Wild Poison Zombie"] = {MinTime = 10, MaxTime = 30}
}

HANDLER.Fallback = true
function HANDLER.SelectorFunction(zombieClassName, team)
	return team == TEAM_UNDEAD
end

function HANDLER.UpdateBotCmdFunction(bot, cmd)
	if GAMEMODE.RoundEnded then return end

	cmd:ClearButtons()
	cmd:ClearMovement()
	
	-- Fix knocked down bots from sliding around. (Workaround for the NoxiousNet codebase, as ply:Freeze() got removed from status_knockdown, status_revive, ...)
	if bot.KnockedDown and IsValid(bot.KnockedDown) or bot.Revive and IsValid(bot.Revive) then
		return
	end
	
	if not bot:Alive() then
		-- Get back into the game
		cmd:SetButtons(IN_ATTACK)
		return
	end
	
	bot:D3bot_UpdatePathProgress()
	D3bot.Basics.SuicideOrRetarget(bot)
	
	local result, actions, forwardSpeed, sideSpeed, upSpeed, aimAngle, minorStuck, majorStuck, facesHindrance = D3bot.Basics.PounceAuto(bot)
	if not result then
		result, actions, forwardSpeed, sideSpeed, upSpeed, aimAngle, minorStuck, majorStuck, facesHindrance = D3bot.Basics.WalkAttackAuto(bot)
		if not result then
			return
		end
	end

	-- Simple hack for throwing poison randomly TODO: Only throw if possible target is close enough. Aiming. Timing.
	local secAttack = HANDLER.RandomSecondaryAttack[GAMEMODE.ZombieClasses[bot:GetZombieClass()].Name]
	if secAttack then
		local mem = bot.D3bot_Mem
		if not mem.NextThrowPoisonTime or mem.NextThrowPoisonTime <= CurTime() then
			mem.NextThrowPoisonTime = CurTime() + secAttack.MinTime + math.random() * (secAttack.MaxTime - secAttack.MinTime)
			actions = actions or {}
			actions.Attack2 = true
		end
	end
	
	local buttons
	if actions then
		buttons = bit.bor(actions.MoveForward and IN_FORWARD or 0, actions.MoveBackward and IN_BACK or 0, actions.MoveLeft and IN_MOVELEFT or 0, actions.MoveRight and IN_MOVERIGHT or 0, actions.Attack and IN_ATTACK or 0, actions.Attack2 and IN_ATTACK2 or 0, actions.Duck and IN_DUCK or 0, actions.Jump and IN_JUMP or 0, actions.Use and IN_USE or 0)
	end

	local wep = bot:GetActiveWeapon()
	if not actions.Attack and not actions.Attack2 and wep.IsMoaning and not wep:IsMoaning() and wep.StartMoaning then
		buttons = bit.bor(buttons, IN_RELOAD)
	end
	
	if majorStuck and GAMEMODE:GetWaveActive() then bot:Kill() end
	
	bot:SetEyeAngles(aimAngle)
	cmd:SetViewAngles(aimAngle)
	cmd:SetForwardMove(forwardSpeed)
	if sideSpeed then cmd:SetSideMove(sideSpeed) end
	if upSpeed then cmd:SetUpMove(upSpeed) end
	cmd:SetButtons(buttons)
end

function HANDLER.ThinkFunction(bot)
	local mem = bot.D3bot_Mem
	
	local botPos = bot:GetPos()
	
	local tracedata = {start=nil,endpos=nil,mask=MASK_PLAYERSOLID,filter=nil}
	tracedata.start = bot:GetPos()
	tracedata.endpos = tracedata.start
	tracedata.filter = bot
	local traceResult = util.TraceEntity(tracedata,bot)
	
	-- Workaround for bots phasing through barricades in some versions of the gamemode
	if bot:Alive() and traceResult.StartSolid == true and traceResult.Entity and not traceResult.Entity:IsWorld() and (traceResult.Entity and traceResult.Entity:GetClass() == "prop_physics") and GAMEMODE:ShouldCollide(bot, traceResult.Entity) and traceResult.Entity:GetCollisionGroup() ~= COLLISION_GROUP_DEBRIS and traceResult.Entity:IsNailed() then
		--bot:Kill()
		if mem.LastValidPos then
			bot:SetPos(mem.LastValidPos)
		end
	elseif bot:Alive() then
		mem.LastValidPos = botPos
	end
	
	if mem.nextUpdateSurroundingPlayers and mem.nextUpdateSurroundingPlayers < CurTime() or not mem.nextUpdateSurroundingPlayers then
		if not mem.TgtOrNil or IsValid(mem.TgtOrNil) and mem.TgtOrNil:GetPos():Distance(botPos) > HANDLER.BotTgtFixationDistMin then
			mem.nextUpdateSurroundingPlayers = CurTime() + 0.9 + math.random() * 0.2
			local targets = team.GetPlayers(TEAM_HUMAN) -- TODO: Filter targets before sorting
			table.sort(targets, function(a, b) return botPos:DistToSqr(a:GetPos()) < botPos:DistToSqr(b:GetPos()) end)
			for k, v in ipairs(targets) do
				if IsValid(v) and botPos:DistToSqr(v:GetPos()) < 500*500 and HANDLER.CanBeTgt(bot, v) and bot:D3bot_CanSeeTarget(nil, v) then
					bot:D3bot_SetTgtOrNil(v, false, nil)
					mem.nextUpdateSurroundingPlayers = CurTime() + 3
					break
				end
				if k > 5 then break end
			end
		end
	end
	
	if mem.nextCheckTarget and mem.nextCheckTarget < CurTime() or not mem.nextCheckTarget then
		mem.nextCheckTarget = CurTime() + 0.9 + math.random() * 0.2
		if not HANDLER.CanBeTgt(bot, mem.TgtOrNil) then
			HANDLER.RerollTarget(bot)
		end
	end
	
	if mem.nextUpdateOffshoot and mem.nextUpdateOffshoot < CurTime() or not mem.nextUpdateOffshoot then
		mem.nextUpdateOffshoot = CurTime() + HANDLER.RateOfViewmodelChange + math.random() * 0.2 --math.random() * 0.2 is a way to make all zombies not update at the same time
		bot:D3bot_UpdateAngsOffshoot(HANDLER.AngOffshoot)
	end

	if mem.nextUpdatePath and mem.nextUpdatePath < CurTime() or not mem.nextUpdatePath then
		local pathCostFunction = nil
	
		if D3bot.UsingSourceNav then
			pathCostFunction = function( cArea, nArea, link )
				local linkMetaData = link:GetMetaData()
				local linkPenalty = linkMetaData and linkMetaData.ZombieDeathCost or 0
				return linkPenalty * ( mem.ConsidersPathLethality and 1 or 0 )
			end
		else
			pathCostFunction = function( node, linkedNode, link )
				local linkMetadata = D3bot.LinkMetadata[link]
				local linkPenalty = linkMetadata and linkMetadata.ZombieDeathCost or 0
				return linkPenalty * (mem.ConsidersPathLethality and 1 or 0)
			end
		end
	
		mem.nextUpdatePath = CurTime() + 0.9 + math.random() * 0.2
		bot:D3bot_UpdatePath(nil, nil)
	end
end

function HANDLER.OnTakeDamageFunction(bot, dmg)
	local attacker = dmg:GetAttacker()
	if not HANDLER.CanBeTgt(bot, attacker) then return end
	local mem = bot.D3bot_Mem
	if IsValid(mem.TgtOrNil) and mem.TgtOrNil:GetPos():DistToSqr(bot:GetPos()) <= HANDLER.BotTgtFixationDistMinSqr then return end
	mem.TgtOrNil = attacker
	--bot:Say("Ouch! Fuck you "..attacker:GetName().."! I'm gonna kill you!")
end

function HANDLER.OnDoDamageFunction(bot, dmg)
	--local mem = bot.D3bot_Mem
	--bot:Say("Gotcha!")
end

function HANDLER.OnDeathFunction(bot)
	local wave = GAMEMODE:GetWave()

	if GAMEMODE.Apocalypse and wave == 1 then
		bot:D3bot_RerollClass({ "Fresh Dead" })
		return
	end

	bot:D3bot_RerollClass((GAMEMODE.ObjectiveMap and HANDLER.ObjBotClasses[1]) or HANDLER.BotClasses[wave] or HANDLER.BotClasses[1])
end

local potTargetEntClasses = {"prop_obj_sigil"} --"prop_*turret", "prop_arsenalcrate", "prop_manhack*", 
local potEntTargets = nil
local potTargets = nil

local function pathFuncAlias(node1, node2, abilities)
	return D3bot.GetBestMeshPathOrNil(node1, node2, nil, nil, abilities)
end

local function pathFuncAliasValve(node1, node2, abilities)
	return D3bot.GetBestValveMeshPathOrNil(node1, node2, nil, nil, abilities)
end

local empty_path_func = function() return {} end

local memo_GetBestMeshPathOrNil = empty_path_func
local memo_GetBestValveMeshPathOrNil = empty_path_func

local closest_pathFunc = empty_path_func

hook.Add("Initialize", "D3bot.Cache_ClosestTarget_PathFunc", function()
	if memoize3_no_nil then
		memo_GetBestMeshPathOrNil = memoize3_no_nil(pathFuncAlias)
		memo_GetBestValveMeshPathOrNil = memoize3_no_nil(pathFuncAliasValve)
	else
		memo_GetBestMeshPathOrNil = pathFuncAlias
		memo_GetBestValveMeshPathOrNil = pathFuncAliasValve
	end

	if not D3bot.UsingSourceNav then
		closest_pathFunc = memo_GetBestMeshPathOrNil
	else
		closest_pathFunc = memo_GetBestValveMeshPathOrNil
	end
end)

local abilities = { Walk = true }
local function GetClosestTarget(bot) --Allows bots to determine the closest gen or human 
	potEntTargets = D3bot.GetEntsOfClss(potTargetEntClasses)
	potTargets = table.Add(D3bot.RemoveObsDeadTgts(team.GetPlayers(TEAM_HUMAN)), potEntTargets)
	local closestTarget = NULL 
	local shortestDistance = math.huge
	local botPos = bot:GetPos()
	local mapNavMesh = D3bot.MapNavMesh
	local node = mapNavMesh:GetNearestNodeOrNil(botPos)

	if not node then return end

	for _, ent in ipairs(potTargets) do
		if not HANDLER.CanBeTgt(bot, ent) then continue end
		local path = closest_pathFunc(node, mapNavMesh:GetNearestNodeOrNil(ent:GetPos()), abilities)
		if path and path[1] then 
			local prevPos = botPos
			local nextPos = path[1].Pos
			local totalDistance = prevPos:Distance(nextPos)

			for i = 1, #path - 1 do 
				prevPos = path[i].Pos
				nextPos = path[i + 1].Pos
				totalDistance = totalDistance + prevPos:Distance(nextPos)
			end

			totalDistance = totalDistance + nextPos:Distance(ent:GetPos())

			if totalDistance < shortestDistance then
				shortestDistance = totalDistance
				closestTarget = ent 
			end 
		end
	end
	
	return closestTarget
end

function HANDLER.OnRespawnFunction(bot)
	bot.D3bot_Mem.nextCheckTarget = CurTime() + 4

	local generation = bot.BotGeneration
	local target = D3bot.GenerationTargets[generation]
	
	if not target or not target:IsValid() then
		target = GetClosestTarget(bot)
		if target and target:IsValid() then
			D3bot.GenerationTargets[generation] = target
		end
	end

	bot:D3bot_SetTgtOrNil(target, false, nil)
end
-----------------------------------
-- Custom functions and settings --
-----------------------------------

function HANDLER.CanBeTgt(bot, target)
	if not target or not IsValid(target) then return end
	local wep = target:IsPlayer() and target:GetActiveWeapon() or nil
	local IsMovementwep = wep and wep:IsValid() and wep.MovementWeapon
	local AltGamemode = GAMEMODE.PVB or GAMEMODE.ZombieEscape
	local botClassName = ""
	if GAMEMODE and GAMEMODE.ZombieClasses and IsValid(bot) and bot.GetZombieClass then
		local idx = bot:GetZombieClass()
		local info = GAMEMODE.ZombieClasses[idx]
		if info and info.Name then botClassName = info.Name end
	end

	if target:IsPlayer() and IsMovementwep and not (botClassName == "Fast Zombie" or botClassName == "Lacerator") and not AltGamemode then return end -- Ignore players with movement weapons unless bot is fast zombie or lacerator.
	if SAM_LOADED and target:IsPlayer() and target:sam_get_nwvar("cloaked",false) then return end -- Ignore cloaked admins.
	if target:IsPlayer() and target:GetStatus("hidden") and not (target:IsPlayer() and target == GAMEMODE.TheLastHuman) then return end -- Ignore player who is hidden.
	if target:IsPlayer() and target ~= bot and target:Team() ~= TEAM_UNDEAD and target:GetObserverMode() == OBS_MODE_NONE and not target:IsFlagSet(FL_NOTARGET) and target:Alive() then return true end
	if target:GetClass() == "prop_obj_sigil" and target:GetSigilCorrupted() then return end -- Special case to ignore corrupted sigils.
	if potEntTargets and table.HasValue(potEntTargets, target) then return true end
end

function HANDLER.RerollTarget(bot)
	-- Get humans or non zombie players or any players in this order
	--local players = D3bot.RemoveObsDeadTgts(GAMEMODE.HumanPlayers)
	--if #players == 0 and TEAM_UNDEAD then
	--players = D3bot.RemoveObsDeadTgts(player.GetAll())
	--players = D3bot.From(players):Where(function(k, v) return v:Team() ~= TEAM_UNDEAD end).R
	--end
	--[[if #players == 0 then
	players = D3bot.RemoveObsDeadTgts(player.GetAll())
end]]
	potEntTargets = D3bot.GetEntsOfClss(potTargetEntClasses)
	potTargets = table.Add(D3bot.RemoveObsDeadTgts(team.GetPlayers(TEAM_HUMAN)), potEntTargets)
	bot:D3bot_SetTgtOrNil(table.Random(potTargets), false, nil)
end
