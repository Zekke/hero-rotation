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
local S = Spell.Priest.Holy
local I = Item.Priest.Holy

--- ===== GUI Settings =====
local Everyone = HR.Commons.Everyone
local Settings = {
  General = HR.GUISettings.General,
  Commons = HR.GUISettings.APL.Priest.Commons,
  CommonsDS = HR.GUISettings.APL.Priest.CommonsDS,
  CommonsOGCD = HR.GUISettings.APL.Priest.CommonsOGCD,
  Holy = HR.GUISettings.APL.Priest.Holy
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

local function Main()
  --holy fire
  if S.HolyFire:IsReady() then
    if Cast(S.HolyFire, nil, nil, not Target:IsSpellInRange(S.HolyFire)) then return "holy_fire main 2"; end
  end
  --holy word: chastise
  if S.HolyWordChastise:IsReady() then
    if Cast(S.HolyWordChastise, nil, nil, not Target:IsSpellInRange(S.HolyWordChastise)) then return "holy_word_chastise main 4"; end
  end
  --holy nova si max stack ou si melee >= 5
  if S.HolyNova:IsReady() and Enemies12yCount >= 5 then
    if Cast(S.HolyNova) then return "holy_nova main 6"; end
  end
  --shadow word: pain
  if S.ShadowWordPain:IsReady() and Target:DebuffDown(S.ShadowWordPainDebuff) then
    if Cast(S.ShadowWordPain, nil, nil, not Target:IsSpellInRange(S.ShadowWordPain)) then return "shadow_word_pain main 8"; end
  end
  --smite
  if S.Smite:IsReady() then
    if Cast(S.Smite, nil, nil, not Target:IsSpellInRange(S.Smite)) then return "smite main 10"; end
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
    local ShouldReturn = Main(); if ShouldReturn then return ShouldReturn; end
    if HR.CastAnnotated(S.Pool, false, "WAIT") then return "Pool for Main()"; end
  end
end

local function Init()
  HR.Print("Holy Priest damage rotation has been updated for patch 11.0.5.")
end

HR.SetAPL(257, APL, Init)
