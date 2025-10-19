-- ServerScriptService/CollisionGroups.server.lua
-- Disable collisions between player characters and enemy NPC rigs
-- using the modern CollisionGroups API.

local Players        = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")

local GROUP_PLAYER = "Players"
local GROUP_ENEMY  = "Enemies"

-- Create/register groups (idempotent)
pcall(function() PhysicsService:RegisterCollisionGroup(GROUP_PLAYER) end)
pcall(function() PhysicsService:RegisterCollisionGroup(GROUP_ENEMY)  end)

-- Players <-> Enemies: do NOT collide
PhysicsService:CollisionGroupSetCollidable(GROUP_PLAYER, GROUP_ENEMY, false)

-- Helper: apply a collision group to all BaseParts in a model and keep it updated
local function watchModelCollisionGroup(model: Model, groupName: string)
	-- initial pass
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.CollisionGroup = groupName
		end
	end
	-- keep future parts in sync (accessories, cloned tools, etc.)
	model.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") then
			inst.CollisionGroup = groupName
		end
	end)
end

-- Treat any Model with IsEnemy=true as an enemy
local function isEnemyModel(m: Instance)
	return m:IsA("Model") and m:GetAttribute("IsEnemy") == true
end

-- Players -> GROUP_PLAYER
local function hookPlayer(plr: Player)
	local function onChar(char: Model)
		watchModelCollisionGroup(char, GROUP_PLAYER)
	end
	if plr.Character then onChar(plr.Character) end
	plr.CharacterAdded:Connect(onChar)
end

Players.PlayerAdded:Connect(hookPlayer)
for _, plr in ipairs(Players:GetPlayers()) do
	hookPlayer(plr)
end

-- Enemies -> GROUP_ENEMY
-- Apply immediately for existing enemies
for _, inst in ipairs(workspace:GetDescendants()) do
	if isEnemyModel(inst) then
		watchModelCollisionGroup(inst, GROUP_ENEMY)
	end
end

-- Watch for new enemy models or models that flip IsEnemy later
workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Model") then
		-- If attribute appears/changes later
		inst:GetAttributeChangedSignal("IsEnemy"):Connect(function()
			if inst:GetAttribute("IsEnemy") == true then
				watchModelCollisionGroup(inst, GROUP_ENEMY)
			end
		end)
		-- If already tagged
		if isEnemyModel(inst) then
			watchModelCollisionGroup(inst, GROUP_ENEMY)
		end
	end
end)
