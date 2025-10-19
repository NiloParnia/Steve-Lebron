-- KnockbackService  (ReplicatedStorage)
-- Applies physics impulses while respecting Guard, I-frames, and Hyper-Armor.

local KnockbackService = {}

------------------------------ DEPENDENCIES
local Players            = game:GetService("Players")
local RS                 = game:GetService("ReplicatedStorage")
local IFrameStore        = require(RS:WaitForChild("IFrameStore"))
local GuardService       = require(RS:WaitForChild("GuardService"))
local AttackStateService = require(RS:WaitForChild("AttackStateService"))

------------------------------ TUNING
local POWER = 5          -- base multiplier (tune to taste)
local DEBUG = false
local function d(...) if DEBUG then print("[Knockback]", ...) end end

------------------------------ HELPERS
local function rootOf(ent)
	if typeof(ent) ~= "Instance" then return nil end
	if ent:IsA("Player") then
		local c = ent.Character
		return c and c:FindFirstChild("HumanoidRootPart")
	elseif ent:IsA("Model") then
		return ent:FindFirstChild("HumanoidRootPart")
	end
end

local function asEntity(x)
	if typeof(x) ~= "Instance" then return nil end
	if x:IsA("Player") or x:IsA("Model") then return x end
	return nil
end

------------------------------ CORE
-- @param target  Player | Model
-- @param dir     Vector3  — direction FROM attacker TO target
-- @param force   number   — base force (scaled by POWER & mass)
-- @param dur     number   — seconds before we zero linear velocity (default 0.3)
function KnockbackService.Apply(target, dir, force, dur)
	target = asEntity(target)
	if not target then return end
	if typeof(dir) ~= "Vector3" or dir.Magnitude == 0 then return end

	------------------------------------------------------------------
	--  Immunity Checks
	------------------------------------------------------------------
	-- Hard invincibility attribute (works for Players & Models)
	if target.GetAttribute and target:GetAttribute("Invincible") then
		return
	end

	-- Blocking negates knockback. (Guard-broken NO LONGER cancels knockback.)
	if GuardService and GuardService.IsBlocking and GuardService.IsBlocking(target) then
		d("IMMUNE: Blocking", target)
		return
	end

	-- I-frames (players only)
	if target:IsA("Player") and IFrameStore.IsActive(target) then
		return
	end

	-- Hyper-Armor (if your AttackStateService tracks it)
	if AttackStateService.HasHyperArmor and AttackStateService.HasHyperArmor(target) then
		d("IMMUNE: HyperArmor", target)
		return
	end

	------------------------------------------------------------------
	--  Physics Impulse
	------------------------------------------------------------------
	local root = rootOf(target)
	if not root then return end

	-- Ensure server controls physics for deterministic result
	local prevOwner = root:GetNetworkOwner()
	if prevOwner then root:SetNetworkOwner(nil) end
	if root.Anchored then root.Anchored = false end

	local impulse = dir.Unit * (force or 1) * POWER * root:GetMass()
	d("Impulse", impulse)
	root:ApplyImpulse(impulse)

	-- Optional slide stop + restore previous network owner
	local stopAfter = dur or 0.3
	if stopAfter > 0 then
		task.delay(stopAfter, function()
			if root and root.Parent then
				root.AssemblyLinearVelocity = Vector3.zero
				if prevOwner and prevOwner.Parent then
					pcall(function() root:SetNetworkOwner(prevOwner) end)
				end
			end
		end)
	end
end

return KnockbackService
