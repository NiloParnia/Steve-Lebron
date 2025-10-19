-- InputHandler (LocalScript) — mount-aware, ROOT-FIX version
-- Teardown actions (e.g., BlockEnd) always pass, even if mounted/stunned/locked.

local Players            = game:GetService("Players")
local UserInputService   = game:GetService("UserInputService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local localPlayer        = Players.LocalPlayer
local RemoteFolder       = ReplicatedStorage:WaitForChild("RemoteEvents")

-- === Remotes ===
local ActivateNode       = RemoteFolder:WaitForChild("ActivateNode")
local ConfirmSuccess     = RemoteFolder:WaitForChild("ConfirmSuccess")
local StunToggle         = RemoteFolder:WaitForChild("StunToggle")
local LockMoves          = RemoteFolder:WaitForChild("LockMoves") -- bool

-- === Game state ===
local CombatState        = require(ReplicatedStorage:WaitForChild("CombatState"))

-- === Debug ===
local DEBUG              = false
local function DebugLog(...) if DEBUG then print("[InputHandler]", ...) end end

-- === State ===
local isStunned          = false
local MOVES_LOCKED       = false
local holdingBlock       = false

-- === Teardown that must always pass ===
local ALWAYS_ALLOW_TEARDOWN = {
	BlockEnd = true,
}

-- === Flags from server ===
StunToggle.OnClientEvent:Connect(function(flag)
	isStunned = flag and true or false
	DebugLog("Stun ->", isStunned)
end)

LockMoves.OnClientEvent:Connect(function(locked)
	MOVES_LOCKED = locked and true or false
	DebugLog("LockMoves ->", MOVES_LOCKED)
	-- Do NOT clear holdingBlock here; we will always send BlockEnd on key-up.
end)

-- === Cooldowns ===
local cooldowns = {}
local pendingCooldowns = {}

local function offCooldown(action)
	return (cooldowns[action] or 0) < tick()
end

ConfirmSuccess.OnClientEvent:Connect(function(actionName)
	local pending = pendingCooldowns[actionName]
	if pending then
		cooldowns[actionName] = tick() + pending.time
		pendingCooldowns[actionName] = nil
	end
end)

-- === Gate (teardown bypass) ===
local function canAct(actionName)
	if actionName and ALWAYS_ALLOW_TEARDOWN[actionName] then
		return true, "teardown"
	end
	if MOVES_LOCKED then return false, "mounted" end
	if isStunned   then return false, "stunned" end
	if CombatState.IsLocked(localPlayer) then return false, "combat-locked" end
	return true
end

-- === Fire helper ===
local function triggerAction(actionName, cooldownTime, extraData, bypassCooldown)
	local ok, why = canAct(actionName)
	if not ok then
		DebugLog(("BLOCKED %s (reason: %s)"):format(actionName, why))
		return
	end
	if bypassCooldown or offCooldown(actionName) then
		DebugLog("📤 Fire:", actionName, "extra:", extraData)
		ActivateNode:FireServer(actionName, extraData)
		if cooldownTime and cooldownTime > 0 then
			pendingCooldowns[actionName] = { time = cooldownTime, issuedAt = tick() }
		end
	else
		DebugLog(("On cooldown: %s (%.2fs left)"):format(
			actionName, math.max(0, (cooldowns[actionName] or 0) - tick())
			))
	end
end

-- === INPUTS ===
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	-- Normal actions respect gates
	local ok = canAct()
	if not ok then
		DebugLog("InputBegan swallowed due to state gate")
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		triggerAction("Punch", 0.5)

	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		triggerAction("Heavy", 2.0)

	elseif input.KeyCode == Enum.KeyCode.F then
		-- Try to start block; if state-gated, no harm—server will ignore.
		if not holdingBlock and offCooldown("Block") then
			holdingBlock = true
			triggerAction("BlockStart")
		end

	elseif input.KeyCode == Enum.KeyCode.Q then
		triggerAction("Dodge", 1.0)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	-- ROOT FIX: Always send BlockEnd on F key-up, regardless of local state.
	if input.KeyCode == Enum.KeyCode.F then
		holdingBlock = false
		triggerAction("BlockEnd", 0) -- teardown bypasses gates in canAct("BlockEnd")
	end
end)

