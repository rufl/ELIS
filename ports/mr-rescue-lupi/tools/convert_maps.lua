-- Emit only gameplay-relevant data from the pinned Tiled Lua exports.
local upstream = assert(arg[1], "upstream path required")

local function compact(relative)
  local source = assert(loadfile(upstream .. "/" .. relative))()
  local result = { width = source.width, height = source.height, data = {}, objects = {} }
  for _, layer in ipairs(source.layers) do
    if layer.name == "main" then
      for index, value in ipairs(layer.data) do result.data[index] = value end
    elseif layer.name == "objects" then
      for _, object in ipairs(layer.objects) do
        result.objects[#result.objects + 1] = {
          type = object.type,
          x = object.x,
          y = object.y,
          width = object.width,
          height = object.height,
          direction = object.properties and object.properties.dir or nil,
        }
      end
    end
  end
  return result
end

local function quoted(value)
  return string.format("%q", value)
end

local function writeValue(value, indent)
  if type(value) == "number" then
    io.write(tostring(value))
  elseif type(value) == "string" then
    io.write(quoted(value))
  elseif type(value) == "table" then
    io.write("{\n")
    local child_indent = indent .. "  "
    local array_count = #value
    for index = 1, array_count do
      io.write(child_indent)
      writeValue(value[index], child_indent)
      io.write(",\n")
    end
    local keys = {}
    for key in pairs(value) do
      if type(key) ~= "number" or key < 1 or key > array_count or key % 1 ~= 0 then
        keys[#keys + 1] = key
      end
    end
    table.sort(keys, function(left, right) return tostring(left) < tostring(right) end)
    for _, key in ipairs(keys) do
      io.write(child_indent, "[", quoted(key), "] = ")
      writeValue(value[key], child_indent)
      io.write(",\n")
    end
    io.write(indent, "}")
  elseif value == nil then
    io.write("nil")
  else
    error("unsupported value type " .. type(value))
  end
end

local output = { floors = {}, rooms = {} }
local floor_names = { "1-1-1", "1-2", "2-1", "2-2" }
for _, name in ipairs(floor_names) do
  output.floors[#output.floors + 1] = compact("maps/floors/" .. name .. ".lua")
end
for _, width in ipairs({ 10, 11, 17, 24 }) do
  output.rooms[tostring(width)] = {}
  for index = 1, 6 do
    output.rooms[tostring(width)][index] =
      compact("maps/room/" .. width .. "/" .. index .. ".lua")
  end
end

io.write("-- Adapted from CC-BY-SA-3.0 Mr. Rescue map data.\nreturn ")
writeValue(output, "")
io.write("\n")
