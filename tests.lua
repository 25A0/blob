local Blob = require("Blob")

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