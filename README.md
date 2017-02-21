# Binary Lunar Objects Library

This is a simple helper utility for parsing binary data in Lua.

BLOB is primarily a wrapper around a struct unpack function, spiced up with some
quality of life improvements:

 - No need to keep track of your reading offset
 - Dealing with padding becomes a breeze
 - Define custom types to not repeat yourself
 - Handle uncertainty about what to expect by putting down markers

It preferably uses the `string.unpack` function introduced in Lua 5.3,
but can also use Roberto Ierusalimschy's struct library (http://www.inf.puc-rio.br/~roberto/struct/)
as a fall-back for Lua 5.1 and 5.2.

## Quick tour

BLOB is designed to help you write sane code for parsing binary data,
but does not try to hide details where precision is necessary.
You will still need to specify things like endianness and the way in which
Strings are represented, but BLOB tries to take care of all the tedious bits.

```
local Blob = require("Blob")

-- load the content of a binary file
local blob = Blob.load("my-file.bin")

-- The first four bytes should contain the string "BLOB"
assert(blob:bytes(4) == "BLOB")

-- This is followed by the version, stored as a 2 byte unsigned integer
local version = blob:unpack("I2")

-- Since version 1.1 of this file format, there might be a field tagged
-- "AUTH", followed by the email-address of the author.
local author

-- We save our current position; if there is no "AUTH" field, we will
-- want to continue parsing from here
blob:mark()

if version >= 110 and blob:bytes(4) == "AUTH" then
	-- there is an "AUTH" field. We can forget about our saved position
	blob:drop()
	-- the author's email address is a zero-terminated String
	author = blob:zerostring()
else
	-- there was no author field, so we want to go back to where we left off
	blob:restore()
end

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

-- Now parse the list
local list = blob:array(count, function(blob)
	return {
		pos = {blob:vector(2)},
		color = {blob:vector(3)},
    	-- The elements are word-aligned.
		blob:pad("word"),
	}
end)
```

## Usage

### Instantiating

 - `local blob = Blob.new(string)` creates a new instance from a binary string.
	You can safely use multiple blobs in parallel.

 - `local blob = Blob.load(filename)` creates a new instance from the content of a file

 - `local blob = other_blob:split(length)` branch off a shallow copy of the
 	`other_blob`. The new copy will have its initial reading position at the current
 	reading position of `other_blob`. The underlying binary data will not be copied,
 	but the reading position and markers of the two blobs are independent once
 	the new blob is created. If a `length` is given, then the `other_blob` will
 	be advanced by that many bytes.

 	This function is useful in cases where you want to keep an explicit reference
 	to a portion of the blob.

### Parsing

 - `blob:unpack(formatstring)` unpacks a bunch of bytes according to the given
 	format string. See http://www.lua.org/manual/5.3/manual.html#6.4.2 for valid
 	format strings, or http://www.inf.puc-rio.br/~roberto/struct/ if you are using
 	Lua 5.1 or 5.2.
 - `blob:unpack(formatstring, ...)` calls `string.format(formatstring, ...)` and uses
	the resulting formatstring to unpack bytes.
	This is useful for generating format strings on the fly, without having to
	write the `string.format` boilerplate code every time. Example:

``` 
	-- Check how many bytes of data are available to read
	local bytes = blob:unpack("I2")
	-- Read that many bytes
	local data = blob:unpack("c%d", bytes)
```

 - `blob:size(formatstring)` returns the size of the given format string.
 	This function does not work for format strings containing zero-terminated
 	or size-prefixed strings.
 	Currently this function does not support custom types, either.
 - `blob:array(count, fun)` Parse a list of `count` elements by repeatedly parsing
 	the blob using `fun`. The passed function should accept a `blob` and return
 	whatever it parsed. See the tour above for an example.

### Custom types

The module `Blob` contains an array `types` where custom types are stored.
These custom types are stored either as a valid formatting string for simple cases,
or as a function, for more complex cases. The default types are:

```
Blob.types = {
  byte = "c1",
  bytes = function(count)
    return string.format("c%d", count)
  end,
  word = "c2",
  dword = "c4",
}
```

These types can be used for parsing: If `mytype` is defined in `Blob.types`,
then you can use it as a method on a blob to generate a format string.
`blob:word()` is equivalent to `blob:unpack("c2")`,
and `blob:bytes(i)` is equivalent to `blob:unpack("c%d", i)`.

If the type is stored as a function, then this function should return a valid
format string.

Custom types can also be used for padding (see below).

Custom types are always shared between instances, no matter if they are stored
in `blob.types` or `Blob.types`.

### Markers

You can use markers to easily navigate between special positions in the blob.

 - `blob:mark()` creates an anonymous marker and pushes it to a stack.
 - `blob:restore()` removes the topmost anonymous marker from the stack, and moves the reading position to that marker
 - `blob:drop()` removes the tompost anonymous marker from the stack

Use named markers if the stack isn't enough

 - `blob:mark(name)` creates a marker named `name`
 - `blob:restore(name)` moves the reading position to the marker called `name`
 - `blob:drop()` removes the marker called `name`

### Padding

Use `blob:pad(size, position)` to skip padding bytes in various ways.

Here, `size` can be:

 - either a size specified in bytes,
 - a formatting string (e.g. "I4"), or
 - a custom type, defined in `Blob.types`.

The `position` is optional, and can be one of the following:

 - a numeric value that defines the position relative to which padding should be applied,
 - the string "absolute", to simply skip a fixed number of padding bytes, or
 - a string that refers to a marker, in which case padding will be aligned
 	relative to the position of that marker.

If no position is given, then padding is applied relative to the start of the
blob.

#### Examples

 - You have finished reading the options field of a TCP packet and want to skip
 	to the data field, which starts at the next multiple of 4 bytes:
```
	-- Your current position is 23 (using Lua's indexing). The next byte after
	-- a 4 byte boundary is at index 25.
	print(blob.pos) -- 23
	-- Apply padding to dword boundary ("dword" is a double-word, or 4 bytes)
	blob:pad("dword")
	-- This skipped two bytes, as expected
	print(blob.pos) -- 25
```

 - You want to skip padding bytes equivalent to the size of a somewhat complex 
	struct:
```
	blob:pad("c16I4I4I4")
```

 - You want to skip to the next boundary of 1024 bytes, but the padding is not
	aligned to the beginning of the blob, but to some other position:
```
	blob:pad(1024, 16)
```

 - The padding does not follow any alignment; it's just a fixed number of bytes:
```
	blob:pad(32, "absolute")
```

## Pitfalls

Compatibility between `string.unpack` and `struct.unpack`:

 - `z` vs `s`
 - no `c0` in `struct`

## Example: Parsing RIFF

Here is how you could parse a generic [RIFF](http://www.tactilemedia.com/info/MCI_Control_Info.html) file with BLOB:

```
local Blob = require("Blob")

-- define type for four-character codes
Blob.types.fourcc = "c4"

local function parse_chunk(blob)
	local chunk = {}
	chunk.id = blob:fourcc()
	chunk.size = blob:unpack("I4")
	-- Both RIFF and LIST chunks contain a four character type
	if chunk.id == "RIFF" or chunk.id == "LIST" then
		chunk.form_type = blob:fourcc()
        chunk.nested = {}
        local begin = blob.pos
        while blob.pos < begin + chunk.size do
      	  table.insert(chunk.nested, parse_chunk(blob))
        end
	else
    	chunk.content = blob:split(chunk.size) -- split off a blob of `size` bytes
        blob:pad("word") -- Skip padding to the next word boundary
	end
    return chunk
end

local function parse_riff(blob)
	local riff = parse_chunk(blob)
	assert(riff.id == "RIFF")
	return riff
end

-- Create a new Blob with the content of the file
local blob = Blob.load("some-file.riff")
local riff = parse_chunk(blob)
```

## TODO

 - stateful endianness
 - support custom types in `size`
 - support in-place string formatting for `size`
 - support custom types and format strings in `array`
