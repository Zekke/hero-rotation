--- ============================ HEADER ============================
--- ======= LOCALIZE =======
-- Addon
local addonName, addonTable = ...
-- HeroDBC
local DBC = HeroDBC.DBC
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
local Cast       = HR.Cast
local CastLeft   = HR.CastLeft
local CDsON      = HR.CDsON
local AoEON      = HR.AoEON
local Mage       = HR.Commons.Mage
-- Num/Bool Helper Functions
local num        = HR.Commons.Everyone.num
local bool       = HR.Commons.Everyone.bool
-- lua
local mathmax        = math.max

--- ============================ CONTENT ===========================
--- ======= APL LOCALS =======
-- luacheck: max_line_length 9999

-- Define S/I for spell and item arrays
local S = Spell.Mage.Frost
local I = Item.Mage.Frost

-- Create table to exclude above trinkets from On Use function
local OnUseExcludes = {
  -- TWW Trinkets
  I.BurstofKnowledge:ID(),
  I.ImperfectAscendancySerum:ID(),
  I.SpymastersWeb:ID(),
  I.TreacherousTransmitter:ID(),
}

--- ===== GUI Settings =====
local Everyone = HR.Commons.Everyone
local Settings = {
  General = HR.GUISettings.General,
  Commons = HR.GUISettings.APL.Mage.Commons,
  CommonsDS = HR.GUISettings.APL.Mage.CommonsDS,
  CommonsOGCD = HR.GUISettings.APL.Mage.CommonsOGCD,
  Frost = HR.GUISettings.APL.Mage.Frost
}

--- ===== Rotation Variables =====
local VarBoltSpam = S.Splinterstorm:IsAvailable() and S.ColdFront:IsAvailable() and S.SlickIce:IsAvailable() and S.DeathsChill:IsAvailable() and S.FrozenTouch:IsAvailable() or S.FrostfireBolt:IsAvailable() and S.DeepShatter:IsAvailable() and S.SlickIce:IsAvailable() and S.DeathsChill:IsAvailable()
local Bolt = S.FrostfireBolt:IsAvailable() and S.FrostfireBolt or S.Frostbolt
local EnemiesCount8ySplash, EnemiesCount16ySplash --Enemies arround target
local Enemies16ySplash
local RemainingWintersChill = 0
local Icicles = 0
local PlayerMaxLevel = 80 -- TODO: Pull this value from Enum instead.
local BossFightRemains = 11111
local FightRemains = 11111
local GCDMax

--- ===== Event Registrations =====
HL:RegisterForEvent(function()
  S.Frostbolt:RegisterInFlightEffect(228597)
  S.Frostbolt:RegisterInFlight()
  S.FrostfireBolt:RegisterInFlight()
  S.FrozenOrb:RegisterInFlightEffect(84721)
  S.FrozenOrb:RegisterInFlight()
  S.Flurry:RegisterInFlightEffect(228354)
  S.Flurry:RegisterInFlight()
  S.GlacialSpike:RegisterInFlightEffect(228600)
  S.GlacialSpike:RegisterInFlight()
  S.IceLance:RegisterInFlightEffect(228598)
  S.IceLance:RegisterInFlight()
  S.Splinterstorm:RegisterInFlight()
  VarBoltSpam = S.Splinterstorm:IsAvailable() and S.ColdFront:IsAvailable() and S.SlickIce:IsAvailable() and S.DeathsChill:IsAvailable() and S.FrozenTouch:IsAvailable() or S.FrostfireBolt:IsAvailable() and S.DeepShatter:IsAvailable() and S.SlickIce:IsAvailable() and S.DeathsChill:IsAvailable()
  Bolt = S.FrostfireBolt:IsAvailable() and S.FrostfireBolt or S.Frostbolt
end, "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB")
S.Frostbolt:RegisterInFlightEffect(228597)
S.Frostbolt:RegisterInFlight()
S.FrostfireBolt:RegisterInFlight()
S.FrozenOrb:RegisterInFlightEffect(84721)
S.FrozenOrb:RegisterInFlight()
S.Flurry:RegisterInFlightEffect(228354)
S.Flurry:RegisterInFlight()
S.GlacialSpike:RegisterInFlightEffect(228600)
S.GlacialSpike:RegisterInFlight()
S.IceLance:RegisterInFlightEffect(228598)
S.IceLance:RegisterInFlight()
S.Splinterstorm:RegisterInFlight()

HL:RegisterForEvent(function()
  BossFightRemains = 11111
  FightRemains = 11111
  RemainingWintersChill = 0
end, "PLAYER_REGEN_ENABLED")

--- ===== Helper Functions =====
local function Freezable(Tar)
  if Tar == nil then Tar = Target end
  return not Tar:IsInBossList() or Tar:Level() < PlayerMaxLevel + 3
end

local function FrozenRemains()
  return mathmax(Player:BuffRemains(S.FingersofFrostBuff), Target:DebuffRemains(S.WintersChillDebuff), Target:DebuffRemains(S.Frostbite), Target:DebuffRemains(S.Freeze), Target:DebuffRemains(S.FrostNova))
end

local function CalculateWintersChill(enemies)
  if S.WintersChillDebuff:AuraActiveCount() == 0 then return 0 end
  local WCStacks = 0
  for _, CycleUnit in pairs(enemies) do
    WCStacks = WCStacks + CycleUnit:DebuffStack(S.WintersChillDebuff)
  end
  return WCStacks
end

--- ===== CastTargetIf Filter Functions =====
local function EvaluateTargetIfFilterWCStacks(TargetUnit)
  -- target_if=min:debuff.winters_chill.stack
  return (TargetUnit:DebuffStack(S.WintersChillDebuff))
end

--- ===== CastTargetIf Condition Functions =====
local function EvaluateTargetIfFlurrySSCleave(TargetUnit)
  -- if=cooldown_react&remaining_winters_chill=0&debuff.winters_chill.down&(prev_gcd.1.frostbolt|prev_gcd.1.glacial_spike)
  -- Note: All but debuff checked prior to CastTargetIf.
  return TargetUnit:DebuffDown(S.WintersChillDebuff)
end

local function EvaluateTargetIfIceLanceSSCleave(TargetUnit)
  -- if=buff.icy_veins.up&debuff.winters_chill.stack=2
  -- Note: Buff check handled prior to CastTargetIf.
  return TargetUnit:DebuffStack(S.WintersChillDebuff) == 2
end

--- ===== Rotation Functions =====
local function Precombat()
  -- flask
  -- food
  -- augmentation
  -- arcane_intellect
  if S.ArcaneIntellect:IsCastable() and Everyone.GroupBuffMissing(S.ArcaneIntellect) then
    if Cast(S.ArcaneIntellect, Settings.CommonsOGCD.GCDasOffGCD.ArcaneIntellect) then return "arcane_intellect precombat 2"; end
  end
  -- snapshot_stats
  -- variable,name=boltspam,value=talent.splinterstorm&talent.cold_front&talent.slick_ice&talent.deaths_chill&talent.frozen_touch|talent.frostfire_bolt&talent.deep_shatter&talent.slick_ice&talent.deaths_chill
  -- Note: Variables moved to declarations and SPELLS_CHANGED/LEARNED_SPELL_IN_TAB Event Registrations.
  -- variable,name=treacherous_transmitter_precombat_cast,value=12*!variable.boltspam
  -- Note: Unused variable.
  -- use_item,name=treacherous_transmitter
  if I.TreacherousTransmitter:IsEquippedAndReady() then
    if Cast(I.TreacherousTransmitter, nil, Settings.CommonsDS.DisplayStyle.Trinkets) then return "treacherous_transmitter precombat 2"; end
  end
  -- blizzard,if=active_enemies>=3
  -- Note: Can't check active_enemies in Precombat
  -- frostbolt,if=active_enemies<=2
  if Bolt:IsCastable() and not Player:IsCasting(Bolt) then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostbolt precombat 4"; end
  end
end

local function CDs()
  if Settings.Commons.Enabled.Trinkets then
    -- use_item,name=treacherous_transmitter,if=fight_remains<32+20*equipped.spymasters_web|prev_off_gcd.icy_veins|(!variable.boltspam|equipped.spymasters_web)&(cooldown.icy_veins.remains<12|cooldown.icy_veins.remains<22&cooldown.shifting_power.remains<10)
    if I.TreacherousTransmitter:IsEquippedAndReady() and (BossFightRemains < 32 + 20 * num(I.SpymastersWeb:IsEquipped()) or Player:PrevOffGCDP(1, S.IcyVeins) or (not VarBoltSpam or I.SpymastersWeb:IsEquipped()) and (S.IcyVeins:CooldownRemains() < 12 or S.IcyVeins:CooldownRemains() < 22 and S.ShiftingPower:CooldownRemains() < 10)) then
      if Cast(I.TreacherousTransmitter, nil, Settings.CommonsDS.DisplayStyle.Trinkets) then return "treacherous_transmitter cds 2"; end
    end
    -- do_treacherous_transmitter_task,if=fight_remains<18|(buff.cryptic_instructions.remains<?buff.realigning_nexus_convergence_divergence.remains<?buff.errant_manaforge_emission.remains)<(action.shifting_power.execute_time+1*talent.ray_of_frost)
    -- TODO
    -- use_item,name=spymasters_web,if=fight_remains<20|buff.icy_veins.remains<19&(fight_remains<105|buff.spymasters_report.stack>=32)&(buff.icy_veins.remains>15|trinket.treacherous_transmitter.cooldown.remains>50)
    if I.SpymastersWeb:IsEquippedAndReady() and (BossFightRemains < 20 or Player:BuffRemains(S.IcyVeinsBuff) < 19 and (FightRemains < 105 or Player:BuffStack(S.SpymastersReportBuff) >= 32) and (Player:BuffRemains(S.IcyVeinsBuff) > 15 or I.TreacherousTransmitter:IsEquipped() and I.TreacherousTransmitter:CooldownRemains() > 50)) then
      if Cast(I.SpymastersWeb, nil, Settings.CommonsDS.DisplayStyle.Trinkets) then return "spymasters_web cds 4"; end
    end
    -- use_item,name=imperfect_ascendancy_serum,if=buff.icy_veins.remains>15|fight_remains<20
    if I.ImperfectAscendancySerum:IsEquippedAndReady() and (Player:BuffRemains(S.IcyVeinsBuff) > 15 or BossFightRemains < 20) then
      if Cast(I.ImperfectAscendancySerum, nil, Settings.CommonsDS.DisplayStyle.Trinkets) then return "imperfect_ascendancy_serum cds 6"; end
    end    
    -- use_item,name=burst_of_knowledge,if=buff.icy_veins.remains>15|fight_remains<20
    if I.BurstofKnowledge:IsEquippedAndReady() and (Player:BuffRemains(S.IcyVeinsBuff) > 15 or BossFightRemains < 20) then
      if Cast(I.BurstofKnowledge, nil, Settings.CommonsDS.DisplayStyle.Trinkets) then return "burst_of_knowledge cds 8"; end
    end
  end
  -- potion,if=fight_remains<35|buff.icy_veins.remains>9&(fight_remains>315|cooldown.icy_veins.remains+12>fight_remains)
  if Settings.Commons.Enabled.Potions and (BossFightRemains < 35 or Player:BuffRemains(S.IcyVeinsBuff) > 9 and (FightRemains > 315 or S.IcyVeins:CooldownRemains() + 12 > FightRemains)) then
    local PotionSelected = Everyone.PotionSelected()
    if PotionSelected and PotionSelected:IsReady() then
      if Cast(PotionSelected, nil, Settings.CommonsDS.DisplayStyle.Potions) then return "potion cds 10"; end
    end
  end
  -- icy_veins,if=buff.icy_veins.remains<gcd.max*2
  if CDsON() and S.IcyVeins:IsCastable() and (Player:BuffRemains(S.IcyVeinsBuff) < Player:GCD() * 2) then
    if Cast(S.IcyVeins, Settings.Frost.GCDasOffGCD.IcyVeins) then return "icy_veins cds 12"; end
  end
  -- flurry,if=time=0&active_enemies<=2
  -- Note: Can't get here at time=0.
  -- use_items
  if (Settings.Commons.Enabled.Trinkets or Settings.Commons.Enabled.Items) then
    local ItemToUse, ItemSlot, ItemRange = Player:GetUseableItems(OnUseExcludes)
    if ItemToUse then
      local DisplayStyle = Settings.CommonsDS.DisplayStyle.Trinkets
      if ItemSlot ~= 13 and ItemSlot ~= 14 then DisplayStyle = Settings.CommonsDS.DisplayStyle.Items end
      if ((ItemSlot == 13 or ItemSlot == 14) and Settings.Commons.Enabled.Trinkets) or (ItemSlot ~= 13 and ItemSlot ~= 14 and Settings.Commons.Enabled.Items) then
        if Cast(ItemToUse, nil, DisplayStyle, not Target:IsInRange(ItemRange)) then return "Generic use_items for " .. ItemToUse:Name() .. " cds 14"; end
      end
    end
  end
  -- invoke_external_buff,name=power_infusion,if=buff.power_infusion.down
  -- invoke_external_buff,name=blessing_of_summer,if=buff.blessing_of_summer.down
  -- Note: Not handling external buffs.
  if CDsON() then
    -- blood_fury
    if S.BloodFury:IsCastable() then
      if Cast(S.BloodFury, Settings.CommonsOGCD.OffGCDasOffGCD.Racials) then return "blood_fury cds 16"; end
    end
    -- berserking,if=buff.icy_veins.remains>9&buff.icy_veins.remains<15|fight_remains<15
    if S.Berserking:IsCastable() and (Player:BuffRemains(S.IcyVeinsBuff) > 9 and Player:BuffRemains(S.IcyVeinsBuff) < 15 or BossFightRemains < 15) then
      if Cast(S.Berserking, Settings.CommonsOGCD.OffGCDasOffGCD.Racials) then return "berserking cds 18"; end
    end
    -- fireblood
    if S.Fireblood:IsCastable() then
      if Cast(S.Fireblood, Settings.CommonsOGCD.OffGCDasOffGCD.Racials) then return "fireblood cds 20"; end
    end
    -- ancestral_call
    if S.AncestralCall:IsCastable() then
      if Cast(S.AncestralCall, Settings.CommonsOGCD.OffGCDasOffGCD.Racials) then return "ancestral_call cds 22"; end
    end
  end
end

local function Movement()
  -- any_blink,if=movement.distance>10
  -- Note: Not handling blink.
  -- ice_floes,if=buff.ice_floes.down
  if S.IceFloes:IsCastable() and (Player:BuffDown(S.IceFloes)) then
    if Cast(S.IceFloes, nil, Settings.Frost.DisplayStyle.Movement) then return "ice_floes movement 2"; end
  end
  -- ice_nova
  if S.IceNova:IsCastable() then
    if Cast(S.IceNova, nil, Settings.Frost.DisplayStyle.Movement, not Target:IsSpellInRange(S.IceNova)) then return "ice_nova movement 4"; end
  end
  -- cone_of_cold,if=!talent.coldest_snap&active_enemies>=2
  if S.ConeofCold:IsReady() and (not S.ColdestSnap:IsAvailable() and EnemiesCount16ySplash >= 2) then
    if Cast(S.ConeofCold, nil, nil, not Target:IsInRange(12)) then return "cone_of_cold movement 6"; end
  end
  -- arcane_explosion,if=mana.pct>30&active_enemies>=2
  -- Note: If we're not in ArcaneExplosion range, just move to the next suggestion.
  if S.ArcaneExplosion:IsReady() and Target:IsInRange(10) and (Player:ManaPercentage() > 30 and EnemiesCount8ySplash >= 2) then
    if Cast(S.ArcaneExplosion, nil, Settings.Frost.DisplayStyle.Movement) then return "arcane_explosion movement 8"; end
  end
  -- fire_blast
  if S.FireBlast:IsReady() then
    if Cast(S.FireBlast, nil, Settings.Frost.DisplayStyle.Movement, not Target:IsSpellInRange(S.FireBlast)) then return "fire_blast movement 10"; end
  end
  -- ice_lance
  if S.IceLance:IsReady() then
    if Cast(S.IceLance, nil, Settings.Frost.DisplayStyle.Movement, not Target:IsSpellInRange(S.IceLance)) then return "ice_lance movement 12"; end
  end
end

local function AoEFF()
  -- cone_of_cold,if=talent.coldest_snap&prev_gcd.1.comet_storm
  if S.ConeofCold:IsCastable() and (S.ColdestSnap:IsAvailable() and Player:PrevGCDP(1, S.CometStorm)) then
    if Cast(S.ConeofCold, nil, nil, not Target:IsInRange(12)) then return "cone_of_cold aoe_ff 2"; end
  end
  -- frostfire_bolt,if=talent.deaths_chill&buff.icy_veins.remains>9&(buff.deaths_chill.stack<9|buff.deaths_chill.stack=9&!action.frostfire_bolt.in_flight)
  if Bolt:IsReady() and (S.DeathsChill:IsAvailable() and Player:BuffRemains(S.IcyVeinsBuff) > 9 and (Player:BuffStack(S.DeathsChillBuff) < 9 or Player:BuffStack(S.DeathsChillBuff) == 9 and not Bolt:InFlight())) then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostfire_bolt aoe_ff 4"; end
  end
  -- freeze,if=freezable&(prev_gcd.1.glacial_spike|prev_gcd.1.comet_storm&cooldown.cone_of_cold.remains&!prev_gcd.2.cone_of_cold)
  if Pet:IsActive() and S.Freeze:IsReady() and (Freezable() and (Player:PrevGCDP(1, S.GlacialSpike) or Player:PrevGCDP(1, S.CometStorm) and S.ConeofCold:CooldownDown() and not Player:PrevGCDP(2, S.ConeofCold))) then
    if Cast(S.Freeze, nil, nil, not Target:IsSpellInRange(S.Freeze)) then return "freeze aoe_ff 6"; end
  end
  -- ice_nova,if=freezable&(prev_gcd.1.glacial_spike&remaining_winters_chill=0&debuff.winters_chill.down|prev_gcd.1.comet_storm&cooldown.cone_of_cold.remains&!prev_gcd.2.cone_of_cold)&!prev_off_gcd.freeze
  if S.IceNova:IsCastable() and (Freezable() and (Player:PrevGCDP(1, S.GlacialSpike) and RemainingWintersChill == 0 and Target:DebuffDown(S.WintersChillDebuff) or Player:PrevGCDP(1, S.CometStorm) and S.ConeofCold:CooldownDown() and not Player:PrevGCDP(2, S.ConeofCold)) and not Player:PrevOffGCDP(1, S.Freeze)) then
    if Cast(S.IceNova, nil, nil, not Target:IsSpellInRange(S.IceNova)) then return "ice_nova aoe_ff 8"; end
  end
  -- frozen_orb,if=!prev_gcd.1.cone_of_cold
  if S.FrozenOrb:IsCastable() and (not Player:PrevGCDP(1, S.ConeofCold)) then
    if Cast(S.FrozenOrb, Settings.Frost.GCDasOffGCD.FrozenOrb, nil, not Target:IsInRange(40)) then return "frozen_orb aoe_ff 10"; end
  end
  -- comet_storm,if=cooldown.cone_of_cold.remains>6|cooldown.cone_of_cold.ready
  if S.CometStorm:IsCastable() and (S.ConeofCold:CooldownRemains() > 6 or S.ConeofCold:CooldownUp()) then
    if Cast(S.CometStorm, Settings.Frost.GCDasOffGCD.CometStorm, nil, not Target:IsSpellInRange(S.CometStorm)) then return "comet_storm aoe_ff 12"; end
  end
  -- flurry,if=cooldown_react&remaining_winters_chill=0&(buff.excess_frost.react&cooldown.comet_storm.remains>5|prev_gcd.1.glacial_spike)
  if S.Flurry:IsCastable() and (RemainingWintersChill == 0 and (Player:BuffUp(S.ExcessFrostBuff) and S.CometStorm:CooldownRemains() > 5 or Player:PrevGCDP(1, S.GlacialSpike))) then
    if Cast(S.Flurry, Settings.Frost.GCDasOffGCD.Flurry, nil, not Target:IsSpellInRange(S.Flurry)) then return "flurry aoe_ff 14"; end
  end
  -- blizzard,if=talent.ice_caller
  if S.Blizzard:IsCastable() and (S.IceCaller:IsAvailable()) then
    if Cast(S.Blizzard, Settings.Frost.GCDasOffGCD.Blizzard, nil, not Target:IsInRange(40)) then return "blizzard aoe_ff 16"; end
  end
  -- ray_of_frost,if=talent.splintering_ray&remaining_winters_chill=2
  if S.RayofFrost:IsCastable() and (S.SplinteringRay:IsAvailable() and RemainingWintersChill == 2) then
    if Cast(S.RayofFrost, Settings.Frost.GCDasOffGCD.RayOfFrost, nil, not Target:IsSpellInRange(S.RayofFrost)) then return "ray_of_frost aoe_ff 18"; end
  end
  -- shifting_power,if=cooldown.icy_veins.remains>10&(fight_remains+10>cooldown.icy_veins.remains)
  if CDsON() and S.ShiftingPower:IsCastable() and (S.IcyVeins:CooldownRemains() > 10 and (FightRemains + 10 > S.IcyVeins:CooldownRemains())) then
    if Cast(S.ShiftingPower, nil, Settings.CommonsDS.DisplayStyle.ShiftingPower, not Target:IsInRange(18)) then return "shifting_power aoe_ff 20"; end
  end
  -- frostfire_bolt,if=buff.frostfire_empowerment.react&!buff.excess_frost.react&!buff.excess_fire.react
  if Bolt:IsReady() and (Player:BuffUp(S.FrostfireEmpowermentBuff) and Player:BuffDown(S.ExcessFrostBuff) and Player:BuffDown(S.ExcessFireBuff)) then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostfire_bolt aoe_ff 22"; end
  end
  -- glacial_spike,if=(active_enemies<=6|!talent.ice_caller)&buff.icicles.react=5
  if S.GlacialSpike:IsReady() and ((EnemiesCount8ySplash <= 6 or not S.IceCaller:IsAvailable()) and Icicles == 5) then
    if Cast(S.GlacialSpike, nil, nil, not Target:IsSpellInRange(S.GlacialSpike)) then return "glacial_spike aoe_ff 24"; end
  end
  -- ice_lance,if=buff.fingers_of_frost.react|remaining_winters_chill
  if S.IceLance:IsReady() and (Player:BuffUp(S.FingersofFrostBuff) or RemainingWintersChill > 0) then
    if Cast(S.IceLance, nil, nil, not Target:IsSpellInRange(S.IceLance)) then return "ice_lance aoe_ff 26"; end
  end
  -- flurry,if=cooldown_react&remaining_winters_chill=0
  if S.Flurry:IsCastable() and (RemainingWintersChill == 0) then
    if Cast(S.Flurry, Settings.Frost.GCDasOffGCD.Flurry, nil, not Target:IsSpellInRange(S.Flurry)) then return "flurry aoe_ff 28"; end
  end
  -- frostfire_bolt
  if Bolt:IsReady() then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostfire_bolt aoe_ff 30"; end
  end
  -- call_action_list,name=movement
  if Player:IsMoving() then
    local ShouldReturn = Movement(); if ShouldReturn then return ShouldReturn; end
  end
end

local function AoESS()
  -- cone_of_cold,if=talent.coldest_snap&!action.frozen_orb.cooldown_react&(prev_gcd.1.comet_storm|prev_gcd.1.frozen_orb&cooldown.comet_storm.remains>5)&(!talent.deaths_chill|buff.icy_veins.remains<9|buff.deaths_chill.stack>=12)
  if S.ConeofCold:IsReady() and (S.ColdestSnap:IsAvailable() and S.FrozenOrb:CooldownDown() and (Player:PrevGCDP(1, S.CometStorm) or Player:PrevGCDP(1, S.FrozenOrb) and S.CometStorm:CooldownRemains() > 5) and (not S.DeathsChill:IsAvailable() or Player:BuffRemains(S.IcyVeinsBuff) < 9 or Player:BuffStack(S.DeathsChillBuff) >= 12)) then
    if Cast(S.ConeofCold, nil, nil, not Target:IsInRange(12)) then return "cone_of_cold aoe_ss 2"; end
  end
  -- freeze,if=freezable&prev_gcd.1.glacial_spike
  if Pet:IsActive() and S.Freeze:IsReady() and (Freezable() and Player:PrevGCDP(1, S.GlacialSpike)) then
    if Cast(S.Freeze, nil, nil, not Target:IsSpellInRange(S.Freeze)) then return "freeze aoe_ss 4"; end
  end
  -- flurry,if=cooldown_react&remaining_winters_chill=0&prev_gcd.1.glacial_spike
  if S.Flurry:IsCastable() and (RemainingWintersChill == 0 and Player:PrevGCDP(1, S.GlacialSpike)) then
    if Cast(S.Flurry, Settings.Frost.GCDasOffGCD.Flurry, nil, not Target:IsSpellInRange(S.Flurry)) then return "flurry aoe_ss 6"; end
  end
  -- ice_nova,if=active_enemies<5&freezable&prev_gcd.1.glacial_spike&remaining_winters_chill=0&debuff.winters_chill.down|active_enemies>=5&time-action.cone_of_cold.last_used<6&time-action.cone_of_cold.last_used>6-gcd.max
  if S.IceNova:IsCastable() and (EnemiesCount8ySplash < 5 and Freezable() and Player:PrevGCDP(1, S.GlacialSpike) and RemainingWintersChill == 0 and Target:DebuffDown(S.WintersChillDebuff) or EnemiesCount8ySplash >= 5 and S.ConeofCold:TimeSinceLastCast() < 6 and S.ConeofCold:TimeSinceLastCast() > 6 - Player:GCD()) then
    if Cast(S.IceNova, nil, nil, not Target:IsSpellInRange(S.IceNova)) then return "ice_nova aoe_ss 8"; end
  end
  -- frozen_orb,if=cooldown_react
  if S.FrozenOrb:IsCastable() then
    if Cast(S.FrozenOrb, Settings.Frost.GCDasOffGCD.FrozenOrb, nil, not Target:IsInRange(40)) then return "frozen_orb aoe_ss 10"; end
  end
  -- frostbolt,if=talent.deaths_chill&buff.icy_veins.remains>9&(buff.deaths_chill.stack<9|buff.deaths_chill.stack=9&!action.frostbolt.in_flight)
  if Bolt:IsCastable() and (S.DeathsChill:IsAvailable() and Player:BuffRemains(S.IcyVeinsBuff) > 9 and (Player:BuffStack(S.DeathsChillBuff) < 9 or Player:BuffStack(S.DeathsChillBuff) == 9 and not Bolt:InFlight())) then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostbolt aoe_ss 12"; end
  end
  -- comet_storm
  if S.CometStorm:IsCastable() then
    if Cast(S.CometStorm, Settings.Frost.GCDasOffGCD.CometStorm, nil, not Target:IsSpellInRange(S.CometStorm)) then return "comet_storm aoe_ss 14"; end
  end
  -- ray_of_frost,if=talent.splintering_ray&prev_gcd.1.flurry
  if S.RayofFrost:IsCastable() and (S.SplinteringRay:IsAvailable() and Player:PrevGCDP(1, S.Flurry)) then
    if Cast(S.RayofFrost, Settings.Frost.GCDasOffGCD.RayOfFrost, nil, not Target:IsSpellInRange(S.RayofFrost)) then return "ray_of_frost aoe_ss 15"; end
  end
  -- blizzard,if=talent.ice_caller|talent.freezing_rain|active_enemies>=5
  if S.Blizzard:IsCastable() and (S.IceCaller:IsAvailable() or S.FreezingRain:IsAvailable() or EnemiesCount16ySplash >= 5) then
    if Cast(S.Blizzard, Settings.Frost.GCDasOffGCD.Blizzard, nil, not Target:IsInRange(40)) then return "blizzard aoe_ss 16"; end
  end
  -- shifting_power,if=cooldown.icy_veins.remains>10&(fight_remains+10>cooldown.icy_veins.remains)
  if CDsON() and S.ShiftingPower:IsCastable() and (S.IcyVeins:CooldownRemains() > 10 and (FightRemains + 10 > S.IcyVeins:CooldownRemains())) then
    if Cast(S.ShiftingPower, nil, Settings.CommonsDS.DisplayStyle.ShiftingPower, not Target:IsInRange(18)) then return "shifting_power aoe_ss 18"; end
  end
  -- glacial_spike,if=buff.icicles.react=5&(action.flurry.cooldown_react|remaining_winters_chill|active_enemies<5&freezable&cooldown.ice_nova.ready&!buff.fingers_of_frost.react)
  if S.GlacialSpike:IsReady() and (Icicles == 5 and (S.Flurry:Charges() >= 1 or RemainingWintersChill > 0 or EnemiesCount8ySplash < 5 and Freezable() and S.IceNova:CooldownUp() and Player:BuffDown(S.FingersofFrostBuff))) then
    if Cast(S.GlacialSpike, nil, nil, not Target:IsSpellInRange(S.GlacialSpike)) then return "glacial_spike aoe_ss 20"; end
  end
  -- ice_lance,if=buff.fingers_of_frost.react&!prev_gcd.1.glacial_spike|remaining_winters_chill
  if S.IceLance:IsReady() and (Player:BuffUp(S.FingersofFrostBuff) and not Player:PrevGCDP(1, S.GlacialSpike) or RemainingWintersChill > 0) then
    if Cast(S.IceLance, nil, nil, not Target:IsSpellInRange(S.IceLance)) then return "ice_lance aoe_ss 22"; end
  end
  -- flurry,if=cooldown_react&remaining_winters_chill=0
  if S.Flurry:IsCastable() and (RemainingWintersChill == 0) then
    if Cast(S.Flurry, Settings.Frost.GCDasOffGCD.Flurry, nil, not Target:IsSpellInRange(S.Flurry)) then return "flurry aoe_ss 24"; end
  end
  -- frostbolt
  if Bolt:IsCastable() then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostbolt aoe_ss 26"; end
  end
  -- call_action_list,name=movement
  if Player:IsMoving() then
    local ShouldReturn = Movement(); if ShouldReturn then return ShouldReturn; end
  end
end

local function CleaveFF()
  -- comet_storm,if=prev_gcd.1.flurry
  if S.CometStorm:IsCastable() and (Player:PrevGCDP(1, S.Flurry)) then
    if Cast(S.CometStorm, Settings.Frost.GCDasOffGCD.CometStorm, nil, not Target:IsSpellInRange(S.CometStorm)) then return "comet_storm cleave_ff 2"; end
  end
  -- frostfire_bolt,if=talent.deaths_chill&buff.icy_veins.remains>9&(buff.deaths_chill.stack<6|buff.deaths_chill.stack=6&!action.frostfire_bolt.in_flight)
  if Bolt:IsCastable() and (S.DeathsChill:IsAvailable() and Player:BuffRemains(S.IcyVeinsBuff) > 9 and (Player:BuffStack(S.DeathsChillBuff) < 6 or Player:BuffStack(S.DeathsChillBuff) == 6 and not Bolt:InFlight())) then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostfire_bolt cleave_ff 4"; end
  end
  -- freeze,if=freezable&prev_gcd.1.glacial_spike
  if Pet:IsActive() and S.Freeze:IsCastable() and (Freezable() and Player:PrevGCDP(1, S.GlacialSpike)) then
    if Cast(S.Freeze, nil, nil, not Target:IsSpellInRange(S.Freeze)) then return "freeze cleave_ff 6"; end
  end
  -- ice_nova,if=freezable&prev_gcd.1.glacial_spike&remaining_winters_chill=0&debuff.winters_chill.down&!prev_off_gcd.freeze
  if S.IceNova:IsCastable() and (Freezable() and Player:PrevGCDP(1, S.GlacialSpike) and RemainingWintersChill == 0 and Target:DebuffDown(S.WintersChillDebuff) and not Player:PrevOffGCDP(1, S.Freeze)) then
    if Cast(S.IceNova, nil, nil, not Target:IsSpellInRange(S.IceNova)) then return "ice_nova cleave_ff 8"; end
  end
  -- flurry,if=cooldown_react&remaining_winters_chill=0&debuff.winters_chill.down&(prev_gcd.1.glacial_spike|buff.icicles.react>=3)&!prev_off_gcd.freeze
  if S.Flurry:IsCastable() and (RemainingWintersChill == 0 and Target:DebuffDown(S.WintersChillDebuff) and (Player:PrevGCDP(1, S.GlacialSpike) or Icicles >= 3) and not Player:PrevOffGCDP(1, S.Freeze)) then
    if Cast(S.Flurry, Settings.Frost.GCDasOffGCD.Flurry, nil, not Target:IsSpellInRange(S.Flurry)) then return "flurry cleave_ff 10"; end
  end
  -- flurry,target_if=min:debuff.winters_chill.stack,if=cooldown_react&prev_gcd.1.glacial_spike&!prev_off_gcd.freeze
  if S.Flurry:IsCastable() and (Player:PrevGCDP(1, S.GlacialSpike) and not Player:PrevOffGCDP(1, S.Freeze)) then
    if Everyone.CastTargetIf(S.Flurry, Enemies16ySplash, "min", EvaluateTargetIfFilterWCStacks, nil, not Target:IsSpellInRange(S.Flurry), Settings.Frost.GCDasOffGCD.Flurry) then return "flurry cleave_ff 12"; end
  end
  -- glacial_spike,if=buff.icicles.react=5
  if S.GlacialSpike:IsReady() and (Icicles == 5) then
    if Cast(S.GlacialSpike, nil, nil, not Target:IsSpellInRange(S.GlacialSpike)) then return "glacial_spike cleave_ff 14"; end
  end
  -- ray_of_frost,target_if=max:debuff.winters_chill.stack,if=remaining_winters_chill
  if S.RayofFrost:IsCastable() and (RemainingWintersChill > 0) then
    if Everyone.CastTargetIf(S.RayofFrost, Enemies16ySplash, "max", EvaluateTargetIfFilterWCStacks, nil, not Target:IsSpellInRange(S.RayofFrost), Settings.Frost.GCDasOffGCD.RayOfFrost) then return "flurry cleave_ff 16"; end
  end
  -- frostfire_bolt,if=buff.frostfire_empowerment.react&!buff.excess_frost.react&!buff.excess_fire.react
  if Bolt:IsReady() and (Player:BuffUp(S.FrostfireEmpowermentBuff) and Player:BuffDown(S.ExcessFrostBuff) and Player:BuffDown(S.ExcessFireBuff)) then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostfire_bolt cleave_ff 18"; end
  end
  -- frozen_orb,if=!buff.fingers_of_frost.react
  if S.FrozenOrb:IsCastable() and (Player:BuffDown(S.FingersofFrostBuff)) then
    if Cast(S.FrozenOrb, Settings.Frost.GCDasOffGCD.FrozenOrb, nil, not Target:IsInRange(40)) then return "frozen_orb cleave_ff 20"; end
  end
  -- shifting_power,if=cooldown.icy_veins.remains>10&cooldown.frozen_orb.remains>10&(!talent.comet_storm|cooldown.comet_storm.remains>10)&(!talent.ray_of_frost|cooldown.ray_of_frost.remains>10)&(fight_remains+10>cooldown.icy_veins.remains)
  if CDsON() and S.ShiftingPower:IsCastable() and (S.IcyVeins:CooldownRemains() > 10 and S.FrozenOrb:CooldownRemains() > 10 and (not S.CometStorm:IsAvailable() or S.CometStorm:CooldownRemains() > 10) and (not S.RayofFrost:IsAvailable() or S.RayofFrost:CooldownRemains() > 10) and (FightRemains + 10 > S.IcyVeins:CooldownRemains())) then
    if Cast(S.ShiftingPower, nil, Settings.CommonsDS.DisplayStyle.ShiftingPower, not Target:IsInRange(18)) then return "shifting_power cleave_ff 22"; end
  end
  -- ice_lance,target_if=max:debuff.winters_chill.stack,if=buff.fingers_of_frost.react&!prev_gcd.1.glacial_spike|remaining_winters_chill&!variable.boltspam
  if S.IceLance:IsReady() and (Player:BuffUp(S.FingersofFrostBuff) and not Player:PrevGCDP(1, S.GlacialSpike) or RemainingWintersChill > 0 and not VarBoltSpam) then
    if Everyone.CastTargetIf(S.IceLance, Enemies16ySplash, "max", EvaluateTargetIfFilterWCStacks, nil, not Target:IsSpellInRange(S.IceLance)) then return "ice_lance cleave_ff 24"; end
  end
  -- blizzard,if=talent.ice_caller&buff.freezing_rain.up&!talent.deaths_chill
  if S.Blizzard:IsCastable() and (S.IceCaller:IsAvailable() and Player:BuffUp(S.FreezingRainBuff) and not S.DeathsChill:IsAvailable()) then
    if Cast(S.Blizzard, Settings.Frost.GCDasOffGCD.Blizzard, nil, not Target:IsInRange(40)) then return "blizzard cleave_ff 26"; end
  end
  -- frostfire_bolt
  if Bolt:IsCastable() then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostfire_bolt cleave_ff 28"; end
  end
  -- call_action_list,name=movement
  if Player:IsMoving() then
    local ShouldReturn = Movement(); if ShouldReturn then return ShouldReturn; end
  end
end

local function CleaveSS()
  -- comet_storm,if=prev_gcd.1.flurry&(buff.icy_veins.down)
  if S.CometStorm:IsCastable() and (Player:PrevGCDP(1, S.Flurry) and Player:BuffDown(S.IcyVeinsBuff)) then
    if Cast(S.CometStorm, Settings.Frost.GCDasOffGCD.CometStorm, nil, not Target:IsSpellInRange(S.CometStorm)) then return "comet_storm cleave_ss 2"; end
  end
  -- freeze,if=freezable&prev_gcd.1.glacial_spike
  if Pet:IsActive() and S.Freeze:IsReady() and (Freezable() and Player:PrevGCDP(1, S.GlacialSpike)) then
    if Cast(S.Freeze, nil, nil, not Target:IsSpellInRange(S.Freeze)) then return "freeze cleave_ss 4"; end
  end
  -- flurry,if=cooldown_react&remaining_winters_chill=0&debuff.winters_chill.down&(prev_gcd.1.frostbolt|prev_gcd.1.glacial_spike)
  if S.Flurry:IsCastable() and (RemainingWintersChill == 0 and Target:DebuffDown(S.WintersChillDebuff) and (Player:PrevGCDP(1, S.Frostbolt) or Player:PrevGCDP(1, S.GlacialSpike))) then
    if Cast(S.Flurry, Settings.Frost.GCDasOffGCD.Flurry, nil, not Target:IsSpellInRange(S.Flurry)) then return "flurry cleave_ss 6"; end
  end
  -- flurry,target_if=min:debuff.winters_chill.stack,if=cooldown_react&prev_gcd.1.glacial_spike
  if S.Flurry:IsCastable() and (Player:PrevGCDP(1, S.GlacialSpike)) then
    if Everyone.CastTargetIf(S.Flurry, Enemies16ySplash, "min", EvaluateTargetIfFilterWCStacks, nil, not Target:IsSpellInRange(S.Flurry), Settings.Frost.GCDasOffGCD.Flurry) then return "flurry cleave_ss 8"; end
  end
  -- ice_nova,if=freezable&!prev_off_gcd.freeze&prev_gcd.1.glacial_spike&remaining_winters_chill=0&debuff.winters_chill.down
  if S.IceNova:IsCastable() and (Freezable() and not Player:PrevOffGCDP(1, S.Freeze) and Player:PrevGCDP(1, S.GlacialSpike) and RemainingWintersChill == 0 and Target:DebuffDown(S.WintersChillDebuff)) then
    if Cast(S.IceNova, nil, Settings.Frost.DisplayStyle.Movement, not Target:IsSpellInRange(S.IceNova)) then return "ice_nova cleave_ss 10"; end
  end
  -- frozen_orb,if=cooldown_react&(cooldown.icy_veins.remains>22|buff.icy_veins.up)
  if S.FrozenOrb:IsCastable() and (S.IcyVeins:CooldownRemains() > 22 or Player:BuffUp(S.IcyVeinsBuff)) then
    if Cast(S.FrozenOrb, Settings.Frost.GCDasOffGCD.FrozenOrb, nil, not Target:IsInRange(40)) then return "frozen_orb cleave_ss 12"; end
  end
  -- shifting_power,if=cooldown.icy_veins.remains>10&!action.flurry.cooldown_react&(buff.icy_veins.down|buff.icy_veins.remains>10)&(fight_remains+10>cooldown.icy_veins.remains)
  if CDsON() and S.ShiftingPower:IsCastable() and (S.IcyVeins:CooldownRemains() > 10 and S.Flurry:CooldownDown() and (Player:BuffDown(S.IcyVeinsBuff) or Player:BuffRemains(S.IcyVeinsBuff) > 10) and (FightRemains + 10 > S.IcyVeins:CooldownRemains())) then
    if Cast(S.ShiftingPower, nil, Settings.CommonsDS.DisplayStyle.ShiftingPower, not Target:IsInRange(18)) then return "shifting_power cleave_ss 14"; end
  end
  -- glacial_spike,if=buff.icicles.react=5&(action.flurry.cooldown_react|remaining_winters_chill|freezable&cooldown.ice_nova.ready&!buff.fingers_of_frost.react)
  if S.GlacialSpike:IsReady() and (Icicles == 5 and (S.Flurry:CooldownUp() or RemainingWintersChill > 0 or Freezable() and S.IceNova:CooldownUp() and Player:BuffDown(S.FingersofFrostBuff))) then
    if Cast(S.GlacialSpike, nil, nil, not Target:IsSpellInRange(S.GlacialSpike)) then return "glacial_spike cleave_ss 16"; end
  end
  -- ray_of_frost,if=remaining_winters_chill&buff.icy_veins.down
  if S.RayofFrost:IsCastable() and (RemainingWintersChill > 0 and Player:BuffDown(S.IcyVeinsBuff)) then
    if Cast(S.RayofFrost, Settings.Frost.GCDasOffGCD.RayOfFrost, nil, not Target:IsSpellInRange(S.RayofFrost)) then return "ray_of_frost cleave_ss 18"; end
  end
  -- frostbolt,if=talent.deaths_chill&buff.icy_veins.remains>9&(buff.deaths_chill.stack<(8+4*talent.slick_ice)|buff.deaths_chill.stack=(8+4*talent.slick_ice)&!action.frostbolt.in_flight)
  if Bolt:IsCastable() and (S.DeathsChill:IsAvailable() and Player:BuffRemains(S.IcyVeinsBuff) > 9 and (Player:BuffStack(S.DeathsChillBuff) < (8 + 4 * num(S.SlickIce:IsAvailable())) or Player:BuffStack(S.DeathsChillBuff) == (8 + 4 * num(S.SlickIce:IsAvailable())) and not Bolt:InFlight())) then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostbolt cleave_ss 20"; end
  end
  -- ice_lance,if=buff.fingers_of_frost.react&!prev_gcd.1.glacial_spike|!variable.boltspam&remaining_winters_chill
  if S.IceLance:IsReady() and (Player:BuffUp(S.FingersofFrostBuff) and not Player:PrevGCDP(1, S.GlacialSpike)) then
    if Cast(S.IceLance, nil, nil, not Target:IsSpellInRange(S.IceLance)) then return "ice_lance cleave_ss 22"; end
  end
  -- frostbolt
  if Bolt:IsCastable() then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostbolt cleave_ss 24"; end
  end
  -- call_action_list,name=movement
  if Player:IsMoving() then
    local ShouldReturn = Movement(); if ShouldReturn then return ShouldReturn; end
  end
end

local function STFF()
  -- comet_storm,if=prev_gcd.1.flurry
  if S.CometStorm:IsCastable() and (Player:PrevGCDP(1, S.Flurry)) then
    if Cast(S.CometStorm, Settings.Frost.GCDasOffGCD.CometStorm, nil, not Target:IsSpellInRange(S.CometStorm)) then return "comet_storm st_ff 2"; end
  end
  -- flurry,if=variable.boltspam&cooldown_react&buff.icicles.react<5&remaining_winters_chill=0
  if S.Flurry:IsCastable() and (VarBoltSpam and Icicles < 5 and RemainingWintersChill == 0) then
    if Cast(S.Flurry, Settings.Frost.GCDasOffGCD.Flurry, nil, not Target:IsSpellInRange(S.Flurry)) then return "flurry st_ff 4"; end
  end
  -- flurry,if=!variable.boltspam&cooldown_react&buff.icicles.react<5&remaining_winters_chill=0&debuff.winters_chill.down&(prev_gcd.1.frostfire_bolt|prev_gcd.1.glacial_spike)
  if S.Flurry:IsCastable() and (not VarBoltSpam and Icicles < 5 and RemainingWintersChill == 0 and Target:DebuffDown(S.WintersChillDebuff) and (Player:PrevGCDP(1, Bolt) or Player:PrevGCDP(1, S.GlacialSpike))) then
    if Cast(S.Flurry, Settings.Frost.GCDasOffGCD.Flurry, nil, not Target:IsSpellInRange(S.Flurry)) then return "flurry st_ff 6"; end
  end
  -- ice_lance,if=variable.boltspam&buff.excess_fire.react&!buff.brain_freeze.react
  if S.IceLance:IsReady() and (VarBoltSpam and Player:BuffUp(S.ExcessFireBuff) and Player:BuffDown(S.BrainFreezeBuff)) then
    if Cast(S.IceLance, nil, nil, not Target:IsSpellInRange(S.IceLance)) then return "ice_lance st_ff 8"; end
  end
  -- glacial_spike,if=buff.icicles.react=5
  if S.GlacialSpike:IsReady() and (Icicles == 5) then
    if Cast(S.GlacialSpike, nil, nil, not Target:IsSpellInRange(S.GlacialSpike)) then return "glacial_spike st_ff 10"; end
  end
  -- ray_of_frost,if=remaining_winters_chill&(!variable.boltspam|buff.icy_veins.remains<15)
  if S.RayofFrost:IsCastable() and (RemainingWintersChill > 0 and (not VarBoltSpam or Player:BuffRemains(S.IcyVeinsBuff) < 15)) then
    if Cast(S.RayofFrost, Settings.Frost.GCDasOffGCD.RayOfFrost, nil, not Target:IsSpellInRange(S.RayofFrost)) then return "ray_of_frost st_ff 12"; end
  end
  -- frozen_orb,if=variable.boltspam&buff.icy_veins.down|!variable.boltspam&!buff.fingers_of_frost.react
  if S.FrozenOrb:IsCastable() and (VarBoltSpam and Player:BuffDown(S.IcyVeinsBuff) or not VarBoltSpam and Player:BuffDown(S.FingersofFrostBuff)) then
    if Cast(S.FrozenOrb, Settings.Frost.GCDasOffGCD.FrozenOrb, nil, not Target:IsInRange(40)) then return "frozen_orb st_ff 14"; end
  end
  -- shifting_power,if=(buff.icy_veins.down|!variable.boltspam)&cooldown.icy_veins.remains>10&cooldown.frozen_orb.remains>10&(!talent.comet_storm|cooldown.comet_storm.remains>10)&(!talent.ray_of_frost|cooldown.ray_of_frost.remains>10)&(fight_remains+10>cooldown.icy_veins.remains)
  if CDsON() and S.ShiftingPower:IsCastable() and ((Player:BuffDown(S.IcyVeinsBuff) or not VarBoltSpam) and S.IcyVeins:CooldownRemains() > 10 and S.FrozenOrb:CooldownRemains() > 10 and (not S.CometStorm:IsAvailable() or S.CometStorm:CooldownRemains() > 10) and (not S.RayofFrost:IsAvailable() or S.RayofFrost:CooldownRemains() > 10) and (FightRemains + 10 > S.IcyVeins:CooldownRemains())) then
    if Cast(S.ShiftingPower, nil, Settings.CommonsDS.DisplayStyle.ShiftingPower, not Target:IsInRange(18)) then return "shifting_power st_ff 16"; end
  end
  -- ice_lance,if=!variable.boltspam&(buff.fingers_of_frost.react&!prev_gcd.1.glacial_spike|remaining_winters_chill)
  if S.IceLance:IsReady() and (not VarBoltSpam and (Player:BuffUp(S.FingersofFrostBuff) and not Player:PrevGCDP(1, S.GlacialSpike) or RemainingWintersChill > 0)) then
    if Cast(S.IceLance, nil, nil, not Target:IsSpellInRange(S.IceLance)) then return "ice_lance st_ff 18"; end
  end
  -- frostfire_bolt
  if Bolt:IsCastable() then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostfire_bolt st_ff 20"; end
  end
  -- call_action_list,name=movement
  if Player:IsMoving() then
    local ShouldReturn = Movement(); if ShouldReturn then return ShouldReturn; end
  end
end

local function STSS()
  -- comet_storm,if=prev_gcd.1.flurry&buff.icy_veins.down
  if S.CometStorm:IsCastable() and (Player:PrevGCDP(1, S.Flurry) and Player:BuffDown(S.IcyVeinsBuff)) then
    if Cast(S.CometStorm, Settings.Frost.GCDasOffGCD.CometStorm, nil, not Target:IsSpellInRange(S.CometStorm)) then return "comet_storm st_ss 2"; end
  end
  -- flurry,if=cooldown_react&remaining_winters_chill=0&debuff.winters_chill.down&(prev_gcd.1.frostbolt|prev_gcd.1.glacial_spike)
  if S.Flurry:IsCastable() and (RemainingWintersChill == 0 and Target:DebuffDown(S.WintersChillDebuff) and (Player:PrevGCDP(1, S.Frostbolt) or Player:PrevGCDP(1, S.GlacialSpike))) then
    if Cast(S.Flurry, Settings.Frost.GCDasOffGCD.Flurry, nil, not Target:IsSpellInRange(S.Flurry)) then return "flurry st_ss 4"; end
  end
  -- frozen_orb,if=cooldown_react&(cooldown.icy_veins.remains>22|buff.icy_veins.up)
  if S.FrozenOrb:IsCastable() and (S.IcyVeins:CooldownRemains() > 22 or Player:BuffUp(S.IcyVeinsBuff)) then
    if Cast(S.FrozenOrb, Settings.Frost.GCDasOffGCD.FrozenOrb, nil, not Target:IsInRange(40)) then return "frozen_orb st_ss 6"; end
  end
  -- glacial_spike,if=buff.icicles.react=5&(action.flurry.cooldown_react|remaining_winters_chill|cooldown.flurry.remains<action.glacial_spike.execute_time&cooldown.flurry.remains>0)
  if S.GlacialSpike:IsReady() and (Icicles == 5 and (S.Flurry:CooldownUp() or RemainingWintersChill > 0 or S.Flurry:CooldownRemains() < S.GlacialSpike:ExecuteTime() and S.Flurry:CooldownDown())) then
    if Cast(S.GlacialSpike, nil, nil, not Target:IsSpellInRange(S.GlacialSpike)) then return "glacial_spike st_ss 8"; end
  end
  -- ray_of_frost,if=variable.boltspam&remaining_winters_chill&buff.icy_veins.down
  if S.RayofFrost:IsCastable() and (VarBoltSpam and RemainingWintersChill > 0 and Player:BuffDown(S.IcyVeinsBuff)) then
    if Cast(S.RayofFrost, Settings.Frost.GCDasOffGCD.RayOfFrost, nil, not Target:IsSpellInRange(S.RayofFrost)) then return "ray_of_frost st_ss 10"; end
  end
  -- ray_of_frost,if=!variable.boltspam&remaining_winters_chill=1
  if S.RayofFrost:IsCastable() and (not VarBoltSpam and RemainingWintersChill == 1) then
    if Cast(S.RayofFrost, Settings.Frost.GCDasOffGCD.RayOfFrost, nil, not Target:IsSpellInRange(S.RayofFrost)) then return "ray_of_frost st_ss 12"; end
  end
  -- shifting_power,if=cooldown.icy_veins.remains>10&!action.flurry.cooldown_react&(variable.boltspam|buff.icy_veins.down|buff.icy_veins.remains>10)&(fight_remains+10>cooldown.icy_veins.remains)
  if CDsON() and S.ShiftingPower:IsCastable() and (S.IcyVeins:CooldownRemains() > 10 and S.Flurry:CooldownDown() and (VarBoltSpam or Player:BuffDown(S.IcyVeinsBuff) or Player:BuffRemains(S.IcyVeinsBuff) > 10) and (FightRemains + 10 > S.IcyVeins:CooldownRemains())) then
    if Cast(S.ShiftingPower, nil, Settings.CommonsDS.DisplayStyle.ShiftingPower, not Target:IsInRange(18)) then return "shifting_power st_ss 14"; end
  end
  -- frostbolt,if=variable.boltspam&buff.icy_veins.remains>9&buff.deaths_chill.stack<8
  if Bolt:IsCastable() and (VarBoltSpam and Player:BuffRemains(S.IcyVeinsBuff) > 9 and Player:BuffStack(S.DeathsChillBuff) < 8) then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostbolt st_ss 16"; end
  end
  -- ice_lance,if=variable.boltspam&(remaining_winters_chill=2|remaining_winters_chill&action.flurry.cooldown_react)
  if S.IceLance:IsReady() and (VarBoltSpam and (RemainingWintersChill == 2 or RemainingWintersChill > 0 and S.Flurry:CooldownUp())) then
    if Cast(S.IceLance, nil, nil, not Target:IsSpellInRange(S.IceLance)) then return "ice_lance st_ss 18"; end
  end
  -- ice_lance,if=!variable.boltspam&(buff.fingers_of_frost.react&!prev_gcd.1.glacial_spike|remaining_winters_chill)
  if S.IceLance:IsReady() and (not VarBoltSpam and (Player:BuffUp(S.FingersofFrostBuff) and not Player:PrevGCDP(1, S.GlacialSpike) or RemainingWintersChill > 0)) then
    if Cast(S.IceLance, nil, nil, not Target:IsSpellInRange(S.IceLance)) then return "ice_lance st_ss 20"; end
  end
  -- frostbolt
  if Bolt:IsCastable() then
    if Cast(Bolt, nil, nil, not Target:IsSpellInRange(Bolt)) then return "frostbolt st_ss 18"; end
  end
  -- call_action_list,name=movement
  if Player:IsMoving() then
    local ShouldReturn = Movement(); if ShouldReturn then return ShouldReturn; end
  end
end

--- ===== APL Main =====
local function APL()
  -- Enemies Update
  Enemies16ySplash = Target:GetEnemiesInSplashRange(16)
  if AoEON() then
    EnemiesCount8ySplash = Target:GetEnemiesInSplashRangeCount(8)
    EnemiesCount16ySplash = Target:GetEnemiesInSplashRangeCount(16)
  else
    EnemiesCount8ySplash = 1
    EnemiesCount16ySplash = 1
  end

  -- Check our IF status
  -- Note: Not referenced in the current APL, but saving for potential use later
  --Mage.IFTracker()

  if Everyone.TargetIsValid() or Player:AffectingCombat() then
    -- Calculate fight_remains
    BossFightRemains = HL.BossFightRemains()
    FightRemains = BossFightRemains
    if FightRemains == 11111 then
      FightRemains = HL.FightRemains(Enemies16ySplash, false)
    end

    -- Calculate remaining_winters_chill and icicles, as it's used in many lines
    if AoEON() and EnemiesCount16ySplash > 1 then
      RemainingWintersChill = CalculateWintersChill(Enemies16ySplash)
    else
      RemainingWintersChill = Target:DebuffStack(S.WintersChillDebuff)
    end
    Icicles = Player:BuffStackP(S.IciclesBuff)

    -- Calculate GCDMax
    GCDMax = Player:GCD() + 0.25
  end

  if Everyone.TargetIsValid() then
    -- call precombat
    if not Player:AffectingCombat() then
      local ShouldReturn = Precombat(); if ShouldReturn then return ShouldReturn; end
    end
    -- counterspell
    local ShouldReturn = Everyone.Interrupt(S.Counterspell, Settings.CommonsDS.DisplayStyle.Interrupts, false); if ShouldReturn then return ShouldReturn; end
    -- Force Flurry in opener
    if S.Flurry:IsCastable() and (HL.CombatTime() < 5 and (Player:IsCasting(Bolt) or Player:PrevGCDP(1, Bolt))) then
      if Cast(S.Flurry, Settings.Frost.GCDasOffGCD.Flurry, nil, not Target:IsSpellInRange(S.Flurry)) then return "flurry opener"; end
    end
    -- call_action_list,name=cds
    -- Note: CDs() includes Trinkets/Items/Potion, so checking CDsON() within the function instead.
    local ShouldReturn = CDs(); if ShouldReturn then return ShouldReturn; end
    -- run_action_list,name=aoe_ff,if=talent.frostfire_bolt&active_enemies>=3
    if AoEON() and (S.FrostfireBolt:IsAvailable() and EnemiesCount16ySplash >= 3) then
      local ShouldReturn = AoEFF(); if ShouldReturn then return ShouldReturn; end
      if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool for AoeFF()"; end
    end
    -- run_action_list,name=aoe_ss,if=active_enemies>=3
    if AoEON() and (EnemiesCount16ySplash >= 3) then
      local ShouldReturn = AoESS(); if ShouldReturn then return ShouldReturn; end
      if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool for AoeSS()"; end
    end
    -- run_action_list,name=cleave_ff,if=talent.frostfire_bolt&active_enemies=2
    if AoEON() and (S.FrostfireBolt:IsAvailable() and EnemiesCount16ySplash == 2) then
      local ShouldReturn = CleaveFF(); if ShouldReturn then return ShouldReturn; end
      if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool for CleaveFF()"; end
    end
    -- run_action_list,name=cleave_ss,if=active_enemies=2
    if AoEON() and (EnemiesCount16ySplash == 2) then
      local ShouldReturn = CleaveSS(); if ShouldReturn then return ShouldReturn; end
      if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool for CleaveSS()"; end
    end
    -- run_action_list,name=st_ff,if=talent.frostfire_bolt
    if S.FrostfireBolt:IsAvailable() then
      local ShouldReturn = STFF(); if ShouldReturn then return ShouldReturn; end
      if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool for STFF()"; end
    end
    -- run_action_list,name=st_ss
    local ShouldReturn = STSS(); if ShouldReturn then return ShouldReturn; end
    if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool for STSS()"; end
  end
end

local function Init()
  S.WintersChillDebuff:RegisterAuraTracking()

  HR.Print("Frost Mage rotation has been updated for patch 11.0.5.")
end

HR.SetAPL(64, APL, Init)
