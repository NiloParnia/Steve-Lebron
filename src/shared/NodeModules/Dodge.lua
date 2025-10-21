-- [[ NodeLibrary compat shim (server-only require) ]]
local RunService = game:GetService("RunService")
local NodeLibrary
if RunService:IsServer() then
    NodeLibrary = require(game:GetService("ServerScriptService"):WaitForChild("NodeLibrary"))
else
    -- client fallback: safe stub to avoid require crash if a client loads this file
    NodeLibrary = setmetatable({}, { __index = function()
        return function() end  -- no-op
    end })
end
