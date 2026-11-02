extends RefCounted
## Sharing maps as text and QR codes. Not part of the game's extends chain: the
## game uses it with preload("res://map_share.gd") and its static functions.
##
## Codes: <prefix><version digit><base32 of the bytes + 2 check bytes>, for example
## "GTD1..." for maps. Base32 is only capital letters and 2-7, so a code survives
## chat apps and line breaks, and fits QR codes in their compact letters mode.
## pack() / unpack() are the envelope, so other things (saves) can use it with
## their own prefix. Map codes hold the size, the name and the deflated tiles.
##
## Everything read from a code is untrusted: lengths are capped before decoding,
## the check bytes must match, decompressing stops at width x height bytes, and
## the rows still have to pass read_map() (the caller does that).

const B32 := "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
const CODE_MAX := 3000  # characters after spaces are taken out: the biggest real map is under 800

const MAP_PREFIX := "GTD"
const MAP_VERSION := 1
const MAP_TILES := ".#1234rtw"  # MAP_LETTERS in game_base.gd: a tile is its index here
const MAP_MIN := Vector2i(12, 9)  # as in game_base.gd
const MAP_MAX := Vector2i(48, 36)
const NAME_BYTES_MAX := 24  # MAP_NAME_MAX


# ---------------------------------------------------------------- the envelope

# prefix: capital letters; version: 0-9.
static func pack(prefix: String, version: int, data: PackedByteArray) -> String:
	var all := data.duplicate()
	all.append_array(check_bytes(data))
	return prefix + str(version) + b32_encode(all)


# Returns {"bytes": PackedByteArray} or {"error": text for the player}. Spaces,
# line breaks, dashes and lower case are fine.
static func unpack(prefix: String, version: int, text: Variant, what := "code") -> Dictionary:
	if not (text is String):
		return {"error": "That isn't a %s" % what}
	if text.length() > CODE_MAX * 2:
		return {"error": "That %s is too long" % what}
	var s := ""
	for ch: String in text.to_upper():
		if ch not in [" ", "\n", "\r", "\t", "-"]:
			s += ch
	if s.length() > CODE_MAX:
		return {"error": "That %s is too long" % what}
	if not s.begins_with(prefix) or s.length() <= prefix.length() + 1:
		return {"error": "That isn't a %s (they start with %s)" % [what, prefix]}
	var v := s[prefix.length()]
	if not v.is_valid_int():
		return {"error": "That isn't a %s (they start with %s)" % [what, prefix]}
	if int(v) > version:
		return {"error": "That %s is from a newer version of the game: update to use it" % what}
	if int(v) != version:
		return {"error": "That %s is from an old version of the game and can't be read" % what}
	var all := b32_decode(s.substr(prefix.length() + 1))
	if all.size() < 3 or check_bytes(all.slice(0, all.size() - 2)) != all.slice(all.size() - 2):
		return {"error": "That %s is broken or incomplete: copy all of it again" % what}
	return {"bytes": all.slice(0, all.size() - 2)}


static func check_bytes(b: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish().slice(0, 2)


static func b32_encode(b: PackedByteArray) -> String:
	var out := ""
	var acc := 0
	var n := 0
	for x in b:
		acc = (acc << 8) | x
		n += 8
		while n >= 5:
			n -= 5
			out += B32[(acc >> n) & 31]
		acc &= (1 << n) - 1
	if n > 0:
		out += B32[(acc << (5 - n)) & 31]
	return out


# Unknown letters give [] (so the check fails).
static func b32_decode(s: String) -> PackedByteArray:
	var out := PackedByteArray()
	var acc := 0
	var n := 0
	for ch in s:
		var v := B32.find(ch)
		if v < 0:
			return PackedByteArray()
		acc = ((acc << 5) | v) & 0xFFFF
		n += 5
		if n >= 8:
			n -= 8
			out.append((acc >> n) & 0xFF)
	return out


# ---------------------------------------------------------------- map codes

# rows: a map's rows of letters (already checked by read_map()).
static func map_to_code(title: String, rows: Array) -> String:
	var tiles := PackedByteArray()
	for r: String in rows:
		for ch in r:
			tiles.append(maxi(MAP_TILES.find(ch), 0))
	var name_bytes := title.to_utf8_buffer().slice(0, NAME_BYTES_MAX)
	var data := PackedByteArray([String(rows[0]).length(), rows.size(), name_bytes.size()])
	data.append_array(name_bytes)
	data.append_array(tiles.compress(FileAccess.COMPRESSION_DEFLATE))
	return pack(MAP_PREFIX, MAP_VERSION, data)


# Returns {"name": String, "rows": Array} or {"error": text}. The caller still
# has to run read_map() on the rows and clean_map_name() on the name.
static func code_to_map(text: Variant) -> Dictionary:
	var u := unpack(MAP_PREFIX, MAP_VERSION, text, "map code")
	if u.has("error"):
		return u
	var p: PackedByteArray = u.bytes
	if p.size() < 4:
		return {"error": "That map code is broken"}
	var w := p[0]
	var h := p[1]
	var nl := p[2]
	if w < MAP_MIN.x or w > MAP_MAX.x or h < MAP_MIN.y or h > MAP_MAX.y or nl > NAME_BYTES_MAX or p.size() < 4 + nl:
		return {"error": "That map code is broken"}
	var title := p.slice(3, 3 + nl).get_string_from_utf8()
	# Exactly width x height bytes: anything that unpacks to more is refused
	var tiles := p.slice(3 + nl).decompress(w * h, FileAccess.COMPRESSION_DEFLATE)
	if tiles.size() != w * h:
		return {"error": "That map code is broken"}
	var rows := []
	for y in h:
		var r := ""
		for x in w:
			var t := tiles[y * w + x]
			if t >= MAP_TILES.length():
				return {"error": "That map code is broken"}
			r += MAP_TILES[t]
		rows.append(r)
	return {"name": title, "rows": rows}


# ---------------------------------------------------------------- QR codes

# The QR code for text as rows of modules (1 dark, 0 light), without the quiet
# zone (leave 4 light modules around it). [] if it doesn't fit. Level M by default.
static func qr_grid(text: String, level := QR.M) -> Array[PackedByteArray]:
	var q := QR.new()
	var out: Array[PackedByteArray] = []
	if not q.make(text, level):
		return out
	for y in q.size:
		out.append(q.modules.slice(y * q.size, (y + 1) * q.size))
	return out


## A small QR encoder (after Nayuki's MIT-licensed QR Code generator): byte or
## alphanumeric mode, levels L/M/Q/H, versions 1-40, best of the 8 masks.
class QR:
	enum {L, M, Q, H}
	const ALNUM := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
	const LEVEL_BITS := [1, 0, 3, 2]
	# Error correction bytes per block and blocks, by level and version (QR spec)
	const ECC := [
		[-1, 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
		[-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
		[-1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
		[-1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
	]
	const BLOCKS := [
		[-1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
		[-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
		[-1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
		[-1, 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
	]

	var version := 0
	var size := 0
	var level := M
	var mask := 0
	var modules := PackedByteArray()  # size x size, row by row: 1 dark
	var is_func := PackedByteArray()  # 1 for finder, timing, alignment and format modules

	static func raw_modules(ver: int) -> int:
		var r := (16 * ver + 128) * ver + 64
		if ver >= 2:
			var na := ver / 7 + 2
			r -= (25 * na - 10) * na - 55
			if ver >= 7:
				r -= 36
		return r

	static func data_bytes(ver: int, lv: int) -> int:
		return raw_modules(ver) / 8 - ECC[lv][ver] * BLOCKS[lv][ver]

	static func count_bits(ver: int, alnum: bool) -> int:
		if alnum:
			return 9 if ver < 10 else (11 if ver < 27 else 13)
		return 8 if ver < 10 else 16

	static func gf_mul(x: int, y: int) -> int:
		var z := 0
		for i in range(7, -1, -1):
			z = (z << 1) ^ ((z >> 7) * 0x11D)
			z ^= ((y >> i) & 1) * x
		return z & 0xFF

	static func rs_divisor(degree: int) -> PackedByteArray:
		var r := PackedByteArray()
		r.resize(degree)
		r[degree - 1] = 1
		var root := 1
		for i in degree:
			for j in degree:
				r[j] = gf_mul(r[j], root)
				if j + 1 < degree:
					r[j] ^= r[j + 1]
			root = gf_mul(root, 2)
		return r

	static func rs_remainder(data: PackedByteArray, div: PackedByteArray) -> PackedByteArray:
		var r := PackedByteArray()
		r.resize(div.size())
		for b in data:
			var f: int = b ^ r[0]
			r.remove_at(0)
			r.append(0)
			for i in div.size():
				r[i] ^= gf_mul(div[i], f)
		return r

	static func push_bits(arr: PackedByteArray, val: int, n: int) -> void:
		for i in range(n - 1, -1, -1):
			arr.append((val >> i) & 1)

	# false if text doesn't fit in version 40
	func make(text: String, lv := M) -> bool:
		level = lv
		var alnum := true
		for ch in text:
			if not ALNUM.contains(ch):
				alnum = false
				break
		var bytes := text.to_utf8_buffer()
		var count := text.length() if alnum else bytes.size()
		var bits := PackedByteArray()
		if alnum:
			var i := 0
			while i + 1 < text.length():
				push_bits(bits, ALNUM.find(text[i]) * 45 + ALNUM.find(text[i + 1]), 11)
				i += 2
			if i < text.length():
				push_bits(bits, ALNUM.find(text[i]), 6)
		else:
			for b in bytes:
				push_bits(bits, b, 8)
		version = 0
		for v in range(1, 41):
			var cb := count_bits(v, alnum)
			if count < (1 << cb) and 4 + cb + bits.size() <= data_bytes(v, lv) * 8:
				version = v
				break
		if version == 0:
			return false
		var all := PackedByteArray()
		push_bits(all, 2 if alnum else 4, 4)
		push_bits(all, count, count_bits(version, alnum))
		all.append_array(bits)
		var cap := data_bytes(version, lv) * 8
		push_bits(all, 0, mini(4, cap - all.size()))
		push_bits(all, 0, (8 - all.size() % 8) % 8)
		var data := PackedByteArray()
		for i in range(0, all.size(), 8):
			var b := 0
			for k in 8:
				b = (b << 1) | all[i + k]
			data.append(b)
		var pad := 0xEC
		while data.size() < cap / 8:
			data.append(pad)
			pad ^= 0xEC ^ 0x11
		build(data)
		return true

	func build(data: PackedByteArray) -> void:
		size = version * 4 + 17
		modules = PackedByteArray()
		modules.resize(size * size)
		is_func = PackedByteArray()
		is_func.resize(size * size)
		draw_function_patterns()
		draw_codewords(add_ecc(data))
		var best := -1
		var best_score := 0
		for m in 8:
			apply_mask(m)
			draw_format(m)
			var p := penalty()
			if best < 0 or p < best_score:
				best = m
				best_score = p
			apply_mask(m)
		mask = best
		apply_mask(mask)
		draw_format(mask)

	func set_f(x: int, y: int, dark: bool) -> void:
		modules[y * size + x] = 1 if dark else 0
		is_func[y * size + x] = 1

	func draw_function_patterns() -> void:
		for i in size:
			set_f(6, i, i % 2 == 0)
			set_f(i, 6, i % 2 == 0)
		finder(3, 3)
		finder(size - 4, 3)
		finder(3, size - 4)
		var pos := align_positions()
		var n := pos.size()
		for i in n:
			for j in n:
				if (i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0):
					continue
				for dy in range(-2, 3):
					for dx in range(-2, 3):
						set_f(pos[i] + dx, pos[j] + dy, maxi(absi(dx), absi(dy)) != 1)
		draw_format(0)
		if version >= 7:
			var rem := version
			for i in 12:
				rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
			var bits := (version << 12) | rem
			for i in 18:
				var dark := ((bits >> i) & 1) == 1
				var a := size - 11 + i % 3
				var b := i / 3
				set_f(a, b, dark)
				set_f(b, a, dark)

	func finder(cx: int, cy: int) -> void:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var d := maxi(absi(dx), absi(dy))
				var x := cx + dx
				var y := cy + dy
				if x >= 0 and x < size and y >= 0 and y < size:
					set_f(x, y, d != 2 and d != 4)

	func align_positions() -> Array[int]:
		var r: Array[int] = []
		if version == 1:
			return r
		var n := version / 7 + 2
		var step := 26 if version == 32 else ceili((size - 13) / float(n * 2 - 2)) * 2
		r.append(6)
		var p := size - 7
		while r.size() < n:
			r.insert(1, p)
			p -= step
		return r

	func format_bits(m: int) -> int:
		var data: int = (LEVEL_BITS[level] << 3) | m
		var rem := data
		for i in 10:
			rem = (rem << 1) ^ ((rem >> 9) * 0x537)
		return ((data << 10) | rem) ^ 0x5412

	func draw_format(m: int) -> void:
		var bits := format_bits(m)
		for i in 6:
			set_f(8, i, ((bits >> i) & 1) == 1)
		set_f(8, 7, ((bits >> 6) & 1) == 1)
		set_f(8, 8, ((bits >> 7) & 1) == 1)
		set_f(7, 8, ((bits >> 8) & 1) == 1)
		for i in range(9, 15):
			set_f(14 - i, 8, ((bits >> i) & 1) == 1)
		for i in 8:
			set_f(size - 1 - i, 8, ((bits >> i) & 1) == 1)
		for i in range(8, 15):
			set_f(8, size - 15 + i, ((bits >> i) & 1) == 1)
		set_f(8, size - 8, true)

	# Splits the data into blocks, adds Reed-Solomon bytes, interleaves them.
	func add_ecc(data: PackedByteArray) -> PackedByteArray:
		var nb: int = BLOCKS[level][version]
		var el: int = ECC[level][version]
		var raw := raw_modules(version) / 8
		var n_short := nb - raw % nb
		var short_len := raw / nb
		var div := rs_divisor(el)
		var blocks := []
		var k := 0
		for i in nb:
			var dl := short_len - el + (0 if i < n_short else 1)
			var dat := data.slice(k, k + dl)
			k += dl
			var e := rs_remainder(dat, div)
			if i < n_short:
				dat.append(0)
			dat.append_array(e)
			blocks.append(dat)
		var out := PackedByteArray()
		for i in blocks[0].size():
			for j in nb:
				if i != short_len - el or j >= n_short:
					out.append(blocks[j][i])
		return out

	# The zigzag: two columns at a time from the right, up then down.
	func draw_codewords(cw: PackedByteArray) -> void:
		var i := 0
		var right := size - 1
		while right >= 1:
			if right == 6:
				right = 5
			for vert in size:
				for j in 2:
					var x := right - j
					var up := ((right + 1) & 2) == 0
					var y := size - 1 - vert if up else vert
					if is_func[y * size + x] == 0 and i < cw.size() * 8:
						modules[y * size + x] = (cw[i >> 3] >> (7 - (i & 7))) & 1
						i += 1
			right -= 2

	static func mask_bit(m: int, x: int, y: int) -> bool:
		match m:
			0: return (x + y) % 2 == 0
			1: return y % 2 == 0
			2: return x % 3 == 0
			3: return (x + y) % 3 == 0
			4: return (x / 3 + y / 2) % 2 == 0
			5: return x * y % 2 + x * y % 3 == 0
			6: return (x * y % 2 + x * y % 3) % 2 == 0
			_: return ((x + y) % 2 + x * y % 3) % 2 == 0

	func apply_mask(m: int) -> void:
		for y in size:
			for x in size:
				if is_func[y * size + x] == 0 and mask_bit(m, x, y):
					modules[y * size + x] ^= 1

	# The spec's penalty: long runs, 2x2 blocks, finder-like patterns, dark balance.
	func penalty() -> int:
		var p := 0
		for horizontal in [true, false]:
			for a in size:
				var line := PackedByteArray()
				line.resize(size)
				for b in size:
					line[b] = modules[a * size + b] if horizontal else modules[b * size + a]
				var run := 1
				for b in range(1, size + 1):
					if b < size and line[b] == line[b - 1]:
						run += 1
						continue
					if run >= 5:
						p += run - 2
					run = 1
				for b in range(0, size - 6):
					if line[b] == 1 and line[b + 1] == 0 and line[b + 2] == 1 and line[b + 3] == 1 and line[b + 4] == 1 and line[b + 5] == 0 and line[b + 6] == 1:
						var light_before := true
						for k in range(1, 5):
							if b - k >= 0 and line[b - k] == 1:
								light_before = false
						var light_after := true
						for k in range(7, 11):
							if b + k < size and line[b + k] == 1:
								light_after = false
						if light_before or light_after:
							p += 40
		var dark := 0
		for y in size:
			for x in size:
				var c := modules[y * size + x]
				dark += c
				if x < size - 1 and y < size - 1 and c == modules[y * size + x + 1] and c == modules[(y + 1) * size + x] and c == modules[(y + 1) * size + x + 1]:
					p += 3
		var total := size * size
		p += maxi(ceili(absf(dark * 20 - total * 10) / total) - 1, 0) * 10
		return p
