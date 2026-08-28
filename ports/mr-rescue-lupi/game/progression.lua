local Progression = {}

local boss_sections = { 8, 11, 15 }
local campaign_floor_counts = { 21, 30, 42 }

function Progression.bossSection(difficulty)
  assert(difficulty >= 1 and difficulty <= 3)
  return boss_sections[difficulty]
end

function Progression.isBoss(section, difficulty)
  return section == Progression.bossSection(difficulty)
end

function Progression.internalSection(section, difficulty)
  assert(section >= 1 and section <= Progression.bossSection(difficulty))
  return section + (difficulty - 1) * 5
end

function Progression.maximumCasualties(difficulty)
  assert(difficulty >= 1 and difficulty <= 3)
  return 6 - difficulty
end

function Progression.floorRange(section)
  assert(section >= 1)
  local first = section * 3 - 2
  return first, first + 2
end

function Progression.floorCount(difficulty)
  assert(difficulty >= 1 and difficulty <= 3)
  return campaign_floor_counts[difficulty]
end

return Progression
