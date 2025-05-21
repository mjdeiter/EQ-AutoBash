# AutoBash.lua

## Overview

**AutoBash.lua** is a highly configurable lua script for EverQuest (Project Lazarus/E3N or similar emulated servers) warriors.  
It automatically swaps your secondary slot between a shield and an offhand weapon to maximize aggro and survivability.  
The script responds dynamically to lost aggro, low health, and NPC spellcasting, automatically using **Bash** at every opportunity for hate or interruption.

---

## Features

- **Automatic Shield Swapping:**  
  - Equips a shield when:
    - You lose aggro
    - Your HP drops below a configurable threshold (default: 50%)
    - The NPC you are fighting starts casting a spell
  - Swaps back to your DPS offhand weapon when safe

- **Aggro Recovery:**  
  Bursts aggro with shield + Bash if you lose threat.

- **Emergency Mode:**  
  Prioritizes survivability by equipping a shield when low on health.

- **Interrupt Mode:**  
  Swaps to shield and Bashes when your target is casting.

- **Configurable:**  
  Easily set item names, HP threshold, intervals, and more at the top of the script.

- **Version Tracking:**  
  Built-in version and changelog.

---

## Requirements

- [MacroQuest (MQ2)](https://github.com/macroquest/macroquest)
- [MQ2Lua](https://github.com/macroquest/macroquest/wiki/Lua-Overview)
- [MQ2Exchange](https://www.macroquest.org/wiki/index.php/MQ2Exchange) (plugin for swapping items)
- A warrior (or class with Bash and shield/weapon swap capability)
- Place your shield and offhand weapon in inventory

---

## Installation

1. **Download the script:**  
   Save [`AutoAggroBash.lua`](./AutoAggroBash.lua) to your MacroQuest `lua` folder.

2. **Edit settings (optional):**  
   Open the script and adjust the configuration section at the top for your item names, HP threshold, etc.

3. **Load plugins:**  
   In-game, ensure MQ2Exchange is loaded:
   ```
   /plugin mq2exchange
   ```

4. **Run the script:**  
   ```
   /lua run AutoAggroBash
   ```

---

## Configuration

At the top of the script, you will find:
```lua
local PROC_ITEM = "Shield of the Lightning Lord"
local PROC_SLOT = 14 -- 13 = mainhand, 14 = offhand
local MAINHAND_ITEM = "Mace of Grim Tidings"
local OFFHAND_ITEM = "Hammer of Rancorous Thoughts"
local AGGRO_CHECK_INTERVAL = 1 -- seconds
local LOW_HP_THRESHOLD = 50    -- % HP to trigger emergency mode
```
- Change the item names and threshold to match your gear and preferences.

---

## How It Works

- The script monitors your combat state, HP, aggro, and if your target is casting.
- It swaps your secondary slot as needed to maximize aggro, interrupt casts, and boost survivability.
- **All actions are echoed in your EQ chat window for clarity.**

---

## Version History

See the top of [`AutoAggroBash.lua`](./AutoAggroBash.lua) for a full changelog.

---

## Contributing

Pull requests, feature suggestions, and improvements are welcome!

1. Fork the repo
2. Create a new branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Create a new Pull Request

---

## License

MIT License. See [LICENSE](./LICENSE) for details.
