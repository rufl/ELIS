local Profile = require("profile")
local Audio = require("audio")
local Boss = require("boss")
local base_map = require("map_data")
local boss_map = require("boss_map")
local map_templates = require("map_templates")

local World = {}
local tiles_0 = Sprites.find("assets/tiles_0")
local tiles_1 = Sprites.find("assets/tiles_1")
local fire_sprite = Sprites.find("assets/fire_wall")
local ash_sprite = Sprites.find("assets/ashes")
local item_sprites = {
  Sprites.find("assets/item_coolant"),
  Sprites.find("assets/item_suit"),
  Sprites.find("assets/item_tank"),
  Sprites.find("assets/item_reserve"),
  Sprites.find("assets/item_regen"),
}
local enemy_sprites = {
  [1] = {
    run = Sprites.find("assets/enemy_normal_run"),
    hit = Sprites.find("assets/enemy_normal_hit"),
    recover = Sprites.find("assets/enemy_normal_recover"),
  },
  [2] = {
    run = Sprites.find("assets/enemy_jumper_jump"),
    hit = Sprites.find("assets/enemy_jumper_hit"),
  },
  [3] = {
    run = Sprites.find("assets/enemy_volcano_run"),
    shoot = Sprites.find("assets/enemy_volcano_shoot"),
    hit = Sprites.find("assets/enemy_volcano_hit"),
  },
  [4] = {
    run = Sprites.find("assets/enemy_angrynormal_run"),
    hit = Sprites.find("assets/enemy_angrynormal_hit"),
    recover = Sprites.find("assets/enemy_angrynormal_recover"),
  },
  [5] = {
    run = Sprites.find("assets/enemy_angryjumper_jump"),
    hit = Sprites.find("assets/enemy_angryjumper_hit"),
  },
  [6] = {
    run = Sprites.find("assets/enemy_angryvolcano_run"),
    shoot = Sprites.find("assets/enemy_angryvolcano_shoot"),
    hit = Sprites.find("assets/enemy_angryvolcano_hit"),
  },
  [7] = {
    run = Sprites.find("assets/enemy_thief_run"),
    hit = Sprites.find("assets/enemy_thief_hit"),
    recover = Sprites.find("assets/enemy_thief_recover"),
  },
}
local fireball_sprite = Sprites.find("assets/enemy_fireball")
local gasghost_sprite = Sprites.find("assets/gasghost")
local gasghost_hit_sprite = Sprites.find("assets/gasghost_hit")
local coalball_sprite = Sprites.find("assets/charcoal_projectile")
local door_normal_sprite = Sprites.find("assets/door_normal")
local door_damaged_sprite = Sprites.find("assets/door_damaged")
local warning_sprites = {
  Sprites.find("assets/warning_0"), Sprites.find("assets/warning_1"),
  Sprites.find("assets/warning_2"), Sprites.find("assets/warning_3"),
  Sprites.find("assets/warning_4"),
}
local night_sprites = {
  Sprites.find("assets/night_0"),
  Sprites.find("assets/night_1"),
  Sprites.find("assets/night_2"),
  Sprites.find("assets/night_3"),
}
local human_sprites = {}
for human_id = 1, 4 do
  human_sprites[human_id] = {
    run = Sprites.find("assets/human_" .. human_id .. "_run"),
    carry_left = Sprites.find("assets/human_" .. human_id .. "_carry_left"),
    carry_right = Sprites.find("assets/human_" .. human_id .. "_carry_right"),
    fly = Sprites.find("assets/human_" .. human_id .. "_fly"),
    burn = Sprites.find("assets/human_" .. human_id .. "_burn"),
    panic = Sprites.find("assets/human_" .. human_id .. "_panic"),
  }
end

local HUMAN_IDLE = 1
local HUMAN_WALK = 2
local HUMAN_CARRIED = 3
local HUMAN_FLY = 4
local HUMAN_BURN = 5
local HUMAN_PANIC = 6
local cells = {}
local fires = {}
local humans = {}
local enemies = {}
local projectiles = {}
local items = {}
local doors = {}
local ashes = {}
local generated_rooms = {}
local random_state = 0x4D52534B
local fire_count = 0
local rescued_count = 0
local casualty_count = 0
local human_count = 0
local enemy_count = 0
local projectile_count = 0
local room_count = 0
local active_boss = nil
local section_number = 1
local enemy_kind_min = 1
local enemy_kind_max = 1
local pending_score = 0
local pending_extinguished = 0
local pending_rescues = 0
local pending_property_damage = 0
local boss_score_awarded = false
local certification_seed_sweep = false
local enemy_scores = { 100, 125, 200, 200, 200, 300, 350 }

for index = 1, Profile.fire_max do
  fires[index] = {
    active = false,
    cell_x = 0,
    cell_y = 0,
    health = 0,
    spread_frames = 0,
    animation = 0,
  }
end

for index = 1, Profile.human_max do
  humans[index] = {
    active = false,
    carried = false,
    id = 1,
    state = HUMAN_IDLE,
    x = 0,
    y = 0,
    speed_x = 0,
    speed_y = 0,
    direction = 1,
    animation = 0,
    state_frames = 0,
    health_frames = 0,
    butt_hits = 0,
  }
end

for index = 1, Profile.enemy_max do
  enemies[index] = {
    active = false,
    kind = 1,
    x = 0,
    y = 0,
    speed_x = 0,
    speed_y = 0,
    direction = 1,
    health = 0,
    health_max = 0,
    state = 1,
    timer = 0,
    fire_timer = 0,
    animation = 0,
    hit_frames = 0,
  }
end
for index = 1, Profile.projectile_max do
  projectiles[index] = {
    active = false,
    kind = 1,
    x = 0,
    y = 0,
    start_y = 0,
    speed_x = 0,
    speed_y = 0,
    animation = 0,
    health = 0,
  }
end
for index = 1, Profile.item_max do
  items[index] = { active = false, kind = 1, x = 0, y = 0, animation = 0 }
end
for index = 1, Profile.door_max do
  doors[index] = {
    active = false,
    solid = false,
    x = 0,
    y = 0,
    speed_x = 0,
    speed_y = 0,
    health = 0,
    cell_x = 0,
    cell_y = 0,
  }
end
for index = 1, Profile.particle_max do
  ashes[index] = { active = false, x = 0, y = 0, animation = 0 }
end
for index = 1, 9 do
  generated_rooms[index] = {
    x = 0,
    y = 0,
    template = nil,
    used_for_item = false,
  }
end

local function random(maximum)
  random_state = (1103515245 * random_state + 12345) & 0x7FFFFFFF
  return random_state % maximum
end

local function mapIndex(cell_x, cell_y)
  return cell_y * Profile.map_width + cell_x + 1
end

function World.tileAt(cell_x, cell_y)
  if cell_x < 0 or cell_x >= Profile.map_width then return 1 end
  if cell_y < 0 then return 0 end
  if cell_y >= Profile.map_height then return 1 end
  return cells[mapIndex(cell_x, cell_y)] or 0
end

function World.solidCell(cell_x, cell_y)
  local tile = World.tileAt(cell_x, cell_y)
  return tile > 0 and tile < 60
end

function World.solidPoint(x, y)
  if World.solidCell(math.floor(x / 16), math.floor(y / 16)) then return true end
  for index = 1, Profile.door_max do
    local door = doors[index]
    if door.active and door.solid and x >= door.x and x <= door.x + 4 and
       y >= door.y and y <= door.y + 47 then
      return true
    end
  end
  return false
end

function World.ladderPoint(x, y)
  local tile = World.tileAt(math.floor(x / 16), math.floor(y / 16))
  return tile == 5 or tile == 8 or tile == 13 or tile == 63 or tile == 79 or
         tile == 137 or tile == 153 or tile == 247
end

local function canBurn(cell_x, cell_y)
  if cell_x < 3 or cell_x > 37 or cell_y < 1 or cell_y >= 15 then return false end
  if World.solidCell(cell_x, cell_y) then return false end
  if not World.solidCell(cell_x, cell_y + 1) then return false end
  for index = 1, Profile.fire_max do
    local fire = fires[index]
    if fire.active and fire.cell_x == cell_x and fire.cell_y == cell_y then return false end
  end
  return true
end

local function fireSpreadFrames()
  local minimum = math.floor(8 - section_number * (6 / 26) + 0.5)
  local maximum = math.floor(14 - section_number * (10 / 26) + 0.5)
  return (minimum + random(maximum - minimum + 1)) * Profile.update_hz
end

function World.addFire(cell_x, cell_y)
  if not canBurn(cell_x, cell_y) then return false end
  for index = 1, Profile.fire_max do
    local fire = fires[index]
    if not fire.active then
      fire.active = true
      fire.cell_x = cell_x
      fire.cell_y = cell_y
      fire.health = 6
      fire.spread_frames = fireSpreadFrames()
      fire.animation = random(5) * 8
      fire_count = fire_count + 1
      return true
    end
  end
  assert(not certification_seed_sweep)
  return false
end

function World.addHuman(x, y)
  for index = 1, Profile.human_max do
    local human = humans[index]
    if not human.active then
      human.active = true
      human.carried = false
      human.id = random(4) + 1
      human.state = HUMAN_IDLE
      human.x = x
      human.y = y
      human.speed_x = 0
      human.speed_y = 0
      human.direction = 1
      human.animation = index * 7
      human.state_frames = random(241)
      human.health_frames = 300
      human.butt_hits = 0
      human_count = human_count + 1
      return true
    end
  end
  return false
end

local start_x = 96
local start_y = 240

local function setTile(cell_x, cell_y, value)
  if cell_x < 0 or cell_x >= Profile.map_width then return end
  if cell_y < 0 or cell_y >= Profile.map_height then return end
  cells[mapIndex(cell_x, cell_y)] = value
end

local function addRoom(room_x, room_y, room_width)
  local choices = map_templates.rooms[tostring(room_width)]
  assert(choices ~= nil and #choices == 6)
  local room = choices[random(#choices) + 1]
  for cell_y = 0, room.height - 1 do
    for cell_x = 0, room.width - 1 do
      if not World.solidCell(room_x + cell_x, room_y + cell_y) then
        setTile(
          room_x + cell_x,
          room_y + cell_y,
          room.data[cell_y * room.width + cell_x + 1]
        )
      end
    end
  end
  return room
end

local enemy_health = { 78, 78, 96, 108, 108, 114, 90 }

local function addEnemy(kind, x, y)
  for index = 1, Profile.enemy_max do
    local enemy = enemies[index]
    if not enemy.active then
      enemy.active = true
      enemy.kind = kind
      enemy.x = x
      enemy.y = y
      enemy.speed_x = 0
      enemy.speed_y = 0
      enemy.direction = (kind == 2 or kind == 5) and
                        (random(2) == 0 and -1 or 1) or 1
      enemy.health_max = enemy_health[kind]
      enemy.health = enemy.health_max
      enemy.state = 1
      enemy.timer = random(60)
      if kind == 2 then
        enemy.fire_timer = 3 + random(11)
      elseif kind == 5 then
        enemy.fire_timer = 3 + random(6)
      elseif kind == 3 or kind == 6 then
        enemy.fire_timer = random(241)
      else
        enemy.fire_timer = (7 + random(19)) * Profile.update_hz
      end
      enemy.animation = 0
      enemy.hit_frames = 0
      enemy_count = enemy_count + 1
      return true
    end
  end
  return false
end

local function addProjectile(x, y, speed_x)
  for index = 1, Profile.projectile_max do
    local projectile = projectiles[index]
    if not projectile.active then
      projectile.active = true
      projectile.kind = 1
      projectile.x = x
      projectile.y = y
      projectile.start_y = y
      projectile.speed_x = speed_x
      projectile.speed_y = -(100 + random(51)) / Profile.update_hz
      projectile.animation = random(24)
      projectile.health = 15
      projectile_count = projectile_count + 1
      return true
    end
  end
  return false
end

function World.bossRandom(maximum)
  return random(maximum)
end

function World.spawnBossHazard(kind, x, y, speed_x, speed_y)
  for index = 1, Profile.projectile_max do
    local projectile = projectiles[index]
    if not projectile.active then
      projectile.active = true
      projectile.kind = kind
      projectile.x = x
      projectile.y = y
      projectile.start_y = y
      projectile.speed_x = speed_x
      projectile.speed_y = speed_y
      projectile.animation = 0
      projectile.health = 15
      projectile_count = projectile_count + 1
      return true
    end
  end
  return false
end

local function populateRoom(room_x, room_y, room_width)
  local count = math.floor(room_width / 5)
  local separation = math.floor(room_width / (count + 1))
  if random(2) == 0 then
    for index = 1, count do
      local cell_x = room_x + index * separation
      if random(2) == 0 then
        assert(World.addHuman(cell_x * 16 + 8, (room_y + 4) * 16))
      else
        World.addFire(cell_x, room_y + 3)
      end
    end
  else
    local enemy_total = 1
    if section_number >= 20 and random(3) == 0 then
      enemy_total = 2
    elseif section_number >= 12 and random(5) == 0 then
      enemy_total = 2
    end
    separation = math.floor(room_width / (enemy_total + 1))
    for index = 1, enemy_total do
      local kind = enemy_kind_min + random(enemy_kind_max - enemy_kind_min + 1)
      assert(addEnemy(kind, (room_x + index * separation) * 16 + 8, (room_y + 4) * 16))
    end
  end
end

local function addDoor(x, y, direction)
  for index = 1, Profile.door_max do
    local door = doors[index]
    if not door.active then
      door.active = true
      door.solid = true
      door.x = direction == "left" and x + 12 or x
      door.y = y
      door.speed_x = 0
      door.speed_y = 0
      door.health = 18
      door.cell_x = math.floor(x / 16)
      door.cell_y = math.floor(y / 16)
      return true
    end
  end
  return false
end

local function addItem(kind, x, y)
  for index = 1, Profile.item_max do
    local item = items[index]
    if not item.active then
      item.active = true
      item.kind = kind
      item.x = x
      item.y = y - 2
      item.animation = 0
      return true
    end
  end
  return false
end

local function chooseUnusedRoom()
  local available_count = 0
  for index = 1, room_count do
    if not generated_rooms[index].used_for_item then
      available_count = available_count + 1
    end
  end
  if available_count == 0 then return nil end
  local selected_rank = random(available_count)
  for index = 1, room_count do
    local room = generated_rooms[index]
    if not room.used_for_item then
      if selected_rank == 0 then
        room.used_for_item = true
        return room
      end
      selected_rank = selected_rank - 1
    end
  end
  return nil
end

local function placeItem(kind)
  local room = chooseUnusedRoom()
  if room == nil or #room.template.objects == 0 then return false end
  local marker = room.template.objects[random(#room.template.objects) + 1]
  return addItem(kind, room.x + marker.x, room.y + marker.y)
end

local function generateBuilding()
  local selected_starts = 0
  for floor_index = 1, 3 do
    local floor = map_templates.floors[random(#map_templates.floors) + 1]
    local cell_y_offset = 5 * (floor_index - 1)
    for cell_y = 0, floor.height - 1 do
      for cell_x = 3, floor.width - 4 do
        setTile(
          cell_x,
          cell_y + cell_y_offset,
          floor.data[cell_y * floor.width + cell_x + 1]
        )
      end
    end
    for _, object in ipairs(floor.objects) do
      if object.type == "door" then
        assert(addDoor(object.x, object.y + cell_y_offset * 16, object.direction))
      elseif object.type == "room" then
        local room_x = math.floor(object.x / 16)
        local room_y = math.floor(object.y / 16) + cell_y_offset
        local room_width = math.floor(object.width / 16)
        local room_template = addRoom(room_x, room_y, room_width)
        room_count = room_count + 1
        assert(room_count <= #generated_rooms)
        local generated = generated_rooms[room_count]
        generated.x = room_x * 16
        generated.y = room_y * 16
        generated.template = room_template
        generated.used_for_item = false
        populateRoom(room_x, room_y, room_width)
      elseif object.type == "start" and floor_index == 3 then
        selected_starts = selected_starts + 1
        if random(selected_starts) == 0 then
          start_x = object.x + 8
          start_y = object.y + cell_y_offset * 16 + 16
        end
      end
    end
  end
  assert(placeItem(1))
  assert(placeItem(1))
  assert(placeItem(random(5) + 1))
end

function World.reset(seed, section, boss_kind)
  random_state = seed or 0x4D52534B
  section_number = section or 1
  enemy_kind_min = 1
  enemy_kind_max = 1
  if section_number >= 20 then
    enemy_kind_min = 4
    enemy_kind_max = 7
  elseif section_number >= 14 then
    enemy_kind_min = 3
    enemy_kind_max = 6
  elseif section_number >= 10 then
    enemy_kind_min = 2
    enemy_kind_max = 5
  elseif section_number >= 8 then
    enemy_kind_max = 4
  elseif section_number >= 4 then
    enemy_kind_max = 3
  elseif section_number >= 2 then
    enemy_kind_max = 2
  end
  fire_count = 0
  rescued_count = 0
  casualty_count = 0
  human_count = 0
  enemy_count = 0
  projectile_count = 0
  room_count = 0
  active_boss = nil
  pending_score = 0
  pending_extinguished = 0
  pending_rescues = 0
  pending_property_damage = 0
  boss_score_awarded = false
  start_x = boss_kind and 280 or 96
  start_y = 240
  local source_map = boss_kind and boss_map or base_map
  for index = 1, #source_map do cells[index] = source_map[index] end
  for index = 1, Profile.fire_max do fires[index].active = false end
  for index = 1, Profile.human_max do humans[index].active = false end
  for index = 1, Profile.enemy_max do enemies[index].active = false end
  for index = 1, Profile.projectile_max do projectiles[index].active = false end
  for index = 1, Profile.item_max do items[index].active = false end
  for index = 1, Profile.door_max do doors[index].active = false end
  for index = 1, Profile.particle_max do ashes[index].active = false end
  if boss_kind then
    active_boss = Boss.create(boss_kind)
    assert(addItem(1, 16 * 16, 8 * 16))
    assert(addItem(1, 24 * 16, 10 * 16))
  else
    generateBuilding()
    if human_count == 0 then assert(World.addHuman(214, 240)) end
  end
end

function World.certificationSeedSweep(seed_count)
  assert(seed_count >= 1 and seed_count <= 256)
  certification_seed_sweep = true
  local peak_fire = 0
  local peak_humans = 0
  local peak_enemies = 0
  for seed_index = 1, seed_count do
    for section = 1, 26 do
      World.reset(0x4D520000 + seed_index * 131 + section * 977, section, nil)
      peak_fire = math.max(peak_fire, fire_count)
      peak_humans = math.max(peak_humans, human_count)
      peak_enemies = math.max(peak_enemies, enemy_count)
    end
  end
  certification_seed_sweep = false
  ui.log(
    "MR_RESCUE_SEED_SWEEP=" .. seed_count ..
    " PEAK_FIRE=" .. peak_fire ..
    " PEAK_HUMANS=" .. peak_humans ..
    " PEAK_ENEMIES=" .. peak_enemies
  )
end

function World.clearCertificationHazards()
  for index = 1, Profile.fire_max do fires[index].active = false end
  for index = 1, Profile.projectile_max do projectiles[index].active = false end
  fire_count = 0
  projectile_count = 0
end

function World.clearFireAndEnemies()
  for index = 1, Profile.fire_max do fires[index].active = false end
  for index = 1, Profile.enemy_max do enemies[index].active = false end
  for index = 1, Profile.projectile_max do projectiles[index].active = false end
  fire_count = 0
  enemy_count = 0
  projectile_count = 0
end

function World.addCertificationHuman(x, y)
  assert(World.addHuman(x, y))
end

function World.addCertificationRescue(y)
  assert(World.addHuman(-17, y))
  for index = 1, Profile.human_max do
    local human = humans[index]
    if human.active and human.x == -17 and human.y == y then
      human.state = HUMAN_FLY
      human.animation = 0
      human.speed_x = -1
      human.speed_y = 0
      return
    end
  end
  assert(false)
end

function World.addCertificationBurningHuman(x, y)
  assert(World.addHuman(x, y))
  for index = 1, Profile.human_max do
    local human = humans[index]
    if human.active and human.x == x and human.y == y then
      human.state = HUMAN_BURN
      human.animation = 0
      human.health_frames = 300
      return
    end
  end
  assert(false)
end

function World.addCertificationScoringTarget(x, y)
  assert(World.spawnBossHazard(2, x, y, 0, 0))
end

function World.addCertificationEnemies()
  for kind = 1, 7 do
    local floor = (kind - 1) % 3
    assert(addEnemy(kind, 96 + kind * 64, 80 + floor * 80))
  end
end

function World.startPosition()
  return start_x, start_y
end

local spread_x = { 1, -1, 0, 0 }
local spread_y = { 0, 0, 1, -1 }

local function humanTouchesFire(human)
  for index = 1, Profile.fire_max do
    local fire = fires[index]
    if fire.active then
      local fire_x = fire.cell_x * 16 + 8
      local fire_y = fire.cell_y * 16 + 8
      if math.abs(fire_x - human.x) <= 13 and math.abs(fire_y - human.y + 8) <= 16 then
        return true
      end
    end
  end
  for index = 1, Profile.enemy_max do
    local enemy = enemies[index]
    if enemy.active and math.abs(enemy.x - human.x) <= 12 and
       math.abs(enemy.y - human.y) <= 26 then
      return true
    end
  end
  for index = 1, Profile.projectile_max do
    local projectile = projectiles[index]
    if projectile.active and math.abs(projectile.x - human.x) <= 9 and
       math.abs(projectile.y - human.y + 8) <= 18 then
      return true
    end
  end
  return false
end

local function setHumanState(human, state)
  human.state = state
  human.animation = 0
  if state == HUMAN_IDLE then
    human.state_frames = 120
  elseif state == HUMAN_WALK then
    human.state_frames = 180
  elseif state == HUMAN_PANIC then
    human.state_frames = 60
  end
end

local function spawnAsh(x, y)
  for index = 1, Profile.particle_max do
    local ash = ashes[index]
    if not ash.active then
      ash.active = true
      ash.x = x
      ash.y = y
      ash.animation = 0
      return
    end
  end
end

local function thrownHumanHitsDoor(x, top, bottom, speed)
  for index = 1, Profile.door_max do
    local door = doors[index]
    if door.active and door.solid and x >= door.x and x <= door.x + 4 and
       bottom >= door.y and top <= door.y + 47 then
      door.health = door.health - 9.6
      if door.health <= 0 then
        door.solid = false
        door.speed_x = speed < 0 and -50 / Profile.update_hz or
                       50 / Profile.update_hz
        door.speed_y = -100 / Profile.update_hz
        pending_score = pending_score + 50
        pending_property_damage = pending_property_damage + 80 + random(41)
        Audio.play("door")
      end
      return true
    end
  end
  return false
end

local function moveHumanHorizontal(human, speed)
  local next_x = human.x + speed
  local side = speed < 0 and -5 or 5
  local collision_x = next_x + side
  if World.solidPoint(collision_x, human.y - 14) or
     World.solidPoint(collision_x, human.y - 2) then
    if human.state == HUMAN_FLY then
      thrownHumanHitsDoor(collision_x, human.y - 14, human.y - 2, speed)
    end
    human.direction = -human.direction
    human.speed_x = -human.speed_x * 0.6
    return false
  end
  human.x = next_x
  return true
end

local function moveHumanVertical(human)
  human.speed_y = human.speed_y + 350 / (Profile.update_hz * Profile.update_hz)
  local next_y = human.y + human.speed_y
  if human.speed_y >= 0 then
    if World.solidPoint(human.x - 5, next_y) or World.solidPoint(human.x + 5, next_y) then
      human.y = math.floor(next_y / 16) * 16
      human.speed_y = -human.speed_y * 0.6
      return true
    end
  elseif World.solidPoint(human.x - 5, next_y - 16) or
         World.solidPoint(human.x + 5, next_y - 16) then
    human.speed_y = -human.speed_y * 0.6
    return false
  end
  human.y = next_y
  return false
end

local function breakWindowAt(x, y)
  local cell_x = math.floor(x / 16)
  local cell_y = math.floor(y / 16)
  local tile = World.tileAt(cell_x, cell_y)
  if tile == 38 then
    setTile(cell_x, cell_y - 1, 239)
    setTile(cell_x, cell_y, 255)
    pending_property_damage = pending_property_damage + 100 + random(101)
    Audio.play("glass")
    return true
  elseif tile == 39 then
    setTile(cell_x, cell_y - 1, 240)
    setTile(cell_x, cell_y, 256)
    pending_property_damage = pending_property_damage + 100 + random(101)
    Audio.play("glass")
    return true
  end
  return false
end

local function humanFireSides(human)
  local left_x = math.floor((human.x - 29) / 16)
  local right_x = math.floor((human.x + 29) / 16)
  local cell_y = math.floor((human.y - 8) / 16)
  local fire_left = false
  local fire_right = false
  for index = 1, Profile.fire_max do
    local fire = fires[index]
    if fire.active and fire.cell_y == cell_y then
      if fire.cell_x == left_x then fire_left = true end
      if fire.cell_x == right_x then fire_right = true end
    end
  end
  local trapped = (fire_left and (fire_right or World.solidCell(right_x, cell_y))) or
                  (fire_right and (fire_left or World.solidCell(left_x, cell_y)))
  return trapped, fire_left, fire_right
end

local function updateHuman(human, player)
  human.animation = human.animation + 1
  if human.state == HUMAN_CARRIED then
    human.x = player.x - player.direction * 10
    human.y = player.y
    return
  elseif human.state == HUMAN_IDLE then
    human.state_frames = human.state_frames - 1
    if humanTouchesFire(human) then
      setHumanState(human, HUMAN_BURN)
    elseif human.state_frames <= 0 then
      setHumanState(human, HUMAN_WALK)
    end
  elseif human.state == HUMAN_WALK then
    moveHumanHorizontal(human, human.direction * 50 / Profile.update_hz)
    human.speed_y = 0
    moveHumanVertical(human)
    local trapped, fire_left, fire_right = humanFireSides(human)
    if trapped then
      setHumanState(human, HUMAN_PANIC)
    elseif fire_left then
      human.direction = 1
    elseif fire_right then
      human.direction = -1
    end
    human.state_frames = human.state_frames - 1
    if humanTouchesFire(human) then
      setHumanState(human, HUMAN_BURN)
    elseif human.state_frames <= 0 then
      setHumanState(human, HUMAN_IDLE)
    end
  elseif human.state == HUMAN_PANIC then
    local trapped = humanFireSides(human)
    if humanTouchesFire(human) then
      setHumanState(human, HUMAN_BURN)
    elseif not trapped then
      setHumanState(human, HUMAN_IDLE)
    end
  elseif human.state == HUMAN_BURN then
    moveHumanHorizontal(human, human.direction * 100 / Profile.update_hz)
    human.speed_y = 0
    moveHumanVertical(human)
    human.health_frames = human.health_frames - 1
    if human.health_frames <= 0 then
      human.active = false
      human_count = human_count - 1
      casualty_count = casualty_count + 1
      spawnAsh(human.x, human.y)
      Audio.play("casualty")
    end
  elseif human.state == HUMAN_FLY then
    local side = human.speed_x < 0 and -5 or 5
    breakWindowAt(human.x + side + human.speed_x, human.y - 2)
    moveHumanHorizontal(human, human.speed_x)
    local landed = moveHumanVertical(human)
    if human.speed_x < 0 then
      human.speed_x = math.min(0, human.speed_x + 150 / (Profile.update_hz * Profile.update_hz))
    else
      human.speed_x = math.max(0, human.speed_x - 150 / (Profile.update_hz * Profile.update_hz))
    end
    if landed then
      human.butt_hits = human.butt_hits + 1
      if human.butt_hits >= 3 then setHumanState(human, HUMAN_WALK) end
    end
  end

  if human.x < -16 or human.x > Profile.map_width * 16 + 16 or
     human.y > Profile.map_height * 16 + 64 then
    human.active = false
    human.carried = false
    human_count = human_count - 1
    rescued_count = rescued_count + 1
    pending_rescues = pending_rescues + 1
    Audio.play("rescue")
  end
end

local function enemyMoveHorizontal(enemy, speed)
  local next_x = enemy.x + speed
  local side = speed < 0 and -7 or 7
  if World.solidPoint(next_x + side, enemy.y - 13) then
    enemy.direction = -enemy.direction
    return false
  end
  enemy.x = next_x
  return true
end

local function lineOfSight(x1, y1, x2, y2)
  local minimum_x = math.floor(math.min(x1, x2) / 16)
  local maximum_x = math.floor(math.max(x1, x2) / 16)
  local minimum_y = math.floor(math.min(y1, y2) / 16)
  local maximum_y = math.floor(math.max(y1, y2) / 16)
  for cell_y = minimum_y, maximum_y do
    for cell_x = minimum_x, maximum_x do
      if World.solidCell(cell_x, cell_y) then return false end
    end
  end
  for index = 1, Profile.door_max do
    local door = doors[index]
    if door.active and door.solid and door.x + 4 >= math.min(x1, x2) and
       door.x <= math.max(x1, x2) and door.y + 47 >= math.min(y1, y2) and
       door.y <= math.max(y1, y2) then
      return false
    end
  end
  return true
end

local function updateWalkingEnemy(enemy, player)
  if enemy.state == 2 then
    if enemy.hit_frames < 29 then
      enemy.state = 3
      enemy.timer = enemy.kind == 4 and 21 or 42
    end
    return
  elseif enemy.state == 3 then
    enemy.timer = enemy.timer - 1
    if enemy.timer <= 0 then enemy.state = 1 end
    return
  end
  local speed = enemy.kind == 7 and 120 or 80
  if (enemy.kind == 4 or enemy.kind == 7) and
     math.abs(player.y - enemy.y) < 64 and math.abs(player.x - enemy.x) < 256 and
     math.abs(player.x - enemy.x) > 16 and
     lineOfSight(enemy.x, enemy.y - 12, player.x, player.y - 12) then
    enemy.direction = player.x < enemy.x and -1 or 1
  end
  enemyMoveHorizontal(enemy, enemy.direction * speed / Profile.update_hz)
  enemy.fire_timer = enemy.fire_timer - 1
  if enemy.fire_timer <= 0 then
    World.addFire(math.floor(enemy.x / 16), math.floor((enemy.y - 4) / 16))
    enemy.fire_timer = (7 + random(19)) * Profile.update_hz
  end
  if enemy.kind == 7 and math.abs(player.x - enemy.x) <= 12 and
     math.abs(player.y - enemy.y) <= 24 then
    local upgrade_count = player.suit_count + player.tank_count +
                          player.regeneration_count
    if upgrade_count > 0 and player.stealItem(random(upgrade_count) + 1) then
      World.addFire(math.floor(enemy.x / 16), math.floor((enemy.y - 4) / 16))
      enemy.active = false
      enemy_count = enemy_count - 1
    end
  end
end

local function updateJumperEnemy(enemy, player)
  if enemy.state == 1 then
    enemy.timer = enemy.timer - 1
    if enemy.kind == 5 and math.abs(player.y - enemy.y) < 64 and
       math.abs(player.x - enemy.x) < 256 and math.abs(player.x - enemy.x) > 16 and
       lineOfSight(enemy.x, enemy.y - 12, player.x, player.y - 12) then
      enemy.direction = player.x < enemy.x and -1 or 1
    end
    if enemy.timer <= 0 then
      enemy.state = 2
      enemy.speed_y = -150 / Profile.update_hz
    end
    return
  end

  enemyMoveHorizontal(enemy, enemy.direction * 100 / Profile.update_hz)
  enemy.speed_y = enemy.speed_y + 350 / (Profile.update_hz * Profile.update_hz)
  local next_y = enemy.y + enemy.speed_y
  if enemy.speed_y >= 0 and
     (World.solidPoint(enemy.x - 6, next_y) or World.solidPoint(enemy.x + 6, next_y)) then
    enemy.y = math.floor(next_y / 16) * 16
    enemy.speed_y = 0
    enemy.state = 1
    enemy.timer = 60
    enemy.fire_timer = enemy.fire_timer - 1
    if enemy.fire_timer <= 0 then
      World.addFire(math.floor(enemy.x / 16), math.floor((enemy.y - 8) / 16))
      local maximum = enemy.kind == 5 and 8 or 13
      enemy.fire_timer = 3 + random(maximum - 2)
    end
  else
    enemy.y = next_y
  end
end

local function updateVolcanoEnemy(enemy, player)
  enemyMoveHorizontal(enemy, enemy.direction * 60 / Profile.update_hz)
  enemy.fire_timer = enemy.fire_timer - 1
  if enemy.kind == 6 and math.abs(player.y - enemy.y) < 64 and
     math.abs(player.x - enemy.x) < 256 and math.abs(player.x - enemy.x) > 16 and
     lineOfSight(enemy.x, enemy.y - 12, player.x, player.y - 12) then
    enemy.fire_timer = enemy.fire_timer - 1
  end
  if enemy.fire_timer <= 0 then
    enemy.fire_timer = 120
    for shot = 0, 3 do
      local speed = (enemy.direction * 60 - 60 + shot * 40) / Profile.update_hz
      assert(addProjectile(enemy.x, enemy.y - 27, speed))
    end
  end
end

local function updateEnemies(player)
  for index = 1, Profile.enemy_max do
    local enemy = enemies[index]
    if enemy.active then
      enemy.animation = enemy.animation + 1
      if enemy.hit_frames > 0 then enemy.hit_frames = enemy.hit_frames - 1 end
      if enemy.kind == 2 or enemy.kind == 5 then
        updateJumperEnemy(enemy, player)
      elseif enemy.kind == 3 or enemy.kind == 6 then
        updateVolcanoEnemy(enemy, player)
      else
        updateWalkingEnemy(enemy, player)
      end
    end
  end
end

local function extinguishProjectile(projectile)
  projectile.active = false
  projectile_count = projectile_count - 1
end

local function projectileExplosion(projectile)
  local cell_x = math.floor(projectile.x / 16)
  local cell_y = math.floor(projectile.y / 16)
  World.addFire(cell_x, cell_y)
  World.addFire(cell_x - 1, cell_y)
  World.addFire(cell_x + 1, cell_y)
  World.addFire(cell_x, cell_y - 1)
  World.addFire(cell_x, cell_y + 1)
  extinguishProjectile(projectile)
end

local function updateProjectiles(player)
  for index = 1, Profile.projectile_max do
    local projectile = projectiles[index]
    if projectile.active then
      projectile.animation = projectile.animation + 1
      if projectile.kind == 1 then
        projectile.speed_y = projectile.speed_y +
                             350 / (Profile.update_hz * Profile.update_hz)
        projectile.x = projectile.x + projectile.speed_x
        projectile.y = projectile.y + projectile.speed_y
        local cell_x = math.floor(projectile.x / 16)
        local cell_y = math.floor(projectile.y / 16)
        if projectile.y > Profile.map_height * 16 + 32 or
           World.solidCell(cell_x, cell_y) then
          if projectile.speed_y > 0 and random(25) == 0 then
            World.addFire(cell_x, cell_y - 1)
          end
          extinguishProjectile(projectile)
        end
      elseif projectile.kind == 2 then
        projectile.x = projectile.x + projectile.speed_x
        projectile.y = projectile.start_y +
                       (-math.cos(projectile.animation * 2.8 / Profile.update_hz) + 1) * 20
        if projectile.x < -32 or projectile.x > Profile.map_width * 16 + 32 then
          extinguishProjectile(projectile)
        elseif math.abs(projectile.x - player.x) <= 12 and
               math.abs(projectile.y - player.y + 8) <= 20 then
          projectileExplosion(projectile)
        end
      else
        projectile.y = projectile.y + projectile.speed_y
        if math.abs(projectile.x - player.x) <= 12 and
           math.abs(projectile.y - player.y + 8) <= 20 then
          projectileExplosion(projectile)
        elseif ((projectile.x < 176 or projectile.x > 480) and
                projectile.y >= Profile.map_height * 16 - 38) or
               projectile.y >= Profile.map_height * 16 - 22 then
          extinguishProjectile(projectile)
        end
      end
    end
  end
end

local function fireAtCell(cell_x, cell_y)
  for index = 1, Profile.fire_max do
    local fire = fires[index]
    if fire.active and fire.cell_x == cell_x and fire.cell_y == cell_y then return true end
  end
  return false
end

local function updateDoors()
  for index = 1, Profile.door_max do
    local door = doors[index]
    if door.active then
      if door.solid then
        if fireAtCell(door.cell_x, door.cell_y) or
           fireAtCell(door.cell_x, door.cell_y + 1) or
           fireAtCell(door.cell_x, door.cell_y + 2) then
          door.health = door.health - 0.2
        end
        if door.health <= 0 then
          door.solid = false
          door.speed_x = (random(101) - 50) / Profile.update_hz
          door.speed_y = -100 / Profile.update_hz
          Audio.play("door")
        end
      else
        door.speed_y = door.speed_y + 550 / (Profile.update_hz * Profile.update_hz)
        door.x = door.x + door.speed_x
        door.y = door.y + door.speed_y
        if door.y > Profile.map_height * 16 then door.active = false end
      end
    end
  end
end

function World.update(player)
  for index = 1, Profile.fire_max do
    local fire = fires[index]
    if fire.active then
      fire.animation = (fire.animation + 1) % 40
      if fire.health < 24 then
        fire.health = math.min(24, fire.health + 0.05)
      else
        fire.spread_frames = fire.spread_frames - 1
      end
      if fire.spread_frames <= 0 then
        local direction = random(4) + 1
        local target_x = fire.cell_x + spread_x[direction]
        local target_y = fire.cell_y + spread_y[direction]
        if spread_y[direction] ~= 0 and not canBurn(target_x, target_y) and
           random(5) == 0 then
          target_y = target_y + spread_y[direction]
        end
        World.addFire(target_x, target_y)
        fire.spread_frames = fireSpreadFrames()
      end
    end
  end

  updateDoors()
  updateEnemies(player)
  updateProjectiles(player)
  if active_boss then active_boss:update(World, player) end
  for index = 1, Profile.human_max do
    local human = humans[index]
    if human.active then updateHuman(human, player) end
  end
  for index = 1, Profile.item_max do
    local item = items[index]
    if item.active then
      item.animation = (item.animation + 1) % 48
      if not player.dead and math.abs(player.x - item.x - 8) <= 12 and
         math.abs(player.y - item.y - 10) <= 24 then
        item.active = false
        pending_score = pending_score + 500
        player.applyItem(item.kind)
      end
    end
  end
  for index = 1, Profile.particle_max do
    local ash = ashes[index]
    if ash.active then
      ash.animation = ash.animation + 1
      if ash.animation >= 82 then ash.active = false end
    end
  end
end

function World.tryCarry(player)
  if player.carrying ~= 0 then return false end
  for index = 1, Profile.human_max do
    local human = humans[index]
    if human.active and human.state ~= HUMAN_BURN then
      if math.abs(human.x - player.x) <= 24 and math.abs(human.y - player.y) <= 28 then
        human.carried = true
        setHumanState(human, HUMAN_CARRIED)
        player.carrying = index
        return true
      end
    end
  end
  return false
end

function World.throwCarried(player)
  if player.carrying == 0 then return false end
  local human = humans[player.carrying]
  assert(human.active and human.state == HUMAN_CARRIED)
  human.carried = false
  setHumanState(human, HUMAN_FLY)
  human.x = player.x
  human.y = player.y
  human.speed_x = player.direction * 250 / Profile.update_hz
  human.speed_y = -130 / Profile.update_hz
  human.direction = player.direction
  human.butt_hits = 0
  player.carrying = 0
  Audio.play("throw")
  return true
end

function World.spray(x, y, direction_x, direction_y, reach)
  local closest_fire = 0
  local closest_door = 0
  local closest_human = 0
  local closest_enemy = 0
  local closest_projectile = 0
  local closest_boss = false
  local closest_distance = reach + 1
  for index = 1, Profile.fire_max do
    local fire = fires[index]
    if fire.active then
      local delta_x = fire.cell_x * 16 + 8 - x
      local delta_y = fire.cell_y * 16 + 8 - y
      local distance = delta_x * direction_x + delta_y * direction_y
      local cross_distance = math.abs(delta_x * direction_y - delta_y * direction_x)
      if distance >= 0 and distance <= reach and cross_distance <= 18 then
        if distance < closest_distance then
          closest_fire = index
          closest_door = 0
          closest_human = 0
          closest_enemy = 0
          closest_projectile = 0
          closest_boss = false
          closest_distance = distance
        end
      end
    end
  end
  for index = 1, Profile.door_max do
    local door = doors[index]
    if door.active and door.solid then
      local delta_x = door.x + 2 - x
      local delta_y = door.y + 23 - y
      local distance = delta_x * direction_x + delta_y * direction_y
      local cross_distance = math.abs(delta_x * direction_y - delta_y * direction_x)
      if distance >= 0 and distance <= reach and cross_distance <= 28 then
        if distance < closest_distance then
          closest_fire = 0
          closest_door = index
          closest_human = 0
          closest_enemy = 0
          closest_projectile = 0
          closest_boss = false
          closest_distance = distance
        end
      end
    end
  end
  for index = 1, Profile.enemy_max do
    local enemy = enemies[index]
    if enemy.active then
      local delta_x = enemy.x - x
      local delta_y = enemy.y - 15 - y
      local distance = delta_x * direction_x + delta_y * direction_y
      local cross_distance = math.abs(delta_x * direction_y - delta_y * direction_x)
      if distance >= 0 and distance <= reach and cross_distance <= 18 then
        if distance < closest_distance then
          closest_fire = 0
          closest_door = 0
          closest_human = 0
          closest_enemy = index
          closest_projectile = 0
          closest_boss = false
          closest_distance = distance
        end
      end
    end
  end
  for index = 1, Profile.projectile_max do
    local projectile = projectiles[index]
    if projectile.active then
      local delta_x = projectile.x - x
      local delta_y = projectile.y - y
      local distance = delta_x * direction_x + delta_y * direction_y
      local cross_distance = math.abs(delta_x * direction_y - delta_y * direction_x)
      if distance >= 0 and distance <= reach and cross_distance <= 16 then
        if distance < closest_distance then
          closest_fire = 0
          closest_door = 0
          closest_human = 0
          closest_enemy = 0
          closest_projectile = index
          closest_boss = false
          closest_distance = distance
        end
      end
    end
  end
  if active_boss and not active_boss:isDefeated() then
    local delta_x = active_boss.x - x
    local delta_y = active_boss.y - 30 - y
    local distance = delta_x * direction_x + delta_y * direction_y
    local cross_distance = math.abs(delta_x * direction_y - delta_y * direction_x)
    if distance >= 0 and distance <= reach and cross_distance <= 36 then
      if distance < closest_distance then
        closest_fire = 0
        closest_door = 0
        closest_human = 0
        closest_enemy = 0
        closest_projectile = 0
        closest_boss = true
        closest_distance = distance
      end
    end
  end
  for index = 1, Profile.human_max do
    local human = humans[index]
    if human.active and human.state ~= HUMAN_CARRIED then
      local delta_x = human.x - x
      local delta_y = human.y - y
      local distance = delta_x * direction_x + delta_y * direction_y
      local cross_distance = math.abs(delta_x * direction_y - delta_y * direction_x)
      if distance >= 0 and distance <= reach and cross_distance <= 20 then
        if distance < closest_distance then
          closest_fire = 0
          closest_door = 0
          closest_human = index
          closest_enemy = 0
          closest_projectile = 0
          closest_boss = false
          closest_distance = distance
        end
      end
    end
  end
  if closest_door ~= 0 then
    local door = doors[closest_door]
    door.health = door.health - 1
    if door.health <= 0 then
      door.solid = false
      door.speed_x = direction_x * 50 / Profile.update_hz
      door.speed_y = -100 / Profile.update_hz
      pending_score = pending_score + 50
      pending_property_damage = pending_property_damage + 80 + random(41)
      Audio.play("door")
    end
  elseif closest_boss then
    if active_boss:hit(direction_x) and active_boss.health <= 0 and
       not boss_score_awarded then
      boss_score_awarded = true
      pending_score = pending_score + 5000
    end
  elseif closest_projectile ~= 0 then
    local projectile = projectiles[closest_projectile]
    projectile.health = projectile.health - 1
    if projectile.health <= 0 then
      pending_score = pending_score + (projectile.kind == 1 and 10 or 50)
      pending_extinguished = pending_extinguished + 1
      extinguishProjectile(projectile)
    end
  elseif closest_enemy ~= 0 then
    local enemy = enemies[closest_enemy]
    enemy.health = enemy.health - 1
    enemy.hit_frames = 30
    if enemy.kind == 1 or enemy.kind == 4 or enemy.kind == 7 then enemy.state = 2 end
    if direction_x ~= 0 then enemy.direction = -direction_x end
    if enemy.health <= 0 then
      enemy.active = false
      enemy_count = enemy_count - 1
      pending_score = pending_score + enemy_scores[enemy.kind]
      pending_extinguished = pending_extinguished + 1
      Audio.play("enemy")
    end
  elseif closest_human ~= 0 then
    local human = humans[closest_human]
    setHumanState(human, HUMAN_FLY)
    human.speed_x = direction_x * 100 / Profile.update_hz
    human.speed_y = direction_y * 100 / Profile.update_hz - 50 / Profile.update_hz
    human.butt_hits = 0
  elseif closest_fire ~= 0 then
    local fire = fires[closest_fire]
    fire.health = fire.health - 1
    if fire.health <= 0 then
      fire.active = false
      fire_count = fire_count - 1
      pending_score = pending_score + 20
      pending_extinguished = pending_extinguished + 1
      Audio.play("steam")
    end
  else
    return reach
  end
  return math.max(0, closest_distance)
end

local function drawMapTile(tile, screen_x, screen_y)
  if tile <= 0 then return end
  local index = tile - 1
  if index < 128 then
    ui.tile(tiles_0, index, screen_x, screen_y)
  else
    ui.tile(tiles_1, index - 128, screen_x, screen_y)
  end
end

function World.draw(camera_x, origin_y)
  if not active_boss then
    local parallax_x = -math.floor(camera_x * 32 /
                                   (Profile.map_width * 16 - Profile.width))
    for index = 1, 4 do
      ui.tile(night_sprites[index], 0, parallax_x + (index - 1) * 128, origin_y)
    end
  end
  local first_column = math.floor(camera_x / 16)
  local last_column = math.min(Profile.map_width - 1, first_column + 30)
  for cell_y = 0, Profile.map_height - 1 do
    for cell_x = first_column, last_column do
      drawMapTile(
        World.tileAt(cell_x, cell_y),
        cell_x * 16 - camera_x,
        cell_y * 16 + origin_y
      )
    end
  end

  for index = 1, Profile.door_max do
    local door = doors[index]
    if door.active then
      local sprite = door.health > 12 and door_normal_sprite or door_damaged_sprite
      ui.tile(
        sprite,
        0,
        math.floor(door.x - camera_x - 2),
        math.floor(door.y + origin_y),
        false,
        false
      )
    end
  end

  for index = 1, Profile.enemy_max do
    local enemy = enemies[index]
    if enemy.active then
      local sprites = enemy_sprites[enemy.kind]
      local sprite = sprites.run
      local frame = math.floor(enemy.animation / 8) % 4
      local width = enemy.kind == 7 and 18 or 16
      local height = (enemy.kind == 1 or enemy.kind == 4) and 26 or 32
      if enemy.state == 3 and sprites.recover then
        sprite = sprites.recover
        frame = math.floor(enemy.animation / 4) % sprite.ntiles
      elseif enemy.hit_frames > 0 and sprites.hit then
        sprite = sprites.hit
      end
      if (enemy.kind == 3 or enemy.kind == 6) and
         (enemy.fire_timer < 3 or enemy.fire_timer > 90) then
        sprite = sprites.shoot
      end
      if enemy.kind == 2 or enemy.kind == 5 then
        if enemy.state == 1 then frame = enemy.timer < 40 and 1 or 2 else frame = 0 end
      end
      ui.tile(
        sprite,
        frame % sprite.ntiles,
        math.floor(enemy.x - camera_x - width / 2),
        math.floor(enemy.y + origin_y - height),
        enemy.direction < 0,
        false
      )
      if enemy.hit_frames > 0 then
        local health_width = math.max(0, math.floor(16 * enemy.health / enemy.health_max))
        local bar_x = math.floor(enemy.x - camera_x - 8)
        local bar_y = math.floor(enemy.y + origin_y - height - 5)
        ui.rect(bar_x - 1, bar_y - 1, bar_x + 16, bar_y + 3, 1)
        if health_width > 0 then
          ui.rectfill(bar_x, bar_y, bar_x + health_width - 1, bar_y + 2, 2)
        end
      end
    end
  end

  for index = 1, Profile.projectile_max do
    local projectile = projectiles[index]
    if projectile.active then
      local sprite = fireball_sprite
      local frame = math.floor(projectile.animation / 6) % 4
      local offset = 4
      if projectile.kind == 2 then
        sprite = gasghost_sprite
        frame = math.floor(projectile.animation / 9) % 3
        offset = 12
      elseif projectile.kind == 3 then
        sprite = coalball_sprite
        frame = math.floor(projectile.animation / 9) % 12
        offset = 7
      end
      ui.tile(
        sprite,
        frame,
        math.floor(projectile.x - camera_x - offset),
        math.floor(projectile.y + origin_y - offset),
        projectile.speed_x < 0,
        false
      )
    end
  end

  if active_boss then active_boss:draw(camera_x, origin_y) end

  for index = 1, Profile.human_max do
    local human = humans[index]
    if human.active and human.state ~= HUMAN_CARRIED then
      local sprites = human_sprites[human.id]
      local sprite = sprites.run
      local frame = 0
      if human.state == HUMAN_WALK then
        frame = math.floor(human.animation / 13) % 4
      elseif human.state == HUMAN_FLY then
        sprite = sprites.fly
        if human.butt_hits >= 2 then
          frame = 3
        elseif human.speed_y > -20 / Profile.update_hz then
          frame = 1
        else
          frame = 2
        end
      elseif human.state == HUMAN_BURN then
        sprite = sprites.burn
        frame = math.floor(human.animation / 6) % 4
      elseif human.state == HUMAN_PANIC then
        sprite = sprites.panic
        frame = math.floor(human.animation / 6) % 6
      end
      ui.tile(
        sprite,
        frame,
        math.floor(human.x - camera_x - 10),
        math.floor(human.y + origin_y - 32),
        human.direction < 0,
        false
      )
    end
  end

  for index = 1, Profile.item_max do
    local item = items[index]
    if item.active then
      ui.tile(
        item_sprites[item.kind],
        math.floor(item.animation / 8) % 6,
        math.floor(item.x - camera_x),
        math.floor(item.y + origin_y)
      )
    end
  end

  for index = 1, Profile.fire_max do
    local fire = fires[index]
    if fire.active then
      ui.tile(
        fire_sprite,
        math.floor(fire.animation / 8) % 5,
        fire.cell_x * 16 - camera_x - 4,
        fire.cell_y * 16 + origin_y - 16
      )
    end
  end
  for index = 1, Profile.particle_max do
    local ash = ashes[index]
    if ash.active then
      ui.tile(
        ash_sprite,
        math.floor(ash.animation / 10) % 8,
        math.floor(ash.x - camera_x - 10),
        math.floor(ash.y + origin_y - 20)
      )
    end
  end
end

local function drawWarningAt(world_x, world_y, frame, camera_x, origin_y)
  local screen_x = world_x - camera_x
  local screen_y = world_y + origin_y
  if screen_x >= 12 and screen_x <= Profile.width - 12 and
     screen_y >= 28 and screen_y <= Profile.height - 28 then
    return
  end
  local delta_x = screen_x - Profile.width / 2
  local delta_y = screen_y - Profile.height / 2
  local scale_x = delta_x == 0 and 1000 or (Profile.width / 2 - 14) / math.abs(delta_x)
  local scale_y = delta_y == 0 and 1000 or (Profile.height / 2 - 30) / math.abs(delta_y)
  local scale = math.min(scale_x, scale_y)
  local icon_x = math.floor(Profile.width / 2 + delta_x * scale - 11)
  local icon_y = math.floor(Profile.height / 2 + delta_y * scale - 10)
  ui.tile(warning_sprites[frame + 1], 0, icon_x, icon_y)
end

function World.drawWarnings(camera_x, origin_y, frame)
  local animation = math.floor(frame / 30) % 2
  for index = 1, Profile.human_max do
    local human = humans[index]
    if human.active and (human.state == HUMAN_BURN or human.state == HUMAN_PANIC) then
      local offset = human.state == HUMAN_BURN and 0 or 2
      drawWarningAt(human.x, human.y - 12, offset + animation, camera_x, origin_y)
    end
  end
  for index = 1, Profile.particle_max do
    local ash = ashes[index]
    if ash.active then drawWarningAt(ash.x, ash.y - 12, 4, camera_x, origin_y) end
  end
end

function World.drawCarried(index, direction, screen_x, screen_y, animation)
  local human = humans[index]
  if not human or not human.active or human.state ~= HUMAN_CARRIED then return false end
  local sprites = human_sprites[human.id]
  local sprite = direction < 0 and sprites.carry_left or sprites.carry_right
  ui.tile(sprite, math.floor(animation / 8) % 4, screen_x - 11, screen_y - 32)
  return true
end

function World.heatAt(x, y)
  local heat = 0
  for index = 1, Profile.fire_max do
    local fire = fires[index]
    if fire.active then
      local delta_x = x - (fire.cell_x * 16 + 8)
      local delta_y = y - (fire.cell_y * 16 + 8)
      local distance_squared = delta_x * delta_x + delta_y * delta_y
      if distance_squared <= 1600 then
        local contribution = (1 - distance_squared / 1600)
        heat = heat + contribution * contribution * 0.5 * fire.health / 24
      end
    end
  end
  for index = 1, Profile.enemy_max do
    local enemy = enemies[index]
    if enemy.active and math.abs(enemy.x - x) <= 12 and math.abs(enemy.y - y) <= 26 then
      heat = math.max(heat, 1)
    end
  end
  for index = 1, Profile.projectile_max do
    local projectile = projectiles[index]
    if projectile.active and math.abs(projectile.x - x) <= 9 and
       math.abs(projectile.y - y) <= 18 then
      heat = math.max(heat, 1)
    end
  end
  if active_boss then heat = math.max(heat, active_boss:heatAt(x, y)) end
  return math.min(1.5, heat)
end

function World.certificationBossPlayerX()
  assert(active_boss ~= nil)
  if active_boss.x < 328 then return active_boss.x + 60 end
  return active_boss.x - 60
end

function World.bossDirectionFrom(x)
  if not active_boss then return 1 end
  return active_boss.x < x and -1 or 1
end

function World.isBossBattle()
  return active_boss ~= nil
end

function World.bossDefeated()
  return active_boss ~= nil and active_boss:isDefeated()
end

function World.consumeEvents()
  local score = pending_score
  local extinguished = pending_extinguished
  local rescues = pending_rescues
  local property_damage = pending_property_damage
  pending_score = 0
  pending_extinguished = 0
  pending_rescues = 0
  pending_property_damage = 0
  return score, extinguished, rescues, property_damage
end

function World.fireCount()
  return fire_count
end

function World.humanCount()
  return human_count
end

function World.rescuedCount()
  return rescued_count
end

function World.casualtyCount()
  return casualty_count
end

function World.logCertificationState()
  if active_boss then
    ui.log(
      "MR_RESCUE_BOSS=" .. active_boss.kind ..
      " X=" .. math.floor(active_boss.x) ..
      " STATE=" .. active_boss.state ..
      " HEALTH=" .. active_boss.health ..
      " DEFEATED=" .. tostring(active_boss:isDefeated())
    )
  end
  for index = 1, Profile.human_max do
    local human = humans[index]
    if human.active then
      ui.log(
        "MR_RESCUE_HUMAN=" .. index ..
        " X=" .. math.floor(human.x) ..
        " Y=" .. math.floor(human.y) ..
        " STATE=" .. human.state
      )
    end
  end
end

return World
