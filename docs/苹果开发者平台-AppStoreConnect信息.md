# 涉川 — 苹果开发者平台 / App Store Connect 注册与上架信息

本文档提供在 **Apple Developer（开发者账号）** 与 **App Store Connect** 注册/创建应用时需填写的描述、需勾选的权限（Capabilities）及权限用途说明。

---

## 一、App 基本信息（App Store Connect / 创建 App 时）

| 项目 | 填写内容 |
|------|----------|
| **App 名称（显示名）** | 涉川 |
| **副标题（Subtitle，可选）** | 步数映射名川徒步 |
| **Bundle ID** | `cn.lindenliu.rivtrek`（需在 Apple Developer 先创建同 ID 的 App ID） |
| **SKU** | 自定义唯一标识，例如：`rivtrek-ios-001` |

### App ID 描述（Apple Developer 创建 App ID 时）

在 **Certificates, Identifiers & Profiles → Identifiers → +** 创建 App ID 时，**Description** 字段通常**不允许符号**（如 · 【】 「」 （）等），且可能只接受英文/数字/空格。下面两段可直接复制使用（二选一）：

**英文简短版（推荐）：**
```
Rivtrek Health and fitness app that maps daily steps to virtual walking along rivers like the Yangtze
```

**英文更短版（若字数受限）：**
```
Rivtrek step to river walking fitness app
```

注意：只填字母、数字、空格，不要加逗号、句号、引号等符号，避免提交报错。

---

## 二、应用描述（可直接复制）

### 宣传文本（Promotional Text，可随时改，最多 170 字符）

```
将每日步数映射为在长江等名川上的虚拟徒步，极简界面、流体动效与河声氛围，记录你的行走成就。
```

### 描述（Description，应用页长描述，建议 200–4000 字）

```
涉川是一款健康运动类 App，把你在现实中的每一步，映射为在地理名川上的虚拟徒步距离。

【核心玩法】
· 步数同步：从「健康」读取步数，换算为在选定河流上的行进里程。
· 河流地图：在长江等名川上虚拟行走，已走过路段高亮，未到达段灰显，一目了然。
· 拾遗与成就：到达特定里程触发拾遗与成就，用极简方式记录你的行走故事。
· 河声氛围：配合河流段落的氛围音效，让行走更有沉浸感。

【设计风格】
采用 Digital Zen 数字禅意风格，极简界面、通透动效与磨砂玻璃质感，并支持深色模式。

【数据与隐私】
步数数据仅用于本地计算行进进度与成就展示；如需云端同步，会在隐私政策中单独说明并征得同意。
```

### 关键词（Keywords，逗号分隔，无空格，最多 100 字符）

```
步数,徒步,健康,运动,河流,长江,成就,计步,行走
```

### 分类（Category）

- **主分类**：健康健美（Health & Fitness）
- **次分类（可选）**：生活（Lifestyle）或 娱乐（Entertainment）

### 年龄分级建议

- 选 **4+** 即可（无社交、无内购、无敏感内容）。

---

## 三、Apple Developer 后台：App ID 与 Capabilities（要勾选的权限）

在 [developer.apple.com](https://developer.apple.com) → **Certificates, Identifiers & Profiles** → **Identifiers** 中：

1. 新建或编辑 **App IDs**，Bundle ID 填：`cn.lindenliu.rivtrek`。
2. 在 **Capabilities** 中勾选下列项（与当前 App 实际使用一致）：

### 必须勾选

| Capability | 说明 | 项目中的用途 |
|------------|------|----------------|
| **HealthKit** | 健康数据读写 | 读取步数、写入行走成就（Info.plist 已有 NSHealthShareUsageDescription / NSHealthUpdateUsageDescription） |
| **Background Modes** | 后台模式 | Info.plist 已声明 `location`、`fetch`、`processing`，需在 Capabilities 中勾选对应项（见下） |

### HealthKit 详细配置

- 勾选 **HealthKit**。
- 若使用 **Clinical Health Records（健康记录）**：勾选 **HealthKit - Clinical Health Records**（当前 `RunnerRelease.entitlements` 中有 `health-records`，若实际只做步数可考虑在 Xcode 里去掉该条）。
- 在 App 内实际请求的为：**步数（Steps）的读、写**；审核时若被问用途，说明：用于将步数换算为河流上的虚拟徒步距离与成就记录。

### Background Modes 详细配置

在 **Background Modes** 中勾选与 Info.plist 中 `UIBackgroundModes` 一致的项：

| 勾选项 | 对应 Info.plist | 用途 |
|--------|----------------------|------|
| **Location updates** | `location` | 后台同步行进进度、路线相关 |
| **Background fetch** | `fetch` | 定期拉取/同步数据 |
| **Background processing** | `processing` | 后台处理任务（如步数同步） |

不需要勾选的常见项（除非你后续要加）：

- Push Notifications（当前项目未使用推送）
- Sign in with Apple（未使用）
- App Groups（未使用）
- Associated Domains（未使用）

---

## 四、权限与隐私声明对应（供审核/备注）

App 内已在 **Info.plist** 配置的用途说明，与 Apple 要求一致即可；在 App Store Connect「App 隐私」与审核备注中可引用：

| 权限 / 能力 | 用途说明（与 Info.plist 一致） |
|-------------|----------------------------------|
| **健康（HealthKit）— 读** | 涉川需要读取步数数据以同步你的行进进度。 |
| **健康（HealthKit）— 写** | 涉川需要记录你的行走成就。 |
| **运动与健身（Motion）** | 涉川需要访问运动传感器以追踪你的实时步数。 |
| **位置 — 使用期间** | 涉川需要你的位置信息以计算行进路线和天气。 |
| **位置 — 始终（后台）** | 涉川需要在后台同步你的行进进度。 |

在 **App Store Connect → 你的 App → App 隐私** 中，按上述用途如实选择「数据类型」与「用途」（例如：健康与健身、位置等），并确保与隐私政策一致。

---

## 五、Xcode 中的配置核对

- **Signing & Capabilities**：  
  - 已启用 **HealthKit**，且 **RunnerRelease.entitlements** 中为 Release 使用。  
  - 若只做步数、不做临床健康记录，可在 Xcode 的 HealthKit 能力里取消 **Clinical Health Records**，并从 `RunnerRelease.entitlements` 中删除 `com.apple.developer.healthkit.access` 的 `health-records`，避免审核被问。
- **Info.plist**：  
  - 已包含上述所有 Usage Description，无需再改即可用于提交。

---

## 六、iOS 发布用哪张证书？备案怎么填

你本机/账号里可能有多张证书，**发布涉川时实际用的**是下面这一套里的那张。

### 1. 涉川项目当前用的是哪个 Team

- 项目里已配置：**Development Team = `9H8CQSVYGG`**（在 Xcode → Runner target → Signing & Capabilities 里可看到）。
- 发布（Archive / 上传 App Store）时，用的就是**这个 Team 下**、且为 **App Store 分发** 的那张证书。

### 2. 怎么确认“发布时用的是哪张证书”

**方法一：看 Xcode 打包结果（最准）**

1. 在 Xcode 打开涉川工程，选 **Any iOS Device**，菜单 **Product → Archive**。
2. 归档完成后在 **Organizer** 里选中刚生成的 Archive，右侧或 **Distribute App** 流程里会显示本次签名用的：
   - **Signing Certificate**（例如：Apple Distribution: 你的名字 (9H8CQSVYGG)）
   - **Provisioning Profile**（例如：AppStore 的 cn.lindenliu.rivtrek 描述文件）

那张 **Signing Certificate** 就是当前发布涉川用的证书，备案时填这张即可。

**方法二：在本机看所有“分发用”证书**

终端执行：

```bash
security find-identity -v -p codesigning
```

在列表里找 **Apple Distribution** 或 **iPhone Distribution**，且括号里是 **9H8CQSVYGG** 的那一行，就是你这个 Team 的发布证书。若只有一条 Apple Distribution (9H8CQSVYGG)，那发布涉川（以及你之前那个已上架 app）用的都是这一张。

### 3. 备案时填什么

- 若备案要求填 **开发者/企业名称**：填你 Apple 开发者账号对应的**团队名称**（个人就是你的名字，公司就是公司名）。
- 若要求填 **证书类型**：选 **Apple Distribution**（App Store 发布用）。
- 若要求填 **Team ID**：填 **9H8CQSVYGG**。
- 若要求填**证书名称/说明**：填 Xcode Organizer 或 `security find-identity` 里看到的那张 **Apple Distribution: xxx (9H8CQSVYGG)** 的完整名称即可。

总结：先做一次 **Product → Archive**，看 Organizer 里显示的 Signing Certificate，那张就是涉川（以及同 Team 下其他已上架 app）发布用的证书，备案选/填这张即可。

### 4. 上一个 app 已备案过，能直接用当时的证书信息吗？

**可以。** 涉川和上一个 app 若都是同一个 Apple 开发者账号（同一 Team，如 9H8CQSVYGG）签名的，用的就是**同一张** Apple Distribution 证书。

- **备案时**：证书相关项（如开发者/企业名称、证书类型、Team ID、证书名称等）可以照搬上一个 app 备案时填的那份，无需重新查。
- **需要按应用区分的**：应用名称、Bundle ID（涉川填 `cn.lindenliu.rivtrek`）、应用简介等，按涉川单独填即可。

---

## 七、提交前检查清单

- [ ] 在 Apple Developer 为 `cn.lindenliu.rivtrek` 创建 App ID，并勾选 HealthKit、Background Modes（Location updates, Background fetch, Background processing）。
- [ ] Xcode 中该 App 的 Signing & Capabilities 与上述一致，Release 使用 RunnerRelease.entitlements。
- [ ] App Store Connect 中已填描述、关键词、分类、年龄分级。
- [ ] 「App 隐私」中已按实际使用的健康、位置、运动数据填写。
- [ ] 若上架中国区，准备好隐私政策 URL、必要时应用备案号等信息。

---

*文档依据当前项目 `ios/Runner/Info.plist`、`ios/Runner/RunnerRelease.entitlements` 及 `pubspec.yaml` 整理，后续若增删权限请同步更新本文档与 Xcode/Developer 配置。*
