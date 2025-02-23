--- ============================ HEADER ============================
--- ======= LOCALIZE =======
-- Addon
local addonName, addonTable = ...
-- HeroDBC
local DBC                   = HeroDBC.DBC
-- HeroLib
local HL                    = HeroLib
local Cache                 = HeroCache
local Unit                  = HL.Unit
local Player                = Unit.Player
local Target                = Unit.Target
local Pet                   = Unit.Pet
local Spell                 = HL.Spell
local Item                  = HL.Item
-- HeroRotation
local HR                    = HeroRotation
local AoEON                 = HR.AoEON
local CDsON                 = HR.CDsON
local Cast                  = HR.Cast
local CastSuggested         = HR.CastSuggested
-- Num/Bool Helper Functions
local num                   = HR.Commons.Everyone.num
local bool                  = HR.Commons.Everyone.bool
-- lua
local mathmax               = math.max
local mathmin               = math.min

--- ============================ CONTENT ===========================
--- ======= APL LOCALS =======
-- luacheck: max_line_length 9999

-- Define S/I for spell and item arrays
local S = Spell.Priest.Discipline
local I = Item.Priest.Discipline

--- ===== GUI Settings =====
local Everyone = HR.Commons.Everyone
local Settings = {
  General = HR.GUISettings.General,
  Commons = HR.GUISettings.APL.Priest.Commons,
  CommonsDS = HR.GUISettings.APL.Priest.CommonsDS,
  CommonsOGCD = HR.GUISettings.APL.Priest.CommonsOGCD,
  Discipline = HR.GUISettings.APL.Priest.Discipline
}

--- ===== Rotation Variables =====
local Enemies40y, Enemies12y
local Enemies12yCount
local BossFightRemains = 11111
local FightRemains = 11111

--- ===== Event Registrations =====
HL:RegisterForEvent(function()
  BossFightRemains = 11111
  FightRemains = 11111
end, "PLAYER_REGEN_ENABLED")

local function Precombat()
  -- flask
  -- food
  -- augmentation
  -- snapshot_stats
  -- Manually added: Group buff check
  if S.PowerWordFortitude:IsCastable() and Everyone.GroupBuffMissing(S.PowerWordFortitudeBuff) then
    if Cast(S.PowerWordFortitude, Settings.CommonsOGCD.GCDasOffGCD.PowerWordFortitude) then return "power_word_fortitude precombat 2"; end
  end
  local DungeonSlice = Player:IsInDungeonArea()
end

local function CountAlliesBelowPercentHP(Percent)
    local groupType, numMembers
    if IsInRaid() then
        groupType = "raid"
        numMembers = GetNumGroupMembers()
    elseif IsInGroup() then
        groupType = "party"
        numMembers = GetNumGroupMembers()
    else
        return 0 -- Pas dans un groupe ou un raid
    end

    local count = 0
    for i = 1, numMembers do
        local unit = groupType .. i
        if UnitExists(unit) and not UnitIsDeadOrGhost(unit) then
            local healthPercent = (UnitHealth(unit) / UnitHealthMax(unit)) * 100
            if healthPercent < Percent then
                count = count + 1
            end
        end
    end

    -- Vérifie le joueur lui-même dans le cas d'un groupe
    if groupType == "party" and UnitExists("player") and not UnitIsDeadOrGhost("player") then
        local healthPercent = (UnitHealth("player") / UnitHealthMax("player")) * 100
        if healthPercent < Percent then
            count = count + 1
        end
    end

    return count
end

local function CountBuff(Spell)
    local SpellID = Spell.SpellID -- ID du buff
    local SpellName = Spell:Name()
    local playerGUID = UnitGUID("player") -- GUID du joueur
    local count = 0

    -- Déterminer le nombre de membres dans le groupe ou raid
    local groupType = IsInRaid() and "raid" or "party"
    local numMembers = GetNumGroupMembers()

    -- Parcourir les membres du groupe ou raid
    for i = 1, numMembers do
        local unitID = (groupType == "raid" and "raid" or "party") .. i
        if not UnitExists(unitID) then
            unitID = "player" -- Pour le joueur lui-même dans un groupe
        end
        -- Vérifier les buffs de l'unité
            --local name = UnitAura(unitID, j, "HELPFUL", "PLAYER")
            local name = AuraUtil.FindAuraByName(SpellName, unitID, "HELPFUL", "PLAYER")
            if name then
                count = count + 1
            end
    end

    return count
end

local function DPS()
  if S.PurgetheWicked:IsCastable() and (Target:DebuffDown(S.PurgetheWicked) or Target:DebuffRemains(S.PurgetheWicked) < 7) then
    if Cast(S.PurgetheWicked, nil, nil, not Target:IsSpellInRange(S.PurgetheWicked)) then return "purge_the_wicked"; end
  end
  if S.MindBlast:IsCastable() then
    if Cast(S.MindBlast, nil, nil, not Target:IsSpellInRange(S.MindBlast)) then return "mind_blast"; end
  end
  if S.Penance:IsCastable() then
    if Cast(S.Penance, nil, nil, not Target:IsSpellInRange(S.Penance)) then return "penance"; end
  end
  if S.ShadowWordDeath:IsCastable() then
    if Cast(S.ShadowWordDeath, nil, nil, not Target:IsSpellInRange(S.ShadowWordDeath)) then return "shadow_word_death"; end
  end
  if S.Smite:IsCastable() then
    if Cast(S.Smite, nil, nil, not Target:IsSpellInRange(S.Smite)) then return "smite"; end
  end
end

local function HPS()
  if S.PowerWordShield:IsCastable() and Target:BuffDown(S.PowerWordShield) then
    if Cast(S.PowerWordShield) then return "power_word_shield"; end
  end
  if S.FlashHeal:IsCastable() and Target:BuffDown(S.Atonement) and CountBuff(S.Atonement) < 4 then
    if Cast(S.FlashHeal) then return "flash_heal"; end
  end
  if S.FlashHeal:IsCastable() and Target:HealthPercentage() < 50 then
    if Cast(S.FlashHeal) then return "flash_heal"; end
  end
end

--- ======= ACTION LISTS =======
local function APL()
  Enemies40y = Player:GetEnemiesInRange(40) -- Multiple CastCycle Spells
  Enemies12y = Player:GetEnemiesInRange(12)
  if AoEON() then
    Enemies12yCount = #Enemies12y
  else
    Enemies12yCount = 1
  end

  if Everyone.TargetIsValid() or Player:AffectingCombat() then
    -- Calculate fight_remains
    BossFightRemains = HL.BossFightRemains()
    FightRemains = BossFightRemains
    if FightRemains == 11111 then
      FightRemains = HL.FightRemains(Enemies10ySplash, false)
    end
  end

  if Everyone.TargetIsValid() then
    -- call precombat
    if not Player:AffectingCombat() then
      local ShouldReturn = Precombat(); if ShouldReturn then return ShouldReturn; end
    end
    -- Interrupts
    local ShouldReturn = Everyone.Interrupt(S.Silence, Settings.CommonsDS.DisplayStyle.Interrupts);
    if ShouldReturn then return ShouldReturn; end
    -- run_action_list,name=main
    local ShouldReturn = DPS(); if ShouldReturn then return "DPS: " .. ShouldReturn; end
    -- Manually added: Pool, if nothing else to do.
    if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool Resources"; end
  end

  --and IsInGroup()
  if Everyone.TargetIsFriendly() then
    ShouldReturn = HPS(); if ShouldReturn then return "Heal: " .. ShouldReturn; end
  end
end

local function Init()
  HR.Print("First pass on discipline priest")
end

HR.SetAPL(256, APL, Init)
