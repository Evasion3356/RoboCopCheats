RoboCop Cheats v1.2 - for RoboCop: Rogue City (Steam)
=====================================================

A clickable in-game menu (plus hotkeys and console commands) to give yourself:
  - any of 17 working weapons, delivered fully loaded like a real pickup
  - ammo for every weapon type (including the Rifle/LMG ammo the old "Add" cheat can't give)
  - Auto-9 chips: choose connections, value % and look
  - Auto-9 upgrade boards
  - a different DLC starting weapon (Deluxe edition) instead of the OCP Combat Shotgun
  - skill points
and shows a checklist of each chapter's secrets and police work (what the end-of-level
grade counts), so you can see what you've missed before the level ends.

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
       GuiConsoleVisible = 0
       GraphicsAPI = dx11
  (GuiConsoleEnabled = 1 is only needed for the optional menu window, see MENU.)
  The mod enables itself through its enabled.txt, so mods.txt doesn't need editing.

UNINSTALL
  Full download: delete dwmapi.dll and the ue4ss\ folder from Game\Binaries\Win64\.
  Mod-only: delete ue4ss\Mods\RoboCopCheats\.


MENU
  In game: press Esc and pick "RoboCop Cheats" at the bottom of the pause menu (mouse, or
  arrow keys + Enter). It has pages for Weapons, Ammo, Chips, Upgrade boards, Skill
  points, the DLC starting weapon and Secrets & police work. Settings such as the ammo amount or a chip's value
  change each time you pick them. The result of each action shows at the top of the
  screen for a few seconds; on the DLC starting weapon page, "> " marks the current
  choice. The "Back" entry returns to the previous page.

  Menu window (optional): Ctrl+O opens or closes the "UE4SS Debugging Tools" window with
  a "RoboCop Cheats" tab offering the same features. Close it again when you're done:
  while it is open, the Steam and NVIDIA overlays don't work.
  The pages below describe the window; the pause menu works the same way.

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

  Skills
    - Set the amount and click Add skill points, then spend them on the Skills screen.
    - Remove unspent points: sets unspent points to 0. Useful once every skill is maxed,
      when leveling up keeps giving points you can't spend (and the game keeps reminding you).

  Secrets
    - The secrets and police work the end-of-level grade counts (e.g. "OCP Bank secret
      #1 found", "Bank Intruder arrested"), marked Found or Missing for your current save.
      Your current chapter is shown first; it updates as you play.
    - Missing items that are at one spot (most secrets) can be clicked ("set waypoint")
      to put the game's waypoint marker on them. It disappears when you reach it, or use
      "Remove waypoint". It only works in that chapter, once the game has loaded that area.
      Items about a whole area (e.g. "All hostages saved") have no waypoint.
    - Chapters without any (e.g. Metro West) show none.


HOTKEYS AND CONSOLE (once you are in a level)
  F7 / F8   previous / next weapon      F9   give the selected weapon

  Console commands (press ~ for the in-game console):
    givelist                          list weapons with their numbers
    give <number|name>                e.g.  give 10   /   give M60
    giveammo <B_AmmoX> [amount]       e.g.  giveammo B_AmmoRifle 200
    givechip <arms> [percent] [look]  arms = letters U R D L, e.g.  givechip UR 45
    boardlist / giveboard <number|name>
    dlcweapon <number|name|default>   e.g.  dlcweapon M60
    giveskill [amount]                e.g.  giveskill 5
    clearskill                        remove all unspent skill points
    secrets                           secrets & police work checklist, this chapter first


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
  - No "RoboCop Cheats" in the pause menu and Ctrl+O does nothing: check that dwmapi.dll
    is next to RoboCop-Win64-Shipping.exe. For the window, GuiConsoleEnabled = 1 must be
    set in ue4ss\UE4SS-settings.ini.
  - Something doesn't work: set ConsoleEnabled = 1 in UE4SS-settings.ini to get a log
    window, or send ue4ss\UE4SS.log. The mod's lines start with [RoboCopCheats].
  - The game crashes at start after an update: remove dwmapi.dll and wait for a mod or
    UE4SS update.

CREDITS
  RE-UE4SS (MIT license, see ue4ss\LICENSE): https://github.com/UE4SS-RE/RE-UE4SS
