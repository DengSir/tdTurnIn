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

function Addon:OnEnable()
    self:RegisterEvent('GOSSIP_SHOW')
    self:RegisterEvent('QUEST_DETAIL')
    self:RegisterEvent('QUEST_PROGRESS')
    self:RegisterEvent('QUEST_COMPLETE')
    self:RegisterEvent('QUEST_GREETING')
end

function Addon:IsAllow()
    return not IsShiftKeyDown()
end

function Addon:GetSetting(key)
    local settings = {
        turnInDaily = true,
    }
    return settings[key]
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

        local isDaily   = self:IsDaily(frequency)
        local isIgnored = isIgnored or self:IsQuestIgnored(questTitle)

        if not isIgnored and not isRepeatable and (not isDaily or self:GetSetting('turnInDaily')) then
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
    elseif not IsQuestIgnored() then
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
        local _, isComplete = GetActiveTitle(i)
        if isComplete then
            return SelectActiveQuest(i)
        end
    end

    for i = 1, GetNumAvailableQuests() do
        local isTrivial, frequency, isRepeatable, isLegendary, isIgnored = GetAvailableQuestInfo(i)
        local isDaily = self:IsDaily(frequency)
        local isIgnored = isIgnored or self:IsQuestIgnored(GetAvailableTitle(i))

        if not isIgnored and not isRepeatable and (not isDaily or self:GetSetting('turnInDaily')) then
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
    return questTitle:find(L.IGNORED_QUEST_PREFIX, nil, true)
end

function Addon:IsDaily(frequency)
    return frequency == LE_QUEST_FREQUENCY_DAILY or frequency == LE_QUEST_FREQUENCY_WEEKLY
end
