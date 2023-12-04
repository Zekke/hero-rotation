--- ============================ HEADER ============================
--- ======= LOCALIZE =======
-- Addon
local addonName, addonTable = ...
-- HeroDBC
local DBC    = HeroDBC.DBC
-- HeroLib
local HL     = HeroLib
local Cache  = HeroCache
local HR     = HeroRotation
local Unit   = HL.Unit
local Player = Unit.Player
local Target = Unit.Target
local Pet    = Unit.Pet
local Spell  = HL.Spell
local Item   = HL.Item
-- Lua
local C_TimerAfter = C_Timer.After
-- File Locals
HR.Commons.Hunter = {}
local Hunter = HR.Commons.Hunter

Hunter.Pet = {}

-- Pet Statuses are 0 (dismissed), 1 (alive), or 2 (dead/feigned)
Hunter.Pet.Status = (Pet:Exists()) and 1 or 0
Hunter.Pet.GUID = (Pet:Exists()) and Pet:GUID() or 0
Hunter.Pet.FeignGUID = 0

HL:RegisterForEvent(
  function()
    if Hunter.Pet.Status == 0 and Pet:Exists() then
      Hunter.Pet.Status = 1
      Hunter.Pet.GUID = Pet:GUID()
      Hunter.Pet.FeignGUID = 0
    end
  end
  , "SPELLS_CHANGED"
)

HL:RegisterForSelfCombatEvent(
  function(...)
    local _, _, _, _, _, _, _, _, _, _, _, SpellID = ...
    if SpellID == 2641 then
      -- Delay for 1s, as SPELL_CAST_SUCCESS fires before SPELLS_CHANGED when casting Dismiss Pet.
      C_TimerAfter(1, function()
        Hunter.Pet.Status = 0
        Hunter.Pet.GUID = 0
        Hunter.Pet.FeignGUID = 0
      end)
    end
    if SpellID == 982 then
      C_TimerAfter(1, function()
        Hunter.Pet.Status = 1
        Hunter.Pet.GUID = Pet:GUID()
        Hunter.Pet.FeignGUID = 0
      end)
    end
  end
  , "SPELL_CAST_SUCCESS"
)

HL:RegisterForCombatEvent(
  function(...)
    local _, _, _, _, _, _, _, DestGUID = ...
    if DestGUID == Hunter.Pet.GUID then
      Hunter.Pet.Status = 2
      Hunter.Pet.GUID = 0
    elseif DestGUID == Player:GUID() and Hunter.Pet.Status ~= 2 then
      Hunter.Pet.Status = 0
      Hunter.Pet.GUID = 0
    end
  end
  , "UNIT_DIED"
)

HL:RegisterForEvent(
  function(...)
    local _, CasterUnit, _, SpellID = ...
    if CasterUnit ~= "player" then return end
    if SpellID == 209997 then
      Hunter.Pet.FeignGUID = Hunter.Pet.GUID
    end
    if SpellID == 210000 and Hunter.Pet.FeignGUID ~= 0 then
      Hunter.Pet.GUID = Hunter.Pet.FeignGUID
      Hunter.Pet.FeignGUID = 0
      Hunter.Pet.Status = 1
    end
  end
  , "UNIT_SPELLCAST_SUCCEEDED"
)

HL:RegisterForEvent(
  function(...)
    -- CHALLENGE_MODE_START is called at the start of a Mythic+ dungeon, which despawns the pet
    Hunter.Pet.GUID = 0
    Hunter.Pet.FeignGUID = 0
    Hunter.Pet.Status = 0
  end
  , "CHALLENGE_MODE_START"
)
