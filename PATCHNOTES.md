# Patch notes

Newest first. Each entry says what changed, which files it touches, and what you need to do to pick it up
(rebuild, restart, re-run SQL, edit config).

## 2026-10-06

**ZRProfessions 1.3: gathering tooltips for 3rd and 4th professions** (`client/ZRProfessions/`)
- Why: for a profession that isn't in the Professions tab's 2 slots, the client prints "Requires Herbalism 1" in red
  on every node (and a red "Skinnable" on corpses) whatever your skill. The real requirement is still enforced
  by the server: Briarthorn refused Herbalism 32 with "Requires Herbalism 70".
- `ZRProfessions.lua`: new `NODES` table with the required skill and skill-up color steps for 107 herb and ore
  nodes. Pre-Pandaria nodes use their classic required skill R (+25 / +50 / +100 for the colors, matching Wowhead,
  e.g. Briarthorn 70 / 95 / 120 / 170); Pandaria nodes need 1 and take their colors from `trivialSkillLow`/`High`
  in the world DB's `gameobject_template`, the same values the server uses for skill-ups. New tooltip hooks: for a
  node or corpse whose profession isn't in a client slot, the placeholder 1 becomes the real requirement and the
  line turns red (too low), orange, yellow, green or gray. Re-applied every frame in case the client repaints it.
  Professions in the 2 slots are left to the client.
- 1.1 kept the table in a second file, `ZRProfessions_Nodes.lua`. In game it didn't load and every node tooltip
  threw "attempt to index global 'ZRPROFESSIONS_NODES'". 1.2 keeps everything in the one file, so it can't happen again.
- 1.3: after swapping "1" for the real number the tooltip is re-fitted (it was sized for the shorter text, so a
  longer number ran into the right border).
- Confirmed in game: Briarthorn shows "Requires Herbalism 70" in red at Herbalism 32, and the tooltip fits. Merged into `main`.
- `ZRProfessions.toc`: version 1.3. `README.md` (addon): new "Gathering tooltips" section.
- To pick up: no rebuild, no SQL, no restart. Replace the `ZRProfessions` folder in `Interface/AddOns/` (delete
  `ZRProfessions_Nodes.lua` if 1.1 left it there) and restart the game client.

## 2026-10-01

**Level-appropriate pickpocket loot in revamped dungeons** (guide section 13)
(`tools/pandaria/pickpocket-difficulty.patch`, `tools/pandaria/sql/2026_10_01_normal_dungeon_pickpocket_loot.sql`
+ `_revert.sql`, all new)
- Found: Deadmines, Shadowfang Keep, Scarlet Halls, Scarlet Monastery and Scholomance use one creature entry
  for normal and heroic. Their pickpocket tables were captured in heroic and drop in every difficulty, so a
  level 14 Kobold Digger gives Rogue's Draught (req. 80) and Flame-Scarred Junkbox (Lockpicking 400). The
  stock core also rolls pickpocket loot without the dungeon difficulty.
- Patch: one line in `Player.cpp` (`Player::SendLoot`) passes the map difficulty to the pickpocket loot
  roll, the same way corpse loot already does. Rows tagged '' (all of the open world) behave as before.
  Recompiles `Player.cpp` and relinks; not a near-full rebuild.
- SQL: re-tags 117 heroic-level pickpocket rows as heroic-only, adds a level-appropriate junkbox for normal
  mode on 27 creatures (Battered for Deadmines/Shadowfang, Worn for the Scarlet dungeons, Sturdy for
  Scholomance), and re-tags 78 heroic-level corpse-loot rows (e.g. Fungus Squeezings in Shadowfang).
- Gold was also found to be heroic-level in these dungeons (Kobold Digger 76s 84c); left as is by choice,
  `SoloCraft.Money.Pct` handles it.
- To pick up: apply the patch and rebuild, back up the two tables, run the SQL, restart `worldserver`.
  The revert file restores every original row.
- Applied to the live server and confirmed in game the same day. Merged into `main`.

**ZRProfessions client addon: up to 4 primary professions** (`client/ZRProfessions/`, new)
- Why: `MaxPrimaryTradeSkill = 4` already works on the server, but the 5.4.8 client's trainer window
  (`Blizzard_TrainerUI.lua`) greys out **Train** for a new profession once the Professions tab's 2nd slot is
  filled. The tab itself only has 2 primary slots, because the client stores only 2 profession skill lines.
- `ZRProfessions.toc`: addon manifest (interface 50400).
- `ZRProfessions.lua`: after Blizzard's trainer code runs, re-enables **Train** for a new primary profession
  while you know fewer than 4 (the server still enforces the real limit when you buy). Gives the confirm
  popup text for the 3rd/4th profession. Adds a `/profs` panel (also an **All professions** button under the
  Professions tab) listing every primary profession with rank; clicking a crafting one opens it.
- `README.md` (addon): why, install steps, limits. Root `README.md` links to it.
- To pick up: no rebuild, no SQL, no restart. Check `MaxPrimaryTradeSkill = 4` in `worldserver.conf`, then
  copy `client/ZRProfessions` into each player's `Interface/AddOns/`.
- Confirmed in game the same day: a character with Leatherworking and Skinning could train a 3rd primary
  profession, and the addon worked as described. Merged into `main`.

**Solocraft settings to use alongside DungeonScale** (guide section 12, config only)
- Recommended values: `SoloCraft.Stats.Mult = 0`, `SoloCraft.Spellpower.Mult = 0`,
  `SoloCraft.Stats.Stamina = 0`, `SoloCraft.DamageTaken.Pct = 100`. `SoloCraft.Money.Pct` is your choice;
  it is only the gold penalty (the live server uses 5).
- Why: Stats.Mult and Spellpower.Mult at 0 switch the player buff off. Stats.Stamina only matters when there is a buff, so
  0 just keeps it off if Stats.Mult ever goes back up. DamageTaken below 100 would cut mob damage a second time on
  top of DungeonScale. Difficulty offsets can stay as they are.
- To pick up: edit `worldserver.conf` and **restart** `worldserver`. Solocraft reads its settings only at
  startup, so `.reload config` won't apply them. Characters that still have the old buff lose it the next
  time they leave a dungeon.

**DungeonScale design spec added to the repo** (`docs/dungeon-scale-spec.md`)
- The one-page spec (rules, starting numbers, phases, decisions and status log) now lives in the repo,
  linked from the README. It is updated with the Solocraft settings above, the loot and honor fixes, and what
  is still untested (the hit cap on a big hit, a MoP dungeon, a second player joining mid-run). Docs only.

**DungeonScale: honor fix** (`tools/pandaria/dungeon-scale.patch`)
- Dungeon kills gave no visible honor. The core stores honor in hundredths (the client shows the total
  divided by 100), but DungeonScale added whole points as-is, so a 5-honor kill added 0.05 honor.
  `DungeonScale.cpp` now converts to the stored unit, so kills give 1 / 5 / 10 / 25 honor as configured.
  Honor already earned from earlier runs stays as the small fraction it was.
- To pick up on a source tree that already has the patch, in `~/pandaria/source` (only that file recompiles):
  ```sh
  sed -i 's|^\( *\)player->ModifyCurrency(CURRENCY_TYPE_HONOR_POINTS, int32(amount));|\1// Honor is stored in hundredths (the client shows the total / 100), so convert whole points first.\n\1CurrencyTypesEntry const* honorEntry = sCurrencyTypesStore.LookupEntry(CURRENCY_TYPE_HONOR_POINTS);\n\1int32 const precision = (honorEntry \&\& (honorEntry->Flags \& CURRENCY_FLAG_HIGH_PRECISION)) ? CURRENCY_PRECISION : 1;\n\1player->ModifyCurrency(CURRENCY_TYPE_HONOR_POINTS, int32(amount) * precision);|' src/server/scripts/Custom/DungeonScale/DungeonScale.cpp
  ```
  then `make install` in `build` and restart `worldserver`.

**DungeonScale signed off** (several solo Deadmines runs)
- Confirmed in game: honor per kill (1 trash, 5 elite), loot and gold, pickpocketing, no kill XP, and
  difficulty that feels right through the dungeon. DungeonScale and the Solocraft settings patch are merged
  into `main`, so a plain `git pull` in the tools repo is enough from now on.
- Next, when wanted: solo enrage-timer handling, moving the gold penalty out of Solocraft (then removing
  Solocraft), and per-dungeon tuning with the `DungeonScale.Map.<id>.*` overrides.

## 2026-09-29

**DungeonScale: loot fix** (`tools/pandaria/dungeon-scale.patch`)
- Scaled dungeon mobs dropped no loot, gold or honor. The core only rewards a kill once players have dealt
  half the mob's health, and that amount was set from the mob's unscaled health, so a mob shrunk to 30% could
  never meet it. `DungeonScale.cpp` now resets that requirement whenever it scales a mob's health.
- To pick up on a source tree that already has the earlier version: add the line with
  `sed -i 's|^\(\s*\)creature->SetHealth(std::max(1u, std::min(health, maxHealth)));|&\n\1creature->ResetPlayerDamageReq();|' src/server/scripts/Custom/DungeonScale/DungeonScale.cpp`,
  then `make install` in `build` (only that file recompiles) and restart `worldserver`. Re-applying the whole
  patch also works but rewrites `ScriptMgr.h`, which forces a near-full rebuild.

**DungeonScale playtest** (live server, solo, Deadmines up to and including the first boss)
- Checked and working: scaled trash and first boss, loot and gold from kills, rogue pickpocketing,
  no kill XP (`Rate.XP.Kill = 0`). The first boss's difficulty felt right at the default multipliers.
- Solocraft is now neutral (`SoloCraft.Stats.Mult = 0`, `SoloCraft.Spellpower.Mult = 0`,
  `SoloCraft.DamageTaken.Pct = 100`) and only applies its gold penalty (`SoloCraft.Money.Pct`).
- Still to test: the rest of the dungeon (end boss, the 35% hit cap on big hits), a MoP dungeon, and a
  second player joining mid-run.

## 2026-09-28

**DungeonScale: dungeon mobs scale to the group** (`tools/pandaria/dungeon-scale.patch`, guide section 12)
- New script scales 5-man dungeon creatures to the number of players inside: health and damage per rank
  (solo trash 30% / 30%, mini-bosses 35% / 35%, end bosses 40% / 35%, straight line to 100% at 5 players).
  Boss adds use the boss's values. Replaces Solocraft's stat buffs, which should now be set to neutral.
- When someone joins or leaves, only mobs out of combat are rescaled.
- No single hit or DoT tick from a scaled mob takes more than 35% of your max health (`DungeonScale.HitCap.Pct`).
- Honor per dungeon kill: 1 trash / 5 elite / 10 mini-boss / 25 end boss.
- GM commands `.dungeonscale info` and `.dungeonscale creature`.
- New files: `src/server/scripts/Custom/DungeonScale/` (`DungeonScale.h`, `DungeonScale.cpp`, `DungeonScaleScripts.cpp`).
- Core files touched: `ScriptMgr.h` / `ScriptMgr.cpp` (new `AllCreatureScript` hooks: creature added,
  removed, level set, killed), `Creature.cpp` (calls the first three), `Unit.cpp` (calls the kill hook after
  kill rewards), `ScriptLoader.cpp` (registers the script), `worldserver.conf.dist` (new `DungeonScale.*` settings).
- Fix to the Solocraft patch: `SpellAuraEffects.cpp` called the DoT damage hook twice per tick, so
  `SoloCraft.DamageTaken.Pct` hit DoTs twice (30% became 9%). The duplicate call is removed.
- To pick up: apply the patch after the Solocraft patch, run `cmake .` in `build` (new source files), rebuild (near-full rebuild, because `ScriptMgr.h` changed),
  copy the `DUNGEON SCALE` block into `worldserver.conf`, set Solocraft's stat and damage settings to neutral
  (guide section 12), restart `worldserver`. The Helix SQL can stay: his damage works out about the same.

**Deadmines: Helix Gearbreaker melee** (`tools/pandaria/sql/2026_09_28_deadmines_helix_melee.sql`)
- Normal-mode Helix (entry 47296) swings every 0.5 s with a 57.5× damage multiplier, which burns a solo
  character down. The SQL lowers the multiplier to 20 (about 35% of stock). Heroic is untouched.
- To pick up: back up the row, run the SQL on the world DB, restart `worldserver`
  and respawn him. The revert line is in the file.

**Solocraft tuning for solo dungeon runs** (`tools/pandaria/solocraft-solo-tuning.patch`, guide section 11)
- New `worldserver.conf` settings: `SoloCraft.Stats.Stamina` (keep your health pool normal),
  `SoloCraft.DamageTaken.Pct` (less NPC damage inside Solocraft instances) and `SoloCraft.Money.Pct`
  (less creature gold). Both percentages rise to 100 with a full group. Defaults change nothing.
- Core files touched: `ScriptMgr.h` / `ScriptMgr.cpp` (new `OnCreatureLootMoney` hook), `Unit.cpp`
  (calls it after a killed creature's gold is rolled), `SpellAuraEffects.cpp` (DoT and leech ticks now
  call the existing `ModifyPeriodicDamageAurasTick` hook). Script: `solocraft_system.cpp`.
  Config: `worldserver.conf.dist`.
- To pick up: apply the patch, rebuild (near-full rebuild, because `ScriptMgr.h` is in the precompiled
  headers), add the settings, restart `worldserver`. `.reload config` does not reload Solocraft.
- Also checked: the world DB matched upstream exactly. Mobs are not nerfed, and low-level MoP really is that easy.

## 2026-09-27

**Holiday calendar and world events**
- `tools/pandaria/holiday_dates.py` regenerates `holiday_dates` so events stop drifting and double-listing
  (`--dump` shows what `Holidays.dbc` says). The Darkmoon Faire is covered for about 2 years; the script
  prints the date to re-run it.
- `CalendarHandler.cpp` fix (in `pandaria-fixes.patch`, or `calendar-fix.patch` on its own): no more
  ghost holidays 26 days early.
- Guide: cap command security at 3 so administrators can use GM commands; document the daily restart loop.

## 2026-09-26

**Debian 13 build guide for pandaria_5.4.8** (`docs/pandaria-debian13.md`)
- Build guide plus database installer (`tools/pandaria/install_databases.sh`).
- `pandaria-fixes.patch` for GCC 14: `std::atomic` init, Hallow's End tables, `PATH_MAX` and
  `inet_addr` includes, mapextractor backslash in DBC/DB2 names, and a shutdown segfault in
  `ScriptMgr::Unload`.
- Guide fixes: install gnupg before mysql-apt-config, MySQL root login, startup check, repo rename.

## 2026-09-25

**spawncompare** (`tools/spawncompare`)
- Compares a SkyFire world DB against a 4.3.4 or 5.4.8 reference and generates SQL for missing spawns.
- Options `--skip-mop-changes`, `--exclude-maps`, `--exclude-zones`; handles old-style `phaseMask`.
