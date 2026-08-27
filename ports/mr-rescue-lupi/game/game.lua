require("palette")
require("sprites")

local Profile = require("profile")
local PortMode = require("port_mode")
local Audio = require("audio")
local Campaign = require("campaign")
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
local splash_left = Sprites.find("assets/splash_left")
local splash_right = Sprites.find("assets/splash_right")
local howto_left = Sprites.find("assets/howto_left")
local howto_right = Sprites.find("assets/howto_right")
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
local menu_labels = {
  "START GAME", "HOW TO PLAY", "HIGHSCORES", "OPTIONS", "HISTORY", "EXIT",
}
local building_names = {
  "SMALL BUSINESS", "APARTMENT COMPLEX", "BIG CORPORATION",
}
local difficulty_names = { "EASY", "NORMAL", "HARD" }
local statistic_names = {
  "FIRES EXTINGUISHED", "WATER USED", "DISTANCE MOVED",
  "PEOPLE RESCUED", "PROPERTY DAMAGE", "FLOORS SCALED",
}
local statistic_units = { "", " LITERS", " METERS", "", " $", "" }
local keyboard = "ABCDEFGHIJKLMNOPQRSTUVWXYZ_-<&"
local boss_sections = { 8, 11, 15 }
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
local highscore_rank = 0
local name_selection = 1
local name_position = 1
local name_entry = "_____"
local failure_message = "YOUR SUIT OVERHEATED!"

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
    local track = normal_music[(campaign_section - 1) % #normal_music + 1]
    sfx.music(track)
  end
  music_state = "play"
end

local function loadSection(first_section)
  local internal_section = PortMode.auto_start and PortMode.section or
                           campaign_section + (difficulty - 1) * 5
  local boss_kind = PortMode.boss_kind
  if not PortMode.auto_start and campaign_section == boss_sections[difficulty] then
    boss_kind = difficulty
  end
  local seed = PortMode.auto_start and 0x4D52534B or
               0x4D52534B + campaign_section * 977 + difficulty * 131
  World.reset(seed, internal_section, boss_kind)
  if PortMode.all_enemies then World.addCertificationEnemies() end
  local start_x, start_y = World.startPosition()
  if first_section then
    Player.reset(start_x, start_y)
    Player.setDifficulty(difficulty)
    if PortMode.boss_victory then Player.maximum_temperature = 100 end
  else
    Player.warp(start_x, start_y)
  end
  if PortMode.auto_start and not PortMode.boss_kind then
    World.addCertificationHuman(Player.x - 20, Player.y)
    World.addCertificationRescue(Player.y)
    World.addCertificationBurningHuman(Player.x + 80, Player.y)
    World.addCertificationScoringTarget(Player.x - 36, Player.y - 40)
  end
  frames = 0
  if first_section and not PortMode.auto_start then
    sfx.music()
    music_state = "stopped"
    state = STATE_COUNTDOWN
  else
    playLevelMusic(boss_kind)
    state = STATE_PLAY
  end
end

local function beginGame()
  campaign_section = 1
  campaign_casualties = 0
  maximum_casualties = 6 - difficulty
  Campaign.reset()
  if PortMode.seed_sweep and PortMode.seed_sweep > 0 then
    World.certificationSeedSweep(PortMode.seed_sweep)
  end
  loadSection(true)
end

local function updateTitle()
  if Input.start_pressed then enterMenu() end
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
  elseif menu_selection == 2 then
    state = STATE_HOWTO
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
  if Input.jump_pressed or Input.rescue_pressed or Input.pause_pressed then enterMenu() end
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
  if Input.rescue_pressed or Input.pause_pressed then enterMenu() end
end

local function enterSummary()
  Campaign.finalize()
  state = STATE_SUMMARY
  sfx.music()
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
  end
  Player.update()
  World.update(Player)
  if PortMode.boss_victory then World.clearCertificationHazards() end
  Campaign.updatePlayer(Player)
  Campaign.consumeWorld(World)
  frames = frames + 1

  if campaign_casualties + World.casualtyCount() >= maximum_casualties and
     not Player.dead then
    Player.temperature = Player.maximum_temperature
    failure_message = "TOO MANY CIVILIANS HAVE DIED!"
  end

  if Player.failed then
    state = STATE_FAILED
    frames = 0
    sfx.music()
    music_state = "stopped"
  elseif World.bossDefeated() then
    Campaign.floorCleared(false)
    state = STATE_WON
    frames = 0
    sfx.music("music/victory.ogg")
    music_state = "clear"
  elseif not World.isBossBattle() and Player.y < 0 then
    local missed = World.humanCount()
    campaign_casualties = campaign_casualties + World.casualtyCount() + missed
    Campaign.floorCleared(campaign_casualties < maximum_casualties)
    if campaign_casualties >= maximum_casualties then
      failure_message = "TOO MANY CIVILIANS HAVE DIED!"
      state = STATE_FAILED
      sfx.music()
      music_state = "stopped"
    else
      campaign_section = campaign_section + 1
      state = STATE_PRESCREEN
    end
    frames = 0
  elseif Player.y > Profile.map_height * 16 + 32 then
    Player.warp(World.startPosition())
  end
end

local function updatePrescreen()
  if Input.start_pressed then
    Audio.play("confirm")
    loadSection(false)
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
  frames = frames + 1
  if frames > 30 and Input.start_pressed then enterSummary() end
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
  drawOriginalScreen(splash_left, splash_right)
  if frames % 96 < 48 then ui.print("PRESS START", 262, 175, COLOR_PAPER) end
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
  ui.print("FLOORS: " .. ({ 21, 30, 42 })[difficulty], 35, 134, COLOR_PAPER)
  ui.print("MISSES: " .. (6 - difficulty), 35, 157, COLOR_PAPER)
  local name, best = Campaign.highscore(difficulty, 1)
  if name then ui.print("BEST: " .. best, 35, 179, COLOR_GREEN) end
  ui.print("Z START   E BACK", 35, 198, COLOR_BLUE)
end

local function drawHowto()
  ui.cls(COLOR_BLACK)
  drawOriginalScreen(howto_left, howto_right)
  ui.print("Z/E: BACK", 405, 258, COLOR_PAPER)
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
  ui.print("E/START: BACK", 194, 214, COLOR_BLUE)
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
    ui.print(Campaign.award(index), 316, y + 34, COLOR_RED)
  end
  ui.print("LEFT/RIGHT PAGE   E BACK", 154, 238, COLOR_BLUE)
end

local function drawHud()
  ui.rectfill(0, 0, 479, 13, COLOR_INK)
  ui.print("SCORE", 4, 3, COLOR_GREEN)
  ui.print(tostring(Campaign.score), 39, 3, COLOR_PAPER)
  ui.print("FIRE", 92, 3, COLOR_RED)
  ui.print(tostring(World.fireCount()), 121, 3, COLOR_PAPER)
  ui.print("WATER", 143, 3, COLOR_BLUE)
  ui.rect(179, 3, 235, 10, COLOR_PAPER)
  local water_end = 180 + math.floor(Player.water * 54 / Player.water_capacity)
  if water_end >= 180 then ui.rectfill(180, 4, water_end, 9, COLOR_BLUE) end
  ui.print("TEMP", 244, 3, COLOR_RED)
  ui.rect(274, 3, 330, 10, COLOR_PAPER)
  local heat_end = 275 + math.floor(
    Player.temperature * 54 / Player.maximum_temperature
  )
  if heat_end >= 275 then ui.rectfill(275, 4, heat_end, 9, COLOR_RED) end
  ui.print("LOST", 339, 3, COLOR_RED)
  ui.print(tostring(campaign_casualties + World.casualtyCount()), 368, 3, COLOR_PAPER)
  ui.print("E: PICK/THROW", 390, 3, COLOR_PAPER)
end

local function drawPlay()
  ui.cls(COLOR_BLACK)
  local camera_x = Player.cameraX()
  World.draw(camera_x, 14)
  Player.draw(camera_x, 14, COLOR_BLUE)
  World.drawWarnings(camera_x, 14, frames)
  drawHud()
end

local function drawPrescreen()
  ui.cls(COLOR_INK)
  ui.rect(72, 48, 407, 221, COLOR_PAPER)
  ui.tile(captain_sprites[math.floor(frames / 20) % 2 + 1], 0, 140, 90)
  local floor = campaign_section * 3 - 2
  if campaign_section == boss_sections[difficulty] then
    ui.print("ROOF", 222, 70, COLOR_RED)
    ui.print(({ "WATCH OUT: MR. MAGMA HULK!", "WATCH OUT: MR. GAS LEAK!",
                "WATCH OUT: MR. CHARCOAL!" })[difficulty], 143, 116, COLOR_RED)
  else
    ui.print("FLOOR " .. floor .. "-" .. (floor + 2), 199, 70, COLOR_RED)
    ui.print("KEEP UP THE GOOD WORK, BUDDY!", 143, 116, COLOR_BLUE)
  end
  ui.print("CASUALTIES: " .. campaign_casualties .. "/" .. maximum_casualties,
           170, 145, COLOR_RED)
  ui.print("PRESS Z OR START", 190, 194, COLOR_PAPER)
end

local function drawWon()
  drawPlay()
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
  ui.print(failure_message, 133, 107, COLOR_RED)
  ui.print("GAME OVER", 204, 132, COLOR_INK)
  ui.print("PRESS Z TO CONTINUE", 181, 162, COLOR_INK)
end

local function drawCountdown()
  drawPlay()
  local seconds = math.max(1, 4 - math.floor(frames / 60))
  ui.rectfill(211, 103, 268, 166, COLOR_BLACK)
  ui.rect(211, 103, 268, 166, COLOR_PAPER)
  ui.print(tostring(seconds), 234, 127, COLOR_RED)
end

local function drawPause()
  drawPlay()
  ui.rectfill(0, 0, 479, 269, COLOR_BLACK)
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
    updateTerminalScreen()
    drawWon()
  elseif state == STATE_PRESCREEN then
    updatePrescreen()
    drawPrescreen()
  elseif state == STATE_PAUSE then
    updatePause()
    drawPause()
  elseif state == STATE_COUNTDOWN then
    updateCountdown()
    drawCountdown()
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
