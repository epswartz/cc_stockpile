# Stockpile Specification (SPEC.md)

Stockpile is an automated restocking program for **CC:Tweaked** and **Advanced Peripherals** that monitors a player's inventory and automatically replenishes specified items from a dedicated supply chest.

---

## 🏗️ Hardware & Peripheral Setup

The program is designed to be highly decoupled, allowing flexible physical placement:

1. **Computer**:
   * An **Advanced Computer** (or standard computer) running CraftOS.
2. **Inventory Manager**:
   * Must be connected to the computer (directly adjacent or via a wired modem network).
   * A **Memory Card** bound to the target player must be inserted into the Inventory Manager.
3. **Chat Box**:
   * Connected to the computer network to listen to chat events.
4. **Supply Chest**:
   * Must be placed **directly on top** of the Inventory Manager (representing the `"up"` direction relative to the Inventory Manager block).
   * It does **not** need to touch the computer directly, and the computer does not perform direct inventory checks on the chest.
5. **Monitor (Optional)**:
   * Any size **Monitor** (such as a 2x3 or 3x2 block setup) placed adjacent to the computer or on the network.
   * If detected, the system automatically projects a visual dashboard displaying all player requests with color-coded operations and high-density text scales.

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
   * **Feedback**: Notifies the player in chat when their stock request is registered or updated.

2. `unstock`
   * **Behavior**: Deletes the restocking entry (`"type": "stock"`) for the item currently held in the player's main hand.
   * **Persistence**: Removes the matching request from `stockpile_requests.json` immediately.
   * **Feedback**: Notifies the player in chat upon successful removal.

3. `pile [optional preserve_count]`
   * **Behavior**: Marks the item currently held in the player's main hand for automatic inventory depletion (items are pulled from the player's inventory and placed into the supply/disposal chest).
   * **Preserve Count**: If specified, the system will pull all excess items of this type from the player's inventory, leaving exactly `preserve_count` items behind. If omitted, it defaults to leaving exactly `64` items (one full stack).
   * **Persistence**: Writes the depletion request immediately to `stockpile_requests.json` with `"type": "pile"`.
   * **Feedback**: Notifies the player in chat when their depletion request is registered or updated.

4. `unpile`
   * **Behavior**: Deletes the depletion entry (`"type": "pile"`) for the item currently held in the player's main hand.
   * **Persistence**: Removes the matching request from `stockpile_requests.json` immediately.
   * **Feedback**: Notifies the player in chat upon successful removal.

5. `stockpile reset`
   * **Behavior**: Wipes all registered requests (`stock` and `pile` types) for the executing player.
   * **Persistence**: Deletes all entries with `player == <username>` from `stockpile_requests.json`.
   * **Feedback**: Sends a private message to the player confirming how many entries were successfully wiped.

> [!IMPORTANT]
> **Stock & Pile Mutual Exclusion Rule**
> To prevent logical item loops (such as trying to restock and deplete the same item on the same player), players are strictly prohibited from having both a `stock` and a `pile` entry for the same item at the same time:
> * If a player has an active `pile` entry and tries to `stock` that item, the system rejects it and broadcasts to the entire server: `"<player> is trying to stock and pile <item> at the same time, but you can't do that, they need to unpile <item> first. DINGUS DETECTED!"`
> * If a player has an active `stock` entry and tries to `pile` that item, the system rejects it and broadcasts to the entire server: `"<player> is trying to stock and pile <item> at the same time, but you can't do that, they need to unstock <item> first. DINGUS DETECTED!"`
> * To switch modes, a player must first `unstock` or `unpile` the held item.

---

## ⚙️ Periodic Restocking Thread

In a parallel thread, every **2 seconds**, Stockpile executes the restocking routine:

1. **Load Requests**: Reads through `stockpile_requests.json`.
2. **Player Grouping**: Groups requests by player to scan each player's inventory exactly once per loop cycle via `manager.getItems()`, maximizing performance.
3. **Count and Compare**: For each requested item, it sums the current counts in the player's inventory.
4. **Replenish & Slot Matching**:
   * If the current count is less than the requested target, it calculates the missing amount (`needed`).
   * **Slot Preservation**: It scans the player's inventory to check if they already have the item in any slot.
     * If they do, it targets that **exact same slot** by passing `toSlot` in the transfer payload (prioritizing slots that are not fully stacked yet).
     * If they do not, it leaves `toSlot` empty, allowing the Inventory Manager to place it in the first available slot.
   * It attempts to transfer the items directly from the supply chest on top of the Inventory Manager using `addItemToPlayer("up", transfer_payload)`.
   * Displays log reports to `stdout` upon a successful transfer, including which slot was restocked into (e.g. `[INFO] Restocked 16x Cobblestone to player Dev (into slot 4)`).

### ⚖️ Depletion System
The periodic background thread handles `pile` requests concurrently alongside restocking:
1. **Load Depletion Requests**: Reads from the unified `stockpile_requests.json` list, identifying entries with `"type": "pile"`.
2. **Scan and Calculate Excess**: Checks each player's inventory to see if they possess more than the specified `target_count` of the marked item.
3. **Deplete (Pull)**:
   * Calculate the excess count (`excess = current_count - target_count`).
   * If `excess > 0`, use the Inventory Manager's `removeItemFromPlayer` to pull items from the player's inventory and transfer them into the chest on the `"up"` side.
   * Gracefully handles error cases where the supply/disposal chest is completely full.

---

## ⚠️ Robust Error Handling & Startup Enforcement

### 1. Startup Peripheral Enforcement (Strict Crash)
To ensure the system works reliably, all necessary peripherals (the **Chat Box** and at least one **Inventory Manager**) must be present on startup.
* **If any peripheral is missing**:
  * Stockpile logs a critical failure message to `stdout` / terminal.
  * If the **Chat Box** is available, it sends a public in-game warning: `"CRITICAL ERROR: Stockpile initialization failed: Missing Inventory Manager peripheral!"`
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
   * Listed with plain usernames in bright yellow (e.g., `Dev`, `Ethan`) with **no `@` prefix**.
3. **Request Rows**:
   * **Restocking (`[STCK]`)**: Displayed with a bright **blue prefix** (lightBlue), showing the target quantity and the item display name (e.g., `[STCK] 64x Cobblestone`).
   * **Depletion (`[PILE]`)**: Displayed with a bright **orange prefix**, showing the preservation limit and the item display name (e.g., `[PILE] 64x Oak Wood`).
4. **Auto-Truncation**:
   * Rows are dynamically truncated with an ellipsis (`...`) if the player name or item display name exceeds the horizontal borders of the monitor.
