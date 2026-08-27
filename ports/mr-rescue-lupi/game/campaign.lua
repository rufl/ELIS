local Profile = require("profile")

local Campaign = {
  score = 0,
  saved = 0,
  combo = 0,
  maximum_combo = 0,
  time_frames = 0,
  combo_frames = 0,
  statistics = { 0, 0, 0, 0, 0, 0 },
}

local scores = { {}, {}, {} }
for difficulty = 1, 3 do
  for rank = 1, 10 do
    scores[difficulty][rank] = { active = false, name = "     ", score = 0 }
  end
end

function Campaign.reset()
  Campaign.score = 0
  Campaign.saved = 0
  Campaign.combo = 0
  Campaign.maximum_combo = 0
  Campaign.time_frames = 0
  Campaign.combo_frames = 0
  Campaign.previous_x = nil
  Campaign.previous_y = nil
end

local function finishCombo()
  Campaign.maximum_combo = math.max(Campaign.maximum_combo, Campaign.combo)
  Campaign.combo = 0
end

function Campaign.updatePlayer(player)
  Campaign.time_frames = Campaign.time_frames + 1
  Campaign.combo_frames = Campaign.combo_frames + 1
  if Campaign.combo_frames > 4 * Profile.update_hz then finishCombo() end
  if player.spraying then Campaign.statistics[2] = Campaign.statistics[2] + 1 / 3 end
  if Campaign.previous_x ~= nil then
    local delta_x = player.x - Campaign.previous_x
    local delta_y = player.y - Campaign.previous_y
    Campaign.statistics[3] = Campaign.statistics[3] +
                             math.sqrt(delta_x * delta_x + delta_y * delta_y) / 16
  end
  Campaign.previous_x = player.x
  Campaign.previous_y = player.y
end

local function rescue()
  Campaign.saved = Campaign.saved + 1
  Campaign.statistics[4] = Campaign.statistics[4] + 1
  Campaign.combo_frames = 0
  Campaign.combo = Campaign.combo + 1
  if Campaign.combo < 3 then
    Campaign.score = Campaign.score + 250
  else
    Campaign.score = Campaign.score + (Campaign.combo - 1) * 250
  end
end

function Campaign.consumeWorld(world)
  local score, extinguished, rescues, property_damage = world.consumeEvents()
  Campaign.score = Campaign.score + score
  Campaign.statistics[1] = Campaign.statistics[1] + extinguished
  Campaign.statistics[5] = Campaign.statistics[5] + property_damage
  for _ = 1, rescues do rescue() end
end

function Campaign.floorCleared(award_score)
  Campaign.statistics[6] = Campaign.statistics[6] + 3
  if award_score then Campaign.score = Campaign.score + 1000 end
end

function Campaign.finalize()
  finishCombo()
end

function Campaign.timeString()
  local total_seconds = math.floor(Campaign.time_frames / Profile.update_hz)
  local hours = math.floor(total_seconds / 3600)
  local minutes = math.floor((total_seconds % 3600) / 60)
  local seconds = total_seconds % 60
  return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

function Campaign.highscore(difficulty, rank)
  local entry = scores[difficulty][rank]
  if entry.active then return entry.name, entry.score end
  return nil, 0
end

function Campaign.highscoreRank(difficulty)
  local entries = scores[difficulty]
  for rank = 1, 10 do
    if not entries[rank].active or entries[rank].score < Campaign.score then
      return rank
    end
  end
  return 0
end

function Campaign.addHighscore(difficulty, rank, name)
  if rank == 0 then return end
  local entries = scores[difficulty]
  for index = 10, rank + 1, -1 do
    entries[index].active = entries[index - 1].active
    entries[index].name = entries[index - 1].name
    entries[index].score = entries[index - 1].score
  end
  entries[rank].active = true
  entries[rank].name = name
  entries[rank].score = Campaign.score
end

function Campaign.award(index)
  local thresholds = {
    { 300, 900, 2000 },
    { 30000, 60000, 120000 },
    { 4000, 8000, 20000 },
    { 80, 160, 400 },
    { 18000, 35000, 90000 },
    { 80, 160, 500 },
  }
  local value = Campaign.statistics[index]
  if value > thresholds[index][3] then return "GOLD" end
  if value > thresholds[index][2] then return "SILVER" end
  if value > thresholds[index][1] then return "BRONZE" end
  return "NONE"
end

return Campaign
