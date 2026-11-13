# Texture import verification probe: prints the actual loaded format of each
# PBR texture so we can prove VRAM compression, linear-vs-sRGB and mipmap
# generation for every role (albedo/normal/orm/rough).
extends SceneTree

func _fmt_name(f: int) -> String:
	match f:
		Image.FORMAT_RGB8: return "RGB8"
		Image.FORMAT_RGBA8: return "RGBA8"
		Image.FORMAT_L8: return "L8"
		Image.FORMAT_RG8: return "RG8"
		Image.FORMAT_DXT1: return "DXT1"
		Image.FORMAT_DXT5: return "DXT5"
		Image.FORMAT_DXT5_RA_AS_RG: return "DXT5_RA"
		Image.FORMAT_RGTC_R: return "RGTC_R"
		Image.FORMAT_RGTC_RG: return "RGTC_RG"
		Image.FORMAT_BPTC_RGBA: return "BPTC_RGBA"
		Image.FORMAT_ETC2_RGB8: return "ETC2_RGB8(sRGB?)"
		Image.FORMAT_ETC2_RGBA8: return "ETC2_RGBA8(sRGB?)"
		Image.FORMAT_ETC2_R11: return "ETC2_R11"
		Image.FORMAT_ETC2_RG11: return "ETC2_RG11"
		Image.FORMAT_ETC2_RA_AS_RG: return "ETC2_RA"
		Image.FORMAT_ASTC_4x4: return "ASTC_4x4"
		Image.FORMAT_ASTC_8x8: return "ASTC_8x8"
		_: return "fmt_%d" % f

func _probe(path: String) -> void:
	var t: Texture2D = load(path)
	if t == null:
		print("PROBE %-40s MISSING" % path)
		return
	var img := t.get_image()
	print("PROBE %-40s %-16s mips=%d %dx%d" % [
		path.get_file(), _fmt_name(img.get_format()),
		img.get_mipmap_count(), t.get_width(), t.get_height()])

func _init() -> void:
	var dir := DirAccess.open("res://assets/textures/pbr")
	dir.list_dir_begin()
	var names: Array[String] = []
	var f := dir.get_next()
	while f != "":
		if f.ends_with(".webp") or f.ends_with(".png"):
			names.append(f)
		f = dir.get_next()
	names.sort()
	for n in names:
		_probe("res://assets/textures/pbr/" + n)
	quit(0)
