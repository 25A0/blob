# Binary Lunar OBjects library

This is a simple helper utility for parsing binary data in Lua.

Blob is primarily a wrapper around a struct unpack function, spiced up with some
quality of life improvements:

 - No need to keep track of your reading offset
 - Dealing with padding becomes a breeze
 - Define custom types to not repeat yourself
 - Handle uncertainty about what to expect by putting down markers

It preferably uses the `string.unpack` function introduced in Lua 5.3,
but can also use Roberto Ierusalimschy's struct library (http://www.inf.puc-rio.br/~roberto/struct/)
as a fall-back for Lua 5.1 and 5.2.

## Quick tour

Blob is designed to help you write sane code for parsing binary data,
but does not try to hide details where precision is necessary.
You will still need to specify things like endianness and the way in which
Strings are represented, but Blob tries to take care of all the tedious bits.

Next we will have a look at `my-file.bin`, a made-up piece of binary data that
we will parse in this example:

```lua
-- [[ my-file.bin
    (offset)  (                     data                     )  (      ASCII     )
    00000000  42 4c 4f 42 71 00 41 55  54 48 67 75 79 40 68 6f  |BLOBq.AUTHguy@ho|
    00000010  73 74 2e 63 6f 6d 00 00  00 00 00 00 00 00 00 00  |st.com..........|
    00000020  03 00 80 d3 20 00 c0 69  e0 3e 76 ac 21 f1 3a d6  |.... ..i.>v.!.:.|
    00000030  c0 3f d6 5b 70 36 eb 2d  e8 3f 0c b5 3a 15 86 5a  |.?.[p6.-.?..:..Z|
    00000040  dd 3f dc 18 a2 e0 6d 0c  e1 3f b6 0d 38 c8 da 06  |.?....m..?..8...|
    00000050  cc 3f 77 2c 30 60 3b 16  a8 3f 85 72 ab 7f 42 b9  |.?w,0`;..?.r..B.|
    00000060  e5 3f 98 79 eb d0 cb bc  e5 3f 02 d2 7b 13 01 e9  |.?.y.....?..{...|
    00000070  ed 3f 99 16 31 4c 4c 8b  d8 3f 1e 3e 61 15 0f 9f  |.?..1LL..?.>a...|
    00000080  e0 3f 89 2e 35 a3 44 97  ea 3f df 66 23 88 6f b3  |.?..5.D..?.f#.o.|
    00000090  a1 3f a6 be 36 cc 52 5f  ab 3f 0a                 |.?..6.R_.?.|
    0000009b
]]
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

if version >= 110 and blob:bytes(4) == "AUTH" then
	-- the author's email address is a zero-terminated String
	author = blob:zerostring()
else
	-- there was no author field, so we want to go back to where we left off
	-- before we checked the four bytes
	blob:rollback()
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
		-- The format string in `vector` captures multiple values at once.
		-- By surrounding the call with curly braces, we make sure that all
		-- captured values are stored in `pos` and `color`.
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

``` lua
	-- Check how many bytes of data are available to read
	local bytes = blob:unpack("I2")
	-- Read that many bytes
	local data = blob:unpack("c%d", bytes)
```

Both variants of `blob:unpack` can be used with format strings that capture
multiple values (e.g. `"c8I4"`). In these cases, the calls will return all those
values. They can be captured in various ways:

```lua
    -- assign the captured values to individual variables
	local r, g, b, a = blob:unpack("BBBB")
	-- store all captured values in a table
	local coords = {blob:unpack("dd")}
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

```lua
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

```lua
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

```lua
	blob:pad("c16I4I4I4")
```

 - You want to skip to the next boundary of 1024 bytes, but the padding is not
	aligned to the beginning of the blob, but to some other position:

```lua
	blob:pad(1024, 16)
```

 - The padding does not follow any alignment; it's just a fixed number of bytes:

```lua
	blob:pad(32, "absolute")
```

## Pitfalls

Blob will automatically detect whether `string.unpack` is available. If not, it
will try to use `struct` as a fall-back.
However, the APIs of these two libraries are not fully compatible.
In particular, the following restrictions apply:

 - `struct` offers the format string `"c0"`, which reads a number of characters
 	equal to the last parsed numeric value. This does not exist in `sting.unpack`.
 - `string.unpack` offers the format string `"s[n]"` to unpack a string that is
 	prefixed by an `n`-byte unsigned integer. This does not exist in `struct`.
 - `struct` allows the format string `"c"` to read one character. However this
 	is not a legal format string in `string.unpack`. The equivalent format string
 	for `string.unpack` is `"c1"`.
 - A zero-terminated string is decoded as `"s"` in `struct`, but as `"z"` in 
 	`string.unpack`.

Blob offers a few workarounds that might help to avoid these problems:

 - Use the custom type `prefixstring(n)` to decode a string that is prefixed by
 	an `n`-byte unsigned integer. This behaves similar to `"s[n]"` in
 	`string.unpack`, and will in some cases be enough to replace `"c0"` in `struct`.
 - Always specify the number of characters in the format string `"c"`, but make
 	sure that this number is never 0.
 - Use the custom type `zerostring()` to decode a zero-terminated string.
 	This will automatically use either `"z"` or `"s"`, depending on which
 	library is used.

The string `Blob.backend` exposes which library is used internally. It contains
`"lua"` when Blob uses the `string` functions of Lua 5.3,
and `"struct"` when Blob uses the `struct` library.

## Example: Parsing RIFF

Here is how you could parse a generic [RIFF](http://www.tactilemedia.com/info/MCI_Control_Info.html) file with Blob:

```lua
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
local riff = parse_riff(blob)
```

## TODO

 - stateful endianness
 - support custom types in `size`
 - support in-place string formatting for `size`
 - support custom types and format strings in `array`
