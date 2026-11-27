# TrinketSwapper

A small addon for **WoW: Forever** that puts your two trinkets on screen as a pair of icons, with a menu for swapping them. Works for every class.

With ElipsUI installed and a class HUD (ArchDruid, WarLord) wearing a theme, the settings window wears it too: a soft glow of its color along the top, and its color on what's lit, selected or ticked in the settings. Without them, the bronze look.

## What it does

- **Two icons**, one for each trinket slot, each showing its trinket and its cooldown, in the look of your action buttons (the art is copied from them, so it matches). Click an icon to use that trinket, or give each a key (Key Bindings > TrinketSwapper).
- **The trinket's buff on its icon.** While the buff from using a trinket, or from its proc, is on you, the icon lights: the buff's icon in a green edge, with its time sweeping away. A proc trinket whose buff is known waits grey for it, and darker while a cooldown runs on it. It works in combat, because the game itself draws the buff.
- **A menu of the trinkets in your bags** opens when you put the mouse on either icon. Left-click one to wear it as your top trinket, right-click to wear it as your bottom trinket.
- **Swaps in combat are queued.** The game doesn't allow changing trinkets during a fight, so a click then queues the trinket for that slot. It shows small in the icon's corner and goes on the moment combat ends. Click it again to take it back.
- **Bag trinkets on cooldown stay showing** next to the icons, counting down, so you can see when one you swapped out is ready to go back on.
- **A minimap button**: click it for the settings, right-click it to move the trinket icons, drag it to move the button itself. It can be hidden.
- **"Swap"** shows on a worn trinket when swapping it costs nothing. Wearing a trinket starts a 30 second cooldown on it; once the one you're wearing has longer than that left on its own cooldown, and a bag trinket is ready, there's no reason not to swap. The trinket's icon with "Swap" under it also shows in the middle of the screen for 10 seconds, once per cooldown and out of combat (a trinket used in a fight gets it when the fight ends).

## Commands

| Command | What it does |
| --- | --- |
| `/ts` | Opens the settings |
| `/ts move` | Blue boxes over the icons and where the swap alert shows: drag them, then `/ts move` again. While you drag, a box lines up with the middle of the screen and with the other addons' frames (a green line shows what it lined up with); hold Shift to place it freely. |
| `/ts minimap` | Shows or hides the minimap button |
| `/ts buffs` | Says in chat what it knows of each worn trinket's buff |
| `/ts swap` | Shows the swap alert for 10 seconds, to see it and where it sits |
| `/ts reset` | Settings and position back to how they came |

## Settings

- Icon size, and the space between the icons (below zero pulls big icons together).
- Whether the menu opens above or below the icons.
- The cooldown tray, the "Swap" label, the swap alert in the middle of the screen, the buff on the icon, the key shown on each icon and the minimap button can each be switched off.

## Good to know

- Which buff is a trinket's: the spells the game names for the item, and any buff called like those spells or like the trinket itself. A proc's buff with a name of its own is learned the first time it is seen (out of combat, or from its cast in a fight) and kept for that trinket from then on; the icon takes it on when the fight ends. A few are built in (Mark of the Chosen).
- The icons can't be moved or resized during combat (a game rule for anything that uses an item when clicked). A change made mid-fight is applied when the fight ends.
- Where the game hides an item's cooldown in combat, the icon counts down from what it last read, or from the longest cooldown it has seen that trinket have.

## Coming from ArchDruid

The trinket icons used to be part of ArchDruid's HUD. The first time TrinketSwapper runs with ArchDruid's settings there, it takes over the two trinket switches (the cooldown tray and "Swap"), the keys you had set for using each trinket, and the buffs ArchDruid had learned for your trinkets.

## Install

Put the `TrinketSwapper` folder in `World of Warcraft\_forever_\Interface\AddOns\` and restart the game.
