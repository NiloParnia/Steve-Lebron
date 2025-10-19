-- ReplicatedStorage/AI/Blackboard.lua
-- TTL flags per target (blocking, parryWindow, dodgeActive, incoming tags, etc.)
local Blackboard = {}
Blackboard.__index = Blackboard

local function now() return os.clock() end

function Blackboard.new()
	return setmetatable({
		flags = {},   -- name -> { value=any, expires=number|nil }
	}, Blackboard)
end

function Blackboard:set(name, value, ttl)
	local e = ttl and (now() + ttl) or nil
	self.flags[name] = { value = value, expires = e }
end

function Blackboard:touch(name, ttl)
	local slot = self.flags[name]
	if not slot then return end
	if ttl then slot.expires = now() + ttl end
end

function Blackboard:get(name)
	local slot = self.flags[name]
	if not slot then return nil end
	if slot.expires and slot.expires <= now() then
		self.flags[name] = nil
		return nil
	end
	return slot.value
end

function Blackboard:clear(name) self.flags[name] = nil end

return Blackboard
