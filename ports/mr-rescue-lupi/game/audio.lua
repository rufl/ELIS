-- Bounded recreations of the original 17 effects through the physical Lupi API.
local Audio = {}

local effects = {
  jump = { 1, 72, 0.5 },
  spray = { 2, 64, 0.5 },
  steam = { 3, 76, 0.5 },
  rescue = { 4, 84, 0.5 },
  door = { 5, 48, 0.5 },
  item = { 6, 88, 0.5 },
  enemy = { 7, 42, 0.5 },
  impact = { 8, 36, 0.5 },
  transform = { 9, 40, 0.5 },
  confirm = { 10, 79, 0.5 },
  blip = { 11, 67, 0.5 },
  empty = { 12, 45, 0.5 },
  glass = { 13, 91, 0.5 },
  throw = { 14, 55, 0.5 },
  casualty = { 15, 34, 0.5 },
  boss_jump = { 16, 38, 0.5 },
  explosion = { 17, 31, 0.5 },
}

function Audio.play(name)
  local effect = effects[name]
  assert(effect ~= nil)
  sfx.fx(effect[1], effect[2], effect[3])
end

return Audio
