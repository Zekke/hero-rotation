--- ============================ HEADER ============================
--- ======= LOCALIZE =======
-- Addon
local addonName, addonTable = ...
-- HeroDBC
local DBC        = HeroDBC.DBC
-- HeroLib
local HL         = HeroLib
local Cache      = HeroCache
local Unit       = HL.Unit
local Player     = Unit.Player
local Target     = Unit.Target
local Pet        = Unit.Pet
local Spell      = HL.Spell
local MultiSpell = HL.MultiSpell
local Item       = HL.Item
-- HeroRotation
local HR         = HeroRotation
local AoEON      = HR.AoEON
local CDsON      = HR.CDsON
local Cast       = HR.Cast
-- Num/Bool Helper Functions
local num        = HR.Commons.Everyone.num
local bool       = HR.Commons.Everyone.bool
-- Lua

--- ============================ CONTENT ===========================
--- ======= APL LOCALS =======
-- luacheck: max_line_length 9999

-- Spells
local S = Spell.Monk.Mistweaver
local I = Item.Monk.Mistweaver

-- Create table to exclude above trinkets from On Use function
local OnUseExcludes = {
  -- I.TrinketName:ID(),
}

-- Rotation Var
local Enemies5y
local Enemies8y
local EnemiesCount8
local ShouldReturn
local Stuns = {
  { S.LegSweep, "Cast Leg Sweep (Stun)", function () return true end },
  { S.Paralysis, "Cast Paralysis (Stun)", function () return true end },
}

-- GUI Settings
local Everyone = HR.Commons.Everyone
local Monk = HR.Commons.Monk
local Settings = {
  General    = HR.GUISettings.General,
  Commons    = HR.GUISettings.APL.Monk.Commons,
  Mistweaver = HR.GUISettings.APL.Monk.Mistweaver
}

local function UseItems()
  -- use_items
  local TrinketToUse = Player:GetUseableTrinkets(OnUseExcludes)
  if TrinketToUse then
    if Cast(TrinketToUse, nil, Settings.Commons.DisplayStyle.Trinkets) then return "Generic use_items for " .. TrinketToUse:Name(); end
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

local function IsJadeSerpentStatueSummoned()
    -- Nom de la Statue du Serpent de Jade en anglais, ajustez en fonction de la langue du client WoW si nécessaire
    local jadeSerpentStatueName = "Jade Serpent Statue"

    -- Parcourir les familiers du joueur
    for i = 1, 5 do
        local unit = "statue" .. i
        if UnitExists(unit) and UnitName(unit) == jadeSerpentStatueName then
            return true
        end
    end

    return false
end

local function DPS()
    if S.SheilunsGift:IsCastable() and S.SheilunsGift:IsReady() and CountAlliesBelowPercentHP(50) >= 2 then
      if Cast(S.SheilunsGift) then return "Sheilun's Gift"; end
    end
    if S.TouchofDeath:CooldownUp() and ((S.ImpTouchofDeath:IsAvailable() and Target:HealthPercentage() <= 15) or (Target:Health() < Player:Health())) then
      if Cast(S.TouchofDeath, nil, nil, not Target:IsInRange(5)) then return "Touch of Death"; end
    end
    --1) Summon White Tiger Statue => si SWTS Talented + ennemies > 1
    if S.SummonWhiteTigerStatue:IsCastable() and EnemiesCount8 > 1 then
      if Cast(S.SummonWhiteTigerStatue, Settings.CommonsOGCD.GCDasOffGCD.SummonWhiteTigerStatue, nil, not Target:IsInRange(40)) then return "Summon White Tiger Statue"; end
    end
    --2) SUGGEST (ou cast sur sois meme ?) Zen Pulse => Zen Pulse talented + ennemies > 3
    if S.ZenPulse:IsCastable() and EnemiesCount8 > 3 then
      if Cast(S.ZenPulse) then return "Zen Pulse"; end
    end
    if S.AncientConcordance:IsAvailable() and EnemiesCount8 >= 3 and Player:BuffUp(S.AncientConcordanceBuff) then
        --3) Blackout Kick => si Ancient Concordance talented + buff Jadefire Stomp + ennemies >= 3
        if S.BlackoutKick:IsCastable() then
            if Cast(S.BlackoutKick, nil, nil, not Target:IsInRange(5)) then return "Blackout Kick (AoE)"; end
        end
        --4) Tiger Palm => si Teachings of the Monastery talented + Blackout kick en cd
        if S.TigerPalm:IsCastable() and S.TeachingsoftheMonastery:IsAvailable() then
            if Cast(S.TigerPalm, nil, nil, not Target:IsInRange(5)) then return "Tiger Palm (AoE)"; end
        end
    end
    --5) Spinning Crane Kick => ennemies >= 5
    if S.SpinningCraneKick:IsCastable() and EnemiesCount8 >= 5 then
      if Cast(S.SpinningCraneKick) then return "Spinning Crane Kick (5+)"; end
    end
    --6) Jadefire stomp => Jadefire stomp talented
    if CDsON() and S.JadefireStomp:IsCastable() and Player:BuffDown(S.JadefireStomp) then
      if Cast(S.JadefireStomp, nil, nil, not Target:IsInRange(30)) then return "Jadefire Stomp"; end
    end
    if S.EssenceFont:IsCastable() and S.AncientTeachings:IsAvailable() and Player:BuffDown(S.AncientTeachingsBuff) then
      if Cast(S.EssenceFont) then return "Essence Font"; end
    end
    --7) Spinning Crane kick => ennemies >= 3
    if S.SpinningCraneKick:IsCastable() and EnemiesCount8 >= 3 then
      if Cast(S.SpinningCraneKick) then return "Spinning Crane Kick (3+)"; end
    end
    --8) Rising Sun kick
    if S.RisingSunKick:IsCastable() then
      if S.ThunderFocusTea:IsCastable() and S.ThunderFocusTea:IsReady() then
        if Cast(S.ThunderFocusTea) then return "Thunder Focus Tea (Rising Sun Kick)"; end
      end
      if Cast(S.RisingSunKick, nil, nil, not Target:IsInRange(5)) then return "Rising Sun Kick"; end
    end
    --9) Spinning Crane Kick => ennemies > 1
    if S.SpinningCraneKick:IsCastable() and EnemiesCount8 > 1 then
      if Cast(S.SpinningCraneKick) then return "Spinning Crane Kick (1+)"; end
    end
    --10) Blackout Kick
    if S.BlackoutKick:IsCastable() then
      if Cast(S.BlackoutKick, nil, nil, not Target:IsInRange(5)) then return "Blackout Kick"; end
    end
    --11) Tiger Palm
    if S.TigerPalm:IsCastable() then
      if Cast(S.TigerPalm, nil, nil, not Target:IsInRange(5)) then return "Tiger Palm"; end
    end
end

local function YulonTheJadeSerpent()
  if S.RenewingMist:IsCastable() and S.RenewingMist:Charges() > 0  and not Player:IsChanneling(S.SoothingMist) then
    if Cast(S.RenewingMist) then return "Renewing Mist"; end
  end
  if Player:BuffStack(S.ManaTeaBuff) > 2 and Player:BuffDown(S.ManaTeaBuffCost) then
    --if Cast(S.ManaTea) then return "Mana Tea"; end
  end
  if S.InvokeYulonTheJadeSerpent:IsCastable() then
    if Cast(S.InvokeYulonTheJadeSerpent) then return "Invoke Yulon, the Jade Serpent"; end
  end
  if Target:BuffUp(S.ChiHarmony) or Target:BuffDown(S.ChiHarmony) then
    if S.EnvelopingMist:IsCastable() and Player:IsChanneling(S.SoothingMist) then
      if Cast(S.EnvelopingMist) then return "Enveloping Mist"; end
    end
    if S.SoothingMist:IsCastable() and not Player:IsChanneling(S.SoothingMist) then
      if Cast(S.SoothingMist) then return "Soothing Mist"; end
    end
  end
end

local function Heal()
  if Player:BuffUp(S.VivaciousVivification) and Target:HealthPercentage() < 35 and Player:BuffDown(S.YulonsBlessing) then
    if S.ThunderFocusTea:IsCastable() and S.ThunderFocusTea:IsReady() then
      if Cast(S.ThunderFocusTea) then return "Thunder Focus Tea (Vivify emergency)"; end
    end
    if S.Vivify:IsCastable() then
      if Cast(S.Vivify) then return "Vivify emergency"; end
    end
  end
  if S.SummonJadeSerpentStatue:IsCastable() and S.SummonJadeSerpentStatue:TimeSinceLastCast() > 90 then
    if Cast(S.SummonJadeSerpentStatue) then return "Summon Jade Serpent Statue"; end
  end
  if CDsON() and S.InvokeYulonTheJadeSerpent:IsAvailable() and (S.InvokeYulonTheJadeSerpent:IsReady() or Player:BuffUp(S.YulonsBlessing)) and IsInRaid() then
    ShouldReturn = YulonTheJadeSerpent();
    if ShouldReturn then return "Yulon: " .. ShouldReturn end;
  end
  if S.RenewingMist:IsCastable() and S.RenewingMist:Charges() > 0 and not Player:IsChanneling(S.SoothingMist) then
    if S.ThunderFocusTea:IsCastable() and S.ThunderFocusTea:IsReady() and S.SecretInfusion:IsAvailable() and not IsInRaid() then
      if Cast(S.ThunderFocusTea) then return "Thunder Focus Tea (Renewing Mist)"; end
    end
    if Cast(S.RenewingMist) then return "Renewing Mist"; end
  end
  if Player:IsChanneling(S.SoothingMist) and Target:BuffUp(S.EnvelopingMist) and Target:BuffUp(S.SoothingMist) then
    if Cast(S.PoolEnergy) then return "Channeling Soothing Mist"; end
  end
  if S.EnvelopingMist:IsCastable() and Target:BuffDown(S.EnvelopingMist) and Player:IsChanneling(S.SoothingMist) then
    if S.ThunderFocusTea:IsCastable() and S.ThunderFocusTea:IsReady() and S.SecretInfusion:IsAvailable() and IsInRaid() then
      if Cast(S.ThunderFocusTea) then return "Thunder Focus Tea (Enveloping Mist)"; end
    end
    if Cast(S.EnvelopingMist) then return "Enveloping Mist"; end
  end
  if S.Vivify:IsCastable() and Player:IsChanneling(S.SoothingMist) and Target:HealthPercentage() < 75 then
    if S.ThunderFocusTea:IsCastable() and S.ThunderFocusTea:IsReady() and not S.SecretInfusion:IsAvailable() then
      if Cast(S.ThunderFocusTea) then return "Thunder Focus Tea (Soothing Mist channeling)"; end
    end
    if S.Vivify:IsCastable() then
      if Cast(S.Vivify) then return "Vivify (Soothing Mist Channeling)"; end
    end
  end
  if S.SoothingMist:IsCastable() and CountAlliesBelowPercentHP(75) > 1 and IsInRaid() then
    if Cast(S.SoothingMist) then return "Soothing Mist AoE"; end
  end
  if S.ExpelHarm:IsCastable() and Player:BuffUp(S.ChiHarmony) and Player:HealthPercentage() < 75 then
    if Cast(S.ExpelHarm) then return "Expel Harm (Chi Harmony)"; end
  end
  if S.SheilunsGift:IsCastable() and S.SheilunsGift:IsReady() and CountAlliesBelowPercentHP(80) >= 2 and not IsInRaid() then
    if Cast(S.SheilunsGift) then return "Sheilun's Gift"; end
  end
  if S.EssenceFont:IsCastable() and S.AncientTeachings:IsAvailable() and Player:BuffDown(S.AncientTeachingsBuff) then
    if S.ThunderFocusTea:IsCastable() and S.ThunderFocusTea:IsReady() and S.SecretInfusion:IsAvailable() and not IsInRaid() then
      if Cast(S.ThunderFocusTea) then return "Thunder Focus Tea (Essence Font)"; end
    end
    if Cast(S.EssenceFont) then return "Essence Font"; end
  end
  if S.SoothingMist:IsCastable() and CountAlliesBelowPercentHP(75) < 2 then
    if Cast(S.SoothingMist) then return "Soothing Mist ST"; end
  end
end

--- ======= ACTION LISTS =======
local function APL()
  -- Unit Update
  Enemies5y = Player:GetEnemiesInMeleeRange(5) -- Multiple Abilities
  Enemies8y = Player:GetEnemiesInMeleeRange(8) -- Multiple Abilities
  if AoEON() then
    EnemiesCount8 = #Enemies8y -- AOE Toogle
  else
    EnemiesCount8 = 1
  end

  --- In Combat
  if Everyone.TargetIsValid() then
    -- Defensives
    --local ShouldReturn = Defensives(); if ShouldReturn then return ShouldReturn; end
    -- use_items
    ShouldReturn = DPS()
    if ShouldReturn then return "DPS: " .. ShouldReturn end
    -- Manually added Pool filler
    if Cast(S.PoolEnergy) then return "Pool Energy"; end
  end
  if Everyone.TargetIsFriendly() and Target:HealthPercentage() < 100 then
    ShouldReturn = Heal()
    if ShouldReturn then return "Heal: " .. ShouldReturn end
    -- Manually added Pool filler
    if Cast(S.PoolEnergy) then return "Pool Energy"; end
  end
end

local function Init()
  HR.Print("Mistweaver Monk rotation has not been updated for pre-patch 10.0. It may not function properly or may cause errors in-game.")
end

HR.SetAPL(270, APL, Init)
