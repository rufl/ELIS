local PortMode = require("port_mode")

local Input = {
  left = false,
  right = false,
  up = false,
  down = false,
  jump = false,
  spray = false,
  rescue = false,
  start = false,
  pause = false,
  jump_pressed = false,
  rescue_pressed = false,
  start_pressed = false,
  pause_pressed = false,
  left_pressed = false,
  right_pressed = false,
  up_pressed = false,
  down_pressed = false,
}

local left_was_down = false
local right_was_down = false
local up_was_down = false
local down_was_down = false
local jump_was_down = false
local rescue_was_down = false
local start_was_down = false
local pause_was_down = false
local smoke_frame = 0

function Input.update()
  Input.left = ui.btn(LEFT, 0)
  Input.right = ui.btn(RIGHT, 0)
  Input.up = ui.btn(UP, 0)
  Input.down = ui.btn(DOWN, 0)
  Input.jump = ui.btn(BTN_Z, 0)
  Input.spray = ui.btn(BTN_X, 0)
  Input.rescue = ui.btn(BTN_E, 0)
  Input.pause = ui.btn(BTN_START, 0)
  Input.start = Input.pause or Input.jump

  if PortMode.auto_start then
    smoke_frame = smoke_frame + 1
    Input.left = smoke_frame <= 260
    Input.right = false
    Input.up = false
    Input.down = false
    Input.jump = smoke_frame == 20
    Input.spray = smoke_frame >= 80 and smoke_frame <= 110
    Input.rescue = smoke_frame == 5 or smoke_frame == 75
    Input.start = false
    Input.pause = false
    if PortMode.boss_kind then
      Input.left = false
      Input.right = false
      Input.jump = smoke_frame == 20
      Input.spray = smoke_frame >= 5
      Input.rescue = false
    end
  end

  Input.left_pressed = Input.left and not left_was_down
  Input.right_pressed = Input.right and not right_was_down
  Input.up_pressed = Input.up and not up_was_down
  Input.down_pressed = Input.down and not down_was_down
  Input.jump_pressed = Input.jump and not jump_was_down
  Input.rescue_pressed = Input.rescue and not rescue_was_down
  Input.start_pressed = Input.start and not start_was_down
  Input.pause_pressed = Input.pause and not pause_was_down

  left_was_down = Input.left
  right_was_down = Input.right
  up_was_down = Input.up
  down_was_down = Input.down
  jump_was_down = Input.jump
  rescue_was_down = Input.rescue
  start_was_down = Input.start
  pause_was_down = Input.pause
end

return Input
