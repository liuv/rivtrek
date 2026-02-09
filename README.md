# 徒步江河

这份设计说明书专为 Flutter 开发环境下的 AI 编程助手（如 Cursor, Claude 3.5 Sonnet, GPT-4o）编写。它将复杂的构思拆解为技术可实现的模块，重点突出了“极简主义”、“程序化流体”和“步数映射机制”。

---

# “徒步江河 (Walking the River)” App 开发设计说明书 (PRD)

## 1. 项目概述

* **定位**：一款文艺、极简的健康运动 App。
* **核心逻辑**：将用户的每日步行数映射为在地理名川（如长江）上的虚拟徒步距离。
* **设计风格**：Digital Zen（数字禅意）、极简主义、高通透感、磨砂玻璃效果。
* **技术栈**：Flutter (Canvas/CustomPainter), Shader (GLSL), HealthKit/Google Fit API。

---

## 2. 视觉规范 (Visual Identity)

* **色调**：
* 主背景：`#F9F9F9` (暖白，类纸张质感) / `#121212` (深色模式)。
* 河流流体：`#00E5FF` (电光青) 到 `#2979FF` (深海蓝) 的动态渐变。
* 文字：`#333333`，字体使用纤细的无衬线体（如 `Inter` 或 `Roboto Thin`）。


* **交互风格**：
* 全屏竖排布局。
* **磨砂玻璃 (Glassmorphism)**：底部菜单栏和弹出面板需具备 `BackdropFilter` 模糊效果。



---

## 3. 核心功能模块 (Core Modules)

### 3.1 动态流体首页 (Flow Screen) - **开发难点**

* **背景表现**：
* 使用 `CustomPainter` 或 `FragmentShader` (Flutter 3.7+ 支持) 绘制一条垂直贯穿屏幕的 S 形流体。
* **算法建议**：基于 **Perlin Noise** 实现流动的位移，通过 `uTime` 变量实现持续向上滑动的效果。


* **数据映射**：
* `Step Count` -> `Flow Speed`: 步数越多，流体流动频率越快。
* `Achievement` -> `Glow Intensity`: 达成阶段目标时，流体发光度（Bloom）增强。


* **UI 元素**：
* 顶部：`Text(Current_Location)` & `Icon(Weather)`。
* 中部：`Big Text(Step_Count)`，字体粗细为 `FontWeight.w100`。
* 底部：悬浮胶囊式功能菜单栏。



### 3.2 步数与地理逻辑 (Geographical Mapping)

* **步数转换公式**：
* `StepLength` 默认为 0.0007 km (70cm)。
* `DifficultyModifier` (地形系数)：源头高海拔段设为 0.8，下游平原段设为 1.2。


* **数据结构 (JSON)**：
* 每一条河为一个 `Challenge` 对象，包含多个 `SubSection` 节点。
* 每个节点包含：名称、里程区间、环境音效、对应的 Shader 参数色值。



### 3.3 拾遗与成就系统 (Collectibles)

* **触发机制**：当 `AccumulatedDistance` 达到特定 `TriggerPoint` 时弹窗。
* **交互表现**：
* 使用极简的 2D 轮廓图或精致的图标。
* 点击“拾取”后，图标以曲线动画飞入“背包”图标。



---

## 4. 技术实现指南 (Technical Guidance for AI)

### 4.1 Shader 代码逻辑建议 (给 AI 的指令)

> "Please implement a custom shader in Flutter for the river background. Use a combination of Fractal Brownian Motion (FBM) and smoothstep to define the river banks. The flow should be vertical and responsive to a 'speed' uniform variable tied to the step count."

### 4.2 状态管理 (State Management)

* 建议使用 **Provider** 或 **Riverpod** 管理步数同步和当前里程。
* **持久化**：使用 `shared_preferences` 存储当前的河段进度和已解锁的物品 ID。

### 4.3 传感器接入

* iOS: `HealthKit` (通过 `health` 插件)。
* Android: `Google Fit API` / `Step Counter Sensor`。

---

## 5. 页面结构定义 (App Structure)

1. **SplashPage**: 极简 Logo + 渐显诗词。
2. **MainFlowPage**: 核心流体交互面，包含：
* `Stack` 布局：底层 Shader 背景 + 中层数据文本 + 顶层磨砂菜单。


3. **DiscoveryPage**: 垂直滚动的河流地图，已走过的路段呈彩色，未达到的呈灰色。
4. **CollectionPage**: 极简的 3xN 宫格，展示已捡拾的物件。

---

## 6. 下一步 Prompt 指令 (可以直接发给 Cursor/AI)

> "你现在是一名资深 Flutter 开发专家。请根据以上设计说明书，首先搭建 App 的基础架构。
> 1. 创建基于 Provider 的数据模型 `RiverProgressModel`。
> 2. 实现主页面 `FlowScreen` 的基本布局，使用 Stack 放置一个占位的蓝色渐变 Canvas 背景。
> 3. 编写一个磨砂玻璃质感的悬浮菜单栏 `FloatingMenuBar`。
> 请先给出这部分的核心代码实现。"
> 
> 

---

**你需要我针对其中某个具体的算法（比如步数换算里程的逻辑代码）进行更详细的补充吗？**
