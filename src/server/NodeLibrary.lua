-- ServerScriptService/NodeLibrary.lua
-- Compat shim: exports a merged table from SSS.NodeLibraryPkg (folder of ModuleScripts).
-- This ensures require(SSS.NodeLibrary) works regardless of the folder/module flip.

local SSS = game:GetService("ServerScriptService")
local pkg = SSS:FindFirstChild("NodeLibraryPkg")
local M = {}

if pkg and pkg:IsA("Folder") then
    for _,child in ipairs(pkg:GetChildren()) do
        if child:IsA("ModuleScript") then
            local ok, mod = pcall(require, child)
            if ok and type(mod) == "table" then
                for k,v in pairs(mod) do
                    if M[k] == nil then M[k] = v end
                end
            else
                warn("[NodeLibrary] require failed for", child.Name, ok and "non-table" or mod)
            end
        end
    end
else
    warn("[NodeLibrary] NodeLibraryPkg folder not found; exporting empty library")
end

return M