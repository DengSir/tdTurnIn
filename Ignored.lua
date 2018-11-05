--[[
Ignored.lua
@Author  : DengSir (tdaddon@163.com)
@Link    : https://dengsir.github.io
]]

local ns = select(2, ...)

ns.IGNORED_QUESTS = {
    '封印命运',
    'Sealing Fate',
    '卷土重来',
    '海难俘虏'
}

ns.IGNORED_NPCS = {
    [98489] = true,     -- 海难俘虏
    [87391] = true,     -- 命运扭曲者赛瑞斯 封印命运
    [88570] = true,     -- 命运扭曲者提拉尔
    [111243] = true,    -- 大法师兰达洛克
}
