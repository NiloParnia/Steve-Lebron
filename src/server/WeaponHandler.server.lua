
-- ServerScriptService/WeaponHandler.lua
-- Bridges client input -> node execution
-- Blocks most actions while Mounted, but whitelists system actions (SummonHorse, BlockEnd, Dismount).
-- Also lets certain nodes run even if not in the 5-slot loadout.

local RS      = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local NodeManager       = require(RS:WaitForChild("NodeManager"))

local Remotes       = RS:WaitForChild("RemoteEvents")
local ActivateNode  = Remotes:WaitForChild("ActivateNode")

-- If your node scripts live here:
local NodeModulesFolder = RS:FindFirstChild("NodeModules")

-- ==== MOUNT GUARD CONFIG =====================================================
local DEBUG_MOUNT = true

local ALLOW_WHEN_MOUNTED = {
	BlockEnd = true,                 -- allow releasing block while mounted
	SummonHorse = true,              -- allow summon/dismiss even if mounted
	Horse_RequestDismount = true,    -- if you route this through the same handler
}

-- Always-available "system actions" (not counted in 5-slot loadout)
local ALWAYS_AVAILABLE = {
	SummonHorse = true,
}
-- ============================================================================

local function isMounted(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum:GetAttribute("Mounted") == true
end

local function getDirVecOrFallback(player, dirVec)
	if typeof(dirVec) == "Vector3" and dirVec.Magnitude > 0 then
		return dirVec.Unit
	end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then return root.CFrame.LookVector end
	return Vector3.new(0, 0, -1)
end

local function resolveNode(player, nodeName)
	-- Loadout-aware path first
	local node = NodeManager.GetNode(player, nodeName)
	if node then return node end

	-- System actions: allow direct require from RS/NodeModules/<name>
	if ALWAYS_AVAILABLE[nodeName] and NodeModulesFolder then
		local mod = NodeModulesFolder:FindFirstChild(nodeName)
		if mod and mod:IsA("ModuleScript") then
			local ok, res = pcall(require, mod)
			if ok then return res end
			warn(("[WeaponHandler] Failed to require NodeModules.%s: %s"):format(nodeName, tostring(res)))
		end
	end

	return nil
end

ActivateNode.OnServerEvent:Connect(function(player, nodeName, dirVec)
	-- 0) Hard gate while mounted (whitelist exceptions)
	if isMounted(player) and not ALLOW_WHEN_MOUNTED[nodeName] then
		if DEBUG_MOUNT then
			print(("[WeaponHandler] BLOCKED while mounted ▶ %s  node=%s"):format(player.Name, tostring(nodeName)))
		end
		return
	end

	print(('[WeaponHandler] ▶ %s  node=%s'):format(player.Name, tostring(nodeName)))

	-- 1) Validate
	if type(nodeName) ~= "string" or nodeName == "" then
		warn("[WeaponHandler] Invalid node name from", player.Name); return
	end

	-- 2) Ensure profile
	local profile = PlayerDataService.GetProfile(player)
	if not profile then
		warn("[WeaponHandler] No profile yet for", player.Name, "(ignoring)"); return
	end

	-- 3) Resolve node (loadout first; fallback system action module)
	local node = resolveNode(player, nodeName)
	if not node then
		warn(('[WeaponHandler] Node not found for %s: %s'):format(player.Name, nodeName))
		return
	end

	-- 4) Direction
	dirVec = getDirVecOrFallback(player, dirVec)

	-- 5) Execute via common call patterns
	local ok, err
	if type(node.OnStart) == "function" then
		ok, err = pcall(function() node.OnStart(player, dirVec) end)
		if ok then return else warn("[WeaponHandler] OnStart error:", err) end
	end

	if type(node.Execute) == "function" then
		ok, err = pcall(function() node.Execute(player, dirVec) end)
		if ok then return else warn("[WeaponHandler] Execute(player,dir) error:", err) end

		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			ok, err = pcall(function() node:Execute(root, dirVec) end)
			if ok then return else warn("[WeaponHandler] Execute(root,dir) error:", err) end
		end
	end

	warn("[WeaponHandler] No valid call pattern for node:", nodeName)
end)
