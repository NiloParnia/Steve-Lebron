-- ServerScriptService/RounderDiagnostics.server.lua
-- Watches a Rounder NPC even if it spawns later. No GetAttribute calls.

local RS          = game:GetService("ReplicatedStorage")
local RunService  = game:GetService("RunService")

local StunService     = require(RS:WaitForChild("StunService"))
local SpeedController = require(RS:WaitForChild("SpeedController"))

-- ───────────────────────────────── helpers
local THIS_SOURCE
do local ok,s=pcall(function() return debug.info(1,"s") end); THIS_SOURCE = ok and s or "" end

local function who()
	for i=3,12 do
		local ok, src = pcall(function() return debug.info(i, "s") end)
		if ok and src and not tostring(src):find("RounderDiagnostics") then
			local ok2, what = pcall(function() return (debug.info(i, "n") or "") end)
			return string.format("%s:%s", tostring(src), tostring(what))
		end
	end
	return "?"
end


local function isHumanoidModel(x)
	return typeof(x) == "Instance" and x:IsA("Model") and x:FindFirstChildOfClass("Humanoid") ~= nil
end

local function looksLikeRounder(m)
	if not isHumanoidModel(m) then return false end
	-- Name checks only (no GetAttribute):
	local n = m.Name:lower()
	if n:find("rounder") then return true end
	-- common child stringValue fallback: enemyId/Id/etc.
	for _, c in ipairs(m:GetChildren()) do
		if c:IsA("StringValue") then
			local v = (c.Value or ""):lower()
			if v:find("rounder") then return true end
		end
	end
	return false
end

local CURRENT    = nil   -- the model we're watching
local HUM        = nil
local baseSpeed  = nil
local conns      = {}
local snapThread = nil
local lastSoftAt, lastHardAt, lastClearAt = 0,0,0

local function disconnectAll()
	for _, cn in ipairs(conns) do pcall(function() cn:Disconnect() end) end
	conns = {}
	if snapThread then
		task.cancel(snapThread)
		snapThread = nil
	end
end

local function attach(model)
	if CURRENT == model then return end
	disconnectAll()

	CURRENT = model
	HUM     = model and model:FindFirstChildOfClass("Humanoid") or nil
	if not (CURRENT and HUM) then
		warn("[RounderDiag] attach failed (no humanoid)")
		CURRENT, HUM = nil, nil
		return
	end

	baseSpeed = HUM.WalkSpeed
	print(("[RounderDiag] Attached to %s  base WS=%.2f")
		:format(CURRENT:GetFullName(), baseSpeed))

	-- Live property logs
	table.insert(conns, HUM:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		print(("[RounderDiag] WalkSpeed → %.2f"):format(HUM.WalkSpeed))
	end))

	table.insert(conns, CURRENT:GetPropertyChangedSignal("Parent"):Connect(function()
		if CURRENT.Parent == nil then
			print("[RounderDiag] Rounder removed; detaching.")
			disconnectAll()
			CURRENT, HUM, baseSpeed = nil, nil, nil
		end
	end))

	-- 1 Hz snapshots + perma-slow heuristic
	snapThread = task.spawn(function()
		while CURRENT and CURRENT.Parent do
			local ws = HUM.WalkSpeed
			local ps = HUM.PlatformStand
			local jr = HUM.JumpPower
			local ar = HUM.AutoRotate
			local hard = false
			pcall(function() hard = StunService.IsStunned(CURRENT) == true end)

		

			local t = os.clock()
			task.wait(1)
		end
	end)
end

-- Pick an existing Rounder if one is already in the world
local function attachExisting()
	-- Prefer workspace.Enemies children named/looking like Rounder
	local enemies = workspace:FindFirstChild("Enemies")
	if enemies then
		for _, m in ipairs(enemies:GetChildren()) do
			if looksLikeRounder(m) then attach(m); return true end
		end
	end
	-- Fallback: search whole workspace for any model that looks like Rounder
	for _, inst in ipairs(workspace:GetDescendants()) do
		if looksLikeRounder(inst) then attach(inst); return true end
	end
	return false
end

-- Watch for future spawns (handles your asynchronous EnemySpawner)
local function onCandidate(inst)
	if CURRENT or not isHumanoidModel(inst) then return end
	-- must be under workspace.Enemies OR look like Rounder by name/id
	if inst:IsDescendantOf(workspace:FindFirstChild("Enemies") or workspace) and looksLikeRounder(inst) then
		attach(inst)
	end
end

workspace.DescendantAdded:Connect(onCandidate)

-- Try to hook immediately if Rounder already spawned
if not attachExisting() then
	print("[RounderDiag] Rounder not present yet; waiting for spawn…")
end

-- ── non-destructive wrappers with dynamic target ─────────────────────────
local oldStunApply = StunService.Apply
local oldStunClear = StunService.Clear

StunService.Apply = function(entity, duration, opts)
	local match = false
	if CURRENT then
		match = (entity == CURRENT)
		if not match and typeof(entity) == "Instance" and entity:IsA("Player") then
			match = (entity.Character == CURRENT)
		end
	end

	if match then
		local hard  = not (type(opts) == "table" and opts.hard == false)
		local scale = (type(opts) == "table" and tonumber(opts.moveScale)) or 0.20
		print(("[RounderDiag] Stun.Apply hard=%s dur=%.2fs scale=%.2f caller=%s")
			:format(tostring(hard), duration, scale, who()))
		if hard then lastHardAt = os.clock() else lastSoftAt = os.clock() end
	end
	return oldStunApply(entity, duration, opts)
end

StunService.Clear = function(entity)
	local match = (CURRENT and (entity == CURRENT))
	if not match and CURRENT and typeof(entity) == "Instance" and entity:IsA("Player") then
		match = (entity.Character == CURRENT)
	end
	if match then
		print("[RounderDiag] Stun.Clear caller=" .. who())
		lastClearAt = os.clock()
	end
	return oldStunClear(entity)
end

local oldSCApply = SpeedController.Apply
local oldSCReset = SpeedController.Reset

SpeedController.Apply = function(playerOrModel, newSpeed, duration)
	local mdl = playerOrModel
	if typeof(playerOrModel) == "Instance" and playerOrModel:IsA("Player") then
		mdl = playerOrModel.Character
	end
	if CURRENT and mdl == CURRENT then
		print(("[RounderDiag] Speed.Apply → %.2f for %.2fs caller=%s")
			:format(newSpeed, duration, who()))
	end
	return oldSCApply(playerOrModel, newSpeed, duration)
end

SpeedController.Reset = function(playerOrModel)
	local mdl = playerOrModel
	if typeof(playerOrModel) == "Instance" and playerOrModel:IsA("Player") then
		mdl = playerOrModel.Character
	end
	if CURRENT and mdl == CURRENT then
		print("[RounderDiag] Speed.Reset caller=" .. who())
	end
	return oldSCReset(playerOrModel)
end
