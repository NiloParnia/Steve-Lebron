-- ResetCleaner (ServerScriptService)

local Players            = game:GetService("Players")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local CombatState        = require(ReplicatedStorage:WaitForChild("CombatState"))
local CooldownService    = require(ReplicatedStorage:WaitForChild("CooldownService"))
local SpeedController    = require(ReplicatedStorage:WaitForChild("SpeedController"))
local DamageService      = require(ReplicatedStorage:WaitForChild("DamageService"))
local GuardService       = require(ReplicatedStorage:WaitForChild("GuardService"))
local DodgeChargeService = require(ReplicatedStorage:WaitForChild("DodgeChargeService"))
local AttackStateService = require(ReplicatedStorage:WaitForChild("AttackStateService"))
local IFrameStore        = require(ReplicatedStorage:WaitForChild("IFrameStore"))

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		-- give Roblox a heartbeat to create Humanoid etc.
		task.wait(0.1)

		-- core combat state
		CombatState.Cleanup(player)
		CooldownService.Clear(player)
		SpeedController.Reset(player)

		-- defense / block systems
		DamageService.EndBlock(player)
		GuardService.EndBlock(player)      -- clears guard flags & regen loop

		-- attack / stamina trackers
		AttackStateService.Clear(player)
		DodgeChargeService.Reset(player)

		-- purge residual i-frames
		IFrameStore.Grant(player, 0)
	end)
end)
local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local CombatState = require(RS:WaitForChild("CombatState"))

local function clearLocksFor(p: Player, why: string)
	pcall(function() CombatState.ForceUnlock(p, why) end)
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum:SetAttribute("Mounted", false) end
end

Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(char)
		-- defer to ensure Humanoid exists
		task.defer(function()
			clearLocksFor(p, "spawn")
		end)
		local hum = char:WaitForChild("Humanoid", 5)
		if hum then
			hum.Died:Connect(function()
				clearLocksFor(p, "death")
			end)
		end
	end)
end)
