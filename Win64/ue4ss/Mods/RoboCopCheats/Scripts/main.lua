--[[
    RoboCop Cheats: weapons, ammo, Auto-9 chips, upgrade boards and skill points for RoboCop: Rogue City
    (UE4SS Lua mod; the GUI tab is drawn by dlls/main.dll)

    Hotkeys (in game):
      F7  / F8   previous / next weapon in the list
      F9         give the selected weapon (calls Backpack directly, with default ammo)

    Console commands (UE4SS console or the in-game console, if enabled):
      givelist                     list the weapons with their index numbers
      give <index|name>            e.g.  give 3   /   give AKM   /   give WP_BrowningM60
      giveammo <B_AmmoX> [amount]  e.g.  giveammo B_AmmoRifle 200
      givechip <arms> [percent] [look]  arms = letters U R D L; percent = value shown in game;
                                   look 1-4 (1 = normal). e.g.  givechip UD 45
      boardlist                    list weapon upgrade boards (DT_WeaponUpgradeBoards rows)
      giveboard <index|row>        give an upgrade board
      dlcweapon <index|name|default>  weapon the Deluxe/DLC edition starts levels with
                                   (instead of the OCP Combat Shotgun); saved to dlc_weapon.txt
      giveskill [amount]           add unspent skill points (default 1, max 100 per call)
      clearskill                   remove all unspent skill points
      secrets                      secrets & police work (the end-of-level grade items):
                                   found / not found, this chapter first

    Developer tools (only when DEV_TOOLS = true below):
      F6 / rcdump                  dump the Backpack API + chip/board info to UE4SS.log
      rcchipdump                   chip enum, board functions and board rows to the log
      rcchipmap   (Ctrl+F6)        research: each chip's shape/rotation vs. what its widget shows
      rcchipinfo                   research: full chip/backpack/widget property dump (large)
      givechipraw <Shape> <rot> <boost> <tier>   raw AddPredefinedChip (tier 0-3)
      rcmenudump                   research: pause menu widget tree + menu/button class API
                                   (open the pause menu first)
      rcmenuwatch                  research: toggle logging of every pause menu/button
                                   blueprint function call (to see what a click runs)
      rcevaldump                   research: objective API + hidden end-of-level evaluation
                                   objective (secrets / police work) state, run mid-level

    Pause menu: "RoboCop Cheats" at the bottom of the game's pause menu opens the same
    features as in-game pages (mouse, or arrow keys + Enter).

    Everything is logged with the [RoboCopCheats] prefix in ue4ss\UE4SS.log.
]]

local UEHelpers = require("UEHelpers")

local MOD_VERSION = "1.1"
-- Research/debug hotkeys and console commands. Off in releases.
local DEV_TOOLS = false

local TAG = "[RoboCopCheats] "
local DEFAULT_AMMO_AMOUNT = 200

local WEAPON_DIR = "/Game/Blueprints/WeaponsNew/"
local AMMO_DIR   = "/Game/Blueprints/Items/Ammo/"

-- Display name, asset name. Paths come from Manifest_UFSFiles_Win64.txt.
local WEAPONS = {
    -- Removed: WP_BerettaAuto9 (RoboCop always has the Auto-9) and WP_Pistol (spawns broken).
    { "SIG Sauer",                  "WP_SigSauer" },
    { "Desert Eagle",               "WP_DesertEagle" },
    { "Uzi",                        "WP_SmgUzi" },
    { "TEC-9",                      "WP_IntraTec" },
    { "Sterling Mk6",               "WP_SterlingMk6" },
    { "AKM",                        "WP_AKM" },
    { "Steyr AUG",                  "WP_SteyrAUG" },
    { "HK G11",                     "WP_HKG11" },
    { "HK21",                       "WP_HK21" },
    { "M60",                        "WP_BrowningM60" },
    -- Removed: WP_Hecklerkoch and WP_FnMinimi are unfinished (meshes with no materials or
    -- textures in the manifest). They spawn as a white gun that breaks the game.
    { "Mossberg",                   "WP_Mossberg" },
    { "OCP Combat Shotgun",         "WP_MossbergBullpup" },
    { "SPAS-12",                    "WP_Spas12" },
    -- Removed: WP_ShotgunRemington and WP_SniperRifle (both spawn broken).
    { "Barrett M82 Sniper",         "WP_BarrettM82_Sniper" },
    { "Cobra Assault Cannon",       "WP_BarrettM82_explosive" },
    { "MM-1",                       "WP_MM1GL" },
    { "ATGM",                       "WP_ATGM" },
    -- Removed: WP_BaseballBat (spawns but can't be used; melee probably goes through
    -- Backpack:SetMeleeWeapon and the DLC1 WP_MeleeWeapon_* classes instead).
    -- Removed: WP_GrenadeLauncher, WP_GrenadeLauncherM79, WP_RocketLauncher and
    -- WP_MountedMinigun (all don't work when spawned).
}

-- Display name, ammo item class (/Game/Blueprints/Items/Ammo/).
-- Items have no display-name data, so each is named after the weapons whose AmmoItem
-- property points at it (read from the weapon defaults in game, 2026-11-13). Only ammo
-- used by a weapon above is listed (the Auto-9 has infinite ammo, so B_AmmoAuto9 is left out).
local AMMO = {
    { "SIG Sauer",                               "B_AmmoSmall" },
    { "Desert Eagle",                            "B_AmmoSmall44" },
    { "SMG (Uzi, TEC-9, Sterling)",              "B_AmmoSmg" },
    { "Rifle (AKM, AUG, G11, HK21)",             "B_AmmoRifle" },
    { "LMG (M60)",                               "B_AmmoLMG" },
    { "Shotgun (Mossberg, OCP, SPAS-12)",        "B_AmmoShotgun" },
    { "Sniper (Barrett M82)",                    "B_AmmoSniper" },
    { "Cobra Assault Cannon",                    "B_AmmoCobra" },
    { "Grenades (MM-1)",                         "B_AmmoGrenade" },
    { "Rockets (ATGM)",                          "B_AmmoRocket" },
}

local selected = 1

----------------------------------------------------------------------------
-- Logging / on-screen feedback
----------------------------------------------------------------------------
local function Log(msg)
    print(TAG .. tostring(msg) .. "\n")
end

-- On-screen message for a few seconds, top centre, over the game and the pause menu.
-- (ClientMessage shows nothing in this shipping build.) Uses the pause menu's own button
-- widget for the game's font: its Construct shows its Text property, uppercased. Created
-- click-through (HitTestInvisible) so it never blocks the menu.
local TOAST_SECONDS = 3
local TOAST_WIDGET = "/Game/UI/Menu/WB_InGameMenuButton02.WB_InGameMenuButton02_C"
local toastWidget, toastSerial = nil, 0
-- Set by the pause menu code below: returns the open pause menu, or nil. The pause menu sits
-- above everything added with AddToViewport (a toast there only appeared once the menu was
-- closed, 2026-11-13), so while it's open the toast goes onto the menu's own root canvas.
local openPauseMenu = nil

local function valid(o)
    return o ~= nil and o.IsValid ~= nil and o:IsValid()
end

local function ShowToast(msg)
    local cls = StaticFindObject(TOAST_WIDGET)
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local pc = UEHelpers.GetPlayerController()
    if not (valid(cls) and valid(wbl) and valid(pc)) then return end -- menu class not loaded yet
    if valid(toastWidget) then pcall(function() toastWidget:RemoveFromParent() end) end
    local menu = openPauseMenu and openPauseMenu() or nil
    local canvas = nil
    if menu then
        pcall(function()
            local root = menu.WidgetTree.RootWidget
            if valid(root) and root:IsA("/Script/UMG.CanvasPanel") then canvas = root end
        end)
    end
    local w = wbl:Create(menu or pc, cls, pc)
    if not valid(w) then return end
    w.Text = FText(msg)
    w:SetVisibility(3) -- HitTestInvisible
    local anchor = { Minimum = { X = 0.5, Y = 0.1 }, Maximum = { X = 0.5, Y = 0.1 } }
    if canvas then
        local slot = canvas:AddChildToCanvas(w)
        slot:SetAnchors(anchor)
        slot:SetAlignment({ X = 0.5, Y = 0.5 })
        slot:SetAutoSize(true)
        slot:SetZOrder(1000)
    else
        w:AddToViewport(10000)
        w:SetAnchorsInViewport(anchor)
        w:SetAlignmentInViewport({ X = 0.5, Y = 0.5 })
    end
    pcall(function() w:ShowElem() end)
    toastWidget = w
    toastSerial = toastSerial + 1
    local mine = toastSerial
    ExecuteWithDelay(TOAST_SECONDS * 1000, function()
        ExecuteInGameThread(function()
            if mine == toastSerial and valid(toastWidget) then
                pcall(function() toastWidget:RemoveFromParent() end)
                toastWidget = nil
            end
        end)
    end)
end

local function Notify(msg)
    msg = tostring(msg)
    Log(msg)
    -- Status line in the "RoboCop Cheats" GUI tab (provided by dlls/main.dll, if present).
    if RC_UI_Status then pcall(RC_UI_Status, msg) end
    ExecuteInGameThread(function()
        local ok, err = pcall(ShowToast, msg)
        if not ok then Log("On-screen message failed: " .. tostring(err)) end
    end)
end

----------------------------------------------------------------------------
-- Finding objects
----------------------------------------------------------------------------
local function LoadClass(dir, assetName)
    local classPath = dir .. assetName .. "." .. assetName .. "_C"
    local cls = StaticFindObject(classPath)
    if not valid(cls) then
        -- Not in memory yet (weapon not used in this level). Try the path forms
        -- LoadAsset accepts, logging each failure so we can see which one works.
        local candidates = {
            classPath,                                   -- /Game/.../WP_X.WP_X_C
            dir .. assetName .. "." .. assetName,        -- /Game/.../WP_X.WP_X
            dir .. assetName,                            -- /Game/.../WP_X
        }
        for _, path in ipairs(candidates) do
            local ok, res = pcall(LoadAsset, path)
            if not ok then Log("LoadAsset('" .. path .. "') error: " .. tostring(res)) end
            cls = StaticFindObject(classPath)
            if valid(cls) then Log("Loaded via LoadAsset('" .. path .. "')") break end
        end
    end
    if not valid(cls) then
        Log("Could not load class " .. classPath)
        return nil
    end
    return cls
end

-- Returns the Backpack of the *current* game state (BP_MyGameState_C_x.Backpack_0).
-- After a death/checkpoint reload the old game state's Backpack can still be in memory
-- while it is being torn down; adding a weapon to that one can crash the game, so we
-- never fall back to "any Backpack" when more than one exists.
local function GetBackpack(quiet)
    local gs = nil
    pcall(function() gs = UEHelpers.GetWorld().GameState end)

    local all = FindAllOf("Backpack") or {}
    local live = {}
    for _, bp in ipairs(all) do
        if valid(bp) and not bp:GetFullName():find("Default__") then
            table.insert(live, bp)
            if valid(gs) then
                local ok, outer = pcall(function() return bp:GetOuter() end)
                if ok and valid(outer) and outer:GetAddress() == gs:GetAddress() then
                    return bp
                end
            end
        end
    end

    if #live == 1 and not valid(gs) then return live[1] end
    if quiet then return nil end
    Log(string.format("No Backpack on the current GameState (%s); %d Backpack object(s) in memory:",
        valid(gs) and gs:GetFullName() or "GameState not found", #live))
    for _, bp in ipairs(live) do Log("    " .. bp:GetFullName()) end
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
                        -- CPF_OutParm = 0x100, CPF_ReferenceParm = 0x8000000
                        local okF, isOut = pcall(function() return prop:HasAnyPropertyFlags(0x100) end)
                        local okR, isRef = pcall(function() return prop:HasAnyPropertyFlags(0x8000000) end)
                        table.insert(params, {
                            name = prop:GetFName():ToString(),
                            type = prop:GetClass():GetFName():ToString(),
                            out  = (okF and isOut) and not (okR and isRef),
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
    for _, p in ipairs(params) do table.insert(parts, (p.out and "out " or "") .. p.type .. " " .. p.name) end
    return funcName .. "(" .. table.concat(parts, ", ") .. ")"
end

local INTERESTING = {
    "AddWeaponToBackpack", "TryToAddDlcWeaponToBackpack",
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
        elseif p.out then
            -- Pure output (e.g. AmmoAdded): UE4SS fills a table we pass in.
            local box = {}
            ctx.outs = ctx.outs or {}
            ctx.outs[p.name] = box
            table.insert(args, box)
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
    for name, box in pairs(ctx.outs or {}) do
        local v = box[1]; if v == nil then v = box.Value end
        if v == nil then for _, x in pairs(box) do v = x break end end
        Log("  out " .. name .. " = " .. tostring(v))
    end
    return true
end

----------------------------------------------------------------------------
-- Actions
----------------------------------------------------------------------------
local function GiveWeapon(entry)
    local display, asset = entry[1], entry[2]
    local bp = GetBackpack()
    if not bp then Notify("No Backpack found (loading? dead?). Try again in a moment.") return end
    Log("Using " .. bp:GetFullName())
    local cls = LoadClass(WEAPON_DIR, asset)
    if not cls then Notify("Could not load " .. asset) return end

    -- AddWeaponToBackpack(Weapon, bAddDefaultAmmo, out AmmoAdded): spawn the actor, then add it.
    -- Verified 2026-11-13: AUG/M60/AKM arrive fully loaded, same as a real pickup.
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
    local ok, why = TryCall(bp, "AddWeaponToBackpack", ctx)
    if ok then Notify("Gave " .. display) return end
    Log(why)

    -- Last resort: the cheat manager's AddWeapon (no ammo, as in 2023).
    local pc = UEHelpers.GetPlayerController()
    local ok2 = pcall(function() pc.CheatManager:AddWeapon(asset) end)
    Notify(ok2 and ("Gave " .. display .. " via CheatManager (may have no ammo)")
                or ("Failed to give " .. display .. ". Run rcdump and check UE4SS.log."))
end

local function GiveAmmo(assetName, amount)
    local bp = GetBackpack()
    if not bp then Notify("No Backpack found.") return end
    local cls = LoadClass(AMMO_DIR, assetName)
    if not cls then Notify("Unknown ammo class " .. assetName) return end
    local label = assetName
    for _, a in ipairs(AMMO) do
        if a[2]:lower() == assetName:lower() then label = a[1] .. " ammo" break end
    end
    local ok, why = TryCall(bp, "AddItemsOfClassToBackpack", { class = cls, amount = amount })
    Notify(ok and ("Added " .. amount .. " " .. label) or ("Ammo failed: " .. why))
end

----------------------------------------------------------------------------
-- Deluxe/DLC starting weapon. On levels whose LevelData has bShouldAddDLCWeapon, the game
-- gives the player the class in Backpack.DeluxeEditionPlayerWeapon (OCP Combat Shotgun by
-- default) at a fresh level start (not on save loads or checkpoint restarts, which restore
-- the saved inventory). We put the chosen class into that property on the live Backpack as
-- soon as it is created, so the game's own code hands out our weapon.
-- What did NOT work (2026-11-13): a hook on Backpack:TryToAddDlcWeaponToBackpack never
-- fires (the game calls it natively), and writing the property on the Default__Backpack
-- CDO corrupted it (read back as an InteractiveComponent) without affecting new Backpacks.
-- The choice is saved to dlc_weapon.txt next to the Scripts folder.
----------------------------------------------------------------------------
local DLC_PROP = "DeluxeEditionPlayerWeapon"
local DLC_DEFAULT_ASSET = "WP_MossbergBullpup"

local dlcWeapon = nil      -- asset name of the replacement, nil = game default

-- Mods\RoboCopCheats, from this script's own path (UE4SS loads it by full path). Falls back
-- to the path relative to the game's Win64 folder, UE4SS's working directory.
local function ModDir()
    local ok, src = pcall(function() return debug.getinfo(1, "S").source end)
    if ok and type(src) == "string" then
        local dir = src:gsub("^@", ""):match("^(.*)[\\/]Scripts[\\/][^\\/]*$")
        if dir then return dir end
    end
    return "ue4ss\\Mods\\RoboCopCheats"
end
local DLC_SETTINGS_FILE = ModDir() .. "\\dlc_weapon.txt"

local function FindWeaponByAsset(asset)
    if not asset then return nil end
    for _, w in ipairs(WEAPONS) do if w[2]:lower() == asset:lower() then return w end end
    return nil
end

local function DlcWeaponName()
    local w = FindWeaponByAsset(dlcWeapon)
    return w and w[1] or "game default (OCP Combat Shotgun)"
end

local function LoadDlcSetting()
    local f = io.open(DLC_SETTINGS_FILE, "r")
    if not f then return end
    local s = (f:read("l") or ""):match("^%s*(%S*)")
    f:close()
    local w = FindWeaponByAsset(s)
    dlcWeapon = (w and w[2] ~= DLC_DEFAULT_ASSET) and w[2] or nil
    Log("DLC starting weapon (from " .. DLC_SETTINGS_FILE .. "): " .. DlcWeaponName())
end

local function SaveDlcSetting()
    local f, err = io.open(DLC_SETTINGS_FILE, "w")
    if not f then Log("Could not save " .. DLC_SETTINGS_FILE .. ": " .. tostring(err)) return false end
    f:write((dlcWeapon or "default") .. "\n")
    f:close()
    return true
end

-- Puts the chosen class into bp.DeluxeEditionPlayerWeapon. "Default" loads the OCP Combat
-- Shotgun class explicitly instead of remembering the old value, because after a mod
-- reload the live Backpack may already hold our replacement.
local function ApplyDlcWeapon(bp)
    if not valid(bp) then return end
    local ok, cur = pcall(function() return bp[DLC_PROP] end)
    if not ok then Log("Backpack has no " .. DLC_PROP .. ": " .. tostring(cur)) return end
    local want = LoadClass(WEAPON_DIR, dlcWeapon or DLC_DEFAULT_ASSET)
    if not want then Log("DLC weapon " .. tostring(dlcWeapon) .. " failed to load; leaving it unchanged") return end
    if valid(cur) and cur:GetAddress() == want:GetAddress() then return end
    Log(DLC_PROP .. " was " .. (valid(cur) and cur:GetFullName() or tostring(cur)))
    local okSet, err = pcall(function() bp[DLC_PROP] = want end)
    if okSet then
        Log("DLC weapon set to " .. want:GetFullName() .. " on " .. bp:GetFullName())
        return
    end
    -- Type of the property is only known from the exe's name table; log it for diagnosis.
    local ptype = "?"
    pcall(function()
        bp:GetClass():ForEachProperty(function(prop)
            if prop:GetFName():ToString() == DLC_PROP then ptype = prop:GetClass():GetFName():ToString() return true end
        end)
    end)
    Log("Setting " .. DLC_PROP .. " (" .. ptype .. ") failed: " .. tostring(err))
end

-- Apply the moment a Backpack is created. NotifyOnNewObject fires while the object is still
-- being constructed (its properties get initialised afterwards), so the actual write is
-- deferred to the game thread. The poll loop below re-checks every 0.5 s as a backup.
local function WatchNewBackpacks()
    local ok, err = pcall(function()
        NotifyOnNewObject("/Script/Game.Backpack", function(obj)
            ExecuteInGameThread(function()
                if valid(obj) and not obj:GetFullName():find("Default__") then
                    Log("New Backpack created: " .. obj:GetFullName())
                    ApplyDlcWeapon(obj)
                end
            end)
        end)
    end)
    Log(ok and "Watching for new Backpacks (DLC weapon)" or ("NotifyOnNewObject failed: " .. tostring(err)))
end

local function SetDlcWeapon(asset)
    local w = nil
    if asset and asset:lower() ~= "default" then
        w = FindWeaponByAsset(asset)
        if not w then Notify("Unknown weapon " .. tostring(asset)) return end
    end
    dlcWeapon = (w and w[2] ~= DLC_DEFAULT_ASSET) and w[2] or nil
    local saved = SaveDlcSetting()
    ApplyDlcWeapon(GetBackpack(true))
    if RC_UI_SetDlcWeapon then pcall(RC_UI_SetDlcWeapon, dlcWeapon or "default") end
    Notify("DLC starting weapon: " .. DlcWeaponName() .. " (from the next level start)"
           .. (saved and "" or "  [not saved, see log]"))
end

----------------------------------------------------------------------------
-- Chips (Auto-9 upgrade board). A chip is a "+" with up to four arms. The game doesn't
-- store arms: AddPredefinedChip takes a shape (EChipConnectionType) plus a rotation.
-- Every non-empty set of arms is exactly one shape at one rotation
-- (4 DeadEnd + 4 LShape + 2 PassThrough + 4 TShape + 1 Omni = 15), so the GUI's arm
-- toggles are converted here.
----------------------------------------------------------------------------
local ARM_UP, ARM_RIGHT, ARM_DOWN, ARM_LEFT = 1, 2, 4, 8 -- must match dllmain.cpp
local ARM_NAMES = { { ARM_UP, "Up" }, { ARM_RIGHT, "Right" }, { ARM_DOWN, "Down" }, { ARM_LEFT, "Left" } }

-- Arms of each shape at rotation 0, and rotation behaviour. Read from the game's own chip
-- widgets (rcchipmap, 2026-11-13): sides are numbered 0=Left 1=Up 2=Right 3=Down, and each
-- RotationOffset step adds 1, i.e. turns the chip a quarter turn clockwise. All 15
-- shape/rotation combinations seen in game match this table.
local CHIP_SHAPES = {
    { "DeadEnd",     ARM_LEFT },
    { "PassThrough", ARM_LEFT | ARM_RIGHT },
    { "LShape",      ARM_LEFT | ARM_DOWN },
    { "TShape",      ARM_LEFT | ARM_RIGHT | ARM_DOWN },
    { "Omni",        ARM_UP | ARM_RIGHT | ARM_DOWN | ARM_LEFT },
}
local CHIP_ROT_UNIT = 1          -- NewRotationOffset per 90-degree turn
local CHIP_ROT_CLOCKWISE = true  -- a higher offset turns the chip clockwise

-- The % the game shows is Boost * 1.5, rounded half up (widget ChipStrength: boost
-- 25 -> 38%, 30 -> 45%, 200 -> 300%). Must match ChipDisplayMultiplier in dllmain.cpp.
local CHIP_DISPLAY_MULT = 1.5
local function BoostToPercent(boost) return math.floor(boost * CHIP_DISPLAY_MULT + 0.5) end
-- Boost whose displayed % is closest to the wanted % (not every % is reachable).
local function PercentToBoost(pct)
    local best = nil
    local guess = math.floor(pct / CHIP_DISPLAY_MULT + 0.5)
    for b = math.max(1, guess - 1), guess + 1 do
        if not best or math.abs(BoostToPercent(b) - pct) < math.abs(BoostToPercent(best) - pct) then best = b end
    end
    return best
end

local DEFAULT_CHIP_PERCENT = 30
local DEFAULT_CHIP_TIER = 0
-- The chip widget has exactly 4 tier textures (BorderTextureTier / BackgroundTextureTier,
-- T_Chip01..04), so ChipTier must be 0..3. Tier 10 indexed past them and crashed the
-- inventory UI (UE crash 2026-11-13 18:06, access violation reading 0x38). Tier 0 is what
-- every normal chip has; 1..3 only change the chip's look.
local MAX_CHIP_TIER = 3
local function ClampTier(t) return math.max(0, math.min(MAX_CHIP_TIER, math.floor(t))) end

local function RotateArmsCW(mask, turns)
    for _ = 1, turns % 4 do mask = ((mask << 1) | (mask >> 3)) & 15 end
    return mask
end

local function ArmsString(mask)
    local parts = {}
    for _, a in ipairs(ARM_NAMES) do if mask & a[1] ~= 0 then table.insert(parts, a[2]) end end
    return #parts > 0 and table.concat(parts, "+") or "none"
end

-- arms bitmask -> shape name, rotation step (0..3)
local function ArmsToChip(mask)
    for _, s in ipairs(CHIP_SHAPES) do
        for r = 0, 3 do
            local cwTurns = CHIP_ROT_CLOCKWISE and r or (4 - r) % 4
            if RotateArmsCW(s[2], cwTurns) == mask then return s[1], r end
        end
    end
    return nil
end

-- EChipConnectionType name -> numeric value, read from the game's own enum (no guessing).
local chipEnum = nil
local function ChipEnumValues()
    if chipEnum then return chipEnum end
    local e = StaticFindObject("/Script/Game.EChipConnectionType")
    if not valid(e) then Log("EChipConnectionType enum not found") return nil end
    local t = {}
    e:ForEachName(function(name, value)
        t[(name:ToString():gsub("^.*::", ""))] = value
    end)
    chipEnum = t
    return t
end

local CHIP_ITEM_DIR = "/Game/Blueprints/Items/Accessories/"
local CHIP_ITEM_CLASS = "B_OCP_Chip"

local function GiveChipRaw(shape, rotation, boost, tier)
    local bp = GetBackpack()
    if not bp then Notify("No Backpack found.") return false end
    local enum = ChipEnumValues()
    local value = enum and enum[shape]
    if value == nil then Notify("Unknown chip shape " .. tostring(shape)) return false end
    local offset = rotation * CHIP_ROT_UNIT
    tier = ClampTier(tier)

    -- Preferred: the real pickup path, so the game shows its "chip added" HUD popup
    -- (AddPredefinedChip adds silently). Spawn the item class every inventory chip has
    -- (B_OCP_Chip, seen in Backpack.ChipsSlots), set its data with the game's own
    -- ChipItem:SpecifyChipData (same params as AddPredefinedChip), then add it with
    -- bShowHUDInfo. Any failure before the add cleans up and falls back, so a chip is
    -- never added twice.
    local added = 0
    local why = nil
    local addAttempted = false
    local okPath, errPath = pcall(function()
        local cls = LoadClass(CHIP_ITEM_DIR, CHIP_ITEM_CLASS)
        if not cls then why = "chip item class not loaded" return end
        local world, pawn = UEHelpers.GetWorld(), UEHelpers.GetPlayer()
        local item = world:SpawnActor(cls, pawn:K2_GetActorLocation(), {})
        if not valid(item) then why = "SpawnActor failed" return end
        if not item:IsA("/Script/Game.ChipItem") then
            why = "spawned item is not a ChipItem"
            pcall(function() item:K2_DestroyActor() end)
            return
        end
        item:SpecifyChipData(value, boost, offset, tier)
        Log(string.format("Spawned %s: ConnectionType=%s Boost=%s RotationOffset=%s ChipTier=%s",
            item:GetFullName(), tostring(item.ConnectionType), tostring(item.Boost),
            tostring(item.RotationOffset), tostring(item.ChipTier)))
        addAttempted = true
        added = bp:AddItemsToBackpack(item, 1, true) or 0
        if added < 1 then
            why = "AddItemsToBackpack returned " .. tostring(added)
            pcall(function() item:K2_DestroyActor() end)
        end
    end)
    if okPath and added >= 1 then
        Log("Chip added via AddItemsToBackpack (with HUD info)")
        return true
    end
    if not okPath and addAttempted then
        -- The add itself errored: the chip may or may not be in the backpack. Don't risk a
        -- duplicate; report instead.
        Notify("Chip add errored (check your chips before trying again): " .. tostring(errPath))
        return false
    end
    Log("Pickup path not used (" .. tostring(okPath and why or errPath) .. "); falling back to AddPredefinedChip")

    Log(string.format("AddPredefinedChip(%s=%d, Boost=%d, RotationOffset=%d, Tier=%d)",
        shape, value, boost, offset, tier))
    local ok, err = pcall(function() bp:AddPredefinedChip(value, boost, offset, tier) end)
    if not ok then Notify("AddPredefinedChip failed: " .. tostring(err)) end
    return ok
end

-- percent = the value the player will see on the chip; look = 1..4 (tier + 1).
local function GiveChip(mask, percent, look)
    local shape, rot = ArmsToChip(mask)
    if not shape then Notify("Pick at least one arm for the chip.") return end
    local boost = PercentToBoost(percent)
    local tier = ClampTier(look - 1)
    if GiveChipRaw(shape, rot, boost, tier) then
        Log(string.format("Chip details: arms %s = %s rotation %d, boost %d, look %d",
            ArmsString(mask), shape, rot, boost, tier + 1))
        Notify(string.format("Gave %d%% chip (%s)", BoostToPercent(boost), ArmsString(mask)))
    end
end

-- "UR", "up right", "NESW" ... -> arms bitmask
local function ParseArms(s)
    local mask = 0
    for c in s:upper():gmatch("%a") do
        if c == "U" or c == "N" then mask = mask | ARM_UP
        elseif c == "R" or c == "E" then mask = mask | ARM_RIGHT
        elseif c == "D" or c == "S" then mask = mask | ARM_DOWN
        elseif c == "L" or c == "W" then mask = mask | ARM_LEFT end
    end
    return mask
end

----------------------------------------------------------------------------
-- Weapon upgrade boards. Board rows come from DT_WeaponUpgradeBoards; the native
-- AddWeaponUpgradeBoardToPlayer is located by reflection (its class isn't known yet)
-- and its arguments are built from its real signature.
----------------------------------------------------------------------------
local BOARD_TABLE = "/Game/Blueprints/Abstract/Config/DT_WeaponUpgradeBoards.DT_WeaponUpgradeBoards"
local BOARD_FUNC = "AddWeaponUpgradeBoardToPlayer"

local function GetBoardTable()
    local dt = StaticFindObject(BOARD_TABLE)
    if not valid(dt) then
        pcall(LoadAsset, BOARD_TABLE)
        dt = StaticFindObject(BOARD_TABLE)
    end
    return valid(dt) and dt or nil
end

local function GetBoardRows()
    local dt = GetBoardTable()
    if not dt then return {} end
    local ok, rows = pcall(function() return dt:GetRowNames() end)
    if not ok or type(rows) ~= "table" then Log("GetRowNames failed: " .. tostring(rows)) return {} end
    local names = {}
    for _, r in ipairs(rows) do table.insert(names, tostring(r)) end
    return names
end

-- Every UFunction with one of these names, wherever it lives. Slow (walks GUObjectArray),
-- so callers cache the result.
local function FindFunctionsNamed(set)
    local found = {}
    ForEachUObject(function(obj)
        local ok, n = pcall(function() return obj:GetFName():ToString() end)
        if ok and set[n] then
            local okF, full = pcall(function() return obj:GetFullName() end)
            if okF and full:find("^Function ") then table.insert(found, obj) end
        end
    end)
    return found
end

local function ReflectParams(fn)
    local params = {}
    fn:ForEachProperty(function(prop)
        local okF, isOut = pcall(function() return prop:HasAnyPropertyFlags(0x100) end)
        local okR, isRef = pcall(function() return prop:HasAnyPropertyFlags(0x8000000) end)
        local p = {
            prop = prop,
            name = prop:GetFName():ToString(),
            type = prop:GetClass():GetFName():ToString(),
            out  = (okF and isOut) and not (okR and isRef),
        }
        if p.type == "ObjectProperty" then
            pcall(function() p.class = prop:GetPropertyClass() end)
        elseif p.type == "StructProperty" then
            pcall(function() p.struct = prop:GetStruct():GetFName():ToString() end)
        end
        table.insert(params, p)
    end)
    return params
end

local function ParamsString(params)
    local parts = {}
    for _, p in ipairs(params) do
        local t = p.type
        if p.class then pcall(function() t = t .. "<" .. p.class:GetFName():ToString() .. ">" end) end
        if p.struct then t = t .. "<" .. p.struct .. ">" end
        table.insert(parts, (p.out and "out " or "") .. t .. " " .. p.name)
    end
    return "(" .. table.concat(parts, ", ") .. ")"
end

local boardFn = nil
local function GetBoardFunction()
    if valid(boardFn) then return boardFn end
    local fns = FindFunctionsNamed({ [BOARD_FUNC] = true })
    if #fns == 0 then Log(BOARD_FUNC .. " not found in memory") return nil end
    for _, fn in ipairs(fns) do Log("Found " .. fn:GetFullName()) end
    boardFn = fns[1]
    return boardFn
end

-- An object to call fn on: the class default object for static functions, else a live
-- instance of the function's class.
local function GetCallTarget(fn)
    local cls = fn:GetOuter()
    local clsName = cls:GetFName():ToString()
    local isStatic = false
    pcall(function() isStatic = (fn:GetFunctionFlags() & 0x2000) ~= 0 end) -- FUNC_Static
    if isStatic then
        local pkg = cls:GetFullName():match("^%S+%s+(.-)%.[^.]+$")
        local cdo = pkg and StaticFindObject(pkg .. ".Default__" .. clsName)
        return valid(cdo) and cdo or nil, clsName .. " (static)"
    end
    for _, o in ipairs(FindAllOf(clsName) or {}) do
        if valid(o) and not o:GetFullName():find("Default__") then return o, clsName end
    end
    return nil, clsName
end

local function GiveBoard(row)
    local fn = GetBoardFunction()
    if not fn then Notify("Board function not found (run rcchipdump).") return end
    local target, where = GetCallTarget(fn)
    if not target then Notify("No live " .. where .. " to call " .. BOARD_FUNC .. " on.") return end
    local params = ReflectParams(fn)
    local dt = GetBoardTable()
    local pc = UEHelpers.GetPlayerController()
    local pawn = UEHelpers.GetPlayer()
    local bp = GetBackpack()
    local args = {}
    for _, p in ipairs(params) do
        local n, t = p.name:lower(), p.type
        if n == "returnvalue" then
        elseif p.out then table.insert(args, {})
        elseif t == "NameProperty" then table.insert(args, FName(row))
        elseif t == "StrProperty" then table.insert(args, row)
        elseif t == "StructProperty" and p.struct == "DataTableRowHandle" then
            table.insert(args, { DataTable = dt, RowName = FName(row) })
        elseif t == "BoolProperty" then table.insert(args, true)
        elseif t == "IntProperty" then table.insert(args, 1)
        elseif t == "ObjectProperty" then
            -- Confirmed 2026-11-13: GlobalFunctionLibrary::AddWeaponUpgradeBoardToPlayer(
            --   Object WorldContextObject, DataTableRowHandle BoardHandle), static.
            -- Any Object matches WorldContextObject, so try the player pawn first.
            local pick = nil
            for _, cand in ipairs({ pawn, pc, bp, dt }) do
                if valid(cand) and p.class and cand:IsA(p.class) then pick = cand break end
            end
            if not pick then Notify(BOARD_FUNC .. ": don't know what to pass for " .. p.name) return end
            table.insert(args, pick)
        else
            Notify(BOARD_FUNC .. ": unhandled parameter " .. t .. " " .. p.name) return
        end
    end
    Log("Calling " .. where .. ":" .. BOARD_FUNC .. ParamsString(params) .. " with row " .. row)
    local ok, err = pcall(function() target[BOARD_FUNC](target, table.unpack(args)) end)
    Notify(ok and ("Gave board " .. row) or ("Board failed: " .. tostring(err)))
end

local function ChipDump()
    local enum = ChipEnumValues()
    if enum then
        for name, v in pairs(enum) do Log(string.format("  EChipConnectionType::%s = %d", name, v)) end
    end
    local bp = GetBackpack()
    if bp then Log("  Backpack:" .. SignatureString("AddPredefinedChip", GetFunctionParams(bp, "AddPredefinedChip"))) end
    local names = {}
    for _, n in ipairs({ BOARD_FUNC, "ActivateBoard", "InitBoard", "ChangeBoardFromName",
                         "CreateNewRandomChip", "SpecifyChipData", "SetChipBoost", "SetChipStrength",
                         "RandomizeChip", "AssignChip" }) do names[n] = true end
    for _, fn in ipairs(FindFunctionsNamed(names)) do
        local ok, sig = pcall(function() return ParamsString(ReflectParams(fn)) end)
        local flags = 0
        pcall(function() flags = fn:GetFunctionFlags() end)
        Log(string.format("  %s%s  flags=0x%X", fn:GetFullName(), ok and sig or "(?)", flags))
    end
    local dt = GetBoardTable()
    if dt then
        pcall(function() Log("  Board row struct: " .. dt:GetRowStruct():GetFullName()) end)
        pcall(function()
            dt:GetRowStruct():ForEachProperty(function(prop)
                Log("    field " .. prop:GetClass():GetFName():ToString() .. " " .. prop:GetFName():ToString())
            end)
        end)
        for i, r in ipairs(GetBoardRows()) do Log(string.format("  board row %2d: %s", i, r)) end
    else
        Log("  " .. BOARD_TABLE .. " not loaded")
    end
end

----------------------------------------------------------------------------
-- Chip research dump (rcchipinfo). Goal: learn how a chip's stored data (tier, boost,
-- type...) turns into the % the player sees, and which tiers are valid (tier 10 crashed
-- the inventory UI on 2026-11-13). Open the weapon upgrade screen first, so the chip
-- widgets exist: each widget holds the chip data AND the text it displays.
----------------------------------------------------------------------------
local function PropType(prop)
    local ok, t = pcall(function() return prop:GetClass():GetFName():ToString() end)
    return ok and t or "?"
end

local function Scalar(v)
    local t = type(v)
    if t ~= "userdata" then return tostring(v) end
    for _, m in ipairs({ "ToString", "GetFullName" }) do
        local ok, s = pcall(function() return v[m](v) end)
        if ok and s ~= nil then return tostring(s) end
    end
    return tostring(v)
end

-- pcall result -> value, keeping false (not `ok and v or ...`, which turns false into the fallback).
local function Readable(ok, v)
    if ok then return v end
    return "<unreadable>"
end

local DumpVal
DumpVal = function(v, prop, label, indent, depth)
    local pad = string.rep("  ", indent)
    local t = PropType(prop)
    if depth > 4 then Log(pad .. label .. " = <depth limit>") return end
    if t == "StructProperty" then
        local sname = "?"
        pcall(function() sname = prop:GetStruct():GetFName():ToString() end)
        Log(pad .. label .. " <" .. sname .. ">")
        pcall(function()
            prop:GetStruct():ForEachProperty(function(sp)
                local n = sp:GetFName():ToString()
                local ok, sv = pcall(function() return v[n] end)
                DumpVal(Readable(ok, sv), sp, n, indent + 1, depth + 1)
            end)
        end)
    elseif t == "ArrayProperty" then
        local n = 0
        pcall(function() n = #v end)
        Log(pad .. label .. " [" .. n .. "]")
        local inner = nil
        pcall(function() inner = prop:GetInner() end)
        pcall(function()
            v:ForEach(function(i, e)
                if i > 64 then Log(pad .. "  ...") return true end
                local ev = e:get()
                if inner then DumpVal(ev, inner, "[" .. i .. "]", indent + 1, depth + 1)
                else Log(pad .. "  [" .. i .. "] " .. Scalar(ev)) end
            end)
        end)
    elseif t == "MapProperty" then
        local n = 0
        pcall(function() n = #v end)
        Log(pad .. label .. " (map, " .. n .. ")")
        pcall(function()
            v:ForEach(function(k, e) Log(pad .. "  " .. Scalar(k:get()) .. " => " .. Scalar(e:get())) end)
        end)
    elseif t == "ObjectProperty" then
        local s = Scalar(v)
        -- Text widgets: show what they display.
        pcall(function()
            if v:IsValid() and (v:IsA("/Script/UMG.TextBlock") or v:IsA("/Script/UMG.RichTextBlock")) then
                s = s .. '  TEXT="' .. v:GetText():ToString() .. '"'
            end
        end)
        Log(pad .. label .. " = " .. s)
    elseif t == "DelegateProperty" or t == "MulticastInlineDelegateProperty"
        or t == "MulticastSparseDelegateProperty" then
        -- noise
    else
        Log(pad .. label .. " (" .. t .. ") = " .. Scalar(v))
    end
end

-- All properties of obj declared by classes up to (not including) stopAt (e.g. UserWidget).
local function DumpObject(obj, stopAt)
    Log("OBJECT " .. obj:GetFullName())
    local cls = obj:GetClass()
    while valid(cls) do
        local cname = cls:GetFName():ToString()
        if stopAt and stopAt[cname] then break end
        cls:ForEachProperty(function(prop)
            local n = prop:GetFName():ToString()
            local ok, v = pcall(function() return obj[n] end)
            DumpVal(Readable(ok, v), prop, cname .. "." .. n, 1, 0)
        end)
        cls = cls:GetSuperStruct()
    end
end

local function LiveInstances(className)
    local out = {}
    for _, o in ipairs(FindAllOf(className) or {}) do
        if valid(o) and not o:GetFullName():find("Default__") then table.insert(out, o) end
    end
    return out
end

local function ChipInfo()
    local stopUI = { UserWidget = true, Widget = true, Visual = true, Object = true }
    local stopActor = { Actor = true, Object = true }

    -- 1. Where the Backpack keeps chips.
    local bp = GetBackpack()
    if bp then
        Log("=== Backpack properties (values only for chip/board/slot ones) ===")
        local cls = bp:GetClass()
        while valid(cls) and cls:GetFName():ToString() ~= "Object" do
            cls:ForEachProperty(function(prop)
                local n = prop:GetFName():ToString()
                local l = n:lower()
                if l:find("chip") or l:find("board") or l:find("upgrade") then
                    local ok, v = pcall(function() return bp[n] end)
                    DumpVal(Readable(ok, v), prop, n, 1, 0)
                else
                    Log("  " .. n .. " (" .. PropType(prop) .. ")")
                end
            end)
            cls = cls:GetSuperStruct()
        end
    end

    -- 2. Chip widgets on the upgrade screen: stored data + displayed text side by side.
    for _, cn in ipairs({ "WeaponUpgradeChipWidget", "WeaponUpgradeSlotWidget" }) do
        local list = LiveInstances(cn)
        Log("=== " .. cn .. ": " .. #list .. " live ===")
        for i, w in ipairs(list) do
            if i > 40 then Log("  ...") break end
            DumpObject(w, stopUI)
        end
    end

    -- 3. Spawned chip items (world pickups / temporary actors).
    local items = LiveInstances("ChipItem")
    Log("=== ChipItem: " .. #items .. " live ===")
    for i, c in ipairs(items) do
        if i > 20 then break end
        DumpObject(c, stopActor)
    end

    -- 4. Cheat manager chip/board commands (the old "chip command").
    pcall(function()
        local pc = UEHelpers.GetPlayerController()
        local cm = pc.CheatManager
        Log("=== CheatManager " .. cm:GetFullName() .. " ===")
        local cls = cm:GetClass()
        while valid(cls) do
            cls:ForEachFunction(function(fn)
                local n = fn:GetFName():ToString()
                local l = n:lower()
                if l:find("chip") or l:find("board") or l:find("upgrade") or l:find("perk") then
                    local ok, sig = pcall(function() return ParamsString(ReflectParams(fn)) end)
                    Log("  " .. cls:GetFName():ToString() .. ":" .. n .. (ok and sig or ""))
                end
            end)
            cls = cls:GetSuperStruct()
        end
    end)
    Notify("Chip info written to UE4SS.log")
end

-- rcchipmap: for every chip widget on the upgrade screen, the chip's stored shape/rotation/
-- boost next to what the widget actually shows (arm images, rotation angle, output
-- directions, value text). Gives the arms<->rotation mapping and the boost->% formula.
local function TextsOf(obj)
    local out = {}
    if not valid(obj) then return out end
    pcall(function()
        local cls = obj:GetClass()
        while valid(cls) do
            local cname = cls:GetFName():ToString()
            if cname == "UserWidget" or cname == "Widget" then break end
            cls:ForEachProperty(function(prop)
                local n, t = prop:GetFName():ToString(), PropType(prop)
                if t == "TextProperty" or t == "StrProperty" then
                    local ok, v = pcall(function() return obj[n]:ToString() end)
                    if ok and v ~= "" then table.insert(out, n .. '="' .. v .. '"') end
                elseif t == "ObjectProperty" then
                    pcall(function()
                        local o = obj[n]
                        if o:IsValid() and (o:IsA("/Script/UMG.TextBlock") or o:IsA("/Script/UMG.RichTextBlock")) then
                            table.insert(out, n .. '="' .. o:GetText():ToString() .. '"')
                        end
                    end)
                end
            end)
            cls = cls:GetSuperStruct()
        end
    end)
    return out
end

local function SetValues(set)
    local vals = {}
    pcall(function() set:ForEach(function(e) table.insert(vals, Scalar(e:get())) end) end)
    table.sort(vals)
    return "{" .. table.concat(vals, ",") .. "}"
end

local function ChipMap()
    local VIS = { [0] = "Vis", [1] = "Collapsed", [2] = "Hidden", [3] = "HitTestInv", [4] = "SelfHitTestInv" }
    local shapeName = {}
    for n, v in pairs(ChipEnumValues() or {}) do shapeName[v] = n end
    local seen, lines, pctSeen = {}, {}, {}
    for _, w in ipairs(LiveInstances("WeaponUpgradeChipWidget")) do
        pcall(function()
            local chip = w.Chip
            if not (chip and chip:IsValid()) then return end
            local shape, rot = chip.ConnectionType, chip.RotationOffset
            local arms = {}
            for _, a in ipairs({ "Up", "Right", "Down", "Left" }) do
                local s = "?"
                pcall(function() s = VIS[w[a]:GetVisibility()] or tostring(w[a]:GetVisibility()) end)
                table.insert(arms, a .. ":" .. s)
            end
            local angle = "?"
            pcall(function() angle = tostring(w.Overlay_Directions.RenderTransform.Angle) end)
            pcall(function() if angle == "?" then angle = tostring(w.Overlay_Directions:GetRenderTransformAngle()) end end)
            local key = string.format("%s rot=%s | widgetRot=%s angle=%s | out=%s base=%s | %s",
                shapeName[shape] or tostring(shape), tostring(rot), tostring(w.Rotation), angle,
                SetValues(w.OutputDirections), SetValues(w.BaseConnections), table.concat(arms, " "))
            if not seen[key] then seen[key] = true table.insert(lines, key) end
            local texts = table.concat(TextsOf(w.WB_StaticText_Value), " ")
            local pkey = string.format("boost=%d tier=%d strength=%s -> %s", chip.Boost, chip.ChipTier,
                tostring(w.ChipStrength), texts)
            if not pctSeen[pkey] then pctSeen[pkey] = true table.insert(lines, "  VALUE " .. pkey) end
        end)
    end
    Log("=== chip map: " .. #lines .. " unique lines ===")
    table.sort(lines)
    for _, l in ipairs(lines) do Log(l) end
    Notify("Chip map written to UE4SS.log (" .. #lines .. " lines)")
end

----------------------------------------------------------------------------
-- Skill points. Native names from the game exe (2026-11-13):
--   * the cheat manager has AddSkillPoints (next to AddWeapon, UnlockAllSkills...);
--   * a progression class has FreeSkillPoints (unspent points), SetSkillPoints,
--     AddSkillPoint and ConsumeSkillPoint (next to ExpLevel, OnLevelUp, WeaponBoards).
-- Signatures and the progression class name are read by reflection at runtime, and a
-- call is only made when it takes exactly one int. Primary path is the game's own cheat;
-- FreeSkillPoints before/after verifies it, and SetSkillPoints(current + n) is the
-- fallback (no CheatManager, or the cheat changed nothing).
----------------------------------------------------------------------------
local DEFAULT_SKILL_POINTS = 1
local MAX_SKILL_POINTS_PER_GIVE = 100
local SKILL_SET_FUNC = "SetSkillPoints"
local SKILL_FREE_PROP = "FreeSkillPoints"

local function SingleIntParam(params)
    if not params then return false end
    local ins = {}
    for _, p in ipairs(params) do
        if p.name:lower() ~= "returnvalue" and not p.out then table.insert(ins, p) end
    end
    return #ins == 1 and ins[1].type == "IntProperty"
end

local progressionClass = nil -- native class owning SetSkillPoints, found once by reflection
local function GetProgression()
    if not progressionClass then
        local fns = FindFunctionsNamed({ [SKILL_SET_FUNC] = true })
        for _, fn in ipairs(fns) do Log("Found " .. fn:GetFullName() .. ParamsString(ReflectParams(fn))) end
        if #fns ~= 1 then Log(#fns .. " " .. SKILL_SET_FUNC .. " functions in memory; expected 1") return nil end
        progressionClass = fns[1]:GetOuter():GetFName():ToString()
    end
    -- Exactly one live instance, or none at all: never write to a stale one left over
    -- from a previous level (same rule as GetBackpack).
    local live = LiveInstances(progressionClass)
    if #live ~= 1 then
        Log(string.format("%d live %s object(s); not using any", #live, progressionClass))
        for _, o in ipairs(live) do Log("    " .. o:GetFullName()) end
        return nil
    end
    return live[1]
end

local function ReadFreeSkillPoints(prog)
    if not valid(prog) then return nil end
    local ok, v = pcall(function() return prog[SKILL_FREE_PROP] end)
    return (ok and type(v) == "number") and v or nil
end

local function GiveSkillPoints(n)
    n = math.max(1, math.min(MAX_SKILL_POINTS_PER_GIVE, math.floor(tonumber(n) or DEFAULT_SKILL_POINTS)))
    local prog = GetProgression()
    local before = ReadFreeSkillPoints(prog)
    Log(string.format("Skill points: progression=%s %s=%s",
        valid(prog) and prog:GetFullName() or "none", SKILL_FREE_PROP, tostring(before)))

    -- 1. The game's own cheat command.
    local done = false
    local cm = nil
    pcall(function() cm = UEHelpers.GetPlayerController().CheatManager end)
    if valid(cm) then
        local params = GetFunctionParams(cm, "AddSkillPoints")
        if SingleIntParam(params) then
            Log("Calling " .. cm:GetFullName() .. ":" .. SignatureString("AddSkillPoints", params) .. " with " .. n)
            local ok, err = pcall(function() cm:AddSkillPoints(n) end)
            if ok then
                done = true
                local after = ReadFreeSkillPoints(prog)
                if before and after == before then
                    Log("AddSkillPoints didn't change " .. SKILL_FREE_PROP .. "; trying " .. SKILL_SET_FUNC)
                    done = false
                end
            else
                Log("AddSkillPoints errored: " .. tostring(err))
            end
        else
            Log("CheatManager " .. SignatureString("AddSkillPoints", params) .. ": not a single int, skipping")
        end
    else
        Log("No CheatManager (is CheatManagerEnablerMod enabled?); trying " .. SKILL_SET_FUNC)
    end

    -- 2. Fallback: set the unspent count directly.
    if not done then
        if not (prog and before) then
            Notify("Couldn't add skill points: player progression not found (load into a level first).")
            return
        end
        local params = GetFunctionParams(prog, SKILL_SET_FUNC)
        if not SingleIntParam(params) then
            Notify("Couldn't add skill points: " .. SignatureString(SKILL_SET_FUNC, params) .. " is not a single int.")
            return
        end
        Log("Calling " .. prog:GetFullName() .. ":" .. SignatureString(SKILL_SET_FUNC, params) .. " with " .. (before + n))
        local ok, err = pcall(function() prog[SKILL_SET_FUNC](prog, before + n) end)
        if not ok then Notify(SKILL_SET_FUNC .. " failed: " .. tostring(err)) return end
    end

    local after = ReadFreeSkillPoints(prog)
    Notify(string.format("Added %d skill point%s%s", n, n == 1 and "" or "s",
        after and string.format(" (%d unspent)", after) or ""))
end

-- Removes all unspent skill points (once every skill is maxed, new levels keep granting
-- points the game can't spend and keeps reminding you about). Verified signature from the
-- log, 2026-11-13: PlayerProgressionManager:SetSkillPoints(int SkillPoints).
local function ClearSkillPoints()
    local prog = GetProgression()
    local before = ReadFreeSkillPoints(prog)
    if not (prog and before) then
        Notify("Couldn't remove skill points: player progression not found (load into a level first).")
        return
    end
    if before == 0 then Notify("No unspent skill points to remove.") return end
    local params = GetFunctionParams(prog, SKILL_SET_FUNC)
    if not SingleIntParam(params) then
        Notify("Couldn't remove skill points: " .. SignatureString(SKILL_SET_FUNC, params) .. " is not a single int.")
        return
    end
    Log("Calling " .. prog:GetFullName() .. ":" .. SignatureString(SKILL_SET_FUNC, params) .. " with 0")
    local ok, err = pcall(function() prog[SKILL_SET_FUNC](prog, 0) end)
    if not ok then Notify(SKILL_SET_FUNC .. " failed: " .. tostring(err)) return end
    local after = ReadFreeSkillPoints(prog)
    Notify(after == 0 and string.format("Removed %d unspent skill point%s", before, before == 1 and "" or "s")
                     or ("Tried to remove skill points, but " .. tostring(after) .. " are still unspent"))
end

----------------------------------------------------------------------------
-- Secrets & police work checklist.
-- The end-of-level grade ("OCP Bank secret #1 found", "Bank Intruder arrested") is a hidden
-- objective, OB_Evaluation, with one bool per item (L09_Secret_01 ...). Each level's own
-- script sets them during play (confirmed 2026-11-16: the SWAT challenge flag went 0 -> 1
-- mid-level) and they are saved with the game. The grade screen reads them at level end.
-- Items and texts below come from the extracted OB_Evaluation asset (which flag goes with
-- which grade line); headings are the game's chapter-select names. The flag prefix is the
-- grade group, not the map: e.g. the Juneberry Mall secret is set in the L12 map, and the
-- "20 - Downtown" flags in the L19_OpenCity maps. Flags the grade never reads
-- (L06_Secret_02, L15_PoliceWork_02/04) are left out.
----------------------------------------------------------------------------
local EVAL_CLASS = "/Game/Quests/OB_Evaluation.OB_Evaluation_C"
local SECRET, POLICE = "Secret", "Police work"

local EVAL_CHAPTERS = {
    { title = "01 - Channel 9 Headquarters", maps = { "^L01_" }, items = {
        { "L01_Secret_01", SECRET, "TV Station secret #1 found" },
        { "L01_Secret_02", SECRET, "TV Station secret #2 found" },
        { "L01_PoliceWork_01", POLICE, "All Office Hostages saved" },
        { "L01_PoliceWork_02", POLICE, "All Studio Hostages saved" } } },
    { title = "03 - Downtown", maps = { "^L03_" }, items = {
        { "L03_Secret_01", SECRET, "Arcade Owner connections discovered" },
        { "L03_Secret_02", SECRET, "Warning note for Maurice found" },
        { "L03_PoliceWork_01", POLICE, "Graffiti Artist busted" },
        { "L03_PoliceWork_02", POLICE, "The grocery store incident resolved" } } },
    { title = "06 - Steel Mill", maps = { "^L06_" }, items = {
        { "L06_Secret_01", SECRET, "Briggs' Squad Car investigated" },
        { "L06_Secret_03", SECRET, "All stolen OCP Chests found" },
        { "L06_PoliceWork_01", POLICE, "The challenge against ED-209 won" },
        { "L06_PoliceWork_02", POLICE, "Intoxicated Hostage saved" } } },
    { title = "09 - OCP Bank", maps = { "^L09_" }, items = {
        { "L09_Secret_01", SECRET, "OCP Bank secret #1 found" },
        { "L09_Secret_02", SECRET, "OCP Bank secret #2 found" },
        { "L09_PoliceWork_01", POLICE, "The challenge against SWAT Team won" },
        { "L09_PoliceWork_02", POLICE, "Bank Intruder arrested" } } },
    { title = "11 - Downtown / 12 - Juneberry Mall", maps = { "^L11_", "^L12_" }, items = {
        { "L11_Secret_01", SECRET, "Downtown secret found" },
        { "L11_Secret_02", SECRET, "Juneberry Mall secret found" },
        { "L11_PoliceWork_01", POLICE, "All Courthouse hostages saved" },
        { "L11_PoliceWork_02", POLICE, "Samantha's belongings recovered" } } },
    { title = "15 - Old Factory", maps = { "^L15_" }, items = {
        { "L15_Secret_01", SECRET, "All stolen OCP Chests found" },
        { "L15_PoliceWork_01", POLICE, "All hostiles neutralized in under 10 min." },
        { "L15_PoliceWork_03", POLICE, "At least 25 UEDs decapitated" } } },
    { title = "17 - OCP Correctional Facility", maps = { "^L17_" }, items = {
        { "L17_Secret_01", SECRET, "Warden's gift discovered" },
        { "L17_Secret_02", SECRET, "Note about Wendell Antonowsky found" },
        { "L17_PoliceWork_01", POLICE, "Prisoners released from the freezer" },
        { "L17_PoliceWork_02", POLICE, "Cunning Prisoner stopped" },
        { "L17_PoliceWork_03", POLICE, "Electric chair execution stopped" } } },
    { title = "20 - Downtown", maps = { "^L19_OpenCity", "^L20_" }, items = {
        { "L20_Secret_01", SECRET, "All stolen OCP Chests found" },
        { "L20_PoliceWork_01", POLICE, "Fish Shop Owner saved" },
        { "L20_PoliceWork_02", POLICE, "Cat rescued from the Burning Hotel" } } },
}

-- Waypoint targets: the actor whose event sets each flag, found by decompiling the level
-- scripts (kismet-analyzer + the game's .usmap, 2026-11-16) and tracing back from the flag
-- write to the bound event. Only items tied to one spot; "all hostages saved", kill
-- contests and the chest counters have no single actor. Several paths = any of them.
local function MapActor(map, actor)
    local name = map:match("([^/]+)$")
    return "/Game/Maps/" .. map .. "." .. name .. ":PersistentLevel." .. actor
end
local WAYPOINT_TARGETS = {
    -- InvestigationFinished of this helper sets the flag
    L01_Secret_01 = { MapActor("L01_Prologue/L01_PrologueTVstation_Gameplay", "BP_InvestigationHelper_C_2") },
    L01_Secret_02 = { MapActor("L01_Prologue/L01_PrologueTVstation_Gameplay", "BP_InvestigationHelper_C_3") },
    L09_Secret_01 = { MapActor("L09_BankHeist/L09_BankHeist_Gameplay", "BP_InvestigationHelper_C_1") },
    -- ItemLooted of either loot item (same DoOnce gate)
    L09_Secret_02 = { MapActor("L09_BankHeist/L09_BankHeist_GameplayPart4", "B_LootItem_C_0"),
                      MapActor("L09_BankHeist/L09_BankHeist_GameplayPart4", "B_LootItem_C_1") },
    L11_Secret_02 = { MapActor("L12_HauntedMall/L12_HauntedMall_Gameplay", "BP_InvestigationHelper_C_1") },
    -- InteractionFinished
    L11_PoliceWork_02 = { MapActor("L11_OpenCity/L11_OpenCity_Gameplay", "B_InteractionHelper_C_567") },
    L17_Secret_01 = { MapActor("L17_Prison/L17_Prison_GameplayMainFlow", "BP_InvestigationHelper_C_1") },
    -- OnTaken
    L17_Secret_02 = { MapActor("L17_Prison/L17_Prison_GameplayMainFlow", "B_ArchiveIndexItem_C_1") },
    -- OnOpeningStart of the door
    L17_PoliceWork_01 = { MapActor("L17_Prison/L17_Prison_GameplayMainFlow", "BP_DoubleDoor_C_5") },
    L20_PoliceWork_02 = { MapActor("L19_OpenCity/L19_Interiors/L19_INT_Hotel/L19_INT_Hotel_Gameplay", "BP_SingleDoor_C_3") },
}

-- The evaluation objective the game itself uses (there can be several identical copies in
-- memory; the current GameState's ObjectivesManager hands out the live one).
local function GetEvaluation()
    local cls = StaticFindObject(EVAL_CLASS)
    if not valid(cls) then return nil end
    local mgr, ev = nil, nil
    pcall(function() mgr = UEHelpers.GetWorld().GameState.ObjectivesManager end)
    if not valid(mgr) then return nil end
    pcall(function() ev = mgr:GetObjective(cls) end)
    return valid(ev) and ev or nil
end

local function CurrentMapName()
    local name = nil
    pcall(function() name = UEHelpers.GetWorld():GetFName():ToString() end)
    return name
end

local function ChapterForMap(map)
    if not map then return nil end
    for _, ch in ipairs(EVAL_CHAPTERS) do
        for _, pat in ipairs(ch.maps) do
            if map:find(pat) then return ch end
        end
    end
    return nil
end

-- { chapters = { { chapter, current, found = n, items = { { text, kind, found (bool|nil) } } } } }
-- or nil when not in a game (main menu, loading).
local function ReadChecklist()
    local ev = GetEvaluation()
    if not ev then return nil end
    local here = ChapterForMap(CurrentMapName())
    local out = { current = here, chapters = {} }
    for _, ch in ipairs(EVAL_CHAPTERS) do
        local c = { chapter = ch, current = (ch == here), found = 0, items = {} }
        for _, it in ipairs(ch.items) do
            local ok, v = pcall(function() return ev[it[1]] end)
            local found = nil
            if ok and type(v) == "boolean" then found = v end
            if found then c.found = c.found + 1 end
            table.insert(c.items, { text = it[3], kind = it[2], found = found, flag = it[1],
                                    waypoint = WAYPOINT_TARGETS[it[1]] ~= nil })
        end
        table.insert(out.chapters, c)
    end
    return out
end

local function ChecklistMark(found)
    if found == nil then return "[?] " end
    return found and "[X] " or "[  ] "
end

-- Waypoints: the game's own custom map waypoint (B_3DCustomMarkerActor), made the way the
-- intranet map's AddPlaceable does it (decompiled WB_IntranetMap, 2026-11-16):
--   remove existing custom markers (RemovePlaceable destroys every B_3DCustomMarkerActor),
--   BeginDeferredActorSpawnFromClass(ctx, class, transform, 1, nil, 0), set ParentCanvas =
--   HUD:GetCanvasPanelObjectiveMarkers() (its BeginPlay adds the marker widget to that
--   canvas, so it must be set before FinishSpawningActor), FinishSpawningActor(actor,
--   transform, 0), then HUD.WB_Compass:"Add to Compass"(ObjectOnMapComponent,
--   ObjectOnMapComponent.Icon, LinearColor 0,0,0,0).
-- The marker removes itself when the player walks into it, and its EndPlay removes the widget.
local MARKER_DIR, MARKER_ASSET = "/Game/Blueprints/Abstract/", "B_3DCustomMarkerActor"

local function RemoveWaypoints()
    local n = 0
    for _, m in ipairs(LiveInstances(MARKER_ASSET .. "_C")) do
        if pcall(function() m:K2_DestroyActor() end) then n = n + 1 end
    end
    return n
end

local function FindWaypointTarget(flag)
    for _, path in ipairs(WAYPOINT_TARGETS[flag] or {}) do
        local a = StaticFindObject(path)
        if valid(a) then return a end
    end
    return nil
end

local function PlaceWaypoint(flag, label)
    local target = FindWaypointTarget(flag)
    if not target then
        Notify("Can't place that waypoint here. Go to that chapter (or closer to that area) first.")
        return
    end
    local cls = LoadClass(MARKER_DIR, MARKER_ASSET)
    local gs = StaticFindObject("/Script/Engine.Default__GameplayStatics")
    local gfl = StaticFindObject("/Script/Game.Default__GlobalFunctionLibrary")
    local pc = UEHelpers.GetPlayerController()
    if not (valid(cls) and valid(gs) and valid(gfl) and valid(pc)) then
        Notify("Waypoint: game classes not found (see UE4SS.log).")
        Log(string.format("Waypoint: class=%s gs=%s gfl=%s pc=%s", tostring(valid(cls)), tostring(valid(gs)),
            tostring(valid(gfl)), tostring(valid(pc))))
        return
    end
    local hud, canvas, compass = nil, nil, nil
    pcall(function() hud = gfl:GetHUD(pc) end)
    pcall(function() canvas = hud:GetCanvasPanelObjectiveMarkers() end)
    pcall(function() compass = hud.WB_Compass end)
    if not (valid(hud) and valid(canvas)) then
        Notify("Waypoint: the HUD isn't available right now.")
        Log("Waypoint: HUD " .. tostring(valid(hud)) .. ", marker canvas " .. tostring(valid(canvas)))
        return
    end
    local loc = target:K2_GetActorLocation()
    local transform = {
        Rotation = { X = 0.0, Y = 0.0, Z = 0.0, W = 1.0 },
        Translation = { X = loc.X, Y = loc.Y, Z = loc.Z },
        Scale3D = { X = 1.0, Y = 1.0, Z = 1.0 },
    }
    local removed = RemoveWaypoints()
    local okB, marker = pcall(function() return gs:BeginDeferredActorSpawnFromClass(pc, cls, transform, 1, nil, 0) end)
    if not okB or not valid(marker) then
        Notify("Waypoint: spawning the marker failed (see UE4SS.log).")
        Log("Waypoint: BeginDeferredActorSpawnFromClass: " .. tostring(marker))
        return
    end
    local okP, errP = pcall(function() marker.ParentCanvas = canvas end)
    if not okP then Log("Waypoint: setting ParentCanvas: " .. tostring(errP)) end
    -- B_3DActorParent's BeginPlay only creates the on-screen marker widget when bIsTracked
    -- is set; a custom marker spawns with it off (logged 2026-11-16: bIsTracked=false,
    -- MarkerWidget=None). The intranet map never sets it, so its waypoint shows only on the
    -- compass/minimap. Only other reader: WB_MinimapItem (tracked style).
    local okT, errT = pcall(function() marker.bIsTracked = true end)
    if not okT then Log("Waypoint: setting bIsTracked: " .. tostring(errT)) end
    local okF, err = pcall(function() gs:FinishSpawningActor(marker, transform, 0) end)
    if not okF then Log("Waypoint: FinishSpawningActor: " .. tostring(err)) end
    -- State after BeginPlay, for the log.
    pcall(function()
        local function S(f) local ok, v = pcall(f) return ok and tostring(v) or "<err>" end
        local w = nil
        pcall(function() w = marker.MarkerWidget end)
        local ml = marker:K2_GetActorLocation()
        Log(string.format("Waypoint state: bIsTracked=%s ParentCanvas=%s canvasMatches=%s MarkerWidget=%s vis=%s inViewport=%s actorAt=(%.0f, %.0f, %.0f) TargetActor=%s",
            S(function() return marker.bIsTracked end),
            S(function() return valid(marker.ParentCanvas) end),
            S(function() return marker.ParentCanvas:GetAddress() == canvas:GetAddress() end),
            S(function() return valid(w) end),
            S(function() return w:GetVisibility() end),
            S(function() return w:IsInViewport() end),
            ml.X, ml.Y, ml.Z,
            S(function() return marker.TargetActor:GetFullName() end)))
    end)
    if valid(compass) then
        local okC, errC = pcall(function()
            local comp = marker.ObjectOnMapComponent
            compass["Add to Compass"](compass, comp, comp.Icon, { R = 0.0, G = 0.0, B = 0.0, A = 0.0 })
        end)
        if not okC then Log("Waypoint: Add to Compass: " .. tostring(errC)) end
    end
    Log(string.format("Waypoint for %s at %s (%.0f, %.0f, %.0f); removed %d old marker(s)",
        flag, target:GetFullName(), loc.X, loc.Y, loc.Z, removed))
    Notify("Waypoint set: " .. (label or flag))
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
if DEV_TOOLS then
    RegisterKeyBind(Key.F6, function()
        ExecuteInGameThread(function() DumpApi() ChipDump() end)
    end)
    RegisterKeyBind(Key.F6, { ModifierKey.CONTROL }, function()
        ExecuteInGameThread(ChipMap)
    end)
end

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
    if Params[1]:lower():find("^b_ammo") then
        local amount = tonumber(Params[2]) or DEFAULT_AMMO_AMOUNT
        Out(Ar, "That's ammo, treating as: giveammo " .. Params[1] .. " " .. amount)
        ExecuteInGameThread(function() GiveAmmo(Params[1], amount) end)
        return true
    end
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

RegisterConsoleCommandHandler("givechip", function(_, Params, Ar)
    local mask = Params[1] and ParseArms(Params[1]) or 0
    if mask == 0 then Out(Ar, "Usage: givechip <arms U/R/D/L> [percent] [look 1-4]   e.g. givechip UR 45") return true end
    local pct = tonumber(Params[2]) or DEFAULT_CHIP_PERCENT
    local look = tonumber(Params[3]) or (DEFAULT_CHIP_TIER + 1)
    ExecuteInGameThread(function() GiveChip(mask, pct, look) end)
    return true
end)

RegisterConsoleCommandHandler("dlcweapon", function(_, Params, Ar)
    if #Params < 1 then
        Out(Ar, "DLC starting weapon: " .. DlcWeaponName())
        Out(Ar, "Usage: dlcweapon <index|name|default>   (see givelist)")
        return true
    end
    local q = table.concat(Params, " ")
    local asset = "default"
    if q:lower() ~= "default" then
        local w = FindWeapon(q)
        if not w then Out(Ar, "No weapon matches '" .. q .. "'") return true end
        asset = w[2]
    end
    ExecuteInGameThread(function() SetDlcWeapon(asset) end)
    return true
end)

RegisterConsoleCommandHandler("giveskill", function(_, Params, Ar)
    local n = tonumber(Params[1] or "") or DEFAULT_SKILL_POINTS
    ExecuteInGameThread(function() GiveSkillPoints(n) end)
    return true
end)

RegisterConsoleCommandHandler("clearskill", function()
    ExecuteInGameThread(ClearSkillPoints)
    return true
end)

RegisterConsoleCommandHandler("secrets", function(_, _, Ar)
    ExecuteInGameThread(function()
        local list = ReadChecklist()
        if not list then Out(Ar, "Available once you're in a level.") return end
        -- This chapter first, then the rest.
        local order = {}
        for _, c in ipairs(list.chapters) do
            if c.current then table.insert(order, 1, c) else table.insert(order, c) end
        end
        if not list.current then Out(Ar, "This chapter has no secrets or police work.") end
        for _, c in ipairs(order) do
            Out(Ar, string.format("%s: %d/%d%s", c.chapter.title, c.found, #c.items, c.current and "  (this chapter)" or ""))
            for _, it in ipairs(c.items) do Out(Ar, "  " .. ChecklistMark(it.found) .. it.text) end
        end
    end)
    return true
end)

RegisterConsoleCommandHandler("boardlist", function(_, _, Ar)
    ExecuteInGameThread(function()
        for i, r in ipairs(GetBoardRows()) do Out(Ar, string.format("%2d  %s", i, r)) end
    end)
    return true
end)

RegisterConsoleCommandHandler("giveboard", function(_, Params, Ar)
    if #Params < 1 then Out(Ar, "Usage: giveboard <index|row>   (see boardlist)") return true end
    ExecuteInGameThread(function()
        local rows = GetBoardRows()
        local row = rows[tonumber(Params[1]) or -1]
        if not row then
            for _, r in ipairs(rows) do if r:lower() == Params[1]:lower() then row = r break end end
        end
        if not row then Notify("No board row matches " .. Params[1]) return end
        GiveBoard(row)
    end)
    return true
end)

----------------------------------------------------------------------------
-- Pause menu research (dev tools): rcmenudump / rcmenuwatch.
-- Goal: add a "RoboCop Cheats" entry to the pause menu (/Game/UI/Menu/WB_InGameMenu).
-- Open the pause menu (Esc) first so the widget and its classes exist.
----------------------------------------------------------------------------
local MENU_DIR = "/Game/UI/Menu/"
local MENU_GLOBALS = "/Game/UI/Globals/"
local MENU_CLASSES = { "WB_InGameMenu", "WB_InGameMenuButton", "WB_InGameMenuButton02" }
local VIS_NAMES = { [0] = "Visible", [1] = "Collapsed", [2] = "Hidden",
                    [3] = "HitTestInvisible", [4] = "SelfHitTestInvisible" }

local function MenuClass(cn)
    return StaticFindObject(MENU_DIR .. cn .. "." .. cn .. "_C")
end

local function WidgetLine(w)
    local s = tostring(w)
    pcall(function() s = w:GetClass():GetFName():ToString() .. " " .. w:GetFName():ToString() end)
    pcall(function() s = s .. "  vis=" .. (VIS_NAMES[w.Visibility] or tostring(w.Visibility)) end)
    pcall(function()
        if w:IsA("/Script/UMG.TextBlock") or w:IsA("/Script/UMG.RichTextBlock") then
            s = s .. '  TEXT="' .. w:GetText():ToString() .. '"'
        end
    end)
    pcall(function()
        local slot = w.Slot
        if valid(slot) then s = s .. "  slot=" .. slot:GetClass():GetFName():ToString() end
    end)
    return s
end

-- Panels (incl. Border/Button/SizeBox) list children in Slots[i].Content; user widgets
-- have their own WidgetTree.RootWidget. userDepth limits how many nested user widgets we open.
local DumpWidgetTree
DumpWidgetTree = function(w, indent, depth, userDepth)
    if not valid(w) then return end
    local pad = string.rep("  ", indent)
    Log(pad .. WidgetLine(w))
    if depth > 14 then Log(pad .. "  <depth limit>") return end
    local isPanel, isUser = false, false
    pcall(function() isPanel = w:IsA("/Script/UMG.PanelWidget") end)
    pcall(function() isUser = w:IsA("/Script/UMG.UserWidget") end)
    if isPanel then
        pcall(function()
            w.Slots:ForEach(function(_, e)
                local slot = e:get()
                if valid(slot) then DumpWidgetTree(slot.Content, indent + 1, depth + 1, userDepth) end
            end)
        end)
    end
    if isUser and userDepth > 0 then
        pcall(function()
            local root = w.WidgetTree.RootWidget
            if valid(root) then
                Log(pad .. "  {own tree}")
                DumpWidgetTree(root, indent + 2, depth + 1, userDepth - 1)
            end
        end)
    end
end

-- Functions (with signature and flags) and property names/types declared by cls and its
-- parents, up to (not including) the classes in stopAt.
local function DumpClassApi(cls, stopAt)
    while valid(cls) do
        if stopAt[cls:GetFName():ToString()] then break end
        Log("  -- " .. cls:GetFullName())
        cls:ForEachFunction(function(fn)
            local ok, sig = pcall(function() return ParamsString(ReflectParams(fn)) end)
            local flags = 0
            pcall(function() flags = fn:GetFunctionFlags() end)
            Log(string.format("    fn %s%s  flags=0x%X", fn:GetFName():ToString(), ok and sig or "(?)", flags))
        end)
        cls:ForEachProperty(function(prop)
            local t = PropType(prop)
            if t == "ObjectProperty" or t == "ClassProperty" then
                pcall(function() t = t .. "<" .. prop:GetPropertyClass():GetFName():ToString() .. ">" end)
            end
            Log("    prop " .. prop:GetFName():ToString() .. " : " .. t)
        end)
        cls = cls:GetSuperStruct()
    end
end

----------------------------------------------------------------------------
-- Level evaluation research (dev tools): rcevaldump. Run it mid-level.
-- The end-of-level grade ("OCP Bank secret #1 found", "Bank Intruder arrested") comes from
-- a hidden objective, /Game/Quests/OB_Evaluation (a DT_ObjectiveData row like every quest).
-- Its stages are named L<nn>_Secret_<n> / L<nn>_PoliceWork_<n>, and at level end it calls
-- GetObjectiveState per stage (found by extracting the asset with retoc, 2026-11-16).
-- Goal: an in-game checklist of the current level's secrets. This only reads: it logs the
-- native objective API, the live objectives and every property of OB_Evaluation.
----------------------------------------------------------------------------
local EVAL_FUNCS = { GetObjectiveState = true, GetObjectiveStage = true, GetObjectivesStages = true,
                     ActivateEvaluation = true, SetObjectiveState = true, SetObjectiveStage = true,
                     CompleteObjective = true, CompleteObjectiveStage = true }
local OBJECTIVE_TABLE = "/Game/Blueprints/Abstract/Config/DT_ObjectiveData.DT_ObjectiveData"

local SCALAR_TYPES = { BoolProperty = true, IntProperty = true, ByteProperty = true, EnumProperty = true,
                       FloatProperty = true, DoubleProperty = true, NameProperty = true, StrProperty = true,
                       TextProperty = true }

-- Property names and types of obj; values only for plain scalars and object references.
-- Never reads arrays/maps/structs.
-- Only Object/ClassProperty may be asked GetPropertyClass(): UE4SS doesn't check the type,
-- so on e.g. a BoolProperty it reads junk as a pointer and crashes natively (pcall can't
-- catch it). That crashed rcevaldump twice on 2026-11-16 (BP_MyGameState's properties).
local HAS_PROPERTY_CLASS = { ObjectProperty = true, ClassProperty = true }
local function ListProps(obj, stopAt, filter)
    local cls = obj:GetClass()
    while valid(cls) and not stopAt[cls:GetFName():ToString()] do
        local cname = cls:GetFName():ToString()
        cls:ForEachProperty(function(prop)
            local n, t = prop:GetFName():ToString(), PropType(prop)
            local pc = ""
            if HAS_PROPERTY_CLASS[t] then
                pcall(function() pc = prop:GetPropertyClass():GetFName():ToString() end)
            end
            if filter and not (n .. " " .. pc):lower():find(filter, 1, true) then return end
            local line = "  " .. cname .. "." .. n .. " : " .. t .. (pc ~= "" and ("<" .. pc .. ">") or "")
            if SCALAR_TYPES[t] or t == "ObjectProperty" then
                local ok, v = pcall(function() return obj[n] end)
                line = line .. " = " .. (ok and Scalar(v) or "<unreadable>")
            end
            Log(line)
        end)
        cls = cls:GetSuperStruct()
    end
end

-- One line per OB_Evaluation copy: state plus every L<nn>_ flag.
local function EvalFlagsLine(e)
    local flags = {}
    pcall(function()
        e:GetClass():ForEachProperty(function(prop)
            local n = prop:GetFName():ToString()
            if n:match("^L%d%d_") then
                local ok, v = pcall(function() return e[n] end)
                table.insert(flags, n:gsub("_Secret_0", "S"):gsub("_PoliceWork_0", "P") .. "="
                    .. (not ok and "?" or (v and "1" or "0")))
            end
        end)
    end)
    local state, stage = "?", "?"
    pcall(function() state = tostring(e.State) end)
    pcall(function() stage = tostring(e.CurrentStage) end)
    return string.format("  %s @%X State=%s Stage=%s  %s", e:GetFName():ToString(), e:GetAddress(),
        state, stage, table.concat(flags, " "))
end

local function EvalDump()
    Log("=== rcevaldump ===")
    -- 1. The functions the evaluation blueprint calls, wherever they live.
    for _, fn in ipairs(FindFunctionsNamed(EVAL_FUNCS)) do
        local ok, sig = pcall(function() return ParamsString(ReflectParams(fn)) end)
        local flags = 0
        pcall(function() flags = fn:GetFunctionFlags() end)
        Log(string.format("  %s%s  flags=0x%X", fn:GetFullName(), ok and sig or "(?)", flags))
    end

    -- 2. Native objective class API.
    local objCls = StaticFindObject("/Script/Game.Objective")
    if valid(objCls) then
        Log("=== /Script/Game.Objective API ===")
        DumpClassApi(objCls, { Actor = true, Object = true })
    else
        Log("  /Script/Game.Objective not found")
    end

    -- 3. Live objectives. (First run: 132 = 4 copies of each objective. Why 4?)
    local live = LiveInstances("Objective")
    Log("=== " .. #live .. " live Objective(s) ===")
    for _, o in ipairs(live) do Log("  " .. o:GetFullName()) end

    -- 4. The evaluation objective: all copies side by side, full dump of the first.
    local evals = LiveInstances("OB_Evaluation_C")
    Log("=== " .. #evals .. " live OB_Evaluation_C ===")
    for _, e in ipairs(evals) do Log(EvalFlagsLine(e)) end
    if evals[1] then DumpObject(evals[1], { Actor = true, Object = true }) end

    -- 5. The objective table's row layout.
    local dt = StaticFindObject(OBJECTIVE_TABLE)
    if valid(dt) then
        pcall(function() Log("  Objective row struct: " .. dt:GetRowStruct():GetFullName()) end)
        pcall(function()
            dt:GetRowStruct():ForEachProperty(function(prop)
                Log("    field " .. PropType(prop) .. " " .. prop:GetFName():ToString())
            end)
        end)
    else
        Log("  " .. OBJECTIVE_TABLE .. " not loaded")
    end

    -- 6. ObjectivesManager (owns GetObjectiveState(ObjectiveClass); lives on
    --    BP_MyGameState_C_0.ObjectivesManager): API and live copies. Scalars and object
    --    references only (see ListProps).
    local mgrCls = StaticFindObject("/Script/Game.ObjectivesManager")
    if valid(mgrCls) then
        Log("=== /Script/Game.ObjectivesManager API ===")
        DumpClassApi(mgrCls, { Object = true, ActorComponent = true, Actor = true, Info = true })
    end
    local mgrs = LiveInstances("ObjectivesManager")
    Log("=== " .. #mgrs .. " live ObjectivesManager ===")
    for _, m in ipairs(mgrs) do
        Log(string.format("OBJECT %s @%X", m:GetFullName(), m:GetAddress()))
        ListProps(m, { Object = true, ActorComponent = true, Actor = true, Info = true }, nil)
    end

    -- 7. Which copy the game itself uses: ObjectivesManager:GetObjective(ObjectiveClass)
    --    (signature from step 6's dump; read-only getter) on the current GameState's manager.
    local evalCls = StaticFindObject("/Game/Quests/OB_Evaluation.OB_Evaluation_C")
    local mgr = nil
    pcall(function() mgr = UEHelpers.GetWorld().GameState.ObjectivesManager end)
    if valid(mgr) and valid(evalCls) then
        local ok, real = pcall(function() return mgr:GetObjective(evalCls) end)
        if ok and valid(real) then
            Log("=== GameState.ObjectivesManager:GetObjective(OB_Evaluation_C) ===")
            Log(EvalFlagsLine(real))
        else
            Log("  GetObjective(OB_Evaluation_C) returned nothing")
        end
    else
        Log("  GameState.ObjectivesManager or OB_Evaluation_C class not found")
    end
    Notify("Evaluation info written to UE4SS.log")
end

-- Our pause menu buttons, by object address (the menu rebuilds its buttons on every open,
-- and there can be more than one WB_InGameMenu instance, so there can be several).
local cheatButtons = {}

local function IsCheatButton(o)
    if not valid(o) then return false end
    local ok, a = pcall(function() return o:GetAddress() end)
    return ok and cheatButtons[a] ~= nil
end

-- The pause menu's buttons (WB_InGameMenuButton02 inside a WB_ScrolledList), excluding ours.
-- Returns { {btn, parent, index}, ... }; logs them if verbose.
local function MenuButtons(verbose)
    local out = {}
    for _, b in ipairs(LiveInstances("WB_InGameMenuButton02_C")) do
        local parent, idx, text, id = nil, -1, "?", "?"
        pcall(function() parent = b:GetParent() end)
        if valid(parent) then pcall(function() idx = parent:GetChildIndex(b) end) end
        pcall(function() text = b.Text:ToString() end)
        pcall(function() id = tostring(b.ChildID) end)
        local mine = IsCheatButton(b)
        if verbose then
            Log(string.format("  button %s  index=%s  ChildID=%s  text=\"%s\"%s  parent=%s",
                b:GetFName():ToString(), tostring(idx), id, text, mine and "  (OURS)" or "",
                valid(parent) and parent:GetFullName() or "none"))
        end
        if valid(parent) and not mine then table.insert(out, { b, parent, idx }) end
    end
    return out
end

local function MenuDump()
    local stop = { UserWidget = true }
    local menus = LiveInstances("WB_InGameMenu_C")
    Log("=== WB_InGameMenu_C: " .. #menus .. " live ===")
    for i, m in ipairs(menus) do
        Log("--- menu " .. i .. ": " .. m:GetFullName())
        pcall(function() Log("  IsInViewport=" .. tostring(m:IsInViewport())) end)
        Log("  Widget tree:")
        DumpWidgetTree(m, 2, 0, 2)
        Log("  Property values:")
        DumpObject(m, stop)
    end
    for _, cn in ipairs(MENU_CLASSES) do
        local cls = MenuClass(cn)
        Log("=== class " .. cn .. "_C: " .. (valid(cls) and "loaded" or "NOT loaded") .. " ===")
        if valid(cls) then DumpClassApi(cls, stop) end
    end
    for _, cn in ipairs({ "WB_InGameMenuButton_C", "WB_InGameMenuButton02_C" }) do
        local btns = LiveInstances(cn)
        Log("=== " .. cn .. ": " .. #btns .. " live (values of the first) ===")
        if btns[1] then DumpObject(btns[1], stop) end
    end
    -- The list that holds the menu buttons (2026-11-13: WB_InGameMenu.WB_ScrolledList).
    local listCls = StaticFindObject(MENU_GLOBALS .. "WB_ScrolledList.WB_ScrolledList_C")
    Log("=== class WB_ScrolledList_C: " .. (valid(listCls) and "loaded" or "NOT loaded") .. " ===")
    if valid(listCls) then DumpClassApi(listCls, stop) end
    for i, m in ipairs(menus) do
        local list = nil
        pcall(function() list = m.WB_ScrolledList end)
        if valid(list) then
            Log("--- menu " .. i .. " WB_ScrolledList tree:")
            DumpWidgetTree(list, 2, 0, 1)
            Log("--- menu " .. i .. " WB_ScrolledList values:")
            DumpObject(list, stop)
        end
    end
    -- Keyboard/controller navigation research: the element base class's API, and per button
    -- whether it's focusable and which UMG navigation rules it has (Rule/Widget per direction).
    local elemCls = StaticFindObject(MENU_GLOBALS .. "WB_ScrolledListElem.WB_ScrolledListElem_C")
    Log("=== class WB_ScrolledListElem_C: " .. (valid(elemCls) and "loaded" or "NOT loaded") .. " ===")
    if valid(elemCls) then DumpClassApi(elemCls, stop) end
    for _, cn in ipairs({ "MenuWindowUserWidget", "MenuUserWidget" }) do
        local cls = StaticFindObject("/Script/Game." .. cn)
        Log("=== native class " .. cn .. ": " .. (valid(cls) and "found" or "NOT found") .. " ===")
        if valid(cls) then DumpClassApi(cls, { [cn == "MenuWindowUserWidget" and "MenuUserWidget" or "UserWidget"] = true }) end
    end
    Log("=== Navigation of each menu button ===")
    for _, b in ipairs(LiveInstances("WB_InGameMenuButton02_C")) do
        local line = b:GetFName():ToString()
        pcall(function() line = line .. '  "' .. b.Text:ToString() .. '"' end)
        pcall(function() line = line .. "  bIsFocusable=" .. tostring(b.bIsFocusable) end)
        pcall(function() line = line .. "  HasKeyboardFocus=" .. tostring(b:HasKeyboardFocus()) end)
        pcall(function() line = line .. "  HasFocusedDescendants=" .. tostring(b:HasFocusedDescendants()) end)
        Log("  " .. line)
        local nav = nil
        pcall(function() nav = b.Navigation end)
        if valid(nav) then
            DumpObject(nav, { Object = true })
        else
            Log("    Navigation: none (default rules)")
        end
    end
    MenuButtons(true)
    if #menus == 0 then
        Notify("No pause menu found. Open the pause menu (Esc), then run rcmenudump again.")
    else
        Notify("Pause menu info written to UE4SS.log")
    end
end

-- Toggle: hook every function the menu/button blueprints declare and log the calls, to see
-- which function runs when a menu button is clicked. Repeated calls are rate-limited.
local menuWatchHooks = {}
local function MenuWatch()
    if #menuWatchHooks > 0 then
        for _, h in ipairs(menuWatchHooks) do pcall(UnregisterHook, h[1], h[2], h[3]) end
        menuWatchHooks = {}
        Notify("Pause menu watch OFF")
        return
    end
    local calls = {}
    local classes = {}
    for _, cn in ipairs(MENU_CLASSES) do table.insert(classes, { MENU_DIR, cn }) end
    table.insert(classes, { MENU_GLOBALS, "WB_ScrolledList" })
    table.insert(classes, { MENU_GLOBALS, "WB_ScrolledListElem" })
    -- The menu's native parents (full path, no _C): in case navigation is handled in C++.
    table.insert(classes, { "/Script/Game.", "MenuWindowUserWidget", native = true })
    table.insert(classes, { "/Script/Game.", "MenuUserWidget", native = true })
    for _, dc in ipairs(classes) do
        local dir, cn = dc[1], dc[2]
        local clsPath = dc.native and (dir .. cn) or (dir .. cn .. "." .. cn .. "_C")
        local cls = StaticFindObject(clsPath)
        if not valid(cls) then
            Log("[menuwatch] " .. cn .. " not loaded (open the pause menu once first)")
        else
            local names = {}
            cls:ForEachFunction(function(fn)
                -- Skip pure delegate signatures (FUNC_Delegate 0x00100000); they never run.
                -- BndEvt__...__DelegateSignature handlers are real events and are kept.
                local flags = 0
                pcall(function() flags = fn:GetFunctionFlags() end)
                if (flags & 0x00100000) == 0 then table.insert(names, fn:GetFName():ToString()) end
            end)
            for _, fname in ipairs(names) do
                local l = fname:lower()
                if not (l:find("tick") or l:find("paint")) then
                    local path = clsPath .. ":" .. fname
                    local key = cn .. ":" .. fname
                    local ok, pre, post = pcall(RegisterHook, path, function(self)
                        local n = (calls[key] or 0) + 1
                        calls[key] = n
                        if n <= 5 or n % 100 == 0 then
                            local who = "?"
                            pcall(function() who = self:get():GetFName():ToString() end)
                            Log(string.format("[menuwatch] %s  on %s  (#%d)", key, who, n))
                        end
                    end)
                    if ok then
                        table.insert(menuWatchHooks, { path, pre, post })
                    else
                        Log("[menuwatch] can't hook " .. path .. ": " .. tostring(pre))
                    end
                end
            end
        end
    end
    Notify("Pause menu watch ON: " .. #menuWatchHooks
        .. " functions hooked. Use the pause menu, then run rcmenuwatch again to stop.")
end

----------------------------------------------------------------------------
-- In-game pause menu: a "RoboCop Cheats" entry at the bottom of the pause menu. Clicking it
-- swaps the menu's buttons for our own pages. Mouse, keyboard and controller.
--
-- How the pause menu works (rcmenudump / rcmenuwatch, 2026-11-13): every open creates a new
-- WB_InGameMenu_C, which fills its WB_ScrolledList (ScrollBox_6) with WB_InGameMenuButton02
-- buttons and calls the list's Finalize. A click reaches the menu as OnElementAction, and the
-- menu picks the action from the clicked button's child index. Our buttons are added straight
-- to the ScrollBox, never via WB_ScrolledList:AddItem, so their OnElementAction is never bound
-- to that handler; their clicks are caught with a hook on WB_ScrolledListElem_C:OnMouseButtonUp.
-- While one of our pages is open the game's buttons are collapsed, not removed, so their
-- indices don't change.
--
-- Keyboard/controller (rcmenuwatch, 2026-11-13): up/down runs the list's blueprint
-- HandleNavigationInput, which steps through its Elements array (CurrentID = selected index)
-- and calls SetActive/OnElementChoosenEvent. So our buttons are appended to Elements too.
-- Enter/A runs the native MenuWindowUserWidget:HandleActionInput on the menu -> menu Action ->
-- list OnActiveItemAction -> GetCurrentElement (Elements[CurrentID], None if CurrentID < 0) ->
-- the menu's child-index handler, which casts the element and checks IsValid first. When the
-- selected element is ours (or a hidden game button), a native pre-hook sets CurrentID to -1
-- for the duration of the call so the game's handler gets None, and runs our action instead.
----------------------------------------------------------------------------
local SLATE_COLLAPSED = 1
local CHIP_MENU_PERCENTS = { 15, 23, 30, 38, 45, 75, 150, 300 }
local AMMO_MENU_AMOUNTS = { 50, 100, 200, 500, 999 }
local SKILL_MENU_AMOUNTS = { 1, 5, 10, 25, 100 }
local CHIP_LOOKS = { "Normal", "Style 2 (ring)", "Style 3", "Style 4" } -- same names as dllmain.cpp

local menuChipArms, menuChipPercent, menuChipLook = ARM_UP | ARM_DOWN, DEFAULT_CHIP_PERCENT, 1
local menuAmmoAmount, menuSkillAmount = DEFAULT_AMMO_AMOUNT, DEFAULT_SKILL_POINTS

-- menu address -> { menu, page, buttons = {addr...}, entries = {btn...}, gameVis = {addr -> visibility},
--                   focus = entry index to select after the next redraw (nil = leave the game's choice) }
local menuStates = {}
local cheatActions = {} -- our button's address -> { state, fn, index } (fn nil = status line, not clickable)
local currentMenuState = nil

local function Addr(o)
    local ok, a = pcall(function() return o:GetAddress() end)
    return ok and a or nil
end

local function Cycle(list, cur)
    for i, v in ipairs(list) do
        if v == cur then return list[i % #list + 1] end
    end
    return list[1]
end

local function BoardLabel(row)
    local tier, rest = row:match("^Tier(%d+)_?(.*)$")
    if not tier then return row end
    return "Tier " .. tier .. (rest ~= "" and (" - " .. rest) or "")
end

-- For on-screen messages (see ShowToast): the pause menu we last clicked in, while the game
-- is paused (the menu pauses it; after closing, the old menu object can linger until GC).
openPauseMenu = function()
    local st = currentMenuState
    if not (st and valid(st.menu)) then return nil end
    local paused = false
    pcall(function() paused = UEHelpers.GetGameplayStatics():IsGamePaused(st.menu) end)
    return paused and st.menu or nil
end

local function OpenPage(page)
    if currentMenuState then currentMenuState.page = page end
end

local function BackTo(page) return { "Back", function() OpenPage(page) end } end
local function OnOff(b) return b and "On" or "Off" end

local PAGES = {}

PAGES.root = function()
    return {
        { "Weapons",             function() OpenPage("weapons") end },
        { "Ammo",                function() OpenPage("ammo") end },
        { "Chips",               function() OpenPage("chips") end },
        { "Upgrade boards",      function() OpenPage("boards") end },
        { "Skill points",        function() OpenPage("skills") end },
        { "DLC starting weapon", function() OpenPage("dlc") end },
        { "Secrets & police work", function() OpenPage("secrets") end },
        BackTo(nil),
    }
end

-- One chapter: heading with the count, then the items (read-only lines, fn = nil). With
-- withWaypoints, missing items that have a known spot can be clicked to set a waypoint.
local function ChecklistEntries(t, c, withWaypoints)
    table.insert(t, { string.format("%s: %d/%d", c.chapter.title, c.found, #c.items), nil })
    for _, it in ipairs(c.items) do
        if withWaypoints and it.found == false and it.waypoint then
            table.insert(t, { ChecklistMark(it.found) .. it.text .. "  - set waypoint",
                              function() PlaceWaypoint(it.flag, it.text) end })
        else
            table.insert(t, { ChecklistMark(it.found) .. it.text, nil })
        end
    end
end

PAGES.secrets = function()
    local t = {}
    local list = ReadChecklist()
    if not list then
        table.insert(t, { "Available once you're in a level", nil })
    else
        local cur = nil
        for _, c in ipairs(list.chapters) do
            if c.current then cur = c end
        end
        if cur then ChecklistEntries(t, cur, true)
        else table.insert(t, { "This chapter has no secrets or police work", nil }) end
        table.insert(t, { "Remove waypoint", function()
            Notify(RemoveWaypoints() > 0 and "Waypoint removed" or "No waypoint to remove")
        end })
    end
    table.insert(t, { "All chapters", function() OpenPage("secrets_all") end })
    table.insert(t, BackTo("root"))
    return t
end

PAGES.secrets_all = function()
    local t = {}
    local list = ReadChecklist()
    if not list then
        table.insert(t, { "Available once you're in a level", nil })
    else
        for _, c in ipairs(list.chapters) do ChecklistEntries(t, c) end
    end
    table.insert(t, BackTo("secrets"))
    return t
end

PAGES.weapons = function()
    local t = {}
    for _, w in ipairs(WEAPONS) do table.insert(t, { w[1], function() GiveWeapon(w) end }) end
    table.insert(t, BackTo("root"))
    return t
end

PAGES.ammo = function()
    local t = { { "Amount: " .. menuAmmoAmount, function() menuAmmoAmount = Cycle(AMMO_MENU_AMOUNTS, menuAmmoAmount) end } }
    for _, a in ipairs(AMMO) do table.insert(t, { a[1], function() GiveAmmo(a[2], menuAmmoAmount) end }) end
    table.insert(t, BackTo("root"))
    return t
end

PAGES.chips = function()
    local t = {}
    for _, arm in ipairs(ARM_NAMES) do
        local bit, name = arm[1], arm[2]
        table.insert(t, { name .. " arm: " .. OnOff((menuChipArms & bit) ~= 0),
                          function() menuChipArms = menuChipArms ~ bit end })
    end
    table.insert(t, { "Value: " .. BoostToPercent(PercentToBoost(menuChipPercent)) .. "%",
                      function() menuChipPercent = Cycle(CHIP_MENU_PERCENTS, menuChipPercent) end })
    table.insert(t, { "Look: " .. CHIP_LOOKS[menuChipLook],
                      function() menuChipLook = menuChipLook % #CHIP_LOOKS + 1 end })
    table.insert(t, { "Give chip", function()
        if menuChipArms == 0 then Notify("Turn on at least one arm first.") return end
        GiveChip(menuChipArms, menuChipPercent, menuChipLook)
    end })
    table.insert(t, BackTo("root"))
    return t
end

PAGES.boards = function()
    local t = {}
    local rows = GetBoardRows()
    if #rows == 0 then table.insert(t, { "Boards appear once you're in a level", nil }) end
    for _, r in ipairs(rows) do table.insert(t, { BoardLabel(r), function() GiveBoard(r) end }) end
    table.insert(t, BackTo("root"))
    return t
end

PAGES.skills = function()
    return {
        { "Amount: " .. menuSkillAmount, function() menuSkillAmount = Cycle(SKILL_MENU_AMOUNTS, menuSkillAmount) end },
        { "Add skill points",            function() GiveSkillPoints(menuSkillAmount) end },
        { "Remove unspent points",       function() ClearSkillPoints() end },
        BackTo("root"),
    }
end

PAGES.dlc = function()
    local function Mark(on, label) return (on and "> " or "") .. label end
    local t = { { Mark(dlcWeapon == nil, "Game default (OCP Combat Shotgun)"), function() SetDlcWeapon("default") end } }
    for _, w in ipairs(WEAPONS) do
        if w[2] ~= DLC_DEFAULT_ASSET then
            table.insert(t, { Mark(dlcWeapon == w[2], w[1]), function() SetDlcWeapon(w[2]) end })
        end
    end
    table.insert(t, BackTo("root"))
    return t
end

local function MenuList(menu)
    local list = nil
    pcall(function() list = menu.WB_ScrolledList end)
    return valid(list) and list or nil
end

local function MenuBox(menu)
    local box = nil
    pcall(function() box = menu.WB_ScrolledList.ScrollBox_6 end)
    return valid(box) and box or nil
end

local function ForEachChild(panel, fn)
    local n = 0
    pcall(function() n = panel:GetChildrenCount() end)
    local kids = {}
    for i = 0, n - 1 do
        local c = nil
        pcall(function() c = panel:GetChildAt(i) end)
        if valid(c) then table.insert(kids, c) end
    end
    for _, c in ipairs(kids) do fn(c) end
end

-- The list's Elements array as a Lua table (1-based). Read with ForEach only: indexing a
-- TArray past its end grows it.
local function ListElements(list)
    local t = {}
    pcall(function()
        list.Elements:ForEach(function(_, e)
            local o = e:get()
            if valid(o) then table.insert(t, o) end
        end)
    end)
    return t
end

local function SetListElements(list, objs)
    local ok, err = pcall(function()
        local arr = list.Elements
        arr:Empty()
        for i, o in ipairs(objs) do arr[i] = o end
    end)
    if not ok then Log("Pause menu: writing the list's Elements failed: " .. tostring(err)) end
end

-- Debug: Elements as "index:name:visible" (raw, including empty entries).
local function DescribeElements(list)
    local parts = {}
    pcall(function()
        list.Elements:ForEach(function(i, e)
            local o = e:get()
            local d = "None"
            if valid(o) then
                d = o:GetFName():ToString()
                pcall(function() d = d .. ":" .. tostring(o:IsVisible()) end)
            end
            table.insert(parts, tostring(i) .. "=" .. d)
        end)
    end)
    local id = "?"
    pcall(function() id = tostring(list.CurrentID) end)
    return "CurrentID=" .. id .. " [" .. table.concat(parts, ", ") .. "]"
end

local function IndexOf(t, obj)
    local a = Addr(obj)
    for i, o in ipairs(t) do
        if Addr(o) == a then return i end
    end
    return nil
end

local function IsShown(w)
    local ok, v = pcall(function() return w:IsVisible() end)
    return ok and v
end

-- The selected element (Elements[CurrentID]) and CurrentID, or nil.
local function SelectedElement(list)
    local id = -1
    pcall(function() id = list.CurrentID end)
    if type(id) ~= "number" or id < 0 then return nil, id end
    return ListElements(list)[id + 1], id
end

-- The WB_InGameMenu that owns a widget inside it (walks the outer chain).
local function OwningMenu(obj)
    local o = obj
    for _ = 1, 6 do
        if not valid(o) then return nil end
        local ok, isMenu = pcall(function() return o:GetClass():GetFName():ToString() == "WB_InGameMenu_C" end)
        if ok and isMenu then return o end
        local okO, outer = pcall(function() return o:GetOuter() end)
        o = okO and outer or nil
    end
    return nil
end

-- Select one of our buttons the way the list's own navigation does: deactivate the old
-- element, point CurrentID at the new one, activate it.
local function SelectElement(list, btn)
    local elems = ListElements(list)
    local idx = IndexOf(elems, btn)
    if not idx then return end
    local old = SelectedElement(list)
    if valid(old) and Addr(old) ~= Addr(btn) then pcall(function() old:SetActive(false) end) end
    pcall(function() list.CurrentID = idx - 1 end)
    pcall(function() btn:SetActive(true) end)
    local menu = OwningMenu(list)
    local st = menu and menuStates[Addr(menu)]
    if st then st.lastID = idx - 1 end
end

-- Our button addresses, also kept in a shared variable: hot reload (Ctrl+R) resets the Lua
-- state but leaves an open pause menu's widgets, and those leftover buttons must be removed.
local SHARED_BUTTONS = "RoboCopCheats_PauseMenuButtons"
local staleButtons = {}
pcall(function()
    local s = ModRef:GetSharedVariable(SHARED_BUTTONS)
    if type(s) == "string" then
        for a in s:gmatch("%d+") do staleButtons[tonumber(a)] = true end
    end
end)

local function SaveButtonList()
    local t = {}
    for a in pairs(cheatButtons) do table.insert(t, tostring(a)) end
    pcall(function() ModRef:SetSharedVariable(SHARED_BUTTONS, table.concat(t, ",")) end)
end

local function IsStaleButton(o)
    local a = Addr(o)
    return a ~= nil and staleButtons[a] == true
end

local function AddMenuButton(state, box, sample, text, fn)
    local wbl = StaticFindObject("/Script/UMG.Default__WidgetBlueprintLibrary")
    local cls = MenuClass("WB_InGameMenuButton02")
    if not (valid(wbl) and valid(cls)) then Log("Pause menu: WidgetBlueprintLibrary or button class not found") return nil end
    local okC, btn = pcall(function() return wbl:Create(state.menu, cls, UEHelpers.GetPlayerController()) end)
    if not okC or not valid(btn) then Log("Pause menu: creating a button failed: " .. tostring(btn)) return nil end
    local a = btn:GetAddress()
    cheatButtons[a] = btn
    table.insert(state.buttons, a)
    pcall(function() btn.Text = FText(text) end)
    local okA, slot = pcall(function() return box:AddChild(btn) end)
    if not okA then Log("Pause menu: AddChild failed: " .. tostring(slot)) return nil end
    table.insert(state.entries, btn)
    cheatActions[a] = { state = state, fn = fn, index = #state.entries }
    pcall(function()
        local src = sample.Slot
        for _, f in ipairs({ "Padding", "HorizontalAlignment", "VerticalAlignment" }) do
            pcall(function() slot["Set" .. f](slot, src[f]) end)
        end
    end)
    -- The list reveals its own buttons one by one (ShowDelay / ShowElem) when it's built;
    -- ours come later, so without this they stay invisible (seen 2026-11-13).
    pcall(function() btn:ShowElem() end)
    return btn
end

local function ClearOurButtons(state)
    for _, a in ipairs(state.buttons) do
        local b = cheatButtons[a]
        if valid(b) then pcall(function() b:RemoveFromParent() end) end
        cheatButtons[a] = nil
        cheatActions[a] = nil
    end
    state.buttons = {}
    state.entries = {}
end

-- Redraw a menu's list: the game's buttons + "RoboCop Cheats" (page nil), or one of our pages.
local function RenderMenu(state)
    if not valid(state.menu) then return end
    local box, list = MenuBox(state.menu), MenuList(state.menu)
    if not (box and list) then return end
    -- Keep the scroll position when redrawing the same page (e.g. after picking a DLC
    -- weapon near the bottom); a different page starts at the top.
    local offset = 0
    if state.renderedPage == state.page then pcall(function() offset = box:GetScrollOffset() end) end
    -- The game's own elements: Elements minus ours and leftovers from before a hot reload.
    local gameElems = {}
    for _, e in ipairs(ListElements(list)) do
        if not (IsCheatButton(e) or IsStaleButton(e)) then table.insert(gameElems, e) end
    end
    ClearOurButtons(state)
    ForEachChild(box, function(c)
        if IsStaleButton(c) then pcall(function() c:RemoveFromParent() end) end
    end)
    local sample = nil
    ForEachChild(box, function(c)
        if IsCheatButton(c) then return end
        sample = sample or c
        local a = Addr(c)
        if state.page then
            if state.gameVis[a] == nil then
                local v = nil
                pcall(function() v = c.Visibility end)
                state.gameVis[a] = v
            end
            pcall(function() c:SetVisibility(SLATE_COLLAPSED) end)
        elseif state.gameVis[a] ~= nil then
            local v = state.gameVis[a]
            pcall(function() c:SetVisibility(v) end)
            state.gameVis[a] = nil
        end
    end)
    if not sample then
        SetListElements(list, gameElems)
        SaveButtonList()
        return
    end
    local entries
    if state.page then
        entries = PAGES[state.page]()
    else
        entries = { { "RoboCop Cheats", function() OpenPage("root") end } }
    end
    for _, e in ipairs(entries) do AddMenuButton(state, box, sample, e[1], e[2]) end
    -- Append ours to Elements so the list's keyboard/controller navigation reaches them.
    -- ChildID = Elements index, the way the list's own AddInternal numbers its elements.
    local all = {}
    for _, e in ipairs(gameElems) do table.insert(all, e) end
    for i, b in ipairs(state.entries) do
        table.insert(all, b)
        local id = #gameElems + i - 1
        pcall(function() b.ChildID = id end)
    end
    SetListElements(list, all)
    SaveButtonList()
    if DEV_TOOLS then
        Log("Pause menu: Elements after redraw: " .. DescribeElements(list))
    end
    -- Selection: on our pages always one of our entries (the game's are hidden); on the game's
    -- page only when coming back from ours.
    local focus = state.focus
    if state.page and not focus then focus = 1 end
    if focus and #state.entries > 0 then
        SelectElement(list, state.entries[math.min(focus, #state.entries)])
    end
    state.focus = nil
    pcall(function() state.lastID = list.CurrentID end)
    state.renderedPage = state.page
    pcall(function() box:SetScrollOffset(offset) end)
    if offset > 0 then
        -- Again once the new buttons have been laid out, in case the first call was
        -- clamped against the old content height.
        ExecuteWithDelay(50, function()
            ExecuteInGameThread(function()
                if valid(box) then pcall(function() box:SetScrollOffset(offset) end) end
            end)
        end)
    end
end

-- Forget menus that are gone, so stale button addresses can't match new objects.
local function PruneMenus()
    local changed = false
    for ma, st in pairs(menuStates) do
        if not valid(st.menu) then
            for _, a in ipairs(st.buttons) do
                cheatButtons[a] = nil
                cheatActions[a] = nil
            end
            menuStates[ma] = nil
            changed = true
        end
    end
    if changed then SaveButtonList() end
end

local function EnsureCheatMenu(menu, why)
    if not valid(menu) then return end
    PruneMenus()
    local ma = Addr(menu)
    if not ma then return end
    local st = menuStates[ma]
    if not st then
        st = { menu = menu, page = nil, buttons = {}, entries = {}, gameVis = {} }
        menuStates[ma] = st
    end
    local box = MenuBox(menu)
    if not box then return end
    local has = false
    ForEachChild(box, function(c) if IsCheatButton(c) then has = true end end)
    if not has then
        RenderMenu(st)
        Log("Pause menu: added RoboCop Cheats to " .. menu:GetFName():ToString() .. " (" .. why .. ")")
    end
end

local function EnsureCheatMenuSoon(menu, why)
    -- Let the menu finish building its list first.
    ExecuteWithDelay(150, function()
        ExecuteInGameThread(function() EnsureCheatMenu(menu, why) end)
    end)
end

local function OnCheatButtonClicked(btn)
    local entry = cheatActions[Addr(btn)]
    if not entry or not entry.fn then return end
    -- Deferred: the action usually redraws the list, which removes the clicked button.
    ExecuteInGameThread(function()
        local st = entry.state
        currentMenuState = st
        local before = st.page
        local ok, err = pcall(entry.fn)
        if not ok then Notify("Error: " .. tostring(err)) end
        -- Keep the selection on the same entry (e.g. "Amount: 100"); a new page starts on
        -- its first entry, and leaving our pages selects "RoboCop Cheats".
        st.focus = (st.page == before) and entry.index or 1
        RenderMenu(st)
    end)
end

local function StateOf(obj)
    local menu = OwningMenu(obj)
    return menu and menuStates[Addr(menu)] or nil
end

-- +1 / -1 for a HandleNavigationInput Direction value, from the enum's names (e.g.
-- "EUINavigation::Down"); nil for anything else.
local navDirNames = nil
local function NavStep(value)
    if not navDirNames then
        navDirNames = {}
        pcall(function()
            local fn = StaticFindObject(MENU_GLOBALS .. "WB_ScrolledList.WB_ScrolledList_C:HandleNavigationInput")
            fn:ForEachProperty(function(p)
                if p:GetFName():ToString() == "Direction" then
                    p:GetEnum():ForEachName(function(n, v) navDirNames[v] = n:ToString() end)
                end
            end)
        end)
    end
    local name = (navDirNames[value] or ""):lower()
    if name:find("down") or name:find("next") or name:find("right") then return 1 end
    if name:find("up") or name:find("prev") or name:find("left") then return -1 end
    return nil
end

-- After the list's own up/down. Its blueprint refuses to step onto our buttons (also when
-- wrapping around to one), for a reason not visible from outside: logged 2026-11-13, ours
-- differed from the game's only in Visibility, and matching that didn't help. So when the list
-- didn't move (CurrentID unchanged since the last navigation; only navigation and our code
-- change it, mouse hover doesn't) or landed on a hidden element (the game's buttons while one
-- of our pages is open), we move on to the next visible element in that direction ourselves.
local function AfterNavigation(list, dirValue)
    local st = StateOf(list)
    if not st then return end
    local step = NavStep(dirValue)
    local cur, id = SelectedElement(list)
    if DEV_TOOLS then
        Log("Pause menu: nav " .. tostring(navDirNames[dirValue] or dirValue) .. " (last " .. tostring(st.lastID)
            .. ") -> " .. DescribeElements(list))
    end
    local stuck = (id == st.lastID) or not valid(cur) or not IsShown(cur)
    if not (stuck and step) then
        st.lastID = id
        return
    end
    local elems = ListElements(list)
    local n = #elems
    if n == 0 then return end
    local i = (type(id) == "number" and id >= 0) and id or (step > 0 and -1 or 0)
    for _ = 1, n do
        i = (i + step) % n
        if IsShown(elems[i + 1]) then
            if i ~= id then
                SelectElement(list, elems[i + 1])
                pcall(function() list.ScrollBox_6:ScrollWidgetIntoView(elems[i + 1], false, 0, 0.0) end)
            end
            st.lastID = i
            return
        end
    end
    st.lastID = id
end

-- Enter/A, step 1 (native pre-hook, before the game acts): if the selected element is ours or
-- a hidden game button, hide it from the game's handler by setting CurrentID to -1.
local function BeforeActionInput(menu)
    local st = menuStates[Addr(menu)]
    if not st then return end
    local list = MenuList(menu)
    if not list then return end
    local elem, id = SelectedElement(list)
    if not valid(elem) then return end
    if IsCheatButton(elem) or not IsShown(elem) then
        st.pendingAction = { id = id, elem = elem, list = list, fired = false }
        pcall(function() list.CurrentID = -1 end)
    end
end

-- Step 2 (list OnActiveItemAction, runs inside that call): the input was "activate the selection".
local function OnActiveItemAction(list)
    local st = StateOf(list)
    if st and st.pendingAction then st.pendingAction.fired = true end
end

-- Step 3 (native post-hook): restore CurrentID and run our action if it was an activation.
local function AfterActionInput(menu)
    local st = menuStates[Addr(menu)]
    local pa = st and st.pendingAction
    if not pa then return end
    st.pendingAction = nil
    if valid(pa.list) then pcall(function() pa.list.CurrentID = pa.id end) end
    if not pa.fired then return end
    if IsCheatButton(pa.elem) then
        OnCheatButtonClicked(pa.elem)
    else
        Log("Pause menu: blocked Enter on a hidden game menu button while a RoboCop Cheats page was open")
    end
end

-- The menu classes load with the first pause menu, so this is retried from the main loop.
local pauseMenuHooked = false
local function TryHookPauseMenu()
    if pauseMenuHooked then return end
    if not (valid(MenuClass("WB_InGameMenu"))
            and valid(StaticFindObject(MENU_GLOBALS .. "WB_ScrolledList.WB_ScrolledList_C"))
            and valid(StaticFindObject(MENU_GLOBALS .. "WB_ScrolledListElem.WB_ScrolledListElem_C"))) then
        return
    end
    pauseMenuHooked = true
    local LIST = MENU_GLOBALS .. "WB_ScrolledList.WB_ScrolledList_C:"
    local ELEM = MENU_GLOBALS .. "WB_ScrolledListElem.WB_ScrolledListElem_C:"
    local function Hook(path, pre, post)
        local ok, err = pcall(RegisterHook, path, pre, post)
        if not ok then Log("Pause menu: can't hook " .. path .. ": " .. tostring(err)) end
    end
    local function Get(p)
        local o = nil
        pcall(function() o = p:get() end)
        return o
    end
    local events = {
        { LIST .. "Finalize", "list Finalize" },
        { MENU_DIR .. "WB_InGameMenu.WB_InGameMenu_C:Construct", "Construct" },
        { MENU_DIR .. "WB_InGameMenu.WB_InGameMenu_C:OnFocusReceived", "OnFocusReceived" },
    }
    for _, h in ipairs(events) do
        Hook(h[1], function(self)
            local menu = OwningMenu(Get(self))
            if menu then EnsureCheatMenuSoon(menu, h[2]) end
        end)
    end
    -- Mouse: click and hover on our buttons (blueprint hooks run after the function).
    Hook(ELEM .. "OnMouseButtonUp", function(self)
        local o = Get(self)
        if IsCheatButton(o) then OnCheatButtonClicked(o) end
    end)
    Hook(ELEM .. "OnMouseEnter", function(self)
        local o = Get(self)
        if not IsCheatButton(o) then return end
        local entry = cheatActions[Addr(o)]
        local list = entry and MenuList(entry.state.menu)
        if list then SelectElement(list, o) end
    end)
    -- Keyboard/controller.
    Hook(LIST .. "HandleNavigationInput", function(self, direction)
        local dir = nil
        pcall(function() dir = direction:get() end)
        local list = Get(self)
        if valid(list) and dir ~= nil then AfterNavigation(list, dir) end
    end)
    Hook(LIST .. "OnActiveItemAction", function(self)
        local list = Get(self)
        if valid(list) then OnActiveItemAction(list) end
    end)
    Hook("/Script/Game.MenuWindowUserWidget:HandleActionInput",
        function(self)
            local menu = Get(self)
            if valid(menu) then BeforeActionInput(menu) end
        end,
        function(self)
            local menu = Get(self)
            if valid(menu) then AfterActionInput(menu) end
        end)
    -- Safety net: the menu's own click handler acts on child indices. It must never get one
    -- of our buttons, or run while our page hides the game's buttons.
    local bnd = MENU_DIR .. "WB_InGameMenu.WB_InGameMenu_C:"
        .. "BndEvt__WB_ScrolledList_K2Node_ComponentBoundEvent_1_OnElementAction__DelegateSignature"
    Hook(bnd, function(self, element)
        local e, menu = Get(element), Get(self)
        local st = menuStates[Addr(menu)]
        if not valid(e) then
            if DEV_TOOLS then Log("Pause menu: the menu's click handler got no element (expected while Enter is redirected)") end
        elseif IsCheatButton(e) then
            Log("WARNING: the pause menu's own click handler received one of our buttons")
        elseif st and st.page then
            Log("WARNING: a hidden game menu button was activated while a RoboCop Cheats page was open")
        end
    end)
    Log("Pause menu hooks installed.")
    for _, m in ipairs(LiveInstances("WB_InGameMenu_C")) do EnsureCheatMenu(m, "hooks installed") end
    -- Leftovers from before a hot reload can only be in menus that were open then.
    staleButtons = {}
end

if DEV_TOOLS then
    RegisterConsoleCommandHandler("rcmenudump", function()
        ExecuteInGameThread(MenuDump)
        return true
    end)

    RegisterConsoleCommandHandler("rcmenuwatch", function()
        ExecuteInGameThread(MenuWatch)
        return true
    end)

    RegisterConsoleCommandHandler("rcdump", function()
        ExecuteInGameThread(DumpApi)
        return true
    end)

    RegisterConsoleCommandHandler("rcchipmap", function()
        ExecuteInGameThread(ChipMap)
        return true
    end)

    RegisterConsoleCommandHandler("rcchipinfo", function()
        ExecuteInGameThread(ChipInfo)
        return true
    end)

    RegisterConsoleCommandHandler("rcchipdump", function()
        ExecuteInGameThread(ChipDump)
        return true
    end)

    RegisterConsoleCommandHandler("rcevaldump", function()
        ExecuteInGameThread(EvalDump)
        return true
    end)

    RegisterConsoleCommandHandler("givechipraw", function(_, Params, Ar)
        if #Params < 2 then Out(Ar, "Usage: givechipraw <Shape> <rotation> [boost] [tier]") return true end
        local shape, rot = Params[1], tonumber(Params[2]) or 0
        local boost = tonumber(Params[3]) or PercentToBoost(DEFAULT_CHIP_PERCENT)
        local tier = tonumber(Params[4]) or DEFAULT_CHIP_TIER
        ExecuteInGameThread(function()
            local enum = ChipEnumValues() or {}
            local value = enum[shape]
            if value == nil then Notify("Unknown shape " .. shape) return end
            local bp = GetBackpack()
            if not bp then Notify("No Backpack found.") return end
            -- raw: rotation goes to the game exactly as typed (no CHIP_ROT_UNIT scaling)
            tier = ClampTier(tier)
            local ok, err = pcall(function() bp:AddPredefinedChip(value, boost, rot, tier) end)
            Notify(ok and string.format("Gave raw chip %s rot %d boost %d tier %d", shape, rot, boost, tier)
                      or ("AddPredefinedChip failed: " .. tostring(err)))
        end)
        return true
    end)
end

----------------------------------------------------------------------------
-- GUI tab bridge. dlls/main.dll registers the RC_UI_* globals right after this
-- script starts, so we connect lazily from a game-thread loop.
----------------------------------------------------------------------------
local uiConnected = false
local uiBoardsPushed = false
local uiBoardRetry = 0
local dlcBackpackRetry = 0
local uiSecretsRetry = 0
local uiSecretsLast = nil

-- Checklist for the GUI's Secrets tab, as text: one line per chapter
-- "C<TAB>title<TAB>found<TAB>total<TAB>current 0|1", then one per item
-- "I<TAB>found 1|0|?<TAB>kind<TAB>text<TAB>flag<TAB>waypoint 1|0". Empty = not in a level.
local function ChecklistText()
    local list = ReadChecklist()
    if not list then return "" end
    local lines = {}
    for _, c in ipairs(list.chapters) do
        table.insert(lines, table.concat({ "C", c.chapter.title, c.found, #c.items, c.current and 1 or 0 }, "\t"))
        for _, it in ipairs(c.items) do
            local f = it.found == nil and "?" or (it.found and "1" or "0")
            table.insert(lines, table.concat({ "I", f, it.kind, it.text, it.flag, it.waypoint and 1 or 0 }, "\t"))
        end
    end
    return table.concat(lines, "\n")
end

LoadDlcSetting()
WatchNewBackpacks()

local function HandleUiRequest(req)
    local words = {}
    for w in req:gmatch("%S+") do table.insert(words, w) end
    local kind, asset, amount = words[1], words[2], words[3]
    if kind == "chip" then
        -- "chip <arms mask> <percent> <look 1-4>"
        GiveChip(tonumber(words[2]) or 0, tonumber(words[3]) or DEFAULT_CHIP_PERCENT,
                 tonumber(words[4]) or (DEFAULT_CHIP_TIER + 1))
    elseif kind == "board" then
        GiveBoard(asset)
    elseif kind == "dlcweapon" then
        SetDlcWeapon(asset)
    elseif kind == "skill" then
        -- "skill <amount>"
        GiveSkillPoints(tonumber(words[2]) or DEFAULT_SKILL_POINTS)
    elseif kind == "skillclear" then
        ClearSkillPoints()
    elseif kind == "waypoint" then
        -- "waypoint <flag>"
        local text = asset
        for _, ch in ipairs(EVAL_CHAPTERS) do
            for _, it in ipairs(ch.items) do
                if it[1] == asset then text = it[3] end
            end
        end
        PlaceWaypoint(asset, text)
    elseif kind == "waypointclear" then
        Notify(RemoveWaypoints() > 0 and "Waypoint removed" or "No waypoint to remove")
    elseif kind == "give" then
        for _, w in ipairs(WEAPONS) do
            if w[2] == asset then GiveWeapon(w) return end
        end
        Notify("Unknown weapon " .. tostring(asset))
    elseif kind == "ammo" then
        GiveAmmo(asset, tonumber(amount) or DEFAULT_AMMO_AMOUNT)
    else
        Log("Ignoring UI request: " .. req)
    end
end

LoopInGameThreadWithDelay(100, function()
    -- DLC weapon backup: keep the live Backpack's DLC weapon on the chosen class
    -- (ApplyDlcWeapon does nothing when it already is).
    dlcBackpackRetry = dlcBackpackRetry - 1
    if dlcBackpackRetry <= 0 then
        dlcBackpackRetry = 5
        local bp = GetBackpack(true)
        if bp then ApplyDlcWeapon(bp) end
        -- Pause menu entry: hook the menu classes once they're loaded.
        TryHookPauseMenu()
    end
    if not RC_UI_Pop then return end
    if not uiConnected then
        uiConnected = true
        RC_UI_Clear()
        for _, w in ipairs(WEAPONS) do RC_UI_AddWeapon(w[1], w[2]) end
        for _, a in ipairs(AMMO) do RC_UI_AddAmmo(a[1], a[2]) end
        if RC_UI_SetDlcWeapon then RC_UI_SetDlcWeapon(dlcWeapon or "default") end
        uiSecretsLast = nil
        Log("GUI tab connected.")
    end
    -- Secrets tab: refresh about once a second, send only when something changed.
    -- (RC_UI_SetSecrets is missing with an older main.dll.)
    if RC_UI_SetSecrets then
        uiSecretsRetry = uiSecretsRetry - 1
        if uiSecretsRetry <= 0 then
            uiSecretsRetry = 10
            local ok, text = pcall(ChecklistText)
            if ok and text ~= uiSecretsLast then
                uiSecretsLast = text
                RC_UI_SetSecrets(text)
            end
        end
    end
    -- Board rows need the DataTable loaded, so wait until a player exists; retry every ~5 s.
    if not uiBoardsPushed and RC_UI_AddBoard then
        uiBoardRetry = uiBoardRetry - 1
        if uiBoardRetry <= 0 then
            uiBoardRetry = 50
            local pawn = nil
            pcall(function() pawn = UEHelpers.GetPlayer() end)
            if valid(pawn) then
                local rows = GetBoardRows()
                for _, r in ipairs(rows) do RC_UI_AddBoard(r, r) end
                uiBoardsPushed = #rows > 0
                if uiBoardsPushed then Log("Pushed " .. #rows .. " upgrade boards to the GUI.") end
            end
        end
    end
    local req = RC_UI_Pop()
    if req then
        local ok, err = pcall(HandleUiRequest, req)
        if not ok then Notify("Error: " .. tostring(err)) end
    end
end)

Log("v" .. MOD_VERSION .. " loaded. F7/F8 select, F9 give. Console: givelist, give, giveammo, givechip, boardlist, giveboard, dlcweapon, giveskill, clearskill, secrets."
    .. (DEV_TOOLS and " Dev tools: F6/rcdump, Ctrl+F6/rcchipmap, rcchipinfo, rcchipdump, givechipraw, rcmenudump, rcmenuwatch, rcevaldump." or ""))
