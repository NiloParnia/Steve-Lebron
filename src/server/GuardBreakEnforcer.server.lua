-- ServerScriptService/GuardBreakEnforcer.server.lua
-- Robust guard-break enforcement + anti-hold-F reblock during rearm.

local Players           = game:GetService("Players")
local RS                = game:GetService("ReplicatedStorage")

local NodeSense         = require(RS:WaitForChild("NodeSense"))
local CombatState       = require(RS:WaitForChild("CombatState"))
local DamageService     = require(RS:WaitForChild("DamageService"))
local StunService       = require(RS:WaitForChild("StunService"))
local CooldownService   = require(RS:WaitForChild("CooldownService"))
local SpeedController   = require(RS:WaitForChild("SpeedController"))
local GuardService      = require(RS:WaitForChild("GuardService"))

local GUARD_BREAK_STUN  = 0.45   -- hard-stun on break
local GUARD_BREAK_REARM = 1.10   -- cannot re-block during this window
local BASE_WALK         = 16     -- fallback for NPC models

local function asModel(ent)
	if typeof(ent) ~= "Instance" then return nil end
	if ent:IsA("Player") then return ent.Character end
	if ent:IsA("Model") then return ent end
	return nil
end

local function asPlayer(ent)
	if typeof(ent) ~= "Instance" then return nil end
	if ent:IsA("Player") then return ent end
	return Players:GetPlayerFromCharacter(ent)
end

local function humOf(ent)
	local m = asModel(ent)
	return m and m:FindFirstChildOfClass("Humanoid") or nil
end

-- Resolve the defender for a GuardBroken outcome, regardless of nodeName
local function resolveDefender(payload)
	-- Case A: guard events emitted from "Block" use the defender as actor
	if tostring(payload.nodeName) == "Block" then
		return payload.actorPlayer or payload.actorModel
	end

	-- Case B: emitted from the attacker node, target is in context.targetId
	local ctx = payload.context or {}
	if ctx.targetId then
		local plr = Players:GetPlayerByUserId(ctx.targetId)
		if plr then return plr end
	end

	-- Fallback: nearest blocking humanoid to the attacker (best-effort)
	local attackerModel = payload.actorModel
	local attackerHRP   = attackerModel and attackerModel:FindFirstChild("HumanoidRootPart")
	if not attackerHRP then return nil end

	local nearest, nd = nil, 10
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
		if hum and hrp and hum.Health > 0 then
			local d = (hrp.Position - attackerHRP.Position).Magnitude
			if d < nd and GuardService.IsBlocking(plr) then
				nearest, nd = plr, d
			end
		end
	end
	return nearest
end

local function forceUnblock(target)
	-- 1) End block + unlock + stop hold anim/track
	pcall(DamageService.EndBlock, target)
	pcall(CombatState.StopCurrentTrack, target)
	pcall(CombatState.Unlock, target, "GuardBroken")

	-- 2) Clear any block slow / restore speed
	local plr = asPlayer(target)
	if plr then
		pcall(SpeedController.Reset, plr)
	else
		local hum = humOf(target)
		if hum then hum.WalkSpeed = BASE_WALK end
	end

	-- 3) Brief hard-stun to sell the break
	pcall(StunService.Apply, target, GUARD_BREAK_STUN, { hard = true })

	-- 4) Re-arm cooldown so holding F can’t instantly re-block
	pcall(CooldownService.Apply, target, "BlockRearm", GUARD_BREAK_REARM)
end

-- If the player tries to BlockStart while BlockRearm is active, cancel it immediately.
local function cancelIllegalBlockStart(actor)
	if not actor then return end
	-- If they cannot use BlockRearm yet, they are still in rearm window.
	if not CooldownService.CanUse(actor, "BlockRearm") then
		-- Immediately force them out of block (prevents “hold F” exploit)
		forceUnblock(actor)
	end
end

-- Subscribe to NodeSense
if NodeSense.ServerEvent then
	NodeSense.ServerEvent.Event:Connect(function(payload)
		if not payload or not payload.context then return end
		local outcome = payload.context.outcome

		-- Enforce on GuardBroken from ANY node
		if outcome == "GuardBroken" then
			local defender = resolveDefender(payload)
			if defender then
				forceUnblock(defender)
			else
				warn("[GuardBreakEnforcer] GuardBroken without resolvable defender for node=", payload.nodeName)
			end
			return
		end

		-- Stop illegal re-block attempts during rearm
		if outcome == "BlockStart" then
			local actor = payload.actorPlayer or payload.actorModel
			cancelIllegalBlockStart(actor)
		end
	end)
else
	warn("[GuardBreakEnforcer] NodeSense.ServerEvent not available; enforcer inactive.")
end
