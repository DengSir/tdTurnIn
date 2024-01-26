
-- Addon.lua
-- @Author  : DengSir (tdaddon@163.com)
-- @Link    : https://dengsir.github.io

local ns = select(2, ...)
local IGNORED_NPCS = ns.IGNORED_NPCS
local L = LibStub('AceLocale-3.0'):GetLocale('tdTurnIn')

---@class tdTurnIn
---@field Handle tdTurnIn
---@field db any
---@field repeatables any[]
local Addon = LibStub('AceAddon-3.0'):NewAddon('tdTurnIn', 'AceEvent-3.0')

local HAS_DAILY = not not QuestIsDaily

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
    local defaults = {
        global = {repeatables = {}},
        profile = {turnInDaily = true, turnInRepeat = true, enable = true, modifierKey = 'shift'},
    }

    self.db = LibStub('AceDB-3.0'):New('TDDB_TURNIN', defaults, true)

    self.repeatables = self.db.global.repeatables

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

function Addon:IsComplete(questTitle)
    local data = self.repeatables[questTitle]
    if type(data) ~= 'table' then
        return
    end

    for id, count in pairs(data) do
        if GetItemCount(id) < count then
            return false
        end
    end
    return true
end

function Addon:IsQuestRepeatable(questTitle)
    return self.repeatables[questTitle]
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

function Addon:ChoiceActiveQuest(quests)
    for id, quest in ipairs(quests) do
        if quest.isComplete then
            return C_GossipInfo.SelectActiveQuest(id) or true
        end
    end
end

function Addon:ChoiceAvailableQuest(quests)
    for id, quest in ipairs(quests) do
        if quest.repeatable then
            self.repeatables[quest.title] = self.repeatables[quest.title] or true
        end

        print(quest.title, quest.repeatable)

        if not quest.isIgnored and (not quest.repeatable or (self:IsRepeatAllow(quest.repeatable) and self:IsComplete(quest.title))) then
            return C_GossipInfo.SelectAvailableQuest(id) or true
        end
    end
end

local SelectOption = {
    ICON = {
        [132050] = true, -- 银行
        [132057] = true, -- 鸟点
        [132058] = true, -- 专业技能
        [132060] = true, -- 商店
        [528409] = true, -- 拍卖行
    }
}
function Addon:ChoiceOption(options)
    for i, option in ipairs(options) do
        if option.name == 'battlemaster' or SelectOption.ICON[option.icon] then
            return C_GossipInfo.SelectOption(option.gossipOptionID) or true
        end
    end
end

function Addon.Handle:GOSSIP_SHOW()
    return self:ChoiceActiveQuest(C_GossipInfo.GetActiveQuests()) or self:ChoiceAvailableQuest(C_GossipInfo.GetAvailableQuests()) or
               self:ChoiceOption(C_GossipInfo.GetOptions())
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
    if GetQuestMoneyToGet() > 0 then
        return
    end
    local questTitle = GetTitleText()
    local isRepeatable = self:IsQuestRepeatable(questTitle)

    if isRepeatable then
        self.repeatables[questTitle] = {}

        for i = 1, GetNumQuestItems() do
            if IsQuestItemHidden(i) == 0 then
                local id = tonumber(GetQuestItemLink('required', i):match('item:(%d+)'))
                local name, icon, count = GetQuestItemInfo('required', i)

                self.repeatables[questTitle][id] = count
            end
        end
    end

    if not self:IsRepeatAllow(isRepeatable) then
        return
    end

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
            if questTitle then
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
