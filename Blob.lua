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

Blob.types = {
  byte = "c1",
  bytes = function(count)
    return string.format("c%d", count)
  end,
  word = "c2",
  dword = "c4",
  
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
      if Blob.types[name] then 
        return function(_, ...)
          local formatstring
          if type(Blob.types[name]) == "function" then
            formatstring = Blob.types[name](...)
          else formatstring = Blob.types[name] end
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

return Blob
