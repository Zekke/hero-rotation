--- ============================ HEADER ============================
--- ======= LOCALIZE =======
-- Addon
local addonName, addonTable = ...
-- HeroDBC
local DBC = HeroDBC.DBC
-- HeroLib
local HL            = HeroLib
local Cache         = HeroCache
local Unit          = HL.Unit
local Player        = Unit.Player
local Target        = Unit.Target
local Pet           = Unit.Pet
local Spell         = HL.Spell
local Item          = HL.Item
-- HeroRotation
local HR            = HeroRotation
local AoEON         = HR.AoEON
local CDsON         = HR.CDsON
local Cast          = HR.Cast
local CastPooling   = HR.CastPooling
local CastAnnotated = HR.CastAnnotated
local CastSuggested = HR.CastSuggested
-- Num/Bool Helper Functions
local num           = HR.Commons.Everyone.num
local bool          = HR.Commons.Everyone.bool
-- lua
local mathmax       = math.max

--- ============================ CONTENT ===========================
--- ======= APL LOCALS =======
-- luacheck: max_line_length 9999

-- Define S/I for spell and item arrays
local S = Spell.Evoker.Devastation
local I = Item.Evoker.Devastation

-- Create table to exclude above trinkets from On Use function
local OnUseExcludes = {
  I.KharnalexTheFirstLight:ID(),
  I.ShadowedOrbofTorment:ID(),
  I.SpoilsofNeltharus:ID(),
}

-- GUI Settings
local Everyone = HR.Commons.Everyone
local Settings = {
  General = HR.GUISettings.General,
  Commons = HR.GUISettings.APL.Evoker.Commons,
  Devastation = HR.GUISettings.APL.Evoker.Devastation
}

-- Trinket Item Objects
local equip = Player:GetEquipment()
local trinket1 = equip[13] and Item(equip[13]) or Item(0)
local trinket2 = equip[14] and Item(equip[14]) or Item(0)

-- Rotation Var
local Enemies25y
local Enemies8ySplash
local EnemiesCount8ySplash
local MaxEssenceBurstStack = (S.EssenceAttunement:IsAvailable()) and 2 or 1
local MaxBurnoutStack = 2
local VarTrinket1Sync, VarTrinket2Sync, TrinketPriority
local VarNextDragonrage
local VarDragonrageUp, VarDragonrageRemains
local VarR1CastTime
local BFRank = S.BlastFurnace:TalentRank()
local PlayerHaste
local BossFightRemains = 11111
local FightRemains = 11111
local GCDMax

-- Stun Interrupts
local StunInterrupts = {
  {S.TailSwipe, "Cast Tail Swipe (Interrupt)", function() return true; end},
  {S.WingBuffet, "Cast Wing Buffet (Interrupt)", function() return true; end},
}

-- Update Equipment
HL:RegisterForEvent(function()
  equip = Player:GetEquipment()
  trinket1 = equip[13] and Item(equip[13]) or Item(0)
  trinket2 = equip[14] and Item(equip[14]) or Item(0)
end, "PLAYER_EQUIPMENT_CHANGED")

-- Talent change registrations
HL:RegisterForEvent(function()
  MaxEssenceBurstStack = (S.EssenceAttunement:IsAvailable()) and 2 or 1
  BFRank = S.BlastFurnace:TalentRank()
end, "PLAYER_TALENT_UPDATE")

-- Reset variables after fights
HL:RegisterForEvent(function()
  BossFightRemains = 11111
  FightRemains = 11111
end, "PLAYER_REGEN_ENABLED")

local function Precombat()
  -- flask
  -- augmentation
  -- food
  -- snapshot_stats
  -- Manually added: Group buff check
  if S.BlessingoftheBronze:IsCastable() and (Player:BuffDown(S.BlessingoftheBronzeBuff) or Everyone.GroupBuffMissing(S.BlessingoftheBronzeBuff)) then
    if Cast(S.BlessingoftheBronze, Settings.Commons.GCDasOffGCD.BlessingOfTheBronze) then return "blessing_of_the_bronze precombat"; end
  end
  -- variable,name=trinket_1_sync,op=setif,value=1,value_else=0.5,condition=variable.trinket_1_buffs&(trinket.1.cooldown.duration%%cooldown.dragonrage.duration=0|cooldown.dragonrage.duration%%trinket.1.cooldown.duration=0)
  -- variable,name=trinket_2_sync,op=setif,value=1,value_else=0.5,condition=variable.trinket_2_buffs&(trinket.2.cooldown.duration%%cooldown.dragonrage.duration=0|cooldown.dragonrage.duration%%trinket.2.cooldown.duration=0)
  -- variable,name=trinket_priority,op=setif,value=2,value_else=1,condition=!variable.trinket_1_buffs&variable.trinket_2_buffs|variable.trinket_2_buffs&((trinket.2.cooldown.duration%trinket.2.proc.any_dps.duration)*(1.5+trinket.2.has_buff.intellect)*(variable.trinket_2_sync))>((trinket.1.cooldown.duration%trinket.1.proc.any_dps.duration)*(1.5+trinket.1.has_buff.intellect)*(variable.trinket_1_sync))
  -- variable,name=trinket_1_manual,value=trinket.1.is.spoils_of_neltharus
  -- variable,name=trinket_2_manual,value=trinket.2.is.spoils_of_neltharus
  -- TODO: Can't yet handle all of these trinket conditions
  -- use_item,name=shadowed_orb_of_torment
  if Settings.Commons.Enabled.Trinkets and I.ShadowedOrbofTorment:IsEquippedAndReady() then
    if Cast(I.ShadowedOrbofTorment, nil, Settings.Commons.DisplayStyle.Trinkets) then return "shadowed_orb_of_torment precombat"; end
  end
  -- firestorm,if=talent.firestorm
  if S.Firestorm:IsCastable() then
    if Cast(S.Firestorm, nil, nil, not Target:IsInRange(25)) then return "firestorm precombat"; end
  end
  -- living_flame,if=!talent.firestorm
  if S.LivingFlame:IsCastable() and (not S.Firestorm:IsAvailable()) then
    if Cast(S.LivingFlame, nil, nil, not Target:IsInRange(25)) then return "living_flame precombat"; end
  end
end

local function Defensives()
  if S.ObsidianScales:IsCastable() and Player:BuffDown(S.ObsidianScales) and (Player:HealthPercentage() < Settings.Devastation.ObsidianScalesThreshold) then
    if Cast(S.ObsidianScales, nil, Settings.Commons.DisplayStyle.Defensives) then return "obsidian_scales defensives"; end
  end
end

local function Trinkets()
  -- use_item,name=spoils_of_neltharus,if=buff.dragonrage.up&(buff.spoils_of_neltharus_mastery.up|buff.spoils_of_neltharus_haste.up|buff.dragonrage.remains+6*(cooldown.eternity_surge.remains<=gcd.max*2+cooldown.fire_breath.remains<=gcd.max*2)<=18)|fight_remains<=20
  if I.SpoilsofNeltharus:IsEquippedAndReady() and (VarDragonrageUp and (Player:BuffUp(S.SpoilsofNeltharusMastery) or Player:BuffUp(S.SpoilsofNeltharusHaste) or VarDragonrageRemains + 6 * num(num(S.EternitySurge:CooldownRemains() <= GCDMax * 2) + num(S.FireBreath:CooldownRemains() <= GCDMax * 2)) <= 18) or FightRemains <= 20) then
    if Cast(I.SpoilsofNeltharus, nil, Settings.Commons.DisplayStyle.Trinkets) then return "spoils_of_neltharus trinkets 2"; end
  end
  -- use_item,slot=trinket1,if=buff.dragonrage.up&(!trinket.2.has_cooldown|trinket.2.cooldown.remains|variable.trinket_priority=1)&!variable.trinket_1_manual|trinket.1.proc.any_dps.duration>=fight_remains|trinket.1.cooldown.duration<=60&(variable.next_dragonrage>20|!talent.dragonrage)&(!buff.dragonrage.up|variable.trinket_priority=1)
  -- use_item,slot=trinket2,if=buff.dragonrage.up&(!trinket.1.has_cooldown|trinket.1.cooldown.remains|variable.trinket_priority=2)&!variable.trinket_2_manual|trinket.2.proc.any_dps.duration>=fight_remains|trinket.2.cooldown.duration<=60&(variable.next_dragonrage>20|!talent.dragonrage)&(!buff.dragonrage.up|variable.trinket_priority=2)
  -- use_item,slot=trinket1,if=!variable.trinket_1_buffs&(trinket.2.cooldown.remains|!variable.trinket_2_buffs)&(variable.next_dragonrage>20|!talent.dragonrage)&!variable.trinket_1_manual
  -- use_item,slot=trinket2,if=!variable.trinket_2_buffs&(trinket.1.cooldown.remains|!variable.trinket_1_buffs)&(variable.next_dragonrage>20|!talent.dragonrage)&!variable.trinket_2_manual
  -- Note: Can't handle above trinket tracking, so let's use a generic fallback. When we can do above tracking, the below can be removed.
  -- use_items,if=buff.dragonrage.up|variable.next_dragonrage>20|!talent.dragonrage
  if (VarDragonrageUp or VarNextDragonrage > 20 or not S.Dragonrage:IsAvailable()) then
    local TrinketToUse = Player:GetUseableTrinkets(OnUseExcludes)
    if TrinketToUse then
      if Cast(TrinketToUse, nil, Settings.Commons.DisplayStyle.Trinkets) then return "Generic use_items for " .. TrinketToUse:Name(); end
    end
  end
end

local function ES()
  local ESEmpower = 0
  -- eternity_surge,empower_to=1,if=spell_targets.pyre<=1+talent.eternitys_span|buff.dragonrage.remains<1.75*spell_haste&buff.dragonrage.remains>=1*spell_haste
  if (EnemiesCount8ySplash <= 1 + num(S.EternitysSpan:IsAvailable()) or VarDragonrageRemains < 1.75 * PlayerHaste and VarDragonrageRemains >= 1 * PlayerHaste) then
    ESEmpower = 1
  -- eternity_surge,empower_to=2,if=spell_targets.pyre<=2+2*talent.eternitys_span|buff.dragonrage.remains<2.5*spell_haste&buff.dragonrage.remains>=1.75*spell_haste
  elseif (EnemiesCount8ySplash <= 2 + 2 * num(S.EternitysSpan:IsAvailable()) or VarDragonrageRemains < 2.5 * PlayerHaste and VarDragonrageRemains >= 1.75 * PlayerHaste) then
    ESEmpower = 2
  -- eternity_surge,empower_to=3,if=spell_targets.pyre<=3+3*talent.eternitys_span|!talent.font_of_magic|buff.dragonrage.remains<=3.25*spell_haste&buff.dragonrage.remains>=2.5*spell_haste
  elseif (EnemiesCount8ySplash <= 3 + 3 * num(S.EternitysSpan:IsAvailable()) or (not S.FontofMagic:IsAvailable()) or VarDragonrageRemains <= 3.25 * PlayerHaste and VarDragonrageRemains >= 2.5 * PlayerHaste) then
    ESEmpower = 3
  -- eternity_surge,empower_to=4
  else
    ESEmpower = 4
  end
  if CastAnnotated(S.EternitySurge, false, ESEmpower) then return "eternity_surge empower " .. ESEmpower .. " ES 2"; end
end

local function FB()
  local FBEmpower = 0
  local FBRemains = Target:DebuffRemains(S.FireBreath)
  -- fire_breath,empower_to=1,if=(20+2*talent.blast_furnace.rank)+dot.fire_breath_damage.remains<(20+2*talent.blast_furnace.rank)*1.3|buff.dragonrage.remains<1.75*spell_haste&buff.dragonrage.remains>=1*spell_haste|active_enemies<=2
  if ((20 + 2 * BFRank) + FBRemains < (20 + 2 * BFRank) * 1.3 or VarDragonrageRemains < 1.75 * PlayerHaste and VarDragonrageRemains >= 1 * PlayerHaste or EnemiesCount8ySplash <= 2) then
    FBEmpower = 1
  -- fire_breath,empower_to=2,if=(14+2*talent.blast_furnace.rank)+dot.fire_breath_damage.remains<(20+2*talent.blast_furnace.rank)*1.3|buff.dragonrage.remains<2.5*spell_haste&buff.dragonrage.remains>=1.75*spell_haste
  elseif ((14 + 2 * BFRank) + FBRemains < (20 + 2 * BFRank) * 1.3 or VarDragonrageRemains < 2.5 * PlayerHaste and VarDragonrageRemains >= 1.75 * PlayerHaste) then
    FBEmpower = 2
  -- fire_breath,empower_to=3,if=(8+2*talent.blast_furnace.rank)+dot.fire_breath_damage.remains<(20+2*talent.blast_furnace.rank)*1.3|!talent.font_of_magic|buff.dragonrage.remains<=3.25*spell_haste&buff.dragonrage.remains>=2.5*spell_haste
  elseif ((8 + 2 * BFRank) + FBRemains < (20 + 2 * BFRank) * 1.3 or (not S.FontofMagic:IsAvailable()) or VarDragonrageRemains <= 3.25 * PlayerHaste and VarDragonrageRemains >= 2.5 * PlayerHaste) then
    FBEmpower = 3
  -- fire_breath,empower_to=4
  else
    FBEmpower = 4
  end
  if CastAnnotated(S.FireBreath, false, FBEmpower) then return "fire_breath empower " .. FBEmpower .. " FB 2"; end
end

local function Aoe()
  -- dragonrage,if=cooldown.fire_breath.remains<=gcd.max&cooldown.eternity_surge.remains<3*gcd.max
  if S.Dragonrage:IsCastable() and CDsON() and (S.FireBreath:CooldownRemains() <= GCDMax and S.EternitySurge:CooldownRemains() < 3 * GCDMax) then
    if Cast(S.Dragonrage, Settings.Devastation.GCDasOffGCD.Dragonrage) then return "dragonrage aoe 2"; end
  end
  -- tip_the_scales,if=buff.dragonrage.up&(spell_targets.pyre<=6|!cooldown.fire_breath.up)
  if S.TipTheScales:IsCastable() and CDsON() and (VarDragonrageUp and (EnemiesCount8ySplash <= 6 or S.FireBreath:CooldownDown())) then
    if Cast(S.TipTheScales, Settings.Devastation.GCDasOffGCD.TipTheScales) then return "tip_the_scales aoe 4"; end
  end
  -- call_action_list,name=fb,if=buff.dragonrage.up|!talent.dragonrage|cooldown.dragonrage.remains>10&talent.everburning_flame
  if S.FireBreath:IsCastable() and (VarDragonrageUp or (not S.Dragonrage:IsAvailable()) or S.Dragonrage:CooldownRemains() > 10 and S.EverburningFlame:IsAvailable()) then
    local ShouldReturn = FB(); if ShouldReturn then return ShouldReturn; end
  end
  if S.FireBreath:IsCastable() and S.Dragonrage:CooldownRemains() > 10 then
    local FBEmpower = 0
    -- fire_breath,empower_to=1,if=cooldown.dragonrage.remains>10&spell_targets.pyre>=7
    if EnemiesCount8ySplash >= 7 then
      FBEmpower = 1
    -- fire_breath,empower_to=2,if=cooldown.dragonrage.remains>10&spell_targets.pyre>=6
    elseif EnemiesCount8ySplash >= 6 then
      FBEmpower = 2
    -- fire_breath,empower_to=3,if=cooldown.dragonrage.remains>10&spell_targets.pyre>=4
    elseif EnemiesCount8ySplash >= 4 then
      FBEmpower = 3
    -- fire_breath,empower_to=2,if=cooldown.dragonrage.remains>10
    else
      FBEmpower = 2
    end
    if CastAnnotated(S.FireBreath, false, FBEmpower) then return "fire_breath empower " .. FBEmpower .. " aoe 6"; end
  end
  -- call_action_list,name=es,if=buff.dragonrage.up|!talent.dragonrage|cooldown.dragonrage.remains>15
  if S.EternitySurge:IsCastable() and (VarDragonrageUp or (not S.Dragonrage:IsAvailable()) or S.Dragonrage:CooldownRemains() > 15) then
    local ShouldReturn = ES(); if ShouldReturn then return ShouldReturn; end
  end
  -- azure_strike,if=buff.dragonrage.up&buff.dragonrage.remains<(buff.essence_burst.max_stack-buff.essence_burst.stack)*gcd.max
  if S.AzureStrike:IsCastable() and (VarDragonrageUp and VarDragonrageRemains < (MaxEssenceBurstStack - Player:BuffStack(S.EssenceBurstBuff)) * GCDMax) then
    if Cast(S.AzureStrike, nil, nil, not Target:IsSpellInRange(S.AzureStrike)) then return "azure_strike aoe 8"; end
  end
  -- deep_breath,if=!buff.dragonrage.up
  if S.DeepBreath:IsCastable() and CDsON() and (not VarDragonrageUp) then
    if Cast(S.DeepBreath, Settings.Devastation.GCDasOffGCD.DeepBreath, nil, not Target:IsInRange(50)) then return "deep_breath aoe 10"; end
  end
  -- firestorm
  if S.Firestorm:IsCastable() then
    if Cast(S.Firestorm, nil, nil, not Target:IsInRange(25)) then return "firestorm aoe 12"; end
  end
  -- shattering_star
  if S.ShatteringStar:IsCastable() then
    if Cast(S.ShatteringStar, nil, nil, not Target:IsSpellInRange(S.ShatteringStar)) then return "shattering_star aoe 14"; end
  end
  -- azure_strike,if=cooldown.dragonrage.remains<gcd.max*6&cooldown.fire_breath.remains<6*gcd.max&cooldown.eternity_surge.remains<6*gcd.max
  if S.AzureStrike:IsCastable() and (S.Dragonrage:CooldownRemains() < GCDMax * 6 and S.FireBreath:CooldownRemains() < 6 * GCDMax and S.EternitySurge:CooldownRemains() < 6 * GCDMax) then
    if Cast(S.AzureStrike, nil, nil, not Target:IsSpellInRange(S.AzureStrike)) then return "azure_strike aoe 16"; end
  end
  -- pyre,if=talent.volatility
  if S.Pyre:IsReady() and (S.Volatility:IsAvailable()) then
    if Cast(S.Pyre, nil, nil, not Target:IsSpellInRange(S.Pyre)) then return "pyre aoe 18"; end
  end
  -- living_flame,if=buff.burnout.up&buff.leaping_flames.up&!buff.essence_burst.up
  if S.LivingFlame:IsCastable() and (Player:BuffUp(S.BurnoutBuff) and Player:BuffUp(S.LeapingFlamesBuff) and Player:BuffDown(S.EssenceBurstBuff)) then
    if Cast(S.LivingFlame, nil, nil, not Target:IsSpellInRange(S.LivingFlame)) then return "living_flame aoe 20"; end
  end
  -- pyre,if=cooldown.dragonrage.remains>=10&spell_targets.pyre>=4
  if S.Pyre:IsReady() and (S.Dragonrage:CooldownRemains() >= 10 and EnemiesCount8ySplash >= 4) then
    if Cast(S.Pyre, nil, nil, not Target:IsSpellInRange(S.Pyre)) then return "pyre aoe 22"; end
  end
  -- pyre,if=cooldown.dragonrage.remains>=10&spell_targets.pyre=3&buff.charged_blast.stack>=10
  if S.Pyre:IsReady() and (S.Dragonrage:CooldownRemains() >= 10 and EnemiesCount8ySplash == 3 and Player:BuffStack(S.ChargedBlastBuff) >= 10) then
    if Cast(S.Pyre, nil, nil, not Target:IsSpellInRange(S.Pyre)) then return "pyre aoe 24"; end
  end
  -- disintegrate,chain=1,if=!talent.shattering_star|cooldown.shattering_star.remains>5|essence>essence.max-1|buff.essence_burst.stack==buff.essence_burst.max_stack
  if S.Disintegrate:IsReady() and ((not S.ShatteringStar:IsAvailable()) or S.ShatteringStar:CooldownRemains() > 5 or Player:Essence() > Player:EssenceMax() - 1 or Player:BuffStack(S.EssenceBurstBuff) == MaxEssenceBurstStack) then
    if Cast(S.Disintegrate, nil, nil, not Target:IsSpellInRange(S.Disintegrate)) then return "disintegrate aoe 26"; end
  end
  -- living_flame,if=talent.snapfire&buff.burnout.up
  if S.LivingFlame:IsCastable() and (S.Snapfire:IsAvailable() and Player:BuffUp(S.BurnoutBuff)) then
    if Cast(S.LivingFlame, nil, nil, not Target:IsSpellInRange(S.LivingFlame)) then return "living_flame aoe 28"; end
  end
  -- azure_strike
  if S.AzureStrike:IsCastable() then
    if Cast(S.AzureStrike, nil, nil, not Target:IsSpellInRange(S.AzureStrike)) then return "azure_strike aoe 30"; end
  end
end

local function ST()
  -- use_item,name=kharnalex_the_first_light,if=!buff.dragonrage.up&debuff.shattering_star_debuff.down
  if Settings.Commons.Enabled.Items and I.KharnalexTheFirstLight:IsEquippedAndReady() and ((not VarDragonrageUp) and Target:DebuffDown(S.ShatteringStar)) then
    if Cast(I.KharnalexTheFirstLight, nil, Settings.Commons.DisplayStyle.Items, not Target:IsInRange(25)) then return "kharnalex_the_first_light st 1"; end
  end
  -- dragonrage,if=cooldown.fire_breath.remains<gcd.max&cooldown.eternity_surge.remains<2*gcd.max|fight_remains<30
  if S.Dragonrage:IsCastable() and CDsON() and (S.FireBreath:CooldownRemains() < GCDMax and S.EternitySurge:CooldownRemains() < 2 * GCDMax or FightRemains < 30) then
    if Cast(S.Dragonrage, Settings.Devastation.GCDasOffGCD.Dragonrage) then return "dragonrage st 2"; end
  end
  -- tip_the_scales,if=buff.dragonrage.up&(buff.dragonrage.remains<variable.r1_cast_time&(buff.dragonrage.remains>cooldown.fire_breath.remains|buff.dragonrage.remains>cooldown.eternity_surge.remains)|talent.feed_the_flames&!cooldown.fire_breath.up)
  if S.TipTheScales:IsCastable() and CDsON() and (VarDragonrageUp and (VarDragonrageRemains < VarR1CastTime and (VarDragonrageRemains > S.FireBreath:CooldownRemains() or VarDragonrageRemains > S.EternitySurge:CooldownRemains()) or S.FeedtheFlames:IsAvailable() and S.FireBreath:CooldownDown())) then
    if Cast(S.TipTheScales, Settings.Devastation.GCDasOffGCD.TipTheScales) then return "tip_the_scales st 4"; end
  end
  -- call_action_list,name=fb,if=!talent.dragonrage|variable.next_dragonrage>15|!talent.animosity
  -- call_action_list,name=es,if=!talent.dragonrage|variable.next_dragonrage>15|!talent.animosity
  if ((not S.Dragonrage:IsAvailable()) or VarNextDragonrage > 15 or not S.Animosity:IsAvailable()) then
    if S.FireBreath:IsCastable() then
      local ShouldReturn = FB(); if ShouldReturn then return ShouldReturn; end
    end
    if S.EternitySurge:IsCastable() then
      local ShouldReturn = ES(); if ShouldReturn then return ShouldReturn; end
    end
  end
  -- wait,sec=cooldown.fire_breath.remains,if=talent.animosity&buff.dragonrage.up&buff.dragonrage.remains<gcd.max+variable.r1_cast_time*buff.tip_the_scales.down&buff.dragonrage.remains-cooldown.fire_breath.remains>=variable.r1_cast_time*buff.tip_the_scales.down
  if (S.Animosity:IsAvailable() and VarDragonrageUp and VarDragonrageRemains < GCDMax + VarR1CastTime * num(Player:BuffDown(S.TipTheScales)) and VarDragonrageRemains - S.FireBreath:CooldownRemains() >= VarR1CastTime * num(Player:BuffDown(S.TipTheScales))) then
    if CastPooling(S.Pool, S.FireBreath:CooldownRemains(), "WAIT") then return "Wait for Fire Breath st 6"; end
  end
  -- wait,sec=cooldown.eternity_surge.remains,if=talent.animosity&buff.dragonrage.up&buff.dragonrage.remains<gcd.max+variable.r1_cast_time&buff.dragonrage.remains-cooldown.eternity_surge.remains>=variable.r1_cast_time*buff.tip_the_scales.down
  if (S.Animosity:IsAvailable() and VarDragonrageUp and VarDragonrageRemains < GCDMax + VarR1CastTime and VarDragonrageRemains - S.EternitySurge:CooldownRemains() >= VarR1CastTime * num(Player:BuffDown(S.TipTheScales))) then
    if CastPooling(S.Pool, S.EternitySurge:CooldownRemains(), "WAIT") then return "Wait for Eternity Surge st 8"; end
  end
  -- shattering_star,if=!buff.dragonrage.up|buff.essence_burst.stack==buff.essence_burst.max_stack|talent.eye_of_infinity
  if S.ShatteringStar:IsCastable() and ((not VarDragonrageUp) or Player:BuffStack(S.EssenceBurstBuff) == MaxEssenceBurstStack or S.EyeofInfinity:IsAvailable()) then
    if Cast(S.ShatteringStar, nil, nil, not Target:IsSpellInRange(S.ShatteringStar)) then return "shattering_star st 10"; end
  end
  -- living_flame,if=buff.dragonrage.up&buff.dragonrage.remains<(buff.essence_burst.max_stack-buff.essence_burst.stack)*gcd.max&buff.burnout.up
  if S.LivingFlame:IsCastable() and (VarDragonrageUp and VarDragonrageRemains < (MaxEssenceBurstStack - Player:BuffStack(S.EssenceBurstBuff)) * GCDMax and Player:BuffUp(S.BurnoutBuff)) then
    if Cast(S.LivingFlame, nil, nil, not Target:IsSpellInRange(S.LivingFlame)) then return "living_flame st 12"; end
  end
  -- azure_strike,if=buff.dragonrage.up&buff.dragonrage.remains<(buff.essence_burst.max_stack-buff.essence_burst.stack)*gcd.max
  if S.AzureStrike:IsCastable() and (VarDragonrageUp and VarDragonrageRemains < (MaxEssenceBurstStack - Player:BuffStack(S.EssenceBurstBuff)) * GCDMax) then
    if Cast(S.AzureStrike, nil, nil, not Target:IsSpellInRange(S.AzureStrike)) then return "azure_strike st 14"; end
  end
  -- firestorm,if=!buff.dragonrage.up&debuff.shattering_star_debuff.down|buff.snapfire.up
  if S.Firestorm:IsCastable() and ((not VarDragonrageUp) and Target:DebuffDown(S.ShatteringStar) or Player:BuffUp(S.SnapfireBuff)) then
    if Cast(S.Firestorm, nil, nil, not Target:IsInRange(25)) then return "firestorm st 18"; end
  end
  -- living_flame,if=buff.burnout.up&buff.essence_burst.stack<buff.essence_burst.max_stack&essence<essence.max-1
  if S.LivingFlame:IsCastable() and (Player:BuffUp(S.BurnoutBuff) and Player:BuffStack(S.EssenceBurstBuff) < MaxEssenceBurstStack and Player:Essence() < Player:EssenceMax() - 1) then
    if Cast(S.LivingFlame, nil, nil, not Target:IsSpellInRange(S.LivingFlame)) then return "living_flame st 20"; end
  end
  -- azure_strike,if=buff.dragonrage.up&(essence<3&!buff.essence_burst.up|(talent.shattering_star&cooldown.shattering_star.remains<=(buff.essence_burst.max_stack-buff.essence_burst.stack)*gcd.max))
  if S.AzureStrike:IsCastable() and (VarDragonrageUp and (Player:Essence() < 3 and Player:BuffDown(S.EssenceBurstBuff) or (S.ShatteringStar:IsAvailable() and S.ShatteringStar:CooldownRemains() <= (MaxEssenceBurstStack - Player:BuffStack(S.EssenceBurstBuff)) * GCDMax))) then
    if Cast(S.AzureStrike, nil, nil, not Target:IsSpellInRange(S.AzureStrike)) then return "azure_strike st 24"; end
  end
  -- disintegrate,chain=1,early_chain_if=evoker.use_early_chaining&buff.dragonrage.up&ticks>=2,interrupt_if=buff.dragonrage.up&ticks>=2&(evoker.use_clipping|cooldown.fire_breath.up|cooldown.eternity_surge.up),if=buff.dragonrage.up|(!talent.shattering_star|cooldown.shattering_star.remains>6|essence>essence.max-1|buff.essence_burst.stack==buff.essence_burst.max_stack)
  -- Note: Chaining is up to the user. We will display this for the next action, but the user must decide when to press the button.
  if S.Disintegrate:IsReady() and (VarDragonrageUp or ((not S.ShatteringStar:IsAvailable()) or S.ShatteringStar:CooldownRemains() > 6 or Player:Essence() > Player:EssenceMax() - 1 or Player:BuffStack(S.EssenceBurstBuff) == MaxEssenceBurstStack)) then
    if Cast(S.Disintegrate, nil, nil, not Target:IsSpellInRange(S.Disintegrate)) then return "disintegrate st 26"; end
  end
  -- deep_breath,if=!buff.dragonrage.up&spell_targets.deep_breath>1
  if S.DeepBreath:IsCastable() and CDsON() and ((not VarDragonrageUp) and EnemiesCount8ySplash > 1) then
    if Cast(S.DeepBreath, Settings.Devastation.GCDasOffGCD.DeepBreath, nil, not Target:IsInRange(50)) then return "deep_breath st 32"; end
  end
  -- living_flame
  if S.LivingFlame:IsCastable() then
    if Cast(S.LivingFlame, nil, nil, not Target:IsSpellInRange(S.LivingFlame)) then return "living_flame st 36"; end
  end
end

-- APL Main
local function APL()
  Enemies25y = Player:GetEnemiesInRange(25)
  Enemies8ySplash = Target:GetEnemiesInSplashRange(8)
  if (AoEON()) then
    EnemiesCount8ySplash = #Enemies8ySplash
  else
    EnemiesCount8ySplash = 1
  end

  if Everyone.TargetIsValid() or Player:AffectingCombat() then
    -- Calculate fight_remains
    BossFightRemains = HL.BossFightRemains(nil, true)
    FightRemains = BossFightRemains
    if FightRemains == 11111 then
      FightRemains = HL.FightRemains(Enemies25y, false)
    end
  end

  -- Set GCDMax (add 0.25 seconds for latency/player reaction)
  GCDMax = Player:GCD() + 0.25

  -- Player haste value is used in multiple places
  PlayerHaste = Player:SpellHaste()

  -- Set Dragonrage Variables
  if Everyone.TargetIsValid() or Player:AffectingCombat() then
    VarDragonrageUp = Player:BuffUp(S.Dragonrage)
    VarDragonrageRemains = VarDragonrageUp and Player:BuffRemains(S.Dragonrage) or 0
  end

  if Everyone.TargetIsValid() then
    -- Precombat
    if not Player:AffectingCombat() and not Player:IsCasting() then
      local ShouldReturn = Precombat(); if ShouldReturn then return ShouldReturn; end
    end
    -- Defensives
    if Player:AffectingCombat() and Settings.Devastation.UseDefensives then
      local ShouldReturn = Defensives(); if ShouldReturn then return ShouldReturn; end
    end
    -- Manually added: Interrupts
    local ShouldReturn = Everyone.Interrupt(10, S.Quell, Settings.Commons.OffGCDasOffGCD.Quell, StunInterrupts); if ShouldReturn then return ShouldReturn; end
    -- potion,if=buff.dragonrage.up|fight_remains<35
    if Settings.Commons.Enabled.Potions and (VarDragonrageUp or FightRemains < 35) then
      local PotionSelected = Everyone.PotionSelected()
      if PotionSelected and PotionSelected:IsReady() then
        if Cast(PotionSelected, nil, Settings.Commons.DisplayStyle.Potions) then return "potion main 2"; end
      end
    end
    -- variable,name=next_dragonrage,value=cooldown.dragonrage.remains<?(cooldown.eternity_surge.remains-2*gcd.max)<?(cooldown.fire_breath.remains-gcd.max)
    VarNextDragonrage = mathmax(S.Dragonrage:CooldownRemains(), (S.EternitySurge:CooldownRemains() - 2 * GCDMax), (S.FireBreath:CooldownRemains() - GCDMax))
    -- variable,name=r1_cast_time,value=1.3*spell_haste
    VarR1CastTime = 1.3 * PlayerHaste
    -- call_action_list,name=trinkets
    if Settings.Commons.Enabled.Trinkets then
      local ShouldReturn = Trinkets(); if ShouldReturn then return ShouldReturn; end
    end
    -- run_action_list,name=aoe,if=spell_targets.pyre>=3
    if EnemiesCount8ySplash >= 3 then
      local ShouldReturn = Aoe(); if ShouldReturn then return ShouldReturn; end
      if CastAnnotated(S.Pool, false, "WAIT") then return "Pool for Aoe()"; end
    end
    -- dragonrage,if=cooldown.eternity_surge.remains<=(buff.dragonrage.duration+6)&(cooldown.fire_breath.remains<=2*gcd.max|!talent.feed_the_flames)
    if S.Dragonrage:IsCastable() and (S.EternitySurge:CooldownRemains() <= (S.Dragonrage:BaseDuration() + 6) and (S.FireBreath:CooldownRemains() <= 2 * GCDMax or not S.FeedtheFlames:IsAvailable())) then
      if Cast(S.Dragonrage, Settings.Devastation.GCDasOffGCD.Dragonrage, nil, not Target:IsInRange(25)) then return "dragonrage main 10"; end
    end
    -- tip_the_scales,if=buff.dragonrage.up&(cooldown.eternity_surge.up|cooldown.fire_breath.up)&buff.dragonrage.remains<=gcd.max
    if S.TipTheScales:IsCastable() and (Player:BuffUp(S.Dragonrage) and (S.EternitySurge:CooldownUp() or S.FireBreath:CooldownUp()) and Player:BuffRemains(S.Dragonrage) <= GCDMax) then
      if Cast(S.TipTheScales, Settings.Devastation.GCDasOffGCD.TipTheScales) then return "tip_the_scales main 12"; end
    end
    -- eternity_surge,empower_to=1,if=buff.dragonrage.up&(buff.bloodlust.up|buff.power_infusion.up)&talent.feed_the_flames
    if S.EternitySurge:IsCastable() and (Player:BuffUp(S.Dragonrage) and (Player:BloodlustUp() or Player:BuffUp(S.PowerInfusionBuff)) and S.FeedtheFlames:IsAvailable()) then
      if CastAnnotated(S.EternitySurge, false, "1") then return "eternity_surge empower 1 main 14"; end
    end
    -- tip_the_scales,if=buff.dragonrage.up&cooldown.fire_breath.up&talent.everburning_flame&talent.firestorm
    if S.TipTheScales:IsCastable() and (Player:BuffUp(S.Dragonrage) and S.FireBreath:CooldownUp() and S.EverburningFlame:IsAvailable() and S.Firestorm:IsAvailable()) then
      if Cast(S.TipTheScales, Settings.Devastation.GCDasOffGCD.TipTheScales) then return "tip_the_scales main 16"; end
    end
    -- fire_breath,empower_to=1,if=talent.everburning_flame&(cooldown.firestorm.remains>=2*gcd.max|!dot.firestorm.ticking)|cooldown.dragonrage.remains>=10&talent.feed_the_flames|!talent.everburning_flame&!talent.feed_the_flames
    -- TODO: Find a way to track Firestorm. It does not have a DoT on the target.
    if S.FireBreath:IsCastable() and (S.EverburningFlame:IsAvailable() and (S.Firestorm:CooldownRemains() >= 2 * GCDMax or S.Firestorm:TimeSinceLastCast() >= 12) or S.Dragonrage:CooldownRemains() >= 10 and S.FeedtheFlames:IsAvailable() or (not S.EverburningFlame:IsAvailable()) and not S.FeedtheFlames:IsAvailable()) then
      if CastAnnotated(S.FireBreath, false, "1") then return "fire_breath main 18"; end
    end
    -- fire_breath,empower_to=2,if=talent.everburning_flame
    if S.FireBreath:IsCastable() and (S.EverburningFlame:IsAvailable()) then
      if CastAnnotated(S.FireBreath, false, "2") then return "fire_breath main 20"; end
    end
    -- firestorm,if=talent.everburning_flame&(cooldown.fire_breath.up|dot.fire_breath_damage.remains>=cast_time&dot.fire_breath_damage.remains<cooldown.fire_breath.remains)|buff.snapfire.up|spell_targets.firestorm>1
    if S.Firestorm:IsCastable() and (S.EverburningFlame:IsAvailable() and (S.FireBreath:CooldownUp() or Target:DebuffRemains(S.FireBreathDebuff) >= S.Firestorm:CastTime() and Target:DebuffRemains(S.FireBreathDebuff) < S.FireBreath:CooldownRemains()) or Player:BuffUp(S.SnapfireBuff) or EnemiesCount8ySplash > 1) then
      if Cast(S.Firestorm, nil, nil, not Target:IsInRange(25)) then return "firestorm main 22"; end
    end
    -- eternity_surge,empower_to=4,if=spell_targets.pyre>3*(1+talent.eternitys_span)
    -- eternity_surge,empower_to=3,if=spell_targets.pyre>2*(1+talent.eternitys_span)
    -- eternity_surge,empower_to=2,if=spell_targets.pyre>(1+talent.eternitys_span)
    -- eternity_surge,empower_to=1,if=(cooldown.eternity_surge.duration-cooldown.dragonrage.remains)<(buff.dragonrage.duration+6-gcd.max)
    if S.EternitySurge:IsReady() then
      local ESEmpower = 1
      if EnemiesCount8ySplash > 3 * (1 + num(S.EternitysSpan:IsAvailable())) then
        ESEmpower = 4
      elseif EnemiesCount8ySplash > 2 * (1 + num(S.EternitysSpan:IsAvailable())) then
        ESEmpower = 3
      elseif EnemiesCount8ySplash > (1 + num(S.EternitysSpan:IsAvailable())) then
        ESEmpower = 2
      end
      if ESEmpower > 1 then
        if CastAnnotated(S.EternitySurge, false, ESEmpower) then return "eternity_surge main 24"; end
      elseif (30 - S.Dragonrage:CooldownRemains()) < (S.Dragonrage:BaseDuration() + 6 - GCDMax) then
        if CastAnnotated(S.EternitySurge, false, ESEmpower) then return "eternity_surge empower 1 main 24"; end
      end
    end
    -- shattering_star,if=!talent.arcane_vigor|essence+1<essence.max|buff.dragonrage.up
    if S.ShatteringStar:IsCastable() and ((not S.ArcaneVigor:IsAvailable()) or Player:Essence() + 1 < Player:EssenceMax() or Player:BuffUp(S.Dragonrage)) then
      if Cast(S.ShatteringStar, nil, nil, not Target:IsInRange(25)) then return "shattering_star main 26"; end
    end
    -- azure_strike,if=essence<essence.max&!buff.burnout.up&spell_targets.azure_strike>(2-buff.dragonrage.up)&buff.essence_burst.stack<buff.essence_burst.max_stack&(!talent.ruby_embers|spell_targets.azure_strike>2)
    if S.AzureStrike:IsCastable() and (Player:Essence() < Player:EssenceMax() and EnemiesCount8ySplash > (2 - num(Player:BuffUp(S.Dragonrage))) and Player:BuffStack(S.EssenceBurstBuff) < MaxEssenceBurstStack and ((not S.RubyEmbers:IsAvailable()) or EnemiesCount8ySplash > 2)) then
      if Cast(S.AzureStrike, nil, nil, not Target:IsInRange(25)) then return "azure_strike main 28"; end
    end
    -- pyre,if=spell_targets.pyre>(2+talent.scintillation*talent.eternitys_span)|buff.charged_blast.stack=buff.charged_blast.max_stack&cooldown.dragonrage.remains>20&spell_targets.pyre>2
    if S.Pyre:IsReady() and (EnemiesCount8ySplash > (2 + num(S.Scintillation:IsAvailable()) * num(S.EternitysSpan:IsAvailable())) or Player:BuffStack(S.ChargedBlastBuff) == 20 and S.Dragonrage:CooldownRemains() > 20 and EnemiesCount8ySplash > 2) then
      if Cast(S.Pyre, nil, nil, not Target:IsInRange(25)) then return "pyre main 30"; end
    end
    -- living_flame,if=essence<essence.max&buff.essence_burst.stack<buff.essence_burst.max_stack&(buff.burnout.up|!talent.engulfing_blaze&!talent.shattering_star&buff.dragonrage.up&target.health.pct>80)
    if S.LivingFlame:IsCastable() and (not Player:IsCasting(S.LivingFlame)) and (Player:Essence() < Player:EssenceMax() and Player:BuffStack(S.EssenceBurstBuff) < MaxEssenceBurstStack and (Player:BuffUp(S.BurnoutBuff) or (not S.EngulfingBlaze:IsAvailable()) and (not S.ShatteringStar:IsAvailable()) and Player:BuffUp(S.Dragonrage) and Target:HealthPercentage() > 80)) then
      if Cast(S.LivingFlame, nil, nil, not Target:IsInRange(25)) then return "living_flame main 32"; end
    end
    -- disintegrate,chain=1,if=buff.dragonrage.up,interrupt_if=buff.dragonrage.up&ticks>=2,interrupt_immediate=1
    if S.Disintegrate:IsReady() and (Player:BuffUp(S.Dragonrage)) then
      if Cast(S.Disintegrate, nil, nil, not Target:IsInRange(25)) then return "disintegrate main 28"; end
    end
    -- disintegrate,chain=1,if=essence=essence.max|buff.essence_burst.stack=buff.essence_burst.max_stack|debuff.shattering_star_debuff.up|cooldown.shattering_star.remains>=3*gcd.max|!talent.shattering_star
    if S.Disintegrate:IsReady() and (Player:Essence() == Player:EssenceMax() or Player:BuffStack(S.EssenceBurstBuff) == MaxEssenceBurstStack or Target:DebuffUp(S.ShatteringStar) or S.ShatteringStar:CooldownRemains() >= 3 * GCDMax or not S.ShatteringStar:IsAvailable()) then
      if Cast(S.Disintegrate, nil, nil, not Target:IsInRange(25)) then return "disintegrate main 30"; end
    end
    -- use_item,name=kharnalex_the_first_light,if=!debuff.shattering_star_debuff.up&!buff.dragonrage.up&spell_targets.pyre=1
    if Settings.Commons.Enabled.Items and I.KharnalexTheFirstLight:IsEquippedAndReady() and (Target:DebuffDown(S.ShatteringStar) and Player:BuffDown(S.Dragonrage) and EnemiesCount8ySplash == 1) then
      if Cast(I.KharnalexTheFirstLight, nil, Settings.Commons.DisplayStyle.Items, not Target:IsInRange(25)) then return "kharnalex_the_first_light main 32"; end
    end
    -- azure_strike,if=spell_targets.azure_strike>2|(talent.engulfing_blaze|talent.feed_the_flames)&buff.dragonrage.up
    if S.AzureStrike:IsCastable() and (EnemiesCount8ySplash > 2 or (S.EngulfingBlaze:IsAvailable() or S.FeedtheFlames:IsAvailable()) and Player:BuffUp(S.Dragonrage)) then
      if Cast(S.AzureStrike, nil, nil, not Target:IsSpellInRange(S.AzureStrike)) then return "azure_strike main 32"; end
    end
    -- living_flame
    if S.LivingFlame:IsCastable() then
      if Cast(S.LivingFlame, nil, nil, not Target:IsInRange(25)) then return "living_flame main 34"; end
    end
    -- Error condition. We should never get here.
    if CastAnnotated(S.Pool, false, "ERR") then return "Wait/Pool Error"; end
  end
end

local function Init()
  HR.Print("Devastation Evoker rotation is currently a work in progress, but has been updated for patch 10.0.")
end

HR.SetAPL(1467, APL, Init);
