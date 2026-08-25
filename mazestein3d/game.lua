-- Mazestein 3D, adapted from NOIST1611/Mazestein3D for ELIS.
-- The source project is a textureless Retro Gadgets raycaster. This port keeps
-- that visual scope while replacing gdt/Color/VideoChip APIs with ui.* calls.

local SCREEN_W, SCREEN_H = 480, 270
local VIEW_H = 252
local TILE = 64
local MAP_W, MAP_H = 15, 15
local FOV = math.pi / 3
local HALF_FOV = FOV / 2
local RAYS = 120
local SLICE_W = SCREEN_W / RAYS
local MOVE_SPEED = 2.0
local TURN_SPEED = 0.045
local PLAYER_RADIUS = 12

-- Palette indices are deliberately small: the original target was a tiny
-- device, and this port uses only eight indexed colors.
local PALETTE = {
  0x0000, -- black
  0x1084, -- ceiling
  0x2108, -- floor
  0x7FFF, -- bright wall
  0x4210, -- distant wall
  0x56B5, -- wall side A
  0x2D6B, -- wall side B
  0x7FFF, -- HUD
}
for i = 1, #PALETTE do ui.palset(i - 1, PALETTE[i]) end

-- 1 = wall, 0 = open. This is the same row-major grid convention used by
-- Mazestein3D's TileMap configuration, with a bounded outer wall.
local MAP = {
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
  1,0,0,0,1,0,0,0,0,0,1,0,0,0,1,
  1,0,1,0,1,0,1,1,1,0,1,0,1,0,1,
  1,0,1,0,0,0,1,0,1,0,0,0,1,0,1,
  1,0,1,1,1,1,1,0,1,1,1,1,1,0,1,
  1,0,0,0,0,0,1,0,0,0,0,0,0,0,1,
  1,1,1,1,1,0,1,1,1,1,1,1,1,0,1,
  1,0,0,0,1,0,0,0,0,0,0,0,1,0,1,
  1,0,1,0,1,1,1,1,1,1,1,0,1,0,1,
  1,0,1,0,0,0,0,0,0,0,1,0,0,0,1,
  1,0,1,1,1,1,1,1,1,0,1,1,1,0,1,
  1,0,0,0,0,0,0,0,1,0,0,0,0,0,1,
  1,0,1,1,1,1,1,0,1,1,1,0,1,0,1,
  1,0,0,0,0,0,0,0,0,0,0,0,1,0,1,
  1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,
}

local player_x, player_y = TILE * 1.5, TILE * 1.5
local player_angle = 0
local frames = 0

local function cell(x, y)
  if x < 0 or y < 0 or x >= MAP_W or y >= MAP_H then return 1 end
  return MAP[y * MAP_W + x + 1]
end

local function open_at(x, y)
  return cell(math.floor(x / TILE), math.floor(y / TILE)) == 0
end

local function can_stand(x, y)
  return open_at(x - PLAYER_RADIUS, y - PLAYER_RADIUS)
    and open_at(x + PLAYER_RADIUS, y - PLAYER_RADIUS)
    and open_at(x - PLAYER_RADIUS, y + PLAYER_RADIUS)
    and open_at(x + PLAYER_RADIUS, y + PLAYER_RADIUS)
end

local function move_player(forward)
  local dx = math.cos(player_angle) * forward * MOVE_SPEED
  local dy = math.sin(player_angle) * forward * MOVE_SPEED
  local next_x, next_y = player_x + dx, player_y + dy
  if can_stand(next_x, player_y) then player_x = next_x end
  if can_stand(player_x, next_y) then player_y = next_y end
end

-- DDA walks grid boundaries instead of sampling thousands of world positions.
-- It is deterministic and caps work at the map diagonal plus a small margin.
local function cast_ray(angle)
  local pos_x, pos_y = player_x / TILE, player_y / TILE
  local ray_x, ray_y = math.cos(angle), math.sin(angle)
  local map_x, map_y = math.floor(pos_x), math.floor(pos_y)
  local delta_x = math.abs(1 / ray_x)
  local delta_y = math.abs(1 / ray_y)
  local step_x, step_y, side_x, side_y

  if ray_x < 0 then
    step_x = -1
    side_x = (pos_x - map_x) * delta_x
  else
    step_x = 1
    side_x = (map_x + 1 - pos_x) * delta_x
  end
  if ray_y < 0 then
    step_y = -1
    side_y = (pos_y - map_y) * delta_y
  else
    step_y = 1
    side_y = (map_y + 1 - pos_y) * delta_y
  end

  for _ = 1, MAP_W + MAP_H + 8 do
    local side
    if side_x < side_y then
      side_x = side_x + delta_x
      map_x = map_x + step_x
      side = 0
    else
      side_y = side_y + delta_y
      map_y = map_y + step_y
      side = 1
    end
    if cell(map_x, map_y) == 1 then
      local distance = (side == 0 and side_x - delta_x or side_y - delta_y) * TILE
      return distance, side
    end
  end
  return TILE * (MAP_W + MAP_H), 0
end

local function draw_world()
  ui.rectfill(0, 0, SCREEN_W, VIEW_H / 2, 1)
  ui.rectfill(0, VIEW_H / 2, SCREEN_W, VIEW_H, 2)

  for ray = 0, RAYS - 1 do
    local ray_angle = player_angle - HALF_FOV + (ray / (RAYS - 1)) * FOV
    local raw_distance, side = cast_ray(ray_angle)
    local corrected = raw_distance * math.cos(player_angle - ray_angle)
    if corrected < 1 then corrected = 1 end

    local wall_height = (TILE * VIEW_H) / corrected
    if wall_height > VIEW_H then wall_height = VIEW_H end
    local top = (VIEW_H - wall_height) / 2
    local color = side == 0 and 5 or 6
    if corrected > TILE * 4 then color = 4 end
    ui.rectfill(ray * SLICE_W, top, (ray + 1) * SLICE_W + 1, top + wall_height, color)
  end
end

local function draw_hud()
  ui.rectfill(0, VIEW_H, SCREEN_W, SCREEN_H, 0)
  ui.print("MAZESTEIN 3D", 8, 256, 7)
  ui.print("W/S MOVER  A/D GIRAR", 350, 256, 7)
end

function update()
  frames = frames + 1
  if ui.btn("UP") then move_player(1) end
  if ui.btn("DOWN") then move_player(-1) end
  if ui.btn("LEFT") then player_angle = player_angle - TURN_SPEED end
  if ui.btn("RIGHT") then player_angle = player_angle + TURN_SPEED end
  draw_world()
  draw_hud()
end
