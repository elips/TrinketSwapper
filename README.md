# TrinketSwapper

A small addon for **WoW: Forever** that puts your two trinkets on screen as a pair of icons, with a menu for swapping them. Works for every class.

## What it does

- **Two icons**, one for each trinket slot, each showing its trinket and its cooldown. Click an icon to use that trinket, or give each a key (Key Bindings > TrinketSwapper).
- **A menu of the trinkets in your bags** opens when you put the mouse on either icon. Left-click one to wear it as your top trinket, right-click to wear it as your bottom trinket.
- **Swaps in combat are queued.** The game doesn't allow changing trinkets during a fight, so a click then queues the trinket for that slot. It shows small in the icon's corner and goes on the moment combat ends. Click it again to take it back.
- **Bag trinkets on cooldown stay showing** next to the icons, counting down, so you can see when one you swapped out is ready to go back on.
- **A minimap button**: click it for the settings, right-click it to move the trinket icons, drag it to move the button itself. It can be hidden.
- **"Swap"** shows on a worn trinket when swapping it costs nothing. Wearing a trinket starts a 30 second cooldown on it; once the one you're wearing has longer than that left on its own cooldown, and a bag trinket is ready, there's no reason not to swap.

## Commands

| Command | What it does |
| --- | --- |
| `/ts` | Opens the settings |
| `/ts move` | A blue box over the icons: drag it, then `/ts move` again |
| `/ts minimap` | Shows or hides the minimap button |
| `/ts reset` | Settings and position back to how they came |

## Settings

- Icon size.
- Whether the menu opens above or below the icons.
- The cooldown tray, the "Swap" label, the key shown on each icon and the minimap button can each be switched off.

## Good to know

- The icons can't be moved or resized during combat (a game rule for anything that uses an item when clicked). A change made mid-fight is applied when the fight ends.
- Where the game hides an item's cooldown in combat, the icon counts down from what it last read, or from the longest cooldown it has seen that trinket have.

## Install

On this page click **Code**, then **Download ZIP**, and open the ZIP. Inside its `TrinketSwapper-main` folder is a folder named `TrinketSwapper`: put that inner folder in `World of Warcraft\_forever_\Interface\AddOns\` and restart the game.
