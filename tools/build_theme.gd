extends SceneTree

## 构建 battle_theme.theme（headless 运行）
## 用法: Godot --headless --script tools/build_theme.gd

func _init() -> void:
	print("Creating battle_theme.theme ...")

	var theme := Theme.new()

	# ──────────────────────────────────────
	# 1. 字体（headless 模式下 TTF 导入不可用，暂不设置）
	# 在 Godot 编辑器中首次打开项目后，字体 .import 文件会自动生成。
	# 之后可重新运行本脚本或手动将字体加入 Theme。
	# ──────────────────────────────────────
	theme.set_default_font_size(14)

	# ──────────────────────────────────────
	# 2. 主色板
	# ──────────────────────────────────────
	_add_color(theme, "bg_deep", "#0A0E17")
	_add_color(theme, "bg_battle", "#0E121B")
	_add_color(theme, "panel_bg", "#141A24")
	_add_color(theme, "panel_inner", "#141924")
	_add_color(theme, "panel_deep", "#10151D")

	_add_color(theme, "accent_cyan", "#00ACC1")
	_add_color(theme, "accent_cyan_dark", "#00838F")
	_add_color(theme, "accent_blue", "#4A90D9")
	_add_color(theme, "accent_gold", "#D4A843")
	_add_color(theme, "accent_gold_dark", "#8B6914")
	_add_color(theme, "accent_red", "#A8454A")
	_add_color(theme, "accent_green", "#5C9A6E")

	_add_color(theme, "border_primary", "#2D3440")
	_add_color(theme, "border_secondary", "#3D4553")
	_add_color(theme, "divider", "#232A33")
	_add_color(theme, "titlebar_bg", "#141A24")
	_add_color(theme, "tag_bg", "#181E28")
	_add_color(theme, "slot_line", "#D2DCEB")
	_add_color(theme, "muted_blue_gray", "#2C3750")

	_add_color(theme, "text_primary", "#EDF0F5")
	_add_color(theme, "text_secondary", "#A8B2C2")
	_add_color(theme, "text_dim", "#6B7588")
	_add_color(theme, "text_disabled", "#4B5568")
	_add_color(theme, "text_cyan_highlight", "#D0F4F8")
	_add_color(theme, "text_gold_highlight", "#FFF0C8")

	_add_color(theme, "state_selected", "#00ACC1")
	_add_color(theme, "state_selected_gold", "#D4A843")
	_add_color(theme, "state_hover", "#4DD0E1")
	_add_color(theme, "state_interactive", "#00ACC1")
	_add_color(theme, "state_success", "#5C9A6E")
	_add_color(theme, "state_warning", "#D95A5A")
	_add_color(theme, "state_disabled", "#3D4553")

	_add_color(theme, "energy_red", "#D95A5A")
	_add_color(theme, "energy_blue", "#4A90D9")
	_add_color(theme, "energy_green", "#5C9A6E")
	_add_color(theme, "energy_purple", "#8E6BBF")
	_add_color(theme, "energy_yellow", "#D4A843")
	_add_color(theme, "energy_white", "#D0D5DE")

	# ──────────────────────────────────────
	# 3. StyleBoxFlat 定义
	# ──────────────────────────────────────

	# 面板
	theme.set_stylebox("panel", "PanelContainer",
		_sb(Color(0.078, 0.102, 0.141, 0.88), 14, 1, Color(0.824, 0.863, 0.922, 0.10),
			Color(0, 0, 0, 0.32), 10.0, 28.0))

	# 面板标题条
	theme.set_stylebox("titlebar", "PanelContainer",
		_sb(Color(0.063, 0.082, 0.114, 0.92), 14, 0, Color(0.824, 0.863, 0.922, 0.06)))

	# 弹窗面板
	theme.set_stylebox("modal_panel", "PanelContainer",
		_sb(Color(0.086, 0.110, 0.149, 0.96), 14, 1, Color(0.176, 0.204, 0.251, 1.0),
			Color(0, 0, 0, 0.40), 16.0, 40.0))

	# 按钮 normal
	theme.set_stylebox("normal", "Button",
		_sb(Color(0.102, 0.137, 0.196, 1.0), 10, 1, Color(0.824, 0.863, 0.922, 0.12),
			Color(0, 0, 0, 0.18), 4.0, 10.0))

	# 按钮 hover
	theme.set_stylebox("hover", "Button",
		_sb(Color(0.141, 0.188, 0.267, 1.0), 10, 1, Color(0.302, 0.851, 0.882, 0.20)))

	# 按钮 pressed
	theme.set_stylebox("pressed", "Button",
		_sb(Color(0.055, 0.082, 0.125, 1.0), 10, 1, Color(0.824, 0.863, 0.922, 0.08)))

	# 按钮 disabled
	theme.set_stylebox("disabled", "Button",
		_sb(Color(0.102, 0.137, 0.196, 0.60), 10, 1, Color(0.239, 0.271, 0.325, 0.40)))

	# 主按钮(青色)
	theme.set_stylebox("primary", "Button",
		_sb(Color.hex(0x00ACC1FF), 10, 1, Color(1, 1, 1, 0.10),
			Color(0, 0, 0, 0.20), 6.0, 14.0))

	# 次按钮
	theme.set_stylebox("secondary", "Button",
		_sb(Color(0.102, 0.137, 0.196, 1.0), 10, 1, Color(0.176, 0.204, 0.251, 1.0),
			Color(0, 0, 0, 0.15), 4.0, 10.0))

	# 警示按钮
	theme.set_stylebox("danger", "Button",
		_sb(Color.hex(0x8B3A3AFF), 10, 1, Color(1, 1, 1, 0.08),
			Color(0, 0, 0, 0.22), 6.0, 14.0))

	# 空槽
	theme.set_stylebox("slot_empty", "Control",
		_sb(Color(1, 1, 1, 0.02), 10, 2, Color(0.824, 0.863, 0.922, 0.14),
			Color(0, 0, 0, 0.12), 4.0, 10.0))

	# 槽位悬停
	theme.set_stylebox("slot_hover", "Control",
		_sb(Color(1, 1, 1, 0.04), 10, 1, Color(0.302, 0.851, 0.882, 0.50),
			Color(0, 0.675, 0.757, 0.12), 0, 10.0))

	# 槽位选中
	theme.set_stylebox("slot_selected", "Control",
		_sb(Color(1, 1, 1, 0.04), 10, 2, Color.hex(0x00ACC1FF),
			Color(0, 0.675, 0.757, 0.18), 0, 16.0))

	# Tooltip
	theme.set_stylebox("tooltip", "Control",
		_sb(Color(0.047, 0.063, 0.086, 0.96), 10, 1, Color(0.176, 0.204, 0.251, 1.0),
			Color(0, 0, 0, 0.38), 8.0, 20.0))

	# 附属堆叠
	theme.set_stylebox("stack", "Control",
		_sb(Color(0.078, 0.102, 0.141, 0.82), 10, 1, Color(0.824, 0.863, 0.922, 0.08),
			Color(0, 0, 0, 0.20), 4.0, 12.0))

	# 顶部 HUD
	var hud_sb := _sb(Color(0.039, 0.055, 0.090, 0.90), 0, 0)
	hud_sb.border_width_bottom = 1
	hud_sb.border_color = Color(0.824, 0.863, 0.922, 0.06)
	theme.set_stylebox("hud", "Control", hud_sb)

	# 日志抽屉
	theme.set_stylebox("drawer", "Control",
		_sb(Color(0.063, 0.082, 0.114, 0.95), 14, 1, Color(0.176, 0.204, 0.251, 1.0),
			Color(0, 0, 0, 0.36), 8.0, 28.0))

	# 前线标题条(暖红)
	theme.set_stylebox("front_titlebar", "Control",
		_sb(Color(0.659, 0.271, 0.290, 0.42), 14, 0, Color(1, 1, 1, 0.04)))

	# 能量线标题条(冷蓝)
	theme.set_stylebox("energy_titlebar", "Control",
		_sb(Color(0.290, 0.565, 0.851, 0.32), 14, 0, Color(1, 1, 1, 0.04)))

	# 阻挡高亮面板
	theme.set_stylebox("block_highlight", "Control",
		_sb(Color(0.078, 0.102, 0.141, 0.88), 14, 2, Color(0.831, 0.659, 0.263, 0.75),
			Color(0.831, 0.659, 0.263, 0.16), 0, 24.0))

	# ──────────────────────────────────────
	# 4. Type Variations — CardView
	# ──────────────────────────────────────
	var card_s := _sb(Color(0, 0, 0, 0), 12, 1, Color(0.824, 0.863, 0.922, 0.08),
		Color(0, 0, 0, 0.28), 8.0, 20.0)
	theme.set_stylebox("normal", "FrontCard", card_s)
	theme.set_stylebox("normal", "EnergyCard", card_s)

	var hand_s := _sb(Color(0, 0, 0, 0), 10, 1, Color(0.824, 0.863, 0.922, 0.06),
		Color(0, 0, 0, 0.24), 6.0, 16.0)
	theme.set_stylebox("normal", "HandCard", hand_s)

	var popup_s := _sb(Color(0, 0, 0, 0), 12, 1, Color(0.824, 0.863, 0.922, 0.08),
		Color(0, 0, 0, 0.30), 8.0, 22.0)
	theme.set_stylebox("normal", "PopupCard", popup_s)

	# ──────────────────────────────────────
	# 5. 标签
	# ──────────────────────────────────────
	theme.set_stylebox("tag", "Control",
		_sb(Color(0.094, 0.118, 0.157, 1.0), 999, 1, Color(1, 1, 1, 0.06)))
	theme.set_stylebox("tag_accent", "Control",
		_sb(Color.hex(0x004D5EFF), 999, 1, Color(0, 0.675, 0.757, 0.14)))

	# ──────────────────────────────────────
	# 6. 常量
	# ──────────────────────────────────────
	_add_const(theme, "margin", 12.0)
	_add_const(theme, "panel_padding", 12.0)
	_add_const(theme, "slot_spacing", 14.0)
	_add_const(theme, "titlebar_height", 28.0)
	_add_const(theme, "hud_height", 40.0)
	_add_const(theme, "corner_radius_small", 8.0)
	_add_const(theme, "corner_radius_medium", 10.0)
	_add_const(theme, "corner_radius_large", 14.0)

	# ──────────────────────────────────────
	# 7. 文字颜色 (Label)
	# ──────────────────────────────────────
	theme.set_color("font_color", "Label", Color("#EDF0F5"))
	theme.set_color("font_color", "Button", Color("#EDF0F5"))
	theme.set_color("font_disabled_color", "Button", Color("#4B5568"))
	theme.set_color("font_hover_color", "Button", Color("#D0F4F8"))
	theme.set_color("font_pressed_color", "Button", Color("#EDF0F5"))
	theme.set_constant("icon_max_width", "Button", 24)

	# ──────────────────────────────────────
	# 保存
	# ──────────────────────────────────────
	var path := "res://assets/ui/battle_theme.theme"
	var err := ResourceSaver.save(theme, path)
	if err == OK:
		print("Theme saved to ", path)
	else:
		printerr("Failed to save theme: error ", err)

	quit(0)


# ── helpers ──

func _add_color(theme: Theme, name: String, hex: String) -> void:
	theme.set_color(name, "Control", Color(hex))

func _add_const(theme: Theme, name: String, value: float) -> void:
	theme.set_constant(name, "Control", int(value))

func _sb(bg: Color, radius: float, border: float, border_color := Color.TRANSPARENT,
		shadow_color := Color.TRANSPARENT, shadow_offset_y: float = 0.0, shadow_size: float = 0.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(radius))
	if border > 0:
		var bw := int(border)
		sb.border_width_left = bw; sb.border_width_right = bw
		sb.border_width_top = bw; sb.border_width_bottom = bw
		sb.border_color = border_color
	if shadow_color.a > 0 and shadow_size > 0:
		sb.shadow_color = shadow_color
		sb.shadow_size = int(shadow_size)
		sb.shadow_offset = Vector2(0, shadow_offset_y)
	return sb
