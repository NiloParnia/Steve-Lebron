-- ReplicatedStorage/DodgeChargeService.lua
local DodgeChargeService = {}

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local DodgeEvt= RS:WaitForChild("RemoteEvents"):WaitForChild("DodgeCharges")

local MAX_CHARGES       = 3
local RECHARGE_INTERVAL = 7.5

local charges   = {}
local regenTask = {}

local function push(player)
	-- send (current, max) to that player
	DodgeEvt:FireClient(player, charges[player] or 0, MAX_CHARGES)
end

local function stopTask(player)
	if regenTask[player] then
		pcall(task.cancel, regenTask[player])
		regenTask[player] = nil
	end
end

local function startRegenLoop(player)
	if regenTask[player] then return end
	regenTask[player] = task.spawn(function()
		while player.Parent do
			if (charges[player] or 0) >= MAX_CHARGES then
				stopTask(player)
				break
			end
			task.wait(RECHARGE_INTERVAL)
			if (charges[player] or 0) < MAX_CHARGES then
				charges[player] = charges[player] + 1
				push(player) -- 🔵 notify client on +1
			end
		end
	end)
end

function DodgeChargeService.Get(player)
	return charges[player] or MAX_CHARGES
end

function DodgeChargeService.CanDodge(player)
	return (charges[player] or 0) > 0
end

function DodgeChargeService.Consume(player)
	if DodgeChargeService.CanDodge(player) then
		charges[player] = charges[player] - 1
		push(player)          -- 🔵 notify client on spend
		startRegenLoop(player)
		return true
	end
	return false
end

function DodgeChargeService.Reset(player)
	stopTask(player)
	charges[player] = MAX_CHARGES
	push(player)              -- 🔵 notify client on reset / spawn
end

Players.PlayerAdded:Connect(function(plr)
	DodgeChargeService.Reset(plr)  -- fires initial push
	-- If you also want full on death, uncomment:
	-- plr.CharacterAdded:Connect(function() DodgeChargeService.Reset(plr) end)
end)

Players.PlayerRemoving:Connect(function(plr)
	stopTask(plr)
	charges[plr]   = nil
	regenTask[plr] = nil
end)

return DodgeChargeService
