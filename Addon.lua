--[[
Addon.lua
@Author  : DengSir (tdaddon@163.com)
@Link    : https://dengsir.github.io
]]
 local ns = select(2, ...)
local IGNORED_NPCS = ns.IGNORED_NPCS
local L = LibStub('AceLocale-3.0'):GetLocale('tdTurnIn')

local Addon = LibStub('AceAddon-3.0'):NewAddon('tdTurnIn', 'AceEvent-3.0')

Addon.Handle = setmetatable({}, {
    __newindex = function(t, k, fn)
        if type(fn) ~= 'function' then
            return
        end

        Addon[k] = function(_, ...)
            Addon:HandleCall(fn, ...)
        end
    end,
})

function Addon:OnInitialize()
    local defaults = {profile = {turnInDaily = true, turnInRepeat = true, enable = true, modifierKey = 'shift'}}

    self.db = LibStub('AceDB-3.0'):New('TDDB_TURNIN', defaults, true)

    local options = {
        type = 'group',
        name = 'tdTurnIn',
        get = function(item)
            return self.db.profile[item[#item]]
        end,
        set = function(item, value)
            self.db.profile[item[#item]] = value
        end,
        args = {
            enable = {
                type = 'toggle',
                name = ENABLE,
                width = 'double',
                order = 1,
                get = function()
                    return self:IsEnabled()
                end,
                set = function(item, value)
                    if value then
                        self:Enable()
                    else
                        self:Disable()
                    end
                end,
            },
            turnInDaily = {type = 'toggle', name = L['Turn in daily quests'], width = 'double', order = 2},
            turnInRepeat = {type = 'toggle', name = L['Turn in repeatable quests'], width = 'double', order = 3},
        },
    }

    local registry = LibStub('AceConfigRegistry-3.0')
    registry:RegisterOptionsTable('tdTurnIn Options', options)

    local dialog = LibStub('AceConfigDialog-3.0')
    dialog:AddToBlizOptions('tdTurnIn Options', 'tdTurnIn')

    if not self.db.profile.enable then
        self:Disable()
    end
end

function Addon:OnEnable()
    self:RegisterEvent('GOSSIP_SHOW')
    self:RegisterEvent('QUEST_DETAIL')
    self:RegisterEvent('QUEST_PROGRESS')
    self:RegisterEvent('QUEST_COMPLETE')
    self:RegisterEvent('QUEST_GREETING')
    self.db.profile.enable = true
end

function Addon:OnDisable()
    self.db.profile.enable = false
end

function Addon:IsAllow()
    return not IsShiftKeyDown()
end

function Addon:GetSetting(key)
    return self.db.profile[key]
end

local function ItemCount(id, count)
    return function()
        return GetItemCount(id) >= count
    end
end

local repeats = { --
    ['铭记奥特兰克！'] = ItemCount(20560, 3),
    ['战歌峡谷之战'] = ItemCount(20558, 3),
    ['水晶簇'] = ItemCount(17423, 5),
    ['森林之王伊弗斯'] = ItemCount(0, 1),
    ['爪牙的天灾石'] = ItemCount(12840, 20),
    ['侵略者的天灾石'] = ItemCount(12841, 10),
    ['堕落者的天灾石'] = ItemCount(12843, 1),
}

function Addon:IsComplete(questTitle)
    return not repeats[questTitle] or repeats[questTitle]()
end

function Addon:Iterate(step, total)
    local count = total / step
    return coroutine.wrap(function()
        for i = count, 1, -1 do
            local s = step * (i - 1) + 1
            coroutine.yield(i, s)
        end
    end)
end

function Addon:ChoiceActiveQuest(...)
    for id, index in self:Iterate(6, select('#', ...)) do
        local _, _, _, isComplete = select(index, ...)
        if isComplete then
            return SelectGossipActiveQuest(id) or true
        end
    end
end

function Addon:ChoiceAvailableQuest(...)
    for id, index in self:Iterate(7, select('#', ...)) do
        local questTitle, _, isTrivial, frequency, isRepeatable, isLegendary, isIgnored = select(index, ...)
        if not isIgnored and (not isRepeatable or self:IsComplete(questTitle)) then
            return SelectGossipAvailableQuest(id) or true
        end
    end
end

function Addon:ChoiceOption(...)
    for id, index in self:Iterate(2, select('#', ...)) do
        local name, type = select(index, ...)
        if type == 'battlemaster' then
            return SelectGossipOption(id) or true
        end
    end
end

function Addon.Handle:GOSSIP_SHOW()
    return self:ChoiceActiveQuest(GetGossipActiveQuests()) or self:ChoiceAvailableQuest(GetGossipAvailableQuests()) or
               self:ChoiceOption(GetGossipOptions())
end

function Addon.Handle:QUEST_DETAIL()
    if not self:GetSetting('turnInDaily') and (QuestIsDaily() or QuestIsWeekly()) then
        return
    end
    if QuestGetAutoAccept and QuestGetAutoAccept() then
        CloseQuest()
    else
        AcceptQuest()
    end
end

function Addon.Handle:QUEST_PROGRESS()
    if IsQuestCompletable() then
        CompleteQuest()
    end
end

function Addon.Handle:QUEST_COMPLETE()
    if GetNumQuestChoices() <= 1 then
        GetQuestReward(1)
    end
end

function Addon.Handle:QUEST_GREETING()
    for i = 1, GetNumActiveQuests() do
        local title, isComplete = GetActiveTitle(i)
        if isComplete then
            return SelectActiveQuest(i)
        end
    end

    for i = 1, GetNumAvailableQuests() do
        if GetAvailableQuestInfo then
            local isTrivial, frequency, isRepeatable, isLegendary, isIgnored = GetAvailableQuestInfo(i)
            local isDaily = self:IsDailyAllow(frequency)

            if not isIgnored and self:IsRepeatAllow(isRepeatable) and self:IsDailyAllow(frequency) then
                return SelectAvailableQuest(i)
            end
        else
            local questTitle = GetAvailableTitle(i)
            if self:IsComplete(questTitle) then
                return SelectAvailableQuest(i)
            end
        end
    end
end

function Addon:IsNpcIgnored()
    local guid = UnitGUID('npc')
    if not guid then
        return true
    end

    local id = tonumber(guid:match('.-%-%d+%-%d+%-%d+%-%d+%-(%d+)'))
    return IGNORED_NPCS[id]
end

function Addon:HandleCall(fn, ...)
    if not self:IsAllow() then
        return
    end

    if self:IsNpcIgnored() then
        return
    end

    local args = {...}
    local argCount = select('#', ...)

    C_Timer.After(0, function()
        return fn(self, unpack(args, 1, argCount))
    end)
end

function Addon:IsDailyAllow(frequency)
    local isDaily = frequency == LE_QUEST_FREQUENCY_DAILY or frequency == LE_QUEST_FREQUENCY_WEEKLY
    return not isDaily or self:GetSetting('turnInDaily')
end

function Addon:IsRepeatAllow(isRepeatable)
    return not isRepeatable or self:GetSetting('turnInRepeat')
end
