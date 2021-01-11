local exports if SERVER then AddCSLuaFile("debugee/haxe_cl_init.lua") exports = include("debugee/haxe_init.lua") end
if CLIENT then exports = include("debugee/haxe_cl_init.lua") end