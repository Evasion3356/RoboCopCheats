WeaponSpawner for RoboCop: Rogue City (UE4SS v4.0.0 + Lua mod)

INSTALL
  Copy everything inside  D:\Backup\Stuff\Robocop\Win64\  into
  C:\Program Files (x86)\Steam\steamapps\common\Robocop Rogue City\Game\Binaries\Win64\
  (You should end up with dwmapi.dll and a ue4ss\ folder next to RoboCop-Win64-Shipping.exe.)

UNINSTALL
  Delete dwmapi.dll and the ue4ss\ folder from that Win64 folder.

MENU
  The "UE4SS Debugging Tools" window opens with the game. Open its "Weapon Spawner" tab
  and click a weapon (comes with full ammo) or an ammo type (set Amount first).
  Ctrl+O shows/hides that window. Easiest with the game in borderless/windowed mode.

USE WITHOUT THE MENU (once you are in a level)
  F7 / F8   previous / next weapon        F9   give the selected weapon
  F6        dump Backpack function signatures to ue4ss\UE4SS.log
  Console: givelist | give <index|name> | giveammo <B_AmmoX> [amount] | wsdump
  The in-game console key is usually ~ (enabled by ConsoleEnablerMod).

A black UE4SS log window opens with the game (ConsoleEnabled=1 in UE4SS-settings.ini).
Set it back to 0 once everything works.

_downloads\ holds the original UE4SS zips. Nothing in there needs to be installed.
