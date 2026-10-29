# ChadcoreMenu

**by ChadBrowick**

The game's **main menu**, **Status** and **Equipment** windows, redrawn in the **YunaUI** style for
**CatsEyeXI** (VanaCore, the CatsEyeXI launcher's client). It's a companion to YunaUI and can also run on its own.

- **Commands**: the main menu as a dark violet panel with the AvantGarde-style font. A pink-to-violet band slides to
  the game's cursor, and a line under the list says what the selected command does.
- **Action menu**: the menu on a target in the same style: out of combat Attack, Magic, Abilities, Trust, Items,
  Check; in combat Switch Target, Magic, Abilities, Trust, Items, Disengage, Check. Its **Abilities** opens a combat
  menu (Job Abilities, Weapon Skills, Ranged Attack, Mount, Pet Commands): Ranged Attack fires, the others open
  that list; cancel steps back. It follows the game's cursor, so the controller works it as always; click a command to use it.
- **Storage picker**: the game's Inventory / Mog Wardrobe 1–8 picker in the same style, with how many items each bag has for the slot.
- **Swap menu**: next to the equipment panel. Pick a slot and it lists every piece from your Inventory and Mog
  Wardrobes 1–8 that fits it, best for your job first (greyed = not for your job or level). Tabs pick the bag
  (ALL, INV, W1–W8); it opens on the bag the piece you're wearing is in, with the cursor on it. Click (or confirm)
  a piece to equip it: ChadcoreMenu sends the game's own equip request (the same one gear-swap addons such as
  luashitacast use), straight from whichever bag the piece is in.
- **Status**: the Status submenu and its pages in one panel: Profile (jobs, race, nation, rank, title, experience,
  HP / MP, gil), Job levels, Combat skills, Magic skills, Crafting skills (with rank) and Merit points (merits,
  limit points, an **Earning** button at level 75+ that switches between experience and limit points, and a **Merit categories** button that opens the game's own merit screens to spend them). Skills at
  their cap are marked CAP.
- **Mog House storage**: picking a bag in the Mog House's storage menu (Mog Safe, Safe 2, Storage, Locker, Satchel, Sack, Case, Wardrobes) opens two windows like the game's: that bag on the left, your Inventory on the right. Confirm moves an item across (a stack asks how many: type it or use the d-pad), Left / Right switch sides, L1 / R1 change the bag on the left, X / Square sorts. Moves use the game's own move request, so the server checks them as usual.
- **The right bag**: Items opened from the game's item list opens on the bag that list shows (Inventory, a Mog Wardrobe, Satchel...) and follows it if it changes. In the equipment screen, a bag picked in the game's Storage picker is the bag the swap menu opens on (otherwise the worn piece's bag).
- **Trade (NPCs)**: the game's trade window is replaced by two windows: **Inventory** (your items) and **Trading** (what you're giving: up to 8 items, gil, and TRADE). Confirm on an item opens **How many?**: type the number, or Up / Down 1, Left / Right 10, L1 / R1 100, then OK / confirm (0 takes it back out). Right / Left switch between the two windows. In Trading, confirm on a piece changes its amount, on Gil sets the gil (type it, or Left / Right 100, L1 / R1 10,000), and on **TRADE** sends it all with the game's own NPC trade request and closes the window. Cancel (or the **Cancel** row, or right-click) backs out of the trade. Trades with players keep the game's own window. `/cmenu trade off` brings the game's window back for NPCs too.
- **Home Points / Survival Guides**: every place you've unlocked in one big list, in columns, so nothing scrolls or pages, with each place's fee and your gil. Confirm a place, then confirm again to go (Home Points also have "Set as your home point"). Left / Right move between columns. ChadcoreMenu answers the NPC the same way the game does when you pick a place, and the server checks it as usual. `/cmenu warp off` brings the game's menus back.
- **Check** (on another player): their name, jobs and job emblem, their 16 pieces of gear in the game's 4 x 4 layout (an item card for the piece under the cursor or mouse), their linkshell with its pearl in the linkshell's colour, and, when they have a bazaar, **View Wares** and their bazaar message. The d-pad moves over their gear (the item card follows); down past the last row is View Wares, which glows when they have a bazaar, and confirm opens it (the game's own button). Cancel closes the window. `/cmenu inspect off` brings the game's window back.
- **Bazaar** (View Wares): beside the Check panel, their wares with each item's icon, name, how many and price (per item for stacks; red when it costs more than you have), their bazaar message, your gil, and the item card (augments too) under the panel for the item under the cursor or mouse. Confirm on an item opens a how-many picker like the trade window's (type the number, or Up / Down 1, Left / Right 10, L1 / R1 100; it stops at the stock or what your gil covers) with the total, then BUY buys it (the server's own bazaar purchase; it checks the price, your gil and the stock as usual). Left / Right on the list moves a page. A click picks an item, a second click opens the picker, right-click backs out. NPC shops are left to the game. `/cmenu bazaar off` brings the game's window back.
- **Magic / Abilities / Items / Key Items**: ChadcoreMenu's own panels, built from your character's data.
  - **Magic**: the spells you can cast now, by type (White, Black, Summon, Ninja, Song, Blue, Geo, Trust), with MP and recast. Click to cast (enemy spells go on `<t>`, party spells open `<stpc>`).
  - **Blue Magic** (BLU main or sub): the spells you have set come first, since only they can be cast. Learned spells that aren't set are listed under them, dimmed. **Set Spells >** at the top opens the setter. Its **SET** tab shows your 20 slots (confirm a slot to unset it). Its **LEARNED** tab lists all your blue magic with set spells first (confirm to set a spell in the first empty slot, or to unset it). The header shows blue points used / max. Cancel goes back to the spell list. Spells are set through the game's own Set Spells function, the same way Ashita's blusets addon does it.
  - **Abilities**: job abilities, pet commands (blood pacts, Ready), weapon skills, and General: Ranged Attack, your mounts and Dismount. With recasts. Click to use.
  - **Items**: every bag in tabs (Inventory, Satchel, Sack, Case, Temporary, Wardrobes 1–8). Hover an item for its tooltip card; click it, then **USE**.
  - **Key Items**: all your key items, A–Z.
  - Mouse: click the command in the ChadcoreMenu main menu. Keyboard / pad: the game's own window opens as usual and the panel opens beside it (the first time, ChadcoreMenu learns which game window that is). `/cmenu status`, `/cmenu magic`, `/cmenu abilities`, `/cmenu items`, `/cmenu keyitems` open one directly, so you can bind them to keys.
- **Character panel**: replaces the Status and Equipment windows (only those two screens: elsewhere, like the Items menu, the game's own gil and item boxes stay and items show as tooltip cards). It has your job emblem, name and jobs, glowing
  HP / MP / TP bars, attributes with their gear bonuses, Attack / Defense, the eight resistances, and your 16 slots in
  the game's own order with HD icons, a wardrobe number and the ammo count. The selected slot glows, and an item card
  shows its name, Rare / Ex, slot, races, description, level and jobs.

## Moving and locking

Every ChadcoreMenu panel (the main menu, the equipment panel, the swap menu, Magic / Abilities / Items / Key Items
and the storage picker) can be dragged by its top. Each one remembers where you put it. The lock in a panel's
top-right corner locks them all in place (click it again to unlock). `/cmenu lock`, `/cmenu unlock`, and
`/cmenu resetpos` (every panel back in its own place) do the same from chat.

## Controller

ChadcoreMenu's own panels work with a controller the way the game's menus do:

- **Equipment**: move on the gear grid as usual. Press confirm on a slot and the swap list takes over: up / down
  moves, left / right (or L1 / R1) changes the bag, confirm equips the piece and puts you back on the grid, cancel
  goes back without changing anything.
- **Magic / Abilities / Items / Key Items**: open them from the game's menu with confirm. ChadcoreMenu's panel
  replaces the game's window: up / down moves, left / right or L1 / R1 changes tab, confirm uses it (Items: confirm
  picks, confirm again uses), cancel closes.
- While one of these panels has the controller, its buttons are kept from the game; the rest of your pad is untouched.
- Confirm and cancel are learned from how you use the game's own menus. `/cmenu pad` shows them, `/cmenu pad reset`
  forgets them, `/cmenu pad off` gives the controller back to the game's own lists.
- On the keyboard: arrow keys, Enter (confirm), Escape (cancel), Page Up / Page Down (tabs).

## How it works (and why it's safe)

The game's menus keep running underneath. Your keyboard, pad and macros drive them exactly as before. ChadcoreMenu only
stops their graphics from being drawn (the same "draw" switch YunaUI uses to hide the game's chat) and draws its own
panel in their place, reading the game's cursor every frame.

- **Mouse:** clicking a row or slot moves the game's own cursor there and presses OK through the game's own
  functions, so Equipment → slot opens the game's normal item list. **Right-click** = back, **wheel** = move the cursor.
- If anything goes wrong (a draw error, or a window it doesn't know), the game's own window comes straight back.
  Errors go to `chadcoremenu-errors.txt` in the addon folder.
- `/cmenu off` or unloading puts every game window back as it was.

## Install

1. Unzip into `VanaCore\addons\vanacore\` so you have `VanaCore\addons\vanacore\chadcoremenu\chadcoremenu.lua`.
2. In game: `/addon load chadcoremenu vanacore`. To load it every time, add that line to your startup script after YunaUI's.

## First run: check the window ids

The game names every window with a short id. ChadcoreMenu expects `menuwind` (main menu), `equip` (equipment) and
`statcom` / `status` (status). Open the main menu, then Equipment, and type:

```
/cmenu windows
```

That lists every open window and its id. If an id differs on CatsEyeXI, tell ChadcoreMenu:

| If… | Type |
| --- | --- |
| the main menu isn't replaced | `/cmenu mainid <id>` |
| the status box beside Equipment still shows | `/cmenu statusids <id>,<id>` |
| another box should go too (e.g. the item help line) | `/cmenu hide <id>` |
| a game window still draws over the panel | `/cmenu hidemode move` |
| the main menu highlight jumps around | `/cmenu learn`, then press **Down** from Status through every command until it's back on Status |
| the main menu names are wrong | `/cmenu labels Status,Equipment,Magic,...` |
| the game's menu still shows faintly behind | `/cmenu hidemode main move` (or `both`, the default) |
| anything else looks off | `/cmenu dump` writes `chadcoremenu-dump.txt`: send it over |

## Status

Status shows your character panel on the left and the Status list on the right (Profile, Job Levels, Master Levels,
Combat Skills, Magic Skills, Craft Skills, Currencies, Currencies 2, Unity, Play Time, Merit Points, Job Points) in the
game's order, following the game's own cursor. For Profile, Job Levels, the skills, crafts and Merit Points, a page beside
the list shows them in the new look (on Merit Points, click SWITCH to change between earning experience and limit points,
or OPEN for the merit categories). Currencies and Currencies 2 are new-style lists too: every currency and how many, read from the server's own currency data; highlight one for a preview, confirm to scroll through it with the controller. The other pages open the game's own screens. `/cmenu statcmd off` brings the game's
list back (and the older tabbed Status panel with it); `/cmenu status` still opens the tabbed panel.

## Moogle

In your Mog House, the Moogle's menu (Storage, Delivery Box, Change Jobs, Gardening, Layout, Open Mog, Remodel) is in the
new look with a line on what each does. Storage lists the bags with how full each is and opens the same two-window
transfer view as View House. Change Jobs shows Main Job / Support Job with what you are now, then every job with its
emblem and level (your main job in gold, your support job in blue, jobs not unlocked as ???). They all follow the game's own
cursor, so the controller works as always. The Delivery Box windows are still the game's. `/cmenu moogle off` brings
the game's menus back.

## Teleport map card

In the Home Point and Survival Guide menus, the place under the cursor (or the mouse) gets a map card beside the menu:
its zone's map, zoomed in round the spot, with a glowing pin where the Home Point or Survival Guide stands, and the fee.
When YunaUI is installed next to ChadcoreMenu (`addons\ashita\yunaui` or `addons\vanacore\yunaui`) and has a map for
that zone, the card uses YunaUI's dark maps (read from YunaUI's own folder, never copied); otherwise it uses the game's own
map from your game files. `/cmenu warpmap game` always uses the game's maps, `/cmenu warpmap whole` shows the whole map
instead of zooming in, and `/cmenu warpmap off` turns the card off. If a place shows no map, `/cmenu warpmap test` checks every place and writes what it found to `chadcoremenu-survey.txt`.

## Treasure

While anything is in the treasure pool, the action menu gets a Treasure command at the bottom, with the number of items. This works on yourself, on another player and on a monster or NPC. It opens a pool panel that lists each item with your lot, the top lot so far and the time left. Confirm (or LOT) lots, and Right, Square / X (or PASS) passes. These send the same lot and pass the game's own treasure window sends. `/cmenu treasure off` removes the command.

## Server NPC menus (EXP Guide (S) and the like)

Some CatsEyeXI NPCs, such as the EXP Guide (S), build their menu on the server. The game shows these menus in a small three-line box. ChadcoreMenu reads the menu as it arrives and shows every choice at once in the Home Point style: level ranges on the right, and a map card of the zone. For a place, confirm once to select it and again to go. Next Page, Exit and similar choices go straight away. The choice is made through the game's own box, so the game sends its usual answer. If that answer ever names a different choice than the one you picked, it is stopped and nothing is sent; talk to the NPC again. `/cmenu npcmenu off` leaves these menus to the game.

## Hiding the game's own menus

VanaCore's HUD Manager can leave out some of the game's windows (`<id>.hide=1` in VanaCore's settings: the main menu,
the action menu, Check, the Items list, item details, the storage list, the comment box, the EXP box...). Use it for those.
The lists the main menu opens in its place (Status, View House, Magic, Missions...) and the NPC menus have no switch there,
so ChadcoreMenu hides the ones it replaces itself, while its panel is up. For anything else you want gone for good,
`/cmenu hide <id>` keeps that game window hidden all the time (it still works underneath, so the controller works it);
`/cmenu hide` alone lists what's hidden and the game windows open right now, and `/cmenu unhide <id>` brings one back.

## Sorting

Magic, Abilities, Items (and the Mog House / usable lists), Key Items and the trade list have a **SORT** button by the page count: the game's order (castable / ready first), **A-Z**, or **LEVEL** (low to high: the level a spell needs on your jobs, an item's level). Click it, or press X (Xbox) / Square (PlayStation). Each menu remembers its own choice.

## Where the panels sit

Every panel can be dragged by its top while the menus are unlocked (the lock icon, or `/cmenu unlock`), and keeps its spot. Magic, Abilities, Items, Key Items and Status each keep their own spot, and separately for the main menu (Commands) and the action menu on a target, so Items from the main menu and Items from the action menu can sit in different places. Check, Bazaar, Trade and Chat have their own spots too. `/cmenu resetpos` puts every panel back in its own place.

## Commands

Every command works as `/cmenu ...` (also `/chadcore ...`).

| Command | What it does |
| --- | --- |
| `/cmenu` | Help |
| `/cmenu on` / `off` | ChadcoreMenu on, or the game's own menus back |
| `/cmenu main on/off`, `/cmenu char on/off` | Each panel on its own |
| `/cmenu clicks on/off`, `/cmenu wheel on/off` | Mouse control |
| `/cmenu lock` / `unlock` | Lock the panels, or let them be dragged by their tops |
| `/cmenu resetpos` | Every panel back in its own place |
| `/cmenu scale 1.1` | Size, 0.6 to 2 |
| `/cmenu anim on/off`, `/cmenu hint on/off` | Animations, and the command description |
| `/cmenu list on/off`, `/cmenu storage on/off` | The item list and storage picker on their own |
| `/cmenu survey on/off` | Record the game's windows to chadcoremenu-survey.txt |
| `/cmenu windows` | List the game windows open now |
| `/cmenu learn` / `learn reset` | Teach or forget the main menu's order |
| `/cmenu dump` | Write the open windows' buttons to a file |
| `/cmenu reset` | Back to defaults |

## Credits

- Home Point and Survival Guide positions (warp_pos.lua) from LandSandBoat's zone data (GPL-3.0). Reading the game's map table and map files after boussole by loonsies (github.com/loonsies/boussole). Dark maps, when used, are YunaUI's own files on your PC.
- Augment names: the lookup tables of Windower's extdata library (Windower Team), in `augments.lua`.

- Look, palette, font and job emblems from **YunaUI** by Yunas (GPL-3.0). The start-up file `native.lua` is YunaUI's.
- Menu structures (window list, cursor, button count, menu area) and the game's cursor / key functions are as
  documented by sruon's **Ashita4-MenuManager** (MIT).
- Hiding a game window with its draw byte follows UIBegone (DragoHorse) and atom0s's hideparty.
- Font: TeX Gyre Adventor (GUST Font License).

## Licence

GPL-3.0 (see `LICENSE`), like YunaUI, whose code it includes.
