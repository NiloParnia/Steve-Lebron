-- NodeSense.lua
-- Central telemetry bus for node intent/outcomes.
-- Server fires a BindableEvent for AI; optional RemoteEvent for tester HUDs.
-- Tags are simple booleans (not CollectionService tags).

local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")
local RS         = game:GetService("ReplicatedStorage")

local NodeSense = {}

---------------------------------------------------------------------
-- Debug toggles
---------------------------------------------------------------------
NodeSense._debug = true           -- 🔊 default ON per your request
NodeSense._debugDedup = true      -- also log when a message is skipped by dedupe

function NodeSense.SetDebug(on)
	NodeSense._debug = (on == nil) and true or (on and true or false)
end

function NodeSense.SetDebugDedup(on)
	NodeSense._debugDedup = (on == nil) and true or (on and true or false)
end

local function fmtTags(t)
	if typeof(t) ~= "table" then return "" end
	local list = {}
	for k, v in pairs(t) do if v then table.insert(list, tostring(k)) end end
	table.sort(list)
	return table.concat(list, ",")
end

local function pick(ctx, keys)
	if typeof(ctx) ~= "table" then return "" end
	local parts = {}
	for _, k in ipairs(keys) do
		local v = rawget(ctx, k)
		if v ~= nil then table.insert(parts, (k .. "=" .. tostring(v))) end
	end
	return table.concat(parts, " ")
end

---------------------------------------------------------------------
-- Internals
---------------------------------------------------------------------
local function shallowClone(t)
	local c = {}
	if typeof(t) == "table" then
		for k, v in pairs(t) do c[k] = v end
	end
	return c
end

local function tryFreeze(t)
	pcall(function() table.freeze(t) end)
	return t
end

-- Dedup to avoid spam (same actor+node+shot/outcome burst)
NodeSense._dedupeWindowSec   = 0.05
NodeSense._recentKeys        = {}   -- key -> expiry os.clock()
NodeSense._recentMaxEntries  = 256
NodeSense._nextPruneAt       = 0

-- Server-side handles
NodeSense._serverEvent   = nil      -- BindableEvent
NodeSense.ServerEvent    = nil      -- alias for consumers
NodeSense._remoteEvent   = nil      -- RemoteEvent (optional debug)
NodeSense._clientBroadcastEnabled = false
NodeSense._clientFilter  = nil      -- function(player, payload) -> bool

-- Ensure the global RemoteEvent exists (server only, created on demand)
local function ensureRemoteEvent()
	if not RunService:IsServer() then return nil end
	local folder = RS:FindFirstChild("RemoteEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RemoteEvents"
		folder.Parent = RS
	end
	local re = folder:FindFirstChild("NodeSense")
	if not re then
		re = Instance.new("RemoteEvent")
		re.Name = "NodeSense"
		re.Parent = folder
	end
	return re
end

-- Normalize actor (Player or Character or any descendant)
local function normalizeActor(actor)
	local player, model

	if typeof(actor) == "Instance" then
		if actor:IsA("Player") then
			player = actor
			model = player.Character
		elseif actor:IsA("Model") then
			model = actor
			player = Players:GetPlayerFromCharacter(model)
		else
			model = actor:FindFirstAncestorOfClass("Model")
			if model then player = Players:GetPlayerFromCharacter(model) end
		end
	end

	return player, model
end

local function buildKey(actorUserId, actorName, nodeName, shotIndex, outcome)
	local who = actorUserId and ("U" .. tostring(actorUserId)) or ("N" .. tostring(actorName or "?"))
	return table.concat({
		who,
		tostring(nodeName or "?"),
		tostring(shotIndex or "-"),
		tostring(outcome or "start")
	}, "|")
end

local function dedupPass(key, node, actorName)
	local now = os.clock()
	-- Fast path: reject if not expired
	local exp = NodeSense._recentKeys[key]
	if exp and exp > now then
		if NodeSense._debug and NodeSense._debugDedup then
			print(("[NodeSense] DEDUP  node=%s actor=%s key=%s"):format(tostring(node), tostring(actorName), key))
		end
		return true
	end

	-- Record expiry for this key
	NodeSense._recentKeys[key] = now + NodeSense._dedupeWindowSec

	-- Periodic prune
	if now >= (NodeSense._nextPruneAt or 0) then
		NodeSense._nextPruneAt = now + 0.5
		local alive = 0
		for k, v in pairs(NodeSense._recentKeys) do
			if v <= now then
				NodeSense._recentKeys[k] = nil
			else
				alive += 1
			end
		end
		if alive > NodeSense._recentMaxEntries then
			-- Coarse prune: drop half by advancing a cutoff
			local cutoff = now + NodeSense._dedupeWindowSec
			local dropped = 0
			for k, v in pairs(NodeSense._recentKeys) do
				if v <= cutoff then
					NodeSense._recentKeys[k] = nil
					dropped += 1
					if dropped >= math.floor(alive / 2) then break end
				end
			end
		end
	end

	return false
end

---------------------------------------------------------------------
-- Public: CollectTags
-- Infer boolean tags from a node config + optional overrides.
---------------------------------------------------------------------
function NodeSense.CollectTags(nodeConfig, overrides)
	local cfg  = typeof(nodeConfig) == "table" and nodeConfig or {}
	local tags = {}

	local function set(k, v)
		if v then tags[k] = true else tags[k] = nil end
	end

	-- Base inferences
	set("Attack",       (cfg.Damage or 0) > 0)
	set("GuardDamage",  (cfg.GuardDamage or 0) > 0)
	set("Parryable",    cfg.Parryable == true)
	set("StunInflict",  (cfg.Stun or 0) > 0)
	set("KnockbackInflict", (cfg.KnockbackForce or 0) > 0 or (cfg.Knockback or 0) > 0)

	-- Heuristics: range/melee + heavy/m1 based on fields/name
	local name = tostring(cfg.Name or "")
	if cfg.UseMovingHitbox or name:lower():find("revolver") or name:lower():find("shot") then
		set("Ranged", true)
	end
	if cfg.Melee == true then set("Melee", true) end
	if cfg.Heavy == true or name:lower():find("heavy") then set("Heavy", true) end
	if cfg.M1    == true or name:lower():find("m1")    then set("M1", true)    end

	-- Blockable default: any Attack that isn't explicitly Unblockable
	if tags.Attack and cfg.Unblockable ~= true then
		set("Blockable", true)
	end

	-- Merge explicit per-node overrides (cfg.Tags) and call-site overrides
	for _, src in ipairs({ cfg.Tags, overrides }) do
		if typeof(src) == "table" then
			for k, v in pairs(src) do set(k, v) end
		end
	end

	return tags
end

---------------------------------------------------------------------
-- Public: SetClientBroadcast
-- Toggle optional client telemetry; filter is (player, payload) -> bool.
---------------------------------------------------------------------
function NodeSense.SetClientBroadcast(enabled, filterFn)
	if not RunService:IsServer() then return end
	NodeSense._clientBroadcastEnabled = enabled and true or false
	NodeSense._clientFilter = filterFn
	if enabled and not NodeSense._remoteEvent then
		NodeSense._remoteEvent = ensureRemoteEvent()
	end
end

---------------------------------------------------------------------
-- Public: SetDedupeWindow(seconds)
---------------------------------------------------------------------
function NodeSense.SetDedupeWindow(seconds)
	if typeof(seconds) == "number" and seconds >= 0 then
		NodeSense._dedupeWindowSec = seconds
	end
end

---------------------------------------------------------------------
-- Public: Subscribe(fn)
-- Server consumers (like EnemyController) can hook the bus easily.
---------------------------------------------------------------------
function NodeSense.Subscribe(fn)
	if not RunService:IsServer() then return nil end
	if not NodeSense._serverEvent then
		local be = Instance.new("BindableEvent")
		be.Name = "NodeSenseServerEvent"
		NodeSense._serverEvent = be
		NodeSense.ServerEvent  = be
	end
	return NodeSense._serverEvent.Event:Connect(fn)
end

---------------------------------------------------------------------
-- Public: Emit
-- actor: Player or Character/descendant
-- nodeName: string (fallbacks to context.nodeName or "Unknown")
-- tags: table of booleans (may be nil)
-- context: shallow table (numbers/strings only for client mirror)
---------------------------------------------------------------------
function NodeSense.Emit(actor, nodeName, tags, context)
	if not RunService:IsServer() then return end
	if not NodeSense._serverEvent then return end

	local player, model = normalizeActor(actor)
	local actorUserId   = player and player.UserId or nil
	local actorName     = (player and player.Name) or (model and model.Name) or tostring(actor)
	local node          = nodeName or (typeof(context)=="table" and context.nodeName) or "Unknown"

	local ctx = shallowClone(context)
	local tgs = shallowClone(tags)

	-- Dedup key based on actor+node+shotIndex+outcome
	local key = buildKey(actorUserId, actorName, node, ctx and ctx.shotIndex, ctx and ctx.outcome)
	if dedupPass(key, node, actorName) then
		return
	end

	local now = os.clock()
	local payload = {
		actorPlayer = player,       -- (server only) Instance
		actorModel  = model,        -- (server only) Instance
		actorUserId = actorUserId,  -- number or nil
		actorName   = actorName,    -- string
		nodeName    = node,         -- string
		tags        = tgs,          -- table<boolean>
		context     = ctx,          -- table
		serverClock = now,          -- number
	}

	-- 🔊 Debug print (server)
	if NodeSense._debug then
		print(("[NodeSense] EMIT  node=%s  actor=%s(%s)  tags=[%s]  ctx{%s}")
			:format(
				tostring(node),
				tostring(actorName),
				tostring(actorUserId or "NPC"),
				fmtTags(tgs),
				pick(ctx, {
					"outcome","damage","guardDamage","stun","kbForce","targetId","shotIndex"
				})
			)
		)
	end

	-- Fire server-side bus for AI/analytics
	NodeSense._serverEvent:Fire(payload)

	-- Optional client mirror (never sends Instances)
	if NodeSense._clientBroadcastEnabled then
		if not NodeSense._remoteEvent then
			NodeSense._remoteEvent = ensureRemoteEvent()
		end

		local clientCtx = {
			nodeName    = node,
			actorId     = actorUserId,
			actorName   = actorName,
			shotIndex   = ctx and ctx.shotIndex,
			outcome     = ctx and ctx.outcome,
			damage      = ctx and ctx.damage,
			guardDamage = ctx and ctx.guardDamage,
			stun        = ctx and ctx.stun,
			kbForce     = ctx and ctx.kbForce,
			ts          = now,
		}
		local clientPayload = {
			nodeName = node,
			tags     = tgs,
			context  = clientCtx,
		}
		tryFreeze(clientPayload)

		local sent = 0
		if NodeSense._clientFilter then
			for _, plr in ipairs(Players:GetPlayers()) do
				local ok, allowed = pcall(NodeSense._clientFilter, plr, payload)
				if ok and allowed then
					NodeSense._remoteEvent:FireClient(plr, clientPayload)
					sent += 1
				end
			end
		else
			NodeSense._remoteEvent:FireAllClients(clientPayload)
			sent = #Players:GetPlayers()
		end

		if NodeSense._debug then
			print(("[NodeSense] ▶ client broadcast  node=%s  recipients=%d"):format(node, sent))
		end
	end
end

---------------------------------------------------------------------
-- Public convenience: EmitWithDef (infer tags from node config)
---------------------------------------------------------------------
function NodeSense.EmitWithDef(actor, nodeDef, overrides, context)
	local nodeName = (typeof(nodeDef)=="table" and nodeDef.Name) or (typeof(context)=="table" and context.nodeName) or "Unknown"
	local tags = NodeSense.CollectTags(nodeDef, overrides)
	NodeSense.Emit(actor, nodeName, tags, context)
end

---------------------------------------------------------------------
-- Public convenience: EmitOutcome (standardize outcome strings)
-- outcomes: "Hit" | "Blocked" | "Parried" | "GuardBroken" | "Miss"
---------------------------------------------------------------------
function NodeSense.EmitOutcome(actor, nodeName, outcome, context)
	local ctx = shallowClone(context)
	ctx = ctx or {}
	ctx.outcome = outcome
	NodeSense.Emit(actor, nodeName, nil, ctx)
end

---------------------------------------------------------------------
-- Init (server/client safe)
---------------------------------------------------------------------
if RunService:IsServer() then
	-- Create a single BindableEvent bus for the server
	local be = Instance.new("BindableEvent")
	be.Name = "NodeSenseServerEvent"
	NodeSense._serverEvent = be
	NodeSense.ServerEvent  = be

	-- RemoteEvent is created only if client broadcast enabled
	NodeSense._remoteEvent = RS:FindFirstChild("RemoteEvents")
		and RS.RemoteEvents:FindFirstChild("NodeSense") or nil
else
	-- Clients don’t need the server bus reference
	NodeSense._serverEvent = nil
	NodeSense.ServerEvent  = nil
end

return NodeSense
