RoboCop Cheats for RoboCop: Rogue City (UE4SS v4.0.0 mod)

INSTALL
  Copy everything inside  D:\Backup\Stuff\Robocop\Win64\  into
  C:\Program Files (x86)\Steam\steamapps\common\Robocop Rogue City\Game\Binaries\Win64\
  (You should end up with dwmapi.dll and a ue4ss\ folder next to RoboCop-Win64-Shipping.exe.)

UNINSTALL
  Delete dwmapi.dll and the ue4ss\ folder from that Win64 folder.

MENU
  The "UE4SS Debugging Tools" window opens with the game. Open its "RoboCop Cheats" tab.
  Weapons & Ammo page: click a weapon (comes with full ammo) or an ammo type (set Amount first).
    - DLC starting weapon: with the Deluxe edition, levels start you with the OCP Combat
      Shotgun. Pick another weapon here (e.g. M60, Cobra Assault Cannon) to get that instead.
      The choice is saved in ue4ss\Mods\RoboCopCheats\dlc_weapon.txt and applies from the
      next level start.
  Chips & Boards page:
    - Chip: click the arms of the "+" to choose which sides connect, set Value % (the number
      the game shows on the chip; game drops go up to 45%), pick a Look, click Give chip.
    - Boards: click an Auto-9 upgrade board to add it.
  Ctrl+O shows/hides that window. Easiest with the game in borderless/windowed mode.

USE WITHOUT THE MENU (once you are in a level)
  F7 / F8   previous / next weapon        F9   give the selected weapon
  F6        dump Backpack function signatures to ue4ss\UE4SS.log
  Console: givelist | give <index|name> | giveammo <B_AmmoX> [amount] | rcdump
           givechip <arms U/R/D/L> [percent] [look 1-4]   e.g.  givechip UR 45
           boardlist | giveboard <index|row>
           dlcweapon <index|name|default>   e.g.  dlcweapon M60   /   dlcweapon default
  The in-game console key is usually ~ (enabled by ConsoleEnablerMod).

A black UE4SS log window opens with the game (ConsoleEnabled=1 in UE4SS-settings.ini).
Set it back to 0 once everything works.

_downloads\ holds the original UE4SS zips. Nothing in there needs to be installed.
