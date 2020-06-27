local exports if SERVER then AddCSLuaFile("debugee/haxe_cl_init.lua") exports = include("debugee/haxe_init.lua") end
if CLIENT then exports = include("debugee/haxe_cl_init.lua") end
if exports.toGlobalTable ~= nil then
    for i,p in pairs(exports.toGlobalTable) do
        _G[i] = p
    end
end
debugee_HAXE = exports.__env
for i,p in pairs(exports) do
    if i ~= "__env" and i ~= "toGlobalTable" then
        _G[i] = p
    end
end
