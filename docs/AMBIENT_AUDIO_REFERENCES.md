# 河畔混音 · 官方范例与实现依据

本模块依赖 **audio_service** 与 **just_audio**。修改逻辑前请先查阅以下官方文档与范例，避免与库约定冲突或引入未定义行为。

---

## 一、官方参考链接

| 来源 | 链接 | 用途 |
|------|------|------|
| audio_service 教程 | https://github.com/ryanheise/audio_service/wiki/Tutorial | Handler 写法、stop 时释放资源、广播 idle |
| audio_service 示例 | https://github.com/ryanheise/audio_service/tree/minor/audio_service/example | 单 player Handler 完整示例（play/pause/seek/stop） |
| just_audio README | https://github.com/ryanheise/just_audio#readme | 基本播放、多 player、stop 释放、错误处理（PlayerInterruptedException） |
| just_audio 多 player | README 中 "Managing Multiple Audio Players" | 多实例时用 `await player.stop()` 释放 decoder/buffers |

---

## 二、audio_service 约定（按 Tutorial / Example）

1. **Handler 是唯一音频逻辑入口**  
   UI / 通知 / 耳机等只向 Handler 发 play、pause、stop 等，由 Handler 内部操作 player。

2. **释放资源（Tutorial "Releasing resources"）**  
   - 在 Handler 的 `stop()` 里：`await _player.stop();` 释放 decoder，再 `playbackState.add(..., processingState: AudioProcessingState.idle)` 关闭通知。  
   - 官方示例：`Future<void> stop() => _player.stop();`（单 player，直接转发）。

3. **customAction**  
   - 用于「标准媒体动作之外的」应用自定义动作。  
   - 我们用 `playAmbient` / `stopAmbient` 触发多轨混音的播放与停止，因标准接口是单曲模型。

4. **初始化**  
   - `AudioService.init(builder: () => YourHandler(), config: ...)` 在 main 里调用一次，得到的 Handler 单例供 UI 调用。

---

## 三、just_audio 约定（按 README / API）

1. **stop() vs dispose()**  
   - **stop()**：暂停并释放平台 decoder/buffer，保留 source，可后续 resume。  
   - **dispose()**：完全释放资源并关闭流，player 不可再用。彻底不用该实例时必须调用。  
   - 多 player 范例里只写了 `await player.stop()`；我们场景是「退出页面后不再用这批 player」，故对每个 player 先 stop 再 dispose，符合「彻底不用时 dispose」的文档说明。

2. **多 player 释放（README "Managing Multiple Audio Players"）**  
   ```dart
   await player1.stop();
   await player2.stop();
   ```  
   说明：Free platform decoders and buffers for each player.

3. **加载被中断（README "Handle Player Errors"）**  
   - 在 load 完成前对 player 调用 **stop 或 dispose**，正在进行的 `setUrl`/`setAsset`/`load` 会抛出 **PlayerInterruptedException**。  
   - 文档原文：*"This call was interrupted since another audio source was loaded or the player was stopped or disposed before this audio source could complete loading."*  
   - 因此：用 stop/dispose 打断加载是**官方支持的用法**，catch 后按「用户中断」处理即可，不应视为加载失败。

4. **错误处理**  
   - 加载失败：`PlayerException`。  
   - 加载被中断：`PlayerInterruptedException`。

---

## 四、本项目的对应实现（代码已按此对齐）

| 官方约定 | 本项目实现 |
|----------|------------|
| Handler 内释放资源、广播 idle | `AmbientAudioHandler.stop()` 与 `customAction('stopAmbient')` 均先 `await _service.stopSyncAsync()`，再 `_broadcastState(idle, false)`。 |
| stop() 里先 await 再 idle | 同上，与 Tutorial "Releasing resources" 一致。 |
| 开始加载时广播 loading | `customAction('playAmbient')` 里先 `_broadcastState(loading, false)`，再调 `_service.play(spec)`、再 `_broadcastState(ready, true)`。 |
| 多 player 释放 | `stopSyncAsync()` 与 `stop()` 对每个 player 执行 `_stopOnePlayer`（await stop + dispose，2s 超时）。 |
| 新 session 前清掉上一轮 | `_playImpl` 开头先设 `_stopRequested = true` 再 `await stop()`，这样上一轮若还在 setAsset 返回后会看到 _stopRequested 并 abort；且 `stop()` 内会一并停掉 `_loadingPlayer`，避免两套 _playImpl 同时往 _layers 加 player。 |
| 加载中用户退出 | `stopSyncAsync()` 立即对 `_loadingPlayer` stop+dispose，setAsset 会抛 `PlayerInterruptedException`，catch 后不打成加载失败。 |
| 彻底不用 player | 退出时每个 player 都 stop+dispose，符合 just_audio 文档。 |

---

## 五、修改时的注意点

1. **不要依赖「setAsset 阻塞 15 秒」**  
   日志里出现的 `getCurrentPosition failed: TimeoutException after 0:00:15.000000` 来自 **flow_screen 的 Geolocator.getCurrentPosition**（定位 15s 超时），不是 just_audio。setAsset 可能因设备/格式较慢，但中断方式以 just_audio 文档为准（stop/dispose → PlayerInterruptedException）。

2. **Handler 的 stop 必须真正停播并广播 idle**  
   否则通知或系统仍认为在播，且资源未释放。

3. **先 stop 再 dispose**  
   just_audio 无「必须先 stop 再 dispose」的强制顺序，但先 stop 再 dispose 更稳妥，与多 player 范例一致。

4. **customAction 为异步**  
   UI 调用 `customAction('stopAmbient')` 不 await 亦可；Handler 内应 await 完成 stop 再返回，以便 audio_service 正确序列化后续动作。

以上依据均来自当前（文档获取时）的 audio_service Wiki / Example 与 just_audio README / API；若库升级导致行为变化，请以官方最新文档为准并更新本文档。
