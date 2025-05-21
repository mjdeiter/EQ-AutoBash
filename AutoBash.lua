local mq = require 'mq'

local SCRIPT_VERSION = "1.6"
local SCRIPT_DATE = "2025-05-21"

--[[
Changelog:
v1.6 (2025-05-21)
  - Adds advanced danger triggers:
    - Threat Level/Number of Aggroed Mobs: Shield if aggro count above threshold.
    - Class-Specific Logic: Defensive disc logic for knights/warriors; shield while disc is up.
    - Mana/Energy Triggers: Shield if mana or endurance below threshold.
    - Root/Mez/Charm Handling: Shield if rooted, mezzed, or charmed.
    - Buff/Debuff Triggers: Shield if specific buff/debuff detected.
  - Retains periodic shield swap for focus effect.
  - Core safety triggers (stun, low HP) remain.
  - No custom slash commands.
]]

----------------------------- CONFIG SECTION -----------------------------
local SHIELD_ITEM = "Shield of the Lightning Lord"
local OFFHAND_ITEM = "Hammer of Rancorous Thoughts"
local PROC_SLOT = 14 -- 13 = mainhand, 14 = offhand

local SHIELD_INTERVAL = 25 -- Seconds between shield swap attempts (while safe)
local SHIELD_DURATION = 5  -- Seconds to leave shield equipped for focus benefit

local LOW_HP_THRESHOLD = 15    -- Equip shield below this HP%
local SAFE_HP_THRESHOLD = 25   -- Only unequip shield when above this HP%

local AGGRO_MOB_COUNT = 3      -- Equip shield if aggro > this number

local LOW_MANA_THRESHOLD = 10      -- Shield if mana < this %
local LOW_ENDURANCE_THRESHOLD = 10 -- Shield if endurance < this %

local DEFENSIVE_DISC_NAMES = {
    -- Add more as needed
    ["Final Stand Discipline"] = true,
    ["Deflection Discipline"] = true,
    ["Mantle of the Preserver"] = true,
    ["Shield Flash"] = true,
}

local BUFF_TRIGGER = "Mortal Coil"        -- Sample: shield if this buff is up
local DEBUFF_TRIGGER = "Doom"             -- Sample: shield if this debuff is up

----------------------------- STATE SECTION -----------------------------
local lastSwapTime = 0
local shieldEquippedForFocus = false
local combatActive = false
local inDanger = false -- Track persistent danger state
local lastDangerEcho = 0

----------------------------- UTILS -----------------------------
local function echo(msg, ...)
    mq.cmdf('/echo [AutoBash v%s] ' .. msg, SCRIPT_VERSION, ...)
end

local function critical_echo(msg, ...)
    mq.cmdf('/echo \ar[AutoBash v%s] ' .. msg .. '\ax', SCRIPT_VERSION, ...)
end

----------------------------- LOGIC -----------------------------
local function isBusy()
    return mq.TLO.Me.Zoning() or mq.TLO.Me.Feigning() or not mq.TLO.Zone()
end

local function isValidCombatTarget()
    local target = mq.TLO.Target
    return target() and target.Type() == "NPC" and target.Aggressive() and not target.Dead() and mq.TLO.Me.Combat()
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

----------------------------- DANGER TRIGGERS -----------------------------
local function aggroCount()
    local count = 0
    for i=1, (mq.TLO.Me.XTargetSlots() or 0) do
        if mq.TLO.Me.XTarget(i).TargetType() == "Auto Hater" then count = count + 1 end
    end
    return count
end

local function hasActiveDisc()
    for i=1, mq.TLO.Me.NumDiscTimers() or 0 do
        local disc = mq.TLO.Me.CombatAbility(i).Name()
        if disc and DEFENSIVE_DISC_NAMES[disc] and mq.TLO.Me.CombatAbilityReady(disc)() == false then
            return true
        end
    end
    return false
end

local function isKnightOrWarrior()
    local class = mq.TLO.Me.Class.ShortName()
    return class == "WAR" or class == "PAL" or class == "SHD"
end

local function manaLow()
    return mq.TLO.Me.PctMana() and mq.TLO.Me.PctMana() < LOW_MANA_THRESHOLD
end

local function enduranceLow()
    return mq.TLO.Me.PctEndurance() and mq.TLO.Me.PctEndurance() < LOW_ENDURANCE_THRESHOLD
end

local function isRootedMezzedCharmed()
    return mq.TLO.Me.Rooted() or mq.TLO.Me.Mezzed() or mq.TLO.Me.Charmed()
end

local function hasBuff(name)
    return name ~= "" and mq.TLO.Me.Buff(name)()
end

local function hasDebuff(name)
    return name ~= "" and mq.TLO.Me.Debuff(name)()
end

local function dangerCheck()
    local hp = mq.TLO.Me.PctHPs()
    local stunned = mq.TLO.Me.Stunned()
    local aggro = aggroCount()
    local class = mq.TLO.Me.Class.ShortName()

    if not inDanger and (hp < LOW_HP_THRESHOLD or stunned) then
        inDanger = true
        return true, "entered (stun/low HP)"
    end

    if aggro >= AGGRO_MOB_COUNT then
        inDanger = true
        return true, "aggro"
    end

    if isKnightOrWarrior() and hasActiveDisc() then
        inDanger = true
        return true, "defensive disc"
    end

    if manaLow() or enduranceLow() then
        inDanger = true
        return true, "mana/endurance low"
    end

    if isRootedMezzedCharmed() then
        inDanger = true
        return true, "cc/root/mez/charm"
    end

    if hasBuff(BUFF_TRIGGER) then
        inDanger = true
        return true, "special buff"
    end

    if hasDebuff(DEBUFF_TRIGGER) then
        inDanger = true
        return true, "special debuff"
    end

    -- Remain in danger state if below safe HP or still stunned
    if inDanger and (hp < SAFE_HP_THRESHOLD or stunned) then
        return true, "still"
    end

    -- Leave danger state if above safe HP and not stunned/triggered
    if inDanger and (hp >= SAFE_HP_THRESHOLD and not stunned and aggro < AGGRO_MOB_COUNT
        and not (isKnightOrWarrior() and hasActiveDisc())
        and not manaLow() and not enduranceLow()
        and not isRootedMezzedCharmed()
        and not hasBuff(BUFF_TRIGGER)
        and not hasDebuff(DEBUFF_TRIGGER)) then
        inDanger = false
        return false, "recovered"
    end
    return inDanger, "none"
end

----------------------------- MAIN -----------------------------
mq.cmd('/echo \agOriginally created by Alektra <Lederhosen>\ax')
echo("Script loaded (version %s, %s).", SCRIPT_VERSION, SCRIPT_DATE)

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

    -- Priority 1: Danger state (all triggers)
    if danger then
        if currentOffhand ~= SHIELD_ITEM then
            if equipItem(PROC_SLOT, SHIELD_ITEM) then
                shieldEquippedForFocus = false
                if dangerReason ~= "still" then
                    echo("DANGER: %s. Equipping shield for safety.", dangerReason)
                    lastDangerEcho = now
                end
            end
        end
        goto continue
    elseif not danger and dangerReason == "recovered" then
        -- Just left danger: restore normal offhand
        if validCombat and currentOffhand ~= OFFHAND_ITEM then
            if equipItem(PROC_SLOT, OFFHAND_ITEM) then
                shieldEquippedForFocus = false
                lastSwapTime = now
                echo("Recovered from danger. Swapping back to DPS offhand for combat.")
            end
        elseif not validCombat and currentOffhand ~= OFFHAND_ITEM then
            if equipItem(PROC_SLOT, OFFHAND_ITEM) then
                shieldEquippedForFocus = false
                echo("Recovered from danger. Out of combat, equipping DPS offhand.")
            end
        end
    end

    -- Priority 2: Valid combat swapping logic
    if validCombat then
        if not combatActive then
            combatActive = true
            shieldEquippedForFocus = false
            lastSwapTime = now
            if currentOffhand ~= OFFHAND_ITEM then
                if equipItem(PROC_SLOT, OFFHAND_ITEM) then
                    echo("Engaged valid combat. Equipping DPS offhand to start swap cycle.")
                end
            end
        end

        -- Periodically swap shield in for focus effect, then back to DPS
        if not shieldEquippedForFocus and (now - lastSwapTime >= SHIELD_INTERVAL) then
            if equipItem(PROC_SLOT, SHIELD_ITEM) then
                shieldEquippedForFocus = true
                lastSwapTime = now
                echo("Equipping shield to benefit from Furious Bash focus effect.")
            end
        elseif shieldEquippedForFocus and (now - lastSwapTime >= SHIELD_DURATION) then
            if equipItem(PROC_SLOT, OFFHAND_ITEM) then
                shieldEquippedForFocus = false
                lastSwapTime = now
                echo("Swapping back to DPS offhand for continued combat.")
            end
        end
    else
        -- Not in valid combat
        if combatActive then
            combatActive = false
            shieldEquippedForFocus = false
            if not danger and currentOffhand ~= OFFHAND_ITEM then
                if equipItem(PROC_SLOT, OFFHAND_ITEM) then
                    echo("Combat ended. Swapping back to DPS offhand.")
                end
            end
        end
        if not danger and currentOffhand ~= OFFHAND_ITEM then
            equipItem(PROC_SLOT, OFFHAND_ITEM)
        end
    end

    ::continue::
end
