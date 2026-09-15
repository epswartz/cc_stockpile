# Stockpile Specification (SPEC.md)

Stockpile is an automated restocking program for **CC:Tweaked** and **Advanced Peripherals** that monitors a player's inventory and automatically replenishes specified items from a dedicated supply chest.

---

## 🏗️ Hardware & Peripheral Setup

The program is designed around an Applied Energistics 2 ME system with a central ME Bridge and per-player staging chests:

1. **Computer**:
   * An **Advanced Computer** (or standard computer) running CraftOS.
2. **Inventory Manager**:
   * One per player. Must be connected to the computer network via a wired modem.
   * A **Memory Card** bound to the target player must be inserted into the Inventory Manager.
3. **ME Bridge**:
   * Connected to the computer network. Used to selectively export items to and import items from each player's staging chest.
4. **Chat Box**:
   * Connected to the computer network to listen to chat events.
5. **Staging Chest**:
   * One per player/Inventory Manager. Must be placed **directly on top** of the Inventory Manager (representing the `"up"` direction relative to the Inventory Manager block).
   * Each staging chest must be connected to the computer network via a **Wired Modem** to allow the central ME Bridge to identify it and target it by its peripheral name (e.g. `minecraft:chest_0`).
6. **Monitor (Optional)**:
   * Any size **Monitor** (such as a 2x3 or 3x2 block setup) placed adjacent to the computer or on the network.
   * If detected, the system automatically projects a visual dashboard displaying all player requests with color-coded operations and high-density text scales.


---

## 🛠️ Staging Chest Configuration Tool (`stockpilecfg`)

The mapping of player names to their dedicated staging chest peripheral names is managed via the **`stockpilecfg`** command-line program and persisted in **`stockpile_chests.json`**:

* **Auto-creation**: If `stockpile_chests.json` does not exist when `stockpile.lua` is started, it will be automatically created containing an empty JSON object `{}`.
* **Map Command**:
  ```bash
  stockpilecfg map <player> <chest peripheral>
  ```
  * Example: `stockpilecfg map Dev minecraft:chest_0`
  * Registers/updates the player's mapping in `stockpile_chests.json`.
  * **Dynamic Reloading**: The background thread in `stockpile.lua` reads the configuration file dynamically on every loop iteration, meaning any updates made via `stockpilecfg` are applied **instantly** without requiring a program restart!

---


## 🚀 Startup & Execution

Stockpile is executed automatically on computer boot via **`startup.lua`**:
* On Advanced Computers, it detects the **`multishell`** API and uses `shell.openTab("stockpile.lua")` to run the program in a background shell tab, leaving the main console terminal fully accessible to the player.
* On basic computers, it falls back to standard foreground execution.

## 💬 Chat Commands & Database Rules

Stockpile listens to the public in-game chat using the Chat Box peripheral. Commands are parsed and processed on a per-player basis:

1. `stock [optional count]`
   * **Behavior**: Marks the item currently held in the player's main hand for restocking.
   * **Count**: If specified, stocks up to that number. If omitted, defaults to the item's maximum stack size (typically 64).
   * **Persistence**: Writes the request immediately to `stockpile_requests.json` with `"type": "stock"`.
   * **Feedback**: Sends a toast notification (`sendToastToPlayer`) to the player when their stock request is registered or updated.

2. `unstock`
   * **Behavior**: Deletes the restocking entry (`"type": "stock"`) for the item currently held in the player's main hand.
   * **Persistence**: Removes the matching request from `stockpile_requests.json` immediately.
   * **Feedback**: Sends a toast notification (`sendToastToPlayer`) to the player upon successful removal.

3. `pile [optional preserve_count]`
   * **Behavior**: Marks the item currently held in the player's main hand for automatic inventory depletion (items are pulled from the player's inventory and placed into the supply/disposal chest).
   * **Preserve Count**: If specified, the system will pull all excess items of this type from the player's inventory, leaving exactly `preserve_count` items behind. If omitted, it defaults to leaving exactly `64` items (one full stack).
   * **Persistence**: Writes the depletion request immediately to `stockpile_requests.json` with `"type": "pile"`.
   * **Feedback**: Sends a toast notification (`sendToastToPlayer`) to the player when their depletion request is registered or updated.

4. `unpile`
   * **Behavior**: Deletes the depletion entry (`"type": "pile"`) for the item currently held in the player's main hand.
   * **Persistence**: Removes the matching request from `stockpile_requests.json` immediately.
   * **Feedback**: Sends a toast notification (`sendToastToPlayer`) to the player upon successful removal.

5. `stockpile reset`
   * **Behavior**: Wipes all registered requests (`stock` and `pile` types) for the executing player.
   * **Persistence**: Deletes all entries with `player == <username>` from `stockpile_requests.json`.
   * **Feedback**: Sends a toast notification (`sendToastToPlayer`) to the player confirming how many entries were successfully wiped.

> [!IMPORTANT]
> **Stock & Pile Mutual Exclusion Rule (with "Keep at Exactly X" Exception)**
> To prevent logical item loops, players are prohibited from having both a `stock` and a `pile` entry for the same item at the same time, unless both entries target the **exact same quantity** (e.g. to keep the inventory at exactly X):
> * If a player has an active `pile` entry with a different quantity and tries to `stock` that item, the system rejects it and broadcasts to the entire server: `"<player> is trying to stock and pile <item> at different quantities (<stock_count> vs <pile_count>), but you can't do that, they must be the same quantity to keep at exactly <stock_count>. DINGUS DETECTED!"`
> * If a player has an active `stock` entry with a different quantity and tries to `pile` that item, the system rejects it and broadcasts to the entire server: `"<player> is trying to stock and pile <item> at different quantities (<stock_count> vs <pile_count>), but you can't do that, they must be the same quantity to keep at exactly <pile_count>. DINGUS DETECTED!"`
> * If the quantities are the same, both requests are registered and co-exist to keep the player's inventory at exactly that target quantity.
> * To switch/change a single mode to a different quantity, a player must first `unstock` or `unpile` the held item or ensure both commands specify matching quantities.

---

## ⚙️ Periodic Restocking Thread

In a parallel thread, every **2 seconds**, Stockpile executes the restocking routine:

1. **Load Requests**: Reads through `stockpile_requests.json`.
2. **Player Grouping**: Groups requests by player to scan each player's inventory exactly once per loop cycle via `manager.getItems()`, maximizing performance.
3. **Player Mapping & Validation**: Checks if the player is configured in the `PLAYER_CHEST_MAP`. If not, skips processing and logs a warning.
4. **Count and Compare**: For each requested item, it sums the current counts in the player's inventory.
5. **Replenish & Slot Matching**:
   * If the current count is less than the requested target, it calculates the missing amount (`needed`).
   * **ME Export**: Triggers the ME Bridge to export `needed` count of the requested item from the AE2 system directly into the player's mapped staging chest.
   * **Slot Preservation**: It scans the player's inventory to check if they already have the item in any slot.
     * If they do, it targets that **exact same slot** by passing `toSlot` in the transfer payload (prioritizing slots that are not fully stacked yet).
     * If they do not, it leaves `toSlot` empty, allowing the Inventory Manager to place it in the first available slot.
   * It attempts to transfer the items directly from the staging chest on top of the Inventory Manager using `addItemToPlayer("up", transfer_payload)`.
   * **ME Clean-up / Sweep**: Immediately instructs the ME Bridge to import any leftovers in the player's staging chest back into the AE2 network.
   * Displays log reports to `stdout` upon a successful transfer, including which slot was restocked into (e.g. `[INFO] Restocked 16x Cobblestone to player Dev (into slot 4)`).

### ⚖️ Depletion System
The periodic background thread handles `pile` requests concurrently alongside restocking:
1. **Load Depletion Requests**: Reads from the unified `stockpile_requests.json` list, identifying entries with `"type": "pile"`.
2. **Scan and Calculate Excess**: Checks each player's inventory to see if they possess more than the specified `target_count` of the marked item.
3. **Deplete (Pull)**:
   * Calculate the excess count (`excess = current_count - target_count`).
   * If `excess > 0`, prioritize pulling items from slots **outside the player's hotbar** (non-hotbar slots, e.g. slot >= 10).
   * Only pull from the player's hotbar slots (slots 1 to 9) if there are no other slots containing the item or if further depletion is still required to satisfy the `target_count`.
   * Use the Inventory Manager's `removeItemFromPlayer` with `fromSlot` to pull items from specific slots and transfer them into the chest on the `"up"` side.
    * **ME Import**: Triggers the ME Bridge to import all pulled excess items from the player's staging chest back into the AE2 network.
    * Gracefully handles error cases where the staging chest or AE2 system is full.

### 🧹 Global Sweep Routine
At the very end of each 2-second tick cycle (after all individual player restocking and depletion requests have been fully processed), a **Global Sweep** is performed:
* The system iterates through every registered staging chest in `PLAYER_CHEST_MAP`.
* It calls `me.importItem` on each chest to pull any residual items (due to disconnected players, inventory full edge-cases, or manually dropped items) back into the AE2 network.
* This guarantees that all staging chests return to a pristine zero-state between cycles.

---

## ⚠️ Robust Error Handling & Startup Enforcement

### 1. Startup Peripheral Enforcement (Strict Crash)
To ensure the system works reliably, all necessary peripherals (the **Chat Box**, **ME Bridge**, and at least one **Inventory Manager**) must be present on startup.
* **If any peripheral is missing**:
  * Stockpile logs a critical failure message to `stdout` / terminal.
  * If the **Chat Box** is available, it sends a public in-game warning: `"CRITICAL ERROR: Stockpile initialization failed: Missing <Missing Peripherals>!"`
  * The program immediately exits and **crashes** using the native `error()` method.


### 2. Runtime Exception Handling (Never Crash)
Once initialized, Stockpile runs in a protected manner. The program will **never crash or halt** under normal gameplay exceptions. Instead, it logs errors/warnings gracefully to `stdout` only (without interrupting other threads or players) in scenarios such as:
* A player makes a request but has no item in hand.
* A player is offline or moves out of range.
* The Inventory Manager is missing a Memory Card or has an unbound card.
* The supply chest on top of the Inventory Manager is empty or does not contain the requested item (the `addItemToPlayer` method returns `0` items added).

---

## 🧩 Resolved Edge Cases

The codebase explicitly accounts for and resolves several complex edge/corner cases:

1. **The "Full Slot" Locking Case**:
   * *Problem*: If a player's first existing stack of an item becomes full (e.g. they have exactly 64 Cobblestone in Slot 5) and the system tries to restock another stack (e.g. up to 128 Cobblestone) into that exact slot, the transfer will fail with `0` items transferred, locking restocking entirely.
   * *Resolution*: Stockpile's slot scanner **only** passes `toSlot` if the identified slot has space left (`count < maxStackSize`). If all matching slots are full, `toSlot` is omitted, prompting the Inventory Manager to safely start stocking into a brand new empty slot.

2. **The "Accidental Chat Command" Case**:
   * *Problem*: If a player types a normal chat message starting with a command word (e.g., `"stock is running low"` or `"unstock this block please"`), the system could parse the message as an unintentional command.
   * *Resolution*: Stockpile strictly filters message word counts.
     * The `stock` command is **ignored** if the message has more than 2 words.
     * The `unstock` command is **ignored** if the message has more than 1 word.

3. **Multiple Inventory Managers**:
   * *Problem*: Multiple players might have active Memory Cards inserted on the same network.
   * *Resolution*: Stockpile scans all attached inventory manager peripherals and calls `getOwner()` on each, matching only the specific peripheral bound to the command-executing player. If multiple peripherals match the same player, the first detected manager is safely selected.

---

## 📺 Monitor Dashboard UI (Visual Interface)

When an adjacent monitor is connected to the computer network, Stockpile renders a real-time, color-coded visual dashboard that refreshes every **2 seconds**:

1. **Title Bar**:
   * Displayed with a solid **green background** (on advanced color monitors) featuring centered white text: `" MOBIUS STOCKPILE "`.
2. **Player Headers**:
   * Listed alphabetically with plain usernames in bright yellow (e.g., `Dev`, `Ethan`) with **no `@` prefix**.
   * If there are configuration or hardware issues for a player, a prominent alert string is rendered next to their name in bright red:
     * `(NO CHEST)`: The player is missing a mapped chest in `stockpile_chests.json`.
     * `(NO CARD)`: No connected Inventory Manager is currently found holding a bound Memory Card for the player.
     * If both are true, they are concatenated together side-by-side: `(NO CHEST) (NO CARD)`.
3. **Request Rows**:
   * **Restocking (`[STCK]`)**: Displayed with a bright **blue prefix** (lightBlue), showing the target quantity and the item display name (e.g., `[STCK] 64x Cobblestone`).
   * **Depletion (`[PILE]`)**: Displayed with a bright **orange prefix**, showing the preservation limit and the item display name (e.g., `[PILE] 64x Oak Wood`).
4. **Auto-Truncation**:
   * Rows are dynamically truncated with an ellipsis (`...`) if the player name or item display name exceeds the horizontal borders of the monitor.
