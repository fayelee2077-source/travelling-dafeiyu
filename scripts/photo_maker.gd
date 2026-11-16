class_name PhotoMaker
extends Node
## Turns a screenshot of the world into a "photo" (way A, no AI): crops around the companion, renders it
## through photo.gdshader (soft pixels, depth of field, bloom, warm grading, vignette) and frames it on
## paper with a caption. Saves user://photos/<time>.png plus <time>_raw.png (the plain crop, for later).

const OUT := "user://photos/"
const W := 960
const H := 720


## shot: the screen; focus: the companion on it (pixels); world_px: screen pixels per world pixel.
func make(shot: Image, focus: Vector2, world_px: float, caption: String) -> String:
	var x := clampi(int(focus.x - W / 2.0), 0, maxi(shot.get_width() - W, 0))
	var y := clampi(int(focus.y - H * 0.55), 0, maxi(shot.get_height() - H, 0))
	var crop := shot.get_region(Rect2i(x, y, mini(W, shot.get_width()), mini(H, shot.get_height())))

	var vp := SubViewport.new()
	vp.size = Vector2i(W + 80, H + 150)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var paper := ColorRect.new()
	paper.color = Color8(250, 247, 240)
	paper.size = Vector2(vp.size)
	vp.add_child(paper)
	var pic := TextureRect.new()
	pic.texture = ImageTexture.create_from_image(crop)
	pic.position = Vector2(40, 40)
	pic.size = Vector2(W, H)
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/photo.gdshader")
	mat.set_shader_parameter("focus", (focus - Vector2(x, y)) / Vector2(W, H))
	mat.set_shader_parameter("px", world_px / W)
	mat.set_shader_parameter("aspect", float(W) / H)
	pic.material = mat
	vp.add_child(pic)
	var label := Label.new()
	label.text = caption
	label.position = Vector2(46, H + 66)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color8(96, 84, 76))
	vp.add_child(label)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	DirAccess.make_dir_recursive_absolute(OUT)
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
	var path := OUT + stamp + ".png"
	img.save_png(path)
	crop.save_png(OUT + stamp + "_raw.png")
	Settings.log_line("photo: %s" % ProjectSettings.globalize_path(path))
	return path
