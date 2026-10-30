# Custom Minigames for Machine Party (+ Live Wire, Power Grid, Spotlight)

An unofficial, free fan mod for **Machine Party** that lets new minigames be added to the game,
and comes with three of them: **Live Wire**, **Power Grid** and **Spotlight**.

> Not made, endorsed or supported by the developers of Machine Party. You need your own copy of the
> game. This mod contains no game files: the minigames use the worker character, animations and
> sounds from your own installed copy.

## Live Wire

One worker is holding a live cable. Touch another worker to pass it on. The fuse is hidden; when it
runs out, whoever holds the cable is electrocuted. The cable crackles harder just before it blows.
Shoving works, and anyone who falls off the floor is out. Last worker standing wins.

- Three arenas: **Classic** (two pillars), **Pocket** (a small floor with nowhere to hide) and
  **Sweeper** (a rotating arm sweeps the floor). A different one each round, or pick one in Settings
- 2-4 players, online or couch
- Practice bots for playing alone or topping up couch games (off by default, see Settings)
- Appears in the standard playlist, the custom playlist editor and the intermission picker, with
  its own icon, briefing and tagline

## Power Grid

The floor is a grid of power panels. Panels flash amber, then surge, and anyone standing on a
surging panel is electrocuted. Each surge covers more of the floor and comes faster. Shoving works,
and the floor has edges. Last worker standing wins.

- 2-4 players, online or couch, with optional practice bots
- Workers who go out in the same surge share a place
- Fair online: each player's own machine decides whether they were standing on a live panel, so lag
  can't shock you after you'd stepped off on your screen

## Spotlight

A spotlight wanders across the floor. Stand in it alone to earn a point every second; if two
workers share the light, nobody scores, so shove them out. Workers who fall off are out but keep
their points. Most points after 45 seconds wins.

- 2-4 players, online or couch, with optional practice bots
- Points show on everyone's name tag; the light turns gold for whoever is scoring and red when it's
  shared

## What the framework does

- Lets mods register new minigames, which then work everywhere built-in ones do: standard and
  custom playlists (saved between sessions), the lobby playlist editor, the intermission picker
  and briefing screen
- Keeps modded and unmodded players apart: modded lobbies have their own version tag, which also
  records which custom minigames (and versions) are installed, so nobody joins a game they can't load
- **Game-update safety:** on start-up it checks that everything it relies on is still in the
  installed game. If a game update changed any of it, the mod switches itself off and says so on
  the main menu, rather than risk breaking your game

## Requirements

- Machine Party on Steam, PC (tested with game version **v2.1.2**)
- **Machine Party Mod Loader** by Krunk-theduck (separate download, see INSTALL.txt)
- Everyone in a lobby needs the same version of this mod

## Install / uninstall

See **INSTALL.txt**. In short: install the mod loader, then close the game and double-click
**Install.bat** (or copy the folders from `mods/` into the `mods` folder the loader creates).
To uninstall, double-click **Uninstall.bat**.

## Settings

`mods/custom_minigames/settings.cfg` (open with Notepad):

| Setting | Default | What it does |
|---|---|---|
| `add_custom_to_standard_playlist` | `true` | Custom minigames join the standard playlist |
| `only_custom_minigames` | `false` | Standard games play only custom minigames (for testing) |

`mods/live_wire/settings.cfg`, `mods/power_grid/settings.cfg` and `mods/spotlight/settings.cfg`:

| Setting | Default | What it does |
|---|---|---|
| `bots` | `0` | Practice bots (0-3) that join that minigame when no other machines are connected. Never used online. Playing alone with `0`? Three bots join anyway. |
| `arena` (Live Wire only) | `rotate` | `rotate` (a different arena each round), `classic`, `pocket` or `sweeper`. In online games the host's choice counts. |

Install.bat keeps your settings when you update.

Don't want one of the minigames? Delete its folder (`live_wire`, `power_grid` or `spotlight`) from `mods`.
Everyone in a lobby needs the same set; the game only lets matching players join each other.

## Known issues

- Test release: tested in automated three-machine sessions over a direct connection, including
  simulated bad networks, but not yet in a full online match over Steam with real players.
  Please report problems.
- Custom minigames take the place of a built-in minigame that isn't in the playlist on the
  intermission picker's icon grid (the grid has a fixed 15 slots).
- After a game update the mod may switch itself off until it is updated (by design).

## For mod makers

See **MODDING.md**: how to build your own minigame on the framework, with Live Wire, Power Grid
and Spotlight (their source is in the zips inside their mod folders) as worked examples.

## Licence

The mod's own code, scene and icon: MIT licence (see LICENSE). Machine Party and all of its
content belong to its developers and publisher and are not covered by this licence.
