--- ============================ HEADER ============================
--- ======= LOCALIZE =======
-- Addon
local addonName, addonTable = ...
-- HeroDBC
local DBC         = HeroDBC.DBC
-- HeroLib
local HL          = HeroLib
local Cache       = HeroCache
local Unit        = HL.Unit
local Player      = Unit.Player
local Pet         = Unit.Pet
local Target      = Unit.Target
local Spell       = HL.Spell
local MultiSpell  = HL.MultiSpell
local Item        = HL.Item
-- HeroRotation
local HR          = HeroRotation
local AoEON       = HR.AoEON
local CDsON       = HR.CDsON
local Cast        = HR.Cast
local CastPooling = HR.CastPooling
-- Num/Bool Helper Functions
local num         = HR.Commons.Everyone.num
local bool        = HR.Commons.Everyone.bool
-- lua
local mathmax     = math.max
-- WoW API
local Delay       = C_Timer.After

--- ============================ CONTENT ============================
--- ======= APL LOCALS =======
-- Define S/I for spell and item arrays
local S = Spell.Druid.Restoration
local I = Item.Druid.Restoration

-- Create table to exclude above trinkets from On Use function
local OnUseExcludes = {
  I.SpymastersWeb:ID(),
}

--- ===== GUI Settings =====
local Everyone = HR.Commons.Everyone
local Druid = HR.Commons.Druid
local Settings = {
  General = HR.GUISettings.General,
  Commons = HR.GUISettings.APL.Druid.Commons,
  CommonsDS = HR.GUISettings.APL.Druid.CommonsDS,
  CommonsOGCD = HR.GUISettings.APL.Druid.CommonsOGCD,
  Restoration = HR.GUISettings.APL.Druid.Restoration
}

--- ===== Rotation Variables =====
local IsInSpellRange = false
local IsInMeleeRange = false
local Enemies10ySplash, EnemiesCount10ySplash, EnemiesMelee, Enemies8y
local BossFightRemains = 11111
local FightRemains = 11111

--- ===== Trinket Variables =====
local Trinket1, Trinket2
local VarTrinket1ID, VarTrinket2ID
local VarTrinket1Level, VarTrinket2Level
local VarTrinket1Spell, VarTrinket2Spell
local VarTrinket1Range, VarTrinket2Range
local VarTrinket1CastTime, VarTrinket2CastTime
local VarTrinket1CD, VarTrinket2CD
local VarTrinket1Ex, VarTrinket2Ex
local VarOnUseTrinket
local VarTrinketFailures = 0
local function SetTrinketVariables()
  local T1, T2 = Player:GetTrinketData(OnUseExcludes)

  -- If we don't have trinket items, try again in 5 seconds.
  if VarTrinketFailures < 5 and ((T1.ID == 0 or T2.ID == 0) or (T1.Level == 0 or T2.Level == 0) or (T1.SpellID > 0 and not T1.Usable or T2.SpellID > 0 and not T2.Usable)) then
    VarTrinketFailures = VarTrinketFailures + 1
    Delay(5, function()
        SetTrinketVariables()
      end
    )
    return
  end

  Trinket1 = T1.Object
  Trinket2 = T2.Object

  VarTrinket1ID = T1.ID
  VarTrinket2ID = T2.ID

  VarTrinket1Level = T1.Level
  VarTrinket2Level = T2.Level

  VarTrinket1Spell = T1.Spell
  VarTrinket1Range = T1.Range
  VarTrinket1CastTime = T1.CastTime
  VarTrinket2Spell = T2.Spell
  VarTrinket2Range = T2.Range
  VarTrinket2CastTime = T2.CastTime

  VarTrinket1CD = T1.Cooldown
  VarTrinket2CD = T2.Cooldown

  VarTrinket1Ex = T1.Excluded
  VarTrinket2Ex = T2.Excluded

  local T1Test = num(Trinket1:HasUseBuff() and VarTrinket1ID ~= I.OvinaxsMercurialEgg:ID())
  local T2Test = num(Trinket2:HasUseBuff() and VarTrinket2ID ~= I.OvinaxsMercurialEgg:ID()) * 2
  VarOnUseTrinket = 0 + T1Test + T2Test
end
SetTrinketVariables()

--- ===== Event Registrations =====
HL:RegisterForEvent(function()
  SetTrinketVariables()
end, "PLAYER_EQUIPMENT_CHANGED")

HL:RegisterForEvent(function()
  BossFightRemains = 11111
  FightRemains = 11111
end, "PLAYER_REGEN_ENABLED")

HL:RegisterForEvent(function()
end, "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB")


--- ===== Rotation Functions =====
local function Precombat()
  if S.MarkoftheWild:IsCastable() and Everyone.GroupBuffMissing(S.MarkoftheWildBuff) then
    if Cast(S.MarkoftheWild, Settings.CommonsOGCD.GCDasOffGCD.MarkOfTheWild) then return "mark_of_the_wild precombat"; end
  end

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

local function HealParty()
  if S.Efflorescence:IsCastable() and Player:BuffDown(S.Efflorescence) then
    if Cast(S.Efflorescence) then return "Efflorescence"; end
  end
  if S.GroveGuardians:IsCastable() and S.GroveGuardians:Charges() > 2 then
    if Cast(S.GroveGuardians) then return "Grove Guardians max charges"; end
  end

  --Emergency
  if Target:HealthPercentage() < 30 then
    if S.Swiftmend:IsCastable() and Target:BuffUp(S.Regrowth) then
      if Cast(S.Swiftmend) then return "Swiftmend (Emergency)"; end
    end
    if S.NaturesSwiftness:IsCastable() then
      if Cast(S.NaturesSwiftness) then return "Nature's Swiftness (Emergency)"; end
    end
    if S.Regrowth:IsCastable() then
      if Cast(S.Regrowth) then return "Regrowth (Emergency)"; end
    end
  end

  if S.Lifebloom:IsCastable() and Target:BuffDown(S.Lifebloom) and CountBuff(S.Lifebloom) < 2 then
    if Cast(S.Lifebloom) then return "Lifebloom"; end
  end
  if S.Regrowth:IsCastable() and Target:BuffDown(S.Lifebloom) and Player:BuffUp(S.Clearcasting) then
    if Cast(S.Regrowth) then return "Regrowth (Clearcasting)"; end
  end
  if S.WildGrowth:IsCastable() and CountAlliesBelowPercentHP(75) > 2 then
    if Cast(S.WildGrowth) then return "Wild Growth"; end
  end
  if S.ConvoketheSpirits:IsCastable() and CountAlliesBelowPercentHP(40) > 2 then
    if Cast(S.ConvoketheSpirits) then return "Convoke the Spirits"; end
  end
  if S.Rejuvenation:IsCastable() and Target:BuffDown(S.Rejuvenation) or (CountBuff(S.Rejuvenation) > 4 and Target:BuffDown(S.RejuvenationGermination)) then
    if Cast(S.Rejuvenation) then return "Rejuvenation"; end
  end
  if Target:HealthPercentage() < 60 then
    if S.Regrowth:IsCastable() then
      if Cast(S.Regrowth) then return "Regrowth"; end
    end
  end
end

local function DPS()
  if Player:BuffUp(S.CatForm) then
    if ComboPoints >= 5 then
      if S.Rip:IsReady() and Target:TimeToDie() >= 8 and Target:DebuffDown(S.RipDebuff) then
        if Cast(S.Rip, nil, nil, not IsInMeleeRange) then return "rip"; end
      end
      if S.FerociousBite:IsReady() then
        if CastPooling(S.FerociousBite, Player:EnergyTimeToX(50)) then return "ferocious_bite"; end
      end
    end
    if S.Rake:IsReady() and Target:TimeToDie() >= 10 and (Target:DebuffDown(S.RakeDebuff) or Target:DebuffRemains(S.RakeDebuff) < 4) then
      if Cast(S.Rake, nil, nil, not IsInMeleeRange) then return "rake"; end
    end
    if S.Swipe:IsReady() and EnemiesCount8y >= 5 then
      if Cast(S.Swipe, nil, nil, not IsInMeleeRange) then return "swipe"; end
    end
    if S.Shred:IsReady() then
      if Cast(S.Shred, nil, nil, not IsInMeleeRange) then return "shred"; end
    end
  end
  if Player:BuffDown(S.CatForm) then
    if S.Moonfire:IsReady() and Target:DebuffDown(S.MoonfireDebuff) then
      if Cast(S.Moonfire, nil, nil, not IsInSpellRange) then return "moonfire"; end
    end
    if S.Sunfire:IsReady() and Target:DebuffDown(S.SunfireDebuff) then
      if Cast(S.Sunfire, nil, nil, not IsInSpellRange) then return "sunfire"; end
    end
    if S.GroveGuardians:IsCastable() and S.GroveGuardians:Charges() > 2 then
      if Cast(S.GroveGuardians) then return "Grove Guardians max charges"; end
    end
  end
end

--- ===== APL Main =====
local function APL()
  -- Unit Update
  EnemiesMelee = Player:GetEnemiesInMeleeRange(5)
  Enemies8y = Player:GetEnemiesInMeleeRange(8)
  Enemies10ySplash = Target:GetEnemiesInSplashRange(10)
  if AoEON() then
    EnemiesCount10ySplash = Target:GetEnemiesInSplashRangeCount(10)
    EnemiesCountMelee = #EnemiesMelee
    EnemiesCount8y = #Enemies8y
  else
    EnemiesCount10ySplash = 1
    EnemiesCountMelee = 1
    EnemiesCount8y = 1
  end

  if S.Renewal:IsCastable() and Player:AffectingCombat() and Player:HealthPercentage() < 30 then
    if Cast(S.Renewal) then return "Renewal"; end
  end

  if Everyone.TargetIsValid() or Player:AffectingCombat() then
    -- Calculate fight_remains
    BossFightRemains = HL.BossFightRemains()
    FightRemains = BossFightRemains
    if FightRemains == 11111 then
      FightRemains = HL.FightRemains(Enemies10ySplash, false)
    end

    -- Combo Points
    ComboPoints = Player:ComboPoints()
    ComboPointsDeficit = Player:ComboPointsDeficit()

    -- We use Wrath to check range for a lot of spells, so let's make a variable for it.
    IsInSpellRange = Target:IsSpellInRange(S.Moonfire)
    IsInMeleeRange = Target:IsInRange(5)
  end

  if Everyone.TargetIsValid() then
    -- Precombat
    if not Player:AffectingCombat() and Player:BuffDown(S.TravelForm) then
      local ShouldReturn = Precombat(); if ShouldReturn then return ShouldReturn; end
    end
    
    if Settings.Commons.Enabled.Trinkets then
      -- use_item,name=aberrant_spellforge
      if I.AberrantSpellforge:IsEquippedAndReady() then
        if Cast(I.AberrantSpellforge, Settings.CommonsDS.DisplayStyle.Trinkets) then return "aberrant_spellforge main 2"; end
      end
      -- do_treacherous_transmitter_task,if=cooldown.ca_inc.remains>10|buff.ca_inc.up
      -- TODO
      -- use_item,name=spymasters_web,if=fight_remains<20
      if I.SpymastersWeb:IsEquippedAndReady() and (BossFightRemains < 20) then
        if Cast(I.SpymastersWeb, Settings.CommonsDS.DisplayStyle.Trinkets) then return "spymasters_web main 4"; end
      end
    end
    -- use_items
    if Settings.Commons.Enabled.Items or Settings.Commons.Enabled.Trinkets then
      local ItemToUse, ItemSlot, ItemRange = Player:GetUseableItems(OnUseExcludes)
      if ItemToUse then
        local DisplayStyle = Settings.CommonsDS.DisplayStyle.Trinkets
        if ItemSlot ~= 13 and ItemSlot ~= 14 then DisplayStyle = Settings.CommonsDS.DisplayStyle.Items end
        if ((ItemSlot == 13 or ItemSlot == 14) and Settings.Commons.Enabled.Trinkets) or (ItemSlot ~= 13 and ItemSlot ~= 14 and Settings.Commons.Enabled.Items) then
          if Cast(ItemToUse, nil, DisplayStyle, not Target:IsInRange(ItemRange)) then return "use_items ("..ItemToUse:Name()..") main 14"; end
        end
      end
    end
    local ShouldReturn = DPS(); if ShouldReturn then return "DPS: " .. ShouldReturn; end
    -- Manually added: Pool, if nothing else to do.
    if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool Resources"; end
  end

  if Everyone.TargetIsFriendly() and IsInGroup() then
    ShouldReturn = HealParty()
    if ShouldReturn then return "Heal: " .. ShouldReturn end
  end
end

local function OnInit()
  S.MoonfireDebuff:RegisterAuraTracking()

  HR.Print("First pass Resto Druid")
end

HR.SetAPL(105, APL, OnInit)
