# Changelog

## Live Wire 0.4.1, Power Grid 0.1.2, Spotlight 0.1.1
- Fixed: Live Wire's settings.cfg couldn't be read by the game (the arena value needed quotes), so
  practice bots never joined and, alone on the floor, the wire never dropped. Found in a real play
  test. All three minigames now read their settings even if a value is missing its quotes, and a new
  test reads the shipped files exactly as the game does.
- Playing alone: if you're the only player and bots are set to 0, three bots join anyway (none of
  the minigames can be played by one worker).
- Live Wire has a set: a high-voltage switch room with a rusted metal floor, walls of server racks
  with blinking lights, hanging lamps, a warning sign and a long drop into a glowing pit. The pillars
  are rack cabinets. Textures come from your own copy of the game; if a game update removes one,
  that piece is simply left out.

## Spotlight 0.1.0 (new minigame, test release)
- A spotlight wanders across the floor. Stand in it alone to score a point a second; share it and
  nobody scores. Falling off puts you out but you keep your points. Most points after 45 seconds wins.
- Practice bots with different temperaments (some barge in, some wait for a gap), off by default.
- Tested: path, scoring, places, bots; three networked machines over direct and simulated wifi, bad
  wifi, mobile and transatlantic connections; a full session through the game's own lobby, picker,
  briefing and score screen.

## Live Wire 0.4.0
- Three arenas: Classic, Pocket (small floor, no pillars) and Sweeper (a rotating arm sweeps the
  floor). A different arena each round by default; `arena` in settings.cfg picks one. The host's
  choice counts online.

## Power Grid 0.1.1
- Fairer online: each player's own machine decides whether they were on a live panel, so lag can no
  longer shock someone who had already stepped off on their screen. The host waits briefly for every
  player's report before scoring a wave. Tested with simulated lag where the host still saw the
  player on the panel: the player correctly survived.

## Installer
- Install.bat / Uninstall.bat: finds the game through Steam, checks the mod loader is installed and
  the game is closed, keeps your settings when updating, and only touches this mod's folders.

## Power Grid 0.1.0 (new minigame, test release)
- The floor is a grid of power panels. Panels flash amber, then surge; anyone on a surging panel is
  electrocuted. Each surge covers more of the floor and comes faster. Shoving and edges work as in
  Live Wire. Workers who go out in the same surge share a place.
- Practice bots (power_grid/settings.cfg), off by default, never online.
- Tested: rules, panels, bots and scoring; three networked machines over direct connection and
  simulated wifi, bad wifi, mobile and transatlantic networks; a full session through the game's
  own lobby, picker and briefing.

## Live Wire 0.3.1
- Easier to read: a glowing ring at the holder's feet, a thicker cable that glows, a bigger plug
  and a brighter arena.

## Custom Minigames 0.3.2
- The round screen shows the custom minigame's tagline even while the game still holds the
  borrowed slot's ID (new `current_custom_id()` for mods).
- The lobby version tag now includes which custom minigames (and versions) are installed, so players
  with different sets can't join each other (tested: a player missing Power Grid is refused).
- New modder's guide: MODDING.md.

## Live Wire 0.3.0 (test release)
- Practice bots: up to 3 computer-controlled workers for solo or couch play (live_wire/settings.cfg).
  They never join online matches and their scores are not sent to the game.
- "No tag-backs": whoever just passed the wire can't be handed it straight back for 1.5 seconds.
- Passing by touch is now reliable: the pass distance was equal to two workers' body width, so
  touching only sometimes passed the wire.
- Tested under simulated bad networks (wifi, mobile, transatlantic, extreme loss) with 3 machines.

## Custom Minigames 0.3.1 (test release)
- Fixed: in online games, other players loaded the borrowed built-in slot (Shape Cutter) instead of
  the custom minigame. Found by a three-machine networked session test.

## Custom Minigames 0.3.0 + Live Wire 0.2.0
- Game-update safety: checks the installed game against everything the mod relies on; switches
  itself off with a main-menu notice if anything changed; notes untested game versions.
- Live Wire checks the game parts it borrows (worker, stages, overlay, sounds) before registering.
- Fixed a load-order problem that could leave the Disco Dodge worker without its script.
- settings.cfg replaces the hard-coded test mode.

## Custom Minigames 0.2.0 + Live Wire 0.1.0
- First custom minigame: Live Wire.
- Icons can be loaded from a mod's own folder.

## Custom Minigames 0.1.1
- Custom minigames in the lobby playlist editor, saved playlists, custom-playlist games,
  intermission picker grid and briefing screen; custom round taglines.

## Custom Minigames 0.1.0
- First version: custom minigame registry, loading through a borrowed unused slot, lobby version tag.
