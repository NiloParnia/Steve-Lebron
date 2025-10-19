-- UnlockHandler.lua (ServerScriptService)
-- Handles client requests to unlock a node and hot-loads it

local RS = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local NodeManager       = require(game:GetService("ReplicatedStorage"):WaitForChild("NodeManager"))

local Remotes        = RS:WaitForChild("RemoteEvents")
local UnlockNode     = Remotes:WaitForChild("UnlockNode")
local ConfirmSuccess = Remotes:WaitForChild("ConfirmSuccess", 2) -- optional

local function notify(player, ok, message)
	if ConfirmSuccess then
		ConfirmSuccess:FireClient(player, { ok = ok, msg = message })
	end
end

local busy = setmetatable({}, { __mode = "k" }) -- weak keys

UnlockNode.OnServerEvent:Connect(function(player, nodeName)
	if busy[player] then return end
	busy[player] = true
	task.delay(0.25, function() busy[player] = nil end)

	if type(nodeName) ~= "string" or nodeName == "" or #nodeName > 40 then
		notify(player, false, "Invalid unlock request.")
		return
	end

	local profile = PlayerDataService.GetProfile(player)
	if not profile then
		notify(player, false, "Data not ready. Try again in a moment.")
		return
	end

	-- Already has it?
	for _, n in ipairs(profile.Data.Unlocks or {}) do
		if n == nodeName then
			notify(player, true, nodeName .. " already unlocked.")
			return
		end
	end

	local added = PlayerDataService.AddUnlock(player, nodeName, true)
	if not added then
		notify(player, false, "Unlock failed or not allowed.")
		return
	end

	NodeManager.AddUnlock(player, nodeName)
	print(player.Name, "unlocked", nodeName)
	notify(player, true, "Unlocked " .. nodeName .. "!")
end)