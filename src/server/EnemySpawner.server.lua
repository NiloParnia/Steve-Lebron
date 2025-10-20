-- ServerScriptService/EnemySpawner.server.lua  ✅ clean, self-contained
local ServerStorage = game:GetService("ServerStorage")

local ENEMY_PREFABS = ServerStorage:WaitForChild("Enemies")
local LEASHES       = workspace:FindFirstChild("EnemyLeashes")  -- folder of pads

local function ensureEnemiesFolder()
	local f = workspace:FindFirstChild("Enemies")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Enemies"
		f.Parent = workspace
	end
	return f
end

local ENEMY_ROOT = ensureEnemiesFolder()

local function topCenterCF(p: BasePart)
	return p.CFrame * CFrame.new(0, p.Size.Y/2 + 3, 0)
end

local function spawnFromFolder(folder: Instance, prefabName: string): Model?
	local src = folder:FindFirstChild(prefabName)
	return (src and src:Clone()) or nil
end

-- Helper: accept Folder or Model; find a Model and ensure PrimaryPart before pivot
local function findModelWithRoot(container)
    if container:IsA("Model") then return container end
    if container:IsA("Folder") then
        for _,child in ipairs(container:GetChildren()) do
            if child:IsA("Model") then return child end
        end
    end
    return nil
end

local function pivotAndFace(inst, cf)
    local mdl = findModelWithRoot(inst)
    if not mdl then
        warn("[Spawner] No model found to pivot for", inst:GetFullName())
        return
    end
    if not mdl.PrimaryPart then
        local hrp = mdl:FindFirstChild("HumanoidRootPart", true)
        if hrp and hrp:IsA("BasePart") then
            mdl.PrimaryPart = hrp
        else
            for _,d in ipairs(mdl:GetDescendants()) do
                if d:IsA("BasePart") then mdl.PrimaryPart = d; break end
            end
        end
    end
    if not mdl.PrimaryPart then
        warn("[Spawner] No PrimaryPart in model", mdl:GetFullName())
        return
    end
    mdl:PivotTo(cf)
end
	end
	rig:PivotTo(cf)
end

local function spawnEnemyAt(leash: BasePart, offset: CFrame?)
	local prefabName = leash:GetAttribute("Prefab")
	if not prefabName or prefabName == "" then
		warn("[EnemySpawner] Leash missing Prefab:", leash:GetFullName())
		return nil
	end

	local rig = spawnFromFolder(ENEMY_PREFABS, prefabName)
	if not rig then
		warn("[EnemySpawner] Enemy prefab not found:", prefabName)
		return nil
	end

	rig.Name   = prefabName
	rig.Parent = ENEMY_ROOT
	pivotAndFace(rig, topCenterCF(leash) * (offset or CFrame.new()))

	-- Identity & behavior (enemyId is your “enemy storyId”)
	local enemyId = leash:GetAttribute("EnemyId") or prefabName
	rig:SetAttribute("IsEnemy", true)
	rig:SetAttribute("enemyId", enemyId)

	-- Optional overrides
	local skinKey = leash:GetAttribute("SkinKey")
	if skinKey and skinKey ~= "" then rig:SetAttribute("SkinKey", skinKey) end

	rig:SetAttribute("LeashRadius", leash:GetAttribute("LeashRadius") or 30)
	rig:SetAttribute("ArenaId",     leash:GetAttribute("ArenaId") or "")

	-- Pointer back to the leash
	local leashRef = Instance.new("ObjectValue")
	leashRef.Name  = "LeashPoint"
	leashRef.Value = leash
	leashRef.Parent = rig

	-- Respawn (default true)
	local respawn = leash:GetAttribute("Respawn")
	if respawn == nil then respawn = true end
	if respawn then
		local hum = rig:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Died:Connect(function()
				local t = leash:GetAttribute("RespawnTime") or 10
				task.delay(t, function()
					if leash.Parent then spawnEnemyAt(leash) end
				end)
			end)
		end
	end

	print(("[EnemySpawner] ✅ Spawned %s at %s (enemyId=%s)")
		:format(prefabName, leash.Name, enemyId))
	return rig
end

-- ===== Boot =====
if not LEASHES then
	warn("[EnemySpawner] No 'EnemyLeashes' folder found in Workspace. Create one and add pads with attributes.")
	return
end

for _, leash in ipairs(LEASHES:GetChildren()) do
	if leash:IsA("BasePart") then
		local count = tonumber(leash:GetAttribute("Count")) or 1
		for i = 1, count do
			local angle = (i-1) * (math.pi * 2 / math.max(1, count))
			local off = CFrame.new(math.cos(angle) * 2, 0, math.sin(angle) * 2)
			spawnEnemyAt(leash, off)
		end
	end
end

