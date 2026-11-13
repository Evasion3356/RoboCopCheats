# WeaponSpawner — RoboCop: Rogue City mod

Goal: an in-game way (hotkeys/console now, maybe a clickable menu later) to spawn any weapon **with working ammo**, replacing the old Cheat Engine + console-command workflow.

## Layout
- `Win64/` — exact mirror of what gets copied into the game's `Game\Binaries\Win64\` folder.
  - `dwmapi.dll` + `ue4ss/` = RE-UE4SS **v4.0.0** (stable, released 2026-11-12).
  - `ue4ss/Mods/WeaponSpawner/Scripts/main.lua` — **our mod** (the only file we author).
  - `ue4ss/Mods/mods.txt` — `WeaponSpawner : 1` added above the `Keybinds` line (Keybinds must stay last).
  - `ue4ss/UE4SS-settings.ini` — only change: `ConsoleEnabled = 1` (external log window). Set back to 0 when done debugging.
- `_downloads/` — original UE4SS zip + zCustomGameConfigs (no RoboCop entry exists; defaults expected to work). Reference only.
- `README.txt` — user-facing install/usage.

## Game facts
- Install: `C:\Program Files (x86)\Steam\steamapps\common\Robocop Rogue City`
- Executable: `Game\Binaries\Win64\RoboCop-Win64-Shipping.exe`, Unreal Engine **5.2**, IoStore paks (`.pak` + `.utoc`).
- `Manifest_UFSFiles_Win64.txt` in the install root lists **every asset path** — grep it instead of guessing paths.
- Weapons: `/Game/Blueprints/WeaponsNew/WP_<Name>` → class path `/Game/Blueprints/WeaponsNew/WP_X.WP_X_C`.
  Also `/Game/Blueprints/Weapons/DLC1/WP_MeleeWeapon*` (bat, hammer).
- Ammo items: `/Game/Blueprints/Items/Ammo/B_Ammo<Type>` (27 of them; newer ones like `B_AmmoMedium556/762`, `B_Ammo762` exist that weren't around in 2023).
- Cheat manager BP: `/Game/Blueprints/Abstract/Player/BP_MyCheatManager`.
- Native names found as strings in the exe (signatures NOT yet confirmed):
  `UBackpack`, `AddWeaponToBackpack` (has a `bAddDefaultAmmo` param), `SpawnWeaponAndAddToBackpack`,
  `TryToAddDlcWeaponToBackpack`, `AddItemsOfClassToBackpack`, `AddItemsToBackpack`,
  `HowManyItemsOfClassCanFitToBackpack`, `GetBackpack`, `AddPredefinedChip`, `ABackpackItem`, `AWeapon`.
- The native script module name (`/Script/???`) was not found in the exe — the mod locates the Backpack via `FindAllOf("Backpack")` instead.

## History / why this exists (from the user's 2023 FearLess forum posts)
- `CheatManager.AddWeapon WP_X` gives the gun with **no ammo**.
- Adding ammo via `Add <amount> B_AmmoX` worked for Cobra/Small44 but **not** Rifle/LMG/Minigun.
- Cheat Engine "infinite ammo" scripts broke weapon swapping and pickups (AR/LMG), even corrupting saves.
- Hypothesis driving this mod: calling the Backpack's own add path with default ammo behaves like a real pickup and avoids all of that.

## How main.lua works
- Hotkeys: F7/F8 cycle selection, F9 give, F6 dump Backpack API to `ue4ss/UE4SS.log`.
- Console: `givelist`, `give <index|name>`, `giveammo <B_AmmoX> [amount]`, `wsdump`.
- Reflection: reads UFunction params at runtime (`ForEachFunction` / `ForEachProperty`) and builds args by property type (class → weapon class, bool named *ammo*/*equip* → true, numbers → amount, object → spawned actor).
- Give order: `SpawnWeaponAndAddToBackpack` → `AddWeaponToBackpack` (spawns actor if it wants an instance) → `CheatManager:AddWeapon` fallback.
- Game-thread work goes through `ExecuteInGameThread`.

## Status
- [x] UE4SS staged, mod written.
- [ ] **Not yet run in game.** Lua not syntax-checked (no lua/luac on this machine).
- [ ] Get F6 dump from `UE4SS.log` → confirm real signatures, fix arg building.
- [ ] Verify ammo works for AKM / M60 / SPAS-12 (the historically broken ones).
- [ ] Decide on UI: keep hotkeys, or C++ UE4SS mod with an ImGui tab for a clickable menu. On-screen `ClientMessage` may be invisible in shipping.
- [ ] Later ideas: precise chip spawner via `AddPredefinedChip`.

## Working rules
- Edit files here in `Win64/`, then copy to the game folder to test (game folder is under Program Files).
- Don't trust asset/function names from memory — grep the manifest or the F6 dump.
