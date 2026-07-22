# 04. Lo-Fi 3D Text 渲染系统

> Issue #44 — Lo-Fi 3D Text Rendering
> 系统级渲染增强，提供 3D 世界中的 lo-fi 文字渲染能力。

## 4.1 架构决策

| 决策 | 选择 | 理由 |
|------|------|------|
| 基节点 | Label3D（Godot 4.7 原生） | 成熟的 3D 文本布局、自动 Billboard、行内换行支持 |
| Lo-Fi 效果 | 片段着色器（ShaderMaterial） | 美学与文本引擎解耦，参数可导出实现逐实例调优 |
| Billboard | Label3D.billboard = true | 原生属性，零自定义代码 |
| 字体 | 像素风位图字体 (.fnt + .png) | 低分辨率源文本避免过度依赖着色器像素化 |
| 霓虹辉光 | WorldEnvironment Glow + emissive_color | Godot 原生后处理，无需自定义 blur shader |
| Label3D pixel_size | 强制 0.0 | 避免与着色器像素化叠加导致视觉破碎 |

## 4.2 数据流

```
Godot 3D World
    │
    ├── WorldEnvironment (Glow enabled)
    ├── Camera3D
    │
    └── LoFiText3D (extends Label3D)
            │
            ├── text → string
            ├── font → PixelFont (assets/fonts/pixel_font.tres)
            ├── pixel_factor → float 0.0–1.0
            ├── color_bits → int 2–24
            ├── scanline_intensity → float 0.0–1.0
            ├── emissive_color → Color
            └── emissive_strength → float 0.0–5.0
                    │
                    └── ShaderMaterial (shaders/lo_fi_text.gdshader)
                            ├── UV quantization (pixelation)
                            ├── per-channel bit reduction (color depth)
                            ├── alpha-masked scanline overlay
                            └── additive emissive glow
```

## 4.3 核心数据结构

### LoFiText3D 导出参数

```gdscript
# shaders/lo_fi_text.gdshader uniforms
uniform float pixel_factor : hint_range(0.0, 1.0) = 0.5
uniform float color_bits : hint_range(2.0, 24.0) = 8.0
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.15
uniform vec4 emissive_color : source_color = vec4(0.0)
uniform float emissive_strength : hint_range(0.0, 5.0) = 0.0
```

### 着色器效果（按顺序执行）

1. **像素化** — UV 坐标取整量化，step count 随 pixel_factor 从 256 降至 16
2. **色深缩减** — 每通道 `floor(rgb * pow(2, color_bits)) / pow(2, color_bits)`
3. **扫描线** — UV.y 正弦波，alpha 遮罩仅作用于文字像素
4. **自发光** — 叠加 emissive_color * emissive_strength * alpha

## 4.4 场景结构

```gdscript
# test_3d_text.tscn — 三种模式演示
Root: Node3D
├── Camera3D (0, 2, 5)
├── WorldEnvironment (Glow enabled, ACES tonemap)
├── DirectionalLight3D (energy=0.5)
├── BillboardSign (Label3D)     → text="BAR", billboard, emissive amber
├── FlatSign (Label3D)          → text="ELM ST.", fixed plane
└── NeonTitle (Label3D)         → text="DAY 17", strong emissive cyan
```

## 4.5 关键设计决策解释

- **为什么用 Label3D 而非 TextMesh/Viewport?** Label3D 是 Godot 原生 3D 文本路径，处理 90% 场景（招牌、标题卡、位置标记）无需自定义字体渲染或网格生成。TextMesh 用于真正的 3D 挤出（未来），Viewport 用于墙面贴花（未来）。
- **为什么着色器像素化要禁用 Label3D.pixel_size?** 两者叠加会导致视觉破碎 — shader 做 UV 域像素化，Label3D 做屏幕域像素化，冲突结果不可预测。
- **为什么扫描线只作用于文字像素?** 全屏扫描线会破坏场景氛围（这是环境文字，不是 CRT 模拟器）。通过 `tex_color.a > 0.01` 遮罩确保透明区域不受影响。
- **为什么使用位图字体而非动态字体?** 8×8 像素位图字体从源头上提供 lo-fi 外观，着色器只需轻微像素化即可达到目标效果。动态字体需要更多像素化才能掩盖光滑边缘。
