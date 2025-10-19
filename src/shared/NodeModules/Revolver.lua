--------------------------------------------------------------------
-- NodeModules/Revolver.lua (lock + interrupt aware, with prop fallback)
-- NodeFactory-driven revolver
-- Obeys CombatState.IsLocked and AttackStateService interruption.
--------------------------------------------------------------------
local RS      = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Debris  = game:GetService("Debris")

local NodeFactory        = require(RS:WaitForChild("NodeFactory"))
local CooldownService    = require(RS:WaitForChild("CooldownService"))
local CombatState        = require(RS:WaitForChild("CombatState"))
local AttackStateService = require(RS:WaitForChild("AttackStateService"))
local NodeSense          = require(RS:WaitForChild("NodeSense"))

local RemoteEvents   = RS:WaitForChild("RemoteEvents")
local CooldownNotice = RemoteEvents:WaitForChild("CooldownNotice")

--------------------------------------------------------------------
-- CONFIG
--------------------------------------------------------------------
local SHOT_COUNT        = 4
local SHOT_INTERVAL     = 0.2
local FIRST_SHOT_DELAY  = 0.2

local BULLET_SPEED      = 150
local BULLET_LIFETIME   = 15
local VIS_SIZE          = 0.2
local HIT_RADIUS        = 1

local COOLDOWN_TIME     = 15
local ANIM_ID           = "rbxassetid://95110526176115"

-- side offset (studs) so it appears from right hand side
local SIDE_OFFSET       = 1

-- Optional: name/path for gun prop template
local GUN_PROP_NAME     = "GunProp"

--------------------------------------------------------------------
-- Helpers: lock/interrupt gates
--------------------------------------------------------------------
local function isInterrupted(player: Player?, char: Model?): boolean
	-- 1) Global move lock (horse/combat lock, etc.)
	if player and CombatState and CombatState.IsLocked and CombatState.IsLocked(player) then
		return true
	end

	-- 2) AttackStateService interruption
	if AttackStateService and type(AttackStateService.IsInterrupted) == "function" then
		local ok, res = pcall(AttackStateService.IsInterrupted, player) -- use player, not char
		if ok and res then return true end
	end

	-- 3) Lightweight fallbacks
	if char then
		if char:GetAttribute("Interrupted") or char:GetAttribute("Stunned") then
			return true
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			if hum.Health <= 0 then return true end
			local st = hum:GetState()
			if st == Enum.HumanoidStateType.Dead
				or st == Enum.HumanoidStateType.Ragdoll
				or st == Enum.HumanoidStateType.FallingDown then
				return true
			end
		end
	end

	return false
end

--------------------------------------------------------------------
-- Node definition
--------------------------------------------------------------------
local RevolverNode = NodeFactory.Create({
	Name             = "Revolver",

	UseMovingHitbox  = true,
	Radius           = HIT_RADIUS,
	Lifetime         = 10,   -- hitbox lifetime per bullet (not the visual)
	OneShot          = true,
	DestroyOnHit     = true,

	GetCFrame        = function(bullet) return bullet.CFrame end,
	LinkedParts      = function(bullet) return { bullet } end,

	Damage           = 5,
	GuardDamage      = 10,
	Parryable        = true,

	Stun             = 0.1,
	KnockbackForce   = 20,

	Cooldown         = 0    -- module handles its own cooldown gating
})

local module = {}

--------------------------------------------------------------------
-- Gun prop resolution + attach/detach
--------------------------------------------------------------------
local function resolveGunPropTemplate(): Instance?
	-- 1) Direct child
	local m = RS:FindFirstChild(GUN_PROP_NAME)
	if m and m:IsA("Model") then return m end

	-- 2) Common folders
	for _, folderName in ipairs({ "Props", "Assets", "Models" }) do
		local f = RS:FindFirstChild(folderName)
		if f then
			local c = f:FindFirstChild(GUN_PROP_NAME)
			if c and c:IsA("Model") then return c end
		end
	end

	-- 3) Deep search (one-time, cheap enough)
	for _, d in ipairs(RS:GetDescendants()) do
		if d:IsA("Model") and d.Name == GUN_PROP_NAME then
			return d
		end
	end

	warn("[REVOLVER] GunProp template not found in ReplicatedStorage")
	return nil
end

local function getRightHandSocket(char: Model): BasePart?
	return char:FindFirstChild("RightHand")
		or char:FindFirstChild("Right Arm")
		or char:FindFirstChild("RightArm")
end

local function attachGunProp(char: Model, template: Instance?): (Instance?, Instance?)
	if not (char and template and template:IsA("Model")) then return nil end

	local socket = getRightHandSocket(char)
	if not (socket and socket:IsA("BasePart")) then return nil end

	local prop = template:Clone()
	prop.Name = GUN_PROP_NAME
	prop.Parent = char

	local handle = prop:FindFirstChild("Handle")
	if not (handle and handle:IsA("BasePart")) then
		warn("[REVOLVER] GunProp has no BasePart 'Handle'")
		prop:Destroy()
		return nil
	end

	for _, d in ipairs(prop:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.Massless = true
			if d ~= handle then
				local wc = Instance.new("WeldConstraint")
				wc.Part0 = handle
				wc.Part1 = d
				wc.Parent = handle
			end
		end
	end

	-- Clean old grip
	local oldGrip = socket:FindFirstChild("GunGrip")
	if oldGrip then oldGrip:Destroy() end

	-- Attach
	local grip = Instance.new("Motor6D")
	grip.Name  = "GunGrip"
	grip.Part0 = socket
	grip.Part1 = handle
	grip.C0    = CFrame.new()
	grip.C1    = CFrame.new(0, -0.05, -0.12) * CFrame.Angles(0, 45, math.rad(180))
	grip.Parent = socket

	return prop, grip
end

local function detachGunProp(char: Model)
	local rh = getRightHandSocket(char)
	if rh then
		local grip = rh:FindFirstChild("GunGrip")
		if grip then grip:Destroy() end
	end
	local prop = char and char:FindFirstChild(GUN_PROP_NAME)
	if prop then prop:Destroy() end
end

--------------------------------------------------------------------
-- Entry point
--------------------------------------------------------------------
function module.OnStart(player, dirVec)
	-- Resolve character/root
	local char = player and player.Character
	if not char then return end
	local hrp  = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	-- 🔒 Abort immediately if locked or interrupted
	if isInterrupted(player, char) then return end

	-- Local cooldown for the whole volley
	if not CooldownService.CanUse(player, "Revolver") then return end
	CooldownService.Apply(player, "Revolver", COOLDOWN_TIME)
	CooldownNotice:FireClient(player, {
		name = "Revolver",
		duration = COOLDOWN_TIME,
		started = os.clock(),
	})

	-- 🔔 Intent ping (before volley)
	local tags = NodeSense.CollectTags(RevolverNode, {
		Ranged           = true,
		Projectile       = true,
		UsesMovingHitbox = true,
		Blockable        = true,
		Parryable        = RevolverNode.Parryable,
	})
	NodeSense.Emit(player, "Revolver", tags, {
		nodeName    = "Revolver",
		damage      = RevolverNode.Damage,
		guardDamage = RevolverNode.GuardDamage,
		stun        = RevolverNode.Stun,
		kbForce     = RevolverNode.KnockbackForce,
		shotIndex   = 0, -- intent marker (pre-volley)
	})

	-- Resolve prop template once (before any waits)
	local propTemplate = resolveGunPropTemplate()

	-- Play animation once
	local hum = char:FindFirstChildOfClass("Humanoid")
	local track
	local propAttached = false

	if hum then
		local anim = Instance.new("Animation")
		anim.AnimationId = ANIM_ID
		track = hum:LoadAnimation(anim)
		track:Play()

		-- Register with CombatState so global interrupts/locks can stop it
		pcall(function() CombatState.RegisterTrack(player, track) end)

		-- If the anim has markers, use them
		track:GetMarkerReachedSignal("draw"):Connect(function()
			if not propAttached and not isInterrupted(player, char) then
				local prop = attachGunProp(char, propTemplate)
				if prop then propAttached = true end
			end
		end)
		track:GetMarkerReachedSignal("holster"):Connect(function()
			detachGunProp(char)
			propAttached = false
		end)
		track.Stopped:Connect(function()
			detachGunProp(char)
			propAttached = false
		end)
	end

	-- Normalize direction (fallback HRP forward)
	local dir = (typeof(dirVec)=="Vector3" and dirVec.Magnitude>0) and dirVec.Unit or hrp.CFrame.LookVector

	-- First-shot delay (cancel if interrupted/locked meanwhile)
	local t0 = os.clock()
	while os.clock() - t0 < FIRST_SHOT_DELAY do
		if isInterrupted(player, char) then
			detachGunProp(char)
			pcall(function() if track then track:Stop() end end)
			return
		end
		task.wait()
	end

	-- Fallback: if no marker has attached the prop yet, attach now
	if not propAttached and propTemplate and not isInterrupted(player, char) then
		local prop = attachGunProp(char, propTemplate)
		if prop then propAttached = true end
	end

	-- Fire volley
	for i = 1, SHOT_COUNT do
		-- 🔒 Check before each shot
		if isInterrupted(player, char) then
			detachGunProp(char)
			pcall(function() if track then track:Stop() end end)
			return
		end

		-- Origin from hand if possible
		local hand = getRightHandSocket(char)
		local originPos = hand and hand.Position or hrp.Position
		local aimCF = CFrame.lookAt(originPos, originPos + dir, Vector3.yAxis)
		local spawnPos = originPos + (dir * 2) + (aimCF.RightVector * SIDE_OFFSET)

		-- Visual bullet
		local bullet = Instance.new("Part")
		bullet.Name       = "RevolverBullet"
		bullet.Shape      = Enum.PartType.Ball
		bullet.Size       = Vector3.new(VIS_SIZE, VIS_SIZE, VIS_SIZE)
		bullet.CFrame     = CFrame.lookAt(spawnPos, spawnPos + dir)
		bullet.Color      = Color3.new(0,0,0)
		bullet.Material   = Enum.Material.Metal
		bullet.CanCollide = false
		bullet.Anchored   = false
		bullet.Parent     = workspace

		local bv = Instance.new("BodyVelocity")
		bv.MaxForce = Vector3.new(1e5,1e5,1e5)
		bv.Velocity = dir * BULLET_SPEED
		bv.Parent   = bullet

		Debris:AddItem(bullet, BULLET_LIFETIME)
		Debris:AddItem(bv,     BULLET_LIFETIME)

		-- Execute node (NodeFactory will also run its own guards)
		RevolverNode:Execute(hrp, bullet)

		-- Interval (cancel during wait)
		if i < SHOT_COUNT then
			local t = os.clock()
			while os.clock() - t < SHOT_INTERVAL do
				if isInterrupted(player, char) then
					detachGunProp(char)
					pcall(function() if track then track:Stop() end end)
					return
				end
				task.wait()
			end
		end
	end

	-- Ensure cleanup even if the anim keeps playing
	detachGunProp(char)
end

return module
