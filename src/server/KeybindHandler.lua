-- KeybindHandler.lua
-- RemoteFunctions to get/set keybinds + list *bindable* (unlockable ∩ owned) nodes only.

local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("RemoteEvents")

local GetKeybindsRF      = Remotes:WaitForChild("GetKeybinds")
local SetKeybindRF       = Remotes:WaitForChild("SetKeybind")
local GetUnlockedNodesRF = Remotes:WaitForChild("GetUnlockedNodes")

local KeybindService     = require(script.Parent:WaitForChild("KeybindService"))
local PlayerDataService  = require(script.Parent:WaitForChild("PlayerDataService"))

-- live unlockables set
local UNLOCKABLES_SET = {}
local function refreshUnlockables()
	table.clear(UNLOCKABLES_SET)
	local f = RS:FindFirstChild("Unlockables")
	if f then
		for _, sv in ipairs(f:GetChildren()) do
			if sv:IsA("StringValue") and sv.Value ~= "" then
				UNLOCKABLES_SET[sv.Value] = true
			end
		end
	end
end
refreshUnlockables()
local f = RS:FindFirstChild("Unlockables")
if f then
	f.ChildAdded:Connect(refreshUnlockables)
	f.ChildRemoved:Connect(refreshUnlockables)
end

GetKeybindsRF.OnServerInvoke = function(player)
	return KeybindService.GetAll(player)
end

SetKeybindRF.OnServerInvoke = function(player, payload)
	if typeof(payload) ~= "table" then return { ok=false, msg="Bad payload" } end
	local key  = tostring(payload.key or "")
	local node = payload.node and tostring(payload.node) or ""
	local ok, msg = KeybindService.Set(player, key, node)
	return { ok=ok, msg=msg, binds = KeybindService.GetAll(player) }
end

-- Return ONLY nodes that are unlockable AND the player owns
GetUnlockedNodesRF.OnServerInvoke = function(player)
	local data = PlayerDataService.GetData(player)
	local out = {}
	for _, n in ipairs((data and data.Unlocks) or {}) do
		if UNLOCKABLES_SET[n] then table.insert(out, n) end
	end
	table.sort(out)
	return out
end

return true
