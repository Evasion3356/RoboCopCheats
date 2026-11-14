--[[
    RoboCop Cheats: weapons, ammo, Auto-9 chips and upgrade boards for RoboCop: Rogue City
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

    Developer tools (only when DEV_TOOLS = true below):
      F6 / rcdump                  dump the Backpack API + chip/board info to UE4SS.log
      rcchipdump                   chip enum, board functions and board rows to the log
      rcchipmap   (Ctrl+F6)        research: each chip's shape/rotation vs. what its widget shows
      rcchipinfo                   research: full chip/backpack/widget property dump (large)
      givechipraw <Shape> <rot> <boost> <tier>   raw AddPredefinedChip (tier 0-3)

    Everything is logged with the [RoboCopCheats] prefix in ue4ss\UE4SS.log.
]]

local UEHelpers = require("UEHelpers")

local MOD_VERSION = "1.0"
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

local function Notify(msg)
    Log(msg)
    -- Status line in the "RoboCop Cheats" GUI tab (provided by dlls/main.dll, if present).
    if RC_UI_Status then pcall(RC_UI_Status, msg) end
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
        Notify(string.format("Gave %d%% chip, arms %s (%s rotation %d, boost %d, look %d)",
            BoostToPercent(boost), ArmsString(mask), shape, rot, boost, tier + 1))
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
                DumpVal(ok and sv or "<unreadable>", sp, n, indent + 1, depth + 1)
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
            DumpVal(ok and v or "<unreadable>", prop, cname .. "." .. n, 1, 0)
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
                    DumpVal(ok and v or "<unreadable>", prop, n, 1, 0)
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

if DEV_TOOLS then
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
    end
    if not RC_UI_Pop then return end
    if not uiConnected then
        uiConnected = true
        RC_UI_Clear()
        for _, w in ipairs(WEAPONS) do RC_UI_AddWeapon(w[1], w[2]) end
        for _, a in ipairs(AMMO) do RC_UI_AddAmmo(a[1], a[2]) end
        if RC_UI_SetDlcWeapon then RC_UI_SetDlcWeapon(dlcWeapon or "default") end
        Log("GUI tab connected.")
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

Log("v" .. MOD_VERSION .. " loaded. F7/F8 select, F9 give. Console: givelist, give, giveammo, givechip, boardlist, giveboard, dlcweapon."
    .. (DEV_TOOLS and " Dev tools: F6/rcdump, Ctrl+F6/rcchipmap, rcchipinfo, rcchipdump, givechipraw." or ""))
