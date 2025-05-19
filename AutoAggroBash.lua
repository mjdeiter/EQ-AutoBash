--[[
AutoAggroBash.lua
Author: Alektra <Lederhosen>
Version: 1.1
Last Updated: 2025-05-19 by mjdeiter

Changelog:
v1.1 - 2025-05-19 - Added version tracking and changelog. Set emergency HP threshold to 50%.
v1.0 - 2025-05-18 - Initial version: Swap to shield on lost aggro, low HP, or NPC casting; reverts to offhand when safe.
]]

-- CONFIGURABLE SECTION
local SCRIPT_VERSION = "1.1"
local PROC_ITEM = "Shield of the Lightning Lord"
local PROC_SLOT = 14 -- 13 = mainhand, 14 = offhand
local MAINHAND_ITEM = "Mace of Grim Tidings"
local OFFHAND_ITEM = "Hammer of Rancorous Thoughts"
local AGGRO_CHECK_INTERVAL = 1 -- seconds
local LOW_HP_THRESHOLD = 50    -- % HP to trigger emergency mode (now 50%)

-- STATE
local usingShield = false
local lastAggroCheck = 0
local emergencyMode = false
local castMode = false

local mq = require 'mq'

local function inCombat()
    return mq.TLO.Me.Combat() and mq.TLO.Target() and mq.TLO.Target.Type() == "NPC"
end

local function equipItem(slot, itemName)
    if mq.TLO.InvSlot(slot).Item.Name() ~= itemName then
        mq.cmdf('/exchange "%s" %d', itemName, slot)
        mq.delay(200)
    end
end

local function bashReady()
    return mq.TLO.Me.AbilityReady("Bash")()
end

local function doBash()
    mq.cmd("/doability Bash")
end

local function echo(msg, ...)
    mq.cmdf('/echo [AutoAggroBash v%s] %s', SCRIPT_VERSION, string.format(msg, ...))
end

echo("Script loaded. Will swap shield for aggro, low HP, or NPC casting.")

while true do
    mq.delay(250)
    if os.clock() - lastAggroCheck < AGGRO_CHECK_INTERVAL then goto continue end
    lastAggroCheck = os.clock()

    local target = mq.TLO.Target
    local hp = mq.TLO.Me.PctHPs()
    emergencyMode = hp < LOW_HP_THRESHOLD

    -- Detect if target is casting a spell
    castMode = false
    if target() and target.Casting() then
        castMode = true
    end

    if inCombat() and target() and target.Aggressive() then
        -- Emergency (Low HP) or Mob Casting
        if emergencyMode or castMode then
            if not usingShield then
                equipItem(PROC_SLOT, PROC_ITEM)
                usingShield = true
                if emergencyMode and castMode then
                    echo("Low HP (%.1f%%) AND mob casting! Shielding up and ready to Bash.", hp)
                elseif emergencyMode then
                    echo("Low HP (%.1f%%)! Shielding up.", hp)
                else
                    echo("Mob is casting! Shielding up for Bash interrupt.")
                end
            end
            -- Spam Bash if available
            if bashReady() then
                doBash()
            end
            goto continue
        end

        -- Aggro check: is target's target you?
        local targetOfTarget = mq.TLO.Target.Target
        local iHaveAggro = targetOfTarget() and targetOfTarget.ID() == mq.TLO.Me.ID()

        if not iHaveAggro then
            if not usingShield then
                equipItem(PROC_SLOT, PROC_ITEM)
                usingShield = true
                echo("Lost aggro! Equipping shield and spamming Bash.")
            end
            if bashReady() then
                doBash()
            end
        else
            -- Only swap back if not in emergency or cast mode
            if usingShield and not emergencyMode and not castMode then
                equipItem(PROC_SLOT, OFFHAND_ITEM)
                usingShield = false
                echo("Safe: Regained aggro, not low HP, mob not casting. Swapping back to %s.", OFFHAND_ITEM)
            end
        end
    else
        -- Out of combat or no target: revert to DPS offhand
        if usingShield then
            equipItem(PROC_SLOT, OFFHAND_ITEM)
            usingShield = false
            echo("Combat ended or no target. Swapping back to %s.", OFFHAND_ITEM)
        end
    end
    ::continue::
end
