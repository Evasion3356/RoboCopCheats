# RoboCop Cheats (`RoboCopCheats`) — RoboCop: Rogue City mod

Renamed from WeaponSpawner on 2026-11-13 (it grew past weapons). Console commands `wsdump`/`wschip*` became `rcdump`/`rcchip*`; the Lua/C++ bridge globals `WS_UI_*` became `RC_UI_*`.

Goal: an in-game way (clickable menu + hotkeys/console) to spawn weapons **with working ammo**, Auto-9 chips and upgrade boards, replacing the old Cheat Engine + console-command workflow.

## Layout
- `Win64/` — exact mirror of what gets copied into the game's `Game\Binaries\Win64\` folder.
  - `dwmapi.dll` + `ue4ss/` = RE-UE4SS **v4.0.0** (stable, released 2026-11-12). Official binaries, not rebuilt.
  - `ue4ss/Mods/RoboCopCheats/Scripts/main.lua` — **our Lua mod**: all game interaction (give weapon/ammo), hotkeys, console commands.
  - `ue4ss/Mods/RoboCopCheats/dlls/main.dll` — **our C++ mod** (build output of `cpp/`): only draws the "RoboCop Cheats" GUI tab.
  - `ue4ss/Mods/mods.txt` — `RoboCopCheats : 1` added above the `Keybinds` line (Keybinds must stay last).
  - `ue4ss/UE4SS-settings.ini` — changes: `ConsoleEnabled = 1` (external log window), `EnableHotReloadSystem = 1` (Ctrl+R reloads all mods, same as the GUI's "Restart All Mods"), `GuiConsoleEnabled = 1` + `GuiConsoleVisible = 1` (GUI window with our tab; Ctrl+O toggles). Console can go back to 0 when done debugging; the GUI ones must stay 1 for the menu.
- `cpp/` — C++ mod source. `cpp/CMakeLists.txt` pulls in `_deps/RE-UE4SS`; `cpp/RoboCopCheats/dllmain.cpp` is the tab. Post-build copies the DLL to `Win64/ue4ss/Mods/RoboCopCheats/dlls/main.dll`.
- `_deps/RE-UE4SS/` (gitignored) — UE4SS source at tag **v4.0.0** with submodules (UEPseudo is private; user's GitHub has access). Submodules use SSH URLs; fetch with `git -c url."https://github.com/".insteadOf="git@github.com:" submodule update --init --recursive --depth 1`.
- `_downloads/` — original UE4SS zip + zCustomGameConfigs (no RoboCop entry exists; defaults work). Reference only.
- `README.txt` — **public** readme (ships in the zips as `RoboCopCheats-README.txt`). No personal paths in it.
- `NEXUS_DESCRIPTION.txt` — Nexus mod page text (BBCode).
- `make_release.ps1` — builds `dist/RoboCopCheats-<ver>-full.zip` (UE4SS + mod) and `-modonly.zip` into `dist/` (gitignored). Zips are rooted at the game folder (`Game/Binaries/Win64/...`). Release-only changes: `ConsoleEnabled = 0`, no `dlc_weapon.txt`. Refuses to build if `DEV_TOOLS` is on or README doesn't mention the version. Version = `MOD_VERSION` in main.lua (DLL `ModVersion` is "1.0" too).
- **Releasing:** GitHub repo `Evasion3356/RoboCopCheats` (public), Nexus page https://www.nexusmods.com/robocoproguecity/mods/98. Bump `MOD_VERSION` in main.lua + `v<ver>` in README.txt, add a `## [X.Y]` section to `docs/CHANGELOG.md`, commit, then tag with a plain number (`1.1`, not `v1.1`) and push the tag. `.github/workflows/release.yml` checks tag == MOD_VERSION, runs `make_release.ps1`, creates the GitHub release with both zips, and uploads them to Nexus as new versions of Full (main, v3 file id 8380659; sets mod version + changelog) and Mod Only (optional, 8380662). Mod v3 id 24897925415010 (= GraphQL `uid`). Skips Nexus on a tag push if Nexus already shows that version; manual "Run workflow" uploads only with "nexus" ticked. Needs the `NEXUS_API_KEY` repo secret (from `~/.nexus_api_key`). **CI doesn't compile the DLL** (UEPseudo is private): rebuild and commit `main.dll` before tagging if `cpp/` changed.
- `Win64/ue4ss/Mods/RoboCopCheats/enabled.txt` — lets the mod-only release load without editing mods.txt (UE4SS skips already-started mods, so no double load with the mods.txt entry; checked in v4.0.0 source `start_mods`).

## Building the C++ mod
- Toolchain: VS 2026 Community (MSVC 14.51), its bundled CMake + Ninja, Rust stable (needed by patternsleuth).
- From a VS x64 dev environment (`vcvars64.bat`) in `cpp/`:
  `cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Game__Shipping__Win64` then `cmake --build build --target RoboCopCheats`.
- ABI check: every UE4SS.dll import of `main.dll` must exist in the **official** `Win64/ue4ss/UE4SS.dll` exports (`dumpbin /imports` vs `/exports`). Verified 2026-11-13: 26/26 present.
- The game locks `main.dll` while running, so C++ changes need a game restart. Lua changes: Ctrl+R / Restart All Mods.
- **ImGui rule:** the DLL has its own ImGui copy. Every tab callback must call `bind_ue4ss_imgui()` first. UE4SS only fires `on_ui_init` at initial startup, never after a reload, so `UE4SS_ENABLE_IMGUI()` alone leaves a reloaded DLL with a null context.
- Crash triage: UE4SS writes `ue4ss/crash_*.dmp`. With no WinDbg installed, parse it with the `minidump` pip package, then symbolize `main.dll+offset` via dbghelp `SymFromAddr`/`SymGetLineFromAddr` against `cpp/build/RoboCopCheats/RoboCopCheats.pdb`.

## Game facts
- Steam app 1681430; release tested on build **22996396**.
- Install: `C:\Program Files (x86)\Steam\steamapps\common\Robocop Rogue City`
- Executable: `Game\Binaries\Win64\RoboCop-Win64-Shipping.exe`, Unreal Engine **5.2**, IoStore paks (`.pak` + `.utoc`).
- `Manifest_UFSFiles_Win64.txt` in the install root lists **every asset path** — grep it instead of guessing paths.
- Weapons: `/Game/Blueprints/WeaponsNew/WP_<Name>` → class path `/Game/Blueprints/WeaponsNew/WP_X.WP_X_C`.
  Also `/Game/Blueprints/Weapons/DLC1/WP_MeleeWeapon*` (bat, hammer).
- Ammo items: `/Game/Blueprints/Items/Ammo/B_Ammo<Type>` (27 exist). Items have **no display-name data** (checked 2026-11-13: only socket/net names on the class defaults). Each weapon's ammo is its `AmmoItem` (ClassProperty) default; main.lua `AMMO` lists only the 10 used by listed weapons, named after their weapons (no Auto-9: it has infinite ammo).
- Cheat manager BP: `/Game/Blueprints/Abstract/Player/BP_MyCheatManager`.
- Native module is `/Script/Game`. Backpack = `/Script/Game.Backpack`, lives on `BP_MyGameState_C_0.Backpack_0`. Confirmed signatures (F6 dump, 2026-11-13):
  `AddWeaponToBackpack(Object Weapon, bool bAddDefaultAmmo, out int AmmoAdded)`,
  `AddItemsOfClassToBackpack(Class, int Amount, bool bShowHUDInfo) -> int`,
  `AddItemsToBackpack(Object Item, int Amount, bool bShowHUDInfo) -> int`,
  `TryToAddDlcWeaponToBackpack(enum DLCType)`, `AddPredefinedChip(enum NewConnectionType, int BoostValue, int NewRotationOffset, int NewChipTier)`.
  **`SpawnWeaponAndAddToBackpack` does NOT exist on Backpack.** Also has `GetFixedAmmoTypeAmount`, `GetItemsOfClassAmount`, `ClearAdditionalWeapons`.

## History / why this exists (from the user's 2023 FearLess forum posts)
- `CheatManager.AddWeapon WP_X` gives the gun with **no ammo**.
- Adding ammo via `Add <amount> B_AmmoX` worked for Cobra/Small44 but **not** Rifle/LMG/Minigun.
- Cheat Engine "infinite ammo" scripts broke weapon swapping and pickups (AR/LMG), even corrupting saves.
- This mod's approach (Backpack's own add path with default ammo) is **confirmed to fix it**.

## How it works
- Lua: give = load class (`StaticFindObject`, else `LoadAsset("/Game/.../WP_X.WP_X_C")`) → `SpawnActor` at player → `Backpack:AddWeaponToBackpack(actor, true, …)`. Ammo = `AddItemsOfClassToBackpack`. Game-thread work via `ExecuteInGameThread` / `LoopInGameThreadWithDelay`.
- Hotkeys: F7/F8 cycle selection, F9 give, F6 dump Backpack API + chip info. Console: `givelist`, `give <index|name>`, `giveammo <B_AmmoX> [amount]` (`give B_AmmoX` also works), `rcdump`, `givechip <URDL> [percent] [look]`, `givechipraw <Shape> <rot> [boost] [tier]`, `boardlist`, `giveboard <index|row>`, `dlcweapon <index|name|default>`, `rcchipdump`.
- GUI bridge: C++ `on_lua_start` (same-named Lua mod) registers globals `RC_UI_Clear/AddWeapon/AddAmmo/AddBoard/Pop/Status/SetDlcWeapon` into the Lua state. Lua polls `RC_UI_Pop()` every 100 ms on the game thread; requests are `"give <asset>"` / `"ammo <asset> <n>"` / `"chip <armsmask> <percent> <look 1-4>"` / `"board <row>"` / `"dlcweapon <asset|default>"`. The tab has two pages: "Weapons & Ammo" and "Chips & Boards". Shared state behind a mutex (GUI thread vs game thread). Weapon/ammo lists live only in main.lua and are pushed to the tab.

## Status
- [x] UE4SS staged and running in game; Lua mod works.
- [x] **Ammo works** (2026-11-13): AUG, M60, AKM arrive fully loaded. Giving a gun swaps out the one in the same slot (AUG dropped the pistol), like a real pickup.
- [x] C++ GUI tab written, built, ABI-checked, deployed (2026-11-13).
- [x] GUI tab works in game (2026-11-13).
- [x] **Unfinished weapons removed** (2026-11-13): `WP_FnMinimi` and `WP_Hecklerkoch` spawn as a white, game-breaking gun. Manifest confirms: meshes only, zero materials/textures (real guns have their own `M_/MI_/T_` assets). Removed from WEAPONS. Use the same manifest check (mesh vs material/texture counts) before adding weapons.
- [x] Removed (2026-11-13): `WP_ShotgunRemington` and `WP_SniperRifle`, confirmed broken in game. The manifest heuristic predicted both (Remington's mesh is under `TerminatorWeapons/` with no materials; Sniper Rifle has no mesh of its own).
- [x] Removed (2026-11-13), confirmed not working in game: `WP_GrenadeLauncher`, `WP_GrenadeLauncherM79`, `WP_RocketLauncher`, `WP_MountedMinigun`. (MM-1 and ATGM turned out to use `B_AmmoGrenade` / `B_AmmoRocket`.)
- [x] GetBackpack hardened (2026-11-13): now only the Backpack whose outer is `World.GameState`, refuses if ambiguous, logs which one it uses (guards against a stale Backpack after death/reload).
- [x] **GPU errors / unkillable process** (2026-11-13): the first GUI run with `GraphicsAPI = opengl` logged 3× `nvlddmkm` event 153 at startup (the only such events in 30 days); afterwards the process hung in the driver while exiting and needed a reboot. Switched to `GraphicsAPI = dx11`; the next run (17:33) had no driver errors. Saves backed up to `_savebackup/` (gitignored) beforehand.
- [x] **Reload crash, root-caused and fixed** (2026-11-13): both Ctrl+R (17:36) and "Restart All Mods" (17:40) crashed. Both UE4SS dumps: access violation reading 0x1440 at `main.dll+0x2F77D` = `ImGui::TextWrapped` (first call in our tab), i.e. a null ImGui context. Cause: after a reload, UE4SS never calls `on_ui_init`, so the reloaded DLL's own ImGui copy never got UE4SS's context. Fix: `bind_ue4ss_imgui()` at the top of the tab callback. Hot reload re-enabled (it had been turned off as a workaround). Verified in game 2026-11-13: multiple reloads, no new dumps, no driver errors. Possibly worth reporting upstream: reinstall skips `fire_ui_init_for_cpp_mods()`.
- [x] Also removed (2026-11-13): `WP_BerettaAuto9` (RoboCop's built-in gun, pointless) and `WP_Pistol` (spawns broken).
- [x] **Every weapon in WEAPONS verified in game** (2026-11-13): all 17 spawn and arrive loaded with ammo (SIG Sauer, Desert Eagle, Uzi, TEC-9, Sterling Mk6, AKM, Steyr AUG, HK G11, HK21, M60, Mossberg, OCP Combat Shotgun, SPAS-12, Barrett M82, Cobra Assault Cannon, MM-1, ATGM). dx11 GUI: no NVIDIA errors since the switch.
- [ ] User's current save already can't pick up the M60 (believed to be old 2023 Cheat Engine damage) — test on a fresh save.
- [x] Ammo list trimmed to the 10 types kept weapons use (2026-11-13), mapping read from each weapon's `AmmoItem`. Removed weapons mostly had no valid `AmmoItem` at all. Ammo buttons show weapon-based names (`RC_UI_AddAmmo(display, asset)`; DLL rebuilt, Lua + DLL must be deployed together).
- [x] Ammo giving via `AddItemsOfClassToBackpack` verified in game (2026-11-13 17:47): every type incl. Rifle, LMG and Auto-9 reported added; user confirmed it works. This fixes the 2023 `Add B_AmmoRifle/LMG` failure.
- [ ] `AmmoAdded` out-param detection (`HasAnyPropertyFlags`) doesn't trigger; harmless, value just isn't logged.
- [x] Removed `WP_BaseballBat` (2026-11-13): spawns but can't be used.
- [x] **Chips** (2026-11-13): menu = arms "+", Value %, Look; mapping and formula confirmed from the game's own chip widgets (`rcchipmap`). **Tested and working in game** (user confirmed).
- [ ] **Boards: still untested in game.** The only feature in the v1.0 release that hasn't been verified.
  - Chips are `B_OCP_Chip`/`B_ChipItem` items (ChipItem: `ConnectionType`, `Boost`, `RotationOffset`, `ChipTier`) in `Backpack.ChipsSlots`. Chips have **no stat**: the board node they sit on decides it.
  - `EChipConnectionType` Omni=0, TShape=1, LShape=2, PassThrough=3, DeadEnd=4. Sides 0=Left 1=Up 2=Right 3=Down; each `RotationOffset` step = quarter turn clockwise. At rotation 0: DeadEnd=L, LShape=L+D, PassThrough=L+R, TShape=L+R+D. Verified against all 15 combinations seen in game.
  - Shown % = `Boost * 1.5` rounded half up (25->38%, 30->45%). Game drops top out at 45% (boost 30); the user's 300% chips came from Cheat Engine.
  - **`ChipTier` must be 0..3**: the widget has 4 tier textures (`T_Chip01..04`). Tier 10 crashed the game when the inventory opened (UE crash 18:06, AV reading 0x38). Lua clamps it. Tier 0 = normal look, tier 1 = hollow ring; tier doesn't change the %. Shown to the user as "Look" 1-4.
  - Boards: `/Script/Game.GlobalFunctionLibrary:AddWeaponUpgradeBoardToPlayer(Object WorldContextObject, DataTableRowHandle BoardHandle)`, static. Rows of `DT_WeaponUpgradeBoards`: Tier2_Tutorial, Tier3_1..3, Tier4_1..3, Tier5_1..3, Tier6, Tier6_1..3.
  - Research commands kept but behind `DEV_TOOLS = false` in main.lua (off in releases): F6/`rcdump`, `rcchipdump`, `rcchipinfo` (large), `rcchipmap` (Ctrl+F6, upgrade screen open), `givechipraw`. Set `DEV_TOOLS = true` to use them.
- [x] **DLC starting weapon** (2026-11-13), verified in game. On levels with `bShouldAddDLCWeapon` (LevelData struct) the game gives the class in `Backpack.DeluxeEditionPlayerWeapon` (ClassProperty, default `WP_MossbergBullpup_C`) at a fresh level start. Save loads and checkpoint restarts restore the saved inventory instead, so test with Chapter Select or a level transition. The mod sets that property on the live Backpack right after it's created (`NotifyOnNewObject("/Script/Game.Backpack")`, deferred with `ExecuteInGameThread`), with a 0.5 s poll as backup. Verified 18:59: the Backpack was switched to the Cobra in the same instant it was created, and the Cobra was received. Saved as `Mods/RoboCopCheats/dlc_weapon.txt` (asset name or `default`). GUI: combo on Weapons & Ammo (`RC_UI_SetDlcWeapon`, request `"dlcweapon <asset|default>"`); console `dlcweapon`.
  - **Dead ends, don't retry:** RegisterHook on `Backpack:TryToAddDlcWeaponToBackpack` never fires (the game calls it natively). `FindAllOf("Backpack")` returns no `Default__` templates. **Writing the property on `/Script/Game.Default__Backpack` corrupted it** (read back as an `InteractiveComponent`) and didn't affect new Backpacks; the BP_MyGameState subobject template paths don't exist.
- [x] **Skill points, add** (2026-11-13): "Skills" page (request `"skill <n>"`), console `giveskill [n]`. **Works in game** (log 20:30-21:03, user spent them on perks). Confirmed signatures: `BP_MyCheatManager_C:AddSkillPoints(int Points)`; `/Script/Game.PlayerProgressionManager` (lives on `BP_MyGameState_C_0.PlayerProgressionManager`) has `FreeSkillPoints` (unspent) and `SetSkillPoints(int SkillPoints)`, plus `AddSkillPoint`, `ConsumeSkillPoint`, `ExpLevel`. Lua uses the cheat, verifies via `FreeSkillPoints`, falls back to `SetSkillPoints(free + n)`. Static `GlobalFunctionLibrary:AddExpPoints` also exists (XP, unused).
- [ ] **Skill points, remove** (2026-11-13): "Remove unspent points" button (request `"skillclear"`), console `clearskill` = `SetSkillPoints(0)`, verified by reading back `FreeSkillPoints`. Reason: once every skill is maxed, level-ups grant points that can't be spent and the game nags. Untested: whether the reminder clears right away, and whether it survives save/reload.
- [ ] Later ideas: melee via `Backpack:SetMeleeWeapon` with the DLC1 `WP_MeleeWeapon_BaseballBat_Child` / `WP_MeleeWeapon_Hammer` (signature unknown; dump it first).

## Working rules
- Edit files here (`Win64/`, `cpp/`), then copy to the game folder to test (game folder is under Program Files).
- Don't trust asset/function names from memory — grep the manifest or the F6 dump.
