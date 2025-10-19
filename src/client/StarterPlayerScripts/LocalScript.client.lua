-- StarterPlayerScripts/SummonHorseKey.client.lua
-- Press H to toggle SummonHorse (always available; server enforces unlock/cooldown).

local UIS = game:GetService("UserInputService")
local RS  = game:GetService("ReplicatedStorage")

local Remotes      = RS:WaitForChild("RemoteEvents")
local ActivateNode = Remotes:WaitForChild("ActivateNode")

local SUMMON_KEY = Enum.KeyCode.H

UIS.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == SUMMON_KEY then
		local cam = workspace.CurrentCamera
		local dir = cam and cam.CFrame.LookVector or Vector3.new(0,0,-1)
		ActivateNode:FireServer("SummonHorse", dir)
	end
end)
