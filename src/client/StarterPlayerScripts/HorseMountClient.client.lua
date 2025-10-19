-- StarterPlayerScripts/HorseMountClient.client.lua
-- While mounted:
--   W          = throttle
--   Space      = jump
--   Q          = GALLOP (spends a DodgeCharge)  ← overrides your normal Q-dodge
--   R          = dismount
-- On dismount, we unbind and your regular Q-dodge works again.

local Players       = game:GetService("Players")
local RS            = game:GetService("ReplicatedStorage")
local RunService    = game:GetService("RunService")
local CAS           = game:GetService("ContextActionService")

local player        = Players.LocalPlayer

-- === Remotes ===
local RE            = RS:WaitForChild("RemoteEvents")
local RE_Face       = RE:WaitForChild("Horse_Face")
local RE_Move       = RE:WaitForChild("Horse_Move")
local RE_Jump       = RE:WaitForChild("Horse_Jump")
local RE_Dismount   = RE:WaitForChild("Horse_RequestDismount")
local RE_Gallop     = RE:WaitForChild("Horse_Gallop")

-- === Config ===
local SEAT_NAME     = "SaddleSeat"
local GALLOP_KEY    = Enum.KeyCode.Q    -- ← replace your dodge key here if different
local PRIORITY      = (Enum.ContextActionPriority.High.Value or 2000) + 1
local DEBUG         = false
local function dprint(...) if DEBUG then print("[HorseClient]", ...) end end

-- === State ===
local mountedHorse: Model? = nil
local forwardDown          = false
local faceConn             = nil

-- === Helpers ===
local function isHorseSeat(seat: Instance?): boolean
	if not (seat and seat:IsA("Seat") and seat.Name == SEAT_NAME) then return false end
	local model = seat:FindFirstAncestorOfClass("Model")
	return model and model:GetAttribute("IsHorse") == true or false
end

local function flat(vec: Vector3): Vector3
	local f = Vector3.new(vec.X, 0, vec.Z)
	return (f.Magnitude > 1e-3) and f.Unit or Vector3.new(0,0,-1)
end

local function sensorCF(): CFrame
	local char = player.Character
	if not (char and char.Parent) then return CFrame.new() end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return CFrame.new() end
	local cam = workspace.CurrentCamera
	local look = cam and cam.CFrame.LookVector or hrp.CFrame.LookVector
	local pos  = hrp.Position
	return CFrame.lookAt(pos, pos + flat(look), Vector3.yAxis)
end

-- === Controls ===
local function bindControls()
	dprint("Bind controls (W/Space/Q/R)")

	CAS:BindAction("Horse_Forward", function(_, state)
		if not mountedHorse then return Enum.ContextActionResult.Sink end
		if state == Enum.UserInputState.Begin then
			if not forwardDown then
				forwardDown = true
				RE_Move:FireServer(mountedHorse, true)
			end
		elseif state == Enum.UserInputState.End then
			if forwardDown then
				forwardDown = false
				RE_Move:FireServer(mountedHorse, false)
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.W)

	CAS:BindAction("Horse_Jump", function(_, state)
		if not mountedHorse then return Enum.ContextActionResult.Sink end
		if state == Enum.UserInputState.Begin then
			RE_Jump:FireServer()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.Space)

	-- IMPORTANT: Use BindActionAtPriority so we PREEMPT your normal Q-dodge while mounted.
	CAS:BindActionAtPriority("Horse_Gallop_Q", function(_, state)
		if not mountedHorse then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then
			RE_Gallop:FireServer()
		end
		return Enum.ContextActionResult.Sink -- swallow so your dodge handler never sees Q while mounted
	end, false, PRIORITY, GALLOP_KEY)

	CAS:BindAction("Horse_Dismount", function(_, state)
		if not mountedHorse then return Enum.ContextActionResult.Sink end
		if state == Enum.UserInputState.Begin then
			RE_Dismount:FireServer()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.R)
end

local function unbindControls()
	dprint("Unbind controls")
	CAS:UnbindAction("Horse_Forward")
	CAS:UnbindAction("Horse_Jump")
	CAS:UnbindAction("Horse_Gallop_Q")
	CAS:UnbindAction("Horse_Dismount")
	forwardDown = false
end

-- Stream facing every frame while mounted
local function startFaceStream()
	if faceConn then return end
	faceConn = RunService.RenderStepped:Connect(function()
		if mountedHorse then
			RE_Face:FireServer(mountedHorse, sensorCF())
		end
	end)
end
local function stopFaceStream()
	if faceConn then faceConn:Disconnect() end
	faceConn = nil
end

-- === Seat hooks ===
local function onSeated(active: boolean, seatPart: BasePart?)
	if active and seatPart and isHorseSeat(seatPart) then
		mountedHorse = seatPart:FindFirstAncestorOfClass("Model")
		dprint("Mounted", mountedHorse and mountedHorse.Name or "?")
		bindControls()
		startFaceStream()
	else
		dprint("Unmounted")
		unbindControls()
		stopFaceStream()
		mountedHorse = nil
	end
end

local function onCharacterAdded(char: Model)
	local hum = char:WaitForChild("Humanoid")
	hum.Seated:Connect(onSeated)
	-- If we spawn already seated
	if hum.SeatPart and isHorseSeat(hum.SeatPart) then
		onSeated(true, hum.SeatPart)
	end
end

if player.Character then onCharacterAdded(player.Character) end
player.CharacterAdded:Connect(onCharacterAdded)
