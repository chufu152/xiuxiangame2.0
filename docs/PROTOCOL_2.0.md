# 修仙4X·宗门争霸 2.0 —— 通信协议（PROTOCOL_2.0）

> **本文是 2.0 命令契约的唯一落地文档**，回答「69 条命令 + `ping` 各自的 `params` / `result` / `view` / `errorCode` 是什么」。
> **权威优先级**：2.0 已实现代码（`shared/protocol/*.gd`、`server/scripts/net/*.gd`、`server/scripts/model/*.gd`）> `docs/REQUIREMENTS_2.0.md` > 1.0 `PROTOCOL.md` / `COMMAND_MAP.md`。
> 本文**不新增**任何字段、命令、错误码、数值；凡在权威源找不到出处的字段一律标 `TODO(需核对)` 并登记在 §11。
> 骨架与搬运规则见 `docs/prompts/R1.5_R2前置修复.md` §任务 B。

---

## 0. 总则

### 0.1 载体与编码

| 项 | 2.0 约定 | 出处 |
|---|---|---|
| 载体 | **WebSocket 文本帧**，UTF-8 JSON，一条消息一个 JSON 对象 | `docs/REQUIREMENTS_2.0.md` §6.1 |
| 监听 | `127.0.0.1:9527`（`--port` 可覆盖） | `shared/protocol/msg.gd` `DEFAULT_HOST`/`DEFAULT_PORT` |
| 协议版本 | `2.0` | `shared/protocol/msg.gd` `PROTOCOL_VERSION` |
| 存档版本 | `3.0` | `shared/protocol/msg.gd` `SAVE_VERSION` |
| 后端标识 | `xiuxian-godot-headless` | `shared/protocol/msg.gd` `BACKEND` |
| 帧缓冲 | 两端建连**前**统一设 `inbound/outbound_buffer_size = Msg.FRAME_BUFFER_BYTES`（16 MiB） | `shared/protocol/msg.gd` `FRAME_BUFFER_BYTES` |
| 顺序 | 单会话顺序处理，事件顺序 == 服务端结算顺序 | PRD §6.1 |

> 1.0 用 stdio + JSONL；2.0 改为 WebSocket 文本帧。分帧由 WebSocket 协议承担，因此 1.0「响应内不得出现裸换行」的约束在 2.0 不再适用。

### 0.2 信封

请求：

```json
{"id":"c12","type":"moveDisciple","params":{"discipleId":"disciple_3","targetTileId":"q4_r5"}}
```

| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `id` | string | 是 | 命令序号，客户端自增；响应原样回显 |
| `type` | string | 是 | 命令名，须在 §1 命令总表内 |
| `params` | object | 否 | 命令参数（小驼峰）；无参命令可省略 |

成功响应：

```json
{"id":"c12","ok":true,"events":["[结算] …"],"view":{ /* 全量快照，只读命令不带 */ },
 "result":{ /* 命令特定返回，可省略 */ }}
```

失败响应：

```json
{"id":"c12","ok":false,"errorCode":"BAD_PARAMS","message":"人读诊断（仅调试用）"}
```

信封字段名常量：`shared/protocol/msg.gd` `KEY_*`；构造/解析：`shared/protocol/dto.gd`（`hello` / `ok_response` / `error_response` / `parse_text` / `parse_envelope`）。

### 0.3 只读命令不回 `view`

`query*` 等**不修改 `GameState`** 的命令，回包**不带 `view`**（见 §1 的「回 view」列与每条命令的 **view** 项）。
理由（沿用 1.0 §3.1）：这类命令在选中单位、鼠标划过时被高频调用，每次回一份 300 格全量快照纯属浪费带宽。
`setSetting` 只确认、值留在客户端，同样不回 `view`。

### 0.4 业务失败 ≠ 协议失败

玩法不允许（工力不足 / 不在射程 / 山岳不可通行 / 山岳不可建城）一律 `ok:true` + `result.success:false` + `result.message`；
只有「参数缺字段 / 类型错 / 取值非法」才回 `BAD_PARAMS`。出处：PRD §6.2。

### 0.5 错误码（唯一来源 `shared/protocol/msg.gd`，不新增）

| errorCode | 触发条件 | 客户端应对 |
|---|---|---|
| `BAD_JSON` | JSON 非法 | 打日志 |
| `NO_ID` | 缺 `id` | 打日志 |
| `BAD_REQUEST` | 缺 `type` 或 `type` 非字符串 | 打日志 |
| `UNKNOWN_COMMAND` | `type` 不在命令总表中 | 打日志（前端拼错了） |
| `NOT_IMPLEMENTED` | 命令已登记但本版未实现 | 按钮据 `hello.implementedCommands` 置灰 |
| `BAD_PARAMS` | 参数缺失 / 类型错 / 值非法 | 弹提示 |
| `NO_GAME` | 未开局 / 未读档 | 先开局 |
| `INTERNAL` | 服务端异常 | 上报并附日志 |

### 0.6 字段命名约定

1. 字段名**小驼峰**（`spiritStones`、`movePoints`）。
2. 枚举序列化为**大写下划线字符串**（`LIAN_QI`、`ZONG_MEN`、`PLAYER_ACTION`、`HILL`）。
3. 布尔 getter 的 `is` 前缀剥离（`player` / `danger` / `capital` / `bloodLine`）。
4. `randomSeed` 按**64 位整型**处理；超出 2^53-1 时以十进制字符串传递（`CommandDispatcher._normalize_params` 已实现该口径）。

出处：PRD §6.6；`server/scripts/model/*.gd` 的 `to_dict()`。

### 0.7 主动消息

| 类型 | 2.0 状态 | 形状 | 出处 |
|---|---|---|---|
| `hello` | ✅ 已实现 | `{type,protocolVersion,backend,saveVersion,implementedCommands[]}` | `shared/protocol/dto.gd` `hello()` |
| `awaitInput` | 待实现（R7，仅 `victoryChoice`） | `{type,reqId,kind:"victoryChoice",prompt,options[{index,label,routeId,description}]}` | PRD §6.3、§5.2 #7 |
| `snapshot` / `event` | 不采用 | 2.0 以「每条命令回包带全量 `view` + `events` 增量」替代 | PRD §6.2 |

> 1.0 的 `awaitInput.kind` 有 `randomEvent` / `victoryChoice` 两种；2.0 **只保留 `victoryChoice`**（PRD §5.2 #7），`resolveChoice` 只分派 `req_victory_*`。

---

## 1. 命令总表

**69 条 + `ping`**。分组点数：会话 13 / 单位 22 / 城市·区域·改良 18 / 探索 4 / 政令 4 / 自动化·设置 6 / 待抉择 2 = **69**。

「回 view」= 成功响应是否携带全量快照。「状态」= 已实现 / 待实现（R*）。

### 会话与存档（13）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `newGame` | 会话 | R1 | 是 | 否 | 已实现 |
| `getState` | 会话 | R1 | 是 | 否 | 已实现 |
| `finishTurn` | 会话 | R2 | 是 | 否 | 已实现（R2） |
| `beginPlayerTurn` | 会话 | R2 | 是 | 否 | 已实现（R2） |
| `nextTurn` | 会话 | R2 | 是 | 否 | 已实现（R2） |
| `listSaves` | 会话 | R7 | 否 | 是 | 待实现（R7） |
| `saveGame` | 会话 | R7 | 否 | 否 | 待实现（R7） |
| `loadGame` | 会话 | R7 | 是 | 否 | 待实现（R7） |
| `queryVictoryProgress` | 会话 | R7 | 否 | 是 | 待实现（R7） |
| `checkVictory` | 会话 | R7 | 否 | 是 | 待实现（R7） |
| `checkDefeat` | 会话 | R7 | 否 | 是 | 待实现（R7） |
| `chooseVictory` | 会话 | R7 | 是 | 否 | 待实现（R7） |
| `queryGameOver` | 会话 | R7 | 否 | 是 | 待实现（R7） |

### 单位（22）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `moveDisciple` | 单位 | R2 | 是 | 否 | 已实现（R2） |
| `queryMoveRange` | 单位 | R2 | 否 | 是 | 已实现（R2） |
| `batchMove` | 单位 | R5 | 是 | 否 | 待实现（R5） |
| `attack` | 单位 | R5 | 是 | 否 | 待实现（R5） |
| `queryAttackPreview` | 单位 | R5 | 否 | 是 | 待实现（R5） |
| `queryAttackable` | 单位 | R5 | 否 | 是 | 待实现（R5） |
| `retreat` | 单位 | R5 | 是 | 否 | 待实现（R5） |
| `teleport` | 单位 | R5 | 是 | 否 | 待实现（R5） |
| `queryTeleportOptions` | 单位 | R5 | 否 | 是 | 待实现（R5） |
| `assignGarrison` | 单位 | R5 | 是 | 否 | 待实现（R5） |
| `withdrawGarrison` | 单位 | R5 | 是 | 否 | 待实现（R5） |
| `reclass` | 单位 | R5 | 是 | 否 | 待实现（R5） |
| `promote` | 单位 | R5 | 是 | 否 | 待实现（R5） |
| `queryDiscipleDetail` | 单位 | R5 | 否 | 是 | 待实现（R5） |
| `foundSpiritPeak` | 单位 | R3 | 是 | 否 | 待实现（R3） |
| `appointBuilder` | 单位 | R3 | 是 | 否 | 待实现（R3） |
| `rally` | 单位 | R6 | 是 | 否 | 待实现（R6） |
| `returnToDefense` | 单位 | R6 | 是 | 否 | 待实现（R6） |
| `tribulate` | 单位 | R7 | 是 | 否 | 待实现（R7） |
| `appointFengZhu` | 单位 | R7 | 是 | 否 | 待实现（R7） |
| `appointZhangLao` | 单位 | R7 | 是 | 否 | 待实现（R7） |
| `appointZongZhu` | 单位 | R7 | 是 | 否 | 待实现（R7） |

### 城市 / 区域 / 改良（18）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `constructBuilding` | 城市 | R3 | 是 | 否 | 待实现（R3） |
| `queryBuildOptions` | 城市 | R3 | 否 | 是 | 待实现（R3） |
| `openCave` | 城市 | R3 | 是 | 否 | 待实现（R3） |
| `fortifyPeak` | 城市 | R3 | 是 | 否 | 待实现（R3） |
| `foundDistrict` | 城市 | R3 | 是 | 否 | 待实现（R3） |
| `queryDistrictSites` | 城市 | R3 | 否 | 是 | 待实现（R3） |
| `assignWorker` | 城市 | R3 | 是 | 否 | 待实现（R3） |
| `unassignWorker` | 城市 | R3 | 是 | 否 | 待实现（R3） |
| `queryAssignableTiles` | 城市 | R3 | 否 | 是 | 待实现（R3） |
| `queryCityDetail` | 城市 | R3 | 否 | 是 | 待实现（R3） |
| `buildImprovement` | 城市 | R3 | 是 | 否 | 待实现（R3） |
| `repairImprovement` | 城市 | R3 | 是 | 否 | 待实现（R3） |
| `queryImprovementOptions` | 城市 | R3 | 否 | 是 | 待实现（R3） |
| `researchDao` | 城市 | R4 | 是 | 否 | 待实现（R4） |
| `holdRecruitment` | 城市 | R4 | 是 | 否 | 待实现（R4） |
| `queryProjectQueue` | 城市 | R4 | 否 | 是 | 待实现（R4） |
| `cancelProject` | 城市 | R4 | 是 | 否 | 待实现（R4） |
| `accelerateProject` | 城市 | R4 | 是 | 否 | 待实现（R4） |

### 探索（4）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `queryJiYuanInfo` | 探索 | R6 | 否 | 是 | 待实现（R6） |
| `sendToJiYuan` | 探索 | R6 | 是 | 否 | 待实现（R6） |
| `queryMiJingInfo` | 探索 | R6 | 否 | 是 | 待实现（R6） |
| `exploreMiJing` | 探索 | R6 | 是 | 否 | 待实现（R6） |

### 政令（4）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `switchGovernment` | 政令 | R6 | 是 | 否 | 待实现（R6） |
| `enactPolicy` | 政令 | R6 | 是 | 否 | 待实现（R6） |
| `revokePolicy` | 政令 | R6 | 是 | 否 | 待实现（R6） |
| `queryPolicyOptions` | 政令 | R6 | 否 | 是 | 待实现（R6） |

### 自动化 / 设置（6）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `setAutomationToggle` | 自动化 | R6 | 是 | 否 | 待实现（R6） |
| `setPeakAutoProject` | 自动化 | R6 | 是 | 否 | 待实现（R6） |
| `setAllAutoProject` | 自动化 | R6 | 是 | 否 | 待实现（R6） |
| `exploreNow` | 自动化 | R6 | 是 | 否 | 待实现（R6） |
| `queryAutomationState` | 自动化 | R6 | 否 | 是 | 待实现（R6） |
| `setSetting` | 自动化 | R6 | 否 | 是 | 待实现（R6） |

### 待抉择（2）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `queryVictoryChoice` | 待抉择 | R7 | 否 | 是 | 待实现（R7） |
| `resolveChoice` | 待抉择 | R7 | 是 | 否 | 待实现（R7） |

> **分组点数校验**：13 / 22 / 18 / 4 / 4 / 6 / 2 = 69，与 PRD §6.7 一致；由 `tools/check_protocol.ps1` 自动断言。

---

## 2. 会话与存档（13 条）

### `newGame`

- **用途**：新建一局；生成地图、初始化四宗、计算视野，返回全量快照。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `playerFaction` | string | 是 | — | 玩家流派，`Enums.FactionType.ALL`（`ZONG_MEN`/`JIA_ZU`/`GUO_JIA`） | 2.0 代码 `CommandDispatcher._normalize_params` |
| `factionType` | string | 否 | — | `playerFaction` 的**兼容别名**；两者同时出现且不一致 → `BAD_PARAMS` | 同上 |
| `sectName` | string | 是 | — | 宗门名，须为非空白字符串 | 同上 |
| `mapWidth` | int | 否 | `map.defaultWidth`（20） | 地图宽；2 ≤ w ≤ `map.setup.maxWidth` | 同上 |
| `mapHeight` | int | 否 | `map.defaultHeight`（15） | 地图高；2 ≤ h ≤ `map.setup.maxHeight`，且 w×h ≤ `map.setup.maxTiles` | 同上 |
| `randomSeed` | int \| string | 否 | 空 → 服务端随机生成并回传 | 64 位整数语义；JSON 数值超 2^53-1 须传十进制字符串 | 同上 |
| `difficultyId` | string | 否 | `difficulty.defaultLevel`（`normal`） | `easy`/`normal`/`hard` | 同上 |
| `difficulty` | string | 否 | — | `difficultyId` 的**兼容别名**；冲突 → `BAD_PARAMS` | 同上 |

- **result**：`{"success": true}`（`CommandDispatcher._handle_new_game`）。
- **view**：是（全量快照）。
- **events**：`[]`（R1 未产生事件）。
- **errorCode**：`BAD_PARAMS`（流派非法 / sectName 空白 / 地图越界 / seed 非法 / 别名冲突）、`INTERNAL`。
- **里程碑**：R1。
- **状态**：已实现。
- **出处**：2.0 代码 `server/scripts/net/CommandDispatcher.gd` `_handle_new_game` / `_normalize_params`；PRD §6.7。

### `getState`

- **用途**：纯拉取当前全量快照（每条命令回包已含 `view`，此命令用于主动刷新）。
- **params**：无。
- **result**：无（省略）。
- **view**：是。
- **events**：`[]`。
- **errorCode**：`NO_GAME`（未开局）。
- **里程碑**：R1。
- **状态**：已实现。
- **出处**：2.0 代码 `CommandDispatcher._handle_get_state`；PRD §6.7。

### `finishTurn`

- **用途**：结束当前回合，服务端依次结算 SETTLEMENT → AI_ACTION → VICTORY_CHECK。
- **params**：无。
- **result**：无（看 `view` / `events`）。
- **view**：是。
- **events**：本轮结算事件（收入、维护、AI 行动、胜负检查）。
- **errorCode**：`NO_GAME`。
- **里程碑**：R2。
- **状态**：已实现（R2）。
- **出处**：1.0 `PROTOCOL.md` §11.1；`COMMAND_MAP.md` §1；2.0 PRD §7（R2）。

### `beginPlayerTurn`

- **用途**：推进到玩家回合前半段（TURN_START / SPIRIT_PEAK 结算）。
- **params**：无。
- **result**：无（看 `view` / `events`）。
- **view**：是。
- **events**：TURN_START / SPIRIT_PEAK 事件。
- **errorCode**：`NO_GAME`。
- **里程碑**：R2。
- **状态**：已实现（R2）。
- **出处**：1.0 `PROTOCOL.md` §11.1；`COMMAND_MAP.md` §1；2.0 PRD §7（R2）。

### `nextTurn`

- **用途**：推进一个完整回合（旧控制台入口）。
- **params**：无。
- **result**：无（看 `view` / `events`）。
- **view**：是。
- **events**：本回合事件。
- **errorCode**：`NO_GAME`。
- **里程碑**：R2。
- **状态**：已实现（R2）。
- **出处**：1.0 `PROTOCOL.md` §11.1；`COMMAND_MAP.md` §1；2.0 PRD §7（R2）。

### `listSaves`

- **用途**：列出本地存档槽。
- **params**：无。
- **result**：`{saves:[{slotId, turn, playerSectName, factionType, savedAt, filePath, fileSize}…]}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`INTERNAL`。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.1；`COMMAND_MAP.md` §1。

### `saveGame`

- **用途**：保存到指定槽位。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `slot` | string \| int | 是 | — | 存档槽标识 | 1.0 `PROTOCOL.md` §11.1 |

- **result**：`{slot, saved}`；`saved=false` 时另带 `message`。**存档类固定形状，不使用写命令通用的 `success` 布尔**（1.0 D5 已拍板）。
- **view**：否。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`（槽位非法）、`NO_GAME`。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.1；`COMMAND_MAP.md` §1。

### `loadGame`

- **用途**：读取指定槽位并重建对局。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `slot` | string \| int | 是 | — | 存档槽标识 | 1.0 `PROTOCOL.md` §11.1 |

- **result**：`{slot, turn}`；槽位不存在 → `BAD_PARAMS`。
- **view**：是。
- **events**：读档后若有待决（胜利择一），追加一条 `awaitInput`（PRD §6.3）。
- **errorCode**：`BAD_PARAMS`、`INTERNAL`。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.1；`COMMAND_MAP.md` §1；PRD §6.3。

### `queryVictoryProgress`

- **用途**：查询某宗各胜利路线的进度。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 目标宗门 id | 1.0 `PROTOCOL.md` §11.1 |

- **result**：`{sectId, routes:[{route, achieved, ratio, summary, stage, score, goals}…]}`。
- **view**：否（只读）。会顺带刷新 `sect.powerLevel` 派生缓存（1.0 既有行为）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.1；`COMMAND_MAP.md` §1。

### `checkVictory`

- **用途**：判定某宗是否达成胜利路线。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 目标宗门 id | 1.0 `PROTOCOL.md` §11.1 |

- **result**：`{sectId, route}`；未达成时 `route` 为 `null`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.1；`COMMAND_MAP.md` §1。

### `checkDefeat`

- **用途**：判定某宗是否已失败。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 目标宗门 id | 1.0 `PROTOCOL.md` §11.1 |

- **result**：`{sectId, defeated}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.1；`COMMAND_MAP.md` §1。

### `chooseVictory`

- **用途**：在同时达成多条胜利路线时择定结局。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `routeId` | string | 是 | — | 选定的胜利路线 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{success, routeId, winType, message}`。
- **view**：是。
- **events**：结局事件。
- **errorCode**：`BAD_PARAMS`（routeId 非法）、`NO_GAME`。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §1、§8。

### `queryGameOver`

- **用途**：查询终局字段。
- **params**：无。
- **result**：`{turn, gameOver, winType, winnerSectId, pendingVictoryChoices[]}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`NO_GAME`。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.1；`COMMAND_MAP.md` §1。

---

## 3. 单位（22 条）

### `moveDisciple`

- **用途**：把弟子移动到目标地块。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.2 |
| `targetTileId` | string | 是 | — | 目标地块 id（`q{q}_r{r}`） | 同上 |

- **result**：`MoveResult` = `{success, message, reachedTileId, turnsRemaining, triggeredEvent}`。
- **view**：是（迷雾随移动刷新）。
- **events**：迷雾刷新 / 触发事件（若 1.0 有）。
- **errorCode**：`BAD_PARAMS`、`BAD_REQUEST`（当前阶段非 PLAYER_ACTION）、`NO_GAME`。
- **里程碑**：R2。
- **状态**：已实现（R2）。
- **出处**：1.0 `PROTOCOL.md` §11.2、§11.4；`COMMAND_MAP.md` §2；2.0 PRD §7（R2）。

### `queryMoveRange`

- **用途**：查询弟子可达地块与逐格代价（移动模式高亮用）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.2 |

- **result**：`{discipleId, originTileId, movePoints, maxMovePoints, tileIds[], costs{tileId:代价}, tileCount}`。`tileIds` 为 BFS 发现顺序（起点在 `tileIds[0]`，`costs[起点]=0`），与 `moveDisciple` 共用同一算法，故「高亮的格子必然走得进去」。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R2。
- **状态**：已实现（R2）。
- **出处**：1.0 `PROTOCOL.md` §11.2、§11.4；`COMMAND_MAP.md` §2；2.0 PRD §4.1.8（移动成本叠加）。

### `batchMove`

- **用途**：批量移动本宗多支部队到同一目标地块。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |
| `discipleIds` | string[] | 是 | — | 弟子 id 列表 | 同上 |
| `targetTileId` | string | 是 | — | 目标地块 id | 同上 |

- **result**：`{success:true, message, sectId, targetTileId, discipleCount}`（逐人战报在 `message`；文案型命令统一 `success:true` + `message`）。
- **view**：是。
- **events**：迷雾刷新等。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R5。
- **状态**：待实现（R5）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2。

### `attack`

- **用途**：对目标地块的敌军发起攻击。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 攻方弟子 id | 1.0 `PROTOCOL.md` §11.2 |
| `targetTileId` | string | 是 | — | 目标地块 id | 同上 |

- **result**：`CombatResult` = `{success, outcome, message, attackerPower, defenderPower, rounds, attackerWon, casualties[], capturedIds[], winChance, ranged, retaliationPower, xpAwarded, notes[]}`。
- **view**：是。
- **events**：战斗事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R5。
- **状态**：待实现（R5）。
- **出处**：1.0 `PROTOCOL.md` §11.2；`COMMAND_MAP.md` §2；2.0 PRD §5.2 #1（2.0 默认可直接攻击，不再要求先宣战）。

### `queryAttackPreview`

- **用途**：攻击预览（胜率 / 损耗 / 地形修正）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 攻方弟子 id | 1.0 `PROTOCOL.md` §11.2 |
| `targetTileId` | string | 是 | — | 目标地块 id | 同上 |

- **result**：`BattlePreview` 全字段 + `targetTileId` = `{attackable, blockedReason, attackerId, defenderId, attackerClass, defenderClass, attackerPower, defenderPower, counterMultiplier, winChance, ranged, beyondMeleeContact, retaliationPower, distance, xpPreview, notes[]}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R5。
- **状态**：待实现（R5）。
- **出处**：1.0 `PROTOCOL.md` §11.2、§11.4；`COMMAND_MAP.md` §2。

### `queryAttackable`

- **用途**：查询弟子可攻击地块（攻击范围高亮）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.2 |

- **result**：`{discipleId, range, tileIds[], tileCount}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R5。
- **状态**：待实现（R5）。
- **出处**：1.0 `PROTOCOL.md` §11.2；`COMMAND_MAP.md` §2。

### `retreat`

- **用途**：战败撤退到指定地块。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |
| `toTileId` | string | 是 | — | 撤退目标地块 id | 同上 |

- **result**：`CombatResult`（字段同 `attack`）。
- **view**：是。
- **events**：撤退事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R5。
- **状态**：待实现（R5）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2。

### `teleport`

- **用途**：把弟子传送到己方灵峰（首版跨越山岳的唯一手段）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |
| `targetPeakId` | string | 是 | — | 目标灵峰 id（1.0 `COMMAND_MAP.md` 记作 `peakId`，见 §11 冲突 #1） | 同上 |

- **result**：`MoveResult`。
- **view**：是。
- **events**：传送事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R5。
- **状态**：待实现（R5）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2。

### `queryTeleportOptions`

- **用途**：列出可传送的己方灵峰与花费、拦截原因。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{discipleId, found, enabled, capacity, remaining, fromPeakId, options:[{peakId, name, capital, level, allowed, blocker, cost}…]}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R5。
- **状态**：待实现（R5）。
- **出处**：1.0 `PROTOCOL.md` §11.5。

### `assignGarrison`

- **用途**：指派弟子驻守节点。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.2 |
| `nodeId` | string | 是 | — | 目标节点 id | 同上 |

- **result**：`MoveResult`。
- **view**：是。
- **events**：驻守事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R5。
- **状态**：待实现（R5）。
- **出处**：1.0 `PROTOCOL.md` §11.2；`COMMAND_MAP.md` §2。

### `withdrawGarrison`

- **用途**：撤回驻守的弟子。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.2 |

- **result**：`MoveResult`。
- **view**：是。
- **events**：撤回事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R5。
- **状态**：待实现（R5）。
- **出处**：1.0 `PROTOCOL.md` §11.2；`COMMAND_MAP.md` §2。

### `reclass`

- **用途**：练兵转职到指定兵种。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |
| `unitClass` | string | 是 | — | 兵种枚举名（`Enums.UnitClass.ALL`）；非法值 → `BAD_PARAMS` | 同上 |

- **result**：`TrainingResult`（字段形状见 §11 待办 #1）。
- **view**：是。
- **events**：转职事件。
- **errorCode**：`BAD_PARAMS`（兵种名非法，须严格比对枚举、不得借道 `UnitClass.from` 静默回退）、`NO_GAME`。
- **里程碑**：R5。
- **状态**：待实现（R5）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2。

### `promote`

- **用途**：消耗晋升点晋升弟子。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |
| `promotionId` | string | 是 | — | 晋升项 id（可选清单由 `queryDiscipleDetail.availablePromotions` 给出） | 同上 |

- **result**：`TrainingResult`（字段形状见 §11 待办 #1）。
- **view**：是。
- **events**：晋升事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R5。
- **状态**：待实现（R5）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2。

### `queryDiscipleDetail`

- **用途**：弟子详情面板数据。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.2 |

- **result**：`{found, id, name, realm, realmName, position, positionName, sectId, sectName, spiritRoots[], spiritRootNames[], spiritRootGrade, bloodLine, cultivationProgress, heartDevil, movePoints, maxMovePoints, strikesLeft, turnsInSect, unitClass, unitClassName, range, reclassCooldown, battleXp, battleLevel, promotionPoints, promotions[], promotionNames[], builderCharges, currentTileId, currentPeakId, currentPeakName, garrisonNodeId, garrisonNodeName, missionNodeId, missionNodeName, injured, tribulating, capturedFromSectId}`；弟子不存在时只有 `{found:false, discipleId}`。
- **result（2.0 只加字段）**：追加 `availablePromotions:[{id, name, description, minLevel}…]`、`availableUnitClasses:[{id, name, allowed, blocker}…]`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R5。
- **状态**：待实现（R5）。
- **出处**：1.0 `PROTOCOL.md` §11.2、§11.5；`COMMAND_MAP.md` §2。

### `foundSpiritPeak`

- **用途**：在目标地块开辟灵峰（建城）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 执行弟子 id | 1.0 `PROTOCOL.md` §11.2 |
| `tileId` | string | 是 | — | 目标地块 id | 同上 |

- **result**：`BuildResult` = `{success, message, projectId, turnsRequired, spiritPowerCost}`。
- **view**：是。
- **events**：建城事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.2；`COMMAND_MAP.md` §2；2.0 PRD §4.1.9（山岳不可建城、缺水提示）、§7（R3 服务端含「灵峰」）。

### `appointBuilder`

- **用途**：任命建造者（受命建造）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |
| `discipleId` | string | 是 | — | 弟子 id | 同上 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：任命事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2；2.0 PRD §7（R3 服务端含「改良」）。

### `rally`

- **用途**：集结部队到指定地块。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |
| `tileId` | string | 否 | — | 集结目标地块 id | 同上 |

- **result**：`{success:true, message}`（文案型命令）。
- **view**：是。
- **events**：集结事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2；2.0 PRD §7（R6 含「集结/回防」）。

### `returnToDefense`

- **用途**：全军回防。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{success:true, message}`（文案型命令）。
- **view**：是。
- **events**：回防事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2；2.0 PRD §7（R6 含「集结/回防」）。

### `tribulate`

- **用途**：让弟子渡劫飞升。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{success:true, message}`（文案型命令）。
- **view**：是。
- **events**：渡劫结果事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2；2.0 PRD §7（R7 含「tribulate/任命」）。

### `appointFengZhu`

- **用途**：任命峰主。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |
| `peakId` | string | 否 | — | 目标灵峰 id | 同上 |

- **result**：`AppointmentResult`（字段形状见 §11 待办 #1）。
- **view**：是。
- **events**：任命事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2。

### `appointZhangLao`

- **用途**：任命长老。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |
| `peakId` | string | 否 | — | 目标灵峰 id | 同上 |

- **result**：`AppointmentResult`（字段形状见 §11 待办 #1）。
- **view**：是。
- **events**：任命事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2。

### `appointZongZhu`

- **用途**：任命宗主。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |
| `peakId` | string | 否 | — | 目标灵峰 id | 同上 |

- **result**：`AppointmentResult`（字段形状见 §11 待办 #1）。
- **view**：是。
- **events**：任命事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2。

---

## 4. 城市 / 区域 / 改良（18 条）

### `constructBuilding`

- **用途**：在灵峰内建造建筑。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `peakId` | string | 是 | — | 灵峰 id | 1.0 `PROTOCOL.md` §11.3 |
| `buildingType` | string | 是 | — | 建筑枚举名（`Enums.Building.ALL`） | 同上 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：建造入队事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.3；`COMMAND_MAP.md` §3。

### `queryBuildOptions`

- **用途**：列出可建建筑、造价、工期与流派限制。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.3 |

- **result**：`{sectId, sectName, options:[{type, displayName, core, factionOnly, allowed, cost, baseCost, turns, materialCost{}, affordable}…]}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.3；`COMMAND_MAP.md` §3。

### `openCave`

- **用途**：由指定弟子开辟洞府。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `peakId` | string | 是 | — | 灵峰 id | 1.0 `PROTOCOL.md` §11.5 |
| `discipleId` | string | 是 | — | 开辟洞府的弟子 id（1.0 `COMMAND_MAP.md` 曾误注 `subPeakId`，以代码为准） | 同上 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：洞府开辟事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §3。

### `fortifyPeak`

- **用途**：灵峰防御加固。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `peakId` | string | 是 | — | 灵峰 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：加固事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §3。

### `foundDistrict`

- **用途**：在城市内为指定区域选址建造。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |
| `peakId` | string | 是 | — | 灵峰 id | 同上 |
| `districtTypeId` | string | 是 | — | 区域类型 id（可建类型由 `queryCityDetail.districtTypes` 给出） | 同上 |
| `tileId` | string | 是 | — | 选址地块 id | 同上 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：区域落成事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §3；2.0 PRD §4.1.9（区域地形邻接）。

### `queryDistrictSites`

- **用途**：列出区域候选地块与推荐位。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |
| `peakId` | string | 是 | — | 灵峰 id | 同上 |
| `districtTypeId` | string | 是 | — | 区域类型 id | 同上 |

- **result**：`{sectId, peakId, districtTypeId, sites:[{tileId, type, yield, adjacencyReasons[]}…], siteCount}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.5。

### `assignWorker`

- **用途**：指派劳力到地块。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `peakId` | string | 是 | — | 灵峰 id | 1.0 `PROTOCOL.md` §11.5 |
| `tileId` | string | 是 | — | 地块 id | 同上 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：指派事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §3。

### `unassignWorker`

- **用途**：撤下地块劳力。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `peakId` | string | 是 | — | 灵峰 id | 1.0 `PROTOCOL.md` §11.5 |
| `tileId` | string | 是 | — | 地块 id | 同上 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：撤下事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §3。

### `queryAssignableTiles`

- **用途**：列出可指派劳力地块。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `peakId` | string | 是 | — | 灵峰 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{peakId, tiles:[{tileId, q, r, terrain, danger, ownerSectId, nodeId, luxuryType}…], tileCount}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.5。

### `queryCityDetail`

- **用途**：城市面板数据（人口/粮食/安定/住房/工作格/区域）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `peakId` | string | 是 | — | 灵峰 id | 1.0 `PROTOCOL.md` §11.3 |

- **result**：`{found, peakId, name, level, capital, defense, qiYun, qiYunMax, population, food, stability, tileId, workedTileIds[], freeWorkers, sectId, sectName, housing, foodBalance, outputMultiplier, cityYield, districts[{id, name, type, typeName, level, populationAssigned, buildings[]}], builtDistrictCount}`；灵峰不存在时只有 `{found:false, peakId}`。
  > 1.0 该 result 另有 `loyalty` 字段；2.0 按 PRD §5.2 #3 裁剪忠诚/叛乱模块，故**不迁移**该字段（见 §11 冲突 #3）。
- **result（2.0 只加字段）**：追加 `districtTypes:[{id, name}…]`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.3、§11.5；`COMMAND_MAP.md` §3。

### `buildImprovement`

- **用途**：派遣弟子在目标地块修筑改良。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.3 |
| `discipleId` | string | 是 | — | 弟子 id | 同上 |
| `tileId` | string | 是 | — | 地块 id | 同上 |
| `improvementType` | string | 是 | — | 改良枚举名（`Enums.Improvement.ALL`）；非法值 → `BAD_PARAMS` | 同上 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：改良入队事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.3；`COMMAND_MAP.md` §3；2.0 PRD §4.1.9（改良地形限制）。

### `repairImprovement`

- **用途**：修缮受损改良。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.3 |
| `discipleId` | string | 是 | — | 弟子 id | 同上 |
| `tileId` | string | 是 | — | 地块 id | 同上 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：修缮事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.3；`COMMAND_MAP.md` §3。

### `queryImprovementOptions`

- **用途**：列出某地块可建改良项（含修缮）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.3 |
| `tileId` | string | 是 | — | 地块 id | 同上 |

- **result**：`{sectId, tileId, broken:{id,type,displayName}|null, options:[{type, displayName, cost, yieldText, buildable, rejection}…]}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：待实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.3；`COMMAND_MAP.md` §3。

### `researchDao`

- **用途**：研究指定道法（入研究队列）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.3 |
| `daoId` | string | 是 | — | 道法 id（21 条道法树） | 同上 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：研究入队事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R4。
- **状态**：待实现（R4）。
- **出处**：1.0 `PROTOCOL.md` §11.3；`COMMAND_MAP.md` §3；2.0 PRD §7（R4）。

### `holdRecruitment`

- **用途**：举办收徒大典。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `peakId` | string | 是 | — | 灵峰 id | 1.0 `PROTOCOL.md` §11.3 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：收徒事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R4。
- **状态**：待实现（R4）。
- **出处**：1.0 `PROTOCOL.md` §11.3；`COMMAND_MAP.md` §3；2.0 PRD §7（R4）。

### `queryProjectQueue`

- **用途**：查询灵峰项目队列与研究队列。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `peakId` | string | 是 | — | 灵峰 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{peakId, found, peakName, projects:[…], researchQueue:[…]}`；项目项 `{id, type, name, turnsRequired, turnsRemaining, spiritPowerCost, targetId, discipleId, buildingType, districtType}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R4。
- **状态**：待实现（R4）。
- **出处**：1.0 `PROTOCOL.md` §11.5；2.0 PRD §7（R4）。

### `cancelProject`

- **用途**：取消项目队列中的项目。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `peakId` | string | 是 | — | 灵峰 id | 1.0 `PROTOCOL.md` §11.5 |
| `projectId` | string | 是 | — | 项目 id | 同上 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：取消事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R4。
- **状态**：待实现（R4）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §3；2.0 PRD §7（R4）。

### `accelerateProject`

- **用途**：花灵石加速项目（可作用于研究队列）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `peakId` | string | 否 | — | 灵峰 id；`research=true` 时省略 | 1.0 `PROTOCOL.md` §11.5 |
| `projectId` | string | 是 | — | 项目 id | 同上 |
| `turns` | int | 是 | — | 加速回合数 | 同上 |
| `research` | bool | 否 | `false` | 是否作用于研究队列 | 同上 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：加速事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R4。
- **状态**：待实现（R4）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §3（参数顺序与本文不同，见 §11 冲突 #4）。

---

## 5. 探索（4 条）

### `queryJiYuanInfo`

- **用途**：查询机缘节点信息。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `nodeId` | string | 是 | — | 节点 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{nodeId, kind:"jiYuan", found, info:NodeInfo}`（`NodeInfo` 形状见 §11 待办 #2）。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §4。

### `sendToJiYuan`

- **用途**：派遣弟子前往机缘。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |
| `nodeId` | string | 是 | — | 节点 id | 同上 |

- **result**：`ExploreResult`（字段形状见 §11 待办 #1）。
- **view**：是。
- **events**：探索事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §4。

### `queryMiJingInfo`

- **用途**：查询秘境节点信息。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `nodeId` | string | 是 | — | 节点 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{nodeId, kind:"miJing", found, info:NodeInfo}`（`NodeInfo` 形状见 §11 待办 #2）。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §4。

### `exploreMiJing`

- **用途**：派遣多名弟子探索秘境。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleIds` | string[] | 是 | — | 弟子 id 列表 | 1.0 `PROTOCOL.md` §11.5 |
| `nodeId` | string | 是 | — | 节点 id | 同上 |

- **result**：`ExploreResult`（字段形状见 §11 待办 #1）。
- **view**：是。
- **events**：探索事件（含伤亡）。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §4。

---

## 6. 政令（4 条）

### `switchGovernment`

- **用途**：更换政体（有切换冷却）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |
| `governmentId` | string | 是 | — | 政体 id（3 政体） | 同上 |

- **result**：`{success:true, message}`（1.0 `COMMAND_MAP.md` 记作 `PolicyResult`，形状未给，见 §11 待办 #1）。
- **view**：是。
- **events**：政体切换事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §5；2.0 PRD §7（R6）。

### `enactPolicy`

- **用途**：颁布政令卡。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |
| `cardId` | string | 是 | — | 政令卡 id（2.0 共 8 张） | 同上 |

- **result**：`{success:true, message}`。
- **view**：是。
- **events**：政令颁布事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §5（参数名记作 `policyId`，见 §11 冲突 #5）。

### `revokePolicy`

- **用途**：废除已颁布的政令卡。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |
| `cardId` | string | 是 | — | 政令卡 id | 同上 |

- **result**：`{success:true, message}`。
- **view**：是。
- **events**：政令废除事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §5（参数名记作 `policyId`，见 §11 冲突 #5）。

### `queryPolicyOptions`

- **用途**：政令面板数据（政体/政令列表 + 效果文案）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{sectId, enabled, found, governmentId, governmentName, switchCooldownLeft, eraIndex, effects{}, lines[], governments[{id,name,description,current,allowed,blocker,slots{},effectsText}…], cards[{id,name,category,categoryLabel,description,unlockEra,enacted,allowed,blocker,usedSlots,effectsText}…]}`。
  > 2.0 按 PRD §5.2 #4 删除 2 张外交卡，`category=diplomacy` 不再出现；`loyalty` 效果改落 `stability`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §5；PRD §5.2 #4。

---

## 7. 自动化 / 设置（6 条）

### `setAutomationToggle`

- **用途**：开关某项自动化。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |
| `key` | string | 是 | — | 自动化项：`improve` / `repair` / `road` / `explore`；其余 → `BAD_PARAMS` | 同上 |
| `on` | bool | 是 | — | 开 / 关 | 同上 |

- **result**：`{success:true, message}`（文案型命令）。
- **view**：是。
- **events**：自动化开关事件。
- **errorCode**：`BAD_PARAMS`（key 非法）、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §7。

### `setPeakAutoProject`

- **用途**：单峰自动项目开关。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `peakId` | string | 是 | — | 灵峰 id | 1.0 `PROTOCOL.md` §11.5 |
| `on` | bool | 是 | — | 开 / 关 | 同上 |

- **result**：`{success:true, message}`。
- **view**：是。
- **events**：自动化开关事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §7。

### `setAllAutoProject`

- **用途**：全峰自动项目开关。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |
| `on` | bool | 是 | — | 开 / 关 | 同上 |

- **result**：`{success:true, message}`。
- **view**：是。
- **events**：自动化开关事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §7。

### `exploreNow`

- **用途**：立即触发一次探索。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{success:true, message}`（文案型命令）。
- **view**：是。
- **events**：探索事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §7。

### `queryAutomationState`

- **用途**：查询自动化开关状态。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{sectId, enabled, found, autoImprove, autoRepair, autoRoad, autoExplore, summary, peaks:[{peakId, name, autoProject}…]}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §7。

### `setSetting`

- **用途**：设置动画/自动播放/快速结算等**客户端本地**偏好；服务端只确认，值留在前端。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `key` | string | 是 | — | 设置项名 | 1.0 `PROTOCOL.md` §11.5 |
| `value` | any | 是 | — | 设置值 | 同上 |

- **result**：`{success:true, key, value, applied:false, note}`。
- **view**：否（只读，不改 `GameState`）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`。
- **里程碑**：R6。
- **状态**：待实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5、`COMMAND_MAP.md` §7、`COMMAND_MAP.md` §11.2 #5；PRD §6.7（标注「客户端本地，不回 view」）。

---

## 8. 待抉择（2 条）

### `queryVictoryChoice`

- **用途**：查询待择的胜利路线。
- **params**：无。
- **result**：`{pending, gameOver, winnerSectId, winType, options[…]}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`NO_GAME`。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §8。

### `resolveChoice`

- **用途**：待抉择统一入口；按 `reqId` 前缀分派（2.0 仅 `req_victory_*`）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `reqId` | string | 是 | — | `awaitInput` 携带的待决请求 id | PRD §6.3 |
| `optionIndex` | int | 是 | — | 选项下标 | 同上 |

- **result**：`{success, routeId, winType, message}`。
- **view**：是。
- **events**：结局事件。
- **errorCode**：`BAD_PARAMS`（`optionIndex` 越界 / `reqId` 认不出，**且待决状态原样保留**）。
- **里程碑**：R7。
- **状态**：待实现（R7）。
- **出处**：PRD §6.3、§5.2 #7；1.0 `PROTOCOL.md` §4.4、§11.5。

---

## 9. 附：ping

### `ping`

- **用途**：连通性与握手自检；不带 `view`，不改任何游戏状态。
- **params**：无。
- **result**：`{"pong": true}`。
- **view**：否。
- **events**：`[]`。
- **errorCode**：`BAD_JSON` / `NO_ID` / `BAD_REQUEST`（信封层错误）。
- **里程碑**：R0（协议管道命令，任何里程碑都可用）。
- **状态**：已实现。
- **出处**：2.0 代码 `server/scripts/net/CommandDispatcher.gd` `_handle_ping`；`shared/protocol/commands.gd` `PING`。

---

## 10. 已裁剪命令（19 条）

> 按 PRD §5.1 裁剪，**不出现在 §2–§9 正文**，亦不提供 `params`/`result`。合计 19 条（1.0 共 88 条 → 2.0 保留 69 条 + `ping`）。

| # | 命令名 | 所属模块 | 删除原因 |
|---|---|---|---|
| 1 | `queryCasusBelli` | 外交/厌战 | PRD §5.1：外交模块整体裁剪 |
| 2 | `declareWar` | 外交/厌战 | 同上；2.0 默认可自由攻击（PRD §5.2 #1） |
| 3 | `makePeace` | 外交/厌战 | 同上 |
| 4 | `trade` | 外交/厌战 | 同上 |
| 5 | `signNonAggressionPact` | 外交/厌战 | 同上 |
| 6 | `formAlliance` | 外交/厌战 | 同上 |
| 7 | `offerVassalage` | 外交/厌战 | 同上 |
| 8 | `breakTreaty` | 外交/厌战 | 同上 |
| 9 | `releaseCaptives` | 外交/厌战 | 同上 |
| 10 | `queryDiplomacyOverview` | 外交/厌战 | 同上 |
| 11 | `clearLair` | 蛮族巢穴 | PRD §5.1：世界威胁模块裁剪 |
| 12 | `queryClearBlocker` | 蛮族巢穴 | 同上 |
| 13 | `queryLairInfo` | 蛮族巢穴 | 同上 |
| 14 | `resolveDisaster` | 灾劫 | PRD §5.1：独立灾劫系统移除（秘境内部风险保留） |
| 15 | `queryThreatOverview` | 威胁总览 | PRD §5.1：巢穴/灾异/民心/外交聚合移除 |
| 16 | `giftLoyalty` | 忠诚/叛乱 | PRD §5.1、§5.2 #3：忠诚模块裁剪 |
| 17 | `queryLoyaltyGiftBlocker` | 忠诚/叛乱 | 同上 |
| 18 | `queryPendingEvent` | 随机事件 | PRD §5.1：事件库裁剪 |
| 19 | `resolvePendingEvent` | 随机事件 | 同上；`resolveChoice` 保留但只分派 `req_victory_*` |

> `ping` 不属玩法命令，未计入 88 条。

---

## 11. 冲突与待办清单

> 本节是本文档的**诚实边界**：凡 1.0 与 2.0 口径不一致、或权威源未给出形状之处，逐条列出，**不做私自调和**。
> `TODO(需核对)` 标记总数由 `tools/check_protocol.ps1` 统计并打印（不判失败）。

### 11.1 冲突（1.0 与 2.0 口径不一致，已按 2.0 处理并在此登记）

| # | 项 | 1.0 | 2.0（本文采用） | 依据 |
|---|---|---|---|---|
| 1 | `teleport` 目标峰字段名 | `COMMAND_MAP.md` 记 `peakId`；`PROTOCOL.md` §11.5 记 `targetPeakId` | 采用 `targetPeakId`（1.0 唯一给出 `result` 的源为 `PROTOCOL.md`） | 权威层级：`PROTOCOL.md` §11 优先于 `COMMAND_MAP.md` 概览列 |
| 2 | `queryTeleportOptions` params | `COMMAND_MAP.md` 记 `discipleId, peakId`；`PROTOCOL.md` §11.5 记 `discipleId` | 采用 `discipleId` | 同上 |
| 3 | `queryCityDetail.loyalty` | 1.0 result 含 `loyalty` | **移除**（忠诚模块已裁剪） | PRD §5.1、§5.2 #3 |
| 4 | `accelerateProject` params 顺序/可选性 | `COMMAND_MAP.md` 记 `peakId, projectId, research, turns`；`PROTOCOL.md` §11.5 记 `[peakId,] projectId, turns[, research]` | 采用 `PROTOCOL.md`（`peakId` 在研究队列时可省） | 权威层级同上 |
| 5 | `enactPolicy`/`revokePolicy` 参数名 | `COMMAND_MAP.md` 记 `policyId`；`PROTOCOL.md` §11.5 记 `cardId` | 采用 `cardId` | 同上 |
| 6 | 开战前置 | 1.0 攻击需先宣战 | 2.0 默认可直接攻击任何非己方单位/节点/灵峰 | PRD §5.2 #1 |
| 7 | `awaitInput.kind` | `randomEvent` + `victoryChoice` | 仅 `victoryChoice` | PRD §5.2 #7 |
| 8 | `view` 顶层结构 | `PROTOCOL.md` §5 列 `turn…eventLog` | 2.0 实际另含 `metadata{}`、`visibleTiles[]`、`exploredTiles[]`、`renderHints{}`（见 §12） | 2.0 代码 `StateView.build` 优先于 PRD §6.5 的字段清单 |
| 9 | 只读命令条数 | `PROTOCOL.md` §9 自述 28 条，但 `Protocol.java` 实为 29 条（含 `setSetting`） | 2.0 去裁剪后为 **22 条**（见 §1「只读」列） | 1.0 源自身不自洽，已按实际枚举重算并登记 |
| 10 | 里程碑归属：`foundSpiritPeak`/`appointBuilder` | — | 本文归 R3（PRD §7 R3 服务端含「灵峰」「改良」） | PRD §7 |
| 11 | 里程碑归属：`researchDao`/`holdRecruitment`/`queryProjectQueue`/`cancelProject`/`accelerateProject` | — | 本文归 R4（PRD §7 R4 明列），而非 R3 的「城市 18 条」分组标签 | PRD §7 R4 明列优先于分组标签 |
| 12 | 险地附加移动代价 `map.dangerTileMoveCost` | 1.0 `HexUtils.getMoveCost()` 记「基础 1 + 险地 2」= 进入险地共 2 点 | 2.0 按 PRD §4.1.8 **叠加公式**，该键语义改为「进入险地格的**附加**代价」，取 **1**；`data/gameConfig.json` 由 `2` 改为 `1`（R2 裁决二，R1 无任何规则代码读取该键，改值安全） | PRD §4.1.8；R2 提示词裁决二 |

### 11.2 待办（`TODO(需核对)`：权威源未给出形状，禁止臆造）

| # | 项 | 现状 | 需要什么 |
|---|---|---|---|
| 1 | `TrainingResult` / `AppointmentResult` / `ExploreResult` / `PolicyResult` 的字段形状 | 1.0 `PROTOCOL.md` §11 只给出类型名，未列字段；`COMMAND_MAP.md` 亦未展开 | `TODO(需核对)`：回 1.0 `bridge/CommandDispatcher.java` 或对应门面类核对字段后再补 |
| 2 | `NodeInfo`（`queryJiYuanInfo`/`queryMiJingInfo` 的 `info`） | 1.0 仅给类型名 | `TODO(需核对)`：同上 |
| 3 | `queryVictoryProgress.routes[].goals` 内部形状 | 1.0 只给到 `goals` 一层 | `TODO(需核对)` |
| 4 | `queryPolicyOptions.effects{}` / `governments[].slots{}` 内部形状 | 1.0 只给到一层 | `TODO(需核对)` |
| 5 | 地形 blocker 的归属 | PRD §6.7 末注：山岳不可建城/不可通行、雾泽、缺水由 `querySpiritPeakBlocker` / `queryBuildOptions` / `queryMoveRange` 返回 | `TODO(需核对)`：`querySpiritPeakBlocker` **不在 69 条命令清单内**（PRD §6.7 未登记），需确认它是否为新增命令或应并入 `queryBuildOptions`；本文**不新增命令**，故仅在 `foundSpiritPeak`/`queryMoveRange` 的说明中引用该语义 |
| 6 | `awaitInput.options` 的 `routeId`/`description` 之外是否另有字段 | PRD §6.3 给出 `routeId`/`description` | 已按 PRD §6.3 落地，无 TODO |

---

## 12. view 快照结构

> **唯一权威：2.0 代码 `server/scripts/net/StateView.gd` + `server/scripts/model/*.gd`。**
> 与 PRD §6.5 的字段清单存在差异（2.0 实现多出 `metadata`/`visibleTiles`/`exploredTiles`/`renderHints`），见 §11 冲突 #8。

### 12.1 顶层字段（`StateView.build` 实际输出）

| 字段 | 类型 | 说明 | 出处 |
|---|---|---|---|
| `turn` | int | 当前回合 | `GameState.turn` |
| `phase` | string | 回合阶段（`Enums.TurnPhase.ALL`：`TURN_START`/`SPIRIT_PEAK`/`PLAYER_ACTION`/`SETTLEMENT`/`AI_ACTION`/`VICTORY_CHECK`） | `GameState.phase` |
| `mapWidth` / `mapHeight` | int | 地图宽高 | `GameState.width`/`height` |
| `playerSectId` | string | 玩家宗门 id | `GameState.playerSectId` |
| `randomSeed` | string | 种子（**以十进制字符串下发**，64 位语义） | `GameState.seed` |
| `difficultyId` | string | 难度 | `GameState.difficulty` |
| `gameOver` | bool | 是否终局 | `GameState.gameOver` |
| `winType` | string | 胜利类型（R1 恒为 `""`，R7 落地） | `StateView.build` |
| `winnerSectId` | string | 胜者宗门 id（R1 恒为 `""`） | 同上 |
| `pendingVictoryChoices` | array | 待择胜利路线（R1 恒为 `[]`） | 同上 |
| `tiles` | **object**（键 = tileId） | 地块；未探索格除 `id`/`q`/`r` 外全为 `null`（防泄露） | `StateView.build` + `HexTile.to_dict` |
| `nodes` | **object**（键 = nodeId） | 节点；敌方/中立节点剔除 `reserve`/`output`/`cooldown` | `GameNode.to_dict` |
| `improvements` | **object** | 改良（R1 恒为 `{}`，R3 落地） | `StateView.build` |
| `sects` | **array** | 宗门；含嵌套 `disciples[]` / `spiritPeaks[]` | `Sect` + `StateView.build` |
| `visibleTiles` | string[] | 当前可见地块 id（迷雾三态权威来源） | `Sect.visibleTiles` |
| `exploredTiles` | string[] | 曾探索地块 id | `Sect.exploredTiles` |
| `eventLog` | string[] | 事件日志 | `GameState.eventLog` |
| `metadata` | object | 上述若干字段的副本（`turn`/`phase`/`mapWidth`/`mapHeight`/`playerSectId`/`randomSeed`/`difficultyId`） | `StateView.build` |
| `renderHints` | object | `{reliefHeight:{FLAT,HILL,MOUNTAIN}}`，供客户端起伏渲染 | `StateView.build` |

> **2.0 已删除**的 1.0 顶层字段：`relations`、`lairs`、`disasters`（PRD §6.5）。

### 12.2 `tiles[tileId]` 字段（`HexTile.to_dict`）

`id, q, r, baseTerrain, relief, features[], riverEdges[], danger, ownerSectId, nodeId, districtId, workedByPeakId, improvementId, luxuryType`

- `baseTerrain` ∈ `Enums.BaseTerrain.ALL`（`LING_FIELDS`/`SPIRIT_PLAIN`/`BARREN`）
- `relief` ∈ `Enums.Relief.ALL`（`FLAT`/`HILL`/`MOUNTAIN`）
- `features` ⊆ `Enums.Feature.ALL`（`SPIRIT_FOREST`/`MIRE`，首版至多 1 个）
- `riverEdges`：0..5 中为河流的**边**索引（河是边不是格）

### 12.3 `nodes[nodeId]` 字段（`GameNode.to_dict`）

`id, type, tileId, ownerSectId, level, reserve, output, cooldown`

- `type` ∈ `Enums.NodeType.ALL`（`LING_TIAN`/`LING_MAI`/`JI_YUAN`/`MI_JING`/`LING_QUAN`/`LING_FENG`）
- 敌方/中立节点下发时剔除 `reserve`/`output`/`cooldown`（内部信息）

### 12.4 `sects[i]` 字段

公共字段（`Sect.public_info`）：`id, name, factionType, player`
追加字段（`StateView.build`）：

| 字段 | 说明 |
|---|---|
| `disciples[]` | 己方全部弟子；敌方弟子仅在其所在格可见时下发 |
| `spiritPeaks[]` | 己方灵峰实时；敌方灵峰按「可见实时 / 记忆冻结快照」下发，冻结态剔除 `fengZhuId` |
| `resources{}` | **仅己方宗门**下发（`Enums.ResourceKind.ALL`） |

`disciples[j]`（`Disciple.to_dict`）：`id, name, sectId, tileId, realm, position, rootGrade, spiritRoots[], unitClass, movePoints, attacksRemaining, assignedPeakId, bloodLine, generation, directLine, heartDevil, injured, cultivationProgress`

`spiritPeaks[k]`（`SpiritPeak.to_dict`）：`id, name, sectId, tileId, capital, level, population, capacity, defense, qiYun, qiYunMax, stability, housing, fengZhuId, buildings{}, districts[]`

### 12.5 不下发的内部字段

| 字段 | 归属 | 不下发理由 |
|---|---|---|
| `tileSnapshots` / `nodeSnapshots` / `peakSnapshots` | `Sect` | 迷雾「记忆态」内部缓存；客户端只需 `visibleTiles`/`exploredTiles` |
| `policyCarry` / `lastPolicySwitchTurn` / `lastEventTurn` | `Sect` | 结算中间态与冷却记账（R6 落地） |
| `lastReproduceTurn` | `Disciple` | 繁衍冷却记账（R4 落地） |

> 出处：1.0 `PROTOCOL.md` §5.1；2.0 `StateView.build` 未输出上述字段（R1 已实证）。

### 12.6 迷雾下发规则（PRD §4.2）

- 地形/地貌/河流/节点一旦 `explored` **永久保留**；未探索格不下发任何地形信息。
- 己方实体（己方灵峰所在地块、己方归属地块、己方节点所在地块）**实时下发**，不受记忆快照冻结。
- 敌方单位仅在可见格下发；敌方城市/建筑/改良/领地在可见格实时、在 mid-fog 格**冻结为最后可见快照**。
