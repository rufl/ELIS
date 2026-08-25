-- Binary-looking text in every Lua lexical form must remain untouched.
local quoted = "0b101"
local single = '0B110'
local long = [=[0b111]=]
local escaped = "quote: \"0b1000\""
-- 0b11111111 is intentionally inside a comment.
--[=[ 0b10101010 is intentionally inside a long comment. ]=]

return {
  quoted = quoted,
  single = single,
  long = long,
  escaped = escaped,
  value = 0b101,
  upper_value = 0B110,
}
