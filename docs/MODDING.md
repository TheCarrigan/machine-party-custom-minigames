# Making your own minigame for Machine Party

This guide is for people who want to add a new minigame using the **Custom Minigames** framework.
Live Wire, Power Grid and Spotlight, the three minigames that ship with it, were built exactly as described
here. Their full source is in the download: it's in the `.zip` inside each minigame's mod folder.
Open those files alongside this guide.

> Unofficial and unsupported by the game's developers. Everything here can break when the game
> updates. The framework checks for that and switches itself off (see "When the game updates").

---

## 1. How it works

The game keeps a fixed list of minigames, numbered 0 and up. The framework lets a mod **register**
another one, which it gives a **negative ID** (-1, -2 and so on, in the order mods load). After
that, the custom minigame shows up everywhere a built-in one does:

| Where | What the player sees |
|---|---|
| Standard playlist | Added automatically (players can turn this off in `settings.cfg`) |
| Lobby playlist editor | Listed with your name and icon, and can be dragged and reordered |
| Intermission picker | Your icon swaps into a grid cell that isn't in use this session |
| Briefing screen | Your pages, plus the controls page copied from a built-in minigame |
| Round screen | "Round 1/2" with your tagline underneath |

When your minigame is due to play, the framework lends your scene to an **unused built-in slot**
(Shape Cutter, which isn't in the shipped playlist). The game's own loader then loads and runs it
like any other minigame, online or couch. Your scene therefore has to behave like a built-in
minigame. Section 4 covers what that means.

Modded lobbies get a version tag such as `v2.1.2+custom-minigames.1.960516`. The last part is a
fingerprint of which custom minigames, and which versions of them, are installed. Players can only
join each other when the tags match, so nobody joins a game they couldn't load.

## 2. What you need

- Machine Party (Steam, PC) and the **Machine Party Mod Loader** by Krunk-theduck.
- The **Custom Minigames** framework (`mods/custom_minigames`) from this download.
- **Godot 4.5.2** (standard build, from godotengine.org) if you want to edit scenes visually.
  A text editor also works: Live Wire's scene was written by hand.
- Optional, to read how the game's own minigames are built: recover a **private** copy of the
  game's project with GDRE Tools. Treat it as reference only and keep it on your PC (see section 8).

## 3. Files of a minigame mod

```
mods/
  my_game/
    mod.json            what the mod loader reads
    main.gd             registers the minigame with the framework
    settings.cfg        optional player settings
    icon_my_game.png    256x256 icon (your own art)
    my_game.zip         your scene and scripts, mounted as a resource pack
```

Inside `my_game.zip`, every path must sit under `custom_minigames_content/<your key>/`:

```
custom_minigames_content/my_game/my_game.tscn
custom_minigames_content/my_game/my_game.gd
custom_minigames_content/my_game/states/play_state.gd
custom_minigames_content/my_game/states/finish_state.gd
```

That folder is where your files live once mounted (`res://custom_minigames_content/my_game/...`).
Keeping each minigame in its own folder means two mods can never overwrite each other's files.
Put only `.gd`, `.tscn` and `.tres` files in the pack, and leave out the `.uid` and `.import` files
the Godot editor creates. On Windows, right-click the `custom_minigames_content` folder and choose
**Send to > Compressed (zipped) folder**. That keeps the folder name at the top of the zip, which is
what you want. Then rename the zip to `my_game.zip`.

### mod.json

```json
{
  "id": "my_game",
  "name": "My Game (custom minigame)",
  "version": "0.1.0",
  "entry": "main.gd",
  "priority": 30,
  "requires": ["custom_minigames"]
}
```

The framework loads at priority 5. Use a higher number so your mod loads after it. Live Wire
uses 20 and Power Grid 21.

### main.gd

Start from Power Grid's `main.gd`. It does five things, in this order:

1. Reads `settings.cfg` (optional).
2. Mounts the content pack: `loader.mount_assets("my_game", "my_game.zip")`.
3. Gets the framework: `loader.registry("custom_minigames").get("api")`. If that is `null`, or
   `cm.is_disabled()` is true, it stops quietly.
4. Checks that the game parts it borrows still exist (section 6).
5. Calls `cm.register({...})`.

Settings files use Godot's ConfigFile syntax: text values need quotes (`arena="rotate"`, not
`arena=rotate`). One unquoted value makes Godot reject the whole file. The shipped minigames read
their files with a forgiving `read_setting()` helper (see Live Wire's `main.gd`) for that reason.

`register` takes:

| Key | Required | Meaning |
|---|---|---|
| `key` | yes | Unique id string, e.g. `"my_game"` |
| `version` | | Your mod's version. It goes into the lobby tag, so only players with the same version meet |
| `scene` | yes | `res://custom_minigames_content/my_game/my_game.tscn` |
| `name` | | Shown in the picker, playlist editor and briefing |
| `tagline` | | Short line under "Round 1/2", in capitals like the game's own |
| `icon` | | A `res://` texture, or an absolute path to a PNG in your mod folder (`loader.dir_of("my_game").path_join("icon.png")`) |
| `rounds` | | Rounds per session (default 2) |
| `brief_from` | | Built-in minigame to copy the controls page from, e.g. `"DiscoDodge"` |
| `brief_headers`, `brief_pages` | | Your own briefing pages: headers and texts, same length |

It returns your minigame's ID (negative), or 0 if registration failed. The reason goes to
`modloader.log`.

## 4. The minigame scene

The root node's script must **extend the game's `Minigame` class**. The game calls the same
functions on your minigame that it calls on its own. Here is what a minimal minigame needs, in
the order things happen:

| Step | Who | What your script does |
|---|---|---|
| Loaded | everyone | `_ready()`: call `super._ready()`. On the host, connect the shared countdown's `countdown_started`, `tick` and `expired` signals to the base class handlers. In couch play (`GameManager.local_game`), emit `minigame_ready` after a short timer, because there are no remote players to wait for. |
| All loaded | host | `all_players_loaded()`: call `super`, set `is_all_player_loaded = true`, emit `minigame_ready(multiplayer.get_unique_id())`. |
| Start | host | `initialize(round, total, scores)`: call `super`, spawn the players, then `state_machine.transition_to_rpc.rpc(&"Round", {"round": round, "total": total})`. |
| Intro | everyone | The shared **Round → PlayerMarker → Countdown** states run by themselves. |
| Go | host | `_on_countdown_expired()`: call `super` (shows GO!), activate the players, move to your own `Play` state, and start your rules. |
| End | host | Work out scores, then emit `player_scores_finalized(scores)` with a `{network_id: score}` dictionary. Higher is better. |
| Hand back | everyone | Move to your `Finish` state. On every machine it fades the minigame out; on the host it then emits `minigame_finished`. |
| Leaver | host | `player_disconnected(id)`: call `super`, then make sure your match can still end. |
| Cleanup | host | `cleanup()`: `queue_free()` if you're the authority. |

The scene tree the shipped minigames use (see `live_wire.tscn`, `power_grid.tscn` and `spotlight.tscn`):

```
MyGame (Node, script extends Minigame)
├─ WorldEnvironment, Lights, Arena ...      your level
├─ StateMachine (game's StateMachine.gd, initial state Empty)
│   ├─ Empty, Round, PlayerMarker, Countdown   the game's shared states
│   └─ Play, Finish                            your own two states
├─ Networked
│   ├─ PlayerSpawner (MultiplayerSpawner: spawnable = the worker scene, spawn path ../Players)
│   ├─ Players
│   └─ PlayerSpawnPositions (one Marker3D per player, up to 4)
├─ Camera3D (current)
└─ MinigameOverlay (instance of the game's overlay scene)
```

The **worker** all three minigames use is Disco Dodge's player scene. It can walk, shove and fall off
edges. The host instantiates one per player, adds it under `Players` (the spawner copies it to
everyone), then calls `set_player_presence.rpc(id)` and `teleport_rpc.rpc(position)`. When the
round starts, `set_active_rpc.rpc(true)` lets players move. A worker emits `died(network_id)` when
it falls, and `kill_rpc.rpc()` knocks one out.

Sounds: call the game's `SoundManager.play_omni("<name>", volume_db, pitch)` with names the game
already uses. Live Wire uses `collar_activate` and `bad_explosion`. You can also reference game
audio files directly from your scene, as Live Wire does with a hum loop. Your mod never includes
those files; they come from the player's own copy of the game.

## 5. Multiplayer rules of thumb

- **The host decides everything.** Timers, randomness, hits and eliminations run only where
  `multiplayer.is_server()` is true.
- **Tell everyone what happened** with RPCs marked `@rpc("authority", "call_local", "reliable")`:
  who holds the wire, which panels light up, who got zapped. Clients only show it.
- **Players move their own workers.** The worker scene already syncs position and animation,
  and the host reads those positions to apply your rules.
- **Mind the lag when a hit depends on where someone stands at a moment.** The host sees other
  players slightly in the past, so a host-side "are you on the hazard?" check can hit someone who
  had already stepped away on their own screen. Let each machine judge its own worker against what
  it sees and report the hit to the host, the way the game's own falls work (Power Grid's
  `_check_own_worker` / `report_shock_rpc`). Have the host wait briefly for every machine's
  report before scoring. For soft, continuous rules (Spotlight's points), the host's view is fine.
- **Same randomness everywhere?** Only the host rolls dice, then sends the result. For something
  that moves smoothly (Spotlight's light, Live Wire's sweeper arm), send a seed or a start signal
  once and let every machine animate it from its own clock, instead of streaming positions.
- **Couch play** is one machine with several local players, and the same code path covers it.
  `GameManager.local_game` is true there.
- **IDs:** real players' network IDs are always positive. If you add computer-controlled players
  (practice bots), give them negative IDs, keep them out of `PlayerManager`, and don't include
  them in the scores you emit. All three shipped minigames show how.

## 6. When the game updates

Your minigame borrows game parts: the `Minigame` class, the worker scene, the shared states and
some sounds. A game update could rename or remove any of them. So before registering, check that
they're still there:

```gdscript
var problems: Array = cm.check_contract({
    "res://modules/minigame/minigame.gd": {
        "methods": {"initialize": 3, "all_players_loaded": 0},   # name: number of arguments
        "props": ["minigame_overlay", "state_machine"],
        "signals": ["minigame_ready", "minigame_finished", "player_scores_finalized"],
    },
})
for path in GAME_FILES:
    if not ResourceLoader.exists(path):
        problems.append("missing game file " + path.get_file())
if not problems.is_empty():
    for pr in problems:
        cm.report_problem("My Game", str(pr))   # shown on the main menu
    return                                      # don't register
```

The framework runs the same kind of check on what it relies on. If anything has changed, it
switches itself off and shows a notice on the main menu. It doesn't guess. That is far better
than a crash halfway through a party.

If a script you check belongs to a scene, add `"load_first": "<scene path>"` to its entry. The
scene then loads before the script, which avoids a Godot quirk that can leave the scene without
its script.

## 7. Testing

- **Fast loop:** in `mods/custom_minigames/settings.cfg`, set `only_custom_minigames=true` so the
  standard playlist plays only custom minigames, and start the game through Steam as usual.
- **Logs:** `%APPDATA%\Godot\app_userdata\Machine Party\modloader.log` shows what loaded and
  what was registered. It also lists any problems.
- **Alone:** give your minigame practice bots (see Live Wire or Power Grid) so you can play it
  with nobody else around.
- **Automated:** Live Wire, Power Grid and Spotlight were tested with scripts that run the game without a
  window. Those scripts check the rules, bots, scoring and game-update safety. They also run three
  networked copies (some through a simulated bad network) and full sessions through the game's own
  lobby and picker. They ran on the author's PC and aren't published, but the list above is a good
  checklist of what to try before you share a minigame.

## 8. Sharing it: what you may and may not include

> Built on this framework, or reused one of the demo minigames? A credit and a link back to
> https://github.com/TheCarrigan/machine-party-custom-minigames is appreciated. The MIT licence also
> asks you to keep the copyright notice and licence text with any copied code.

- **Ship only your own work:** your scripts, scenes, icon and docs. Use art and sound you made
  yourself, or CC0 assets with credit.
- **Don't include any of the game's files**, even ones you changed, and don't include code copied
  from the game's scripts. Reference game resources by their `res://` path instead, so they load
  from each player's own copy of the game. (The release builder for this download compares every file
  with the game's files and refuses to build if it finds a copy.)
- Say clearly that your mod is unofficial, and that players need their own copy of the game.
- Bump your version whenever you change anything, because everyone in a lobby needs the same one.

## 9. Framework API reference

From another mod: `var cm = loader.registry("custom_minigames").get("api")`

| Call | Returns |
|---|---|
| `register(def)` | New ID (negative), or 0 |
| `is_custom(id)` | true for a registered custom minigame |
| `get_def(id)`, `all_ids()` | Its definition / all custom IDs |
| `display_name(id)`, `tagline(id)`, `icon_texture(id)` | What the menus show |
| `current_custom_id()` | The custom minigame being played right now, or 0 |
| `wait_ready()` (await), `is_ready()` | Whether the game's singletons exist and playlists are set up |
| `is_disabled()`, `problems()` | Whether the framework switched itself off, and why |
| `check_contract(dict)` | List of problems with the game parts you rely on |
| `report_problem(source, text)` | Adds a line to the main-menu notice |

Limits: up to 20 custom minigames. The picker grid has 15 cells, so a custom minigame takes
the place of a built-in one that isn't in the current playlist.
