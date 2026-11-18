# Forever Dungeon Atlas

Dungeon maps and dungeon quest tracking for **WoW Forever**, inside the normal world map. Press your usual map key (M) in a dungeon and you get a map of the dungeon, not the continent.

The Forever client ships no dungeon maps at all, old dungeons included (like Classic Era). So the addon brings its own: overhead maps of each dungeon, shown over the world map.

## Features

- **Dungeon maps**: an overhead map of the dungeon shows up when you open the map inside (or from the side panel anywhere). Wheel to zoom, drag to move, right-click to go back. Included: Ragefire Chasm, Wailing Caverns, Deadmines, Shadowfang Keep, Blackfathom Deeps, Stockade, Gnomeregan, Razorfen Kraul, Scarlet Monastery, Razorfen Downs, Uldaman, Zul'Farrak, Maraudon, Sunken Temple, Blackrock Depths, Dire Maul, Scholomance, Stratholme, and the new Forever dungeons Ruins of Lordaeron, City of Dalaran, Excavation Site: Wetlands, The Drowned City and The Hall of Thanes. Dungeons with several levels are shown in one picture.
- **Boss markers** on those maps: each boss's portrait where it stands (placed from cMaNGOS spawn positions). Killed bosses grey out with a tick, and the next one glows. Not yet in Shadowfang Keep, Deadmines, Scarlet Monastery and Zul'Farrak.
- **If the game adds real dungeon maps**: the addon finds them on its own and uses them on Blizzard's world map: floors and wings (with a wing picker for Scarlet Monastery and Dire Maul), floor memory (it learns which floor goes with each area and can follow you between floors), and boss portraits on the map.
- **Side panel**:
  - **Bosses**: in order. Shows killed / next / rare, and a `!` when a quest in your log needs that boss.
  - **Your quests**: this dungeon's quests in your log, with live objective progress. Hover for your party's progress.
  - **Available quests**: what you can still pick up, which step of the chain you're on, and who gives it. Click to set a waypoint.
  - **Group**: which floor each party member is probably on (if they run this addon). Click to view it.
- **Dungeon browser** (side panel anywhere outside a dungeon):
  - **Here**: the dungeon quests you can pick up in the zone you're viewing, and dungeon entrances in it.
  - **Your level / Coming up / Later / Below your level**: every dungeon, with how many of its quests are done, in progress or left to pick up.
  - **One dungeon**: entrance (waypoint), its map (browse the floors from anywhere), bosses and loot, and every quest chain grouped by where you go next. Expand a chain to see every step: prerequisites, the dungeon quest and its follow-ups (rewards often come on the last one), each with its quest giver.
  - Opens by itself when you look at a dungeon's map.
- **Quest givers on the map**: a `!` on zone maps where the next step of a dungeon quest chain near your level starts, badged with the dungeon's icon. Click for a waypoint; it clears itself when you arrive.
- **Movable side panel**: drag it by its title, and right-click the title to put it back. Collapsed, it's a small tab.
- **Key bindings**: next / previous floor (Key Bindings → AddOns).

## Commands

| Command | What it does |
|---|---|
| `/fdm` | Settings |
| `/fdm dungeons` | Open the map on the dungeon browser |
| `/fdm status` | What the addon found for this dungeon |
| `/fdm next`, `/fdm prev` | Change floor |
| `/fdm reset` | Clear boss kills for this run |
| `/fdm forget` | Forget learned floors |
| `/fdm clearpins` | Remove placed boss pins |
| `/fdm scan` | Write a diagnostic report to SavedVariables (then `/reload`) |

## Credits and license

Forever Dungeon Atlas is free software under the **GNU General Public License v3.0** (see `LICENSE`).

- Quest, boss and loot data (`Data/DungeonMaster_Data.lua`, `Data/DungeonMaster_Curated.lua`) comes, unchanged, from **DungeonMaster** by MalkDev (GPL-3.0). It is built on the **cMaNGOS classic-db** (GPL-3.0, https://github.com/cmangos/classic-db).
- Dungeon maps `Media/Maps/Wh_*` are Wowhead's overhead renders (wowhead.com), credited on screen.
- Guide maps for the new Forever dungeons (`Media/Maps/Guides.lua`) are community images, credited on screen: Ruins of Lordaeron, City of Dalaran, Excavation Site: Wetlands and Hall of Thanes from **Icy Veins** (icy-veins.com), and The Drowned City from **Warcraft Tavern** (warcrafttavern.com). They are not covered by this project's license.

World of Warcraft content (names, texts, IDs, art) belongs to Blizzard Entertainment. This project is not affiliated with Blizzard, DungeonMaster, CMaNGOS or Questie.
