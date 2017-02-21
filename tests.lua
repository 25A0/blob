local Blob = require("Blob")
local struct = require("struct")

-- Test initialization
do
  local blob = Blob.new("xkcd")
  assert(blob.pos == 1)
  assert(blob.buffer == "xkcd")
  -- Make sure that each blob instance has its own table
  local otherblob = Blob.new("abcd")
  assert(blob.buffer == "xkcd")
end

-- Test markers and position
do
  local blob = Blob.new("xkcd")
  blob:seek(2)
  assert(blob.pos == 2)
  -- mark returns the marked position
  assert(blob:mark() == 2)
  blob:seek(4)
  assert(blob.pos == 4)
  -- now restore the previous position
  assert(blob:restore() == 2)
  -- make sure that this corresponds with the actual position
  assert(blob.pos == 2)
end

-- Test custom types
do
  local blob = Blob.new("xkcd")
  assert(blob:bytes(4) == "xkcd")
  blob:seek(1)
  assert(blob:bytes(1) == "x")
  assert(blob:bytes(3) == "kcd")
  blob:seek(1)
  assert(blob:dword() == "xkcd")
  blob:seek(1)
  assert(blob:word() == "xk")
  assert(blob:word() == "cd")
  blob:seek(1)
  assert(blob:byte() == "x")
  assert(blob:byte() == "k")
end

-- Test custom types across instances
do
  local blob1 = Blob.new("xkcd")
  Blob.types.pair = "c2"
  assert(blob1:pair() == "xk")
  local blob2 = Blob.new("1234")
  assert(blob2:pair() == "12")
end

-- Test array
do
  local blob = Blob.new("xkcdabcd1234")
  local function quad(blob)
    return blob:bytes(4)
  end
  local quads = blob:array(3, quad)
  assert(#quads == 3)
  assert(quads[1] == "xkcd")
  assert(quads[2] == "abcd")
  assert(quads[3] == "1234")
end

-- Test multiple return values
do
  local blob = Blob.new("xkcdabcd1234")
  local a, b = blob:unpack("c2c2")
  assert(a == "xk" and b == "cd")
  local list = {blob:unpack("cccc")}
  assert(#list == 4)
  assert(unpack(list) == "a", "b", "c", "d")
end

-- Test array with multiple return values
do
  local blob = Blob.new("xkcdabcd1234")
  local function quad(blob)
    return blob:unpack("c2c2")
  end
  local quads = blob:array(3, quad)
  assert(#quads == 3)
  assert(quads[1] == "xk", "cd")
  assert(quads[2] == "ab", "cd")
  assert(quads[3] == "12", "34")
end

-- Test padding
do
  local blob = Blob.new [[
    Lorem ipsum dolor sit amet, consectetur adipisicing elit, sed do eiusmod
    tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam,
    quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo
    consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse
    cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non
    proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
  ]]

  -- test that padding at initial position has no effect
  blob:pad("word")
  assert(blob.pos == 1)
  blob:pad("c256")
  assert(blob.pos == 1)
  blob:pad(64)
  assert(blob.pos == 1)

  -- test actual padding
  blob:byte()
  blob:pad("word")
  assert(blob.pos == 3)
  blob:pad("I4")
  assert(blob.pos == 5)
  blob:pad("c10")
  assert(blob.pos == 11)
  blob:pad(32)
  assert(blob.pos == 33)

  -- test that padding a single byte has no effect
  blob:pad(1)
  assert(blob.pos == 33)
  blob:pad("byte")
  assert(blob.pos == 33)

  -- test absolute padding
  blob:pad(30, "absolute")
  assert(blob.pos == 63)

  -- test relative padding
  blob:seek(13)
  blob:mark("beginning")
  blob:unpack("c6")
  blob:mark("unpadded")
  blob:pad("c8", "beginning")
  assert(blob.pos == 21)
  blob:restore("unpadded")
  blob:pad("c8")
  assert(blob.pos == 25)

  -- test case from the readme
  blob:seek(23)
  blob:pad("dword")
  assert(blob.pos == 25)
end

-- Test size
do
  assert(Blob:size("c4") == 4)
  assert(Blob:size(Blob.types.bytes(4)) == 4)
  assert(Blob:size(Blob.types.bytes(4), "c6") == 10)

end

-- Test offset and splitting
do
  local blob = Blob.new("xkcdabcd1234")
  assert(blob:bytes(2) == "xk")
  blob:mark()
  local split = blob:split()
  -- Offset into the buffer is not visible in the blob's position
  assert(split.pos == 1)
  -- Instead it's tracked by its offset field
  assert(split.offset == 2)
  -- Now these blobs can be used independently
  assert(blob:bytes(2) == "cd")
  assert(split:bytes(2) == "cd")

  blob:restore()
  assert(blob.pos == 3)
  -- Now split off a blob of 4 bytes
  split = blob:split(4)
  assert(blob.pos == 7)
  assert(blob:bytes(6) == "cd1234")
  assert(split:bytes(6) == "cdabcd")
end

-- Test in-place string formatting
do
  local blob = Blob.new("xkcdabcd1234")
  assert(blob:unpack("c%d", 4) == "xkcd")
end

-- Test "quick tour" code from the Readme
do
  local binstrings = {}
  table.insert(binstrings, "BLOB")
  table.insert(binstrings, struct.pack("I2", 113))
  table.insert(binstrings, "AUTH")
  local email = "guy@host.com"
  table.insert(binstrings, struct.pack("s", email))
  local len = #email + 1 + 4 + 4 + 2
  table.insert(binstrings, struct.pack(string.rep("x", 16 - (len % 16))))

  table.insert(binstrings, struct.pack("I2", 3))
  local c = {}
  for i=1,3 do
    local x, y = math.random(), math.random()
    local r, g, b = math.random(), math.random(), math.random()
    table.insert(c, {x, y, r, g, b})
    local padding
    if struct.size("ddddd") % 2 > 0 then padding = "x" else padding = "" end
    table.insert(binstrings, 
      struct.pack("ddddd"..padding, x, y, r, g, b)
    )
  end

  -- README code below

  -- load the content of a binary file
  local blob = Blob.new(table.concat(binstrings))

  -- The first four bytes should contain the string "BLOB"
  assert(blob:bytes(4) == "BLOB")

  -- This is followed by the version, stored as a 2 byte unsigned integer
  local version = blob:unpack("I2")
  assert(version == 113)

  -- Since version 1.1 of this file format, there might be a field tagged
  -- "AUTH", followed by the email-address of the author.
  local author

  -- We save our current position; if there is no "AUTH" field, we will
  -- want to continue parsing from here
  blob:mark()

  if version >= 110 and blob:bytes(4) == "AUTH" then
    -- there is an "AUTH" field. We can forget about our saved position
    blob:drop()
    --  the author's email address is a zero-terminated String
    author = blob:zerostring()
  else
    -- there was no author field, so we want to go back to where we left off
    blob:restore()
  end
  assert(author == email, author.." " ..email)

  -- We want to skip padding bytes to the next 16 byte boundary
  blob:pad(16)

  -- Create a custom type that can parse 2D or 3D vectors
  blob.types.vector = function(dimensions)
  -- The vector has one double value per dimension
  return string.rep("d", dimensions)
  end

  -- Parse a list of pairs of 2D coordinates and a three-dimensional color vector.
  -- The number of elements is stored as a two byte unsigned integer
  local count = blob:unpack("I2")
  assert(count == 3)

  -- Now parse the list
  local list = blob:array(count, function(blob)
    return {
      pos = {blob:vector(2)},
      color = {blob:vector(3)},
      -- The elements are word-aligned.
      blob:pad("word"),
    }
  end)

  for i=1,count do
    assert(list[i].pos[1] == c[i][1])
    assert(list[i].pos[2] == c[i][2])
    assert(list[i].color[1] == c[i][3])
    assert(list[i].color[2] == c[i][4])
    assert(list[i].color[3] == c[i][5])
  end

end