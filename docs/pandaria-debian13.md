# Building pandaria_5.4.8 on Debian 13

Core: <https://github.com/alexkulya/pandaria_5.4.8> (GPL-2.0, Mists of Pandaria 5.4.8 build 18414).

This guide builds the core, creates its databases and prepares client data on a fresh Debian 13
(trixie) VM. The project documents Ubuntu 20.04/22.04 with GCC 9–11 and MySQL 8.0. Debian 13 ships
GCC 14, CMake 3.31 and no MySQL 8.0, so a few steps differ from the upstream README. Every
difference below was reproduced with the same compiler (GCC 14.2), Boost (1.83) and CMake behaviour:
the patched source compiles, `authserver` starts and serves the realm list, and `worldserver`
connects to the three databases and runs until it needs the extracted client data.

## 0. VM sizing

| | Minimum | Comfortable |
|---|---|---|
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 16 GB |
| Disk | 60 GB | 100 GB (source + build + client copy + extracted data) |

The full compile took 61 minutes on 4 cores in testing (upstream estimates about 70 minutes with 8
threads on their setup). Generating movement maps (step 6) takes several hours.

## 1. Build tools and libraries

```sh
sudo apt update
sudo apt install -y git cmake make g++ unzip tmux gnupg wget \
  libssl-dev libbz2-dev libreadline-dev libncurses-dev zlib1g-dev \
  libboost-system-dev libboost-locale-dev libboost-filesystem-dev libboost-thread-dev \
  libboost-regex-dev libboost-serialization-dev libboost-date-time-dev
```

## 2. MySQL 8.4 LTS (not MariaDB)

The core must be built against **MySQL's** client library; MariaDB's headers break the build
(`my_bool` typedef clash in `src/server/shared/Database/MySQLCompat.h`). Debian 13 only packages
MariaDB, and Oracle publishes MySQL 8.4 LTS, not 8.0, for trixie. Install server and client from
Oracle's APT repository on this VM, and do not install any MariaDB packages alongside it.

1. Download the repository setup package (it needs `gnupg`, installed in step 1) (`mysql-apt-config_*_all.deb`, version 0.8.36 or newer; 0.8.40
   works) from <https://dev.mysql.com/downloads/repo/apt/>.
2. Install it and select **mysql-8.4-lts** when asked:
   ```sh
   sudo dpkg -i mysql-apt-config_*_all.deb
   sudo apt update
   sudo apt install -y mysql-server libmysqlclient-dev
   ```
3. Server settings matching the project's own Docker setup, plus a packet size large enough for
   the database dumps:
   ```sh
   sudo tee /etc/mysql/mysql.conf.d/pandaria.cnf <<'EOF'
   [mysqld]
   sql_mode             = NO_ENGINE_SUBSTITUTION
   max_allowed_packet   = 1G
   character-set-server = utf8mb4
   collation-server     = utf8mb4_unicode_ci
   EOF
   sudo systemctl restart mysql
   ```
4. A database user for the server. Oracle's installer asks for a MySQL root password; log in
   with it (`-p` prompts for it):
   ```sh
   mysql -u root -p -e "CREATE USER 'pandaria'@'localhost' IDENTIFIED BY 'choose-a-password';
     GRANT ALL PRIVILEGES ON auth.* TO 'pandaria'@'localhost';
     GRANT ALL PRIVILEGES ON characters.* TO 'pandaria'@'localhost';
     GRANT ALL PRIVILEGES ON world.* TO 'pandaria'@'localhost';"
   ```

The project lists MySQL 5.7/8.0 as supported. It doesn't use any client function that MySQL 8.4
removed (only `my_bool`, which its compatibility header already handles), but it hasn't been tested
against 8.4 here.

## 3. Source and fixes

```sh
mkdir -p ~/pandaria && cd ~/pandaria
git clone https://github.com/alexkulya/pandaria_5.4.8.git source
git clone https://github.com/xxciv/zrpandaria548.git tools-repo
cd source
git apply ../tools-repo/tools/pandaria/pandaria-fixes.patch
```

GCC 14 rejects a few things older compilers let through, and one extractor bug only shows on Linux.
The patch fixes exactly those, plus a shutdown crash and the holiday calendar, in seven files:

| File | Fix |
|---|---|
| `src/server/shared/Define.h` | add `<climits>` for `PATH_MAX` |
| `src/server/shared/Utilities/Util.cpp` | add `<arpa/inet.h>` for `inet_addr` |
| `src/server/game/World/World.cpp` | initialise two `std::atomic` statics with braces (C++14 copy-init is ill-formed) |
| `src/server/scripts/Events/hallows_end.cpp` | brace the `Position` in two Hallow's End tables |
| `src/tools/map_extractor/System.cpp` | don't keep the `\` path separator in extracted `.dbc`/`.db2` names |
| `src/server/game/Scripting/ScriptMgr.cpp` | stop double-deleting unused scripts (segfault in `ScriptMgr::Unload()` on every shutdown) |
| `src/server/game/Handlers/CalendarHandler.cpp` | send yearly holidays by calendar year, the Darkmoon Faire by its real dates, and nothing in 2031+ (the client reads year 31 as "every year", which drew a copy of each holiday 26 days early) |

The Hallow's End fix is also a real bug fix: `Position` has a constructor, so without inner braces
each row's coordinates spilled into the following rows, and the fire event read wrong positions.
Older compilers only warned about it.

## 4. Configure and compile

CMake 3.28 and newer reject the `exec_program` calls in the project's MySQL detection. Passing an
empty `MYSQL_CONFIG` together with explicit paths skips that code without changing any source.

```sh
cd ~/pandaria/source && mkdir -p build && cd build
cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=$HOME/pandaria/server \
  -DBUILD_DEPLOY=0 \
  -DSCRIPTS=1 -DTOOLS=1 -DNOJEM=1 -DUSE_COREPCH=1 -DUSE_SCRIPTPCH=1 \
  -DMYSQL_CONFIG= \
  -DMYSQL_INCLUDE_DIR=/usr/include/mysql \
  -DMYSQL_LIBRARY=/usr/lib/x86_64-linux-gnu/libmysqlclient.so
make -j"$(nproc)" install
```

`-DBUILD_DEPLOY=0` matters: the project turns that option on by default, which adds full debug
information (`-g3`) and `-march=native`. With it on, the build directory grows to about 14 GB and
the binaries only run on CPUs like the build machine's; the project's own Dockerfile turns it off too.

Run the compile inside `tmux` so it survives a dropped SSH session. If the machine runs out of
memory, use fewer jobs (`make -j2 install`). Afterwards `~/pandaria/server/bin` contains
`authserver`, `worldserver`, `mapextractor`, `vmap4extractor`, `vmap4assembler` and
`mmaps_generator`, and `~/pandaria/server/etc` the `.conf.dist` templates.

## 5. Databases

`tools/pandaria/install_databases.sh` imports the base dumps and applies about 110 update files in
the correct order. Don't skip them: the project's own Docker import only applies `sql/updates` and
misses the 2023–2026 world updates that were moved to `sql/old`, including
`2024_08_22_00_world_faction.sql`. Without it the current core refuses to start
(`Unknown column 'faction'` / `Cannot connect to world database`).

```sh
export MYSQL_PWD='your-mysql-root-password'   # sudo mysql users: see below
MYSQL_ARGS="-u root" ~/pandaria/tools-repo/tools/pandaria/install_databases.sh ~/pandaria/source
unset MYSQL_PWD
```

If you left the root password empty during installation, root logs in through `sudo mysql`
instead; then use `sudo mysql` in step 2.4 and run the installer as
`sudo MYSQL_ARGS="" ~/pandaria/tools-repo/tools/pandaria/install_databases.sh ~/pandaria/source`.

Expected result: about 314,700 creatures and 170,100 gameobjects, and one known failure,
`old/world/2026_08_06_21_world_repair_locale_encoding.sql` (French/Spanish/Portuguese text repairs;
English is unaffected). Anything else listed as failed needs a look.

## 6. Client data

The server needs `dbc`, `maps`, `vmaps` and `mmaps` extracted from a **5.4.8 (18414)** client.
Copy the client folder (the one with `Wow.exe` and `Data/`) to the VM, then:

```sh
cd ~/wow-548-client
~/pandaria/server/bin/mapextractor                 # dbc/ and maps/
~/pandaria/server/bin/vmap4extractor               # Buildings/
mkdir -p vmaps && ~/pandaria/server/bin/vmap4assembler Buildings vmaps
mkdir -p mmaps && ~/pandaria/server/bin/mmaps_generator --threads "$(nproc)"   # several hours
mkdir -p ~/pandaria/server/data
mv dbc maps vmaps mmaps ~/pandaria/server/data/
```

Without the extractor fix, every file in `dbc/` is named with a leading backslash
(`\AreaTable.dbc`) and `worldserver` stops with `ALL required *.dbc files (168) not found`. To
repair files extracted with an unpatched `mapextractor`, rename them in place (and in any locale
subfolder):

```sh
cd ~/pandaria/server/data/dbc
for f in \\*; do mv -- "$f" "${f#\\}"; done
```

The upstream README also links a prebuilt geodata archive on Google Drive; it was made from a
Russian client (`RU dbc`), so extracting from your own client is preferable.

## 7. Configuration

```sh
cd ~/pandaria/server/etc
cp authserver.conf.dist authserver.conf
cp worldserver.conf.dist worldserver.conf
mkdir -p ~/pandaria/server/logs
```

In **both** files, point the database lines at the `pandaria` user
(`"127.0.0.1;3306;pandaria;choose-a-password;auth"`, and likewise `world` and `characters` in
`worldserver.conf`) and set `LogsDir = "/home/<you>/pandaria/server/logs"`. In `worldserver.conf`
also set `DataDir = "/home/<you>/pandaria/server/data"`.

`SOAP.Enabled = 1` is the default but only listens on `127.0.0.1`; leave it or set it to 0.

## 8. Realm address and first account

The realm list ships with `127.0.0.1`. For clients on other machines, use the VM's LAN address:

```sh
mysql -u root -p -e "UPDATE auth.realmlist SET address = '192.168.x.x' WHERE id = 1;"
```

Start both servers (each in its own `tmux` window):

```sh
cd ~/pandaria/server/bin
./authserver
./worldserver
```

At the worldserver console:

```
account create myname mypassword
account set gmlevel myname 3 -1
```

Open TCP ports 3724 (auth) and 8085 (world) if the VM has a firewall.

**Daily restart.** `worldserver` restarts itself every day at 03:55 (`Enable.Auto.Restart.Server`
is on by default; the time is `Auto.Restart.Server.Hour`/`Minute`). "Restart" means it exits, so
start it from a loop that brings it back, still inside `tmux` so the console stays usable:

```sh
cd ~/pandaria/server/bin
while true; do ./worldserver; echo "worldserver exited ($?), restarting in 10s (Ctrl-C to stop)"; sleep 10; done
```

To turn the daily restart off instead, add `Enable.Auto.Restart.Server = 0` to `worldserver.conf`.
Keeping it on is useful: holiday dates (section 10) are only read at startup.

The shipped `command` table comes from a live server with its own staff levels: most commands
require level 4, 5 or 6, which no account can use (the core's highest account level is 3,
administrator). As shipped, even `.gm on` and `.event` are out of reach. Cap them at 3 so
administrators can use every command, then restart `worldserver`:

```sh
mysqldump -u root -p world command > ~/command_backup.sql
mysql -u root -p -e "UPDATE world.command SET security = 3 WHERE security > 3;"
```

GM levels are read when the account logs in, so log out to the login screen after changing them.

If `worldserver` stops with `Correct *.map files not found`, `DataDir` doesn't point at the folder
from step 6 (it must contain `dbc`, `maps`, `vmaps` and `mmaps`).

## 9. Client

Set `realmlist.wtf` in the client's `Data/enUS` (or your locale) folder to
`set realmlist 192.168.x.x`. A 5.4.8 client needs a connection-patched `Wow.exe` to connect to a
private server; the upstream README links one ("Client exe files"). It's an executable from a file
share, so scan it before running it.

## 10. Holiday dates (calendar and world events)

The shipped `holiday_dates` stop around 2019 (the Darkmoon Faire in 2023). Past that, the core
keeps the old start dates and repeats them every 360–362 days, so holidays drift weeks early,
appear twice in the in-game calendar, and the Darkmoon Faire vanishes. This affects when the
events actually run, not only the calendar.

`tools/pandaria/holiday_dates.py` writes fresh dates: fixed-date holidays repeat every year,
Easter / Lunar New Year / Thanksgiving based ones get 26 years of dates, and the Darkmoon Faire
gets the first Sunday of each month for about two years. Re-run it before the date the script
prints for the Darkmoon Faire (`re-run before YYYY-MM`); everything else lasts until 2050 or
indefinitely. The server reads these dates at startup, which the daily restart (section 8) takes
care of.

```sh
cd ~/pandaria/tools-repo
python3 tools/pandaria/holiday_dates.py ~/pandaria/server/data/dbc/Holidays.dbc > ~/holiday_dates.sql
mysqldump -u root -p world holiday_dates > ~/holiday_dates_backup.sql
mysql -u root -p world < ~/holiday_dates.sql
```

Restart `worldserver`, then log out and back in so the client requests a new calendar.

The calendar also needs the `CalendarHandler.cpp` fix from the patch in step 3. If your source tree
already has the earlier fixes, apply just that file and rebuild (only one file recompiles):

```sh
cd ~/pandaria/source
git apply ../tools-repo/tools/pandaria/calendar-fix.patch
cd build && make -j"$(nproc)" install
```

## 11. Solocraft for solo dungeon runs (optional)

The core ships Solocraft (`src/server/scripts/Custom/solocraft_system.cpp`), switched on in
`worldserver.conf.dist`. When you enter a dungeon or raid, it adds a flat bonus to all five of
your stats. It has no setting for mob damage or gold, and the bonus includes Stamina, so your
health pool balloons and you spend ages eating between pulls.

What the stock settings do:

| Setting | Effect |
|---|---|
| `Solocraft.Dungeon`, `.Heroic`, `.Raid25`, `.Raid40` | Default difficulty offset per instance type. |
| `Solocraft.<Dungeon>` / `Solocraft.<Dungeon>H` | Per-dungeon offset for normal / heroic, e.g. `Solocraft.DeadMines`, `Solocraft.DeadMinesH`. |
| `SoloCraft.Stats.Mult` | Stat bonus = offset × this, added to Str, Agi, Sta, Int and Spi. |
| `SoloCraft.Spellpower.Mult` | Mana users also get level × this × offset spell power. |
| `SoloCraft.Attackpower.Mult` | Not read by the code; does nothing. |
| `SoloCraft.<Class>` (0–100) | Only used when you join a group whose members already carry the full buff: it sizes your reduced share. Does nothing solo; values over 100 count as 100. |
| `Solocraft.<Dungeon>.Level`, `Solocraft.Max.Level.Diff` | No buff once your level is above dungeon level + diff. |

`tools/pandaria/solocraft-solo-tuning.patch` adds three settings and the two core hooks they need
(a DoT/leech tick hook call and a creature gold hook):

| Setting | Default | Effect |
|---|---|---|
| `SoloCraft.Stats.Stamina` | `1` | `0` leaves Stamina out of the stat bonus, so your health stays normal. |
| `SoloCraft.DamageTaken.Pct` | `100` | Percent of normal damage NPCs deal to you and your pets (melee, spells, DoTs) inside Solocraft instances. |
| `SoloCraft.Money.Pct` | `100` | Percent of normal gold creatures drop inside Solocraft instances. Quest, vendor and open-world gold are untouched. |

Both percentages apply in full to a solo player and rise in a straight line to 100 with a full
group (5 for a dungeon, 10 or 25 for a raid). They follow the same level cap as the stat buff. The
defaults change nothing, so applying the patch alone keeps stock behaviour.

```sh
cd ~/pandaria/source
git apply ../tools-repo/tools/pandaria/solocraft-solo-tuning.patch
cd build && make -j"$(nproc)" install
```

Then add the settings to your `worldserver.conf` (the patched `.dist` has them with comments), e.g.:

```ini
# +50 Str/Agi/Int/Spi in normal Deadmines, no extra Stamina
SoloCraft.Stats.Mult = 1
Solocraft.DeadMines = 50.0
SoloCraft.Stats.Stamina = 0
# a solo player takes 30% damage and gets 30% gold
SoloCraft.DamageTaken.Pct = 30
SoloCraft.Money.Pct = 30
```

Solocraft reads its settings only when `worldserver` starts, so `.reload config` doesn't change
them: restart the server, then leave and re-enter the instance.

## 12. DungeonScale: scale dungeon mobs to the group (optional)

`tools/pandaria/dungeon-scale.patch` adds a script that shrinks dungeon **creatures** to the number of
players inside, instead of inflating the player like Solocraft does. It is a port of `mod-dungeon-scale`
from the 548DS repo. Apply it **after** the Solocraft patch from section 11:

```sh
cd ~/pandaria/source
git apply ../tools-repo/tools/pandaria/dungeon-scale.patch
cd build && cmake . && make -j"$(nproc)" install
```

`cmake .` is needed because the patch adds new source files, and cmake only picks those up when it runs
(it reuses your existing options). This is a near-full rebuild, because the patch adds hooks to `ScriptMgr.h`.

What it does, with the defaults:

| Rule | Default |
|---|---|
| Health and damage multipliers per rank for a solo player, rising in a straight line to 1.0 at 5 players | trash 0.30 / 0.30, mini-boss 0.35 / 0.35, end boss 0.40 / 0.35 |
| Adds summoned by a boss use the boss's multipliers | on |
| When someone joins or leaves, only mobs **out of combat** are rescaled; mobs in a fight keep their values | always |
| No single hit or DoT tick from a scaled mob takes more than this share of your max health (only while the group isn't full) | `DungeonScale.HitCap.Pct = 35` |
| Honor per kill: Normal / Elite / MiniBoss / EndBoss, for every group member in range | 1 / 5 / 10 / 25 |
| Scaled content | 5-man dungeons only; raids, scenarios and Challenge Modes off |

The settings are at the end of the patched `worldserver.conf.dist`. Copy the `DUNGEON SCALE` block into
your `worldserver.conf`. Unlike Solocraft, `.reload config` picks up changes (mobs out of combat are
rescaled within a second). Without `DungeonScale.Enable = 1` in your config the script does nothing.

Turn Solocraft's own scaling off so mobs aren't scaled twice, and keep only its gold penalty:

```ini
SoloCraft.Stats.Mult = 0
SoloCraft.Spellpower.Mult = 0
SoloCraft.Stats.Stamina = 0
SoloCraft.DamageTaken.Pct = 100
SoloCraft.Money.Pct = 30
```

- `Stats.Mult = 0` and `Spellpower.Mult = 0` remove the player buff completely.
- `Stats.Stamina` does nothing while `Stats.Mult` is 0. Setting it to 0 keeps Stamina out if the buff is ever turned back on.
- `DamageTaken.Pct = 100` leaves mob damage to DungeonScale. Anything lower would cut it a second time.
- `Money.Pct` is the gold penalty, so pick whatever you like.
- Leave the `Solocraft.<Dungeon>` difficulty offsets alone, because with the multipliers at 0 they scale nothing.

Remember that Solocraft reads these only when `worldserver` starts, so restart after you change them.

GM commands (GM level 1 and up):
- `.dungeonscale info`: player count the instance is scaled for, and each rank's multipliers.
- `.dungeonscale creature`: rank, multipliers and current health of the selected mob.

Per-dungeon tuning goes in `DungeonScale.Map.<mapId>.*` keys (e.g. `DungeonScale.Map.36.Damage = 0.25`
for Deadmines), and `DungeonScale.RankOverride` fixes a mob the database ranks wrong. The combat log
shows a capped hit's original number; your health bar shows the capped one.

## 13. Level-appropriate pickpocket loot in revamped dungeons

Deadmines, Shadowfang Keep, Scarlet Halls, Scarlet Monastery and Scholomance use one creature entry for
normal and heroic; `creature_difficulty` only swaps level and stats. Their pickpocket tables were recorded
in heroic and drop in every difficulty, so a level 14 Kobold Digger gives a Rogue's Draught (requires
level 80) and a Flame-Scarred Junkbox (Lockpicking 400). The stock core also rolls pickpocket loot without
the dungeon difficulty, so loot rows tagged per difficulty would never drop.

Two parts, both needed:

```sh
cd ~/pandaria/source
git apply ../tools-repo/tools/pandaria/pickpocket-difficulty.patch
cd build && make -j"$(nproc)" install

mysqldump -u root -p world pickpocketing_loot_template creature_loot_template > ~/pickpocket_backup.sql
mysql -u root -p world < ~/pandaria/tools-repo/tools/pandaria/sql/2026_10_01_normal_dungeon_pickpocket_loot.sql
```

Then restart `worldserver`.

- The patch changes one line in `Player::SendLoot` (`Player.cpp`): pickpocketing passes the map difficulty
  to the loot roll, like corpse loot already does. Rows tagged `''`, which is every stock pickpocket row,
  drop exactly as before. Only `Player.cpp` recompiles.
- The SQL tags level 80-90 pickpocket items (junkboxes, Rogue's Draught, level 85 food, pricey grey junk) as
  heroic-only, and gives 27 mobs a normal-mode junkbox instead: Battered (22%) in Deadmines and Shadowfang
  Keep, Worn (18%) in the Scarlet dungeons, Sturdy (12%) in Scholomance. It also tags 78 level 80+ corpse
  drops in these dungeons (e.g. Fungus Squeezings) as heroic-only.
- `2026_10_01_normal_dungeon_pickpocket_loot_revert.sql` restores every original row.
- Gold in these dungeons is heroic-level too (a Kobold Digger drops 76s 84c). It is left as is; use
  `SoloCraft.Money.Pct` (section 11) to cut it.

## 14. Per-vendor item prices (optional, for the NPC Designer)

The stock core sells every item at its own `BuyPrice` from `Item-sparse.db2`, so two vendors can't sell
the same item at different prices. This adds `npc_vendor.OverrideGoldCost`, the column later
TrinityCore cores (and the BFA core) use for that: `-1` keeps the item's price, `0` or more is the price
in copper for one purchase at that vendor. The
[NPC Designer](https://github.com/xxciv/zrbfacore/tree/main/tools/npc-designer) writes it.

```sh
cd ~/pandaria/source
git apply ../tools-repo/tools/pandaria/vendor-price.patch
cd build && make -j"$(nproc)" install

mysql -u root -p world < ~/pandaria/tools-repo/tools/pandaria/sql/2026_10_12_vendor_price_column.sql
```

Then restart `worldserver`.

- Patch the core and add the column together: the patched core reads `OverrideGoldCost` at startup, and
  without the column the vendor query fails and every vendor in the world is empty.
- Existing vendor rows get `-1`, so nothing changes until a row sets a price.
- The price shows in the merchant window and is what the purchase costs; reputation discounts still apply.
- `Creature.h` changes, so most of the `game` library recompiles.
