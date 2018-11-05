--[[
Addon.lua
@Author  : DengSir (tdaddon@163.com)
@Link    : https://dengsir.github.io
]]

local ns             = select(2, ...)
local IGNORED_QUESTS = ns.IGNORED_QUESTS
local L              = LibStub('AceLocale-3.0'):GetLocale('tdTurnIn')

local Addon = LibStub('AceAddon-3.0'):NewAddon('tdTurnIn', 'AceEvent-3.0')

Addon.Handle = setmetatable({}, {__newindex = function(t, k, fn)
    if type(fn) ~= 'function' then
        return
    end

    Addon[k] = function(_, ...)
        Addon:HandleCall(fn, ...)
    end
end})

function Addon:OnInitialize()
    local defaults = {
        profile = {
            turnInDaily  = true,
            turnInRepeat = true,
            enable       = true,
            modifierKey  = 'shift',
        }
    }

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
                type  = 'toggle',
                name  = ENABLE,
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
                end
            },
            turnInDaily = {
                type  = 'toggle',
                name  = L['Turn in daily quests'],
                width = 'double',
                order = 2,
            },
            turnInRepeat = {
                type  = 'toggle',
                name  = L['Turn in repeatable quests'],
                width = 'double',
                order = 3,
            },
        }
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

function Addon:ChoiceActiveQuest(...)
    for i = 1, select('#', ...), 6 do
        local _, _, _, isComplete = select(i, ...)
        if isComplete then
            return SelectGossipActiveQuest(math.floor(i/6) + 1) or true
        end
    end
end

function Addon:ChoiceAvailableQuest(...)
    for i = 1, select('#', ...), 7 do
        local questTitle, _, isTrivial, frequency, isRepeatable, isLegendary, isIgnored = select(i, ...)
        local isIgnored = isIgnored or self:IsQuestIgnored(questTitle)

        if not isIgnored and self:IsRepeatAllow(isRepeatable) and self:IsDailyAllow(frequency) then
            return SelectGossipAvailableQuest(math.floor(i/7) + 1) or true
        end
    end
end

function Addon.Handle:GOSSIP_SHOW()
    return self:ChoiceActiveQuest(GetGossipActiveQuests()) or self:ChoiceAvailableQuest(GetGossipAvailableQuests())
end

function Addon.Handle:QUEST_DETAIL()
    if not self:GetSetting('turnInDaily') and (QuestIsDaily() or QuestIsWeekly()) then
        return
    end
    if self:IsQuestIgnored(GetTitleText()) then
        return
    end
    if QuestGetAutoAccept() then
        CloseQuest()
    else--if not IsQuestIgnored() then
        AcceptQuest()
    end
end

function Addon.Handle:QUEST_PROGRESS()
    if self:IsQuestIgnored(GetTitleText()) then
        return
    end
    if IsQuestCompletable() then
        CompleteQuest()
    end
end

function Addon.Handle:QUEST_COMPLETE()
    if self:IsQuestIgnored(GetTitleText()) then
        return
    end
    if GetNumQuestChoices() <= 1 then
        GetQuestReward(1)
    end
end

function Addon.Handle:QUEST_GREETING()
    for i = 1, GetNumActiveQuests() do
        local title, isComplete = GetActiveTitle(i)
        if isComplete and not self:IsQuestIgnored(title) then
            return SelectActiveQuest(i)
        end
    end

    for i = 1, GetNumAvailableQuests() do
        local isTrivial, frequency, isRepeatable, isLegendary, isIgnored = GetAvailableQuestInfo(i)
        local isDaily = self:IsDailyAllow(frequency)
        local isIgnored = isIgnored or self:IsQuestIgnored(GetAvailableTitle(i))

        if not isIgnored and self:IsRepeatAllow(isRepeatable) and self:IsDailyAllow(frequency) then
            return SelectAvailableQuest(i)
        end
    end
end

function Addon:HandleCall(fn, ...)
    if not self:IsAllow() then
        return
    end
    local args = {...}
    local argCount = select('#', ...)

    C_Timer.After(0, function()
        fn(self, unpack(args, 1, argCount))
    end)
end

function Addon:IsQuestIgnored(questTitle)
    for _, v in ipairs(IGNORED_QUESTS) do
        if questTitle:find(v, nil, true) then
            return true
        end
    end
end

function Addon:IsDailyAllow(frequency)
    local isDaily = frequency == LE_QUEST_FREQUENCY_DAILY or frequency == LE_QUEST_FREQUENCY_WEEKLY
    return not isDaily or self:GetSetting('turnInDaily')
end

function Addon:IsRepeatAllow(isRepeatable)
    return not isRepeatable or self:GetSetting('turnInRepeat')
end
