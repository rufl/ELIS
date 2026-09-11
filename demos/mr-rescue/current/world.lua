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
local small_fire_sprite = Sprites.find("assets/fire_wall_small")
local floor_fire_sprite = Sprites.find("assets/fire_floor")
local ash_sprite = Sprites.find("assets/ashes")
local black_smoke_sprite = Sprites.find("assets/black_smoke")
local small_smoke_sprite = Sprites.find("assets/black_smoke_small")
local sparkle_sprite = Sprites.find("assets/sparkles")
local shard_sprite = Sprites.find("assets/shards_spin")
local darkness_sprite = Sprites.find("assets/dark_dither")
local popup_sprites = {
  Sprites.find("assets/popup_rescue"), Sprites.find("assets/popup_coolant"),
  Sprites.find("assets/popup_suit"), Sprites.find("assets/popup_tank"),
  Sprites.find("assets/popup_reserve"), Sprites.find("assets/popup_regen"),
  Sprites.find("assets/popup_theft"), Sprites.find("assets/popup_combo_3"),
  Sprites.find("assets/popup_combo_4"), Sprites.find("assets/popup_combo_5"),
  Sprites.find("assets/popup_mega"),
}
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
local enemy_health_base = Sprites.find("assets/enemy_health_base")
local enemy_health_bar = Sprites.find("assets/enemy_health_bar")
local gasghost_sprite = Sprites.find("assets/gasghost")
local gasghost_hit_sprite = Sprites.find("assets/gasghost_hit")
local coalball_sprite = Sprites.find("assets/charcoal_projectile")
local door_normal_sprite = Sprites.find("assets/door_normal")
local door_damaged_sprite = Sprites.find("assets/door_damaged")
local door_normal_spin = Sprites.find("assets/door_normal_spin")
local door_damaged_spin = Sprites.find("assets/door_damaged_spin")
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
local spawnSmoke

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
    hit_frames = 0,
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
  ashes[index] = {
    active = false,
    kind = 1,
    x = 0,
    y = 0,
    speed_x = 0,
    speed_y = 0,
    animation = 0,
    life = 0,
    variant = 0,
    rotation = 0,
  }
end
for index = 1, Profile.room_max do
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

function World.basicLadderPoint(x, y)
  local tile = World.tileAt(math.floor(x / 16), math.floor(y / 16))
  return tile == 5 or tile == 8 or tile == 13
end

local function canBurn(cell_x, cell_y)
  if cell_x < 3 or cell_x > 37 or cell_y < -1 or cell_y > 16 then return false end
  if World.solidCell(cell_x, cell_y) then return false end
  local tile = World.tileAt(cell_x, cell_y)
  local below = World.tileAt(cell_x, cell_y + 1)
  if tile == 239 or tile == 240 or tile == 255 or tile == 256 or
     tile == 137 or tile == 153 or tile == 21 or below == 5 then
    return false
  end
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
      fire.animation = random(25)
      fire_count = fire_count + 1
      return true
    end
  end
  assert(false, "derived fire capacity exhausted")
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
      projectile.hit_frames = 0
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
      projectile.hit_frames = 0
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

local function validateBuilding()
  if room_count < 6 or room_count > Profile.room_max then return false end
  if start_x < 0 or start_y < 0 then return false end
  local active_doors = 0
  for index = 1, Profile.door_max do
    if doors[index].active then active_doors = active_doors + 1 end
  end
  if active_doors < 6 or active_doors > Profile.generated_door_max then return false end
  for floor = 0, 2 do
    local has_ladder = false
    for cell_y = floor * 5, floor * 5 + 4 do
      for cell_x = 3, Profile.map_width - 4 do
        local tile = World.tileAt(cell_x, cell_y)
        if tile == 5 or tile == 8 or tile == 13 or tile == 63 or tile == 79 or
           tile == 137 or tile == 153 or tile == 247 then
          has_ladder = true
        end
      end
    end
    if not has_ladder then return false end
  end
  for index = 1, room_count do
    local room = generated_rooms[index]
    if room.template == nil or #room.template.objects == 0 then return false end
  end
  return true
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
  assert(validateBuilding())
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
  for index = 1, Profile.fire_max do
    local fire = fires[index]
    if fire.active then
      fire.active = false
      spawnSmoke(fire.cell_x * 16 + 8, fire.cell_y * 16 + 8, false)
    end
  end
  for index = 1, Profile.enemy_max do
    local enemy = enemies[index]
    if enemy.active then
      enemy.active = false
      spawnSmoke(enemy.x, enemy.y - 8, false)
      pending_score = pending_score + enemy_scores[enemy.kind]
      pending_extinguished = pending_extinguished + 1
    end
  end
  for index = 1, Profile.projectile_max do
    local projectile = projectiles[index]
    if projectile.active then
      projectile.active = false
      spawnSmoke(projectile.x, projectile.y, projectile.kind == 1)
      pending_score = pending_score + (projectile.kind == 1 and 10 or 50)
      if projectile.kind == 1 then
        pending_extinguished = pending_extinguished + 1
      end
    end
  end
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

function World.preparePlayerTrace()
  for index = 1, #cells do cells[index] = 0 end
  for cell_x = 0, Profile.map_width - 1 do setTile(cell_x, 15, 1) end
  for index = 1, Profile.fire_max do fires[index].active = false end
  for index = 1, Profile.human_max do humans[index].active = false end
  for index = 1, Profile.enemy_max do enemies[index].active = false end
  for index = 1, Profile.projectile_max do projectiles[index].active = false end
  for index = 1, Profile.item_max do items[index].active = false end
  for index = 1, Profile.door_max do doors[index].active = false end
  for index = 1, Profile.particle_max do ashes[index].active = false end
  fire_count = 0
  human_count = 0
  enemy_count = 0
  projectile_count = 0
  active_boss = nil
  start_x = 200
  start_y = 240
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
    local enemy_top = enemy.y -
                      ((enemy.kind == 2 or enemy.kind == 5) and 23 or 15)
    if enemy.active and math.abs(enemy.x - human.x) <= 10 and
       human.y >= enemy_top and human.y - 16 <= enemy.y then
      return true
    end
  end
  for index = 1, Profile.projectile_max do
    local projectile = projectiles[index]
    if projectile.active then
      local half_width = projectile.kind == 1 and 3 or
                         (projectile.kind == 2 and 6 or 7)
      local half_height = projectile.kind == 1 and 3 or
                          (projectile.kind == 2 and 5 or 7)
      if math.abs(projectile.x - human.x) <= half_width + 5 and
         human.y >= projectile.y - half_height and
         human.y - 16 <= projectile.y + half_height then
        return true
      end
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

local function spawnParticle(kind, x, y, speed_x, speed_y, variant, life)
  for index = 1, Profile.particle_max do
    local particle = ashes[index]
    if not particle.active then
      particle.active = true
      particle.kind = kind
      particle.x = x
      particle.y = y
      particle.speed_x = speed_x or 0
      particle.speed_y = speed_y or 0
      particle.animation = 0
      particle.life = life or 0
      particle.variant = variant or 0
      particle.rotation = 0
      return true
    end
  end
  return false
end

local function spawnAsh(x, y)
  spawnParticle(1, x, y, 0, 0, 0, 82)
end

spawnSmoke = function(x, y, small)
  spawnParticle(small and 3 or 2, x, y, 0, 0, 0, small and 29 or 36)
end

local function spawnSparkles(x, y)
  for index = 1, 15 do
    local speed_x = (random(201) - 100) / Profile.update_hz
    local speed_y = -(50 + random(151)) / Profile.update_hz
    spawnParticle(4, x, y, speed_x, speed_y, index % 3, 120)
  end
end

local function spawnShards(x, y, direction)
  for index = 1, 8 do
    local speed_x = direction * (100 + random(101)) / Profile.update_hz
    local speed_y = (random(101) - 50) / Profile.update_hz
    spawnParticle(5, x, y + index * 3 + 4, speed_x, speed_y, index - 1, 180)
  end
end

function World.addPopup(x, y, variant)
  assert(variant >= 1 and variant <= #popup_sprites)
  spawnParticle(6, x, y, 0, 0, variant, 43)
end

function World.spawnBossDeathSmoke(x, y)
  spawnSmoke(x, y, false)
end

function World.certificationCapacityBoundaries()
  World.reset(0x4D52534B, 1, nil)

  for index = 1, Profile.human_max do humans[index].active = true end
  assert(not World.addHuman(0, 0))

  for index = 1, Profile.enemy_max do enemies[index].active = true end
  assert(not addEnemy(1, 0, 0))

  for index = 1, Profile.item_max do items[index].active = true end
  assert(not addItem(1, 0, 0))

  for index = 1, Profile.door_max do doors[index].active = true end
  assert(not addDoor(0, 0, "left"))

  for index = 1, Profile.projectile_max do projectiles[index].active = true end
  assert(not World.spawnBossHazard(2, 0, 0, 0, 0))

  for index = 1, Profile.particle_max do ashes[index].active = true end
  assert(not spawnParticle(1, 0, 0, 0, 0, 0, 1))

  for index = 1, Profile.fire_max do fires[index].active = false end
  local valid_x = 0
  local valid_y = 0
  local found_fire_cell = false
  for cell_y = 0, Profile.map_height - 2 do
    for cell_x = 3, Profile.map_width - 4 do
      if not found_fire_cell and canBurn(cell_x, cell_y) then
        valid_x = cell_x
        valid_y = cell_y
        found_fire_cell = true
      end
    end
  end
  assert(found_fire_cell)
  for index = 1, Profile.fire_max do
    fires[index].active = true
    fires[index].cell_x = -index
    fires[index].cell_y = -1
  end
  local accepted = pcall(World.addFire, valid_x, valid_y)
  assert(not accepted)

  ui.log("MR_RESCUE_CAPACITY_BOUNDARIES=PASS")
end

local function thrownHumanHitsDoor(x, top, bottom, speed)
  for index = 1, Profile.door_max do
    local door = doors[index]
    if door.active and door.solid and x >= door.x and x <= door.x + 4 and
       bottom >= door.y and top <= door.y + 47 then
      door.health = door.health - 9.6
      if door.health < 0 then
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

local function breakWindowAt(x, y, direction)
  local cell_x = math.floor(x / 16)
  local cell_y = math.floor(y / 16)
  local tile = World.tileAt(cell_x, cell_y)
  if tile == 38 then
    setTile(cell_x, cell_y - 1, 239)
    setTile(cell_x, cell_y, 255)
    pending_property_damage = pending_property_damage + 100 + random(101)
    spawnShards(cell_x * 16 + 6, (cell_y - 1) * 16, direction)
    Audio.play("glass")
    return true
  elseif tile == 39 then
    setTile(cell_x, cell_y - 1, 240)
    setTile(cell_x, cell_y, 256)
    pending_property_damage = pending_property_damage + 100 + random(101)
    spawnShards(cell_x * 16 + 10, (cell_y - 1) * 16, direction)
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
    breakWindowAt(
      human.x + side + human.speed_x,
      human.y - 2,
      human.speed_x < 0 and -1 or 1
    )
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
      World.addPopup(player.x, player.y - 24, 7)
      spawnSmoke(enemy.x, enemy.y - 8, false)
      spawnSmoke(enemy.x - 6, enemy.y - 18, false)
      spawnSmoke(enemy.x + 6, enemy.y - 18, false)
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
  spawnSmoke(projectile.x, projectile.y - 8, false)
  spawnSmoke(projectile.x - 6, projectile.y - 18, false)
  spawnSmoke(projectile.x + 6, projectile.y - 18, false)
  if projectile.kind == 2 then Audio.play("explosion") end
  extinguishProjectile(projectile)
end

local function updateProjectiles(player)
  for index = 1, Profile.projectile_max do
    local projectile = projectiles[index]
    if projectile.active then
      projectile.animation = projectile.animation + 1
      if projectile.hit_frames > 0 then projectile.hit_frames = projectile.hit_frames - 1 end
      if projectile.kind == 1 then
        projectile.speed_y = projectile.speed_y +
                             350 / (Profile.update_hz * Profile.update_hz)
        projectile.x = projectile.x + projectile.speed_x
        projectile.y = projectile.y + projectile.speed_y
        local cell_x = math.floor(projectile.x / 16)
        local cell_y = math.floor(projectile.y / 16)
        if projectile.y > Profile.map_height * 16 + 32 or
           World.solidCell(cell_x, cell_y) then
          if projectile.speed_y > 0 then
            local tile = World.tileAt(cell_x, cell_y)
            if tile >= 1 and tile <= 5 and random(25) == 0 then
              World.addFire(cell_x, cell_y - 1)
            end
          end
          spawnSmoke(projectile.x, projectile.y - 1, true)
          extinguishProjectile(projectile)
        else
          for door_index = 1, Profile.door_max do
            local door = doors[door_index]
            if door.active and door.solid and projectile.x + 3 >= door.x and
               projectile.x - 3 <= door.x + 4 and projectile.y + 3 >= door.y and
               projectile.y - 3 <= door.y + 47 then
              spawnSmoke(projectile.x, projectile.y, true)
              extinguishProjectile(projectile)
              break
            end
          end
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
          spawnSmoke(projectile.x, projectile.y, false)
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
        if door.health < 0 then
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

local function updateFires()
  for index = 1, Profile.fire_max do
    local fire = fires[index]
    if fire.active and fire.cell_y >= 0 and
       fire.cell_y < Profile.map_height then
      fire.animation = (fire.animation + 1) % 100
      if fire.health < 24 then
        fire.health = math.min(24, fire.health + 0.05)
      else
        fire.spread_frames = fire.spread_frames - 1
      end
      if fire.spread_frames <= 0 then
        local direction = random(4) + 1
        local target_x = fire.cell_x + spread_x[direction]
        local target_y = fire.cell_y + spread_y[direction]
        local can_burn_through = (spread_y[direction] < 0 and target_y > 0) or
                                 (spread_y[direction] > 0 and target_y < 14)
        if can_burn_through and not canBurn(target_x, target_y) and
           random(5) == 0 then
          target_y = target_y + spread_y[direction]
        end
        World.addFire(target_x, target_y)
        fire.spread_frames = fireSpreadFrames()
      end
    end
  end
end

function World.update(player)
  updateDoors()
  updateEnemies(player)
  updateProjectiles(player)
  for index = 1, Profile.human_max do
    local human = humans[index]
    if human.active then updateHuman(human, player) end
  end
  for index = 1, Profile.item_max do
    local item = items[index]
    if item.active then item.animation = (item.animation + 1) % 216 end
  end
  for index = 1, Profile.particle_max do
    local particle = ashes[index]
    if particle.active then
      particle.animation = particle.animation + 1
      particle.life = particle.life - 1
      if particle.kind == 4 or particle.kind == 5 then
        local gravity = particle.kind == 4 and 500 or 350
        particle.speed_y = particle.speed_y +
                           gravity / (Profile.update_hz * Profile.update_hz)
        particle.x = particle.x + particle.speed_x
        particle.y = particle.y + particle.speed_y
        if particle.kind == 5 then
          particle.rotation = particle.rotation + particle.speed_x * 0.2
        end
      end
      if particle.life <= 0 or
         (particle.kind == 5 and particle.y > Profile.map_height * 16 + 4) then
        particle.active = false
      end
    end
  end
  updateFires()
  if active_boss then
    active_boss:update(World, player)
    if active_boss.just_died and not boss_score_awarded then
      boss_score_awarded = true
      pending_score = pending_score + 5000
    end
  end
end

local function playerTouchesHuman(player, human)
  return player.x - 6 <= human.x + 5 and player.x + 5 >= human.x - 5 and
         player.y - 22 <= human.y and player.y >= human.y - 16
end

function World.collectItems(player)
  if player.dead then return end
  for index = 1, Profile.item_max do
    local item = items[index]
    if item.active then
      local item_left = item.x + 4
      local item_top = item.y
      if player.x - 6 <= item_left + 7 and player.x + 5 >= item_left and
         player.y - 22 <= item_top + 20 and player.y >= item_top then
        item.active = false
        pending_score = pending_score + 500
        spawnSparkles(item.x + 6, item.y + 10)
        World.addPopup(player.x, player.y - 24, item.kind + 1)
        player.applyItem(item.kind)
      end
    end
  end
end

function World.canCarry(player)
  for index = 1, Profile.human_max do
    local human = humans[index]
    if human.active and human.state ~= HUMAN_BURN and
       playerTouchesHuman(player, human) then
      return true
    end
  end
  return false
end

function World.tryCarry(player)
  if player.carrying ~= 0 then return false end
  for index = 1, Profile.human_max do
    local human = humans[index]
    if human.active and human.state ~= HUMAN_BURN and
       playerTouchesHuman(player, human) then
      human.carried = true
      setHumanState(human, HUMAN_CARRIED)
      player.carrying = index
      return true
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

function World.spray(x, y, direction_x, direction_y, reach, impact_direction)
  assert(impact_direction == -1 or impact_direction == 1)
  local closest_fire = 0
  local closest_door = 0
  local closest_human = 0
  local closest_enemy = 0
  local closest_projectile = 0
  local closest_boss = false
  local closest_wall = false
  local closest_distance = reach + 1
  local distance = 4
  while distance <= reach do
    local point_x = x + direction_x * distance
    local point_y = y + direction_y * distance
    if World.solidCell(math.floor(point_x / 16), math.floor(point_y / 16)) then
      closest_wall = true
      closest_distance = distance
      break
    end
    distance = distance + 4
  end
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
    if door.health < 0 then
      door.solid = false
      door.speed_x = impact_direction * 50 / Profile.update_hz
      door.speed_y = -100 / Profile.update_hz
      pending_score = pending_score + 50
      pending_property_damage = pending_property_damage + 80 + random(41)
      Audio.play("door")
    end
  elseif closest_boss then
    active_boss:hit(impact_direction)
  elseif closest_projectile ~= 0 then
    local projectile = projectiles[closest_projectile]
    projectile.health = projectile.health - 1
    projectile.hit_frames = 6
    if projectile.health <= 0 then
      spawnSmoke(projectile.x, projectile.y, projectile.kind == 1)
      pending_score = pending_score + (projectile.kind == 1 and 10 or 50)
      if projectile.kind == 1 then
        pending_extinguished = pending_extinguished + 1
      end
      extinguishProjectile(projectile)
    end
  elseif closest_enemy ~= 0 then
    local enemy = enemies[closest_enemy]
    enemy.health = enemy.health - 1
    enemy.hit_frames = 30
    if enemy.kind == 1 or enemy.kind == 4 or enemy.kind == 7 then enemy.state = 2 end
    enemy.direction = -impact_direction
    if enemy.health <= 0 then
      enemy.active = false
      enemy_count = enemy_count - 1
      spawnSmoke(enemy.x, enemy.y - 8, false)
      pending_score = pending_score + enemy_scores[enemy.kind]
      pending_extinguished = pending_extinguished + 1
      Audio.play("enemy")
    end
  elseif closest_human ~= 0 then
    local human = humans[closest_human]
    setHumanState(human, HUMAN_FLY)
    human.speed_x = impact_direction * 100 / Profile.update_hz
    human.speed_y = -50 / Profile.update_hz
    human.butt_hits = 0
  elseif closest_fire ~= 0 then
    local fire = fires[closest_fire]
    fire.health = fire.health - 1
    if fire.health < 0 then
      fire.active = false
      fire_count = fire_count - 1
      spawnSmoke(fire.cell_x * 16 + 8, fire.cell_y * 16 + 8, false)
      pending_score = pending_score + 20
      pending_extinguished = pending_extinguished + 1
      Audio.play("steam")
    end
  elseif closest_wall then
    local hit_x = x + direction_x * closest_distance
    local hit_y = y + direction_y * closest_distance
    breakWindowAt(hit_x, hit_y, impact_direction)
  else
    return reach
  end
  return math.max(0, closest_distance)
end

function World.certificationInteractionTrace(player)
  Audio.resetCertificationCounts()
  World.preparePlayerTrace()
  player.x = 200
  player.y = 240
  player.direction = 1

  assert(addDoor(240, 192, "right"))
  for _ = 1, 19 do World.spray(210, 232, 1, 0, 100, 1) end
  local door_broken = false
  for index = 1, Profile.door_max do
    if doors[index].active and not doors[index].solid then door_broken = true end
  end
  assert(door_broken)
  local door_score, _, _, door_damage = World.consumeEvents()
  assert(door_score == 50 and door_damage >= 80 and door_damage <= 120)

  setTile(20, 14, 38)
  player.x = 280
  World.spray(290, 232, 1, 0, 100, 1)
  assert(World.tileAt(20, 13) == 239 and World.tileAt(20, 14) == 255)
  local _, _, _, window_damage = World.consumeEvents()
  assert(window_damage >= 100 and window_damage <= 200)

  assert(World.addHuman(200, 240))
  assert(World.addFire(12, 14))
  for index = 1, Profile.human_max do
    local human = humans[index]
    if human.active then
      updateHuman(human, player)
      assert(human.state == HUMAN_BURN)
      break
    end
  end

  player.suit_count = 1
  player.tank_count = 1
  player.regeneration_count = 1
  assert(addEnemy(7, player.x, player.y))
  for index = 1, Profile.enemy_max do
    local enemy = enemies[index]
    if enemy.active and enemy.kind == 7 then
      updateWalkingEnemy(enemy, player)
      assert(not enemy.active)
      break
    end
  end
  assert(player.suit_count + player.tank_count + player.regeneration_count == 2)

  assert(World.spawnBossHazard(2, player.x, player.y - 8, 0, 0))
  updateProjectiles(player)
  assert(projectile_count == 0 and fire_count >= 1)
  local interaction_fire_count = fire_count
  World.consumeEvents()

  local enemy_kills = 0
  for kind = 1, 7 do
    World.preparePlayerTrace()
    player.x = 200
    player.y = 240
    player.direction = 1
    assert(addEnemy(kind, 260, 240))
    World.spray(210, 232, 1, 0, 100, 1)
    local target
    for index = 1, Profile.enemy_max do
      if enemies[index].active then target = enemies[index] break end
    end
    assert(target ~= nil and target.health == target.health_max - 1)
    if kind == 1 or kind == 4 or kind == 7 then
      updateEnemies(player)
      updateEnemies(player)
      assert(target.state == 3)
    end
    for _ = 1, target.health_max + 1 do
      if target.active then World.spray(210, 232, 1, 0, 100, 1) end
    end
    assert(not target.active)
    local score, extinguished = World.consumeEvents()
    assert(score == enemy_scores[kind] and extinguished == 1)
    enemy_kills = enemy_kills + 1
  end

  World.preparePlayerTrace()
  assert(World.addFire(12, 14))
  local spread_frame = 0
  for frame = 1, 2000 do
    updateFires()
    if fire_count > 1 then spread_frame = frame break end
  end
  assert(spread_frame > 360 and spread_frame <= 2000)
  assert(Audio.certificationCount("door") == 1)
  assert(Audio.certificationCount("glass") == 1)
  assert(Audio.certificationCount("enemy") == 7)
  assert(Audio.certificationCount("explosion") == 1)

  ui.log(
    "MR_RESCUE_INTERACTIONS=PASS DOOR_SCORE=" .. door_score ..
    " DOOR_DAMAGE=" .. door_damage ..
    " WINDOW_DAMAGE=" .. window_damage ..
    " FIRE=" .. interaction_fire_count ..
    " ENEMY_KILLS=" .. enemy_kills ..
    " SPREAD_FRAME=" .. spread_frame ..
    " EFFECTS=10"
  )
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

function World.draw(camera_x, origin_y, family_presentation, phase)
  local draw_front = phase == "front"
  if not draw_front and not active_boss then
    local parallax_x = -math.floor(camera_x * 32 /
                                   (Profile.map_width * 16 - Profile.width))
    for index = 1, 4 do
      ui.tile(night_sprites[index], 0, parallax_x + (index - 1) * 128, origin_y)
    end
  end
  if not draw_front then
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
  end

  if not draw_front then
    for index = 1, Profile.fire_max do
      local fire = fires[index]
      if fire.active then
        local fire_frame = math.floor(fire.animation / 5) % 5
        local wall_sprite = fire.health < 12 and small_fire_sprite or fire_sprite
        ui.tile(
          wall_sprite,
          fire_frame,
          fire.cell_x * 16 - camera_x - 4,
          fire.cell_y * 16 + origin_y - 16
        )
      end
    end
  end

  if draw_front then
  for index = 1, Profile.door_max do
    local door = doors[index]
    if door.active then
      local normal = door.health > 12
      if door.solid then
        ui.tile(
          normal and door_normal_sprite or door_damaged_sprite,
          0,
          math.floor(door.x - camera_x - 2),
          math.floor(door.y + origin_y),
          false,
          false
        )
      else
        local angle = (100 + door.speed_y * Profile.update_hz) *
                      (door.speed_x * Profile.update_hz) * 0.0005
        local frame = math.floor(angle * 4 / math.pi + 0.5) % 8
        ui.tile(
          normal and door_normal_spin or door_damaged_spin,
          frame,
          math.floor(door.x - camera_x - 26),
          math.floor(door.y + origin_y)
        )
      end
    end
  end
  end

  if not draw_front then
  for index = 1, Profile.enemy_max do
    local enemy = enemies[index]
    if enemy.active then
      local sprites = enemy_sprites[enemy.kind]
      local sprite = sprites.run
      local animation_delay = (enemy.kind == 3 or enemy.kind == 6) and 10.2 or 7.8
      local frame = math.floor(enemy.animation / animation_delay) % 4
      local width = enemy.kind == 7 and 18 or 16
      local height = (enemy.kind == 1 or enemy.kind == 4) and 26 or 32
      if enemy.state == 3 and sprites.recover then
        sprite = sprites.recover
        frame = math.floor(enemy.animation / 4.2) % sprite.ntiles
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
        local health_width = math.max(
          0, math.floor(16 * enemy.health / enemy.health_max + 0.5)
        )
        local health_y = enemy.y + origin_y -
                         ((enemy.kind == 1 or enemy.kind == 4) and 30 or 36)
        ui.tile(
          enemy_health_base,
          0,
          math.floor(enemy.x - camera_x - 10),
          math.floor(health_y - 4)
        )
        ui.tile(
          enemy_health_bar,
          health_width,
          math.floor(enemy.x - camera_x - 8),
          math.floor(health_y - 2)
        )
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
        sprite = projectile.hit_frames > 0 and gasghost_hit_sprite or gasghost_sprite
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
        frame = math.floor(human.animation / 13.2) % 4
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
        if family_presentation then
          sprite = sprites.panic
          frame = math.floor(human.animation / 6) % 6
        else
          sprite = sprites.burn
          frame = math.floor(human.animation / 6) % 4
        end
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
  end

  if draw_front then
  for index = 1, Profile.item_max do
    local item = items[index]
    if item.active then
      ui.tile(
        item_sprites[item.kind],
        math.floor(item.animation / 7.2) % 6,
        math.floor(item.x - camera_x),
        math.floor(item.y + origin_y)
      )
    end
  end
  end

  for index = 1, Profile.fire_max do
    local fire = fires[index]
    if fire.active then
      local floor_frame = math.floor(fire.animation / 5) % 4
      if draw_front and World.solidCell(fire.cell_x, fire.cell_y + 1) then
        ui.tile(
          floor_fire_sprite,
          floor_frame,
          fire.cell_x * 16 - camera_x,
          fire.cell_y * 16 + origin_y + 1
        )
      end
      if draw_front and World.solidCell(fire.cell_x, fire.cell_y - 1) then
        ui.tile(
          floor_fire_sprite,
          floor_frame,
          fire.cell_x * 16 - camera_x,
          fire.cell_y * 16 + origin_y - 1,
          false,
          true
        )
      end
    end
  end
  if draw_front then
  for index = 1, Profile.particle_max do
    local particle = ashes[index]
    if particle.active then
      local sprite = ash_sprite
      local frame = math.floor(particle.animation / 10) % 8
      local offset_x = 10
      local offset_y = 20
      if particle.kind == 1 and family_presentation then
        sprite = sparkle_sprite
        frame = math.floor(particle.animation / 6) % 3
        offset_x, offset_y = 3, 4
      elseif particle.kind == 2 then
        sprite = black_smoke_sprite
        frame = math.floor(particle.animation / 6) % 6
      elseif particle.kind == 3 then
        sprite = small_smoke_sprite
        frame = math.floor(particle.animation / 7.2) % 4
        offset_x, offset_y = 4, 4
      elseif particle.kind == 4 then
        sprite = sparkle_sprite
        frame = particle.variant
        offset_x, offset_y = 3, 3
      elseif particle.kind == 5 then
        sprite = shard_sprite
        local rotation_frame = math.floor(
          particle.rotation * 4 / math.pi + 0.5
        ) % 8
        frame = particle.variant * 8 + rotation_frame
        offset_x, offset_y = 4, 4
      elseif particle.kind == 6 then
        sprite = popup_sprites[particle.variant]
        frame = 0
        offset_x = 32
        offset_y = math.floor(math.sqrt(particle.animation / Profile.update_hz) * 32)
      end
      ui.tile(
        sprite,
        frame,
        math.floor(particle.x - camera_x - offset_x),
        math.floor(particle.y + origin_y - offset_y)
      )
    end
  end
  end
end

function World.drawBossHud()
  if active_boss then active_boss:drawHud() end
end

local function lightingBlockIsLit(world_x, world_y, player_x, player_y)
  local player_delta_x = world_x - player_x
  local player_delta_y = world_y - (player_y - 11)
  if player_delta_x * player_delta_x + player_delta_y * player_delta_y <= 10000 then
    return true
  end
  for index = 1, Profile.fire_max do
    local fire = fires[index]
    if fire.active then
      local delta_x = world_x - (fire.cell_x * 16 + 8)
      local delta_y = world_y - (fire.cell_y * 16 + 8)
      if delta_x * delta_x + delta_y * delta_y <= 2704 then return true end
    end
  end
  for index = 1, Profile.enemy_max do
    local enemy = enemies[index]
    if enemy.active then
      local delta_x = world_x - enemy.x
      local delta_y = world_y - (enemy.y - 12)
      if delta_x * delta_x + delta_y * delta_y <= 2025 then return true end
    end
  end
  if active_boss then
    local delta_x = world_x - active_boss.x
    local delta_y = world_y - (active_boss.y - 30)
    if delta_x * delta_x + delta_y * delta_y <= 3600 then return true end
  end
  return false
end

function World.drawLighting(camera_x, origin_y, player_x, player_y)
  for block_y = 0, 7 do
    for block_x = 0, 14 do
      local world_x = camera_x + block_x * 32 + 16
      local world_y = block_y * 32 + 16
      if world_x >= 32 and world_x < Profile.map_width * 16 - 32 and
         not lightingBlockIsLit(world_x, world_y, player_x, player_y) then
        ui.tile(darkness_sprite, 0, block_x * 32, origin_y + block_y * 32)
      end
    end
  end
end

local function drawWarningAt(world_x, world_y, frame, camera_x, origin_y)
  local screen_x = world_x - camera_x
  local screen_y = world_y + origin_y
  if screen_x >= 12 and screen_x <= Profile.width - 12 and
     screen_y >= 28 and screen_y <= Profile.stage_height - 28 then
    return
  end
  local delta_x = screen_x - Profile.width / 2
  local delta_y = screen_y - Profile.stage_height / 2
  local scale_x = delta_x == 0 and 1000 or (Profile.width / 2 - 14) / math.abs(delta_x)
  local scale_y = delta_y == 0 and 1000 or (Profile.stage_height / 2 - 30) / math.abs(delta_y)
  local scale = math.min(scale_x, scale_y)
  local icon_x = math.floor(Profile.width / 2 + delta_x * scale - 11)
  local icon_y = math.floor(Profile.stage_height / 2 + delta_y * scale - 10)
  ui.tile(warning_sprites[frame + 1], 0, icon_x, icon_y)
end

function World.drawWarnings(camera_x, origin_y, frame, family_presentation)
  local animation = math.floor(frame / 30) % 2
  for index = 1, Profile.human_max do
    local human = humans[index]
    if human.active and (human.state == HUMAN_BURN or human.state == HUMAN_PANIC) then
      local offset = human.state == HUMAN_BURN and
                     (family_presentation and 2 or 0) or 2
      drawWarningAt(human.x, human.y - 12, offset + animation, camera_x, origin_y)
    end
  end
  for index = 1, Profile.particle_max do
    local ash = ashes[index]
    if ash.active and ash.kind == 1 then
      local warning = family_presentation and 2 or 4
      drawWarningAt(ash.x, ash.y - 12, warning, camera_x, origin_y)
    end
  end
end

function World.drawCarried(index, direction, screen_x, screen_y, animation, speed_x)
  local human = humans[index]
  if not human or not human.active or human.state ~= HUMAN_CARRIED then return false end
  local sprites = human_sprites[human.id]
  local sprite = direction < 0 and sprites.carry_left or sprites.carry_right
  local frame = math.floor(animation / 7.2) % 4
  if math.abs(speed_x) < 30 / Profile.update_hz then frame = 0 end
  ui.tile(sprite, frame, screen_x - 11, screen_y - 32)
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
    local enemy_top = enemy.y -
                      ((enemy.kind == 2 or enemy.kind == 5) and 23 or 15)
    if enemy.active and math.abs(enemy.x - x) <= 11 and
       y + 11 >= enemy_top and y - 11 <= enemy.y then
      heat = math.max(heat, 1)
    end
  end
  for index = 1, Profile.projectile_max do
    local projectile = projectiles[index]
    if projectile.active then
      local half_width = projectile.kind == 1 and 3 or
                         (projectile.kind == 2 and 6 or 7)
      local half_height = projectile.kind == 1 and 3 or
                          (projectile.kind == 2 and 5 or 7)
      if math.abs(projectile.x - x) <= half_width + 6 and
         y + 11 >= projectile.y - half_height and
         y - 11 <= projectile.y + half_height then
        heat = math.max(heat, 1)
      end
    end
  end
  if active_boss then heat = math.max(heat, active_boss:heatAt(x, y)) end
  return heat
end

function World.certificationBossPlayerX()
  assert(active_boss ~= nil)
  if active_boss.x < 254 then return active_boss.x + 60 end
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
  for index = 1, Profile.enemy_max do
    local enemy = enemies[index]
    if enemy.active then
      ui.log(
        "MR_RESCUE_ENEMY=" .. enemy.kind ..
        " X=" .. math.floor(enemy.x) ..
        " Y=" .. math.floor(enemy.y) ..
        " STATE=" .. enemy.state ..
        " HEALTH=" .. enemy.health
      )
    end
  end
  ui.log(
    "MR_RESCUE_WORLD FIRE=" .. fire_count ..
    " PROJECTILES=" .. projectile_count ..
    " CASUALTIES=" .. casualty_count ..
    " RESCUED=" .. rescued_count
  )
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
