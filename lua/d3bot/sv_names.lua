D3bot.Names = {"Bot"}
D3bot.ZombieMainBotName = "Z-main"

-- TODO: Make search path relative
if D3bot.BotNameFile then
	include("names/"..D3bot.BotNameFile..".lua")
end

local function getUsernames()
	local usernames = {}
	for k, v in pairs(player.GetAll()) do
		usernames[v:Nick()] = v
	end
	return usernames
end

local names = {}
function D3bot.GetUsername(forcedName)
	local usernames = getUsernames()
	if forcedName then
		if not usernames[forcedName] then return forcedName end
		local number = 2
		while usernames[forcedName.."("..number..")"] do
			number = number + 1
		end
		return forcedName.."("..number..")"
	end
	
	if #names == 0 then names = table.Copy(D3bot.Names) end
	local name = table.remove(names, math.random(#names))
	
	if usernames[name] then
		local number = 2
		while usernames[name.."("..number..")"] do
			number = number + 1
		end
		return name.."("..number..")"
	end
	return name
end