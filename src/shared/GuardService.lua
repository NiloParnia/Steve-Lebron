-- GuardService  (ReplicatedStorage)
-- Guard meter with block/regen/break + NodeSense outcome emits.
-- Compatible with DamageService.Apply/DealDamage and AttackStateService.
-- Extras: sets debug attributes "Blocking" (bool) and "Guard" (0..MAX)

-------------------------------------------------- CONFIG
local MAX_GUARD      = 50
local REGEN_PER_SEC  = 5
local BREAK_STUN     = 2.5

-------------------------------------------------- SERVICES
local Players        = game:GetService("Players")
local RS             = game:GetService("ReplicatedStorage")

local CombatState    = require(RS:WaitForChild("CombatState"))
local StunService    = require(RS:WaitForChild("StunService"))
local SpeedController= require(RS:WaitForChild("SpeedController"))
local NodeSense      = require(RS:WaitForChild("NodeSense"))

-------------------------------------------------- STATE
local GuardService   = {}
local guardHP        = {}   -- [entity(Player|Model)] = current guard
local isBlocking     = {}   -- [entity] = true while holding block

-------------------------------------------------- HELPERS
local function getHumanoid(entity)
	if typeof(entity) ~= "Instance" then return nil end
	if entity:IsA("Player") then
		local c = entity.Character
		return c and c:FindFirstChildOfClass("Humanoid")
	elseif entity:IsA("Model") then
		return entity:FindFirstChildOfClass("Humanoid")
	end
end

local function getPlayerFromEntity(entity)
	if typeof(entity) ~= "Instance" then return nil end
	if entity:IsA("Player") then return entity end
	if entity:IsA("Model") then
		return Players:GetPlayerFromCharacter(entity)
	end
	return nil
end

local function getUserId(entity)
	local plr = getPlayerFromEntity(entity)
	return plr and plr.UserId or nil
end

local function ensureInit(ent)
	if guardHP[ent] == nil then guardHP[ent] = MAX_GUARD end
end

local function setAttrs(ent)
	-- purely debug/UX; harmless if unused
	local hp = guardHP[ent]
	if typeof(ent) == "Instance" and ent.Parent then
		pcall(function()
			ent:SetAttribute("Blocking", isBlocking[ent] == true)
			if hp ~= nil then
				ent:SetAttribute("Guard", math.clamp(hp, 0, MAX_GUARD))
			end
		end)
	end
end

-------------------------------------------------- API
function GuardService.StartBlock(entity)
	if not entity then return end
	ensureInit(entity)
	isBlocking[entity] = true
	setAttrs(entity)

	-- Optional: broadcast block state for AI blackboards
	NodeSense.EmitOutcome(entity, "Block", "BlockStart", {
		targetId = getUserId(entity),
	})
end

function GuardService.EndBlock(entity)
	if not entity then return end
	isBlocking[entity] = nil
	setAttrs(entity)

	NodeSense.EmitOutcome(entity, "Block", "BlockEnd", {
		targetId = getUserId(entity),
	})
end

function GuardService.GetPercent(entity)
	return (guardHP[entity] or MAX_GUARD) / MAX_GUARD
end

-- Preferred signature:
--   ApplyGuardDamage(attacker, defender, rawDamage, nodeName)
-- Legacy signature (still supported):
--   ApplyGuardDamage(defender, rawDamage [, nodeName])
-- Returns: nil | "blocked" | "break"
function GuardService.ApplyGuardDamage(a, b, c, d)
	local attacker, defender, rawDamage, nodeName

	-- Detect signature based on argument types
	if typeof(a) == "Instance" and typeof(b) == "Instance" and type(c) == "number" then
		-- New signature
		attacker  = a
		defender  = b
		rawDamage = c
		nodeName  = (type(d) == "string") and d or nil
	else
		-- Legacy
		attacker  = nil
		defender  = a
		rawDamage = b
		nodeName  = (type(c) == "string") and c or nil
	end

	if not defender or type(rawDamage) ~= "number" then return nil end
	if not isBlocking[defender] then return nil end

	ensureInit(defender)

	-- Drain guard (rawDamage may be 0; that's fine — still "Blocked")
	guardHP[defender] = (guardHP[defender] or MAX_GUARD) - rawDamage
	setAttrs(defender)

	local defUserId = getUserId(defender)
	local nn = nodeName or "Unknown"

	if guardHP[defender] > 0 then
		-- Blocked but not broken
		NodeSense.EmitOutcome(attacker, nn, "Blocked", {
			targetId    = defUserId,
			guardDamage = rawDamage,
		})
		return "blocked"
	else
		-- Broke guard
		GuardService.Break(defender)

		NodeSense.EmitOutcome(attacker, nn, "GuardBroken", {
			targetId    = defUserId,
			guardDamage = rawDamage,
		})
		return "break"
	end
end

function GuardService.Break(entity)
	if not entity then return end
	ensureInit(entity)

	isBlocking[entity] = nil
	guardHP[entity]    = 0
	setAttrs(entity)

	-- Reset any movement modifiers
	if entity:IsA("Player") then
		SpeedController.Reset(entity)
	end

	-- Stop looping block animation
	if entity:IsA("Player") then
		CombatState.StopCurrentTrack(entity)   -- drops hold pose
	else
		local hum = getHumanoid(entity)
		if hum then
			for _, track in ipairs(hum:GetPlayingAnimationTracks()) do
				local anim = track.Animation
				if anim and anim.AnimationId == "rbxassetid://72122053405063" then -- HOLD anim ID
					track:Stop()
				end
			end
		end
	end

	-- Apply stun on break
	StunService.Apply(entity, BREAK_STUN)
end

-- Optional helpers for NPCs
function GuardService.RegisterEntity(model)
	if typeof(model) == "Instance" then
		guardHP[model] = MAX_GUARD
		isBlocking[model] = nil
		setAttrs(model)
	end
end

function GuardService.UnregisterEntity(model)
	guardHP[model]   = nil
	isBlocking[model]= nil
	if typeof(model) == "Instance" then
		pcall(function()
			model:SetAttribute("Blocking", nil)
			model:SetAttribute("Guard", nil)
		end)
	end
end

-------------------------------------------------- REGEN LOOP
task.spawn(function()
	while true do
		task.wait(1)
		for ent, hp in pairs(guardHP) do
			if typeof(ent) == "Instance" and ent.Parent == nil then
				-- Clean up dead references
				guardHP[ent]    = nil
				isBlocking[ent] = nil
			elseif not isBlocking[ent] and hp < MAX_GUARD then
				guardHP[ent] = math.min(MAX_GUARD, hp + REGEN_PER_SEC)
				setAttrs(ent)
			end
		end
	end
end)

-------------------------------------------------- LIFECYCLE
local function resetGuard(ent)
	guardHP[ent]    = MAX_GUARD
	isBlocking[ent] = nil
	setAttrs(ent)
end

Players.PlayerAdded:Connect(function(plr)
	resetGuard(plr)
	plr.CharacterAdded:Connect(function() resetGuard(plr) end)
end)

Players.PlayerRemoving:Connect(function(plr)
	guardHP[plr]    = nil
	isBlocking[plr]  = nil
end)

-------------------------------------------------- QUERIES
function GuardService.IsBlocking(entity)
	return isBlocking[entity] == true
end

function GuardService.IsGuardBroken(entity)
	return (guardHP[entity] or MAX_GUARD) <= 0
end

return GuardService
