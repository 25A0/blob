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

-- Test bytes
do
  local blob = Blob.new("xkcd")
  assert(blob:bytes(4) == "xkcd")
  blob:seek(1)
  assert(blob:bytes(1) == "x")
  assert(blob:bytes(3) == "kcd")
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

-- Test size
do
  assert(Blob:size("c4") == 4)
  assert(Blob:size(Blob.Alias.bytes(4)) == 4)
  assert(Blob:size(Blob.Alias.bytes(4), "c6") == 10)

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