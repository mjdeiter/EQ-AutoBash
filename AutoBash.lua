-- AutoBash.lua

local SCRIPT_VERSION = "2.0"
local SCRIPT_DATE = "2025-05-21"

--[[
Changelog:
v2.0 (2025-05-21)
  - Command system: /autobash help, status, on, off, verbose, bossadd, bossdel, addzone, delzone, reload
  - /autobash help prints all features/commands on load and on request
  - Boss and zone awareness: always shield for named mobs or in dangerous zones
  - Aggro/multi-mob awareness: shield if many mobs have aggro
  - Stun/low HP/rapid spike/feign/root/mez/medding triggers
  - Buff/debuff triggers (example stub)
  - Group awareness: shield if tank or healer dead
  - Logging of swaps/reasons
  - Verbosity toggling
  - All prior logic improvements retained
]]

----------------------------- CONFIG SECTION -----------------------------
local SHIELD_ITEM = "Shield of the Lightning Lord"
local OFFHAND_ITEM = "Hammer of Rancorous Thoughts"
local PROC_SLOT = 14 -- 13 = mainhand, 14 = offhand

local SHIELD_INTERVAL = 25 -- Seconds between shield swap attempts (while safe)
local SHIELD_DURATION = 5  -- Seconds to leave shield equipped for focus benefit

local LOW_HP_THRESHOLD = 15    -- Equip shield below this HP%
local SAFE_HP_THRESHOLD = 25   -- Only unequip shield when above this HP%
local DANGER_COOLDOWN = 2      -- Minimum seconds between danger-triggered swaps

local AGGRO_MOB_COUNT = 3      -- Equip shield if aggro > this number

local VERBOSE_ECHO = true      -- Set to false for minimal chat spam
local LOGGING = true           -- Log swaps/reasons to file

local BOSS_LIST = { "Lord Nagafen", "Veeshan" } -- Boss/named list (case-sensitive)
local DANGEROUS_ZONES = { "Veeshan's Peak", "Plane of Fear" } -- Always shield in these

local BUFF_TRIGGER = ""        -- e.g. "Mortal Coil" (example stub)
local DEBUFF_TRIGGER = ""      -- e.g. "Doom" (example stub)

----------------------------- STATE SECTION -----------------------------
local lastSwapTime = 0
local shieldEquippedForFocus = false
local combatActive = false
local inDanger = false -- Track persistent danger state
local lastDangerEcho = 0
local autobash_enabled = true
local lastSpikeHP = mq.TLO.Me.PctHPs() or 100
local lastLogTime = 0

local mq = require 'mq'

----------------------------- UTILS -----------------------------
local function filelog(msg)
    if LOGGING then
        local f = io.open(mq.configDir .. "/AutoBash.log", "a")
        if f then
            f:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. msg .. "\n")
            f:close()
        end
    end
end

local function echo(msg, ...)
    if VERBOSE_ECHO then
        mq.cmdf('/echo [AutoBash v%s] ' .. msg, SCRIPT_VERSION, ...)
    end
end

local function critical_echo(msg, ...)
    mq.cmdf('/echo \ar[AutoBash v%s] ' .. msg .. '\ax', SCRIPT_VERSION, ...)
end

----------------------------- FEATURE HELP -----------------------------
local function printHelp()
    local help = [[
\agAutoBash v%s - Features and Commands:
\ayFeatures:\ax
- Auto swaps shield/offhand for Furious Bash focus effect for DPS and defense
- Always equips shield if stunned, low HP, rapid spike, rooted, mezzed, or medding
- Boss/named mob awareness (no swap to offhand for BOSS_LIST mobs)
- Zone awareness (always shield in DANGEROUS_ZONES)
- Aggro awareness: always shield if aggroed by >= %d mobs
- Buff/debuff triggers (stub: %s/%s)
- Group tank/healer death awareness (shield for survival)
- Logging to file if enabled
- Anti-spam logic (no rapid reswaps during danger)
- Configurable echo verbosity and logging
- Command interface for in-game control

\ayCommands:\ax
  /autobash help      - Show this help
  /autobash status    - Show current state and config
  /autobash on        - Enable script
  /autobash off       - Disable script
  /autobash verbose   - Toggle echo verbosity
  /autobash bossadd <name> - Add a boss to always-shield list
  /autobash bossdel <name> - Remove a boss from always-shield list
  /autobash addzone <name> - Add a zone to danger zone list
  /autobash delzone <name> - Remove a zone from danger zone list
  /autobash reload    - Reload config lists (future)
]]
    mq.cmdf(help, SCRIPT_VERSION, AGGRO_MOB_COUNT, BUFF_TRIGGER, DEBUFF_TRIGGER)
end

----------------------------- COMMANDS -----------------------------
mq.event("AutoBashCmd",
    "#1#/autobash#2#",
    function(line, _, rest)
        local arg = (rest or ""):gsub("^%s+", "")
        if arg:find("help") then
            printHelp()
        elseif arg:find("status") then
            local state = autobash_enabled and "\agENABLED\ax" or "\arDISABLED\ax"
            mq.cmdf("[AutoBash] State: %s | Verbose: %s | Focus swap: %s | Shield: %s | DPS: %s",
                state, tostring(VERBOSE_ECHO), tostring(shieldEquippedForFocus), SHIELD_ITEM, OFFHAND_ITEM)
        elseif arg:find("on") then
            autobash_enabled = true
            echo("AutoBash enabled.")
        elseif arg:find("off") then
            autobash_enabled = false
            echo("AutoBash disabled.")
        elseif arg:find("verbose") then
            VERBOSE_ECHO = not VERBOSE_ECHO
            echo("Verbose echo now: %s", tostring(VERBOSE_ECHO))
        elseif arg:find("^bossadd%s+(.+)") then
            local name = arg:match("^bossadd%s+(.+)")
            table.insert(BOSS_LIST, name)
            echo("Added '%s' to boss list.", name)
        elseif arg:find("^bossdel%s+(.+)") then
            local name = arg:match("^bossdel%s+(.+)")
            for i, v in ipairs(BOSS_LIST) do
                if v == name then table.remove(BOSS_LIST, i) break end
            end
            echo("Removed '%s' from boss list.", name)
        elseif arg:find("^addzone%s+(.+)") then
            local name = arg:match("^addzone%s+(.+)")
            table.insert(DANGEROUS_ZONES, name)
            echo("Added '%s' to dangerous zones.", name)
        elseif arg:find("^delzone%s+(.+)") then
            local name = arg:match("^delzone%s+(.+)")
            for i, v in ipairs(DANGEROUS_ZONES) do
                if v == name then table.remove(DANGEROUS_ZONES, i) break end
            end
            echo("Removed '%s' from dangerous zones.", name)
        elseif arg:find("reload") then
            echo("Reload not implemented (edit script and /reload).")
        else
            echo("Unknown command. Use /autobash help.")
        end
    end
)

----------------------------- TRIGGERS -----------------------------
local function isBusy()
    return mq.TLO.Me.Zoning() or mq.TLO.Me.Loading() or mq.TLO.Me.Feigning()
end

local function isBossFight()
    local target = mq.TLO.Target
    for _, boss in ipairs(BOSS_LIST) do
        if target() and target.Name() == boss then return true end
    end
    return false
end

local function inDangerZone()
    local zone = mq.TLO.Zone.ShortName() or ""
    for _, z in ipairs(DANGEROUS_ZONES) do
        if zone == z then return true end
    end
    return false
end

local function aggroCount()
    -- Uses XTarget slots if available, fallback to 1 if not supported
    local count = 0
    for i=1, mq.TLO.Me.XTargetSlots() or 0 do
        if mq.TLO.Me.XTarget(i).TargetType() == "Auto Hater" then count = count + 1 end
    end
    return math.max(count, (mq.TLO.Me.PctAggro() and mq.TLO.Me.PctAggro() > 100 and 2 or 1))
end

local function groupTankOrHealerDead()
    for i = 1, mq.TLO.Group() do
        local member = mq.TLO.Group.Member(i)
        if member() then
            local class = member.Class.ShortName()
            if ((class == "WAR" or class == "PAL" or class == "SHD") or (class == "CLR" or class == "DRU" or class == "SHM")) and member.Dead() then
                return true
            end
        end
    end
    return false
end

local function hasBuff(name)
    return name ~= "" and mq.TLO.Me.Buff(name)()
end

local function hasDebuff(name)
    return name ~= "" and mq.TLO.Me.Debuff(name)()
end

local function isRootedMezzed()
    return mq.TLO.Me.Rooted() or mq.TLO.Me.Mezzed()
end

local function isMedding()
    return mq.TLO.Me.Sitting()
end

local function isRapidSpike()
    local hp = mq.TLO.Me.PctHPs()
    local prev = lastSpikeHP
    lastSpikeHP = hp
    return (prev - hp) >= 25
end

local function isValidCombatTarget()
    local target = mq.TLO.Target
    return target()
        and target.Type() == "NPC"
        and target.Aggressive()
        and not target.Dead()
        and mq.TLO.Me.Combat()
end

local function equipItem(slot, itemName)
    if not mq.TLO.FindItem(itemName)() then
        critical_echo("WARNING: Could not find item: %s", itemName)
        return false
    end
    if mq.TLO.InvSlot(slot).Item() and mq.TLO.InvSlot(slot).Item.Name() ~= itemName then
        mq.cmdf('/exchange "%s" %d', itemName, slot)
        mq.delay(200)
    end
    return true
end

local function getCurrentOffhand()
    if mq.TLO.InvSlot(PROC_SLOT).Item() then
        return mq.TLO.InvSlot(PROC_SLOT).Item.Name()
    end
    return ""
end

------------------ DANGER LOGIC (returns true/false/reason) ------------------
local function dangerCheck()
    local hp = mq.TLO.Me.PctHPs()
    local stunned = mq.TLO.Me.Stunned()

    if not autobash_enabled then return false, "disabled" end
    if isBossFight() then return true, "boss" end
    if inDangerZone() then return true, "dangerzone" end
    if aggroCount() >= AGGRO_MOB_COUNT then return true, "aggro" end
    if stunned then return true, "stunned" end
    if hp < LOW_HP_THRESHOLD then return true, "lowhp" end
    if isRootedMezzed() then return true, "cc" end
    if isMedding() then return true, "medding" end
    if isRapidSpike() then return true, "spike" end
    if hasBuff(BUFF_TRIGGER) then return true, "buff" end
    if hasDebuff(DEBUFF_TRIGGER) then return true, "debuff" end
    if groupTankOrHealerDead() then return true, "group" end
    return false, nil
end

----------------------------- MAIN -----------------------------
mq.cmd('/echo \agOriginally created by Alektra <Lederhosen>\ax')
echo("Script loaded (version %s, %s). Type \ay/autobash help\ax for all features and commands.", SCRIPT_VERSION, SCRIPT_DATE)
printHelp()

-- Item presence warnings
if not mq.TLO.FindItem(SHIELD_ITEM)() then
    critical_echo("WARNING: Could not find your shield item: %s", SHIELD_ITEM)
end
if not mq.TLO.FindItem(OFFHAND_ITEM)() then
    critical_echo("WARNING: Could not find your offhand item: %s", OFFHAND_ITEM)
end

while true do
    mq.delay(250)
    if isBusy() then goto continue end

    local now = os.time()
    local currentOffhand = getCurrentOffhand()
    local validCombat = isValidCombatTarget()
    local danger, dangerReason = dangerCheck()

    -- Danger state: equip shield, echo/log swap
    if danger then
        if currentOffhand ~= SHIELD_ITEM and (now - lastDangerEcho > DANGER_COOLDOWN) then
            if equipItem(PROC_SLOT, SHIELD_ITEM) then
                shieldEquippedForFocus = false
                lastDangerEcho = now
                local msg = ""
                if dangerReason == "disabled" then msg = "AutoBash is disabled."
                elseif dangerReason == "boss" then msg = "Boss/named target! Equipping shield for max defense."
                elseif dangerReason == "dangerzone" then msg = "Dangerous zone! Equipping shield for safety."
                elseif dangerReason == "aggro" then msg = "High aggro count! Equipping shield."
                elseif dangerReason == "stunned" then msg = "Stunned! Equipping shield for safety."
                elseif dangerReason == "lowhp" then msg = "Low HP (below %d%%)! Equipping shield for safety.", LOW_HP_THRESHOLD
                elseif dangerReason == "cc" then msg = "Rooted or mezzed! Equipping shield."
                elseif dangerReason == "medding" then msg = "Sitting/medding! Equipping shield."
                elseif dangerReason == "spike" then msg = "Rapid HP drop! Equipping shield."
                elseif dangerReason == "buff" then msg = "Dangerous buff detected! Equipping shield."
                elseif dangerReason == "debuff" then msg = "Dangerous debuff detected! Equipping shield."
                elseif dangerReason == "group" then msg = "Group tank/healer dead! Equipping shield."
                else msg = "Danger! Equipping shield for safety." end
                echo(msg)
                filelog("Shield equipped due to: "..tostring(dangerReason))
            end
        end
        goto continue
    end

    -- Combat focus swap logic (only if not in danger and enabled)
    if autobash_enabled and validCombat then
        if not combatActive then
            combatActive = true
            shieldEquippedForFocus = false
            lastSwapTime = now
            if currentOffhand ~= OFFHAND_ITEM then
                if equipItem(PROC_SLOT, OFFHAND_ITEM) then
                    echo("Engaged valid combat. Equipping DPS offhand to start swap cycle.")
                    filelog("Combat start: DPS offhand equipped.")
                end
            end
        end
        if not shieldEquippedForFocus and (now - lastSwapTime >= SHIELD_INTERVAL) then
            if equipItem(PROC_SLOT, SHIELD_ITEM) then
                shieldEquippedForFocus = true
                lastSwapTime = now
                echo("Equipping shield to benefit from Furious Bash focus effect.")
                filelog("Shield equipped for Furious Bash focus effect.")
            end
        elseif shieldEquippedForFocus and (now - lastSwapTime >= SHIELD_DURATION) then
            if equipItem(PROC_SLOT, OFFHAND_ITEM) then
                shieldEquippedForFocus = false
                lastSwapTime = now
                echo("Swapping back to DPS offhand for continued combat.")
                filelog("DPS offhand equipped after focus swap.")
            end
        end
    else
        if combatActive then
            combatActive = false
            shieldEquippedForFocus = false
            if currentOffhand ~= OFFHAND_ITEM then
                if equipItem(PROC_SLOT, OFFHAND_ITEM) then
                    echo("Combat ended. Swapping back to DPS offhand.")
                    filelog("Combat end: DPS offhand equipped.")
                end
            end
        end
        if currentOffhand ~= OFFHAND_ITEM then
            equipItem(PROC_SLOT, OFFHAND_ITEM)
        end
    end

    ::continue::
end
