-- ZRProfessions: lets the 5.4.8 trainer UI teach more than 2 primary professions,
-- lists every primary profession you know (/profs), since the Professions tab only has 2 slots,
-- and colors gathering tooltips for the professions that aren't in those 2 slots.
--
-- The server stays the real limit (worldserver.conf MaxPrimaryTradeSkill). This addon only removes the
-- client's own "you already know 2" check in Blizzard_TrainerUI.

-- Keep this equal to MaxPrimaryTradeSkill in worldserver.conf.
local MAX_PRIMARY_PROFESSIONS = 4

-- Rank spell IDs per primary profession, Apprentice -> Zen Master (same table the core uses in
-- ServiceMgr.cpp). Knowing any of them means the profession is learned; the highest known one is the rank.
-- open: spell that opens the profession window (nil = gathering, nothing to open).
local PROFESSIONS = {
    { skillLine = 171, ranks = { 2259, 3101, 3464, 11611, 28596, 51304, 80731, 105206 } },  -- Alchemy
    { skillLine = 164, ranks = { 2018, 3100, 3538, 9785, 29844, 51300, 76666, 110396 } },   -- Blacksmithing
    { skillLine = 333, ranks = { 7411, 7412, 7413, 13920, 28029, 51313, 74258, 110400 } },  -- Enchanting
    { skillLine = 202, ranks = { 4036, 4037, 4038, 12656, 30350, 51306, 82774, 110403 } },  -- Engineering
    { skillLine = 773, ranks = { 45357, 45358, 45359, 45360, 45361, 45363, 86008, 110417 } }, -- Inscription
    { skillLine = 755, ranks = { 25229, 25230, 28894, 28895, 28897, 51311, 73318, 110420 } }, -- Jewelcrafting
    { skillLine = 165, ranks = { 2108, 3104, 3811, 10662, 32549, 51302, 81199, 110423 } },  -- Leatherworking
    { skillLine = 197, ranks = { 3908, 3909, 3910, 12180, 26790, 51309, 75156, 110426 } },  -- Tailoring
    { skillLine = 182, ranks = { 2366, 2368, 3570, 11993, 28695, 50300, 74519, 110413 }, gathering = true },  -- Herbalism
    { skillLine = 186, ranks = { 2575, 2576, 3564, 10248, 29354, 50310, 74517, 102161 }, open = 2656 },       -- Mining (opens Smelting)
    { skillLine = 393, ranks = { 8613, 8617, 8618, 10768, 32678, 50305, 74522, 102216 }, gathering = true },  -- Skinning
}

local RANK_NAMES = { "Apprentice", "Journeyman", "Expert", "Artisan", "Master", "Grand Master", "Illustrious", "Zen Master" }

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99ZRProfessions:|r " .. msg)
end

-- Highest known rank (1-8) of a profession, or nil if not learned.
local function KnownRank(prof)
    for i = #prof.ranks, 1, -1 do
        if IsPlayerSpell(prof.ranks[i]) then
            return i
        end
    end
end

local function CountKnownPrimaries()
    local count = 0
    for _, prof in ipairs(PROFESSIONS) do
        if KnownRank(prof) then
            count = count + 1
        end
    end
    return count
end

-- Current/max skill for a skill line, if the client will tell us. GetProfessionInfo is meant for the
-- indexes GetProfessions() returns; we try the others too and only trust a result whose skill line matches.
local function SkillInfo(skillLine)
    for index = 1, 256 do
        local ok, name, _, rank, maxRank, _, _, line = pcall(GetProfessionInfo, index)
        if not ok then
            return
        end
        if name and line == skillLine then
            return name, rank, maxRank
        end
    end
end

local function SkillValues(skillLine)
    local _, rank, maxRank = SkillInfo(skillLine)
    return rank, maxRank
end

---------------------------------------------------------------------------------------------------
-- Trainer: re-enable "Train" for a new primary profession while under the limit
---------------------------------------------------------------------------------------------------

-- Runs after Blizzard's ClassTrainerFrame_SetServiceButton, which disables Train for any new profession
-- once GetProfessions() reports a second one.
local function AfterSetServiceButton(skillButton, skillIndex, playerMoney, selected, isTradeSkill)
    if not (ClassTrainerFrame.selectedService and selected == skillIndex) then
        return
    end
    local _, _, serviceType = GetTrainerServiceInfo(skillIndex)
    local moneyCost, isProfession = GetTrainerServiceCost(skillIndex)
    if serviceType ~= "available" or not isProfession then
        return
    end
    if moneyCost and moneyCost > (playerMoney or GetMoney()) then
        return
    end
    if CountKnownPrimaries() < MAX_PRIMARY_PROFESSIONS then
        ClassTrainerTrainButton:Enable()
    end
end

-- Blizzard's confirmation popup only has text for 0 or 1 known professions.
local function PatchConfirmPopup()
    local dialog = StaticPopupDialogs["CONFIRM_PROFESSION"]
    if not dialog then
        return
    end
    local originalOnShow = dialog.OnShow
    dialog.OnShow = function(self, ...)
        if originalOnShow then
            originalOnShow(self, ...)
        end
        local _, prof2 = GetProfessions()
        if prof2 then
            local skill = GetTrainerServiceSkillLine(ClassTrainerFrame.selectedService) or "this profession"
            self.text:SetFormattedText("Learn %s? You will know %d of %d primary professions.",
                skill, CountKnownPrimaries() + 1, MAX_PRIMARY_PROFESSIONS)
        end
    end
end

local trainerHooked = false
local function HookTrainerUI()
    if trainerHooked then
        return
    end
    trainerHooked = true
    hooksecurefunc("ClassTrainerFrame_SetServiceButton", AfterSetServiceButton)
    PatchConfirmPopup()
end

---------------------------------------------------------------------------------------------------
-- /profs panel: every primary profession, click to open it
---------------------------------------------------------------------------------------------------

local ROW_HEIGHT = 40
local panel, rows = nil, {}
local refreshPending = false

local function CreateRow(index)
    -- Secure button: opening a profession window is a spell cast, which addons may only do this way.
    local row = CreateFrame("Button", "ZRProfessionsRow" .. index, panel, "SecureActionButtonTemplate")
    row:SetSize(260, ROW_HEIGHT - 4)
    row:SetPoint("TOPLEFT", panel, "TOPLEFT", 14, -34 - (index - 1) * ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(32, 32)
    row.icon:SetPoint("LEFT", 2, 0)

    row.name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)

    row.sub = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.sub:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)

    rows[index] = row
    return row
end

local function RefreshPanel()
    if InCombatLockdown() then
        refreshPending = true
        return
    end
    refreshPending = false

    local shown = 0
    for _, prof in ipairs(PROFESSIONS) do
        local rank = KnownRank(prof)
        if rank then
            shown = shown + 1
            local row = rows[shown] or CreateRow(shown)
            local name, _, icon = GetSpellInfo(prof.ranks[rank])
            row.icon:SetTexture(icon)
            row.name:SetText(name)

            local current, max = SkillValues(prof.skillLine)
            local sub = RANK_NAMES[rank]
            if current and max then
                sub = sub .. "  " .. current .. "/" .. max
            end
            if prof.gathering then
                sub = sub .. "  (gathering)"
            end
            row.sub:SetText(sub)

            if prof.gathering then
                row:SetAttribute("type", nil)
                row:SetAttribute("spell", nil)
            else
                row:SetAttribute("type", "spell")
                row:SetAttribute("spell", (GetSpellInfo(prof.open or prof.ranks[rank])))
            end
            row:Show()
        end
    end
    for i = shown + 1, #rows do
        rows[i]:Hide()
    end

    if shown == 0 then
        panel.empty:Show()
    else
        panel.empty:Hide()
    end
    panel.count:SetFormattedText("%d / %d primary professions", shown, MAX_PRIMARY_PROFESSIONS)
    panel:SetHeight(64 + math.max(shown, 1) * ROW_HEIGHT)
end

local function CreatePanel()
    panel = CreateFrame("Frame", "ZRProfessionsFrame", UIParent)
    panel:SetSize(290, 100)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    panel:Hide()

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Primary Professions")

    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    panel.empty = panel:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    panel.empty:SetPoint("TOP", 0, -46)
    panel.empty:SetText("No primary professions learned.")

    panel.count = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    panel.count:SetPoint("BOTTOM", 0, 14)

    panel:SetScript("OnShow", RefreshPanel)
end

local function TogglePanel()
    if InCombatLockdown() then
        Print("not available in combat.")
        return
    end
    if panel:IsShown() then
        panel:Hide()
    else
        panel:Show()
    end
end

-- "All professions" button on the spellbook's Professions tab, next to the bottom tabs.
local function AddSpellbookButton()
    if not SpellBookProfessionFrame then
        return
    end
    local button = CreateFrame("Button", "ZRProfessionsSpellbookButton", SpellBookProfessionFrame, "UIPanelButtonTemplate")
    button:SetSize(130, 22)
    button:SetPoint("TOPRIGHT", SpellBookFrame, "BOTTOMRIGHT", -8, 2)
    button:SetText("All professions")
    button:SetScript("OnClick", TogglePanel)
end

SLASH_ZRPROFESSIONS1 = "/profs"
SLASH_ZRPROFESSIONS2 = "/zrprofs"
SlashCmdList["ZRPROFESSIONS"] = TogglePanel

---------------------------------------------------------------------------------------------------
-- Tooltips: difficulty colors for gathering with a profession that isn't on the Professions tab
---------------------------------------------------------------------------------------------------

-- The client works out "Requires Herbalism <skill>" (nodes) and "Skinnable" (corpses) only for the 2 professions
-- in its slots; for any other it prints "1" in red. For those we fill in the real requirement and color the line
-- ourselves: red when the server would refuse, else orange, yellow, green or gray by skill-up chance.

local HERBALISM, MINING, SKINNING = 182, 186, 393

-- Gathering node requirements for the tooltips below (enUS node names).
-- req: skill the server needs before it lets you gather the node (Lock.dbc, checked in Spell::CanOpenLock).
-- yellow/green/gray: skill at which the node turns that color; from req up to yellow it is orange.
--
-- Pre-Pandaria nodes: the classic required skill R (e.g. Briarthorn 70, which the server enforces), and
-- R+25 / R+50 / R+100 for the colors, the same steps Player::UpdateGatherSkill uses for skill-up chances.
-- Pandaria nodes share the Peacebloom / Copper Vein locks (req 1); their colors come from
-- trivialSkillLow/High (data23/data24) in the world DB's gameobject_template, turned into colors the way
-- UpdateGatherSkill does: yellow = low, green = high, gray = high + (high - low).

local NODES = {
    -- Herbalism (182)
    ['Peacebloom'] = { skill = 182, req = 1, yellow = 26, green = 51, gray = 101 },
    ['Silverleaf'] = { skill = 182, req = 1, yellow = 26, green = 51, gray = 101 },
    ['Bloodthistle'] = { skill = 182, req = 1, yellow = 26, green = 51, gray = 101 },
    ['Earthroot'] = { skill = 182, req = 15, yellow = 40, green = 65, gray = 115 },
    ['Mageroyal'] = { skill = 182, req = 50, yellow = 75, green = 100, gray = 150 },
    ['Briarthorn'] = { skill = 182, req = 70, yellow = 95, green = 120, gray = 170 },
    ['Stranglekelp'] = { skill = 182, req = 85, yellow = 110, green = 135, gray = 185 },
    ['Bruiseweed'] = { skill = 182, req = 100, yellow = 125, green = 150, gray = 200 },
    ['Wild Steelbloom'] = { skill = 182, req = 115, yellow = 140, green = 165, gray = 215 },
    ['Grave Moss'] = { skill = 182, req = 120, yellow = 145, green = 170, gray = 220 },
    ['Kingsblood'] = { skill = 182, req = 125, yellow = 150, green = 175, gray = 225 },
    ['Liferoot'] = { skill = 182, req = 150, yellow = 175, green = 200, gray = 250 },
    ['Fadeleaf'] = { skill = 182, req = 160, yellow = 185, green = 210, gray = 260 },
    ['Goldthorn'] = { skill = 182, req = 170, yellow = 195, green = 220, gray = 270 },
    ['Khadgar\'s Whisker'] = { skill = 182, req = 185, yellow = 210, green = 235, gray = 285 },
    ['Dragon\'s Teeth'] = { skill = 182, req = 195, yellow = 220, green = 245, gray = 295 },
    ['Firebloom'] = { skill = 182, req = 205, yellow = 230, green = 255, gray = 305 },
    ['Purple Lotus'] = { skill = 182, req = 210, yellow = 235, green = 260, gray = 310 },
    ['Arthas\' Tears'] = { skill = 182, req = 220, yellow = 245, green = 270, gray = 320 },
    ['Sungrass'] = { skill = 182, req = 230, yellow = 255, green = 280, gray = 330 },
    ['Blindweed'] = { skill = 182, req = 235, yellow = 260, green = 285, gray = 335 },
    ['Ghost Mushroom'] = { skill = 182, req = 245, yellow = 270, green = 295, gray = 345 },
    ['Gromsblood'] = { skill = 182, req = 250, yellow = 275, green = 300, gray = 350 },
    ['Golden Sansam'] = { skill = 182, req = 260, yellow = 285, green = 310, gray = 360 },
    ['Dreamfoil'] = { skill = 182, req = 270, yellow = 295, green = 320, gray = 370 },
    ['Mountain Silversage'] = { skill = 182, req = 280, yellow = 305, green = 330, gray = 380 },
    ['Sorrowmoss'] = { skill = 182, req = 285, yellow = 310, green = 335, gray = 385 },
    ['Icecap'] = { skill = 182, req = 290, yellow = 315, green = 340, gray = 390 },
    ['Black Lotus'] = { skill = 182, req = 300, yellow = 325, green = 350, gray = 400 },
    ['Felweed'] = { skill = 182, req = 300, yellow = 325, green = 350, gray = 400 },
    ['Dreaming Glory'] = { skill = 182, req = 315, yellow = 340, green = 365, gray = 415 },
    ['Ragveil'] = { skill = 182, req = 325, yellow = 350, green = 375, gray = 425 },
    ['Terocone'] = { skill = 182, req = 325, yellow = 350, green = 375, gray = 425 },
    ['Flame Cap'] = { skill = 182, req = 335, yellow = 360, green = 385, gray = 435 },
    ['Ancient Lichen'] = { skill = 182, req = 340, yellow = 365, green = 390, gray = 440 },
    ['Netherbloom'] = { skill = 182, req = 350, yellow = 375, green = 400, gray = 450 },
    ['Netherdust Bush'] = { skill = 182, req = 350, yellow = 375, green = 400, gray = 450 },
    ['Nightmare Vine'] = { skill = 182, req = 365, yellow = 390, green = 415, gray = 465 },
    ['Mana Thistle'] = { skill = 182, req = 375, yellow = 400, green = 425, gray = 475 },
    ['Goldclover'] = { skill = 182, req = 350, yellow = 375, green = 400, gray = 450 },
    ['Firethorn'] = { skill = 182, req = 360, yellow = 385, green = 410, gray = 460 },
    ['Tiger Lily'] = { skill = 182, req = 375, yellow = 400, green = 425, gray = 475 },
    ['Talandra\'s Rose'] = { skill = 182, req = 385, yellow = 410, green = 435, gray = 485 },
    ['Adder\'s Tongue'] = { skill = 182, req = 400, yellow = 425, green = 450, gray = 500 },
    ['Frozen Herb'] = { skill = 182, req = 400, yellow = 425, green = 450, gray = 500 },
    ['Lichbloom'] = { skill = 182, req = 425, yellow = 450, green = 475, gray = 525 },
    ['Icethorn'] = { skill = 182, req = 435, yellow = 460, green = 485, gray = 535 },
    ['Frost Lotus'] = { skill = 182, req = 450, yellow = 475, green = 500, gray = 550 },
    ['Cinderbloom'] = { skill = 182, req = 425, yellow = 450, green = 475, gray = 525 },
    ['Stormvine'] = { skill = 182, req = 425, yellow = 450, green = 475, gray = 525 },
    ['Azshara\'s Veil'] = { skill = 182, req = 425, yellow = 450, green = 475, gray = 525 },
    ['Heartblossom'] = { skill = 182, req = 475, yellow = 500, green = 525, gray = 575 },
    ['Whiptail'] = { skill = 182, req = 500, yellow = 525, green = 550, gray = 600 },
    ['Twilight Jasmine'] = { skill = 182, req = 525, yellow = 550, green = 575, gray = 625 },
    -- Mining (186)
    ['Copper Vein'] = { skill = 186, req = 1, yellow = 26, green = 51, gray = 101 },
    ['Tin Vein'] = { skill = 186, req = 65, yellow = 90, green = 115, gray = 165 },
    ['Incendicite Mineral Vein'] = { skill = 186, req = 65, yellow = 90, green = 115, gray = 165 },
    ['Silver Vein'] = { skill = 186, req = 75, yellow = 100, green = 125, gray = 175 },
    ['Ooze Covered Silver Vein'] = { skill = 186, req = 75, yellow = 100, green = 125, gray = 175 },
    ['Lesser Bloodstone Deposit'] = { skill = 186, req = 75, yellow = 100, green = 125, gray = 175 },
    ['Iron Deposit'] = { skill = 186, req = 125, yellow = 150, green = 175, gray = 225 },
    ['Indurium Mineral Vein'] = { skill = 186, req = 150, yellow = 175, green = 200, gray = 250 },
    ['Gold Vein'] = { skill = 186, req = 155, yellow = 180, green = 205, gray = 255 },
    ['Ooze Covered Gold Vein'] = { skill = 186, req = 155, yellow = 180, green = 205, gray = 255 },
    ['Mithril Deposit'] = { skill = 186, req = 175, yellow = 200, green = 225, gray = 275 },
    ['Ooze Covered Mithril Deposit'] = { skill = 186, req = 175, yellow = 200, green = 225, gray = 275 },
    ['Truesilver Deposit'] = { skill = 186, req = 230, yellow = 255, green = 280, gray = 330 },
    ['Ooze Covered Truesilver Deposit'] = { skill = 186, req = 230, yellow = 255, green = 280, gray = 330 },
    ['Dark Iron Deposit'] = { skill = 186, req = 230, yellow = 255, green = 280, gray = 330 },
    ['Small Thorium Vein'] = { skill = 186, req = 245, yellow = 270, green = 295, gray = 345 },
    ['Ooze Covered Thorium Vein'] = { skill = 186, req = 245, yellow = 270, green = 295, gray = 345 },
    ['Rich Thorium Vein'] = { skill = 186, req = 275, yellow = 300, green = 325, gray = 375 },
    ['Ooze Covered Rich Thorium Vein'] = { skill = 186, req = 275, yellow = 300, green = 325, gray = 375 },
    ['Hakkari Thorium Vein'] = { skill = 186, req = 275, yellow = 300, green = 325, gray = 375 },
    ['Small Obsidian Chunk'] = { skill = 186, req = 305, yellow = 330, green = 355, gray = 405 },
    ['Large Obsidian Chunk'] = { skill = 186, req = 305, yellow = 330, green = 355, gray = 405 },
    ['Fel Iron Deposit'] = { skill = 186, req = 300, yellow = 325, green = 350, gray = 400 },
    ['Nethercite Deposit'] = { skill = 186, req = 275, yellow = 300, green = 325, gray = 375 },
    ['Adamantite Deposit'] = { skill = 186, req = 325, yellow = 350, green = 375, gray = 425 },
    ['Rich Adamantite Deposit'] = { skill = 186, req = 350, yellow = 375, green = 400, gray = 450 },
    ['Khorium Vein'] = { skill = 186, req = 375, yellow = 400, green = 425, gray = 475 },
    ['Ancient Gem Vein'] = { skill = 186, req = 375, yellow = 400, green = 425, gray = 475 },
    ['Cobalt Deposit'] = { skill = 186, req = 350, yellow = 375, green = 400, gray = 450 },
    ['Rich Cobalt Deposit'] = { skill = 186, req = 375, yellow = 400, green = 425, gray = 475 },
    ['Saronite Deposit'] = { skill = 186, req = 400, yellow = 425, green = 450, gray = 500 },
    ['Rich Saronite Deposit'] = { skill = 186, req = 425, yellow = 450, green = 475, gray = 525 },
    ['Pure Saronite Deposit'] = { skill = 186, req = 450, yellow = 475, green = 500, gray = 550 },
    ['Titanium Vein'] = { skill = 186, req = 450, yellow = 475, green = 500, gray = 550 },
    ['Obsidium Deposit'] = { skill = 186, req = 425, yellow = 450, green = 475, gray = 525 },
    ['Rich Obsidium Deposit'] = { skill = 186, req = 450, yellow = 475, green = 500, gray = 550 },
    ['Elementium Vein'] = { skill = 186, req = 475, yellow = 500, green = 525, gray = 575 },
    ['Rich Elementium Vein'] = { skill = 186, req = 500, yellow = 525, green = 550, gray = 600 },
    ['Pyrite Deposit'] = { skill = 186, req = 525, yellow = 550, green = 575, gray = 625 },
    ['Rich Pyrite Deposit'] = { skill = 186, req = 525, yellow = 550, green = 575, gray = 625 },
    -- Pandaria (world DB)
    ['Green Tea Leaf'] = { skill = 182, req = 1, yellow = 525, green = 550, gray = 575 },
    ['Rain Poppy'] = { skill = 182, req = 1, yellow = 550, green = 575, gray = 600 },
    ['Silkweed'] = { skill = 182, req = 1, yellow = 570, green = 595, gray = 620 },
    ['Sha-Touched Herb'] = { skill = 182, req = 1, yellow = 575, green = 600, gray = 625 },
    ['Snow Lily'] = { skill = 182, req = 1, yellow = 600, green = 615, gray = 630 },
    ['Fool\'s Cap'] = { skill = 182, req = 1, yellow = 600, green = 615, gray = 630 },
    ['Golden Lotus'] = { skill = 182, req = 1, yellow = 600, green = 615, gray = 630 },
    ['Ghost Iron Deposit'] = { skill = 186, req = 1, yellow = 550, green = 600, gray = 650 },
    ['Rich Ghost Iron Deposit'] = { skill = 186, req = 1, yellow = 575, green = 600, gray = 625 },
    ['Kyparite Deposit'] = { skill = 186, req = 1, yellow = 600, green = 615, gray = 630 },
    ['Rich Kyparite Deposit'] = { skill = 186, req = 1, yellow = 600, green = 615, gray = 630 },
    ['Trillium Vein'] = { skill = 186, req = 1, yellow = 600, green = 615, gray = 630 },
    ['Rich Trillium Vein'] = { skill = 186, req = 1, yellow = 605, green = 620, gray = 635 },
}

local COLORS = {
    red    = { 1.00, 0.10, 0.10 },
    orange = { 1.00, 0.50, 0.25 },
    yellow = { 1.00, 1.00, 0.00 },
    green  = { 0.25, 0.75, 0.25 },
    gray   = { 0.50, 0.50, 0.50 },
}

local function DifficultyColor(skill, yellow, green, gray)
    if skill >= gray then
        return COLORS.gray
    elseif skill >= green then
        return COLORS.green
    elseif skill >= yellow then
        return COLORS.yellow
    end
    return COLORS.orange
end

-- True when the client already handles this skill (it is one of the 2 Professions-tab slots).
local function IsShownNatively(skillLine)
    local prof1, prof2 = GetProfessions()
    for _, index in pairs({ prof1, prof2 }) do
        if select(7, GetProfessionInfo(index)) == skillLine then
            return true
        end
    end
    return false
end

-- Required skill to skin (or herb/mine) a corpse, by creature level. Same formula as the core
-- (Spell::CheckCast, SPELL_EFFECT_SKINNING).
local function CorpseRequiredSkill(level)
    if level < 10 then return 0
    elseif level < 20 then return (level - 10) * 10
    elseif level < 74 then return level * 5
    elseif level < 80 then return (level * 2 - 73) * 5
    elseif level < 85 then return level * 5 + 35
    elseif level < 88 then return level * 5 + 35 + (level - 84) * 10
    end
    return level * 5 + 35 + (level - 85) * 15
end

local function TooltipLine(index)
    return _G["GameTooltipTextLeft" .. index]
end

-- What we last worked out for the node tooltip on screen, so the per-frame re-apply stays cheap.
local nodeTip = {}

local function ColorNodeTooltip(tooltip)
    if tooltip:GetUnit() then
        return
    end
    local title = TooltipLine(1) and TooltipLine(1):GetText()
    if not title then
        return
    end
    if nodeTip.title ~= title then
        nodeTip.title, nodeTip.line, nodeTip.text, nodeTip.color = title, nil, nil, nil
        local node = NODES[strtrim(title)]
        if not node or IsShownNatively(node.skill) then
            return
        end
        local skillName, skill = SkillInfo(node.skill)
        if not skill then
            return
        end
        for i = 2, tooltip:NumLines() do
            local text = TooltipLine(i) and TooltipLine(i):GetText()
            if text and text:find(skillName, 1, true) then
                -- The client prints a placeholder 1 for unslotted professions; show the real requirement.
                nodeTip.line = i
                nodeTip.text = text:gsub("%d+$", tostring(node.req))
                if skill < node.req then
                    nodeTip.color = COLORS.red
                else
                    nodeTip.color = DifficultyColor(skill, node.yellow, node.green, node.gray)
                end
                break
            end
        end
    end
    -- Re-applied every frame: the client may repaint the line after OnShow.
    local line = nodeTip.line and TooltipLine(nodeTip.line)
    if line then
        line:SetTextColor(unpack(nodeTip.color))
        if line:GetText() ~= nodeTip.text then
            line:SetText(nodeTip.text)
            -- The tooltip was sized for the client's "1"; Show() on a shown tooltip re-fits its width.
            tooltip:Show()
        end
    end
end

local function ResetNodeTooltip()
    nodeTip.title = nil
end

local CORPSE_LINES = {
    [UNIT_SKINNABLE_LEATHER or "Skinnable"] = SKINNING,
    [UNIT_SKINNABLE_HERB or "Requires Herbalism"] = HERBALISM,
    [UNIT_SKINNABLE_ROCK or "Requires Mining"] = MINING,
}

local function ColorCorpseTooltip(tooltip)
    local _, unit = tooltip:GetUnit()
    if not unit or not UnitIsDead(unit) then
        return
    end
    for i = 2, tooltip:NumLines() do
        local line = TooltipLine(i)
        local skillLine = line and CORPSE_LINES[line:GetText() or ""]
        if skillLine and not IsShownNatively(skillLine) then
            local _, skill = SkillInfo(skillLine)
            if skill then
                local required = CorpseRequiredSkill(UnitLevel(unit))
                if skill < required then
                    line:SetTextColor(unpack(COLORS.red))
                else
                    line:SetTextColor(unpack(DifficultyColor(skill, required + 25, required + 50, required + 100)))
                end
            end
            return
        end
    end
end

GameTooltip:HookScript("OnShow", ColorNodeTooltip)
GameTooltip:HookScript("OnUpdate", ColorNodeTooltip)
GameTooltip:HookScript("OnHide", ResetNodeTooltip)
GameTooltip:HookScript("OnTooltipSetUnit", ColorCorpseTooltip)

---------------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("LEARNED_SPELL_IN_TAB")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "ZRProfessions" then
            CreatePanel()
            AddSpellbookButton()
            -- The trainer UI is load-on-demand; it may already be loaded if another addon pulled it in.
            if IsAddOnLoaded("Blizzard_TrainerUI") then
                HookTrainerUI()
            end
        elseif arg1 == "Blizzard_TrainerUI" then
            HookTrainerUI()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Hide before combat lockdown starts; the panel holds secure buttons and can't be hidden during it.
        if panel and panel:IsShown() then
            panel:Hide()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if refreshPending and panel and panel:IsShown() then
            RefreshPanel()
        end
    elseif panel and panel:IsShown() then
        RefreshPanel()
    end
end)
