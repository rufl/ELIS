-- Hard limits for the Lupi port. Arrays are allocated once and never grow.
local Profile = {
  width = 480,
  height = 270,
  update_hz = 60,
  dt = 1 / 60,
  map_width = 41,
  map_height = 16,
  tile_size = 16,
  fire_max = 630,
  human_max = 18,
  enemy_max = 18,
  item_max = 8,
  door_max = 12,
  projectile_max = 72,
  particle_max = 96,
  room_max = 9,
  generated_human_max = 18,
  generated_enemy_max = 18,
  generated_door_max = 12,
  generated_item_count = 3,
  lua_heap_bytes_max = 4 * 1024 * 1024,
  flash_bytes_max = 16 * 1024 * 1024,
}

assert(Profile.map_width * Profile.map_height == 656)
assert(Profile.fire_max == 35 * 18)
assert(Profile.human_max <= 18)
assert(Profile.enemy_max <= 18)
assert(Profile.item_max >= Profile.generated_item_count)
assert(Profile.human_max >= Profile.generated_human_max)
assert(Profile.enemy_max >= Profile.generated_enemy_max)
assert(Profile.door_max >= Profile.generated_door_max)
assert(Profile.room_max == 9)

return Profile
