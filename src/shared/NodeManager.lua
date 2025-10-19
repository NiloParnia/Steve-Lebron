-- NodeManager.lua (ReplicatedStorage)
-- Maps player -> { nodeName -> nodeModule } and loads only allowed + unlocked nodes
-- Public API: LoadUnlocked, RefreshFromProfile, GetNode, GetAll, AddUnlock, RemoveUnlock, Unload
-- NOW: Mount-safe. Any function on a node is blocked while the caller is Mounted.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local Players             = game:GetService("Players")
local NodeModulesFolder   = ReplicatedStorage:WaitForChild("NodeModules")

local NodeManager = {}
local active = {} -- [player] = { [nodeName] = wrappedNodeTable }
NodeManager._playerNodes = active -- for debugging/inspection only

-- ========== Mounted gate wrappers (hard mode: wrap ANY function on the node) ==========
-- weak caches to avoid re-wrapping
local __wrapCache = setmetatable({}, { __mode = "k" })  -- original node tbl -> proxy
local __fnCache   = setmetatable({}, { __mode = "k" })  -- per node: key -> wrapped fn

local function resolvePlayerFromArgs(...)
	-- Supports both call shapes you use:
	--   node.OnStart(player, dir)
	--   node.Execute(player, dir)
	--   node:Execute(rootPart, dir)  -- method form; self in slot 1, BasePart in slot 2
	local a1, a2 = ...
	if typeof(a1) == "Instance" and a1:IsA("Player") then
		return a1
	end
	if typeof(a2) == "Instance" and a2:IsA("BasePart") then
		local char = a2:FindFirstAncestorOfClass("Model")
		if char then return Players:GetPlayerFromCharacter(char) end
	end
	return nil
end

local function isMountedPlayer(player)
	if not player then return false end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return hum and hum:GetAttribute("Mounted") == true
end

local function guardFunc(nodeTbl, key, fn)
	-- cache wrapper per (node, key)
	local nodeCache = __fnCache[nodeTbl]
	if not nodeCache then nodeCache = {}; __fnCache[nodeTbl] = nodeCache end
	local cached = nodeCache[key]
	if cached then return cached end

	local wrapped = function(...)
		local plr = resolvePlayerFromArgs(...)
		if isMountedPlayer(plr) then
			-- Uncomment if you want logs:
			-- warn(("[NodeManager] BLOCKED while mounted  node=%s fn=%s"):format(tostring(nodeTbl.Name or key or "?"), tostring(key)))
			return
		end
		return fn(...)
	end
	nodeCache[key] = wrapped
	return wrapped
end

-- Proxy that guards ANY callable; preserves table semantics
local function wrapNodeForMounted(nodeTbl)
	if type(nodeTbl) ~= "table" then return nodeTbl end
	local existing = __wrapCache[nodeTbl]
	if existing then return existing end

	local proxy = setmetatable({}, {
		__index = function(_, k)
			local v = nodeTbl[k]
			if type(v) == "function" then
				return guardFunc(nodeTbl, k, v)
			elseif type(v) == "table" then
				-- If subtable contains callables, they’ll be guarded on access too (via __index again)
				return v
			else
				return v
			end
		end,
		__newindex = function(_, k, v)
			nodeTbl[k] = v  -- allow nodes to mutate themselves
		end,
		__pairs  = function() return pairs(nodeTbl) end,
		__ipairs = function() return ipairs(nodeTbl) end,
	})

	__wrapCache[nodeTbl] = proxy
	return proxy
end
-- ===============================================================================

-- ---------- ALLOWLIST (cached from RS/Unlockables + defaults mirror) ----------
local DEFAULTS = { "Punch", "Heavy", "Dodge", "BlockStart", "BlockEnd" }
local ALLOWED

local function refreshAllowed()
	local t = {}
	local folder = ReplicatedStorage:FindFirstChild("Unlockables")
	if folder then
		for _, sv in ipairs(folder:GetChildren()) do
			if sv:IsA("StringValue") and sv.Value ~= "" then
				t[sv.Value] = true
			end
		end
	end
	for _, def in ipairs(DEFAULTS) do t[def] = true end
	ALLOWED = t
end

local function getAllowed()
	if not ALLOWED then refreshAllowed() end
	return ALLOWED
end

local unlockFolder = ReplicatedStorage:FindFirstChild("Unlockables")
if unlockFolder then
	unlockFolder.ChildAdded:Connect(refreshAllowed)
	unlockFolder.ChildRemoved:Connect(refreshAllowed)
end

-- ---------- utils ----------
local function toSet(list)
	local s = {}
	if type(list) ~= "table" then return s end
	for _, name in ipairs(list) do
		if type(name) == "string" then s[name] = true end
	end
	return s
end

local function isValidExport(modTable)
	return type(modTable) == "table"
end

local function requireNode(mod)
	local ok, node = pcall(require, mod)
	if not ok then
		warn("[NodeManager] require failed:", mod.Name, node)
		return nil
	end
	if not isValidExport(node) then
		warn("[NodeManager] invalid export:", mod.Name)
		return nil
	end
	-- Store the WRAPPED proxy so even direct access via _playerNodes is mount-safe
	return wrapNodeForMounted(node)
end

-- ---------- API ----------
function NodeManager.LoadUnlocked(player, profileOrList)
	if not player then return end
	local unlockList
	if type(profileOrList) == "table" and profileOrList.Data then
		unlockList = profileOrList.Data.Unlocks or {}
	else
		unlockList = profileOrList or {}
	end

	local allowed  = getAllowed()
	local unlocked = toSet(unlockList)
	local map = {}

	for name in pairs(unlocked) do
		if not allowed[name] then
			warn(('[NodeManager] skipping disallowed node %q'):format(name))
			continue
		end
		local mod = NodeModulesFolder:FindFirstChild(name)
		if not (mod and mod:IsA("ModuleScript")) then
			warn(('[NodeManager] missing module %q'):format(name))
			continue
		end
		local node = requireNode(mod)
		if node then
			map[name] = node -- already wrapped proxy
		end
	end

	active[player] = map

	-- pretty print
	local names = {}
	for k in pairs(map) do table.insert(names, k) end
	table.sort(names)
	print(('[NodeManager] loaded for %s: %s'):format(player.Name, (#names > 0 and table.concat(names, ', ') or '<none>')))
end

function NodeManager.RefreshFromProfile(player, profile)
	if not player or not profile then return end
	NodeManager.LoadUnlocked(player, profile)
end

-- Base GetNode (raw lookup from active). Already returns wrapped nodes.
function NodeManager.GetNode(player, name)
	local set = active[player]
	return set and set[name] or nil
end

-- (Optional extra armor) If someone swaps this later, keep a wrapper layer:
do
	local _origGetNode = NodeManager.GetNode
	function NodeManager.GetNode(player, nodeName)
		local raw = _origGetNode(player, nodeName)
		if raw then
			-- raw is likely already a proxy, but this makes it idempotent
			return wrapNodeForMounted(raw)
		end
		return nil
	end
end

function NodeManager.GetAll(player)
	local set = active[player]
	if not set then return nil end
	local clone = {}
	for k, v in pairs(set) do clone[k] = v end
	return clone
end

function NodeManager.AddUnlock(player, nodeName)
	if not player or type(nodeName) ~= "string" or nodeName == "" then return false end
	local allowed = getAllowed()
	if not allowed[nodeName] then
		warn("[NodeManager] AddUnlock rejected (not allowed):", nodeName)
		return false
	end
	local mod = NodeModulesFolder:FindFirstChild(nodeName)
	if not (mod and mod:IsA("ModuleScript")) then
		warn("[NodeManager] AddUnlock failed: no module", nodeName)
		return false
	end
	local node = requireNode(mod); if not node then return false end
	active[player] = active[player] or {}
	active[player][nodeName] = node -- wrapped proxy
	print(('[NodeManager] hot-loaded %s for %s'):format(nodeName, player.Name))
	return true
end

function NodeManager.RemoveUnlock(player, nodeName)
	if not player or type(nodeName) ~= "string" then return end
	if active[player] then active[player][nodeName] = nil end
end

function NodeManager.Unload(player)
	active[player] = nil
end

return NodeManager