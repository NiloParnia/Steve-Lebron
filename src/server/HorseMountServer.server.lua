-- ServerScriptService/HorseMountServer.lua
-- W = throttle, Space = jump, Q (client) = gallop (spends DodgeCharge), R = dismount.

-- ========= Animation IDs =========
local WALK_ANIM_ID   = "rbxassetid://81146949344342"
local JUMP_ANIM_ID   = "rbxassetid://98771585060096"
local GALLOP_ANIM_ID = "rbxassetid://83469750908764" -- loop during gallop

-- ========= Services / Deps =========
local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local Workspace   = game:GetService("Workspace")
local RunService  = game:GetService("RunService")

local CombatState       = require(RS:WaitForChild("CombatState"))
local DodgeCharges      = require(RS:WaitForChild("DodgeChargeService"))
local PlayerDataService = require(game:GetService("ServerScriptService"):WaitForChild("PlayerDataService"))

-- ========= Remotes (auto-created) =========
local Remotes = RS:FindFirstChild("RemoteEvents") or Instance.new("Folder", RS)
Remotes.Name = "RemoteEvents"

local function ensureRemote(name)
	local r = Remotes:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = Remotes end
	return r
end

local RE_Face      = ensureRemote("Horse_Face")
local RE_Move      = ensureRemote("Horse_Move")
local RE_Jump      = ensureRemote("Horse_Jump")
local RE_Dismount  = ensureRemote("Horse_RequestDismount")
local RE_LockMoves = ensureRemote("LockMoves")
local RE_Gallop    = ensureRemote("Horse_Gallop")
local ConfirmSuccess = ensureRemote("ConfirmSuccess") -- ensure it's present for toasts

-- ========= Defaults (per-horse Attributes can override) =========
local SEAT_NAME               = "SaddleSeat"
local DEFAULT_SPEED           = 32
local DEFAULT_JUMP_POWER      = 30
local DEFAULT_JUMP_IMPULSE    = 60
local DEFAULT_JUMP_COOLDOWN   = 1.0

local REQUIRE_GROUND_TO_JUMP  = true
local DEFAULT_SURFACE_YAW_DEG = -90
local DEFAULT_FORWARD_BASIS   = "Left"
local DEFAULT_GROUND_RAY      = 12

local DEFAULT_FRICTION_K      = 2.5
local FRICTION_BOOST_VALUE    = 1.25

-- Gallop
local DEFAULT_GALLOP_MULT     = 2.0   -- BaseSpeed * mult
local DEFAULT_GALLOP_DURATION = 1.5   -- seconds per charge

-- Display
local PLAYER_HORSE_NAME       = "Get That Call"

-- mounts[player] = {...}
local mounts = {}

-- ========= Logging =========
local DEBUG = true
local function slog(st, ...) if (st and st.debug) or DEBUG then print("[HORSE]", ...) end end
local function swarn(st, ...) if (st and st.debug) or DEBUG then warn("[HORSE]", ...) end end

-- ========= Helpers =========
local function findHorseFromSeat(seat: Instance)
	if not (seat and seat:IsA("Seat") and seat.Name == SEAT_NAME) then return nil end
	local m = seat:FindFirstAncestorOfClass("Model")
	if m and m:GetAttribute("IsHorse") then return m end
	return nil
end

local function ensureHumanoid(horse: Model)
	local hum = horse:FindFirstChildOfClass("Humanoid")
	if not hum then hum = Instance.new("Humanoid", horse) end
	hum.AutoRotate   = false
	hum.UseJumpPower = true
	hum.WalkSpeed    = horse:GetAttribute("BaseSpeed") or DEFAULT_SPEED
	hum.JumpPower    = horse:GetAttribute("HorseJumpPower") or DEFAULT_JUMP_POWER
	return hum
end

local function buildFacingConstraint(horse: Model)
	local root = horse.PrimaryPart or horse:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return end

	local att0 = root:FindFirstChild("_HorseA0")
	if not att0 then
		att0 = Instance.new("Attachment")
		att0.Name = "_HorseA0"
		att0.CFrame = CFrame.new()
		att0.Parent = root
	end

	local sensorPart = Instance.new("Part")
	sensorPart.Name = "_HorseSensor"
	sensorPart.Size = Vector3.new(0.2, 0.2, 0.2)
	sensorPart.Transparency = 1
	sensorPart.CanCollide = false
	sensorPart.Anchored = true
	sensorPart.CFrame = root.CFrame
	sensorPart.Parent = Workspace

	local sensorAtt = Instance.new("Attachment")
	sensorAtt.Name = "_HorseA1"
	sensorAtt.Parent = sensorPart

	local ao = Instance.new("AlignOrientation")
	ao.Name = "_HorseFace"
	ao.Attachment0 = att0
	ao.Attachment1 = sensorAtt
	ao.RigidityEnabled = true
	ao.Responsiveness = 200
	pcall(function() ao.MaxTorque = math.huge end)
	ao.Parent = root

	return ao, att0, sensorPart, sensorAtt
end

local function setMovesLocked(player: Player, locked: boolean)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then hum:SetAttribute("Mounted", locked) end
	if locked then
		CombatState.Lock(player)
		pcall(function() CombatState.StopCurrentTrack(player) end)
	else
		CombatState.Unlock(player)
		pcall(function() CombatState.SetUnlockBuffer(player, 0.2) end)
	end
	RE_LockMoves:FireClient(player, locked)
end

local function applyFrictionBoost(st, enable: boolean)
	if st.frictionApplied == enable then return end
	st.frictionApplied = enable
	if enable then st._origPhys = st._origPhys or {} end
	for _, d in ipairs(st.horse:GetDescendants()) do
		if d:IsA("BasePart") then
			if enable then
				if not st._origPhys[d] then st._origPhys[d] = d.CustomPhysicalProperties end
				local cp = d.CustomPhysicalProperties
				local density    = (cp and cp.Density) or 1
				local elasticity = (cp and cp.Elasticity) or 0
				local friction   = math.max(FRICTION_BOOST_VALUE, (cp and cp.Friction) or 0.3)
				d.CustomPhysicalProperties = PhysicalProperties.new(density, friction, elasticity, 1, 1)
			else
				d.CustomPhysicalProperties = st._origPhys[d]
			end
		end
	end
	if not enable then st._origPhys = nil end
end

local function cleanupMount(st)
	if st.hbConn then st.hbConn:Disconnect() end
	if st.stateConn then st.stateConn:Disconnect() end
	if st.watch then for _, c in ipairs(st.watch) do pcall(function() c:Disconnect() end) end end
	if st.ao then st.ao:Destroy() end
	if st.att0 then st.att0:Destroy() end
	if st.sensorAtt then st.sensorAtt:Destroy() end
	if st.sensorPart then st.sensorPart:Destroy() end

	for _, track in ipairs({st.gallopTrack, st.walkTrack, st.jumpTrack}) do
		if track then pcall(function() track:Stop(0.1); track:Destroy() end) end
	end
	st.gallopTrack, st.walkTrack, st.jumpTrack = nil, nil, nil

	pcall(function()
		if st.horse then
			local hum = st.horse:FindFirstChildOfClass("Humanoid")
			if hum then hum.DisplayName = st.origDisplayName or "" end
			if st.origModelName then st.horse.Name = st.origModelName end
		end
	end)

	st.baseSpeed = st.nominalSpeed or DEFAULT_SPEED
	applyFrictionBoost(st, false)
end

local function forceDismountSeat(seat: Seat, st)
	local occ = seat.Occupant
	if occ then
		occ.Sit = false
		pcall(function() seat:Sit(nil) end)
		pcall(function() occ.Jump = true end)
	end
	local weld = seat:FindFirstChild("SeatWeld"); if weld then weld:Destroy() end
	if occ and occ.Parent then
		local hrp = occ.Parent:FindFirstChild("HumanoidRootPart")
		if hrp then hrp.CFrame = hrp.CFrame + Vector3.new(0, 3, 0) end
	end
end

local function dismount(player: Player)
	local st = mounts[player]
	
	if not st then return end

	if st.riderHum then
		pcall(function()
			st.riderHum:SetStateEnabled(Enum.HumanoidStateType.Jumping, st.riderJumpingEnabled ~= false)
			st.riderHum.AutoJumpEnabled = (st.riderAutoJump == true)
			st.riderHum.Sit = false
			st.riderHum.Jump = true
		end)
	end

	local hHum = st.horse and st.horse:FindFirstChildOfClass("Humanoid")
	if hHum then hHum:Move(Vector3.zero) end
	if st.seat and st.seat:IsA("Seat") then forceDismountSeat(st.seat, st) end

	cleanupMount(st)
	setMovesLocked(player, false)
	mounts[player] = nil
end

Players.PlayerRemoving:Connect(dismount)

-- Grounded check
local function isGrounded(hum: Humanoid?, root: BasePart?, rayLen: number)
	if hum and hum.FloorMaterial ~= Enum.Material.Air then return true end
	if not root then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {root.Parent}
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -rayLen, 0), params)
	return hit ~= nil
end

-- Verify rider
local function isCurrentRider(player: Player, st): boolean
	if not (st and st.seat and st.seat.Occupant) then return false end
	local occChar = st.seat.Occupant.Parent
	return occChar == (player.Character or nil)
end

-- ========= Anim state chooser =========
local function updateMoveAnim(st)
	if not st then return end
	local now = os.clock()
	local galloping = (st.gallopUntil or 0) > now and st.throttle

	if not st.throttle then
		if st.gallopTrack and st.gallopTrack.IsPlaying then st.gallopTrack:Stop(0.12) end
		if st.walkTrack   and st.walkTrack.IsPlaying   then st.walkTrack:Stop(0.12)   end
		return
	end

	if galloping then
		if st.walkTrack   and st.walkTrack.IsPlaying       then st.walkTrack:Stop(0.10) end
		if st.gallopTrack and not st.gallopTrack.IsPlaying then st.gallopTrack:Play(0.10, 1, 1.0) end
	else
		if st.gallopTrack and st.gallopTrack.IsPlaying     then st.gallopTrack:Stop(0.10) end
		if st.walkTrack   and not st.walkTrack.IsPlaying   then st.walkTrack:Play(0.12, 1, 1.0)   end
	end
end

-- ========= Orientation stream =========
RE_Face.OnServerEvent:Connect(function(player: Player, horse: Model, sensorCF: CFrame)
	local st = mounts[player]
	if not (st and st.horse == horse and isCurrentRider(player, st)) then return end
	local root = st.horse.PrimaryPart or st.horse:FindFirstChild("HumanoidRootPart")
	if not (root and st.sensorPart) then return end
	if typeof(sensorCF) ~= "CFrame" then return end

	local f = sensorCF.LookVector; f = Vector3.new(f.X, 0, f.Z)
	if f.Magnitude < 1e-3 then f = Vector3.new(0,0,-1) else f = f.Unit end

	local base = CFrame.lookAt(root.Position, root.Position + f, Vector3.yAxis)
	local modelOffset   = math.rad(st.horse:GetAttribute("YawOffsetDeg") or 0)
	local surfaceOffset = math.rad(st.horse:GetAttribute("SurfaceYawOffsetDeg") or DEFAULT_SURFACE_YAW_DEG)
	st.sensorPart.CFrame = base * CFrame.Angles(0, modelOffset + surfaceOffset, 0)
end)

-- ========= Move (W) =========
RE_Move.OnServerEvent:Connect(function(player: Player, horse: Model, forwardDown: boolean)
	local st = mounts[player]
	if not (st and st.horse == horse and isCurrentRider(player, st)) then return end
	st.throttle = forwardDown and true or false
	updateMoveAnim(st)
end)

-- ========= Jump (Space) =========
RE_Jump.OnServerEvent:Connect(function(player: Player)
	local st = mounts[player]
	if not (st and isCurrentRider(player, st)) then return end
	slog(st, "Jump remote received")

	local now = time()
	local cd = st.horse:GetAttribute("HorseJumpCooldown")
	if cd == nil then cd = DEFAULT_JUMP_COOLDOWN end
	if (st.nextJumpTime or 0) > now then return end

	local hum  = st.horse:FindFirstChildOfClass("Humanoid")
	local root = st.horse.PrimaryPart or st.horse:FindFirstChild("HumanoidRootPart")
	if not hum then swarn(st, "Jump aborted: no horse Humanoid"); return end

	local requireGround = st.horse:GetAttribute("RequireGroundToJump")
	if requireGround == nil then requireGround = REQUIRE_GROUND_TO_JUMP end
	local rayLen = st.horse:GetAttribute("JumpGroundRay") or DEFAULT_GROUND_RAY

	if (not requireGround) or isGrounded(hum, root, rayLen) then
		st.nextJumpTime = now + cd
		hum.Jump = true
		if st.jumpTrack then pcall(function() st.jumpTrack:Play(0.05, 1, 1.0) end) end
		hum:ChangeState(Enum.HumanoidStateType.Jumping)
		if root then
			local mult = st.horse:GetAttribute("HorseJumpImpulse") or DEFAULT_JUMP_IMPULSE
			local mass = root.AssemblyMass or 100
			root:ApplyImpulse(Vector3.new(0, mass * mult, 0))
		end
	end
end)

-- ========= Gallop (spends DodgeCharge) =========
local function startOrExtendGallop(player: Player, st)
	if not st or not st.horse then return end
	local mult = st.horse:GetAttribute("GallopMult");     if mult == nil then mult = DEFAULT_GALLOP_MULT end
	local dur  = st.horse:GetAttribute("GallopDuration"); if dur  == nil then dur  = DEFAULT_GALLOP_DURATION end

	st.baseSpeed   = (st.nominalSpeed or DEFAULT_SPEED) * mult
	local now      = os.clock()
	st.gallopUntil = math.max(st.gallopUntil or 0, now + dur)

	st.gallopToken = (st.gallopToken or 0) + 1
	local myTok    = st.gallopToken

	updateMoveAnim(st)

	task.delay(dur, function()
		if mounts[player] == st and st.gallopToken == myTok and os.clock() >= (st.gallopUntil or 0) then
			st.baseSpeed = st.nominalSpeed or DEFAULT_SPEED
			updateMoveAnim(st)
		end
	end)
end

-- ===== UX toasts (rate-limited) =====
local _toastAt = setmetatable({}, { __mode = "k" })
local function toast(player, msg)
	local now, last = os.clock(), _toastAt[player] or 0
	if (now - last) < 1.0 then return end -- 1s cooldown for any toast
	_toastAt[player] = now
	ConfirmSuccess:FireClient(player, { ok = false, msg = msg })
end

RE_Gallop.OnServerEvent:Connect(function(player: Player)
	-- If this prints, the client actually fired the remote:
	print("[HORSE] RE_Gallop from", player.Name)

	local st = mounts[player]
	if not st then
		toast(player, "You must be mounted to gallop.")
		return
	end
	if not isCurrentRider(player, st) then
		toast(player, "You must be mounted to gallop.")
		return
	end

	-- Durable unlock gate (ProfileService-backed). Attribute fallback for legacy.
	local hasUnlock = false
	local ok, res = pcall(function() return PlayerDataService.HasUnlock(player, "Gallop") end)
	if ok then hasUnlock = res end
	if not hasUnlock and player:GetAttribute("HasGallop") ~= true then
		toast(player, "You haven't learned Gallop yet.")
		return
	end

	-- Shared charge pool with dodge:
	if not DodgeCharges.CanDodge(player) then
		toast(player, "No stamina to gallop.")
		return
	end
	if not DodgeCharges.Consume(player) then
		toast(player, "No stamina to gallop.")
		return
	end

	startOrExtendGallop(player, st)
end)

-- ========= Dismount (R) =========
RE_Dismount.OnServerEvent:Connect(function(player: Player)
	print("[HORSE] RE_Dismount from", player.Name)
	dismount(player)
end)

-- ========= Seat watcher (mount/dismount) =========
local function hookSeat(seat: Seat)
	if seat:GetAttribute("HorseSeatHooked") then return end
	seat:SetAttribute("HorseSeatHooked", true)

	seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local horse = findHorseFromSeat(seat)
		if not horse then return end

		local occ = seat.Occupant
		if occ and occ.Parent then
			local player = Players:GetPlayerFromCharacter(occ.Parent)
			if not player then return end

			if mounts[player] then dismount(player) end

			local hum = ensureHumanoid(horse)
			local ao, att0, sensorPart, sensorAtt = buildFacingConstraint(horse)

			-- Animator + tracks
			local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator", hum)

			local walkAnim = Instance.new("Animation"); walkAnim.AnimationId = WALK_ANIM_ID
			local walk = animator:LoadAnimation(walkAnim); walk.Looped = true

			local jumpAnim = Instance.new("Animation"); jumpAnim.AnimationId = JUMP_ANIM_ID
			local jump = animator:LoadAnimation(jumpAnim); jump.Looped = false

			local galAnim = Instance.new("Animation"); galAnim.AnimationId = GALLOP_ANIM_ID
			local gallop = animator:LoadAnimation(galAnim); gallop.Looped = true

			for _, d in ipairs(horse:GetDescendants()) do if d:IsA("BasePart") then d.Anchored = false end end
			if horse.PrimaryPart then pcall(function() horse.PrimaryPart:SetNetworkOwner(nil) end) end

			local riderHum = occ
			local prevJump, prevAuto = true, true
			pcall(function()
				prevJump = riderHum:GetStateEnabled(Enum.HumanoidStateType.Jumping)
				prevAuto = riderHum.AutoJumpEnabled
				riderHum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
				riderHum.AutoJumpEnabled = false
			end)

			local prevModelName = horse.Name
			local prevDisplay   = hum.DisplayName
			pcall(function() hum.DisplayName = PLAYER_HORSE_NAME end)

			local debug     = horse:GetAttribute("DebugHorse")
			local basisAttr = tostring(horse:GetAttribute("ForwardBasis") or DEFAULT_FORWARD_BASIS)
			local baseSpeed = horse:GetAttribute("BaseSpeed") or DEFAULT_SPEED

			local st = {
				horse = horse, seat = seat,
				nominalSpeed = baseSpeed,
				baseSpeed    = baseSpeed,
				forwardBasis = basisAttr,
				frictionK    = horse:GetAttribute("FrictionImpulseK") or DEFAULT_FRICTION_K,
				debug = (debug == nil) and true or (debug == true),

				ao = ao, att0 = att0, sensorPart = sensorPart, sensorAtt = sensorAtt,

				riderHum = riderHum, riderJumpingEnabled = prevJump, riderAutoJump = prevAuto,

				throttle = false, wasThrottle = false, hbConn = nil,
				frictionApplied = false, _origPhys = nil,

				walkTrack = walk, jumpTrack = jump, gallopTrack = gallop,
				stateConn = nil,

				nextJumpTime = 0,
				gallopUntil  = 0, gallopToken = 0,

				origModelName = prevModelName, origDisplayName = prevDisplay,
				watch = {},
			}

			-- Stop jump anim when we land
			st.stateConn = hum.StateChanged:Connect(function(_, new)
				if new == Enum.HumanoidStateType.Landed then
					if st.jumpTrack and st.jumpTrack.IsPlaying then st.jumpTrack:Stop(0.1) end
				end
			end)

			-- Auto-dismount watchers
			local function autoDismount(reason)
				if mounts[player] then slog(st, "Auto-dismount ("..reason..")"); dismount(player) end
			end
			table.insert(st.watch, horse.AncestryChanged:Connect(function(_, parent) if parent == nil then autoDismount("horse destroyed") end end))
			table.insert(st.watch, seat.AncestryChanged:Connect(function(_, parent)  if parent == nil then autoDismount("seat destroyed")  end end))

			local char = player.Character
			if char then
				local pHum = char:FindFirstChildOfClass("Humanoid")
				if pHum then table.insert(st.watch, pHum.Died:Connect(function() autoDismount("player died") end)) end
				table.insert(st.watch, char.AncestryChanged:Connect(function(_, parent) if parent == nil then autoDismount("character removed") end end))
			end

			slog(st, "Mounted. Speed=", st.baseSpeed, " Basis=", st.forwardBasis, " FricK=", st.frictionK)

			-- SERVER HEARTBEAT: clamp velocity, braking, friction
			st.hbConn = RunService.Heartbeat:Connect(function()
				if not st or not st.horse then return end
				local root = st.horse.PrimaryPart or st.horse:FindFirstChild("HumanoidRootPart")
				local hHum = st.horse:FindFirstChildOfClass("Humanoid")
				if not (root and hHum) then return end

				-- Make forward vector from basis
				local f = (function()
					if st.forwardBasis == "Right" then return root.CFrame.RightVector
					elseif st.forwardBasis == "Left" then return -root.CFrame.RightVector
					elseif st.forwardBasis == "Back" then return -root.CFrame.LookVector
					else return root.CFrame.LookVector end
				end)()
				f = Vector3.new(f.X, 0, f.Z); if f.Magnitude > 0 then f = f.Unit end

				local speed  = st.baseSpeed or DEFAULT_SPEED
				local target = st.throttle and (f * speed) or Vector3.zero

				local v = root.AssemblyLinearVelocity
				local horiz = Vector3.new(v.X, 0, v.Z)

				-- On W release: exact cancel + friction boost
				if st.wasThrottle and (not st.throttle) then
					local mass = root.AssemblyMass or 100
					local k    = st.frictionK or DEFAULT_FRICTION_K
					local cancelImpulse = -horiz * mass * k
					root:ApplyImpulse(cancelImpulse)
					applyFrictionBoost(st, true)
				end

				-- Clamp horizontal velocity
				local tx = math.abs(target.X) < 1e-5 and 0 or target.X
				local tz = math.abs(target.Z) < 1e-5 and 0 or target.Z
				root.AssemblyLinearVelocity = Vector3.new(tx, v.Y, tz)

				if not st.throttle then
					local rayLen   = st.horse:GetAttribute("JumpGroundRay") or DEFAULT_GROUND_RAY
					local grounded = isGrounded(hHum, root, rayLen)
					local v2       = root.AssemblyLinearVelocity
					local h2       = Vector3.new(v2.X, 0, v2.Z)
					local vyThresh = st.horse:GetAttribute("StopVYThreshold") or 0.75

					if grounded or h2.Magnitude > 0.02 then
						local vy = (math.abs(v2.Y) < vyThresh) and 0 or v2.Y
						root.AssemblyLinearVelocity = Vector3.new(0, vy, 0)
					end

					-- Kill tiny spin; keep yaw
					local av = root.AssemblyAngularVelocity
					root.AssemblyAngularVelocity = Vector3.new(0, av.Y, 0)
					hHum:Move(Vector3.zero)
				else
					if st.frictionApplied then applyFrictionBoost(st, false) end
				end

				-- Drive animations continuously
				updateMoveAnim(st)
				st.wasThrottle = st.throttle
			end)

			setMovesLocked(player, true)
			mounts[player] = st
		else
			for p, st in pairs(mounts) do
				if st.seat == seat then slog(st, "Seat emptied → dismount"); dismount(p); break end
			end
		end
	end)
end

local function scan(scope: Instance)
	for _, inst in ipairs(scope:GetDescendants()) do
		if inst:IsA("Seat") and inst.Name == SEAT_NAME then
			if findHorseFromSeat(inst) then hookSeat(inst) end
		end
	end
end

scan(Workspace)
Workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("Seat") and inst.Name == SEAT_NAME then
		if findHorseFromSeat(inst) then hookSeat(inst) end
	end
end)

-- Horse Attributes:
--   IsHorse=true (required)
--   BaseSpeed (number) [default 32]
--   HorseJumpPower (number) [default 30]
--   HorseJumpImpulse (number) [default 60]
--   HorseJumpCooldown (number) [default 1.0]
--   RequireGroundToJump (bool) [default true]
--   YawOffsetDeg (number) [default 0]
--   SurfaceYawOffsetDeg (number) [default -90]
--   ForwardBasis "Look"|"Right"|"Left"|"Back" [default "Left"]
--   JumpGroundRay (number) [default 12]
--   FrictionImpulseK (number) [default 2.5]
--   DebugHorse (bool) [default true]
--   GallopMult (number) [default 2.0]
--   GallopDuration (number seconds) [default 1.5]
