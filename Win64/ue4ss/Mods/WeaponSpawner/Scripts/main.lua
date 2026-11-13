--[[
    WeaponSpawner for RoboCop: Rogue City (UE4SS Lua mod)

    Hotkeys (in game):
      F7  / F8   previous / next weapon in the list
      F9         give the selected weapon (calls Backpack directly, with default ammo)
      F6         dump the Backpack API (function signatures) to UE4SS.log

    Console commands (UE4SS console or the in-game console, if enabled):
      givelist                     list the weapons with their index numbers
      give <index|name>            e.g.  give 3   /   give AKM   /   give WP_BrowningM60
      giveammo <B_AmmoX> [amount]  e.g.  giveammo B_AmmoRifle 200
      wsdump                       same as F6

    Everything is logged with the [WeaponSpawner] prefix in ue4ss\UE4SS.log.
]]

local UEHelpers = require("UEHelpers")

local TAG = "[WeaponSpawner] "
local DEFAULT_AMMO_AMOUNT = 200

local WEAPON_DIR = "/Game/Blueprints/WeaponsNew/"
local AMMO_DIR   = "/Game/Blueprints/Items/Ammo/"

-- Display name, asset name. Paths come from Manifest_UFSFiles_Win64.txt.
local WEAPONS = {
    { "Auto-9",                     "WP_BerettaAuto9" },
    { "Pistol",                     "WP_Pistol" },
    { "SIG Sauer",                  "WP_SigSauer" },
    { "Desert Eagle",               "WP_DesertEagle" },
    { "Uzi",                        "WP_SmgUzi" },
    { "TEC-9",                      "WP_IntraTec" },
    { "Sterling Mk6",               "WP_SterlingMk6" },
    { "AKM",                        "WP_AKM" },
    { "Steyr AUG",                  "WP_SteyrAUG" },
    { "HK G11",                     "WP_HKG11" },
    { "Heckler & Koch",             "WP_Hecklerkoch" },
    { "HK21",                       "WP_HK21" },
    { "FN Minimi",                  "WP_FnMinimi" },
    { "M60",                        "WP_BrowningM60" },
    { "Mossberg",                   "WP_Mossberg" },
    { "OCP Combat Shotgun",         "WP_MossbergBullpup" },
    { "SPAS-12",                    "WP_Spas12" },
    { "Remington Shotgun",          "WP_ShotgunRemington" },
    { "Sniper Rifle",               "WP_SniperRifle" },
    { "Barrett M82 Sniper",         "WP_BarrettM82_Sniper" },
    { "Cobra Assault Cannon",       "WP_BarrettM82_explosive" },
    { "Grenade Launcher",           "WP_GrenadeLauncher" },
    { "M79",                        "WP_GrenadeLauncherM79" },
    { "MM-1",                       "WP_MM1GL" },
    { "Rocket Launcher",            "WP_RocketLauncher" },
    { "ATGM",                       "WP_ATGM" },
    { "Baseball Bat",               "WP_BaseballBat" },
    { "Mounted Minigun (cut)",      "WP_MountedMinigun" },
}

local selected = 1

----------------------------------------------------------------------------
-- Logging / on-screen feedback
----------------------------------------------------------------------------
local function Log(msg)
    print(TAG .. tostring(msg) .. "\n")
end

local function Notify(msg)
    Log(msg)
    -- Best effort on-screen text. May be invisible in a shipping build; harmless if so.
    pcall(function()
        local pc = UEHelpers.GetPlayerController()
        if pc and pc:IsValid() then pc:ClientMessage(TAG .. msg, FName("None"), 5.0) end
    end)
end

local function valid(o)
    return o ~= nil and o.IsValid ~= nil and o:IsValid()
end

----------------------------------------------------------------------------
-- Finding objects
----------------------------------------------------------------------------
local function LoadClass(dir, assetName)
    local classPath = dir .. assetName .. "." .. assetName .. "_C"
    local cls = StaticFindObject(classPath)
    if not valid(cls) then
        pcall(LoadAsset, dir .. assetName)
        cls = StaticFindObject(classPath)
    end
    if not valid(cls) then
        Log("Could not load class " .. classPath)
        return nil
    end
    return cls
end

-- Returns the Backpack belonging to the local player.
local function GetBackpack()
    local pawn = UEHelpers.GetPlayer()

    -- 1) A GetBackpack() UFunction on the pawn or controller, if one exists.
    for _, owner in ipairs({ pawn, UEHelpers.GetPlayerController() }) do
        if valid(owner) then
            local ok, bp = pcall(function() return owner:GetBackpack() end)
            if ok and valid(bp) then return bp end
        end
    end

    -- 2) Any live Backpack object, preferring one owned by the player pawn.
    local all = FindAllOf("Backpack")
    if all then
        local fallback = nil
        for _, bp in ipairs(all) do
            if valid(bp) and not bp:GetFullName():find("Default__") then
                local ok, outer = pcall(function() return bp:GetOuter() end)
                if ok and valid(outer) and valid(pawn) and outer:GetAddress() == pawn:GetAddress() then
                    return bp
                end
                fallback = fallback or bp
            end
        end
        if fallback then return fallback end
    end
    return nil
end

----------------------------------------------------------------------------
-- Reflection: read UFunction parameters so we can build calls correctly
----------------------------------------------------------------------------
local function GetFunctionParams(obj, funcName)
    local params, found = {}, false
    local ok, err = pcall(function()
        local cls = obj:GetClass()
        while valid(cls) and not found do
            cls:ForEachFunction(function(fn)
                if fn:GetFName():ToString() == funcName then
                    found = true
                    fn:ForEachProperty(function(prop)
                        table.insert(params, {
                            name = prop:GetFName():ToString(),
                            type = prop:GetClass():GetFName():ToString(),
                        })
                    end)
                    return true -- stop iterating
                end
            end)
            if not found then cls = cls:GetSuperStruct() end
        end
    end)
    if not ok then Log("Reflection error for " .. funcName .. ": " .. tostring(err)) end
    return found and params or nil
end

local function SignatureString(funcName, params)
    if not params then return funcName .. "  <not found>" end
    local parts = {}
    for _, p in ipairs(params) do table.insert(parts, p.type .. " " .. p.name) end
    return funcName .. "(" .. table.concat(parts, ", ") .. ")"
end

local INTERESTING = {
    "AddWeaponToBackpack", "SpawnWeaponAndAddToBackpack", "TryToAddDlcWeaponToBackpack",
    "AddItemsOfClassToBackpack", "AddItemsToBackpack", "HowManyItemsOfClassCanFitToBackpack",
    "AddPredefinedChip",
}

local function DumpApi()
    local bp = GetBackpack()
    if not bp then Log("Dump: no Backpack found (load into a level first).") return end
    Log("Backpack object: " .. bp:GetFullName())
    pcall(function()
        local cls = bp:GetClass()
        while valid(cls) do
            Log("  class chain: " .. cls:GetFullName())
            cls = cls:GetSuperStruct()
        end
    end)
    for _, name in ipairs(INTERESTING) do
        Log("  " .. SignatureString(name, GetFunctionParams(bp, name)))
    end
    -- Every function on the Backpack class, so nothing is missed.
    pcall(function()
        bp:GetClass():ForEachFunction(function(fn)
            Log("  fn: " .. fn:GetFName():ToString())
        end)
    end)
end

----------------------------------------------------------------------------
-- Building arguments from the reflected signature
----------------------------------------------------------------------------
local function BuildArgs(params, ctx)
    local args = {}
    for _, p in ipairs(params) do
        local n, t = p.name:lower(), p.type
        if n == "returnvalue" then
            -- skip
        elseif t == "ClassProperty" or t == "SoftClassProperty" then
            table.insert(args, ctx.class)
        elseif t == "BoolProperty" then
            -- bAddDefaultAmmo -> true; anything about equipping -> true; others false.
            table.insert(args, (n:find("ammo") or n:find("equip")) and true or false)
        elseif t == "IntProperty" or t == "FloatProperty" or t == "DoubleProperty" then
            table.insert(args, ctx.amount or 1)
        elseif t == "ObjectProperty" then
            if not ctx.instance then return nil, "needs an object instance for '" .. p.name .. "'" end
            table.insert(args, ctx.instance)
        else
            return nil, "unhandled parameter type " .. t .. " (" .. p.name .. ")"
        end
    end
    return args
end

local function TryCall(obj, funcName, ctx)
    local params = GetFunctionParams(obj, funcName)
    if not params then return false, funcName .. " not found" end
    local args, why = BuildArgs(params, ctx)
    if not args then return false, funcName .. ": " .. why end
    Log("Calling " .. SignatureString(funcName, params))
    local ok, err = pcall(function() obj[funcName](obj, table.unpack(args)) end)
    if not ok then return false, funcName .. " errored: " .. tostring(err) end
    return true
end

----------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------
local function GiveWeapon(entry)
    local display, asset = entry[1], entry[2]
    local bp = GetBackpack()
    if not bp then Notify("No Backpack found. Load into a level first.") return end
    local cls = LoadClass(WEAPON_DIR, asset)
    if not cls then Notify("Could not load " .. asset) return end

    -- Preferred: spawn-and-add by class (acts like a pickup, with default ammo).
    local ok, why = TryCall(bp, "SpawnWeaponAndAddToBackpack", { class = cls })
    if ok then Notify("Gave " .. display) return end
    Log(why)

    -- Fallback: AddWeaponToBackpack. If it wants an actor instance, spawn one first.
    local ctx = { class = cls }
    local params = GetFunctionParams(bp, "AddWeaponToBackpack")
    if params then
        for _, p in ipairs(params) do
            if p.type == "ObjectProperty" and p.name:lower() ~= "returnvalue" then
                pcall(function()
                    local world = UEHelpers.GetWorld()
                    local pawn = UEHelpers.GetPlayer()
                    local loc = pawn:K2_GetActorLocation()
                    ctx.instance = world:SpawnActor(cls, loc, {})
                end)
                break
            end
        end
    end
    ok, why = TryCall(bp, "AddWeaponToBackpack", ctx)
    if ok then Notify("Gave " .. display) return end
    Log(why)

    -- Last resort: the cheat manager's AddWeapon (no ammo, as in 2023).
    local pc = UEHelpers.GetPlayerController()
    local ok2 = pcall(function() pc.CheatManager:AddWeapon(asset) end)
    Notify(ok2 and ("Gave " .. display .. " via CheatManager (may have no ammo)")
                or ("Failed to give " .. display .. ". Run wsdump and check UE4SS.log."))
end

local function GiveAmmo(assetName, amount)
    local bp = GetBackpack()
    if not bp then Notify("No Backpack found.") return end
    local cls = LoadClass(AMMO_DIR, assetName)
    if not cls then Notify("Unknown ammo class " .. assetName) return end
    local ok, why = TryCall(bp, "AddItemsOfClassToBackpack", { class = cls, amount = amount })
    Notify(ok and ("Added " .. amount .. " " .. assetName) or ("Ammo failed: " .. why))
end

local function FindWeapon(query)
    local idx = tonumber(query)
    if idx and WEAPONS[idx] then return WEAPONS[idx] end
    local q = query:lower()
    for _, w in ipairs(WEAPONS) do
        if w[2]:lower() == q or w[2]:lower() == "wp_" .. q or w[1]:lower() == q then return w end
    end
    for _, w in ipairs(WEAPONS) do
        if w[2]:lower():find(q, 1, true) or w[1]:lower():find(q, 1, true) then return w end
    end
    return nil
end

local function ShowSelected()
    Notify(string.format("Selected [%d/%d]: %s  (F9 to give)", selected, #WEAPONS, WEAPONS[selected][1]))
end

----------------------------------------------------------------------------
-- Hotkeys (game-thread calls must go through ExecuteInGameThread)
----------------------------------------------------------------------------
RegisterKeyBind(Key.F7, function()
    selected = (selected - 2) % #WEAPONS + 1
    ShowSelected()
end)
RegisterKeyBind(Key.F8, function()
    selected = selected % #WEAPONS + 1
    ShowSelected()
end)
RegisterKeyBind(Key.F9, function()
    local w = WEAPONS[selected]
    ExecuteInGameThread(function() GiveWeapon(w) end)
end)
RegisterKeyBind(Key.F6, function()
    ExecuteInGameThread(DumpApi)
end)

----------------------------------------------------------------------------
-- Console commands
----------------------------------------------------------------------------
local function Out(Ar, msg)
    Log(msg)
    if Ar and Ar.Log then pcall(function() Ar:Log(msg) end) end
end

RegisterConsoleCommandHandler("givelist", function(_, _, Ar)
    for i, w in ipairs(WEAPONS) do Out(Ar, string.format("%2d  %-24s %s", i, w[1], w[2])) end
    return true
end)

RegisterConsoleCommandHandler("give", function(_, Params, Ar)
    if #Params < 1 then Out(Ar, "Usage: give <index|name>   (see givelist)") return true end
    local w = FindWeapon(table.concat(Params, " "))
    if not w then Out(Ar, "No weapon matches '" .. Params[1] .. "'") return true end
    ExecuteInGameThread(function() GiveWeapon(w) end)
    return true
end)

RegisterConsoleCommandHandler("giveammo", function(_, Params, Ar)
    if #Params < 1 then Out(Ar, "Usage: giveammo <B_AmmoX> [amount]") return true end
    local amount = tonumber(Params[2]) or DEFAULT_AMMO_AMOUNT
    ExecuteInGameThread(function() GiveAmmo(Params[1], amount) end)
    return true
end)

RegisterConsoleCommandHandler("wsdump", function()
    ExecuteInGameThread(DumpApi)
    return true
end)

Log("Loaded. F7/F8 select, F9 give, F6 dump API. Console: givelist, give, giveammo, wsdump.")
