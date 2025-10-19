-- AttackStateService  (ReplicatedStorage)
--
-- Tracks per-player attack phases so delayed hit logic can be cancelled
-- if the attacker is interrupted. Also supports:
--   • Hyper-Armor  – ignore interrupts (stun / hit-stagger).
--   • Move I-frames – grant temporary invulnerability at startup.
--
-- Emits NodeSense outcomes (server-side safe):
--   AttackStart            { duration? }
--   AttackEnd              { result = "Completed" | "Canceled" | "Interrupted" }
--   Interrupted            { reason = "Interrupt" }
--   HyperArmorStart/End    { reason? }
--
-- Usage inside a Node (e.g., Heavy):
--   AttackStateService.Start(player, {
--     duration   = 0.55,
--     hyperArmor = true,
--     iFrames    = 0.4,
--     nodeName   = "Heavy"    -- optional, for nicer telemetry labels
--   })
--   task.delay(0.55, function()
--     -- ✅ gate on IsActive so any cancel before impact stops the hit
--     if AttackStateService.IsActive and not AttackStateService.IsActive(player) then return end
--     -- deal damage here
--     AttackStateService.Clear(player)
--   end)
---------------------------------------------------------------------

local AttackStateService = {}

------------------------------ SERVICES
local Players           = game:GetService("Players")
local RS                = game:GetService("ReplicatedStorage")
local IFrameStore       = require(RS:WaitForChild("IFrameStore"))
local NodeSense         = require(RS:WaitForChild("NodeSense"))

------------------------------ STATE
-- [player] = {
--   interrupted = false,
--   hyperArmor  = false,
--   endTask     = task handle or nil,
--   nodeName    = "Attack",
--   startedAt   = os.clock(),
-- }
local attackState = {}

------------------------------ INTERNAL
local function emit(player, nodeName, outcome, ctx)
	-- Safe on client: NodeSense no-ops there; server will broadcast.
	pcall(function()
		NodeSense.EmitOutcome(player, nodeName or "Attack", outcome, ctx or {})
	end)
end

local function endAttackInternal(player, result, reason)
	local st = attackState[player]
	if not st then return end
	-- cancel timer
	if st.endTask then
		pcall(task.cancel, st.endTask)
	end

	-- Hyper armor ends when the attack ends
	if st.hyperArmor then
		emit(player, st.nodeName, "HyperArmorEnd", { reason = reason or result })
	end

	-- Finalize with AttackEnd
	emit(player, st.nodeName, "AttackEnd", { result = result or "Canceled" })

	attackState[player] = nil
end

------------------------------ PUBLIC API

-- params:
--   • duration    (number) – seconds until attack naturally ends
--   • hyperArmor  (bool)   – immune to interruption
--   • iFrames     (number) – grant i-frames at start
--   • nodeName    (string) – optional label for telemetry
function AttackStateService.Start(player, params)
	if not player then return end

	-- Clear any previous attack (treat as canceled)
	if attackState[player] then
		endAttackInternal(player, "Canceled", "Restart")
	end

	local cfg = params or {}
	local nodeName = tostring(cfg.nodeName or cfg.name or "Attack")

	attackState[player] = {
		interrupted = false,
		hyperArmor  = cfg.hyperArmor == true,
		endTask     = nil,
		nodeName    = nodeName,
		startedAt   = os.clock(),
	}

	-- Optional move-based i-frames (authoritative in IFrameStore)
	if cfg.iFrames and cfg.iFrames > 0 then
		IFrameStore.Grant(player, cfg.iFrames, "Move")
	end

	-- Hyper armor telemetry (if enabled)
	if attackState[player].hyperArmor then
		emit(player, nodeName, "HyperArmorStart", { reason = "Start" })
	end

	-- Attack lifecycle start
	emit(player, nodeName, "AttackStart", {
		duration = cfg.duration,
	})

	-- Auto-clear after duration, if provided
	if cfg.duration and cfg.duration > 0 then
		local t
		t = task.delay(cfg.duration, function()
			-- only complete if still active and timer matches
			if attackState[player] and attackState[player].endTask == t then
				endAttackInternal(player, "Completed", "Duration")
			end
		end)
		attackState[player].endTask = t
	end
end

-- Attempts to interrupt the player’s current attack.
-- Returns true if an interruption occurred.
function AttackStateService.Interrupt(player, reason)
	local st = attackState[player]
	if not st then return false end
	if st.hyperArmor then return false end  -- cannot interrupt

	st.interrupted = true
	emit(player, st.nodeName, "Interrupted", { reason = reason or "Interrupt" })
	endAttackInternal(player, "Interrupted", reason or "Interrupt")
	return true
end

function AttackStateService.HasHyperArmor(player)
	local st = attackState[player]
	return st and st.hyperArmor == true
end

function AttackStateService.IsInterrupted(player)
	local st = attackState[player]
	return st and st.interrupted == true
end

-- ✅ NEW: returns true while an attack is currently active/alive
function AttackStateService.IsActive(player)
	return attackState[player] ~= nil
end

function AttackStateService.Clear(player, reason)
	if not attackState[player] then return end
	endAttackInternal(player, "Canceled", reason or "Clear")
end

------------------------------ LIFECYCLE CLEANUP
Players.PlayerRemoving:Connect(function(plr)
	if attackState[plr] then
		endAttackInternal(plr, "Canceled", "PlayerRemoving")
	end
end)

return AttackStateService
