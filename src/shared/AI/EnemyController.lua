-- ReplicatedStorage/AI/EnemyController.lua
local Players     = game:GetService("Players")
local RS          = game:GetService("ReplicatedStorage")
local RunService  = game:GetService("RunService")

local Attention   = require(RS:WaitForChild("AI"):WaitForChild("Attention"))
local Blackboard  = require(RS:WaitForChild("AI"):WaitForChild("Blackboard"))
local NodeSense   = require(RS:WaitForChild("NodeSense"))

-- Optional NodeLibrary adapter
local NL
do
	local libScript = game.ServerScriptService:FindFirstChild("NodeLibrary") or RS:FindFirstChild("NodeLibrary")
	if libScript then NL = require(libScript) end
end

-- === Moves (with NPC dodge fallback) ========================================
local Moves = {}

local function _charOf(actor)
	if typeof(actor) == "Instance" and actor:IsA("Model") then return actor end
	if typeof(actor) == "Instance" and actor:IsA("Player") then return actor.Character end
	return nil
end
local function _hrpOf(m) return m and m:FindFirstChild("HumanoidRootPart") end

function Moves.M1(actor)              if NL and NL.Punch      then NL.Punch(actor)          end end
function Moves.Heavy(actor)           if NL and NL.Heavy      then NL.Heavy(actor)          end end
function Moves.BlockStart(actor)      if NL and NL.BlockStart then NL.BlockStart(actor)      end end
function Moves.BlockEnd(actor)        if NL and NL.BlockEnd   then NL.BlockEnd(actor)        end end
function Moves.Revolver(actor, dir)   if NL and NL.Revolver   then NL.Revolver(actor, dir)   end end

-- Fallback Dodge: simple BodyVelocity burst (movement only; no iframes)
local function _fallbackDodgeBurst(actor, dirVec, dur)
	local ch  = _charOf(actor)
	local hrp = _hrpOf(ch)
	if not hrp then return end
	local dir = (dirVec and dirVec.Magnitude > 0) and dirVec.Unit or hrp.CFrame.LookVector
	local bv  = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e5, 0, 1e5)
	bv.P        = 1250
	bv.Velocity = dir * 50
	bv.Parent   = hrp
	task.delay(dur or 0.20, function() if bv then bv:Destroy() end end)
end

-- If NL expects a Player, pass it; otherwise pass the actor through.
local function _actorForNL(actor)
	if typeof(actor) == "Instance" and actor:IsA("Model") then
		return Players:GetPlayerFromCharacter(actor) or actor
	end
	return actor
end

-- Only skip fallback when NL.Dodge returns true explicitly.
function Moves.Dodge(actor, dirVec)
	if NL and NL.Dodge then
		local a = _actorForNL(actor)
		local ok, res = pcall(NL.Dodge, a, dirVec)
		if ok and res == true then
			return true
		end
	end
	_fallbackDodgeBurst(actor, dirVec, 0.22)
	return true
end

function Moves.DodgeAway(actorModel, fromPos)
	local hrp = actorModel and actorModel:FindFirstChild("HumanoidRootPart")
	if hrp and fromPos then
		local away = (hrp.Position - fromPos)
		if away.Magnitude > 0 then
			return Moves.Dodge(actorModel, away.Unit)
		end
	end
	return Moves.Dodge(actorModel)
end

-- === Controller =============================================================
local Controller = {}
Controller.__index = Controller

local function hrpOf(m) return m and m:FindFirstChild("HumanoidRootPart") end
local function humOf(m) return m and m:FindFirstChildOfClass("Humanoid") end
local function dist(a,b) return (a-b).Magnitude end
local function dir(from,to) local v=(to-from) local m=v.Magnitude return m>0 and (v/m) or v end
local function clamp01(x) return math.max(0, math.min(1, x)) end
local function lerp(a,b,t) return a + (b-a) * t end

-- DEF/OFF → timings/weights
local function reactDelayByDEF(def) return lerp(0.35, 0.06, clamp01(def/100)) end
local function blockProbByDEF(def)  return lerp(0.25, 0.95, clamp01(def/100)) end
local function dodgeProbByDEF(def)  return lerp(0.20, 0.90, clamp01(def/100)) end
local function tempoGapByOFF(off)   return lerp(0.60, 0.15, clamp01(off/100)) end
local function comboLenByOFF(off)   return math.floor(lerp(2, 5, clamp01(off/100)) + 0.5) end

local DEBUG = false
local function log(...) if DEBUG then print("[EnemyController]", ...) end end

-- === NodeSense → flags =======================================================
local function setIncoming(self, what, ttl) self.board:set(what, true, ttl or 0.6) end
local function clearIncoming(self)
	self.board:set("incomingHeavy",        false, 0.2)
	self.board:set("incomingUnblockable",  false, 0.2)
	self.board:set("incomingBlockable",    false, 0.2)
	self.board:set("incomingParryable",    false, 0.2)
	self.board:set("rangedThreat",         false, 0.2)
end

-- Treat any “breaks block” as an unblockable-level danger for dodge logic.
local function interpretIntent(self, node, tags, closeEnough)
	if not closeEnough then return end
	local lower = (node or "Unknown"):lower()
	if tags and next(tags) then
		if tags.Unblockable then setIncoming(self, "incomingUnblockable", 0.8) end
		if tags.Heavy       then setIncoming(self, "incomingHeavy", 0.8) end
		if tags.Ranged or tags.Projectile then setIncoming(self, "rangedThreat", 0.8) end
		if tags.BreaksBlock or tags.GuardBreak or tags.ShieldBreak then
			setIncoming(self, "incomingUnblockable", 0.8)
		end
		if tags.Blockable or tags.Melee or tags.M1 then
			setIncoming(self, "incomingBlockable", 0.6)
			if tags.Parryable then setIncoming(self, "incomingParryable", 0.6) end
		end
		return
	end
	if lower:find("heavy") then
		setIncoming(self, "incomingHeavy", 0.8)
	elseif (lower:find("guard") and lower:find("break")) or lower:find("shieldbreak") then
		setIncoming(self, "incomingUnblockable", 0.8)
	elseif lower:find("revolver") or lower:find("shot") or lower:find("bullet") then
		setIncoming(self, "rangedThreat", 0.8)
	elseif lower:find("punch") or lower:find("m1") then
		setIncoming(self, "incomingBlockable", 0.6)
		setIncoming(self, "incomingParryable", 0.6)
	end
end

local function interpretSense(self, payload)
	if not payload or payload.actorModel == self.rig then return end
	local myHRP = hrpOf(self.rig); if not myHRP then return end

	local aHRP = payload.actorModel and hrpOf(payload.actorModel)
	local closeEnough = (aHRP and dist(aHRP.Position, myHRP.Position) <= 18)

	local outcome = payload.context and payload.context.outcome
	local node    = tostring(payload.nodeName or "Unknown")
	local tags    = payload.tags

	-- Outcomes targeted at me
	local myPlr = Players:GetPlayerFromCharacter(self.rig)
	local myId  = myPlr and myPlr.UserId or self.rig:GetAttribute("UID")
	if payload.context and payload.context.targetId and myId and payload.context.targetId ~= myId then
		-- ignore
	else
		if outcome == "Hit" then
			self.attention:Hit(payload.actorModel or payload.actorUserId, payload.context.damage or 1)
			self.board:set("recentlyHitAt", os.clock(), 1.0)
		elseif outcome == "Blocked" then
			self.attention:BlockedBy(payload.actorModel or payload.actorUserId, payload.context.guardDamage or 5)
			self.board:set("recentlyBlockedAt", os.clock(), 1.0)
		elseif outcome == "Parried" then
			self.attention:ParriedBy(payload.actorModel or payload.actorUserId)
			self.board:set("parryWindow", true, 0.35)
		elseif outcome == "GuardBroken" then
			self.board:set("blocking", false, 1.0)
			self.board:set("guardBroken", true, 1.0)
		elseif outcome == "Miss" and payload.context and payload.context.reason == "IFrame" then
			self.board:set("baitRoll", true, 0.8)
		end
	end

	-- Intent (treat nil outcome and "AttackStart" as intent)
	if (not outcome and closeEnough) or outcome == "AttackStart" then
		interpretIntent(self, node, tags, closeEnough)
	end
	-- Clear intent on AttackEnd
	if outcome == "AttackEnd" then
		clearIncoming(self)
	end

	-- Defensive state echoes
	if outcome == "BlockStart" then
		self.board:set("blocking", true, 0.9)
	elseif outcome == "BlockEnd" then
		self.board:set("blocking", false, 0.2)
	elseif outcome == "ParryWindowStart" then
		self.board:set("parryWindow", true, 0.35)
	elseif outcome == "ParryWindowEnd" then
		self.board:set("parryWindow", false, 0.05)
	end
end

-- === lifecycle ==============================================================
function Controller.Start(rig: Model, spec: table)
	local self = setmetatable({
		rig = rig,
		spec = spec or {},
		DEF = rig:GetAttribute("DEF") or (spec and spec.DEF) or 25,
		OFF = rig:GetAttribute("OFF") or (spec and spec.OFF) or 30,
		attention = Attention.new({ halfLife = 1.7 }),
		board = Blackboard.new(),
		lastJump = 0,
		lastActionAt = 0,
		lastDodgeAt = -1,          -- local dodge cooldown
		isBlocking = false,
		connections = {},
		-- preferred distance band (don’t stand on top)
		rangeInner = 4.4,
		rangeKeep  = 4.5,
		rangeOuter = 4.6,
	}, Controller)

	self.leashObj  = rig:FindFirstChild("LeashPoint")
	self.leashPart = self.leashObj and self.leashObj.Value
	self.homeCF    = self.leashPart and self.leashPart.CFrame or rig:GetPivot()
	self.leashR    = rig:GetAttribute("LeashRadius") or 30
	self.aggroR    = rig:GetAttribute("AggroRadius") or 70

	local hum = humOf(rig); if hum then hum.AutoRotate = true end

	-- Subscribe to NodeSense server bus
	if NodeSense and NodeSense.ServerEvent and NodeSense.ServerEvent.Event then
		local conn = NodeSense.ServerEvent.Event:Connect(function(payload)
			interpretSense(self, payload)
		end)
		table.insert(self.connections, conn)
	end

	-- main loop
	local hb
	hb = RunService.Heartbeat:Connect(function(dt)
		if not self.rig.Parent then hb:Disconnect() return end
		Controller._tick(self, dt)
	end)
	table.insert(self.connections, hb)

	-- cleanup on death
	if hum then
		table.insert(self.connections, hum.Died:Connect(function()
			Controller.Stop(self)
		end))
	end

	return self
end

function Controller.Stop(self)
	for _, c in ipairs(self.connections or {}) do
		pcall(function() c:Disconnect() end)
	end
	self.connections = {}
end

-- === target & movement helpers =============================================
function Controller:_acquireTarget()
	local uid = self.attention:primary(0.3)
	if uid then
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr.UserId == uid and plr.Character and humOf(plr.Character) and humOf(plr.Character).Health > 0 then
				return plr.Character
			end
		end
	end
	local myHRP = hrpOf(self.rig); if not myHRP then return nil end
	local best, bd = nil, self.aggroR
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr.Character; local hrp = ch and hrpOf(ch)
		local hum = ch and humOf(ch)
		if hum and hum.Health > 0 and hrp then
			local d = dist(myHRP.Position, hrp.Position)
			if d < bd then best, bd = ch, d end
		end
	end
	return best
end

function Controller:_withinLeash()
	local p = hrpOf(self.rig); if not p then return true end
	local center = self.leashPart and self.leashPart.Position or self.homeCF.Position
	return dist(p.Position, center) <= (self.leashR + 5)
end

function Controller:_moveTo(pos) local h = humOf(self.rig); if h then h:MoveTo(pos) end end

-- keep a ring around the target; never stand on top
function Controller:_approachInBand(thrp)
	local myHRP = hrpOf(self.rig); if not (myHRP and thrp) then return end
	local myPos, tPos = myHRP.Position, thrp.Position
	local d  = dist(myPos, tPos)
	local dv = dir(tPos, myPos) -- vector from target → me

	if d > self.rangeOuter then
		-- approach, but stop at keep distance (do not MoveTo target directly)
		local dest = tPos + (-dir(tPos, myPos)) * self.rangeKeep
		self:_moveTo(dest)
	elseif d < self.rangeInner then
		-- too close → step back a little (spacing only; no dodge)
		local retreat = myPos + dv * (self.rangeInner - d + 1.0)
		self:_moveTo(retreat)
	end
	-- if inside the band, no MoveTo → we can attack/strafe
end

-- local dodge cooldown (used only for danger-dodge)
function Controller:_tryDodgeAway(thrpPos)
	local now = os.clock()
	if (now - (self.lastDodgeAt or -1)) < 1.25 then return false end
	self.lastDodgeAt = now
	Moves.DodgeAway(self.rig, thrpPos)
	return true
end

-- === decision loop ==========================================================
function Controller._tick(self, dt)
	local rig  = self.rig
	local myHRP = hrpOf(rig); local hum = humOf(rig)
	if not myHRP or not hum or hum.Health <= 0 then return end

	-- leash
	if not self:_withinLeash() then
		local homePos = (self.leashPart and self.leashPart.Position) or self.homeCF.Position
		self:_moveTo(homePos)
		return
	end

	local target = self:_acquireTarget()
	if not target then
		self:_moveTo(((self.leashPart and self.leashPart.Position) or self.homeCF.Position))
		return
	end
	local thrp = hrpOf(target); if not thrp then return end

	local d = dist(myHRP.Position, thrp.Position)
	local now = os.clock()

	-- soft hop only when far (prevents “jump on head” near)
	if d > 10 and now - self.lastJump > lerp(1.5, 3.5, 1 - clamp01(self.OFF/100)) then
		hum.Jump = true
		self.lastJump = now
	end

	-- read board
	local blocking        = self.board:get("blocking") == true
	local parryWindow     = self.board:get("parryWindow") == true
	local incomingHeavy   = self.board:get("incomingHeavy") == true
	local incomingUnblk   = self.board:get("incomingUnblockable") == true
	local incomingBlock   = self.board:get("incomingBlockable") == true
	local rangedThreat    = self.board:get("rangedThreat") == true
	local recentlyBlocked = (self.board:get("recentlyBlockedAt") ~= nil)

	-- === DODGE POLICY: ONLY on dangerous threats (Unblockable or Heavy) ===
	if incomingUnblk or incomingHeavy then
		if math.random() < dodgeProbByDEF(self.DEF) then
			task.delay(reactDelayByDEF(self.DEF), function()
				self:_tryDodgeAway(thrp.Position)
			end)
			return
		end
	end

	-- Block normal melee if appropriate
	if incomingBlock and d < 6 then
		if math.random() < blockProbByDEF(self.DEF) then
			task.delay(reactDelayByDEF(self.DEF), function()
				Moves.BlockStart(rig); self.isBlocking = true
				task.delay(lerp(0.3, 1.2, clamp01(self.DEF/100)), function()
					Moves.BlockEnd(rig); self.isBlocking = false
				end)
			end)
			return
		end
	end

	-- maintain distance band while waiting for tempo
	local gap = tempoGapByOFF(self.OFF)
	if now - self.lastActionAt < gap then
		self:_approachInBand(thrp)
		return
	end

	-- ranged pressure when far / during enemy parry
	if parryWindow or d > 14 or rangedThreat then
		Moves.Revolver(rig, dir(myHRP.Position, thrp.Position))
		self.lastActionAt = now
		return
	end

	-- punish blockers
	if (blocking or recentlyBlocked) and d <= 7 then
		if math.random() < lerp(0.2, 0.8, clamp01(self.OFF/100)) then
			Moves.Heavy(rig)
			self.lastActionAt = now
			return
		end
	end

	-- keep band, then attack
	self:_approachInBand(thrp)

	-- if outside inner band, we can choose to close one step before M1
	if d > self.rangeOuter then
		-- approach already handled above; wait a frame
		return
	end

	-- M1 burst (no automatic dodge-out anymore)
	local len = math.max(2, math.min(5, comboLenByOFF(self.OFF)))
	for i=1,len do
		if parryWindow then break end
		Moves.M1(rig)
		task.wait(lerp(0.16, 0.10, clamp01(self.OFF/100)))
	end
	self.lastActionAt = os.clock()
end

return Controller
