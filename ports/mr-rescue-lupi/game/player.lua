local Profile = require("profile")
local Audio = require("audio")
local Input = require("input")
local World = require("world")

local Player = {
  x = 96,
  y = 240,
  speed_x = 0,
  speed_y = 0,
  direction = 1,
  on_ground = false,
  climbing = false,
  carrying = 0,
  animation = 0,
  water = 300,
  water_capacity = 300,
  regeneration_rate = 3,
  overloaded = false,
  has_reserve = false,
  suit_count = 0,
  tank_count = 0,
  regeneration_count = 0,
  temperature = 0,
  maximum_temperature = 1.5,
  heat = 0,
  dead = false,
  failed = false,
  spraying = false,
  spray_reach = 0,
  spray_x = 1,
  spray_y = 0,
}

local running_sprite = Sprites.find("assets/player_running")
local gun_sprite = Sprites.find("assets/player_gun")
local climbing_sprite = Sprites.find("assets/player_climb_down")
local death_up_sprite = Sprites.find("assets/player_death_up")
local death_down_sprite = Sprites.find("assets/player_death_down")
local death_suit_sprite = Sprites.find("assets/player_death_suit")
local acceleration = 500 / (Profile.update_hz * Profile.update_hz)
local braking = 250 / (Profile.update_hz * Profile.update_hz)
local gravity = 350 / (Profile.update_hz * Profile.update_hz)
local jump_speed = 135 / Profile.update_hz
local maximum_speed = 160 / Profile.update_hz
local carrying_speed = 100 / Profile.update_hz

local function cap(value, minimum, maximum)
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

function Player.setCertificationPosition(x)
  Player.x = x
  Player.speed_x = 0
end

function Player.setCertificationDirection(direction)
  Player.direction = direction
end

function Player.setDifficulty(difficulty)
  if difficulty == 1 then
    Player.maximum_temperature = 1.5
  elseif difficulty == 2 then
    Player.maximum_temperature = 1.2
  else
    Player.maximum_temperature = 1.0
  end
end

function Player.reset(x, y)
  Player.x = x or 96
  Player.y = y or 240
  Player.speed_x = 0
  Player.speed_y = 0
  Player.direction = 1
  Player.on_ground = false
  Player.climbing = false
  Player.carrying = 0
  Player.animation = 0
  Player.water = 300
  Player.water_capacity = 300
  Player.regeneration_rate = 3
  Player.overloaded = false
  Player.has_reserve = false
  Player.suit_count = 0
  Player.tank_count = 0
  Player.regeneration_count = 0
  Player.temperature = 0
  Player.maximum_temperature = 1.5
  Player.heat = 0
  Player.dead = false
  Player.failed = false
  Player.spraying = false
  Player.spray_reach = 0
  Player.spray_x = 1
  Player.spray_y = 0
end

function Player.warp(x, y)
  Player.x = x
  Player.y = y
  Player.speed_x = 0
  Player.speed_y = 0
  Player.on_ground = false
  Player.climbing = false
  Player.carrying = 0
  Player.spraying = false
  Player.spray_reach = 0
end

local function moveHorizontal()
  local requested_direction = 0
  if Input.left and not Input.right then requested_direction = -1 end
  if Input.right and not Input.left then requested_direction = 1 end

  if requested_direction ~= 0 then
    Player.direction = requested_direction
    Player.speed_x = Player.speed_x + requested_direction * acceleration
  end

  local speed_limit = Player.carrying == 0 and maximum_speed or carrying_speed
  Player.speed_x = cap(Player.speed_x, -speed_limit, speed_limit)
  if Player.speed_x < 0 then
    Player.speed_x = math.min(0, Player.speed_x + braking)
  elseif Player.speed_x > 0 then
    Player.speed_x = math.max(0, Player.speed_x - braking)
  end
  local next_x = Player.x + Player.speed_x
  local side = Player.speed_x < 0 and -6 or 5
  if World.solidPoint(next_x + side, Player.y - 20) or
     World.solidPoint(next_x + side, Player.y - 2) then
    Player.speed_x = -Player.speed_x
  else
    Player.x = cap(next_x, 8, Profile.map_width * 16 - 8)
  end
end

local function moveVertical()
  Player.speed_y = Player.speed_y + gravity
  local next_y = Player.y + Player.speed_y
  Player.on_ground = false
  if Player.speed_y >= 0 then
    if World.solidPoint(Player.x - 5, next_y) or World.solidPoint(Player.x + 5, next_y) then
      Player.y = math.floor(next_y / 16) * 16
      Player.speed_y = 0
      Player.on_ground = true
    else
      Player.y = next_y
    end
  else
    if World.solidPoint(Player.x - 5, next_y - 22) or
       World.solidPoint(Player.x + 5, next_y - 22) then
      Player.speed_y = 0
    else
      Player.y = next_y
    end
  end
end

local function updateSpray()
  Player.spray_x = Player.direction
  Player.spray_y = 0
  if Input.up then
    Player.spray_x = 0
    Player.spray_y = -1
  elseif Input.down then
    Player.spray_x = 0
    Player.spray_y = 1
  end
  Player.spraying = Input.spray and not Player.overloaded and
                    Player.carrying == 0 and not Player.climbing
  if Player.spraying then
    if Player.spray_reach == 0 then Audio.play("spray") end
    Player.spray_reach = math.min(100, Player.spray_reach + 400 / Profile.update_hz)
    Player.spray_reach = World.spray(
      Player.x + Player.spray_x * 10,
      Player.y - 8 + Player.spray_y * 8,
      Player.spray_x,
      Player.spray_y,
      Player.spray_reach
    )
    Player.water = Player.water - 2.5
    if Player.water <= 0 then
      if Player.has_reserve then
        Player.has_reserve = false
        Player.water = Player.water_capacity
      else
        Player.water = 0
        Player.overloaded = true
        Audio.play("empty")
      end
    end
  else
    Player.spray_reach = 0
    local rate = Player.overloaded and Player.regeneration_rate * 0.5 or
                 Player.regeneration_rate
    Player.water = math.min(Player.water_capacity, Player.water + rate)
    if Player.overloaded and Player.water >= Player.water_capacity then
      Player.overloaded = false
    end
  end
end

function Player.stealItem(selection)
  if selection <= Player.suit_count then
    Player.suit_count = Player.suit_count - 1
    Player.maximum_temperature = Player.maximum_temperature - 0.2
  elseif selection <= Player.suit_count + Player.tank_count then
    Player.tank_count = Player.tank_count - 1
    Player.water_capacity = Player.water_capacity - 60
    Player.water = math.min(Player.water, Player.water_capacity)
  elseif Player.regeneration_count > 0 then
    Player.regeneration_count = Player.regeneration_count - 1
    Player.regeneration_rate = Player.regeneration_rate - 0.5
  else
    return false
  end
  return true
end

function Player.applyItem(kind)
  Audio.play("item")
  if kind == 1 then
    Player.temperature = math.max(0, Player.temperature - 0.25)
  elseif kind == 2 then
    Player.suit_count = math.min(3, Player.suit_count + 1)
    Player.maximum_temperature = math.min(1.6, Player.maximum_temperature + 0.2)
  elseif kind == 3 then
    Player.tank_count = math.min(3, Player.tank_count + 1)
    Player.water_capacity = math.min(480, Player.water_capacity + 60)
  elseif kind == 4 then
    Player.has_reserve = true
  elseif kind == 5 then
    Player.regeneration_count = math.min(3, Player.regeneration_count + 1)
    Player.regeneration_rate = math.min(4.5, Player.regeneration_rate + 0.5)
  end
end

local function updateClimbing()
  if Input.left or Input.right then
    Player.climbing = false
    return
  end
  if Input.up then Player.y = Player.y - 1 end
  if Input.down then Player.y = Player.y + 1 end
  Player.speed_x = 0
  Player.speed_y = 0
  if not World.ladderPoint(Player.x, Player.y) and
     not World.ladderPoint(Player.x, Player.y - 20) then
    Player.climbing = false
  end
end

function Player.update()
  if Player.dead then
    Player.speed_y = Player.speed_y + gravity
    Player.y = Player.y + Player.speed_y
    if Player.y > Profile.map_height * 16 + 48 then Player.failed = true end
    return
  end
  if Player.climbing then
    updateClimbing()
  else
    moveHorizontal()
    moveVertical()
    if (Input.up or Input.down) and
       (World.ladderPoint(Player.x, Player.y) or
        World.ladderPoint(Player.x, Player.y - 20)) then
      Player.climbing = true
      Player.x = math.floor(Player.x / 16) * 16 + 8
      Player.speed_x = 0
      Player.speed_y = 0
    end
  end
  if Input.jump_pressed then
    if Player.climbing then
      Player.climbing = false
    elseif Player.on_ground then
      Player.speed_y = -jump_speed
      Audio.play("jump")
    end
  end
  if Input.rescue_pressed then
    if Player.carrying == 0 then
      World.tryCarry(Player)
    else
      World.throwCarried(Player)
    end
  end
  updateSpray()
  Player.heat = World.heatAt(Player.x, Player.y - 11)
  local time_damage = World.isBossBattle() and 0 or 0.008
  Player.temperature = math.min(
    Player.maximum_temperature,
    Player.temperature + (time_damage + Player.heat * 0.5) / Profile.update_hz
  )
  if Player.temperature >= Player.maximum_temperature then
    Player.dead = true
    Player.climbing = false
    Player.spraying = false
    Player.speed_y = -230 / Profile.update_hz
  end

  if Player.climbing and (Input.up or Input.down) then
    Player.animation = (Player.animation + 1) % 32
  elseif math.abs(Player.speed_x) > 0.2 then
    Player.animation = (Player.animation + 1) % 32
  else
    Player.animation = 0
  end
end

function Player.cameraX()
  return math.floor(cap(Player.x - 240, 0, Profile.map_width * 16 - Profile.width))
end

function Player.draw(camera_x, origin_y, water_color)
  local frame = math.floor(Player.animation / 8) % 4
  local screen_x = math.floor(Player.x - camera_x)
  local screen_y = math.floor(Player.y + origin_y)
  if Player.dead then
    local body_sprite = Player.speed_y < 0 and death_up_sprite or death_down_sprite
    ui.tile(body_sprite, 0, screen_x - 8, screen_y - 24, Player.direction < 0, false)
    ui.tile(death_suit_sprite, 0, screen_x - 7, screen_y - 10, Player.direction < 0, false)
    return
  end
  if Player.climbing then
    ui.tile(
      climbing_sprite,
      math.floor(Player.animation / 8) % 4,
      screen_x - 7,
      screen_y - 23
    )
    return
  end
  if Player.carrying ~= 0 then
    if World.drawCarried(
      Player.carrying,
      Player.direction,
      screen_x,
      screen_y,
      Player.animation
    ) then return end
  end
  ui.tile(
    running_sprite,
    frame,
    screen_x - 8,
    screen_y - 22,
    Player.direction < 0,
    false
  )
  local gun_frame = 2
  if Player.spray_y < 0 then gun_frame = 0 end
  if Player.spray_y > 0 then gun_frame = 4 end
  ui.tile(
    gun_sprite,
    gun_frame,
    screen_x - 3,
    screen_y - 16,
    Player.direction < 0,
    false
  )
  if Player.spraying and Player.spray_reach > 0 then
    local start_x = screen_x + Player.spray_x * 10
    local start_y = screen_y - 8 + Player.spray_y * 8
    local end_x = start_x + Player.spray_x * math.floor(Player.spray_reach)
    local end_y = start_y + Player.spray_y * math.floor(Player.spray_reach)
    ui.line(start_x, start_y, end_x, end_y, water_color)
    if Player.spray_y == 0 then
      ui.line(start_x, start_y + 1, end_x, end_y + 1, water_color)
    else
      ui.line(start_x + 1, start_y, end_x + 1, end_y, water_color)
    end
  end
end

return Player
