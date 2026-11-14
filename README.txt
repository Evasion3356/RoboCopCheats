RoboCop Cheats v1.0 - for RoboCop: Rogue City (Steam)
=====================================================

A clickable in-game menu (plus hotkeys and console commands) to give yourself:
  - any of 17 working weapons, delivered fully loaded like a real pickup
  - ammo for every weapon type (including the Rifle/LMG ammo the old "Add" cheat can't give)
  - Auto-9 chips: choose connections, value % and look
  - Auto-9 upgrade boards
  - a different DLC starting weapon (Deluxe edition) instead of the OCP Combat Shotgun

Built on RE-UE4SS v4.0.0. Tested on the Steam version, build 22996396.


INSTALL (full download - includes UE4SS)
  1. Open the game folder: in Steam, right-click RoboCop: Rogue City > Manage >
     Browse local files.
  2. Extract the zip there. Its Game\ folder merges with the game's Game\ folder.
     Afterwards, Game\Binaries\Win64\ contains dwmapi.dll and a ue4ss\ folder next to
     RoboCop-Win64-Shipping.exe.
  3. Start the game.

INSTALL (mod-only download - you already have UE4SS)
  Requires UE4SS v4.0.0 exactly. The menu's DLL is built against that version and
  can crash with other versions.
  1. Extract into the game folder as above (adds ue4ss\Mods\RoboCopCheats\).
  2. In ue4ss\UE4SS-settings.ini set:
       GuiConsoleEnabled = 1
       GuiConsoleVisible = 1
       GraphicsAPI = dx11
  The mod enables itself through its enabled.txt, so mods.txt doesn't need editing.

UNINSTALL
  Full download: delete dwmapi.dll and the ue4ss\ folder from Game\Binaries\Win64\.
  Mod-only: delete ue4ss\Mods\RoboCopCheats\.


MENU
  The "UE4SS Debugging Tools" window opens with the game. Ctrl+O shows or hides it.
  Open the "RoboCop Cheats" tab. Borderless or windowed mode makes switching easiest.

  Weapons & Ammo
    - Click a weapon to receive it with full ammo. Like a real pickup, it replaces the
      weapon you carry in the same slot.
    - Set Amount, then click an ammo type.
    - DLC starting weapon (Deluxe edition): pick the weapon you want levels to start you
      with. It applies from the next fresh level start (Chapter Select or moving to a new
      level). Loading a save or restarting from a checkpoint restores your saved inventory
      instead. "Default" restores the OCP Combat Shotgun.

  Chips & Boards
    - Chip: click the arms of the "+" to choose which sides connect, set Value % (the
      number the game shows on the chip; normal drops go up to 45%), choose a Look, then
      click Give chip.
    - Upgrade boards: click a board to add it. The list appears once you are in a level.


HOTKEYS AND CONSOLE (once you are in a level)
  F7 / F8   previous / next weapon      F9   give the selected weapon

  Console commands (press ~ for the in-game console):
    givelist                          list weapons with their numbers
    give <number|name>                e.g.  give 10   /   give M60
    giveammo <B_AmmoX> [amount]       e.g.  giveammo B_AmmoRifle 200
    givechip <arms> [percent] [look]  arms = letters U R D L, e.g.  givechip UR 45
    boardlist / giveboard <number|name>
    dlcweapon <number|name|default>   e.g.  dlcweapon M60


GOOD TO KNOW
  - Back up your saves before using cheats:
      %LOCALAPPDATA%\RoboCop\Saved\SaveGames
  - Saving with cheated items stores them in that save.
  - Some weapons in the game files are unfinished (white, untextured, or unusable) and are
    deliberately left out of the list.
  - Whether achievements still unlock while using the mod is untested.
  - Steam only. Game Pass and Epic versions are untested.
  - After a game update the mod may need an update too.

TROUBLESHOOTING
  - No menu window: check that dwmapi.dll is next to RoboCop-Win64-Shipping.exe and that
    GuiConsoleEnabled = 1 is set in ue4ss\UE4SS-settings.ini.
  - Something doesn't work: set ConsoleEnabled = 1 in UE4SS-settings.ini to get a log
    window, or send ue4ss\UE4SS.log. The mod's lines start with [RoboCopCheats].
  - The game crashes at start after an update: remove dwmapi.dll and wait for a mod or
    UE4SS update.

CREDITS
  RE-UE4SS (MIT license, see ue4ss\LICENSE): https://github.com/UE4SS-RE/RE-UE4SS
