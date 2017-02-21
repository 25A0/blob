local struct = require("struct")

local Blob = {
  -- Mark the current position in the blob with the given name.
  -- If no name is provided, an anonymous marker is pushed to a stack.
  mark = function (self, name)
    if type(name) == "string" then
      self.markers[name] = self.pos
    else table.insert(self.markers, self.pos) end
    return self.pos
  end,
  -- Restore the position to the position of the mark with the given name.
  -- If no name is given, an anonymous marker is popped (and thus removed)
  -- from a stack
  restore = function (self, name)
    -- only drop anonymous markers
    local pos
    if type(name) == "string" then pos = self.markers[name]
    else pos = self:drop(name) end

    self.pos = pos
    return pos
  end,
  -- Drop a marker without altering the position.
  -- If no name is given, drop the topmost marker from the stack.
  -- Return the dropped position
  drop = function (self, name) 
    if type(name) == "string" then
      local ret = self.markers[name]
      self.markers[name] = nil
      return ret
    else return table.remove(self.markers) end
  end,


  -- Expose a method to manuall set the position
  seek = function(self, pos) self.pos = pos end,

  unpack = function(self, formatstring, ...)
    local unpacked
    -- This allows the user to call blob:unpack("%d", myvar)
    -- instead of creating the formatted string first.
    if ... then
      formatstring = string.format(formatstring, ...)
    end

    unpacked, self.pos = struct.unpack(formatstring,
      self.buffer, self.pos + self.offset)
    self.pos = self.pos - self.offset
    return unpacked, self.pos
  end,

  size = function(self, ...)
    local total = 0
    for _, f in ipairs({...}) do
      total = total + struct.size(f)
    end
    return total
  end,

  array = function(self, limit, fun)
    local t = {}
    for i=1,limit do
      -- fun might return multiple values, but table.insert easily gets confused by that.
      -- This makes sure that only the first value is passed to table.insert.
      local capture = fun(self)
      table.insert(t, capture)
    end
    return t
  end,
}

local Alias = {
  bytes = function(count)
    return string.format("c%d", count)
  end,
  
}

-- Create a new blob from a given binary string
Blob.new = function(string, offset)
  local blob = setmetatable({
    buffer = string,
    pos = 1,
    offset = offset or 0,
    markers = {}
  }, {
    __index = function(self, name)
      if Alias[name] then 
        return function(_, ...)
          local formatstring = Alias[name](...)
          return self:unpack(formatstring)
        end
      else return Blob[name] end
    end
  })
  return blob
end

-- Create a new blob from the content of the given file
Blob.load = function(filename)
  local f = assert(io.open(filename, "rb"), "Could not open file ".. filename)
  local buffer = f:read("*all")
  f:close()
  local blob = Blob.new(buffer)
  return blob
end

-- Split off an existing blob at the current position of this blob.
-- Note that this does not copy the content of the given blob.
-- If a length is given, advance the original blob by that many bytes
-- after splitting off the new blob.
Blob.split = function(blob, length)
  local new = Blob.new(blob.buffer, blob.pos - 1 + blob.offset)
  blob.pos = blob.pos + (length or 0)
  return new
end

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
  assert(Blob:size(Alias.bytes(4)) == 4)
  assert(Blob:size(Alias.bytes(4), "c6") == 10)

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

return Blob
