-- ActivateNodeRouter.server.lua
-- Forwards ActivateNode to node module; passes camera dir + camera right
local RS = game:GetService("ReplicatedStorage")
local Remotes = RS:WaitForChild("RemoteEvents")
local ActivateNode = Remotes:WaitForChild("ActivateNode")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local okNM, NodeManager = pcall(function() return require(RS:WaitForChild("NodeManager")) end)

local function sanitizeDir(v)
	if typeof(v) ~= "Vector3" or v.Magnitude <= 0 then return nil end
	return v.Unit
end

local function orthoRight(dir, rightGuess)
	-- try provided right; make it orthogonal to dir
	if typeof(rightGuess) == "Vector3" and rightGuess.Magnitude > 0 then
		local r = (rightGuess - dir * rightGuess:Dot(dir))
		if r.Magnitude > 1e-4 then return r.Unit end
	end
	-- fallback from dir and world up
	local up = Vector3.yAxis
	local r = up:Cross(dir) -- screen-style right given look and up
	if r.Magnitude < 1e-4 then
		r = dir:Cross(up)
	end
	return r.Magnitude > 0 and r.Unit or Vector3.xAxis
end

ActivateNode.OnServerEvent:Connect(function(player, nodeName, dirVec, camRight)
	if type(nodeName) ~= "string" or nodeName == "" or #nodeName > 40 then return end
	if not PlayerDataService.HasUnlock(player, nodeName) then return end

	local dir = sanitizeDir(dirVec)
	local right = dir and orthoRight(dir, camRight) or nil

	-- Prefer NodeManager if it exposes Activate(player, nodeName, dir, right)
	if okNM and NodeManager and typeof(NodeManager.Activate) == "function" then
		local ok, err = pcall(function() NodeManager.Activate(player, nodeName, dir, right) end)
		if not ok then warn("[ActivateNodeRouter] NodeManager.Activate error:", err) end
		return
	end

	-- Fallback: require module and call OnStart(player, dir, right)
	local folder = RS:FindFirstChild("NodeModules")
	local mod = folder and folder:FindFirstChild(nodeName)
	if not (mod and mod:IsA("ModuleScript")) then return end

	local ok, nodeMod = pcall(require, mod)
	if not ok then warn("[ActivateNodeRouter] require failed:", nodeMod) return end
	if type(nodeMod) == "table" and type(nodeMod.OnStart) == "function" then
		local ok2, err2 = pcall(nodeMod.OnStart, player, dir, right)
		if not ok2 then warn("[ActivateNodeRouter] OnStart error:", err2) end
	end
end)
