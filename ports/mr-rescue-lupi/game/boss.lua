local Profile = require("profile")
local Audio = require("audio")

local Boss = {}
Boss.__index = Boss

local magma = {
  jump = Sprites.find("assets/magmahulk_jump"),
  land = Sprites.find("assets/magmahulk_land"),
  jump_hit = Sprites.find("assets/magmahulk_jump_hit"),
  land_hit = Sprites.find("assets/magmahulk_land_hit"),
  rage_jump = Sprites.find("assets/magmahulk_rage_jump"),
  rage_land = Sprites.find("assets/magmahulk_rage_land"),
}
local gas = {
  idle = Sprites.find("assets/gasleak_idle"),
  hit = Sprites.find("assets/gasleak_hit"),
  walk = Sprites.find("assets/gasleak_walk"),
  shot_walk = Sprites.find("assets/gasleak_shot_walk"),
  rage_walk = Sprites.find("assets/gasleak_rage_walk"),
  rage_shot_walk = Sprites.find("assets/gasleak_rage_shot_walk"),
  idle_shot = Sprites.find("assets/gasleak_idle_shot"),
  rage_idle_shot = Sprites.find("assets/gasleak_rage_idle_shot"),
  rage_idle = Sprites.find("assets/gasleak_rage_idle"),
  transition = Sprites.find("assets/gasleak_transition"),
  transition_last = Sprites.find("assets/gasleak_transition_1"),
}
local charcoal = {
  idle = Sprites.find("assets/charcoal_idle"),
  transform = Sprites.find("assets/charcoal_transform"),
  transform_rage = Sprites.find("assets/charcoal_transform_rage"),
  transition = Sprites.find("assets/charcoal_transition"),
  roll = Sprites.find("assets/charcoal_roll"),
  roll_rage = Sprites.find("assets/charcoal_roll_rage"),
  daze = Sprites.find("assets/charcoal_daze"),
  daze_hit = Sprites.find("assets/charcoal_daze_hit"),
  daze_rage = Sprites.find("assets/charcoal_daze_rage"),
}

local IDLE = 1
local JUMP = 2
local FLY = 3
local LAND = 4
local TRANSITION = 5
local DEAD = 6
local WALK = 7
local PUSHED = 8
local ROLL = 9
local DAZED = 10
local TRANSFORM = 11

local function cap(value, minimum, maximum)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

function Boss.create(kind)
  local self = setmetatable({}, Boss)
  self.kind = kind
  self.x = kind == 1 and 328 or 368
  self.y = 240
  self.speed_x = 0
  self.speed_y = 0
  self.direction = -1
  self.health_max = kind == 3 and 600 or 720
  self.health = self.health_max
  self.state = IDLE
  self.timer = 90
  self.animation = 0
  self.angry = false
  self.hit_frames = 0
  self.next_attack = kind == 2 and 150 or 60
  self.shockwave_frames = 0
  self.hit_ground = false
  self.defeated = false
  return self
end

local function setState(self, state, timer)
  self.state = state
  self.timer = timer or 0
  self.animation = 0
end

local function enterDead(self, world)
  setState(self, DEAD, 300)
  self.speed_x = 0
  self.speed_y = 0
  world.clearFireAndEnemies()
  Audio.play("explosion")
end

local function updateMagma(self, world, player)
  if self.state == IDLE then
    self.timer = self.timer - 1
    if self.timer <= 0 then setState(self, JUMP, 42) end
  elseif self.state == JUMP then
    self.timer = self.timer - 1
    if self.health <= 0 then
      enterDead(self, world)
    elseif not self.angry and self.health < self.health_max * 0.75 then
      setState(self, TRANSITION, 120)
    elseif self.timer <= 0 then
      setState(self, FLY)
      self.speed_y = -200 / Profile.update_hz
      self.hit_ground = false
      local target = cap(player.x, 194, 464)
      self.speed_x = cap(target - self.x, -128, 128) * 0.93 / Profile.update_hz
      Audio.play("boss_jump")
    end
  elseif self.state == FLY then
    self.speed_y = self.speed_y + 350 / (Profile.update_hz * Profile.update_hz)
    self.x = self.x + self.speed_x
    self.y = self.y + self.speed_y
    if self.speed_y > 0 and self.y > 208 then setState(self, LAND, 59) end
  elseif self.state == LAND then
    self.speed_y = self.speed_y + 350 / (Profile.update_hz * Profile.update_hz)
    self.y = self.y + self.speed_y
    if self.y >= 240 then
      if not self.hit_ground then
        world.addFire(math.floor((self.x - 8) / 16), math.floor((self.y - 5) / 16))
        world.addFire(math.floor((self.x + 8) / 16), math.floor((self.y - 5) / 16))
        if self.angry then self.shockwave_frames = 25 end
        self.hit_ground = true
        Audio.play("impact")
      end
      self.y = 240
      self.speed_y = 0
    else
      self.x = self.x + self.speed_x
    end
    self.timer = self.timer - 1
    if self.timer <= 0 then setState(self, JUMP, 42) end
  elseif self.state == TRANSITION then
    self.timer = self.timer - 1
    if self.timer <= 0 then
      self.angry = true
      setState(self, LAND, 59)
      self.hit_ground = true
      Audio.play("transform")
    end
  end
  self.x = cap(self.x, 194, 464)
  if self.shockwave_frames > 0 then self.shockwave_frames = self.shockwave_frames - 1 end
end

local function updateGas(self, world, player)
  if self.state == IDLE then
    self.timer = self.timer - 1
    if self.timer <= 0 then setState(self, WALK) end
  elseif self.state == WALK then
    self.x = self.x + self.direction * 40 / Profile.update_hz
    if math.abs(player.x - self.x) > 32 then
      self.direction = player.x < self.x and -1 or 1
    end
    self.next_attack = self.next_attack - 1
    if self.next_attack <= 0 then
      local delay = self.angry and 90 or 150
      self.next_attack = delay
      if not self.angry then
        world.spawnBossHazard(2, self.x + self.direction * 14, self.y - 46,
                              self.direction * 100 / Profile.update_hz, 0)
      else
        local selection = world.bossRandom(5) + 1
        if selection >= 4 or selection == 1 then
          world.spawnBossHazard(2, self.x + self.direction * 14, self.y - 46,
                                self.direction * 100 / Profile.update_hz, 0)
        end
        if selection >= 2 and selection <= 3 or selection == 1 then
          world.spawnBossHazard(2, self.x + self.direction * 14, self.y - 46,
                                self.direction * 100 / Profile.update_hz, 1.67)
        end
      end
      self.hit_frames = math.max(self.hit_frames, 24)
    end
    if self.health <= 0 then
      enterDead(self, world)
    elseif not self.angry and self.health < self.health_max * 0.75 then
      setState(self, TRANSITION, 102)
    end
  elseif self.state == PUSHED then
    self.x = self.x - self.direction * 40 / Profile.update_hz
    self.timer = self.timer - 1
    if self.health <= 0 then
      enterDead(self, world)
    elseif not self.angry and self.health < self.health_max * 0.75 then
      setState(self, TRANSITION, 102)
    elseif self.timer <= 0 then
      setState(self, WALK)
    end
  elseif self.state == TRANSITION then
    self.timer = self.timer - 1
    if self.timer <= 0 then
      self.angry = true
      setState(self, WALK)
      Audio.play("transform")
    end
  end
  self.x = cap(self.x, 194, 462)
end

local function spawnCoalBurst(self, world)
  local count = self.angry and 10 or 6
  for index = 1, count do
    local x = 168 + (320 / (count - 1)) * (index - 1)
    world.spawnBossHazard(3, x, -world.bossRandom(101), 0, 140 / Profile.update_hz)
  end
end

local function updateCharcoal(self, world, player)
  if self.state == IDLE then
    self.timer = self.timer - 1
    if self.timer <= 0 then setState(self, TRANSFORM, 160) end
  elseif self.state == TRANSFORM then
    self.timer = self.timer - 1
    if self.timer <= 0 then
      setState(self, ROLL)
      self.next_attack = 0
    end
  elseif self.state == ROLL then
    self.x = self.x + self.direction * 100 / Profile.update_hz
    if self.angry then
      self.next_attack = self.next_attack - 1
      if self.next_attack <= 0 then
        world.spawnBossHazard(3, player.x, 0, 0, 140 / Profile.update_hz)
        self.next_attack = 60
      end
    end
    if self.x < 190 or self.x > 466 then
      self.y = 240
      self.speed_y = -100 / Profile.update_hz
      self.direction = -self.direction
      self.speed_x = self.direction * 40 / Profile.update_hz
      setState(self, DAZED, 180)
      spawnCoalBurst(self, world)
    end
  elseif self.state == DAZED then
    self.timer = self.timer - 1
    self.speed_y = self.speed_y + 350 / (Profile.update_hz * Profile.update_hz)
    self.x = self.x + self.speed_x
    self.y = math.min(240, self.y + self.speed_y)
    if self.y >= 240 then
      self.speed_x = 0
      self.speed_y = 0
    end
    if self.health <= 0 then
      enterDead(self, world)
    elseif not self.angry and self.health < self.health_max * 0.75 then
      setState(self, TRANSITION, 120)
    elseif self.timer <= 0 then
      self.y = 240
      setState(self, TRANSFORM, 160)
    end
  elseif self.state == TRANSITION then
    self.timer = self.timer - 1
    if self.timer <= 0 then
      self.angry = true
      setState(self, TRANSFORM, 160)
      Audio.play("transform")
    end
  end
  self.x = cap(self.x, 190, 466)
end

function Boss:update(world, player)
  self.animation = self.animation + 1
  if self.hit_frames > 0 then self.hit_frames = self.hit_frames - 1 end
  if self.state == DEAD then
    self.timer = self.timer - 1
    if self.timer <= 0 then self.defeated = true end
    return
  end
  if self.kind == 1 then
    updateMagma(self, world, player)
  elseif self.kind == 2 then
    updateGas(self, world, player)
  else
    updateCharcoal(self, world, player)
  end
  if self.kind == 1 and self.shockwave_frames > 0 and player.y >= 235 then
    local width = (25 - self.shockwave_frames) * 6
    if math.abs(player.x - self.x) <= width then
      local direction = player.x < self.x and -1 or 1
      player.speed_x = player.speed_x + direction * 100 / Profile.update_hz
    end
  end
end

function Boss:hit(direction_x)
  if self.state == DEAD or self.state == TRANSITION then return false end
  if self.kind == 3 and self.state ~= DAZED then return false end
  self.health = math.max(0, self.health - 1)
  self.hit_frames = 12
  if self.kind == 2 then
    self.direction = direction_x == 0 and self.direction or -direction_x
    setState(self, PUSHED, 12)
  end
  return true
end

function Boss:heatAt(x, y)
  local half_height = self.kind == 2 and 60 or 34
  if math.abs(self.x - x) <= 16 and y >= self.y - half_height and y <= self.y then
    return 1
  end
  if self.kind == 1 and self.shockwave_frames > 0 and y >= 218 then
    local width = (25 - self.shockwave_frames) * 6
    if math.abs(self.x - x) <= width then return 1 end
  end
  return 0
end

local function drawGasTransition(self, screen_x, screen_y)
  local frame = math.min(9, math.floor(self.animation / 10))
  if frame < 9 then
    ui.tile(gas.transition, frame, screen_x - 20, screen_y - 128, self.direction < 0, false)
  else
    ui.tile(gas.transition_last, 0, screen_x - 20, screen_y - 128,
            self.direction < 0, false)
  end
end

function Boss:draw(camera_x, origin_y)
  local screen_x = math.floor(self.x - camera_x)
  local screen_y = math.floor(self.y + origin_y)
  if self.kind == 1 then
    local sprite = magma.jump
    local count = 5
    if self.state == FLY or self.state == LAND then sprite, count = magma.land, 7 end
    if self.angry then
      sprite = (self.state == FLY or self.state == LAND) and
               magma.rage_land or magma.rage_jump
    elseif self.hit_frames > 0 then
      sprite = (self.state == FLY or self.state == LAND) and
               magma.land_hit or magma.jump_hit
    end
    local frame = math.floor(self.animation / 8) % count
    ui.tile(sprite, frame, screen_x - 27, screen_y - 64, self.direction < 0, false)
    if self.shockwave_frames > 0 then
      local width = (25 - self.shockwave_frames) * 6
      ui.rectfill(screen_x - width, screen_y - 5, screen_x + width, screen_y - 1, 2)
    end
  elseif self.kind == 2 then
    if self.state == TRANSITION or self.state == DEAD then
      drawGasTransition(self, screen_x, screen_y)
    elseif self.state == PUSHED then
      ui.tile(gas.hit, math.floor(self.animation / 6) % 2,
              screen_x - 20, screen_y - 64, self.direction < 0, false)
    else
      local at_edge = self.x <= 194 or self.x >= 462
      local shooting = self.hit_frames > 0
      local sprite = gas.walk
      if self.angry then sprite = shooting and gas.rage_shot_walk or gas.rage_walk end
      if at_edge then
        if self.angry then sprite = shooting and gas.rage_idle_shot or gas.rage_idle
        else sprite = shooting and gas.idle_shot or gas.idle end
      end
      ui.tile(sprite, math.floor(self.animation / 8) % sprite.ntiles,
              screen_x - 20, screen_y - 128, self.direction < 0, false)
    end
  else
    local sprite = charcoal.idle
    local frame_count = 1
    local offset_x, offset_y = 32, 64
    if self.state == TRANSFORM then
      sprite = self.angry and charcoal.transform_rage or charcoal.transform
      frame_count, offset_x = 19, 20
    elseif self.state == ROLL then
      sprite = self.angry and charcoal.roll_rage or charcoal.roll
      frame_count, offset_x, offset_y = 19, 16, 32
    elseif self.state == DAZED then
      sprite = self.hit_frames > 0 and charcoal.daze_hit or
               (self.angry and charcoal.daze_rage or charcoal.daze)
      frame_count, offset_x = 4, 20
    elseif self.state == TRANSITION or self.state == DEAD then
      sprite = charcoal.transition
      frame_count, offset_x = 2, 20
    end
    ui.tile(sprite, math.floor(self.animation / 8) % frame_count,
            screen_x - offset_x, screen_y - offset_y, self.direction < 0, false)
  end

  local health_width = math.floor(120 * self.health / self.health_max)
  ui.rect(179, 18, 300, 25, 1)
  if health_width > 0 then ui.rectfill(180, 19, 179 + health_width, 24, 2) end
end

function Boss:isDefeated()
  return self.defeated
end

return Boss
