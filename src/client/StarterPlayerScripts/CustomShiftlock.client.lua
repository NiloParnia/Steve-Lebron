-- CustomShiftlock.client.lua (two-attachment AO; camera-facing yaw or no lock)
-- Make sure StarterPlayer.EnableMouseLockOption = false (disables Roblox default shiftlock).

local Players    = game:GetService("Players")
local UIS        = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")

local player = Players.LocalPlayer
local cam    = Workspace.CurrentCamera

-- ========= CONFIG =========
local LOCK_MOUSE   = true      -- center mouse while locked
local SHOW_CURSOR  = false
local LOCK_BODY    = true      -- << set to false to NOT rotate body; still toggles mouse lock

-- ========= STATE =========
local isLocked = false
local char, hum, hrp
local att0        -- Attachment on HRP
local ao          -- AlignOrientation on HRP
local aimPart     -- invisible anchored part we rotate to camera yaw
local aimAtt      -- Attachment on aimPart

-- ========= UTILS =========
local function flat(v: Vector3)
	local f = Vector3.new(v.X, 0, v.Z)
	return (f.Magnitude > 1e-4) and f.Unit or Vector3.new(0,0,-1)
end

local function setMouseLock(on: boolean)
	if not UIS.MouseEnabled then return end
	UIS.MouseBehavior    = (on and LOCK_MOUSE) and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
	UIS.MouseIconEnabled = (not on) or SHOW_CURSOR
end

-- Build/remove constraint (TWO-ATTACHMENT mode ensures world-yaw matches camera)
local function ensureConstraint()
	if not (LOCK_BODY and hrp) then return end

	if not aimPart then
		aimPart = Instance.new("Part")
		aimPart.Name = "_ShiftlockAim"
		aimPart.Size = Vector3.new(0.2, 0.2, 0.2)
		aimPart.Anchored = true
		aimPart.CanCollide = false
		aimPart.Transparency = 1
		aimPart.CFrame = hrp.CFrame
		aimPart.Parent = Workspace
	end
	if not aimAtt then
		aimAtt = Instance.new("Attachment")
		aimAtt.Name = "_ShiftlockA1"
		aimAtt.Parent = aimPart
	end
	if not att0 then
		att0 = Instance.new("Attachment")
		att0.Name = "_ShiftlockA0"
		att0.Parent = hrp
	end
	if not ao then
		ao = Instance.new("AlignOrientation")
		ao.Name = "_ShiftlockAO"
		ao.Attachment0 = att0
		ao.Attachment1 = aimAtt
		ao.RigidityEnabled = true      -- crisp lock
		ao.Responsiveness  = 200       -- snappy
		ao.ReactionTorqueEnabled = false
		-- Be generous with torque if your character is heavy:
		pcall(function() ao.MaxTorque = math.huge end)
		ao.Parent = hrp
	end
end

local function destroyConstraint()
	if ao then ao:Destroy(); ao = nil end
	if att0 then att0:Destroy(); att0 = nil end
	if aimAtt then aimAtt:Destroy(); aimAtt = nil end
	if aimPart then aimPart:Destroy(); aimPart = nil end
end

-- ========= ALIGN LOOP =========
local BIND = "CustomShiftlockAlign_TwoAttach"

local function alignStep()
	if not isLocked then return end
	if LOCK_BODY and not (hum and hrp and ao and aimPart) then return end
	if not cam then return end

	-- Skip physics-hostile states
	local st = hum and hum:GetState()
	if st == Enum.HumanoidStateType.Seated
		or st == Enum.HumanoidStateType.Dead
		or st == Enum.HumanoidStateType.Ragdoll then
		return
	end

	-- Update the (invisible) aimPart’s orientation to camera yaw.
	-- Using hrp.Position keeps the yaw intuitive; position doesn't matter for AO.
	local f = flat(cam.CFrame.LookVector)
	if LOCK_BODY and aimPart then
		local pos = hrp and hrp.Position or aimPart.Position
		aimPart.CFrame = CFrame.lookAt(pos, pos + f, Vector3.yAxis)
	end
end

local function bindLoop()
	RunService:BindToRenderStep(BIND, Enum.RenderPriority.Last.Value, alignStep)
end

local function unbindLoop()
	pcall(function() RunService:UnbindFromRenderStep(BIND) end)
end

-- ========= TOGGLE =========
local function setLocked(on: boolean)
	isLocked = on
	if hum then hum.AutoRotate = not (on and LOCK_BODY) end
	if char then char:SetAttribute("CustomShiftlock", on and LOCK_BODY) end

	if on then
		if LOCK_BODY then ensureConstraint() end
		setMouseLock(true)
		bindLoop()
	else
		setMouseLock(false)
		unbindLoop()
		destroyConstraint()
	end
end

-- ========= CHARACTER LIFECYCLE =========
local function onCharacter(c: Model)
	char = c
	hum  = c:WaitForChild("Humanoid")
	hrp  = c:WaitForChild("HumanoidRootPart")
	if isLocked then
		if LOCK_BODY then ensureConstraint() end
		hum.AutoRotate = not (LOCK_BODY)
	end
end
player.CharacterAdded:Connect(onCharacter)
if player.Character then onCharacter(player.Character) end

player.CharacterRemoving:Connect(function()
	unbindLoop()
	destroyConstraint()
	setMouseLock(false)
end)

-- ========= SHIFT TOGGLE =========
UIS.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if UIS:GetFocusedTextBox() then return end
	if input.KeyCode ~= Enum.KeyCode.LeftShift and input.KeyCode ~= Enum.KeyCode.RightShift then return end
	setLocked(not isLocked)
end)

-- Safety cleanup
script.AncestryChanged:Connect(function(_, parent)
	if not parent then
		unbindLoop()
		destroyConstraint()
		setMouseLock(false)
	end
end)
