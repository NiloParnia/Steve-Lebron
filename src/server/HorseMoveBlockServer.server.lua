
-- Blocks combat/move remotes and tools while the player is mounted

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")

-- 🔁 CHANGE THESE to match your game’s remotes (add more if you have them):
local REMOTE_NAMES = {
	"ActivateNode",      -- e.g., your combat/ability trigger
	"UseAbility",        -- example
	"CastSkill",         -- example
}

-- === Reject "move" remotes while mounted ===
for _, name in ipairs(REMOTE_NAMES) do
	local re = RS:FindFirstChild("RemoteEvents") and RS.RemoteEvents:FindFirstChild(name)
	if re and re:IsA("RemoteEvent") then
		re.OnServerEvent:Connect(function(player, ...)
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if hum and hum:GetAttribute("Mounted") then
				-- hard reject
				return
			end
			-- else: let your existing handler run (this script is a guard, not the main logic)
		end)
	end
end

-- === Optional: block Tools while mounted (unequip instantly) ===
local function hookCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid")

	-- if player equips a Tool while mounted, instantly unequip it
	hum.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			if hum:GetAttribute("Mounted") then
				hum:UnequipTools()
			end
			-- also guard the Tool’s own Activated
			child.Activated:Connect(function()
				if hum:GetAttribute("Mounted") then
					hum:UnequipTools()
				end
			end)
		end
	end)

	-- also watch Backpack → move to character
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		backpack.ChildAdded:Connect(function(tool)
			if tool:IsA("Tool") then
				tool.Activated:Connect(function()
					if hum:GetAttribute("Mounted") then
						hum:UnequipTools()
					end
				end)
			end
		end)
	end
end

Players.PlayerAdded:Connect(function(p)
	p.CharacterAdded:Connect(function(c) hookCharacter(p, c) end)
	if p.Character then hookCharacter(p, p.Character) end
end)
