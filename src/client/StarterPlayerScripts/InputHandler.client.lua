-- src/client/StarterPlayerScripts/InputHandler.client.lua
-- Minimal client input: Block start/end only. SummonHorse handled elsewhere.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes       = ReplicatedStorage:WaitForChild("RemoteEvents")
local ActivateNode  = Remotes:WaitForChild("ActivateNode")

local LOCAL_PLAYER  = Players.LocalPlayer

-- You can change these to your preferred keys/buttons.
local BLOCK_KEYS = {
	[Enum.KeyCode.F] = true,
}
local BLOCK_MOUSE = {
	[Enum.UserInputType.MouseButton2] = true, -- right mouse
}

local blockDown = false

local function beginBlock()
	if blockDown then return end
	blockDown = true
	-- Your NodeModules implement BlockStart; server routes via ActivateNode
	ActivateNode:FireServer("BlockStart")
end

local function endBlock()
	if not blockDown then return end
	blockDown = false
	ActivateNode:FireServer("BlockEnd")
end

-- Keyboard / mouse listeners -------------------------------------------------
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.Keyboard and BLOCK_KEYS[input.KeyCode] then
		beginBlock()
	elseif BLOCK_MOUSE[input.UserInputType] then
		beginBlock()
	end
end)

UserInputService.InputEnded:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.Keyboard and BLOCK_KEYS[input.KeyCode] then
		endBlock()
	elseif BLOCK_MOUSE[input.UserInputType] then
		endBlock()
	end
end)

-- Defensive cleanup on character reset (not strictly necessary here)
LOCAL_PLAYER.CharacterAdded:Connect(function()
	-- Ensure block isn’t stuck down across respawns
	blockDown = false
end)
