# Changelog

## 0.13.0
- A listed item dropping gets a banner above the middle of the screen (icon, name, the list that wants it and its slot), a sound and a chat line. It fires for an item in a loot window you open and for a roll starting.
- One alert per drop: opening the same corpse again stays quiet, and so does the roll popup that follows the loot window.
- A chat line says who it was when someone else picks up an item on your list.
- It covers every list on the character you're on, both specs, and only items you don't have yet.
- Three new settings, all on: the banner, the sound, the chat lines. `/gl test` and a button in the settings window show the alert for the first missing item on your list.
- Looting an item straight after its drop line no longer adds the "is on your list" line a second later.

## 0.12.0
- Dual spec. On a character with two specs the window has a button for each, named after its biggest talent tree (Restoration, Feral Combat). Tie a list to each spec and click a button to look at that spec's list; right-click a button to change which list it uses.
- Switching spec in game switches the window to that spec's list, and so does logging in.
- The import window has a Spec choice. It picks the spec from the export's names ("resto", "Restoration EP") when that spec has no list yet. Replacing a list keeps its spec.
- Fix: the list name and character you picked in the import window were put back to the export's own when you clicked Import.

## 0.11.1
- The Cost column puts the amount first and what it is after it: "45g (Materials)" for crafted gear and "45g (Auction)" for auction prices, in place of "mats 45g" and "AH 45g". The tooltips match.
- The Cost column is a little wider so the longer text fits.

## 0.11.0
- Rows you can get where you're standing are washed blue with a blue edge: every missing item that drops in the dungeon you're in, or is a reward from a quest there. Outside dungeons the same goes for the zone you're in, so a vendor's rows light up when you're in its zone. The window's title says how many, e.g. "3 items to get in Stratholme".
- The Dungeons tab marks the dungeon you're in ("you are here") and washes its rows blue too.
- It follows you as you zone. Every wing of a dungeon lights up while you're inside, since the game doesn't say which wing it is. Only on your own character's list.

## 0.10.2
- Gold, silver and copper show as coin icons after the number, the way vendors show prices, in place of the letters g, s and c.

## 0.10.1
- The addon has its own icon file now (the parchment note it already used), so the DrangedAddons manager can show it.

## 0.10.0
- Right-click a column's name for its filter menu. Slot: armor, jewellery, weapons. Item: still to get, have it. Source: each kind of source the list has. Details: each place (dungeon or zone). Cost: anything with a cost, each currency or token, gold. Reputation: anything needing one, each faction. Enchant: still to do, done, none listed.
- Filters on different columns combine. A tick beside a column's name shows it's filtered, and every menu has "Clear every filter" while one is set. Filters aren't saved, so the list is whole again after a reload.
- Column names have a tooltip saying what a click and a right-click do.

## 0.9.0
- The source icon has its own **Source** column, and the text beside it is now **Details**.
- Click a column's name to sort the list by it; click it again to reverse. An arrow marks the sorted column. Source groups drops, then quests, vendors, crafted and bought. Cost puts currencies first (by name), then token items, then gold, dearest on top. Rows with nothing in the sorted column, such as items you already have, stay at the bottom either way.
- **Slot** always puts the character-sheet order back. The sort is remembered.

## 0.8.0
- A small icon left of each source says what kind it is: a skull for a boss or creature, the yellow quest mark for a quest, a vendor bag for a vendor, the currency's own icon for a currency vendor, the profession's icon for crafted gear, a chest for a chest, a bag for a world drop, a gold coin for a bind-on-equip item you'd buy.
- With the icon there, a quest's source is just the quest's name, and a vendor's is its zone and name without "Vendor:". The row's tooltip still has the zone and the full wording.

## 0.7.0
- Quest rewards now say which quest. Sources are filled in from Questie's database wherever DungeonJournal has nothing: the quest that rewards the item with its zone (`Western Plaguelands, Quest: In Dreams`), the boss, creature or chest that drops it outside the journal's dungeons, `World drop` for items that drop from many creatures, and the vendor on your side for sold items whose price isn't known yet.
- Only your faction's quests are listed. A quest or drop DungeonJournal already names isn't repeated.
- Needs Questie, which is optional like the other sources.

## 0.6.2
- A currency vendor's source is just the currency: `Tarnished Real vendor`, `Honor vendor`, `Darkmoon vendor`. The seller's name and zone are still in the row's tooltip. Vendors that take gold or token items keep their zone and name.

## 0.6.1
- Sources name the place first, then who: `Stratholme, Ramstein the Gorger`, `Stratholme, Quest: ...`, `Vendor: Stranglethorn Vale, Pix Xizzix`.

## 0.6.0
- The built-in vendor price table now covers every weapon and armor piece of uncommon quality or better that Wowhead lists as sold by a vendor: 2,029 items, up from 344. That adds gear sold for gold alone (1,433 pieces, PvP rank gear and reputation quartermasters among them), gear bought with token items alone (252), and the honor gear the 300-row currency list had cut off.
- 31 sellers are named, with their zone; the rest show the price without a seller.
- The inputs are in `tools/vendors/` (`gear.txt` plus the currency lists) and every line of `gear.txt` carries a count and checksums that `build.py` verifies.
- Not in the table: common (white) and poor (grey) vendor gear. Those still get their price the first time a character opens the vendor.

## 0.5.0
- Vendor prices no longer wait for you to visit the vendor. A built-in table has the price of every piece of gear Wowhead lists as bought with a currency: Tarnished Undermine Reals (37 items, with the vendor and zone), Honor Points with the marks each piece also takes (300 items), Darkmoon Prize Tickets (5) and Merchant's Favor (2).
- The table is keyed by item, so it applies to any list on any character, old or newly imported.
- A price read off a merchant window still wins over the table and still covers what the table doesn't have: gear sold for gold alone or for token items alone, and anything added to the game after the table was built. Those are remembered for the whole account the first time any character opens the vendor.
- `tools/vendors/build.py` rebuilds the table from the saved lists in `tools/vendors/`.

## 0.4.1
- Rows are tinted once you have them: a faint green behind the item half when the item is found, and behind the enchant half when the enchant is on, so a finished row is green right across. A hand tick tints gold instead.

## 0.4.0
- The summary box (Goals / Where to get it) is gone. The window is the list again, about 100 px shorter.
- New **Dungeons** tab beside **Gear** that swaps the whole view: the missing items by dungeon, the dungeon with the most wanted items first, and under each its bosses in the dungeon's own order with the item each one drops. Quest rewards come after the bosses. Hover an item for its tooltip; Shift-click links it.
- Dungeon data comes from the DungeonJournal addon; without it the tab says so.

## 0.3.0
- Two new columns in the list. **Cost**: token and currency amounts with their icons (red while you're short, green once you have enough) and vendor gold; for an item you'd make or buy, the cheaper of `mats` (crafting materials) and `AH` (auction price). **Reputation**: the faction and standing the item needs, red until you have it.
- The Source column now only says where an item comes from: boss and dungeon, quest, vendor and zone, profession and skill, BoE.
- Column names above the list. The window is 160 px wider to fit the new columns.

## 0.2.1
- Shorter source text: a boss and dungeon no longer says "Drop:", a profession and skill no longer says "Craft:" (or "Cast:" for enchants), and a vendor's token cost no longer says "Vendor:". Quests keep "Quest:", and a vendor price in gold alone keeps "Vendor:" so it isn't read as an auction price.

## 0.2.0
- The list is one line per slot now: slot, item, where it is (or how to get it while it's missing), enchant. All 17 slots fit without scrolling and the window is about 100 px shorter and 30 px narrower.
- New summary box above the list with two tabs.
  - **Goals**: what the list still asks of you, each with a tick and a progress bar. Gear and enchants done, gold needed against what you carry (vendor prices, plus the cheaper of crafting materials or the auction price for each item, plus enchant materials), every vendor currency and token against what you have (Tarnished Undermine Reals, PvP marks and the like), reputations with your standing and how far to the one required, profession skill, and whether each pattern is learned. Hover a line for the items behind it.
  - **Where to get it**: the missing items grouped by dungeon (with the boss or quest), vendor, profession, or the auction house.
- Skill and recipe goals show for professions the character has. Whether a pattern is learned comes from CraftRoute, which knows once that profession's window has been open.
- Another character's list says in the window title when it was last checked.
- "Show finished slots" is in the settings window only; a Settings button sits beside Import and Delete.

## 0.1.0
- First version. Paste a gear set's Export text from sixtyupgrades.com/forever (`/gearlist import`), pick the character it's for and get a checklist: one row per slot with the item and its enchant.
- Items tick themselves off when the character wears them, carries them or has them in the bank. Enchants tick off when the right one is on the item. Right-click a row to tick it by hand; items ticked as acquired on the site come in ticked.
- Lists are kept for the whole account, filed by character, several per character. You can import for a character you aren't on, including one the addon hasn't seen yet. Other characters' lists show what was found the last time you were on them.
- Each missing item shows how to get it: vendor cost in gold, currencies and token items (written down when you open the vendor) with how many you have, the recipe and priced materials for crafted items (CraftRoute + Auctionator), dungeon drops and quest rewards (DungeonJournal), the auction price for bind-on-equip items, and reputation or profession requirements in red while you don't meet them. Enchants show their recipe's materials.
- The window totals what vendors still want for the missing items.
- Item tooltips anywhere say when the item is on one of your lists. A chat line says when a listed item or enchant turns up.
- `/gl` opens the list (`/gearlist` and `/glist` too); `/gl import` and `/gl config` work the same.
- Settings window (`/gearlist config`), minimap button, Options > AddOns page, addon compartment entry.
