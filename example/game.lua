local Palette = {
  0x0000, 0x5905, 0x51A9, 0x18A8,
  0x75E7, 0x7AF1, 0x7FFF, 0x4929,
}
for i = 1, #Palette do
  ui.palset(i - 1, Palette[i])
end

local t = 0
local player_x = 240
local player_y = 135
function update()
  t = t + 0.05
  if ui.btn("LEFT") then player_x = player_x - 2 end
  if ui.btn("RIGHT") then player_x = player_x + 2 end
  if ui.btn("UP") then player_y = player_y - 2 end
  if ui.btn("DOWN") then player_y = player_y + 2 end
  ui.cls(0)
  ui.rectfill(22, 20, 436, 220, 1)
  ui.rect(22, 20, 436, 220, 7)
  ui.print("LUPI // EDICAO ZIG", 130, 42, 7)
  ui.print("A tiny Brazilian console simulator", 112, 60, 6)
  ui.line(70, 82, 410, 82, 5)
  ui.circfill(player_x, player_y + math.floor(math.sin(t) * 12), 28, 3)
  ui.trisfill(player_x - 70, 205, player_x, 105, player_x + 70, 205, 4)
  ui.print("WASD  MOVER", 175, 228, 7)
  if ui.btnp("BTN_Z") then ui.log("BTN_Z pressed") end
end
