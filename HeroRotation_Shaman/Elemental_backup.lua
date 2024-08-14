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
local Pet        = Unit.Pet
local Target     = Unit.Target
local Spell      = HL.Spell
local MultiSpell = HL.MultiSpell
local Item       = HL.Item
-- HeroRotation
local HR         = HeroRotation
local Cast       = HR.Cast
local AoEON      = HR.AoEON
local CDsON      = HR.CDsON
-- Num/Bool Helper Functions
local num        = HR.Commons.Everyone.num
local bool       = HR.Commons.Everyone.bool
-- Lua
local GetTime    = GetTime

--- ============================ CONTENT ============================
--- ======= APL LOCALS =======

-- Define S/I for spell and item arrays
local S = Spell.Shaman.Elemental
local I = Item.Shaman.Elemental

-- Create table to exclude above trinkets from On Use function
local OnUseExcludes = {
  -- I.TrinketName:ID(),
}

-- GUI Settings
local Everyone = HR.Commons.Everyone
local Shaman = HR.Commons.Shaman
local Settings = {
  General = HR.GUISettings.General,
  Commons = HR.GUISettings.APL.Shaman.Commons,
  CommonsDS = HR.GUISettings.APL.Shaman.CommonsDS,
  CommonsOGCD = HR.GUISettings.APL.Shaman.CommonsOGCD,
  Elemental = HR.GUISettings.APL.Shaman.Elemental
}

HL:RegisterForEvent(function()
  S.PrimordialWave:RegisterInFlightEffect(327162)
  S.PrimordialWave:RegisterInFlight()
  S.LavaBurst:RegisterInFlight()
end, "LEARNED_SPELL_IN_TAB")
S.PrimordialWave:RegisterInFlightEffect(327162)
S.PrimordialWave:RegisterInFlight()
S.LavaBurst:RegisterInFlight()

-- Rotation Variables
local VarMaelCap = 100 + 50 * num(S.SwellingMaelstrom:IsAvailable()) + 25 * num(S.PrimordialCapacity:IsAvailable())
local BossFightRemains = 11111
local FightRemains = 11111
local HasMainHandEnchant, MHEnchantTimeRemains
local Enemies40y, Enemies10ySplash
Shaman.Targets = 0
Shaman.ClusterTargets = 0

HL:RegisterForEvent(function()
  VarMaelCap = 100 + 50 * num(S.SwellingMaelstrom:IsAvailable()) + 25 * num(S.PrimordialCapacity:IsAvailable())
end, "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB")

local function T302pcNextTick()
  return 40 - (GetTime() - Shaman.LastT302pcBuff)
end

local function EvaluateFlameShockRefreshable(TargetUnit)
  -- target_if=refreshable
  return (TargetUnit:DebuffRefreshable(S.FlameShockDebuff))
end

local function EvaluateFlameShockRefreshable2(TargetUnit)
  -- target_if=refreshable,if=dot.flame_shock.remains<target.time_to_die-5
  -- Note: Trimmed items handled before this function is called
  return (TargetUnit:DebuffRefreshable(S.FlameShockDebuff) and TargetUnit:DebuffRemains(S.FlameShockDebuff) < TargetUnit:TimeToDie() - 5)
end

local function EvaluateFlameShockRefreshable3(TargetUnit)
  -- target_if=refreshable,if=dot.flame_shock.remains<target.time_to_die-5&dot.flame_shock.remains>0
  -- Note: Trimmed items handled before this function is called
  return (TargetUnit:DebuffRefreshable(S.FlameShockDebuff) and TargetUnit:DebuffRemains(S.FlameShockDebuff) < TargetUnit:TimeToDie() - 5 and TargetUnit:DebuffRemains(S.FlameShockDebuff) > 0)
end

local function EvaluateFlameShockRemains(TargetUnit)
  -- target_if=min:dot.flame_shock.remains
  return (TargetUnit:DebuffRemains(S.FlameShockDebuff))
end

local function EvaluateFlameShockRemains2(TargetUnit)
  -- target_if=dot.flame_shock.remains>2
  return (TargetUnit:DebuffRemains(S.FlameShockDebuff) > 2)
end

local function EvaluateLightningRodRemains(TargetUnit)
  -- target_if=min:debuff.lightning_rod.remains
  return (TargetUnit:DebuffRemains(S.LightningRodDebuff))
end

local function Precombat()
  -- actions.precombat+=/flametongue_weapon,if=talent.improved_flametongue_weapon.enabled
  -- actions.precombat+=/skyfury
  -- actions.precombat+=/potion
  -- actions.precombat+=/stormkeeper
  if S.Stormkeeper:IsViable() then
    if Cast(S.Stormkeeper, Settings.Elemental.GCDasOffGCD.Stormkeeper) then return "stormkeeper precombat 2"; end
  end
  -- actions.precombat+=/lightning_shield
  -- actions.precombat+=/thunderstrike_ward

  -- icefury
  if S.Icefury:IsViable() then
    if Cast(S.Icefury, nil, nil, not Target:IsSpellInRange(S.Icefury)) then return "icefury precombat 4"; end
  end
  -- Manually added: Opener abilities, in case icefury is on CD
  if S.ElementalBlast:IsViable() then
    if Cast(S.ElementalBlast, nil, nil, not Target:IsSpellInRange(S.ElementalBlast)) then return "elemental_blast precombat 6"; end
  end
  if CDsON() and Player:IsCasting(S.ElementalBlast) and S.PrimordialWave:IsViable() then
    if Cast(S.PrimordialWave, nil, Settings.CommonsDS.DisplayStyle.Signature, not Target:IsSpellInRange(S.PrimordialWave)) then return "primordial_wave precombat 8"; end
  end
  if Player:IsCasting(S.ElementalBlast) and not S.PrimordialWave:IsViable() and S.FlameShock:IsReady() then
    if Cast(S.FlameShock, nil, nil, not Target:IsSpellInRange(S.FlameShock)) then return "flameshock precombat 10"; end
  end
  if S.LavaBurst:IsViable() and not Player:IsCasting(S.LavaBurst) and (not S.ElementalBlast:IsAvailable() or (S.ElementalBlast:IsAvailable() and not S.ElementalBlast:IsViable())) then
    if Cast(S.LavaBurst, nil, nil, not Target:IsSpellInRange(S.LavaBurst)) then return "lavaburst precombat 12"; end
  end
  if Player:IsCasting(S.LavaBurst) and S.FlameShock:IsReady() then 
    if Cast(S.FlameShock, nil, nil, not Target:IsSpellInRange(S.FlameShock)) then return "flameshock precombat 14"; end
  end
  if CDsON() and Player:IsCasting(S.LavaBurst) and S.PrimordialWave:IsViable() then
    if Cast(S.PrimordialWave, nil, Settings.CommonsDS.DisplayStyle.Signature, not Target:IsSpellInRange(S.PrimordialWave)) then return "primordial_wave precombat 16"; end
  end
end

local function Aoe()
  -- actions.aoe+=/fire_elemental,if=!buff.fire_elemental.up&(!talent.primal_elementalist.enabled|!buff.lesser_fire_elemental.up)
  if CDsON() and S.FireElemental:IsReady() then
    if Cast(S.FireElemental, Settings.Elemental.GCDasOffGCD.FireElemental) then return "fire_elemental aoe 2"; end
  end
  -- actions.aoe+=/storm_elemental,if=!buff.storm_elemental.up&(!talent.primal_elementalist.enabled|!buff.lesser_storm_elemental.up)
  if S.StormElemental:IsReady() then
    if Cast(S.StormElemental, Settings.Elemental.GCDasOffGCD.StormElemental) then return "storm_elemental aoe 4"; end
  end
  -- actions.aoe+=/stormkeeper,if=!buff.stormkeeper.up
  if S.Stormkeeper:IsViable() and (not Player:StormkeeperP()) then
    if Cast(S.Stormkeeper, Settings.Elemental.GCDasOffGCD.Stormkeeper) then return "stormkeeper aoe 6"; end
  end
  -- actions.aoe+=/totemic_recall,if=cooldown.liquid_magma_totem.remains>45
  if S.TotemicRecall:IsCastable() and (S.LiquidMagmaTotem:CooldownRemains() > 45) then
    if Cast(S.TotemicRecall, Settings.CommonsOGCD.GCDasOffGCD.TotemicRecall) then return "totemic_recall aoe 8"; end
  end
  -- actions.aoe+=/liquid_magma_totem,if=totem.liquid_magma_totem.down
  if S.LiquidMagmaTotem:IsReady() then
    if Cast(S.LiquidMagmaTotem, Settings.Elemental.GCDasOffGCD.LiquidMagmaTotem, nil, not Target:IsInRange(40)) then return "liquid_magma_totem aoe 10"; end
  end
  -- actions.aoe+=/primordial_wave,cycle_targets=1,if=buff.surge_of_power.up
  if CDsON() and S.PrimordialWave:IsViable() and Player:BuffUp(S.SurgeofPowerBuff) then
    if Everyone.CastTargetIf(S.PrimordialWave, Enemies10ySplash, "min", EvaluateFlameShockRemains, nil, not Target:IsSpellInRange(S.PrimordialWave), nil, Settings.CommonsDS.DisplayStyle.Signature) then return "primordial_wave aoe 12"; end
  end
  -- actions.aoe+=/primordial_wave,cycle_targets=1,if=talent.deeply_rooted_elements.enabled&!talent.surge_of_power.enabled
  if CDsON() and S.PrimordialWave:IsViable() and S.DeeplyRootedElements:IsAvailable() and not S.SurgeofPower:IsAvailable() then
    if Everyone.CastTargetIf(S.PrimordialWave, Enemies10ySplash, "min", EvaluateFlameShockRemains, nil, not Target:IsSpellInRange(S.PrimordialWave), nil, Settings.CommonsDS.DisplayStyle.Signature) then return "primordial_wave aoe 14"; end
  end
  -- actions.aoe+=/primordial_wave,cycle_targets=1,if=talent.master_of_the_elements.enabled&!talent.lightning_rod.enabled
  if CDsON() and S.PrimordialWave:IsViable() and S.MasteroftheElements:IsAvailable() and not S.LightningRod:IsAvailable() then
    if Everyone.CastTargetIf(S.PrimordialWave, Enemies10ySplash, "min", EvaluateFlameShockRemains, nil, not Target:IsSpellInRange(S.PrimordialWave), nil, Settings.CommonsDS.DisplayStyle.Signature) then return "primordial_wave aoe 16"; end
  end
  if S.FlameShock:IsCastable() then
    -- actions.aoe+=/flame_shock,cycle_targets=1,if=refreshable&buff.surge_of_power.up&talent.lightning_rod.enabled&dot.flame_shock.remains<target.time_to_die-16&active_enemies<5
    if (Player:BuffUp(S.SurgeofPowerBuff) and S.LightningRod:IsAvailable() and Target:DebuffRemains(S.FlameShockDebuff) < Target:TimeToDie() - 1 and S.FlameShockDebuff:AuraActiveCount() < 5) then
      if Everyone.CastCycle(S.FlameShock, Enemies10ySplash, EvaluateFlameShockRefreshable2, not Target:IsSpellInRange(S.FlameShock)) then return "flame_shock aoe 18"; end
    end
    -- actions.aoe+=/flame_shock,cycle_targets=1,if=buff.surge_of_power.up&(!talent.lightning_rod.enabled|talent.skybreakers_fiery_demise.enabled)&dot.flame_shock.remains<target.time_to_die-5&active_dot.flame_shock<6
    if (Player:BuffUp(S.SurgeofPowerBuff) and (not S.LightningRod:IsAvailable() or S.SkybreakersFieryDemise:IsAvailable()) and S.FlameShockDebuff:AuraActiveCount() < 6) then
      if Everyone.CastCycle(S.FlameShock, Enemies10ySplash, EvaluateFlameShockRefreshable2, not Target:IsSpellInRange(S.FlameShock)) then return "flame_shock aoe 20"; end
    end
    -- actions.aoe+=/flame_shock,cycle_targets=1,if=talent.master_of_the_elements.enabled&!talent.lightning_rod.enabled&!talent.surge_of_power.enabled&dot.flame_shock.remains<target.time_to_die-5&active_dot.flame_shock<6
    if (S.MasteroftheElements:IsAvailable() and not S.LightningRod:IsAvailable() and not S.SurgeofPower:IsAvailable() and S.FlameShockDebuff:AuraActiveCount() < 6) then
      if Everyone.CastCycle(S.FlameShock, Enemies10ySplash, EvaluateFlameShockRefreshable2, not Target:IsSpellInRange(S.FlameShock)) then return "flame_shock aoe 22"; end
    end
    -- actions.aoe+=/flame_shock,cycle_targets=1,if=talent.deeply_rooted_elements.enabled&!talent.surge_of_power.enabled&dot.flame_shock.remains<target.time_to_die-5&active_dot.flame_shock<6
    if (S.DeeplyRootedElements:IsAvailable() and not S.SurgeofPower:IsAvailable() and S.FlameShockDebuff:AuraActiveCount() < 6) then
      if Everyone.CastCycle(S.FlameShock, Enemies10ySplash, EvaluateFlameShockRefreshable2, not Target:IsSpellInRange(S.FlameShock)) then return "flame_shock aoe 24"; end
    end
    -- actions.aoe+=/flame_shock,cycle_targets=1,if=buff.surge_of_power.up&(!talent.lightning_rod.enabled|talent.skybreakers_fiery_demise.enabled)&dot.flame_shock.remains<target.time_to_die-5&dot.flame_shock.remains>0
    if (Player:BuffUp(S.SurgeofPowerBuff) and (not S.LightningRod:IsAvailable() or S.SkybreakersFieryDemise:IsAvailable())) then
      if Everyone.CastCycle(S.FlameShock, Enemies10ySplash, EvaluateFlameShockRefreshable3, not Target:IsSpellInRange(S.FlameShock)) then return "flame_shock aoe 26"; end
    end
    -- actions.aoe+=/flame_shock,cycle_targets=1,if=refreshable&talent.master_of_the_elements.enabled&!talent.lightning_rod.enabled&!talent.surge_of_power.enabled&dot.flame_shock.remains<target.time_to_die-5&dot.flame_shock.remains>0
    if (S.MasteroftheElements:IsAvailable() and not S.LightningRod:IsAvailable() and not S.SurgeofPower:IsAvailable()) then
      if Everyone.CastCycle(S.FlameShock, Enemies10ySplash, EvaluateFlameShockRefreshable3, not Target:IsSpellInRange(S.FlameShock)) then return "flame_shock aoe 28"; end
    end
    -- actions.aoe+=/flame_shock,cycle_targets=1,if=refreshable&talent.deeply_rooted_elements.enabled&!talent.surge_of_power.enabled&dot.flame_shock.remains<target.time_to_die-5&dot.flame_shock.remains>0
    if (S.DeeplyRootedElements:IsAvailable() and not S.SurgeofPower:IsAvailable()) then
      if Everyone.CastCycle(S.FlameShock, Enemies10ySplash, EvaluateFlameShockRefreshable3, not Target:IsSpellInRange(S.FlameShock)) then return "flame_shock aoe 30"; end
    end
  end
  -- actions.aoe+=/ascendance
  if CDsON() and S.Ascendance:IsCastable() then
    if Cast(S.Ascendance, Settings.CommonsOGCD.GCDasOffGCD.Ascendance) then return "ascendance aoe 32"; end
  end
  -- actions.aoe+=/lava_burst,cycle_targets=1,if=dot.flame_shock.remains&active_enemies=3&(!talent.lightning_rod.enabled&set_bonus.tier31_4pc)
  if S.LavaBurst:IsViable() and (Shaman.Targets == 3 and (not S.LightningRod:IsAvailable() and Player:HasTier(31, 4))) then
    if Everyone.CastCycle(S.LavaBurst, Enemies10ySplash, EvaluateFlameShockRemains, not Target:IsSpellInRange(S.LavaBurst)) then return "lava_burst aoe 34"; end
  end
  -- actions.aoe+=/earthquake,if=buff.master_of_the_elements.up&(buff.magma_chamber.stack=10&active_enemies>=6|talent.splintered_elements.enabled&active_enemies>=9|talent.mountains_will_fall.enabled&active_enemies>=9)&(!talent.lightning_rod.enabled&set_bonus.tier31_4pc)
  if S.Earthquake:IsReady() and (Player:MOTEP() and (Player:BuffStack(S.MagmaChamberBuff) == 10 and Shaman.Targets >= 6 or S.SplinteredElements:IsAvailable() and Shaman.Targets >= 9 or S.MountainsWillFall:IsAvailable() and Shaman.Targets >= 9) and (not S.LightningRod:IsAvailable() and Player:HasTier(31, 4))) then
    if Cast(S.Earthquake, nil, nil, not Target:IsInRange(40)) then return "earthquake aoe 36"; end
  end
  -- actions.aoe+=/lava_beam,if=buff.stormkeeper.up&(buff.surge_of_power.up&active_enemies>=6|buff.master_of_the_elements.up&(active_enemies<6|!talent.surge_of_power.enabled))&(!talent.lightning_rod.enabled&set_bonus.tier31_4pc)
  if S.LavaBeam:IsViable() and (Player:StormkeeperP() and (Player:BuffUp(S.SurgeofPowerBuff) and Shaman.Targets >= 6 or Player:MOTEP() and (Shaman.Targets < 6 or not S.SurgeofPower:IsAvailable())) and (not S.LightningRod:IsAvailable() and Player:HasTier(31, 4))) then
    if Cast(S.LavaBeam, nil, nil, not Target:IsSpellInRange(S.LavaBeam)) then return "lava_beam aoe 38"; end
  end
  -- actions.aoe+=/chain_lightning,if=buff.stormkeeper.up&(buff.surge_of_power.up&active_enemies>=6|buff.master_of_the_elements.up&(active_enemies<6|!talent.surge_of_power.enabled))&(!talent.lightning_rod.enabled&set_bonus.tier31_4pc)
  if S.ChainLightning:IsViable() and (Player:StormkeeperP() and (Player:BuffUp(S.SurgeofPowerBuff) and Shaman.Targets >= 6 or Player:MOTEP() and (Shaman.Targets < 6 or not S.SurgeofPower:IsAvailable())) and (not S.LightningRod:IsAvailable() and Player:HasTier(31, 4))) then
    if Cast(S.ChainLightning, nil, nil, not Target:IsSpellInRange(S.ChainLightning)) then return "chain_lightning aoe 40"; end
  end
  -- actions.aoe+=/lava_burst,cycle_targets=1,if=dot.flame_shock.remains&cooldown_react&buff.lava_surge.up&(!talent.lightning_rod.enabled&set_bonus.tier31_4pc)
  if S.LavaBurst:IsViable() and (Player:BuffUp(S.LavaSurgeBuff) and (not S.LightningRod:IsAvailable() and Player:HasTier(31, 4))) then
    if Everyone.CastCycle(S.LavaBurst, Enemies10ySplash, EvaluateFlameShockRemains, not Target:IsSpellInRange(S.LavaBurst)) then return "lava_burst aoe 42"; end
  end
  -- actions.aoe+=/lava_burst,cycle_targets=1,if=dot.flame_shock.remains&cooldown_react&buff.lava_surge.up&talent.master_of_the_elements.enabled&!buff.master_of_the_elements.up&(maelstrom>=52-5*talent.eye_of_the_storm.enabled-2*talent.flow_of_power.enabled)&(!talent.echoes_of_great_sundering.enabled&!talent.lightning_rod.enabled|buff.echoes_of_great_sundering_es.up|buff.echoes_of_great_sundering_eb.up)&(!buff.ascendance.up&active_enemies>3|active_enemies=3)
  if S.LavaBurst:IsViable() and (Player:BuffUp(S.LavaSurgeBuff) and S.MasteroftheElements:IsAvailable() and not Player:MOTEP() and (Player:MaelstromP() >= 52 - 5 * num(S.EyeoftheStorm:IsAvailable()) - 2 * num(S.FlowofPower:IsAvailable())) and (not S.EchoesofGreatSundering:IsAvailable() and not S.LightningRod:IsAvailable() or Player:BuffUp(S.EchoesofGreatSunderingBuff)) and (Player:BuffDown(S.AscendanceBuff) and Shaman.Targets > 3 or Shaman.Targets == 3)) then
    if Everyone.CastCycle(S.LavaBurst, Enemies10ySplash, EvaluateFlameShockRemains, not Target:IsSpellInRange(S.LavaBurst)) then return "lava_burst aoe 44"; end
  end
  -- actions.aoe+=/earthquake,if=!talent.echoes_of_great_sundering.enabled&active_enemies>3&(spell_targets.chain_lightning>3|spell_targets.lava_beam>3)
  if S.Earthquake:IsReady() and (not S.EchoesofGreatSundering:IsAvailable() and Shaman.Targets > 3 and Shaman.ClusterTargets > 3) then
    if Cast(S.Earthquake, nil, nil, not Target:IsInRange(40)) then return "earthquake aoe 46"; end
  end
  -- actions.aoe+=/earthquake,if=!talent.echoes_of_great_sundering.enabled&!talent.elemental_blast.enabled&active_enemies=3&(spell_targets.chain_lightning=3|spell_targets.lava_beam=3)
  if S.Earthquake:IsReady() and (not S.EchoesofGreatSundering:IsAvailable() and not S.ElementalBlast:IsAvailable() and Shaman.Targets == 3 and Shaman.ClusterTargets == 3) then
    if Cast(S.Earthquake, nil, nil, not Target:IsInRange(40)) then return "earthquake aoe 48"; end
  end
  -- actions.aoe+=/earthquake,if=buff.echoes_of_great_sundering_es.up|buff.echoes_of_great_sundering_eb.up
  if S.Earthquake:IsReady() and (Player:BuffUp(S.EchoesofGreatSunderingBuff)) then
    if Cast(S.Earthquake, nil, nil, not Target:IsInRange(40)) then return "earthquake aoe 50"; end
  end
  -- actions.aoe+=/elemental_blast,cycle_targets=1,if=talent.echoes_of_great_sundering.enabled
  if S.ElementalBlast:IsViable() and (S.EchoesofGreatSundering:IsAvailable()) then
    if Everyone.CastTargetIf(S.ElementalBlast, Enemies10ySplash, "min", EvaluateLightningRodRemains, nil, not Target:IsSpellInRange(S.ElementalBlast)) then return "elemental_blast aoe 52"; end
  end
  -- actions.aoe+=/elemental_blast,if=talent.echoes_of_great_sundering.enabled
  if S.ElementalBlast:IsViable() and (S.EchoesofGreatSundering:IsAvailable()) then
    if Cast(S.ElementalBlast, nil, nil, not Target:IsSpellInRange(S.ElementalBlast)) then return "elemental_blast aoe 54"; end
  end
  -- actions.aoe+=/elemental_blast,if=active_enemies=3&!talent.echoes_of_great_sundering.enabled
  if S.ElementalBlast:IsViable() and (Shaman.Targets == 3 and not S.EchoesofGreatSundering:IsAvailable()) then
    if Cast(S.ElementalBlast, nil, nil, not Target:IsSpellInRange(S.ElementalBlast)) then return "elemental_blast aoe 56"; end
  end
  -- actions.aoe+=/earth_shock,cycle_targets=1,if=talent.echoes_of_great_sundering.enabled
  if S.EarthShock:IsReady() and (S.EchoesofGreatSundering:IsAvailable()) then
    if Everyone.CastTargetIf(S.EarthShock, Enemies10ySplash, "min", EvaluateLightningRodRemains, nil, not Target:IsSpellInRange(S.EarthShock)) then return "earth_shock aoe 58"; end
  end
  -- actions.aoe+=/earth_shock,if=talent.echoes_of_great_sundering.enabled
  if S.EarthShock:IsReady() and (S.EchoesofGreatSundering:IsAvailable()) then
    if Cast(S.EarthShock, nil, nil, not Target:IsSpellInRange(S.EarthShock)) then return "earth_shock aoe 60"; end
  end
  -- actions.aoe+=/lava_burst,cycle_targets=1,if=dot.flame_shock.remains&talent.master_of_the_elements.enabled&!buff.master_of_the_elements.up&(buff.stormkeeper.up|t30_2pc_timer.next_tick<3&set_bonus.tier30_2pc)&(maelstrom<60-5*talent.eye_of_the_storm.enabled-2*talent.flow_of_power.enabled-10)&active_enemies<5
  if S.LavaBurst:IsViable() and (S.MasteroftheElements:IsAvailable() and not Player:MOTEP() and (Player:StormkeeperP() or Player:HasTier(30, 2) and T302pcNextTick() < 3) and (Player:MaelstromP() < 60 - 5 * num(S.EyeoftheStorm:IsAvailable()) - 2 * num(S.FlowofPower:IsAvailable()) - 10) and Shaman.Targets < 5) then
    if Everyone.CastCycle(S.LavaBurst, Enemies10ySplash, EvaluateFlameShockRemains, not Target:IsSpellInRange(S.LavaBurst)) then return "lava_burst aoe 66"; end
  end
  -- actions.aoe+=/lava_beam,if=buff.stormkeeper.up
  if S.LavaBeam:IsViable() and (Player:StormkeeperP()) then
    if Cast(S.LavaBeam, nil, nil, not Target:IsSpellInRange(S.LavaBeam)) then return "lava_beam aoe 68"; end
  end
  -- actions.aoe+=/chain_lightning,if=buff.stormkeeper.up
  if S.ChainLightning:IsViable() and (Player:StormkeeperP()) then
    if Cast(S.ChainLightning, nil, nil, not Target:IsSpellInRange(S.ChainLightning)) then return "chain_lightning aoe 70"; end
  end
  -- actions.aoe+=/lava_beam,if=buff.power_of_the_maelstrom.up&buff.ascendance.remains>cast_time
  if S.LavaBeam:IsViable() and (Player:PotMP() and Player:BuffRemains(S.AscendanceBuff) > S.LavaBeam:CastTime()) then
    if Cast(S.LavaBeam, nil, nil, not Target:IsSpellInRange(S.LavaBeam)) then return "lava_beam aoe 72"; end
  end
  -- actions.aoe+=/chain_lightning,if=buff.power_of_the_maelstrom.up
  if S.ChainLightning:IsViable() and (Player:PotMP()) then
    if Cast(S.ChainLightning, nil, nil, not Target:IsSpellInRange(S.ChainLightning)) then return "chain_lightning aoe 74"; end
  end
  -- actions.aoe+=/lava_beam,if=active_enemies>=6&buff.surge_of_power.up&buff.ascendance.remains>cast_time
  if S.LavaBeam:IsViable() and (Shaman.Targets >= 6 and Player:BuffUp(S.SurgeofPowerBuff) and Player:BuffRemains(S.AscendanceBuff) > S.LavaBeam:CastTime()) then
    if Cast(S.LavaBeam, nil, nil, not Target:IsSpellInRange(S.LavaBeam)) then return "lava_beam aoe 76"; end
  end
  -- actions.aoe+=/chain_lightning,if=active_enemies>=6&buff.surge_of_power.up
  if S.ChainLightning:IsViable() and (Shaman.Targets >= 6 and Player:BuffUp(S.SurgeofPowerBuff)) then
    if Cast(S.ChainLightning, nil, nil, not Target:IsSpellInRange(S.ChainLightning)) then return "chain_lightning aoe 78"; end
  end
  -- actions.aoe+=/lava_beam,if=buff.master_of_the_elements.up&buff.ascendance.remains>cast_time
  if S.LavaBeam:IsViable() and (Player:MOTEP() and Player:BuffRemains(S.AscendanceBuff) > S.LavaBeam:CastTime()) then
    if Cast(S.LavaBeam, nil, nil, not Target:IsSpellInRange(S.LavaBeam)) then return "lava_beam aoe 82"; end
  end
  -- actions.aoe+=/lava_burst,cycle_targets=1,if=dot.flame_shock.remains&active_enemies=3&talent.master_of_the_elements.enabled
  if S.LavaBurst:IsViable() and (Shaman.Targets == 3 and S.MasteroftheElements:IsAvailable()) then
    if Everyone.CastCycle(S.LavaBurst, Enemies10ySplash, EvaluateFlameShockRemains, not Target:IsSpellInRange(S.LavaBurst)) then return "lava_burst aoe 84"; end
  end
  -- actions.aoe+=/lava_burst,cycle_targets=1,if=dot.flame_shock.remains&buff.lava_surge.up&talent.deeply_rooted_elements.enabled
  if S.LavaBurst:IsViable() and (Player:BuffUp(S.LavaSurgeBuff) and S.DeeplyRootedElements:IsAvailable()) then
    if Everyone.CastCycle(S.LavaBurst, Enemies10ySplash, EvaluateFlameShockRemains, not Target:IsSpellInRange(S.LavaBurst)) then return "lava_burst aoe 86"; end
  end
  -- actions.aoe+=/icefury,if=talent.fusion_of_elements.enabled&talent.echoes_of_great_sundering.enabled
  if S.Icefury:IsViable() and (S.FusionofElements:IsAvailable() and S.EchoesofGreatSundering:IsAvailable()) then
    if Cast(S.Icefury, nil, nil, not Target:IsSpellInRange(S.Icefury)) then return "icefury aoe 88"; end
  end
  -- actions.aoe+=/lava_beam,if=buff.ascendance.remains>cast_time
  if S.LavaBeam:IsViable() and (Player:BuffRemains(S.AscendanceBuff) > S.LavaBeam:CastTime()) then
    if Cast(S.LavaBeam, nil, nil, not Target:IsSpellInRange(S.LavaBeam)) then return "lava_beam aoe 92"; end
  end
  -- actions.aoe+=/chain_lightning
  if S.ChainLightning:IsViable() then
    if Cast(S.ChainLightning, nil, nil, not Target:IsSpellInRange(S.ChainLightning)) then return "chain_lightning aoe 94"; end
  end
  -- actions.aoe+=/flame_shock,moving=1,cycle_targets=1,if=refreshable
  if S.FlameShock:IsCastable() then
    if Everyone.CastCycle(S.FlameShock, Enemies10ySplash, EvaluateFlameShockRefreshable, not Target:IsSpellInRange(S.FlameShock)) then return "flame_shock moving aoe 96"; end
  end
  -- actions.aoe+=/frost_shock,moving=1
  if S.FrostShock:IsCastable() then
    if Cast(S.FrostShock, nil, nil, not Target:IsSpellInRange(S.FrostShock)) then return "frost_shock moving aoe 98"; end
  end
end

local function SingleTarget()
  -- actions.single_target+=/fire_elemental,if=!buff.fire_elemental.up&(!talent.primal_elementalist.enabled|!buff.lesser_fire_elemental.up)
  if CDsON() and S.FireElemental:IsCastable() then
    if Cast(S.FireElemental, Settings.Elemental.GCDasOffGCD.FireElemental) then return "fire_elemental single_target 2"; end
  end
  -- actions.single_target+=/storm_elemental,if=!buff.storm_elemental.up&(!talent.primal_elementalist.enabled|!buff.lesser_storm_elemental.up)
  if S.StormElemental:IsCastable() then
    if Cast(S.StormElemental, Settings.Elemental.GCDasOffGCD.StormElemental) then return "storm_elemental single_target 4"; end
  end
  -- actions.single_target+=/totemic_recall,if=cooldown.liquid_magma_totem.remains>45&(active_enemies>1&(spell_targets.chain_lightning>1|spell_targets.lava_beam>1))
  if S.TotemicRecall:IsCastable() and (S.LiquidMagmaTotem:CooldownRemains() > 45 and (Shaman.Targets > 1 and Shaman.ClusterTargets > 1)) then
    if Cast(S.TotemicRecall, Settings.CommonsOGCD.GCDasOffGCD.TotemicRecall) then return "totemic_recall single_target 6"; end
  end
  -- actions.single_target+=/liquid_magma_totem,if=totem.liquid_magma_totem.down&(active_dot.flame_shock=0|dot.flame_shock.remains<6|active_enemies>1&(spell_targets.chain_lightning>1|spell_targets.lava_beam>1))
  --if S.LiquidMagmaTotem:IsCastable() and (S.FlameShockDebuff:AuraActiveCount() == 0 or Target:DebuffRemains(S.FlameShockDebuff) < 6 or Shaman.Targets > 1 and Shaman.ClusterTargets > 1) then
  --  if Cast(S.LiquidMagmaTotem, Settings.Elemental.GCDasOffGCD.LiquidMagmaTotem, nil, not Target:IsInRange(40)) then return "liquid_magma_totem single_target 8"; end
  --end
  -- actions.single_target+=/primordial_wave,cycle_targets=1
  if CDsON() and S.PrimordialWave:IsViable() then
    if Everyone.CastTargetIf(S.PrimordialWave, Enemies10ySplash, "min", EvaluateFlameShockRemains, nil, not Target:IsSpellInRange(S.PrimordialWave), nil, Settings.CommonsDS.DisplayStyle.Signature) then return "primordial_wave single_target 10"; end
  end
  -- actions.single_target+=/flame_shock,cycle_targets=1,if=active_enemies=1&refreshable&(dot.flame_shock.remains<cooldown.primordial_wave.remains|!talent.primordial_wave.enabled)&!buff.surge_of_power.up&(!buff.master_of_the_elements.up|(!buff.stormkeeper.up&(talent.elemental_blast.enabled&maelstrom<90-10*talent.eye_of_the_storm.enabled|maelstrom<60-5*talent.eye_of_the_storm.enabled)))
  if S.FlameShock:IsCastable() and (Shaman.Targets == 1 and Target:DebuffRefreshable(S.FlameShockDebuff) and (Target:DebuffRemains(S.FlameShockDebuff) < S.PrimordialWave:CooldownRemains() or not S.PrimordialWave:IsAvailable()) and Player:BuffDown(S.SurgeofPowerBuff) and (not Player:MOTEP() or (not Player:StormkeeperP() and (S.ElementalBlast:IsAvailable() and Player:MaelstromP() < 90 - 10 * num(S.EyeoftheStorm:IsAvailable()) or Player:MaelstromP() < 60 - 5 * num(S.EyeoftheStorm:IsAvailable()))))) then
    if Cast(S.FlameShock, nil, nil, not Target:IsSpellInRange(S.FlameShock)) then return "flame_shock single_target 12"; end
  end
  -- actions.single_target+=/flame_shock,cycle_targets=1,if=active_dot.flame_shock=0&active_enemies>1&(spell_targets.chain_lightning>1|spell_targets.lava_beam>1)&(talent.deeply_rooted_elements.enabled|talent.ascendance.enabled|talent.primordial_wave.enabled|talent.searing_flames.enabled|talent.magma_chamber.enabled)&(!buff.master_of_the_elements.up&(buff.stormkeeper.up|cooldown.stormkeeper.remains=0)|!talent.surge_of_power.enabled)
  if S.FlameShock:IsCastable() and (S.FlameShockDebuff:AuraActiveCount() == 0 and Shaman.Targets > 1 and Shaman.ClusterTargets > 1 and (S.DeeplyRootedElements:IsAvailable() or S.Ascendance:IsAvailable() or S.PrimordialWave:IsAvailable() or S.SearingFlames:IsAvailable() or S.MagmaChamber:IsAvailable()) and (not Player:MOTEP() and (Player:StormkeeperP() or S.Stormkeeper:CooldownUp()) or not S.SurgeofPower:IsAvailable())) then
    if Everyone.CastTargetIf(S.FlameShock, Enemies10ySplash, "min", EvaluateFlameShockRemains, nil, not Target:IsSpellInRange(S.FlameShock)) then return "flame_shock single_target 14"; end
  end
  -- actions.single_target+=/flame_shock,cycle_targets=1,if=active_enemies>1&(spell_targets.chain_lightning>1|spell_targets.lava_beam>1)&refreshable&(talent.deeply_rooted_elements.enabled|talent.ascendance.enabled|talent.primordial_wave.enabled|talent.searing_flames.enabled|talent.magma_chamber.enabled)&(buff.surge_of_power.up&!buff.stormkeeper.up&!cooldown.stormkeeper.remains=0|!talent.surge_of_power.enabled),cycle_targets=1
  if S.FlameShock:IsCastable() and (Shaman.Targets > 1 and Shaman.ClusterTargets > 1 and (S.DeeplyRootedElements:IsAvailable() or S.Ascendance:IsAvailable() or S.PrimordialWave:IsAvailable() or S.SearingFlames:IsAvailable() or S.MagmaChamber:IsAvailable()) and (Player:BuffUp(S.SurgeofPowerBuff) and not Player:StormkeeperP() and S.Stormkeeper:CooldownDown() or not S.SurgeofPower:IsAvailable())) then
    if Everyone.CastTargetIf(S.FlameShock, Enemies10ySplash, "min", EvaluateFlameShockRemains, EvaluateFlameShockRefreshable, not Target:IsSpellInRange(S.FlameShock)) then return "flame_shock single_target 16"; end
  end
  -- actions.single_target+=/stormkeeper,if=!buff.ascendance.up&!buff.stormkeeper.up&buff.surge_of_power.up
  if S.Stormkeeper:IsViable() and (Player:BuffDown(S.AscendanceBuff) and not Player:StormkeeperP() and Player:BuffUp(S.SurgeofPowerBuff)) then
    if Cast(S.Stormkeeper, Settings.Elemental.GCDasOffGCD.Stormkeeper) then return "stormkeeper single_target 18"; end
  end
  -- actions.single_target+=/stormkeeper,if=!buff.ascendance.up&!buff.stormkeeper.up&(!talent.surge_of_power.enabled|!talent.elemental_blast.enabled)
  if S.Stormkeeper:IsViable() and Player:BuffDown(S.AscendanceBuff) and not Player:StormkeeperP() and (not S.SurgeofPower:IsAvailable() or not S.ElementalBlast:IsAvailable()) then
    if Cast(S.Stormkeeper, Settings.Elemental.GCDasOffGCD.Stormkeeper) then return "stormkeeper single_target 20"; end
  end
  -- actions.single_target+=/ascendance,if=!buff.stormkeeper.up
  if CDsON() and S.Ascendance:IsCastable() and (not Player:StormkeeperP()) then
    if Cast(S.Ascendance, Settings.CommonsOGCD.GCDasOffGCD.Ascendance) then return "ascendance single_target 24"; end
  end
  -- actions.single_target+=/lightning_bolt,if=buff.stormkeeper.up&buff.surge_of_power.up
  if S.LightningBolt:IsViable() and (Player:StormkeeperP() and Player:BuffUp(S.SurgeofPowerBuff)) then
    if Cast(S.LightningBolt, nil, nil, not Target:IsSpellInRange(S.LightningBolt)) then return "lightning_bolt single_target 26"; end
  end
  -- actions.single_target+=/lava_beam,if=active_enemies>1&(spell_targets.chain_lightning>1|spell_targets.lava_beam>1)&buff.stormkeeper.up&!talent.surge_of_power.enabled
  if S.LavaBeam:IsCastable() and (Shaman.Targets > 1 and Shaman.ClusterTargets > 1 and Player:StormkeeperP() and not S.SurgeofPower:IsAvailable()) then
    if Cast(S.LavaBeam, nil, nil, not Target:IsSpellInRange(S.LavaBeam)) then return "lava_beam single_target 28"; end
  end
  -- actions.single_target+=/chain_lightning,if=active_enemies>1&(spell_targets.chain_lightning>1|spell_targets.lava_beam>1)&buff.stormkeeper.up&!talent.surge_of_power.enabled
  if S.ChainLightning:IsViable() and (Shaman.Targets > 1 and Shaman.ClusterTargets > 1 and Player:StormkeeperP() and not S.SurgeofPower:IsAvailable()) then
    if Cast(S.ChainLightning, nil, nil, not Target:IsSpellInRange(S.ChainLightning)) then return "chain_lightning single_target 30"; end
  end
  -- actions.single_target+=/lava_burst,if=buff.stormkeeper.up&!buff.master_of_the_elements.up&!talent.surge_of_power.enabled&talent.master_of_the_elements.enabled
  if S.LavaBurst:IsViable() and (Player:StormkeeperP() and not Player:MOTEP() and not S.SurgeofPower:IsAvailable() and S.MasteroftheElements:IsAvailable()) then
    if Cast(S.LavaBurst, nil, nil, not Target:IsSpellInRange(S.LavaBurst)) then return "lava_burst single_target 32"; end
  end
  -- actions.single_target+=/lightning_bolt,if=buff.stormkeeper.up&!talent.surge_of_power.enabled&buff.master_of_the_elements.up
  if S.LightningBolt:IsViable() and (Player:StormkeeperP() and not S.SurgeofPower:IsAvailable() and Player:MOTEP()) then
    if Cast(S.LightningBolt, nil, nil, not Target:IsSpellInRange(S.LightningBolt)) then return "lightning_bolt single_target 34"; end
  end
  -- actions.single_target+=/lightning_bolt,if=buff.stormkeeper.up&!talent.surge_of_power.enabled&!talent.master_of_the_elements.enabled
  if S.LightningBolt:IsViable() and (Player:StormkeeperP() and not S.SurgeofPower:IsAvailable() and not S.MasteroftheElements:IsAvailable()) then
    if Cast(S.LightningBolt, nil, nil, not Target:IsSpellInRange(S.LightningBolt)) then return "lightning_bolt single_target 36"; end
  end
  -- actions.single_target+=/lightning_bolt,if=buff.surge_of_power.up&talent.lightning_rod.enabled
  if S.LightningBolt:IsViable() and (Player:BuffUp(S.SurgeofPowerBuff) and S.LightningRod:IsAvailable()) then
    if Cast(S.LightningBolt, nil, nil, not Target:IsSpellInRange(S.LightningBolt)) then return "lightning_bolt single_target 38"; end
  end
  -- actions.single_target+=/lava_beam,if=active_enemies>1&(spell_targets.chain_lightning>1|spell_targets.lava_beam>1)&buff.power_of_the_maelstrom.up&buff.ascendance.remains>cast_time&!set_bonus.tier31_4pc
  if S.LavaBeam:IsCastable() and (Shaman.Targets > 1 and Shaman.ClusterTargets > 1 and Player:PotMP() and Player:BuffRemains(S.AscendanceBuff) > S.LavaBeam:CastTime() and not Player:HasTier(31, 4)) then
    if Cast(S.LavaBeam, nil, nil, not Target:IsSpellInRange(S.LavaBeam)) then return "lava_beam single_target 46"; end
  end
  -- actions.single_target+=/lava_burst,if=cooldown_react&buff.lava_surge.up&(talent.deeply_rooted_elements.enabled|!talent.master_of_the_elements.enabled|!talent.elemental_blast.enabled)
  if S.LavaBurst:IsViable() and (Player:BuffUp(S.LavaSurgeBuff) and (S.DeeplyRootedElements:IsAvailable() or not S.MasteroftheElements:IsAvailable() or not S.ElementalBlast:IsAvailable())) then
    if Cast(S.LavaBurst, nil, nil, not Target:IsSpellInRange(S.LavaBurst)) then return "lava_burst single_target 54"; end
  end
  -- actions.single_target+=/lava_burst,cycle_targets=1,if=dot.flame_shock.remains>2&buff.ascendance.up&!talent.elemental_blast.enabled
  if S.LavaBurst:IsViable() and (Player:BuffUp(S.AscendanceBuff) and not S.ElementalBlast:IsAvailable()) then
    if Everyone.CastCycle(S.LavaBurst, Enemies10ySplash, EvaluateFlameShockRemains2, not Target:IsSpellInRange(S.LavaBurst)) then return "lava_burst single_target 56"; end
  end
  -- actions.single_target+=/lava_burst,cycle_targets=1,if=dot.flame_shock.remains>2&talent.master_of_the_elements.enabled&!buff.master_of_the_elements.up&!talent.lightning_rod.enabled
  if S.LavaBurst:IsViable() and (S.MasteroftheElements:IsAvailable() and not Player:MOTEP() and not S.LightningRod:IsAvailable()) then
    if Everyone.CastCycle(S.LavaBurst, Enemies10ySplash, EvaluateFlameShockRemains2, not Target:IsSpellInRange(S.LavaBurst)) then return "lava_burst single_target 60"; end
  end
  -- actions.single_target+=/lava_burst,if=talent.master_of_the_elements.enabled&!buff.master_of_the_elements.up&(maelstrom>=80|maelstrom>=55&!talent.elemental_blast.enabled)&talent.swelling_maelstrom.enabled&maelstrom<=130
  if S.LavaBurst:IsViable() and (S.MasteroftheElements:IsAvailable() and not Player:MOTEP() and (Player:MaelstromP() >= 80 or Player:MaelstromP() >= 55 and not S.ElementalBlast:IsAvailable()) and S.SwellingMaelstrom:IsAvailable() and Player:MaelstromP() <= 130) then
    if Cast(S.LavaBurst, nil, nil, not Target:IsSpellInRange(S.LavaBurst)) then return "lava_burst single_target 62"; end
  end
  -- actions.single_target+=/earthquake,if=(buff.echoes_of_great_sundering_es.up|buff.echoes_of_great_sundering_eb.up)&(!talent.elemental_blast.enabled&active_enemies<2|active_enemies>1)
  if S.Earthquake:IsReady() and (Player:BuffUp(S.EchoesofGreatSunderingBuff) and (not S.ElementalBlast:IsAvailable() and Shaman.Targets < 2 or Shaman.Targets > 1)) then
    if Cast(S.Earthquake, nil, nil, not Target:IsInRange(40)) then return "earthquake single_target 64"; end
  end
  -- actions.single_target+=/earthquake,if=active_enemies>1&(spell_targets.chain_lightning>1|spell_targets.lava_beam>1)&!talent.echoes_of_great_sundering.enabled&!talent.elemental_blast.enabled
  if S.Earthquake:IsReady() and (Shaman.Targets > 1 and Shaman.ClusterTargets > 1 and not S.EchoesofGreatSundering:IsAvailable() and not S.ElementalBlast:IsAvailable()) then
    if Cast(S.Earthquake, nil, nil, not Target:IsInRange(40)) then return "earthquake single_target 66"; end
  end
  -- actions.single_target+=/elemental_blast,if=buff.master_of_the_elements.up|talent.lightning_rod.enabled
  if S.ElementalBlast:IsViable() and (Player:MOTEP() or S.LightningRod:IsAvailable()) then
    if Cast(S.ElementalBlast, nil, nil, not Target:IsSpellInRange(S.ElementalBlast)) then return "elemental_blast single_target 72"; end
  end
  -- actions.single_target+=/earth_shock
  if S.EarthShock:IsReady() then
    if Cast(S.EarthShock, nil, nil, not Target:IsSpellInRange(S.EarthShock)) then return "earth_shock single_target 74"; end
  end
  -- actions.single_target+=/lava_burst,cycle_targets=1,if=dot.flame_shock.remains>2&talent.deeply_rooted_elements.enabled
  if S.LavaBurst:IsViable() and (S.DeeplyRootedElements:IsAvailable()) then
    if Everyone.CastCycle(S.LavaBurst, Enemies10ySplash, EvaluateFlameShockRemains2, not Target:IsSpellInRange(S.LavaBurst)) then return "lava_burst single_target 78"; end
  end
  -- actions.single_target+=/frost_shock,if=buff.icefury_dmg.up&talent.flux_melting.enabled&!buff.flux_melting.up
  if S.FrostShock:IsCastable() and (Player:IcefuryP() and S.FluxMelting:IsAvailable() and Player:BuffDown(S.FluxMeltingBuff)) then
    if Cast(S.FrostShock, nil, nil, not Target:IsSpellInRange(S.FrostShock)) then return "frost_shock single_target 80"; end
  end
  -- actions.single_target+=/lava_burst,cycle_targets=1,if=dot.flame_shock.remains>2&talent.echo_of_the_elements.enabled|!talent.elemental_blast.enabled|!talent.master_of_the_elements.enabled|buff.stormkeeper.up
  if S.LavaBurst:IsViable() and (S.EchooftheElements:IsAvailable() or not S.ElementalBlast:IsAvailable() or not S.MasteroftheElements:IsAvailable() or Player:StormkeeperP()) then
    if Everyone.CastCycle(S.LavaBurst, Enemies10ySplash, EvaluateFlameShockRemains2, not Target:IsSpellInRange(S.LavaBurst)) then return "lava_burst single_target 84"; end
  end
  -- actions.single_target+=/elemental_blast
  if S.ElementalBlast:IsViable() then
    if Cast(S.ElementalBlast, nil, nil, not Target:IsSpellInRange(S.ElementalBlast)) then return "elemental_blast single_target 86"; end
  end
  -- actions.single_target+=/icefury
  if S.Icefury:IsViable() then
    if Cast(S.Icefury, nil, nil, not Target:IsSpellInRange(S.Icefury)) then return "icefury single_target 92"; end
  end
  -- actions.single_target+=/chain_lightning,if=buff.power_of_the_maelstrom.up&active_enemies>1&(spell_targets.chain_lightning>1|spell_targets.lava_beam>1)
  if S.ChainLightning:IsViable() and (Player:PotMP() and Shaman.Targets > 1 and Shaman.ClusterTargets > 1) then
    if Cast(S.ChainLightning, nil, nil, not Target:IsSpellInRange(S.ChainLightning)) then return "chain_lightning single_target 88"; end
  end
  -- actions.single_target+=/lightning_bolt,if=buff.power_of_the_maelstrom.up
  if S.LightningBolt:IsViable() and (Player:PotMP()) then
    if Cast(S.LightningBolt, nil, nil, not Target:IsSpellInRange(S.LightningBolt)) then return "lightning_bolt single_target 90"; end
  end
  -- actions.single_target+=/frost_shock,if=buff.icefury_dmg.up
  if S.FrostShock:IsCastable() and Player:IcefuryP() then
    if Cast(S.FrostShock, nil, nil, not Target:IsSpellInRange(S.FrostShock)) then return "frost_shock single_target 106"; end
  end
  -- actions.single_target+=/chain_lightning,if=active_enemies>1&(spell_targets.chain_lightning>1|spell_targets.lava_beam>1)
  if S.ChainLightning:IsViable() and (Shaman.Targets > 1 and Shaman.ClusterTargets > 1) then
    if Cast(S.ChainLightning, nil, nil, not Target:IsSpellInRange(S.ChainLightning)) then return "chain_lightning single_target 108"; end
  end
  -- actions.single_target+=/lightning_bolt
  if S.LightningBolt:IsViable() then
    if Cast(S.LightningBolt, nil, nil, not Target:IsSpellInRange(S.LightningBolt)) then return "lightning_bolt single_target 110"; end
  end
  -- actions.single_target+=/flame_shock,moving=1,cycle_targets=1,if=refreshable
  if S.FlameShock:IsCastable() and (Player:IsMoving()) then
    if Everyone.CastCycle(S.FlameShock, Enemies10ySplash, EvaluateFlameShockRefreshable, not Target:IsSpellInRange(S.FlameShock)) then return "flame_shock single_target 112"; end
  end
  -- actions.single_target+=/flame_shock,moving=1,if=movement.distance>6
  if S.FlameShock:IsCastable() then
    if Cast(S.FlameShock, nil, nil, not Target:IsSpellInRange(S.FlameShock)) then return "flame_shock single_target 114"; end
  end
  -- actions.single_target+=/frost_shock,moving=1
  if S.FrostShock:IsCastable() then
    if Cast(S.FrostShock, nil, nil, not Target:IsSpellInRange(S.FrostShock)) then return "frost_shock single_target 116"; end
  end
end

--- ======= MAIN =======
local function APL()
  Enemies40y = Player:GetEnemiesInRange(40)
  Enemies10ySplash = Target:GetEnemiesInSplashRange(10)
  if AoEON() then
    Shaman.Targets = #Enemies40y
    Shaman.ClusterTargets = Target:GetEnemiesInSplashRangeCount(10)
  else
    Shaman.Targets = 1
    Shaman.ClusterTargets = 1
  end

  if Everyone.TargetIsValid() or Player:AffectingCombat() then
    -- Calculate fight_remains
    BossFightRemains = HL.BossFightRemains()
    FightRemains = BossFightRemains
    if FightRemains == 11111 then
      FightRemains = HL.FightRemains(Enemies10ySplash, false)
    end
  end

  -- Shield Handling
  if Everyone.TargetIsValid() or Player:AffectingCombat() or Settings.Commons.ShieldsOOC then
    local EarthShieldBuff = (S.ElementalOrbit:IsAvailable()) and S.EarthShieldSelfBuff or S.EarthShieldOtherBuff
    if (S.ElementalOrbit:IsAvailable() or Settings.Commons.PreferEarthShield) and S.EarthShield:IsReady() and (Player:BuffDown(EarthShieldBuff) or (not Player:AffectingCombat() and Player:BuffStack(EarthShieldBuff) < 5)) then
      if Cast(S.EarthShield, Settings.Elemental.GCDasOffGCD.Shield) then return "Earth Shield Refresh"; end
    elseif (S.ElementalOrbit:IsAvailable() or not Settings.Commons.PreferEarthShield) and S.LightningShield:IsReady() and Player:BuffDown(S.LightningShield) then
      if Cast(S.LightningShield, Settings.Elemental.GCDasOffGCD.Shield) then return "Lightning Shield Refresh" end
    end
  end

  -- Weapon Buff Handling
  if Everyone.TargetIsValid() or Player:AffectingCombat() or Settings.Commons.WeaponBuffsOOC then
    -- Check weapon enchants
    HasMainHandEnchant, MHEnchantTimeRemains = GetWeaponEnchantInfo()
    -- flametongue_weapon,if=talent.improved_flametongue_weapon.enabled
    if S.ImprovedFlametongueWeapon:IsAvailable() and (not HasMainHandEnchant or MHEnchantTimeRemains < 600000) and S.FlametongueWeapon:IsViable() then
      if Cast(S.FlametongueWeapon) then return "flametongue_weapon enchant"; end
    end
  end

  if Everyone.TargetIsValid() then
    -- call Precombat
    if not Player:AffectingCombat() then
      local ShouldReturn = Precombat(); if ShouldReturn then return ShouldReturn; end
    end
    -- actions+=/wind_shear
    local ShouldReturn = Everyone.Interrupt(S.WindShear, Settings.CommonsDS.DisplayStyle.Interrupts); if ShouldReturn then return ShouldReturn; end
    if CDsON() then
      -- actions+=/blood_fury,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
      if S.BloodFury:IsCastable() and (not S.Ascendance:IsAvailable() or Player:BuffUp(S.AscendanceBuff) or S.Ascendance:CooldownRemains() > 50) then
        if Cast(S.BloodFury, Settings.CommonsOGCD.OffGCDasOffGCD.Racials) then return "blood_fury main 2"; end
      end
      -- actions+=/berserking,if=!talent.ascendance.enabled|buff.ascendance.up
      if S.Berserking:IsCastable() and (not S.Ascendance:IsAvailable() or Player:BuffUp(S.AscendanceBuff)) then
        if Cast(S.Berserking, Settings.CommonsOGCD.OffGCDasOffGCD.Racials) then return "berserking main 4"; end
      end
      -- actions+=/fireblood,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
      if S.Fireblood:IsCastable() and (not S.Ascendance:IsAvailable() or Player:BuffUp(S.AscendanceBuff) or S.Ascendance:CooldownRemains() > 50) then
        if Cast(S.Fireblood, Settings.CommonsOGCD.OffGCDasOffGCD.Racials) then return "fireblood main 6"; end
      end
      -- actions+=/ancestral_call,if=!talent.ascendance.enabled|buff.ascendance.up|cooldown.ascendance.remains>50
      if S.AncestralCall:IsCastable() and (not S.Ascendance:IsAvailable() or Player:BuffUp(S.AscendanceBuff) or S.Ascendance:CooldownRemains() > 50) then
        if Cast(S.AncestralCall, Settings.CommonsOGCD.OffGCDasOffGCD.Racials) then return "ancestral_call main 8"; end
      end
      -- actions+=/bag_of_tricks,if=!talent.ascendance.enabled|!buff.ascendance.up
      if S.BagofTricks:IsCastable() and (not S.Ascendance:IsAvailable() or Player:BuffUp(S.AscendanceBuff)) then
        if Cast(S.BagofTricks, Settings.CommonsOGCD.OffGCDasOffGCD.Racials) then return "bag_of_tricks main 10"; end
      end
    end
    -- actions+=/use_items
    if Settings.Commons.Enabled.Trinkets or Settings.Commons.Enabled.Items then
      local ItemToUse, ItemSlot, ItemRange = Player:GetUseableItems(OnUseExcludes)
      if ItemToUse then
        local DisplayStyle = Settings.CommonsDS.DisplayStyle.Trinkets
        if ItemSlot ~= 13 and ItemSlot ~= 14 then DisplayStyle = Settings.CommonsDS.DisplayStyle.Items end
        if ((ItemSlot == 13 or ItemSlot == 14) and Settings.Commons.Enabled.Trinkets) or (ItemSlot ~= 13 and ItemSlot ~= 14 and Settings.Commons.Enabled.Items) then
          if Cast(ItemToUse, nil, DisplayStyle, not Target:IsInRange(ItemRange)) then return "Generic use_items for " .. ItemToUse:Name(); end
        end
      end
    end
    -- actions+=/lightning_shield,if=buff.lightning_shield.down
    -- actions+=/natures_swiftness
    if S.NaturesSwiftness:IsCastable() and Player:BuffDown(S.NaturesSwiftness) then
      if Cast(S.NaturesSwiftness, Settings.CommonsOGCD.GCDasOffGCD.NaturesSwiftness) then return "natures_swiftness main 12"; end
    end
    -- actions+=/ancestral_swiftness
    -- actions+=/potion
    if Settings.Commons.Enabled.Potions then
      local PotionSelected = Everyone.PotionSelected()
      if PotionSelected and PotionSelected:IsReady() then
        if Cast(PotionSelected, nil, Settings.CommonsDS.DisplayStyle.Potions) then return "potion main 14"; end
      end
    end
    -- actions+=/run_action_list,name=aoe,strict=1,if=active_enemies>2&(spell_targets.chain_lightning>2|spell_targets.lava_beam>2)
    if (AoEON() and Shaman.Targets > 2 and Shaman.ClusterTargets > 2) then
      local ShouldReturn = Aoe(); if ShouldReturn then return ShouldReturn; end
      if HR.CastAnnotated(S.Pool, false, "POOL") then return "Pool for Aoe()"; end
    end
    -- actions+=/run_action_list,name=single_target
    if (true) then
      local ShouldReturn = SingleTarget(); if ShouldReturn then return ShouldReturn; end
      if HR.CastAnnotated(S.Pool, false, "POOL") then return "Pool for SingleTarget()"; end
    end
  end
end

local function Init()
  S.FlameShockDebuff:RegisterAuraTracking()

  HR.Print("Elemental Shaman rotation has been updated for patch 11.0.0.")
end

HR.SetAPL(262, APL, Init)
