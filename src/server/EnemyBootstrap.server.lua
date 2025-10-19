-- ServerScriptService/EnemyBootstrap.server.lua
local RS       = game:GetService("ReplicatedStorage")
local Looks    = require(RS:WaitForChild("EnemyLooks"))
local Specs    = require(RS:WaitForChild("EnemySpecs"))
local RigKit   = require(RS:WaitForChild("RigMadLibs"))

local ENEMY_ROOT = workspace:FindFirstChild("Enemies") or workspace

-- ===== AI module resolve (EnemyController preferred; fallback Controller) ===
local function resolveAIModule()
	local aiFolder = RS:WaitForChild("AI")
	local mod = aiFolder:FindFirstChild("EnemyController") or aiFolder:FindFirstChild("Controller")
	if not mod then
		warn("[EnemyBootstrap] No AI module found under ReplicatedStorage/AI (expected 'EnemyController' or 'Controller').")
		return nil
	end
	local ok, ctrl = pcall(require, mod)
	if not ok then
		warn("[EnemyBootstrap] Failed to require AI module:", ctrl)
		return nil
	end
	if type(ctrl) ~= "table" or type(ctrl.Start) ~= "function" then
		warn("[EnemyBootstrap] AI module does not return a table with Start(self, spec).")
		return nil
	end
	return ctrl
end

local Controller = resolveAIModule()

-- ===== Looks helpers ========================================================
local function firstLook(key)
	local t = Looks[key]
	return (t and #t > 0) and t[1] or nil
end

local function applyLook(model: Model, spec: table, overrideSkinKey: string?)
	if model:GetAttribute("Skinned") then return end

	local entry
	if overrideSkinKey and overrideSkinKey ~= "" then
		entry = firstLook(overrideSkinKey)
	elseif spec and spec.skinKey then
		entry = firstLook(spec.skinKey)
	elseif spec and spec.skin then
		entry = spec.skin -- inline recipe: { userId=.. | outfitId=.. | assets={..} }
	end
	if not entry then return end

	if entry.userId then
		RigKit.applyUserLook(model, entry.userId)
	elseif entry.outfitId then
		RigKit.applyOutfit(model, entry.outfitId)
	elseif entry.assets then
		RigKit.applyAssets(model, entry.assets)
	end

	model:SetAttribute("Skinned", true)
end

-- ===== Binder ===============================================================
local function bind(model: Model)
	if model:GetAttribute("Bound") then return end
	if not model:GetAttribute("IsEnemy") then return end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local enemyId = model:GetAttribute("enemyId")
	if not enemyId or enemyId == "" then enemyId = model.Name end

	local spec = Specs[enemyId]
	if not spec then
		warn(("[EnemyBootstrap] Unknown enemyId '%s' on '%s'"):format(enemyId, model:GetFullName()))
		return
	end

	-- Appearance
	applyLook(model, spec, model:GetAttribute("SkinKey"))

	-- Defaults / labels
	model:SetAttribute("enemyType", spec.enemyType or "Unknown")
	model:SetAttribute("AIProfile", spec.aiProfile or "")
	if spec.leashRadius and model:GetAttribute("LeashRadius") == nil then
		model:SetAttribute("LeashRadius", spec.leashRadius)
	end
	if spec.DEF ~= nil then model:SetAttribute("DEF", spec.DEF) end
	if spec.OFF ~= nil then model:SetAttribute("OFF", spec.OFF) end

	-- Stats
	if spec.stats then
		if spec.stats.WalkSpeed then hum.WalkSpeed = spec.stats.WalkSpeed end
		if spec.stats.JumpPower then hum.JumpPower = spec.stats.JumpPower end
	end

	-- Start controller (only if we actually resolved it)
	if Controller then
		local ok, err = pcall(function()
			Controller.Start(model, spec)
		end)
		if not ok then
			warn("[EnemyBootstrap] Controller.Start failed:", err)
		end
	else
		warn("[EnemyBootstrap] No Controller available; enemy will not act.")
	end

	model:SetAttribute("Bound", true)
end

-- ===== Initial sweep + live binding ========================================
for _, m in ipairs(ENEMY_ROOT:GetDescendants()) do
	if m:IsA("Model") then bind(m) end
end

ENEMY_ROOT.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") then bind(inst) end
end)
