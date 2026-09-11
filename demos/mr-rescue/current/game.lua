require("palette")
require("sprites")

local Profile = require("profile")
local PortMode = require("port_mode")
local Audio = require("audio")
local Campaign = require("campaign")
local Progression = require("progression")
local Input = require("input")
local World = require("world")
local Player = require("player")

local COLOR_BLACK = Palette.hex(0x000000)
local COLOR_INK = Palette.hex(0x242424)
local COLOR_PAPER = Palette.hex(0xF4E6C1)
local COLOR_RED = Palette.hex(0xE84035)
local COLOR_BLUE = Palette.hex(0x52B7D8)
local COLOR_GREEN = Palette.hex(0x70C15A)
local STATE_TITLE = 1
local STATE_MENU = 2
local STATE_LEVEL = 3
local STATE_HOWTO = 4
local STATE_HIGHSCORES = 5
local STATE_OPTIONS = 6
local STATE_HISTORY = 7
local STATE_PLAY = 8
local STATE_WON = 9
local STATE_FAILED = 10
local STATE_PRESCREEN = 11
local STATE_PAUSE = 12
local STATE_SUMMARY = 13
local STATE_HIGHSCORE_ENTRY = 14
local STATE_COUNTDOWN = 15
local STATE_TRANSITION_OUT = 16
local STATE_COUNTDOWN_IN = 17
local STATE_TRANSITION_IN = 18
local splash_left = Sprites.find("assets/splash_left")
local splash_right = Sprites.find("assets/splash_right")
local tangram_left = Sprites.find("assets/tangram_left")
local tangram_right = Sprites.find("assets/tangram_right")
local love_left = Sprites.find("assets/love_left")
local love_right = Sprites.find("assets/love_right")
local howto_sprites = {}
for slide = 0, 8 do
  howto_sprites[slide + 1] = {
    Sprites.find("assets/howto_" .. slide .. "_left"),
    Sprites.find("assets/howto_" .. slide .. "_right"),
  }
end
local level_buildings = Sprites.find("assets/level_buildings")
local building_outlines = {
  Sprites.find("assets/building_outline_1"),
  Sprites.find("assets/building_outline_2"),
  Sprites.find("assets/building_outline_3"),
}
local captain_sprites = {
  Sprites.find("assets/captain_0"), Sprites.find("assets/captain_1"),
}
local captain_sad_sprites = {
  Sprites.find("assets/captain_sad_0"), Sprites.find("assets/captain_sad_1"),
}
local highscore_panes = {
  Sprites.find("assets/highscore_pane_1"),
  Sprites.find("assets/highscore_pane_2"),
  Sprites.find("assets/highscore_pane_3"),
}
local stats_left = Sprites.find("assets/stats_screen_left")
local stats_right = Sprites.find("assets/stats_screen_right")
local stats_panes = {
  Sprites.find("assets/stats_pane_1"),
  Sprites.find("assets/stats_pane_2"),
  Sprites.find("assets/stats_pane_3"),
}
local countdown_sprites = {
  Sprites.find("assets/countdown_0"), Sprites.find("assets/countdown_1"),
  Sprites.find("assets/countdown_2"), Sprites.find("assets/countdown_3"),
}
local hud_sprite = Sprites.find("assets/hud")
local hud_front_sprite = Sprites.find("assets/hud_front")
local hud_person_lost = Sprites.find("assets/hud_person_lost")
local hud_person_safe = Sprites.find("assets/hud_person_safe")
local item_slot_sprites = {
  Sprites.find("assets/item_slot_regen"),
  Sprites.find("assets/item_slot_tank"),
  Sprites.find("assets/item_slot_suit"),
}
local red_hit_sprite = Sprites.find("assets/red_hit")
local water_bar_sprite = Sprites.find("assets/water_bar")
local reserve_bar_sprite = Sprites.find("assets/reserve_bar")
local overloaded_bar_sprite = Sprites.find("assets/overloaded_bar")
local temperature_bar_sprite = Sprites.find("assets/temperature_bar")
local temperature_blink_sprite = Sprites.find("assets/temperature_blink")
local circle_sprites = {}
for frame = 0, 6 do
  circle_sprites[frame + 1] = Sprites.find("assets/circle_" .. frame)
end
local award_sprites = {}
for statistic = 1, 6 do
  award_sprites[statistic] = {
    NONE = Sprites.find("assets/award_" .. statistic .. "_none"),
    BRONZE = Sprites.find("assets/award_" .. statistic .. "_bronze"),
    SILVER = Sprites.find("assets/award_" .. statistic .. "_silver"),
    GOLD = Sprites.find("assets/award_" .. statistic .. "_gold"),
  }
end
local menu_labels = {
  "START GAME", "HOW TO PLAY", "HIGHSCORES", "OPTIONS", "HISTORY", "EXIT",
}
local building_names = {
  "SMALL BUSINESS", "APARTMENT COMPLEX", "BIG CORPORATION",
}
local difficulty_names = { "EASY", "NORMAL", "HARD" }
local no_casualty_messages = {
  { "REMEMBER: YOUR JOB IS TO RESCUE PEOPLE.", "NOT TO PUT OUT FIRE!" },
  { "KEEP UP THE GOOD WORK, BUDDY!", "YOU'RE ON FIRE. HE HE HE" },
  { "REMEMBER TO SCOUT FOR POWERUPS.", "THEY WILL COME IN HANDY LATER." },
  { "SAVE WATER OPENING DOORS:", "TRY THROWING PEOPLE AT THEM." },
  { "RESCUE 3 PEOPLE QUICKLY", "TO EARN A COMBO BONUS." },
  { "COLLECTING COOLANT IS ESSENTIAL", "FOR YOUR SURVIVAL." },
}
local boss_messages = {
  { "WATCH OUT, MR. RESCUE!", "IT'S THE EVIL MR. MAGMA HULK!" },
  { "WATCH OUT, MR. RESCUE!", "IT'S THE VICIOUS MR. GAS LEAK!" },
  { "WATCH OUT, MR. RESCUE!", "IT'S THE MALICIOUS MR. CHARCOAL!" },
}
local statistic_names = {
  "FIRES EXTINGUISHED", "WATER USED", "DISTANCE MOVED",
  "PEOPLE RESCUED", "PROPERTY DAMAGE", "FLOORS SCALED",
}
local statistic_units = { "", " LITERS", " METERS", "", " $", "" }
local keyboard = "ABCDEFGHIJKLMNOPQRSTUVWXYZ_-<&"
local normal_music = {
  "music/rockerronni.ogg", "music/bundesliga.ogg", "music/scooterfest.ogg",
}
local state = STATE_TITLE
local frames = 0
local music_state = "title"
local menu_selection = 1
local difficulty = 1
local campaign_section = 1
local campaign_casualties = 0
local maximum_casualties = 5
local pause_selection = 1
local highscore_page = 1
local history_page = 1
local howto_slide = 0
local highscore_rank = 0
local name_selection = 1
local name_position = 1
local name_entry = "_____"
local failure_message = "YOUR SUIT OVERHEATED!"
local family_presentation = PortMode.family_presentation or false
local transition_outcome = 0
local normal_music_index = 1
local last_missed = 0
local last_logged_state = 0
local last_logged_howto = -1
local last_logged_menu_detail = ""

assert(_VERSION == "Lua 5.4")
assert(ui.stat(0) < Profile.lua_heap_bytes_max)
sfx.music("music/opening.ogg")

local function drawOriginalScreen(left, right)
  ui.tile(left, 0, 112, 35)
  ui.tile(right, 0, 240, 35)
end

local function enterMenu()
  state = STATE_MENU
  menu_selection = 1
  if music_state ~= "title" then
    sfx.music("music/opening.ogg")
    music_state = "title"
  end
end

local function playLevelMusic(boss_kind)
  if boss_kind then
    sfx.music("music/roof.ogg")
  else
    sfx.music(normal_music[normal_music_index])
  end
  music_state = "play"
end

local function loadSection(first_section, fade_in)
  local internal_section = PortMode.auto_start and PortMode.section or
                           Progression.internalSection(campaign_section, difficulty)
  local boss_kind = PortMode.boss_kind
  if not PortMode.auto_start and Progression.isBoss(campaign_section, difficulty) then
    boss_kind = difficulty
  end
  local seed = PortMode.auto_start and 0x4D52534B or
               0x4D52534B + campaign_section * 977 + difficulty * 131
  World.reset(seed, internal_section, boss_kind)
  if PortMode.player_trace or PortMode.section_exit_probe then
    World.preparePlayerTrace()
  end
  if PortMode.all_enemies then World.addCertificationEnemies() end
  local start_x, start_y = World.startPosition()
  if first_section then
    Player.reset(start_x, start_y)
    Player.setDifficulty(difficulty)
    if PortMode.boss_victory then Player.maximum_temperature = 100 end
    if PortMode.failure_probe then Player.temperature = Player.maximum_temperature end
    if PortMode.section_exit_probe then Player.y = -10 end
  else
    Player.warp(start_x, start_y)
  end
  if PortMode.auto_start and not PortMode.boss_kind and
     not PortMode.player_trace and not PortMode.interaction_probe and
     not PortMode.section_exit_probe then
    World.addCertificationHuman(Player.x - 10, Player.y)
    World.addCertificationRescue(Player.y)
    World.addCertificationBurningHuman(Player.x + 80, Player.y)
    World.addCertificationScoringTarget(Player.x - 36, Player.y - 40)
  end
  if PortMode.interaction_probe then
    World.certificationInteractionTrace(Player)
  end
  frames = 0
  if first_section and not PortMode.auto_start then
    sfx.music(-1)
    music_state = "stopped"
    state = STATE_COUNTDOWN_IN
  elseif fade_in then
    state = STATE_TRANSITION_IN
  else
    playLevelMusic(boss_kind)
    state = STATE_PLAY
  end
end

local function beginGame()
  campaign_section = 1
  campaign_casualties = 0
  last_missed = 0
  failure_message = "YOUR SUIT OVERHEATED!"
  maximum_casualties = Progression.maximumCasualties(difficulty)
  normal_music_index = (difficulty - 1) % #normal_music + 1
  Campaign.reset()
  if PortMode.capacity_probe then World.certificationCapacityBoundaries() end
  if PortMode.seed_sweep and PortMode.seed_sweep > 0 then
    World.certificationSeedSweep(PortMode.seed_sweep)
  end
  loadSection(true)
end

local function updateTitle()
  if Input.start_pressed or Input.rescue_pressed then enterMenu() end
end

local function updateMenu()
  if Input.down_pressed then
    menu_selection = menu_selection % #menu_labels + 1
    Audio.play("blip")
  end
  if Input.up_pressed then
    menu_selection = (menu_selection - 2) % #menu_labels + 1
    Audio.play("blip")
  end
  if not Input.jump_pressed then return end
  Audio.play("confirm")
  if menu_selection == 1 then
    state = STATE_LEVEL
    sfx.music("music/menujazz.ogg")
    music_state = "information"
  elseif menu_selection == 2 then
    howto_slide = 0
    state = STATE_HOWTO
    sfx.music("music/menujazz.ogg")
    music_state = "information"
  elseif menu_selection == 3 then
    highscore_page = 1
    state = STATE_HIGHSCORES
    sfx.music("music/happyfeerings.ogg")
    music_state = "scores"
  elseif menu_selection == 4 then
    state = STATE_OPTIONS
  elseif menu_selection == 5 then
    history_page = 1
    state = STATE_HISTORY
    sfx.music("music/happyfeerings.ogg")
    music_state = "scores"
  else
    state = STATE_TITLE
  end
end

local function updateLevel()
  if Input.right_pressed or Input.down_pressed then
    difficulty = difficulty % 3 + 1
    Audio.play("blip")
  end
  if Input.left_pressed or Input.up_pressed then
    difficulty = (difficulty - 2) % 3 + 1
    Audio.play("blip")
  end
  if Input.jump_pressed then
    Audio.play("confirm")
    beginGame()
  elseif Input.rescue_pressed then
    enterMenu()
  end
end

local function updateInformationScreen()
  if Input.right_pressed or Input.down_pressed then
    howto_slide = math.min(8, howto_slide + 1)
    Audio.play("blip")
  elseif Input.left_pressed or Input.up_pressed then
    howto_slide = math.max(0, howto_slide - 1)
    Audio.play("blip")
  elseif Input.jump_pressed then
    howto_slide = math.min(8, howto_slide + 1)
    Audio.play("blip")
  elseif Input.rescue_pressed or Input.pause_pressed then
    enterMenu()
  end
end

local function updateHighscores()
  if Input.right_pressed then
    highscore_page = highscore_page % 3 + 1
    Audio.play("blip")
  elseif Input.left_pressed then
    highscore_page = (highscore_page - 2) % 3 + 1
    Audio.play("blip")
  elseif Input.jump_pressed or Input.rescue_pressed or Input.pause_pressed then
    enterMenu()
  end
end

local function updateHistory()
  if Input.right_pressed then
    history_page = history_page % 3 + 1
    Audio.play("blip")
  elseif Input.left_pressed then
    history_page = (history_page - 2) % 3 + 1
    Audio.play("blip")
  elseif Input.rescue_pressed or Input.pause_pressed then
    enterMenu()
  end
end

local function updateOptions()
  if Input.left_pressed or Input.right_pressed or Input.jump_pressed then
    family_presentation = not family_presentation
    Audio.play("blip")
  elseif Input.rescue_pressed or Input.pause_pressed then
    enterMenu()
  end
end

local function enterSummary()
  Campaign.finalize()
  state = STATE_SUMMARY
  sfx.music(-1)
  music_state = "stopped"
end

local function updatePlay()
  if Input.pause_pressed and not PortMode.auto_start then
    pause_selection = 1
    state = STATE_PAUSE
    Audio.play("blip")
    return
  end
  if PortMode.boss_victory then
    Player.setCertificationPosition(World.certificationBossPlayerX())
    Player.setCertificationDirection(World.bossDirectionFrom(Player.x))
    Player.refillCertificationWater()
  end
  World.update(Player)
  if PortMode.boss_victory then World.clearCertificationHazards() end
  Player.update()
  Campaign.updatePlayer(Player)
  Campaign.consumeWorld(World)
  local popup = Campaign.consumePopup()
  while popup ~= 0 do
    World.addPopup(Player.x, Player.y - 24, popup)
    popup = Campaign.consumePopup()
  end

  if campaign_casualties + World.casualtyCount() >= maximum_casualties and
     not Player.dead then
    Player.temperature = Player.maximum_temperature
    failure_message = "TOO MANY CIVILIANS HAVE DIED!"
  end

  if Player.failed then
    transition_outcome = 2
    state = STATE_TRANSITION_OUT
    frames = 0
  elseif World.bossDefeated() then
    state = STATE_WON
    frames = 0
    sfx.music("music/victory.ogg")
    music_state = "clear"
  elseif not World.isBossBattle() and Player.y < 0 then
    transition_outcome = 1
    state = STATE_TRANSITION_OUT
    frames = 0
  elseif Player.y > Profile.map_height * 16 + 32 then
    transition_outcome = 3
    state = STATE_TRANSITION_OUT
    frames = 0
  end
end

local function updateTransitionOut()
  World.update(Player)
  Campaign.consumeWorld(World)
  if frames <= 80 then return end
  if transition_outcome == 1 then
    local missed = World.humanCount()
    last_missed = missed
    campaign_casualties = campaign_casualties + World.casualtyCount() + missed
    Campaign.floorCleared(campaign_casualties < maximum_casualties)
    if campaign_casualties >= maximum_casualties then
      failure_message = "TOO MANY CIVILIANS HAVE DIED!"
      state = STATE_FAILED
      sfx.music(-1)
      music_state = "stopped"
    else
      campaign_section = campaign_section + 1
      if Progression.isBoss(campaign_section, difficulty) then
        playLevelMusic(true)
      end
      state = STATE_PRESCREEN
    end
  elseif transition_outcome == 2 then
    state = STATE_FAILED
    sfx.music(-1)
    music_state = "stopped"
  else
    Player.warp(World.startPosition())
    state = STATE_TRANSITION_IN
  end
  frames = 0
end

local function updatePrescreen()
  if Input.left_pressed or Input.right_pressed then
    if not Progression.isBoss(campaign_section, difficulty) then
      if Input.left_pressed then
        normal_music_index = (normal_music_index - 2) % #normal_music + 1
      else
        normal_music_index = normal_music_index % #normal_music + 1
      end
      playLevelMusic(false)
      Audio.play("blip")
    end
  elseif Input.start_pressed then
    Audio.play("confirm")
    loadSection(false, true)
  end
end

local function updateTransitionIn()
  World.update(Player)
  Campaign.consumeWorld(World)
  if frames > 80 then
    state = STATE_PLAY
    frames = 0
  end
end

local function updateCountdownIn()
  World.update(Player)
  Campaign.consumeWorld(World)
  if frames > 80 then
    state = STATE_COUNTDOWN
    frames = 0
    Audio.play("confirm")
  end
end

local function updateCountdown()
  World.update(Player)
  Campaign.consumeWorld(World)
  if frames >= 210 then
    playLevelMusic(World.isBossBattle())
    state = STATE_PLAY
    frames = 0
  end
end

local function updatePause()
  if Input.down_pressed or Input.up_pressed then
    pause_selection = pause_selection == 1 and 2 or 1
    Audio.play("blip")
  end
  if Input.rescue_pressed or Input.pause_pressed then
    state = STATE_PLAY
    Audio.play("blip")
  elseif Input.jump_pressed then
    Audio.play("confirm")
    if pause_selection == 1 then state = STATE_PLAY else enterMenu() end
  end
end

local function updateTerminalScreen()
  if frames > 30 and Input.start_pressed then enterSummary() end
end

local function updateWon()
  World.update(Player)
  Campaign.consumeWorld(World)
  if frames > 1 and Input.start_pressed then enterSummary() end
end

local function beginHighscoreEntry()
  highscore_rank = Campaign.highscoreRank(difficulty)
  if highscore_rank == 0 then
    highscore_page = difficulty
    state = STATE_HIGHSCORES
    return
  end
  name_selection = 1
  name_position = 1
  name_entry = "_____"
  state = STATE_HIGHSCORE_ENTRY
end

local function updateSummary()
  if Input.start_pressed or Input.rescue_pressed then beginHighscoreEntry() end
end

local function replaceNameCharacter(character)
  local head = name_entry:sub(1, name_position - 1)
  local tail = name_entry:sub(name_position + 1, 5)
  name_entry = head .. character .. tail
  name_position = math.min(6, name_position + 1)
  Audio.play("confirm")
end

local function deleteNameCharacter()
  name_position = math.max(1, name_position - 1)
  local head = name_entry:sub(1, name_position - 1)
  name_entry = head .. string.rep("_", 6 - name_position)
  Audio.play("blip")
end

local function confirmHighscore()
  Campaign.addHighscore(difficulty, highscore_rank, name_entry:gsub("_", " "))
  highscore_page = difficulty
  state = STATE_HIGHSCORES
  sfx.music("music/happyfeerings.ogg")
  music_state = "scores"
  Audio.play("confirm")
end

local function updateHighscoreEntry()
  if Input.right_pressed then
    name_selection = name_selection % 10 == 0 and name_selection - 9 or
                     name_selection + 1
    Audio.play("blip")
  elseif Input.left_pressed then
    name_selection = name_selection % 10 == 1 and name_selection + 9 or
                     name_selection - 1
    Audio.play("blip")
  elseif Input.down_pressed then
    name_selection = name_selection >= 21 and name_selection - 20 or
                     name_selection + 10
    Audio.play("blip")
  elseif Input.up_pressed then
    name_selection = name_selection <= 10 and name_selection + 20 or
                     name_selection - 10
    Audio.play("blip")
  elseif Input.rescue_pressed then
    deleteNameCharacter()
  elseif Input.pause_pressed then
    confirmHighscore()
  elseif Input.jump_pressed then
    if name_selection <= 28 and name_position <= 5 then
      replaceNameCharacter(keyboard:sub(name_selection, name_selection))
    elseif name_selection == 29 then
      deleteNameCharacter()
    elseif name_selection == 30 then
      confirmHighscore()
    end
  end
end

local function drawTitle()
  ui.cls(COLOR_BLACK)
  if frames <= 240 then
    drawOriginalScreen(tangram_left, tangram_right)
  elseif frames <= 480 then
    drawOriginalScreen(love_left, love_right)
  else
    drawOriginalScreen(splash_left, splash_right)
    if frames > 600 and frames % 96 < 48 then
      ui.print("PRESS START", 262, 175, COLOR_PAPER)
    end
  end
end

local function drawMenu()
  ui.cls(COLOR_BLACK)
  drawOriginalScreen(splash_left, splash_right)
  for index, label in ipairs(menu_labels) do
    local y = 121 + index * 13
    if index == menu_selection then ui.print(">", 256, y, COLOR_RED) end
    ui.print(label, 266, y, COLOR_PAPER)
  end
end

local function drawLevel()
  ui.cls(COLOR_INK)
  ui.print("PLEASE SELECT A LEVEL", 176, 18, COLOR_PAPER)
  ui.tile(level_buildings, 0, 228, 55)
  local outline = building_outlines[difficulty]
  local outline_x = ({ 250, 304, 268 })[difficulty]
  local outline_y = ({ 142, 129, 64 })[difficulty]
  ui.tile(outline, 0, outline_x, outline_y)
  ui.rect(22, 68, 206, 211, COLOR_PAPER)
  ui.print(building_names[difficulty], 35, 86, COLOR_PAPER)
  ui.print("DIFFICULTY: " .. difficulty_names[difficulty], 35, 111, COLOR_RED)
  ui.print("FLOORS: " .. Progression.floorCount(difficulty), 35, 134, COLOR_PAPER)
  ui.print("MISSES: " .. Progression.maximumCasualties(difficulty),
           35, 157, COLOR_PAPER)
  local name, best = Campaign.highscore(difficulty, 1)
  if name then ui.print("BEST: " .. best, 35, 179, COLOR_GREEN) end
  ui.print("Z START   E BACK", 35, 198, COLOR_BLUE)
end

local function drawHowto()
  ui.cls(COLOR_BLACK)
  local sprites = howto_sprites[howto_slide + 1]
  drawOriginalScreen(sprites[1], sprites[2])
  ui.print((howto_slide + 1) .. "/9  ARROWS/Z: NEXT  E: BACK",
           260, 258, COLOR_PAPER)
end

local function drawHighscores()
  ui.cls(COLOR_INK)
  ui.tile(highscore_panes[highscore_page], 0, 112, 34)
  ui.print("HIGHSCORES - " .. difficulty_names[highscore_page], 170, 24, COLOR_RED)
  for rank = 1, 10 do
    local name, score = Campaign.highscore(highscore_page, rank)
    local y = 44 + rank * 18
    ui.print((rank < 10 and " " or "") .. rank .. ".", 118, y, COLOR_PAPER)
    ui.print(name or "---", 158, y, COLOR_PAPER)
    if name then ui.print(tostring(score), 286, y, COLOR_GREEN) end
  end
  ui.print("LEFT/RIGHT PAGE   Z/E BACK", 143, 250, COLOR_BLUE)
end

local function drawOptions()
  ui.cls(COLOR_INK)
  ui.print("OPTIONS", 219, 52, COLOR_RED)
  ui.print("DISPLAY SCALE: ELIS HOST", 157, 94, COLOR_PAPER)
  ui.print("FULLSCREEN/VSYNC: ELIS HOST", 145, 117, COLOR_PAPER)
  ui.print("SOUND/MUSIC: PHYSICAL PROFILE", 137, 140, COLOR_PAPER)
  ui.print("CLASSIC GAMEPLAY: ON", 164, 169, COLOR_GREEN)
  ui.print("FAMILY PRESENTATION: " .. (family_presentation and "ON" or "OFF"),
           145, 190, family_presentation and COLOR_GREEN or COLOR_PAPER)
  ui.print("LEFT/RIGHT/Z TOGGLE   E BACK", 137, 224, COLOR_BLUE)
end

local function drawHistory()
  ui.cls(COLOR_INK)
  ui.tile(stats_left, 0, 112, 35)
  ui.tile(stats_right, 0, 240, 35)
  ui.tile(stats_panes[history_page], 0, 170, 83)
  ui.print("STATS " .. history_page .. "/3", 211, 28, COLOR_RED)
  for row = 1, 2 do
    local index = row + (history_page - 1) * 2
    local y = 66 + (row - 1) * 82
    ui.rect(84, y, 395, y + 62, COLOR_PAPER)
    ui.print(statistic_names[index], 105, y + 11, COLOR_PAPER)
    ui.print(math.floor(Campaign.statistics[index]) .. statistic_units[index],
             105, y + 34, COLOR_GREEN)
    local award = Campaign.award(index)
    ui.tile(award_sprites[index][award], 0, 316, y + 24)
    ui.print(award, 346, y + 34, COLOR_RED)
  end
  ui.print("LEFT/RIGHT PAGE   E BACK", 154, 238, COLOR_BLUE)
end

local function drawHud()
  local hud_x = 112
  local hud_y = Profile.stage_height
  ui.tile(hud_sprite, 0, hud_x, hud_y)

  local water_width = math.floor(Player.water * 55 / Player.water_capacity + 0.5)
  local water_sprite = water_bar_sprite
  if Player.overloaded then
    water_sprite = overloaded_bar_sprite
  elseif Player.has_reserve then
    water_sprite = reserve_bar_sprite
  end
  ui.tile(water_sprite, water_width, hud_x + 10, hud_y + 10)

  local temperature_width = math.floor(
    Player.temperature * 82 / Player.maximum_temperature + 0.5
  )
  ui.tile(temperature_bar_sprite, temperature_width, hud_x + 75, hud_y + 7)
  if Player.temperature > Player.maximum_temperature * 0.75 and
     frames % 60 < 30 then
    ui.tile(temperature_blink_sprite, 0, hud_x + 74, hud_y + 6)
  end

  local casualties = campaign_casualties + World.casualtyCount()
  for index = 1, maximum_casualties do
    local person = index <= casualties and hud_person_lost or hud_person_safe
    ui.tile(person, 0, hud_x + 168 + (index - 1) * 5, hud_y + 7)
  end
  ui.tile(hud_front_sprite, 0, hud_x, hud_y)

  for index = 1, 3 do
    if index <= Player.regeneration_count then
      ui.tile(item_slot_sprites[1], 0, hud_x + 78 + (index - 1) * 6, hud_y + 18)
    end
    if index <= Player.tank_count then
      ui.tile(item_slot_sprites[2], 0, hud_x + 100 + (index - 1) * 6, hud_y + 18)
    end
    if index <= Player.suit_count then
      ui.tile(item_slot_sprites[3], 0, hud_x + 122 + (index - 1) * 6, hud_y + 18)
    end
  end
  ui.print("SCORE: " .. Campaign.score, hud_x + 150, hud_y + 19, COLOR_INK)
  ui.print("SCORE: " .. Campaign.score, hud_x + 150, hud_y + 18, COLOR_PAPER)
end

local function drawPlay(world_offset, hide_boss_hud)
  ui.cls(COLOR_BLACK)
  ui.clip(0, 0, Profile.width, Profile.stage_height)
  local camera_x = Player.cameraX()
  local origin_y = -Player.cameraY() + (world_offset or 0)
  World.draw(camera_x, origin_y, family_presentation)
  Player.draw(camera_x, origin_y, COLOR_BLUE)
  World.draw(camera_x, origin_y, family_presentation, "front")
  if not World.isBossBattle() then
    World.drawLighting(camera_x, origin_y, Player.x, Player.y)
  end
  if Player.heat > 0 and (not family_presentation or frames % 4 < 2) then
    ui.tile(red_hit_sprite, 0, 112, 14)
  end
  World.drawWarnings(camera_x, origin_y, frames, family_presentation)
  if not hide_boss_hud then World.drawBossHud() end
  ui.clip()
  drawHud()
end

local function drawPrescreen()
  ui.cls(COLOR_INK)
  ui.rect(72, 48, 407, 221, COLOR_PAPER)
  ui.tile(captain_sprites[math.floor(frames / 20) % 2 + 1], 0, 140, 101)
  local floor, floor_end = Progression.floorRange(campaign_section)
  local message
  if Progression.isBoss(campaign_section, difficulty) then
    ui.print("ROOF", 222, 68, COLOR_RED)
    message = boss_messages[difficulty]
  elseif last_missed == 1 then
    ui.print("FLOOR " .. floor .. "-" .. floor_end, 199, 68, COLOR_RED)
    message = { "HEY THERE, BUDDY!", "YOU MISSED 1 PERSON. TRY HARDER." }
  elseif last_missed > 1 then
    ui.print("FLOOR " .. floor .. "-" .. floor_end, 199, 68, COLOR_RED)
    if family_presentation then
      message = { "HEY THERE, BUDDY!", "YOU MISSED " .. last_missed .. " PEOPLE. TRY HARDER." }
    else
      message = { "HEY THERE, BUDDY!", "YOU LET " .. last_missed .. " PEOPLE BURN TO DEATH.",
                  "TRY A LITTLE HARDER." }
    end
  else
    ui.print("FLOOR " .. floor .. "-" .. floor_end, 199, 68, COLOR_RED)
    message = no_casualty_messages[(campaign_section - 2) % #no_casualty_messages + 1]
  end
  for index, line in ipairs(message) do
    ui.print(line, 205, 108 + (index - 1) * 14, index == 1 and COLOR_BLUE or COLOR_PAPER)
  end
  local outcome_label = family_presentation and "MISSED: " or "CASUALTIES: "
  ui.print(outcome_label .. campaign_casualties .. "/" .. maximum_casualties,
           205, 163, COLOR_RED)
  ui.print("PRESS Z OR START", 190, 198, COLOR_PAPER)
  if not Progression.isBoss(campaign_section, difficulty) then
    ui.print("LEFT/RIGHT: MUSIC", 183, 213, COLOR_BLUE)
  end
end

local function drawWon()
  local world_offset = math.min(270, math.floor(frames / 3))
  drawPlay(world_offset, true)
  ui.rectfill(78, 50, 401, 211, COLOR_BLACK)
  ui.rect(78, 50, 401, 211, COLOR_GREEN)
  ui.print("CONGRATULATIONS!", 180, 70, COLOR_GREEN)
  ui.print(({ "YOU HAVE BEATEN MR. MAGMA HULK", "YOU HAVE BEATEN MR. GAS LEAK",
              "YOU HAVE BEATEN MR. CHARCOAL" })[difficulty], 135, 102, COLOR_PAPER)
  ui.print("AND RESCUED THE " .. building_names[difficulty], 135, 126, COLOR_PAPER)
  ui.print("PRESS Z TO CONTINUE", 181, 176, COLOR_RED)
end

local function drawFailed()
  drawPlay()
  ui.rectfill(82, 76, 397, 190, COLOR_PAPER)
  ui.rect(82, 76, 397, 190, COLOR_RED)
  ui.tile(captain_sad_sprites[math.floor(frames / 20) % 2 + 1], 0, 140, 90)
  local message = failure_message
  if family_presentation and message == "TOO MANY CIVILIANS HAVE DIED!" then
    message = "TOO MANY CIVILIANS WERE MISSED!"
  end
  ui.print(message, math.floor((Profile.width - #message * 6) / 2), 151, COLOR_INK)
  ui.print("GAME OVER", 204, 132, COLOR_PAPER)
  ui.print("PRESS Z TO CONTINUE", 181, 174, COLOR_INK)
end

local function drawCountdown()
  drawPlay()
  local countdown_frame = math.min(3, math.floor(frames / 60))
  ui.tile(countdown_sprites[countdown_frame + 1], 0, 208, 122)
end

local function drawCountdownIn()
  drawPlay()
  local transition_frame = math.floor(frames / 4)
  for cell_y = 0, 8 do
    for cell_x = 0, 14 do
      local progress = math.max(0, math.min(6, transition_frame - 13 + cell_x + cell_y))
      ui.tile(circle_sprites[7 - progress], 0, cell_x * 32, cell_y * 32)
    end
  end
end

local function drawTransitionOut()
  drawPlay()
  local transition_frame = math.floor(frames / 4)
  for cell_y = 0, 8 do
    for cell_x = 0, 14 do
      local frame = math.max(0, math.min(6, transition_frame - 13 + cell_x + cell_y))
      ui.tile(circle_sprites[frame + 1], 0, cell_x * 32, cell_y * 32)
    end
  end
end

local function drawPause()
  ui.cls(COLOR_BLACK)
  ui.print("PAUSED", 219, 72, COLOR_PAPER)
  ui.print(pause_selection == 1 and "> RESUME" or "  RESUME", 195, 116, COLOR_GREEN)
  ui.print(pause_selection == 2 and "> QUIT" or "  QUIT", 195, 142, COLOR_RED)
end

local function drawSummary()
  ui.cls(COLOR_INK)
  ui.print("YOUR SCORE", 205, 36, COLOR_PAPER)
  ui.print(tostring(Campaign.score), 226, 55, COLOR_GREEN)
  ui.print("YOU SAVED " .. Campaign.saved .. " CIVILIANS", 174, 94, COLOR_PAPER)
  ui.print("LONGEST COMBO: " .. Campaign.maximum_combo, 180, 118, COLOR_PAPER)
  ui.print("TOTAL TIME: " .. Campaign.timeString(), 174, 142, COLOR_PAPER)
  ui.print("FLOORS CLEARED: " .. ((campaign_section - 1) * 3), 177, 166, COLOR_PAPER)
  ui.print("PRESS Z TO CONTINUE", 181, 218, COLOR_BLUE)
end

local function drawHighscoreEntry()
  ui.cls(COLOR_INK)
  ui.print("NEW HIGHSCORE!", 187, 24, COLOR_GREEN)
  ui.print("PLEASE ENTER YOUR NAME", 166, 43, COLOR_PAPER)
  local character = 1
  for row = 1, 3 do
    for column = 1, 10 do
      local x = 112 + column * 24
      local y = 64 + row * 30
      local color = character == name_selection and COLOR_RED or COLOR_PAPER
      ui.print(keyboard:sub(character, character), x, y, color)
      character = character + 1
    end
  end
  ui.print(name_entry, 211, 179, COLOR_GREEN)
  ui.print("Z SELECT  E DELETE  START CONFIRM", 126, 222, COLOR_BLUE)
end

function update(frame)
  ui.set_pallet(0, #Palette, Palette)
  Input.update()
  if PortMode.auto_start and state == STATE_TITLE then
    difficulty = PortMode.difficulty or PortMode.boss_kind or difficulty
    beginGame()
  end
  frames = frames + 1

  if state == STATE_TITLE then
    updateTitle()
    drawTitle()
  elseif state == STATE_MENU then
    updateMenu()
    drawMenu()
  elseif state == STATE_LEVEL then
    updateLevel()
    drawLevel()
  elseif state == STATE_HOWTO then
    updateInformationScreen()
    drawHowto()
  elseif state == STATE_HIGHSCORES then
    updateHighscores()
    drawHighscores()
  elseif state == STATE_OPTIONS then
    updateOptions()
    drawOptions()
  elseif state == STATE_HISTORY then
    updateHistory()
    drawHistory()
  elseif state == STATE_PLAY then
    updatePlay()
    drawPlay()
  elseif state == STATE_WON then
    updateWon()
    drawWon()
  elseif state == STATE_PRESCREEN then
    updatePrescreen()
    drawPrescreen()
  elseif state == STATE_PAUSE then
    updatePause()
    drawPause()
  elseif state == STATE_COUNTDOWN_IN then
    updateCountdownIn()
    drawCountdownIn()
  elseif state == STATE_COUNTDOWN then
    updateCountdown()
    drawCountdown()
  elseif state == STATE_TRANSITION_IN then
    updateTransitionIn()
    drawCountdownIn()
  elseif state == STATE_TRANSITION_OUT then
    updateTransitionOut()
    drawTransitionOut()
  elseif state == STATE_SUMMARY then
    updateSummary()
    drawSummary()
  elseif state == STATE_HIGHSCORE_ENTRY then
    updateHighscoreEntry()
    drawHighscoreEntry()
  else
    updateTerminalScreen()
    drawFailed()
  end

  if PortMode.player_trace and
     (frame == 1 or frame == 20 or frame == 40 or frame == 60 or
      frame == 80 or frame == 100 or frame == 120) then
    ui.log(
      "MR_RESCUE_PLAYER_TRACE FRAME=" .. frame ..
      " X=" .. string.format("%.4f", Player.x) ..
      " Y=" .. string.format("%.4f", Player.y) ..
      " SX=" .. string.format("%.4f", Player.speed_x) ..
      " SY=" .. string.format("%.4f", Player.speed_y) ..
      " WATER=" .. string.format("%.2f", Player.water) ..
      " SPRAY=" .. tostring(Player.spraying)
    )
  end

  if PortMode.menu_probe then
    local menu_detail = ""
    if state == STATE_OPTIONS then
      menu_detail = "OPTIONS FAMILY=" .. tostring(family_presentation)
    elseif state == STATE_HISTORY then
      menu_detail = "HISTORY PAGE=" .. history_page
    elseif state == STATE_HIGHSCORES then
      menu_detail = "HIGHSCORES PAGE=" .. highscore_page
    end
    if menu_detail ~= "" and menu_detail ~= last_logged_menu_detail then
      last_logged_menu_detail = menu_detail
      ui.log("MR_RESCUE_MENU " .. menu_detail)
    end
  end

  if PortMode.tutorial_probe and state == STATE_HOWTO and
     howto_slide ~= last_logged_howto then
    last_logged_howto = howto_slide
    ui.log("MR_RESCUE_HOWTO SLIDE=" .. howto_slide)
  end

  if (PortMode.flow_probe or PortMode.failure_probe or PortMode.menu_probe or
      PortMode.section_exit_probe) and state ~= last_logged_state then
    last_logged_state = state
    ui.log(
      "MR_RESCUE_FLOW STATE=" .. state ..
      " SECTION=" .. campaign_section ..
      " FRAMES=" .. frames ..
      " TICK=" .. frame
    )
  end

  if frame % 60 == 0 then
    local lua_bytes = ui.stat(0)
    assert(lua_bytes < Profile.lua_heap_bytes_max)
    if PortMode.auto_start then
      World.logCertificationState()
      ui.log(
        "MR_RESCUE_LUA_BYTES=" .. math.floor(lua_bytes) ..
        " X=" .. math.floor(Player.x) ..
        " CARRY=" .. Player.carrying ..
        " SAFE=" .. World.rescuedCount() ..
        " SCORE=" .. Campaign.score
      )
    end
  end
end
