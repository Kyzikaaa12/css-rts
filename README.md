# CSS RTS

A SourceMod mod that turns a Counter-Strike: Source listen server into a small RTS. You command from above, seat workers at desks, research guns, and win by destroying the enemy HQ.

cs_office is the map this is built for. de_dust2 is included and still rough.

## Install

1. Install [Counter-Strike: Source](https://store.steampowered.com/app/240).
2. Install [MetaMod:Source](https://www.sourcemm.net/) and [SourceMod 1.12](https://www.sourcemod.net/) into the game's `cstrike` folder.
3. Download this repo (Code, then Download ZIP) or the Release zip.
4. Unzip into `cstrike`, so these paths exist:
   - `cstrike/addons/sourcemod/plugins/css_rts.smx`
   - `cstrike/addons/sourcemod/configs/css_rts/`
   - `cstrike/custom/css_rts/`
   - `cstrike/cfg/rts.cfg`
   - `cstrike/cfg/sourcemod/css_rts.cfg`
5. Launch the game with `-insecure`. MetaMod does not load without it.
6. On the main menu, click **RTS**. Leave the map on cs_office, set the Game tab, then Start.

The mod forces a LAN listen server (`sv_lan 1`). It does not replace stock Counter-Strike when the plugin is not loaded.

## Play

F2 opens the command menu. F3 takes commander. In command view, WASD pans, the mouse wheel zooms, and Q and E rotate. Hire workers onto the yellow desk rings. The match ends when an HQ hits 0%.

A map restart loads a new plugin and desk layout. The Create Server Game tab is read when the game starts, so a change there needs a full restart.

## Notes

Soldiers per team on the Game tab is 0–16. Trained units are extra bots, up to 8 per team. Workers do not use player slots. The engine cap is still 64 players.
