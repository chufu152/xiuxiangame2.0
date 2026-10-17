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
| `awaitInput` | 已实现（R7，仅 `victoryChoice`） | `{type,reqId,kind:"victoryChoice",prompt,options[{index,label,routeId,description}]}` | PRD §6.3、§5.2 #7 |
| `snapshot` / `event` | 不采用 | 2.0 以「每条命令回包带全量 `view` + `events` 增量」替代 | PRD §6.2 |

> 1.0 的 `awaitInput.kind` 有 `randomEvent` / `victoryChoice` 两种；2.0 **只保留 `victoryChoice`**（PRD §5.2 #7），`resolveChoice` 只分派 `req_victory_*`。

---

## 1. 命令总表

**69 条 + `ping`**。分组点数：会话 13 / 单位 22 / 城市·区域·改良 18 / 探索 4 / 政令 4 / 自动化·设置 6 / 待抉择 2 = **69**。

「回 view」= 成功响应是否携带全量快照。「状态」= 已实现 / 待实现（R*）。

> 截至 R7 已实现 **69 条 + `ping`**（`CommandDispatcher.implemented_commands()` 共 **70** 项）：PRD §6.7 的 69 条**全部落地**，**无待实现**。

### 会话与存档（13）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `newGame` | 会话 | R1 | 是 | 否 | 已实现 |
| `getState` | 会话 | R1 | 是 | 否 | 已实现 |
| `finishTurn` | 会话 | R2 | 是 | 否 | 已实现（R2） |
| `beginPlayerTurn` | 会话 | R2 | 是 | 否 | 已实现（R2） |
| `nextTurn` | 会话 | R2 | 是 | 否 | 已实现（R2） |
| `listSaves` | 会话 | R7 | 否 | 是 | 已实现（R7） |
| `saveGame` | 会话 | R7 | 否 | 否 | 已实现（R7） |
| `loadGame` | 会话 | R7 | 是 | 否 | 已实现（R7） |
| `queryVictoryProgress` | 会话 | R7 | 否 | 是 | 已实现（R7） |
| `checkVictory` | 会话 | R7 | 否 | 是 | 已实现（R7） |
| `checkDefeat` | 会话 | R7 | 否 | 是 | 已实现（R7） |
| `chooseVictory` | 会话 | R7 | 是 | 否 | 已实现（R7） |
| `queryGameOver` | 会话 | R7 | 否 | 是 | 已实现（R7） |

### 单位（22）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `moveDisciple` | 单位 | R2 | 是 | 否 | 已实现（R2） |
| `queryMoveRange` | 单位 | R2 | 否 | 是 | 已实现（R2） |
| `batchMove` | 单位 | R5 | 是 | 否 | 已实现（R5） |
| `attack` | 单位 | R5 | 是 | 否 | 已实现（R5） |
| `queryAttackPreview` | 单位 | R5 | 否 | 是 | 已实现（R5） |
| `queryAttackable` | 单位 | R5 | 否 | 是 | 已实现（R5） |
| `retreat` | 单位 | R5 | 是 | 否 | 已实现（R5） |
| `teleport` | 单位 | R5 | 是 | 否 | 已实现（R5） |
| `queryTeleportOptions` | 单位 | R5 | 否 | 是 | 已实现（R5） |
| `assignGarrison` | 单位 | R5 | 是 | 否 | 已实现（R5） |
| `withdrawGarrison` | 单位 | R5 | 是 | 否 | 已实现（R5） |
| `reclass` | 单位 | R5 | 是 | 否 | 已实现（R5） |
| `promote` | 单位 | R5 | 是 | 否 | 已实现（R5） |
| `queryDiscipleDetail` | 单位 | R5 | 否 | 是 | 已实现（R5） |
| `foundSpiritPeak` | 单位 | R3 | 是 | 否 | 已实现（R3） |
| `appointBuilder` | 单位 | R3 | 是 | 否 | 已实现（R3） |
| `rally` | 单位 | R6 | 是 | 否 | 已实现（R6） |
| `returnToDefense` | 单位 | R6 | 是 | 否 | 已实现（R6） |
| `tribulate` | 单位 | R7 | 是 | 否 | 已实现（R7） |
| `appointFengZhu` | 单位 | R7 | 是 | 否 | 已实现（R7） |
| `appointZhangLao` | 单位 | R7 | 是 | 否 | 已实现（R7） |
| `appointZongZhu` | 单位 | R7 | 是 | 否 | 已实现（R7） |

### 城市 / 区域 / 改良（18）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `constructBuilding` | 城市 | R3 | 是 | 否 | 已实现（R3） |
| `queryBuildOptions` | 城市 | R3 | 否 | 是 | 已实现（R3） |
| `openCave` | 城市 | R3 | 是 | 否 | 已实现（R3） |
| `fortifyPeak` | 城市 | R3 | 是 | 否 | 已实现（R3） |
| `foundDistrict` | 城市 | R3 | 是 | 否 | 已实现（R3） |
| `queryDistrictSites` | 城市 | R3 | 否 | 是 | 已实现（R3） |
| `assignWorker` | 城市 | R3 | 是 | 否 | 已实现（R3） |
| `unassignWorker` | 城市 | R3 | 是 | 否 | 已实现（R3） |
| `queryAssignableTiles` | 城市 | R3 | 否 | 是 | 已实现（R3） |
| `queryCityDetail` | 城市 | R3 | 否 | 是 | 已实现（R3） |
| `buildImprovement` | 城市 | R3 | 是 | 否 | 已实现（R3） |
| `repairImprovement` | 城市 | R3 | 是 | 否 | 已实现（R3） |
| `queryImprovementOptions` | 城市 | R3 | 否 | 是 | 已实现（R3） |
| `researchDao` | 城市 | R4 | 是 | 否 | 已实现（R4） |
| `holdRecruitment` | 城市 | R4 | 是 | 否 | 已实现（R4） |
| `queryProjectQueue` | 城市 | R4 | 否 | 是 | 已实现（R4） |
| `cancelProject` | 城市 | R4 | 是 | 否 | 已实现（R4） |
| `accelerateProject` | 城市 | R4 | 是 | 否 | 已实现（R4） |

### 探索（4）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `queryJiYuanInfo` | 探索 | R6 | 否 | 是 | 已实现（R6） |
| `sendToJiYuan` | 探索 | R6 | 是 | 否 | 已实现（R6） |
| `queryMiJingInfo` | 探索 | R6 | 否 | 是 | 已实现（R6） |
| `exploreMiJing` | 探索 | R6 | 是 | 否 | 已实现（R6） |

### 政令（4）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `switchGovernment` | 政令 | R6 | 是 | 否 | 已实现（R6） |
| `enactPolicy` | 政令 | R6 | 是 | 否 | 已实现（R6） |
| `revokePolicy` | 政令 | R6 | 是 | 否 | 已实现（R6） |
| `queryPolicyOptions` | 政令 | R6 | 否 | 是 | 已实现（R6） |

### 自动化 / 设置（6）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `setAutomationToggle` | 自动化 | R6 | 是 | 否 | 已实现（R6） |
| `setPeakAutoProject` | 自动化 | R6 | 是 | 否 | 已实现（R6） |
| `setAllAutoProject` | 自动化 | R6 | 是 | 否 | 已实现（R6） |
| `exploreNow` | 自动化 | R6 | 是 | 否 | 已实现（R6） |
| `queryAutomationState` | 自动化 | R6 | 否 | 是 | 已实现（R6） |
| `setSetting` | 自动化 | R6 | 否 | 是 | 已实现（R6） |

### 待抉择（2）

| 命令名 | 分组 | 里程碑 | 回 view | 只读 | 状态 |
|---|---|---|---|---|---|
| `queryVictoryChoice` | 待抉择 | R7 | 否 | 是 | 已实现（R7） |
| `resolveChoice` | 待抉择 | R7 | 是 | 否 | 已实现（R7） |

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
- **状态**：已实现（R7）。
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
- **状态**：已实现（R7）。
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
- **状态**：已实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.1；`COMMAND_MAP.md` §1；PRD §6.3。

### `queryVictoryProgress`

- **用途**：查询某宗各胜利路线的进度。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 目标宗门 id | 1.0 `PROTOCOL.md` §11.1 |

- **result**：`{sectId, routes:[{route, achieved, ratio, summary, stage, score, goals}…]}`。
  - `route` ∈ `ZONG_MEN_DAOTONG`/`JIA_ZU_ASCENSION`/`GUO_JIA_UNIFICATION`/`SCORE_SUPREMACY`（= 1.0 `VictoryRoute.name()`）；
  - `ratio` = 各 goal 比例（**取最拖后腿一项**为 `min`，其余为均值；分数路线取 `min`）；
  - `summary` = 1.0 `getSummary()`（已达成给「已达成」，否则报最短板 `missingText`）；
  - `stage` ∈ `白手起家`/`初具规模`/`渐入佳境`/`大势已成`/`临门一脚`/`功成`（1.0 阈值 0/0.3/0.6/0.85/达成）；
  - `score` 仅分数路线非 `null`，其余为 `null`；
  - `goals[]` = **9 键** `{name, current, target, unit, description, ratio, met, missingText, valueText}`（见 §11.2 #3）。
- **view**：否（只读）。会顺带刷新 `sect.powerLevel` 派生缓存（1.0 既有行为）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R7。
- **状态**：已实现（R7）。
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
- **状态**：已实现（R7）。
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
- **状态**：已实现（R7）。
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
- **状态**：已实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §1、§8。

### `queryGameOver`

- **用途**：查询终局字段。
- **params**：无。
- **result**：`{turn, gameOver, winType, winnerSectId, pendingVictoryChoices[]}`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`NO_GAME`。
- **里程碑**：R7。
- **状态**：已实现（R7）。
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
- **状态**：已实现（R5）。
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
- **状态**：已实现（R5）。
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
- **状态**：已实现（R5）。
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
- **状态**：已实现（R5）。
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
- **状态**：已实现（R5）。
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
- **状态**：已实现（R5）。
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
- **状态**：已实现（R5）。
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
- **状态**：已实现（R5）。
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
- **状态**：已实现（R5）。
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
- **状态**：已实现（R5）。
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
- **状态**：已实现（R5）。
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
- **状态**：已实现（R5）。
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
- **状态**：已实现（R3）。
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
- **状态**：已实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2；2.0 PRD §7（R3 服务端含「改良」）。

### `rally`

- **用途**：集结部队到指定地块。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |
| `tileId` | string | 否 | — | 集结目标地块 id；缺省取本宗都城地块 | 同上 |

- **result**：`{success:true, message}`（文案型命令；**不含** `movedIds` 等明细，与 1.0 一致）。
  > 2.0 差异（§11.1 #27）：待集结弟子数 > `automation.rallyMaxDisciples` 时**直接返回 `success:false`** 并在 `message` 写明上限；1.0 是静默截断到上限后照常返回成功。
- **view**：是。
- **events**：集结事件（`[自动]` 前缀）。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：已实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2；2.0 PRD §7（R6 含「集结/回防」）。

### `returnToDefense`

- **用途**：全军回防。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{success:true, message}`（文案型命令）。
  > 2.0 差异（§11.1 #27）：与 `rally` 同一上限规则——待回防弟子数 > `automation.rallyMaxDisciples` 时**直接失败**，不静默截断。
- **view**：是。
- **events**：回防事件（`[自动]` 前缀）。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：已实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2；2.0 PRD §7（R6 含「集结/回防」）。

### `tribulate`

- **用途**：让弟子渡劫飞升。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{success, reason, chance, realm, heartDevil, fallen, message}`。
  六键取自 1.0 `DiscipleManager.tribulate` 的返回体，`message` 为 2.0 追加的中文文案：
  `chance` 为**服务端实算成功率**（`tribulationBaseSuccessChance` + 已解锁道法数×`tribulationDaoBonusPerUnlocked` + 灵根品级×`tribulationRootGradeBonusPerGrade`，夹在 0..1）；
  `realm` 为渡劫后境界（成功即 `HUA_SHEN`）；`heartDevil` 为渡劫后心魔值（失败 +`tribulationFailHeartDevil`）；
  `fallen=true` 表示按 `tribulationFailFallChance` 判定陨落。**业务失败仍是 `ok:true + success:false`**（如境界不足/资源不足），
  与 1.0 一致。
- **view**：是。
- **events**：渡劫结果事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R7。
- **状态**：已实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2；2.0 PRD §7（R7 含「tribulate/任命」）。

### `appointFengZhu`

- **用途**：任命峰主。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |
| `peakId` | string | 否 | — | 目标灵峰 id | 同上 |

- **result**：`{success, message}`（1.0 `entity/AppointmentResult.java` 只有这两个字段，见 §11.2 #1 / 裁决二；**不加** `discipleId`/`position`/`peakId`）。
- **view**：是。
- **events**：任命事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R7。
- **状态**：已实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2。

### `appointZhangLao`

- **用途**：任命长老。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |
| `peakId` | string | 否 | — | 目标灵峰 id | 同上 |

- **result**：`{success, message}`（1.0 `entity/AppointmentResult.java` 只有这两个字段，见 §11.2 #1 / 裁决二；**不加** `discipleId`/`position`/`peakId`）。
- **view**：是。
- **events**：任命事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R7。
- **状态**：已实现（R7）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §2。

### `appointZongZhu`

- **用途**：任命宗主。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |
| `peakId` | string | 否 | — | 目标灵峰 id | 同上 |

- **result**：`{success, message}`（1.0 `entity/AppointmentResult.java` 只有这两个字段，见 §11.2 #1 / 裁决二；**不加** `discipleId`/`position`/`peakId`）。
- **view**：是。
- **events**：任命事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R7。
- **状态**：已实现（R7）。
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
- **状态**：已实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.3；`COMMAND_MAP.md` §3。

### `queryBuildOptions`

- **用途**：列出可建建筑、造价、工期与流派限制。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.3 |

- **result**：`{sectId, sectName, options:[{type, displayName, core, factionOnly, allowed, cost, baseCost, turns, materialCost{}, affordable}…]}`。
  - `cost` / `turns` 为**按流派特性调整后的实际值**（宗门流副峰 −20%、营造 −30%；家族流建筑 +50%），
    `baseCost` 保留 `building.costs` 配置原值供 UI 对比。`affordable` 亦按 `cost` 判定（见 §11.1 #24）。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：已实现（R3）。
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
- **状态**：已实现（R3）。
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
- **状态**：已实现（R3）。
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
- **状态**：已实现（R3）。
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
- **状态**：已实现（R3）。
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
- **状态**：已实现（R3）。
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
- **状态**：已实现（R3）。
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
- **状态**：已实现（R3）。
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
- **状态**：已实现（R3）。
- **出处**：1.0 `PROTOCOL.md` §11.3、§11.5；`COMMAND_MAP.md` §3。

### `buildImprovement`

- **用途**：派遣弟子在目标地块修筑改良。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.3 |
| `discipleId` | string | 是 | — | 弟子 id | 同上 |
| `tileId` | string | 是 | — | 地块 id | 同上 |
| `improvementType` | string | 是 | — | 改良枚举名（`Enums.ImprovementType.ALL`）；非法值 → `BAD_PARAMS` | 同上 |

- **result**：`BuildResult`。
- **view**：是。
- **events**：改良入队事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R3。
- **状态**：已实现（R3）。
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
- **状态**：已实现（R3）。
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
- **状态**：已实现（R3）。
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
- **状态**：已实现（R4）。
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
- **状态**：已实现（R4）。
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
- **状态**：已实现（R4）。
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
- **状态**：已实现（R4）。
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
- **状态**：已实现（R4）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §3（参数顺序与本文不同，见 §11 冲突 #4）。

---

## 5. 探索（4 条）

### `queryJiYuanInfo`

- **用途**：查询机缘节点信息。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `nodeId` | string | 是 | — | 节点 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{nodeId, kind:"jiYuan", found, info}`；节点不存在或类型不符时 `found=false`、`info=null`。
  `NodeInfo`（§11.2 #2 已回填，1.0 `entity/NodeInfo.java` 九字段原样落地）：
  `{nodeId, name, type, level, requiredRealmLevel, cooldown, cost, maxParticipants, rewardPreview}`。
  机缘取 `requiredRealmLevel = level × explore.jiYuanThresholdPerNodeLevel`、`cost=0`、`maxParticipants=1`；
  `rewardPreview` 为中文预览串（如 `天晶x(2+灵根品级x1) + 道统点xN`）。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：已实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §4。

### `sendToJiYuan`

- **用途**：派遣弟子前往机缘。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleId` | string | 是 | — | 弟子 id | 1.0 `PROTOCOL.md` §11.5 |
| `nodeId` | string | 是 | — | 节点 id | 同上 |

- **result**：`ExploreResult`（§11.2 #1 已回填，1.0 `ExploreResult.java` 六字段）：
  `{success, message, rewards[], casualties[], injured[], cooldown}`。
  `rewards[]` 元素为 `Reward`：`{type, amount, materialId}`，`type` ∈ `SPIRIT_POWER` / `SPIRIT_STONES` / `RARE_MATERIAL` / `DAO_POINT`（机缘产出 `DAO_POINT` + `RARE_MATERIAL`）。
  `casualties[]` / `injured[]` 为弟子 id 字符串数组；`cooldown` 为本次探索后该节点的剩余冷却回合数（成败均计）。
- **view**：是。
- **events**：探索事件（含死亡/受伤/心魔）。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：已实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §4。

### `queryMiJingInfo`

- **用途**：查询秘境节点信息。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `nodeId` | string | 是 | — | 节点 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{nodeId, kind:"miJing", found, info}`；`found=false` 时 `info=null`。`NodeInfo` 同 `queryJiYuanInfo`；
  秘境取 `cost = explore.miJingCost`、`maxParticipants = explore.miJingMaxParticipants`、`requiredRealmLevel=0`。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：已实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §4。

### `exploreMiJing`

- **用途**：派遣多名弟子探索秘境。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `discipleIds` | string[] | 是 | — | 弟子 id 列表 | 1.0 `PROTOCOL.md` §11.5 |
| `nodeId` | string | 是 | — | 节点 id | 同上 |

- **result**：`ExploreResult`，字段同 `sendToJiYuan`；秘境「丰厚」产出 `RARE_MATERIAL` + `SPIRIT_STONES` + `DAO_POINT`。
  业务失败（冷却中 / 类型不符 / 空列表 / 超人数 / 跨宗门 / 弟子未站在节点格 / 灵石不足）一律 `success:false` + 中文 `message`，协议层仍 `ok:true`。
- **view**：是。
- **events**：探索事件（含伤亡）。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：已实现（R6）。
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

- **result**：`{success:true, message}`（1.0 `COMMAND_MAP.md` 记作 `PolicyResult`；§11.2 #1 已回填，实际恰为 `{success, message}` 两字段）。
  > 切换成功后 `Sect.lastPolicySwitchTurn = 当前回合`，冷却 `policy.governments[].switchCooldownTurns`；新政权体槽位少于已颁卡数时**自动废止溢出的卡**并在 `message` 逐条写明（`PolicyRules.trim_policies_to_slots`）。
- **view**：是。
- **events**：政体切换事件。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：已实现（R6）。
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
- **状态**：已实现（R6）。
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
- **状态**：已实现（R6）。
- **出处**：1.0 `PROTOCOL.md` §11.5；`COMMAND_MAP.md` §5（参数名记作 `policyId`，见 §11 冲突 #5）。

### `queryPolicyOptions`

- **用途**：政令面板数据（政体/政令列表 + 效果文案）。
- **params**：

| 字段 | 类型 | 必填 | 默认/缺省 | 含义 | 出处 |
|---|---|---|---|---|---|
| `sectId` | string | 是 | — | 宗门 id | 1.0 `PROTOCOL.md` §11.5 |

- **result**：`{sectId, enabled, found, governmentId, governmentName, switchCooldownLeft, eraIndex, effects{}, lines[], governments[{id,name,description,current,allowed,blocker,slots{},effectsText}…], cards[{id,name,category,categoryLabel,description,unlockEra,enacted,allowed,blocker,usedSlots,effectsText}…]}`。
  > 2.0 按 PRD §5.2 #4 删除 2 张外交卡，`category=diplomacy` 不再出现；`loyalty` 效果改落 `stability`。
  > `effects{}` 与 `governments[].slots{}` 的内部形状见 §11.2 #4（已回填）。`cards[]` **不含** `unlockDaoKey`——道法门控只在服务端 `PolicyRules.card_block_reason` 内判定，`blocker` 给中文原因，避免泄露未推演道法 id。
- **view**：否（只读）。
- **events**：`[]`。
- **errorCode**：`BAD_PARAMS`、`NO_GAME`。
- **里程碑**：R6。
- **状态**：已实现（R6）。
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
- **状态**：已实现（R6）。
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
- **状态**：已实现（R6）。
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
- **状态**：已实现（R6）。
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
- **状态**：已实现（R6）。
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
- **状态**：已实现（R6）。
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
- **状态**：已实现（R6）。
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
- **状态**：已实现（R7）。
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
- **状态**：已实现（R7）。
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
| 13 | 灵田梯田改良的道法门控键 `improvement.byType.LING_TIAN_TI_TIAN.requiredDaoKey` | 1.0 改良与道法用同名键 | 2.0 `requiredDaoKey` 约定取**道法 id**（对照 `JU_LING_ZHEN.requiredDaoKey = "ju_ling_zhen"`）；原值 `lingtian_ti` 是道法 `ling_tian_nong` 的 `UNLOCK_IMPROVEMENT` **效果简写 key**，非任何道法 id（悬空，会使灵田梯田永久不可建）。已修正为 `ling_tian_nong`（R3 预生成提示词复核时发现，R3 裁决一登记） | `data/gameConfig.json` `improvement.byType`；R3 提示词裁决一 |
| 14 | 改良枚举类名 `Enums.Improvement.ALL` | 1.0 `ImprovementType` 为独立枚举类 | 2.0 模型新增全局 `class_name Improvement`（`server/scripts/model/Improvement.gd`）与 R1 内层枚举类同名，触发 Godot「Class hides a global script class」，故 R1 内层枚举类**改名** `Enums.ImprovementType`；§4 `buildImprovement.improvementType` 的枚举引用同步为 `Enums.ImprovementType.ALL`（R3 任务 1 登记） | GDScript `class_name` 全局唯一；2.0 代码 `shared/protocol/enums.gd` |
| 15 | 区域枚举类名 `Enums.District` | 1.0 `DistrictType` 为独立枚举类 | 同 #14：R1 内层枚举类 `Enums.District` **改名** `Enums.DistrictType`（`ALL`/`NAMES`/`BUILDABLE` 取值不变），以让位 2.0 全局 `class_name District`（`server/scripts/model/District.gd`） | 同上 |
| 16 | `improvement` 对象字段 `networkLevel` | 1.0 `Improvement` 无该字段 | 2.0 **只加** `networkLevel`（青石道路网络等级缓存：`0`=无 / `1`=连 / `2`=枢纽），由 `RoadNetworkService.refresh()` 维护；随 `view.improvements{}` 与 `queryCityDetail` 相关查询下发 | 2.0 代码 `RoadNetworkService.gd`、`Improvement.to_dict` |
| 17 | `queryCityDetail.districts[].buildings` 元素类型 | 1.0 `District.buildings` 为 `List<BuildingType>` | 2.0 为**建筑类型字符串数组**（如 `["SHAN_MEN","CANG_JING_GE"]`），非对象数组 | 2.0 代码 `CityAction.query_city_detail` |
| 18 | 道法门控改良在 R3 不可建 | 1.0 改良门控与道法同里程碑生效 | 2.0 道法系统属 **R4**（R3 非目标），故 `ImprovementRules._has_unlocked_dao()` 在 R3 **恒返回 false**（`# TODO(R4)`）：`LING_TIAN_TI_TIAN`（需 `ling_tian_nong`）与 `JU_LING_ZHEN`（需 `ju_ling_zhen`）在 R3 `queryImprovementOptions.buildable=false`、`rejection` 提示「需道法」。**R4 已回填**：改为查 `Sect.unlockedDaoIds`（`requiredDaoKey` 约定取道法 id），两条改良随对应道法推演完成而可建 | R3 提示词「非目标」（道法属 R4）；2.0 代码 `ImprovementRules` |
| 19 | 海拔/河流产出加成的配置落点 | 1.0 `EconomyCalculator` 无「丘陵石+1」「沿河粮+1」实现（`grep foodBonus`/`HILL` 于 1.0 全仓无命中），该加成为 **2.0 PRD 新增** | 2.0 按 PRD 既有写法落为配置键：`map.relief[].yield`（形状对齐 `map.features[].yield`，`HILL` 取 `{spiritStones:1}`、`FLAT`/`MOUNTAIN` 空表，依据 PRD §4.1.3 表「丘陵…石 +1」）与 `map.river.foodBonus`（**该键 2.0 配置与 `ConfigValidator` 早已存在但此前无代码读取**，依据 PRD §4.1.5 L280「沿河地块：粮 +1」）。产出顺序 = 基底 → 海拔 → 地貌 → 河流 → 节点 → 改良（PRD §4.1.9 L315）。R3 收尾完善时回填，`EconomyRules.tile_yield_preview` 唯一出口 | PRD §4.1.3 / §4.1.5 L280 / §4.1.9 L315；2.0 代码 `EconomyRules`、`ConfigValidator` |
| 20 | 道法「时代未到」的判定公式 | 1.0 只有前置链，无独立时代门控（时代是展示分组） | PRD §4.9 给出 5 时代与分布但**未定义门控公式**。若取「同代才可研究」：炼气篇 3 条全解锁后宗门时代仍是炼气篇，筑基篇永久不可研究（**死锁**）。故 2.0 取 **`sect_era_index`（已解锁道法所属最高时代，无解锁时为 0）+ `ERA_LOOKAHEAD`(1)**：可研究「当前时代及其后一代」的道法。`DaoRules.ERA_LOOKAHEAD` 是唯一常量，不散落 | PRD §4.9（未定义 → 取不死锁的最窄解释）；2.0 代码 `DaoRules.can_research` |
| 21 | `researchDao` 的费用与工期语义 | 1.0 `BuildAction.researchDao`：**入队即扣道点**，`dao.spiritPowerCost` 实为**工力总额**，逐回合按 `ceil(总额/回合)` 从 `workPower` 扣，不足则项目暂停 | 2.0 完全沿用 1.0 口径。故 `BuildResult.spiritPowerCost` 对研究命令返回的是**工力总额**（不是灵力）；`queryProjectQueue.researchQueue[].spiritPowerCost` 同义。工期倍率 = `(1−宗门研究加速)×(1−长老数×zhangLaoResearchSpeedBonus)×(1−RESEARCH_BONUS)`，下限 `0.3`，与 1.0 同式 | 1.0 `BuildAction.researchDao/advanceProject`；2.0 代码 `DaoRules.research_turns`、`ProjectRules.advance_research` |
| 22 | `holdRecruitment` 落成人数公式 | 1.0 `completeRecruitment`：`recruitmentBaseCount + peak.level × recruitmentPerLevel`（1 级峰 = 3 人） | 2.0 按 R4 提示词取 **`recruitmentBaseCount + recruitmentPerLevel × (峰级 − 1)`**（1 级峰 = 2 人）。与 1.0 相差 1 人/次，属里程碑规格明示的差异，登记备查 | R4 提示词自动验收 #5；1.0 `BuildAction.completeRecruitment` |
| 23 | 道统成就「初探秘境」的判定语义 | 1.0 以「已探索地块中存在秘境节点」计数（`sect.exploredTiles` 含秘境节点所在格即算达成） | 该口径在 2.0 会**开局即成立**：出生点视野内常含秘境节点，导致第 1 回合白送 30 道点、且成就永久失效（R4 客户端端到端实测暴露，见 `R4_CLIENT_FAIL: 开局无任何 AVAILABLE 道法`）。故 2.0 改为**成功探索秘境次数** `Sect.miJingExploredTotal`（内部记账，不下发 view）：`exploreMiJing` 成功才递增，R5 落地该命令时回填；R4 期间恒为 `0`，成就不可触发。`ownLingMai`/`recruited`/`enemyDefeated` 三个成就的计数口径不受影响 | PRD §4.9「道统成就 boost（一次性道点奖励）」；2.0 代码 `DaoRules._boost_progress` |
| 24 | 三流派特性的落地口径 | 1.0 `GameConfig` 声明了 `faction.zongMen.*` / `jiaZu.*` / `guoJia.*` 全套字段，但**业务代码零引用**（`grep` 全仓仅命中 `GameConfig.java` 的 getter/setter）——即 1.0 从未实现流派特性 | 2.0 按 PRD §1.1 原文落地其中**口径明确**的 6 项，统一由 `FactionRules` 出口：① `zongMen.buildSpeedBonus` 营造工期 ×(1−0.3) 下限 1（「营造 +30%」）；② `zongMen.subPeakCostReduction` 4 种 `*_FEN_FENG` 造价 ×0.8（「副峰花费 −20%」）；③ `zongMen.uniqueBuildingDefenseBonus` 护山剑阵落成防御 +25（「落成防御 +25」）；④ `jiaZu.peakBuildCostPenalty` 建筑造价 ×1.5（「建峰花费 +50%」）；⑤ `jiaZu.bloodLineSpeedBonus` 血脉弟子修炼 ×1.4（「血脉修炼 +40%」）；⑥ `jiaZu.zuCiCultivationBonus` 本宗有祖祠时血脉弟子再 ×1.25（「祖祠修炼 +25%」）。**`zongMen.buildSpeedBonus` 与 `jiaZu.peakBuildCostPenalty` 互斥**（一宗一流派，用 if/elif 不累乘）；**开峰造价不叠乘**——`spiritPeak.foundCost` 表已内建流派差异（宗门 500 / 家族 800 / 国家 350），故 `jiaZu.foundCostPenalty`、`guoJia.foundCostReduction` 属**冗余键**，若再乘一次会双重计费 | PRD §1.1、§4.3 L348；2.0 代码 `FactionRules`、`CityAction`、`CityRules.can_build`、`DiscipleRules.cultivation_speed` |
| 25 | 地形防御 / 高台 / 河流三处「1.0 有实现但键名口径不同」的判定 | 1.0 各有一份实现，但都建立在**中文地形名**之上：① `CombatCalculator` 查 `terrainDefenseBonus{平原,险地}`（中文键）；② 高台加成判「攻方站在 `danger` 格」这一布尔；③ 河流减益判「地形名 ∈ `riverTerrains`」 | 2.0 的地形 id 是**英文枚举**（`FLAT/HILL/MOUNTAIN`、`SPIRIT_FOREST/MIRE`），1.0 的中文表**无法复用**，故三处一律改为读 2.0 自己的分层配置，并各自登记为语义差异：① **地形防御** = `map.relief[].defenseBonus` + `map.features[].defenseBonus` 累加，`danger` 格再取 `max(累加值, warfare.terrainDefenseBonus.danger)`（`UnitRules.terrain_defense_bonus`）；② **高台** 改判**海拔比较**（`map.relief[].height`：`FLAT` 1.0 / `HILL` 1.7 / `MOUNTAIN` 3.0），攻方海拔严格高于守方才加成（`UnitRules.high_ground_bonus`），不再是「站险地即加成」；③ **河流减益** 判**边**而非地形：读 `HexTile.riverEdges` 并经 `MoveRules.crosses_river` 判「攻方与守方之间是否隔河」（`UnitRules.river_penalty`）。三处均为 `CombatResolver._build_matchup` 的唯一来源，`preview()` 与 `attack()` 共用，故「预览=实战」结构性成立（R5 裁决三） | 2.0 `data/gameConfig.json` `map.relief`/`map.features`/`warfare.terrainDefenseBonus`；2.0 代码 `UnitRules`、`CombatResolver`、`MoveRules.crosses_river` |
| 26 | 探索/集结的随机源 | 1.0 `ExploreAction` 用 `MISSION_SEQ`（静态 `AtomicLong`）+ XOR 播种造伪随机 | 2.0 **全部改走 `GameState.rng`**（`RngService.next_float` / `chance`），与移动/战斗同一确定性源；同种子 + 同命令序列结果逐字节一致（`R6Test._test_determinism` 实证） | 确定性铁律（PRD §6.6）；2.0 `ExploreRules`、`AutomationRules` |
| 27 | `rally` / `returnToDefense` 超限行为 | 1.0 静默截断到 `rallyMaxDisciples` 后返回成功 | 2.0 **直接返回 `success:false`** 并在 `message` 写明上限，让玩家知道有一批人没动；命令 result 仍为 `{success, message}`（§11.2 #1） | PRD §7 R6「集结/回防」；避免「以为全军出动实则漏人」的静默行为 |
| 28 | `policy.effects{}` 四个百分比乘区的消费点 | 1.0 分散在 `EconomyCalculator`（`total *= 1 + outputBonus + spiritPowerBonus`）、`DiscipleManager`（`speed *= 1 + cultivationBonus`）、`CombatResolver`（`power *= 1 + combatBonus`）三处 | 2.0 同样三处接线：`EconomyRules.apply_settlement` 乘 `PolicyRules.output_multiplier()`（**只作用灵力总产出**，且在 deficit 判定之前），`DiscipleRules.cultivation_speed` 并入加性池，`CombatResolver.compute_power` 末尾乘法。三处在未颁任何加成卡时恒为恒等元（×1.0 / +0），故**不改变 R3/R4/R5 已验收的任何数值**；`policy.enabled=false` 时全部失效 | PRD §4.13 明列各卡「产出+15%/战力+10%/修炼+10%」；若只落 `stabilityPerTurn`/`prestigePerTurn`，8 张卡里 6 张的主效果颁了等于没颁 |
| 29 | `Disciple.missionNodeId` 的写入时机 | 1.0 该字段**只清不设**：`MoveAction.clearMissionIfLeft`（离开节点地块即清）与 `MoveAction.withdrawGarrison`（`missionNodeId != null` 时回「已撤回机缘/秘境任务」）都写好了，但全仓没有任何 setter 调用，故 1.0 里它恒为 `null`（`queryDiscipleDetail.missionNodeId` 永远为空） | 2.0 让字段真正有值：探索（机缘/秘境）后置为节点 id，按 1.0 的两条规则清除——`MoveAction.clear_mission_if_left()` 在每次移动到达后调用，`withdrawGarrison` 优先判任务节点。这样 `queryDiscipleDetail.missionNodeId/missionNodeName` 才有意义 | PROTOCOL §3 `queryDiscipleDetail` 声明了 `missionNodeId`/`missionNodeName`；1.0 的清理规则即为其语义定义 |
| 30 | 「探索面板显示成功率」不可实现（提示词内部冲突） | 1.0 `NodeInfo` 九字段**不含任何成功率**（`rewardPreview` 只是材料/道点预览串），`ExploreAction` 的成功率是服务端 `sendToJiYuan` 内部现算的 | 2.0 **面板不显示成功率**：`R6_探索政令自动化.md` 验收 11 要求「`queryJiYuanInfo` 显示成功率」，但硬约束 2 禁止客户端算成功率、裁决三禁止凭空发明 `NodeInfo` 字段——两条约束与该验收项互斥，取约束优先。面板改为展示服务端下发的 `cooldown` / `rewardPreview` / `requiredRealmLevel`（机缘）或 `cost` / `maxParticipants`（秘境），成功率由服务端在 `sendToJiYuan` 内判定，结果由 `ExploreResult` 回包体现 | 裁决二/三 + 硬约束 2；1.0 `entity/NodeInfo.java`、`action/ExploreAction.java` |

### 11.2 待办（`TODO(需核对)`：权威源未给出形状，禁止臆造）

| # | 项 | 现状 | 需要什么 |
|---|---|---|---|
| 1 | `TrainingResult` / `AppointmentResult` / `ExploreResult` / `PolicyResult` 的字段形状 | 1.0 `PROTOCOL.md` §11 只给出类型名，未列字段；`COMMAND_MAP.md` 亦未展开 | **`TrainingResult` 已回填（R5）**：1.0 `TrainingResult.java` 实际字段恰为 `{success, message, unitClass}`，故 `reclass`/`promote` 的 result 按此三字段落地（`unitClass` 返回**改后**的兵种）。**`ExploreResult` / `PolicyResult` 已回填（R6）**：1.0 `ExploreResult.java` 恰为 `{success, message, rewards:List<Reward>, casualties:List<String>, injured:List<String>, cooldown:int}`，`Reward` 为 `{type, amount, materialId}`（`type` ∈ `SPIRIT_POWER`/`SPIRIT_STONES`/`RARE_MATERIAL`/`DAO_POINT`）；1.0 `PolicyAction.PolicyResult` 恰为 `{success, message}`。**`AppointmentResult` 已回填（R7）**：1.0 `entity/AppointmentResult.java` 只有 `boolean success` + `String message` 两个字段，`bridge/CommandDispatcher.toResult()` 亦无额外包装，故 `appointFengZhu`/`appointZhangLao`/`appointZongZhu` 的 result 按 **`{success, message}` 两键**落地（裁决二），**不添加** `discipleId`/`position`/`peakId` 等 1.0 不存在的字段。至此本节第 1 项**全部回填完毕，无 TODO** |
| 2 | `NodeInfo`（`queryJiYuanInfo`/`queryMiJingInfo` 的 `info`） | 1.0 仅给类型名 | **已回填（R6）**：1.0 `entity/NodeInfo.java` 九字段 `{nodeId, name, type, level, requiredRealmLevel, cooldown, cost, maxParticipants, rewardPreview}`，2.0 原样落地；未用到的字段留默认（机缘 `cost`=0 / `maxParticipants`=1，秘境 `requiredRealmLevel`=0）。`name` 取自 `GameNode.name`（`MapGenerator` 按 `NodeType.NAMES` + 序号取名），不下发进 `view.nodes[]` |
| 3 | `queryVictoryProgress.routes[].goals` 内部形状 | 1.0 只给到 `goals` 一层 | **已回填（R7）**：1.0 `entity/VictoryGoal.java` 五字段 `{name, current, target, unit, description}` + 四个派生方法 `getRatio()`/`isMet()`/`missingText()`/`valueText()` → 2.0 落为 **9 键** `{name, current, target, unit, description, ratio, met, missingText, valueText}`，**派生值一并下发**（客户端零规则，不得自行除算比例或拼差距文案）。`ratio = clamp(current/target, 0, 1)`（`target<=0` 视为 1.0）；`missingText` 仅在 `met=false` 时非空 |
| 4 | `queryPolicyOptions.effects{}` / `governments[].slots{}` 内部形状 | 1.0 只给到一层 | **已回填（R6）**：`effects{}` = `{outputBonus, spiritPowerBonus, cultivationBonus, combatBonus, stabilityPerTurn, prestigePerTurn}`（前四项为**百分比小数**，后两项为**每回合增量**；合计只经 `PolicyRules.effect_sum` 一个出口，`policy.enabled=false` 时全零）；`governments[].slots{}` = `{economy, military, governance}` 三个整数槽位（键名与 `data/gameConfig.json` **逐字一致**——PRD §4.13「原外交槽 2.0 改治理」把 1.0 的 `diplomacy` 换成了 `governance`，写成 `culture` 会让 `used_slots` 恒 0、治理卡永远「槽位已满」），**读自 `policy.governments[].slots` 配置**而非硬编码（R6 裁决四） |
| 5 | 地形 blocker 的归属 | PRD §6.7 末注：山岳不可建城/不可通行、雾泽、缺水由 `querySpiritPeakBlocker` / `queryBuildOptions` / `queryMoveRange` 返回 | `TODO(需核对)`：`querySpiritPeakBlocker` **不在 69 条命令清单内**（PRD §6.7 未登记），需确认它是否为新增命令或应并入 `queryBuildOptions`；本文**不新增命令**，故仅在 `foundSpiritPeak`/`queryMoveRange` 的说明中引用该语义 |
| 6 | `awaitInput.options` 的 `routeId`/`description` 之外是否另有字段 | PRD §6.3 给出 `routeId`/`description` | 已按 PRD §6.3 落地，无 TODO |
| 7 | `ImprovementRules.apply_pillage()` 的接线点 | 配置含 `pillageChanceOnMove` 0.35 / `pillageChanceOnAttack` 1.0；R3 已实现掠夺判定函数本身 | **攻击路径已接线（R5）**：`CombatResolver.resolve_attack` 在 `attackerWon` 时对目标格调用 `ImprovementRules.apply_pillage(state, config, tile, 1.0, "battle")`（战火打残改良、产出停摆待修缮）。**移动路径仍未接线**（`pillageChanceOnMove` 0.35 未被读取）：1.0 在移动途中按概率掠夺，2.0 R2 的移动规则已验证稳定，故 R5 不改动移动路径，留待 R6 探索/劫掠一并回填 |
| 8 | 敌方可见弟子的 `assignedPeakId` 是否应剥离 | `Disciple.to_dict` 恒含 `assignedPeakId`；灵峰快照已按迷雾剔除 `fengZhuId`（§12.4），弟子侧**无对称处理** | `TODO(需核对)`：核对 1.0 敌方弟子字段裁剪口径；若不泄露，敌方可见弟子的 `assignedPeakId` 应清空（R3 沿用 R1/R2 现状，未改） |
| 9 | 灵泉衰减/修缮恢复的生效口径 | 配置含 `economy.lingQuanDecayRate` 0.02 / `lingQuanMinOutput` 3 / `improvement.lingQuanRestorePerTurn` 0.05，PRD §4.4 记「灵泉修缮：灵泉每回合恢复 5%」；但 2.0 配置**无 `lingQuanBaseOutput`**（1.0 有，值 15），而 2.0 节点产出改由 `city.workYieldByNode.LING_QUAN`（`spiritPower:6`）给出，衰减下限 `minFactor` 的分母无权威取值 | `TODO(需核对)`：1.0 `EconomyCalculator.settleLingQuanDecay()` 以 `lingQuanMinOutput / lingQuanBaseOutput` 求下限、以 `node.decayRate` 乘算产出；2.0 改用 `workYieldByNode` 后分母应取哪个键未定。**R3 未实现衰减与恢复**（灵泉枯竭属 PRD §5.1「灾劫」，归 R6 判定），待 R6 落地时一并回填，避免臆造系数 |
| 10 | 前期「道点不可得」的跨里程碑断层 | PRD §5.1 L345 初始资源为 灵力400/灵石300/工力120/声望0，**无道点**；PRD §4.9 L455 道点来源为藏经阁（+2/回合）、灵脉/机缘/秘境节点、道统成就 boost。而 `sendToJiYuan`（机缘，成功 +20 道点）与 `exploreMiJing`（秘境，富裕 +40 道点）属 **R5**，节点占领亦无对应命令 | 结果为 R4 实测：开局 21 条道法**全部 `BLOCKED`**（`tu_na` blocker =「道点不足: 需要 20, 当前 0」），必须先建藏经阁（250 灵力 / 4 回合）再等 10 回合，最早**第 15 回合**才有第一条可研究道法（`R4ClientTest` 端到端实测：14 回合后道点 20）。**不属缺陷、不改配置**（与 1.0 一致，1.0 亦有 `daoPoints = 0` 初值），但 R5 落地机缘/秘境后应复查该节奏是否达到设计预期 | PRD §5.1 L345、§4.9 L455；2.0 实测 `R4ClientTest` |
| 11 | 三流派特性中**未能落地**的键 | `faction` 块共 46 个叶子键，R3/R4 已落地 6 项（§11.1 #24）。剩余未读键分三类：**① 属后续里程碑**：`guoJia.territoryPowerWeight`（R7 胜负）、`zongMen.exploreSuccessBonus`（R5/R6 探索）、`jiaZu.zuCiReproduceCostReduction` + `bloodline.*` 全套（R7 繁衍）、`guoJia.rareMaterialPenalty`（R5/R6 资源）、`appointment.*` 7 键（R7 任命）、`bloodLinePenalty`（语义未明，PRD §1.1 宗门流条目未提）。**② PRD 未给可计算口径**：`guoJia.expansionCostReduction`（「扩张 −20%」未定义扩张指建区还是气运吞并）、`guoJia.diDuGrowthBonus`（「帝都人口增长 +50%」缺 `building` 侧住房/增长配置，且 `building.housingBonus` 键不存在）。**③ 展示用文案**：`flavors.*.tendency/uniqueAbilityName/...`（R8 UI 打磨才需要） | `TODO(需核对)`：②类需回 PRD/1.0 补齐口径后再实现；①类随对应里程碑落地。**禁止**按字面猜「扩张」「增长 +50%」的具体公式——与 R3 灵泉衰减同一处理原则（不臆造系数） | PRD §1.1、§4.3；2.0 死键审计（`FactionRules` 注释列明已落地项） |

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
| `improvements` | **object**（键 = improvementId） | 改良（R3 起填充）：己方/可见格实时，explored-but-not-visible 格冻结为最后可见快照，未探索格不下发（见 §12.6） | `StateView.build` + `Improvement.to_dict` |
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
| `unlockedDaoIds[]` | **仅己方宗门**下发（R4）：已推演道法 id，升序即解锁顺序 |
| `daoOptions[]` | **仅己方宗门**下发（R4）：21 条道法的面板视图（见下），三态与 `blocker` 由服务端算好，客户端零规则 |

`disciples[j]`（`Disciple.to_dict`）：`id, name, sectId, tileId, realm, position, rootGrade, spiritRoots[], unitClass, movePoints, maxMovePoints, attacksRemaining, turnsInSect, assignedPeakId, bloodLine, generation, directLine, heartDevil, injured, cultivationProgress, builderCharges`（R3 起追加 `builderCharges` 建造差事次数）

`spiritPeaks[k]`（`SpiritPeak.to_dict`）：`id, name, sectId, tileId, capital, level, population, capacity, defense, qiYun, qiYunMax, stability, housing, fengZhuId, buildings{}, districts[], food, foodProgress, freeWorkers, workedTileIds[]`（R3 起 `districts[]` 为 `District.to_dict()` 对象数组，并追加 `food/foodProgress/freeWorkers/workedTileIds`）

`districts[j]`（`District.to_dict`）：`id, name, type, typeName, level, populationAssigned, buildings[], tileId`（`type` ∈ `Enums.DistrictType.ALL`，`buildings[]` 为建筑**类型字符串**数组）

`improvements[id]`（`Improvement.to_dict`，顶层 `view.improvements{}`）：`id, type, tileId, sectId, broken, charges, networkLevel`（`type` ∈ `Enums.ImprovementType.ALL`）

`daoOptions[j]`（R4，`StateView._dao_options`）：`id, name, desc, era, iconKey, prerequisiteDaoIds[], daoPointCost, spiritPowerCost, turns, effects[], factionOnly, requiresBloodLine, eraIndex, state, blocker`
- `daoPointCost` / `spiritPowerCost` / `turns` 为**按本宗折扣与加速后的实际值**（血脉道法 `jiaZu.bloodDaoCostReduction`、宗门/长老/`RESEARCH_BONUS` 的研究加速已折算）；其中 `spiritPowerCost` 语义为**研究工力总额**（对齐 1.0 `BuildAction.researchDao` 的 `workCost`）。
- `state` ∈ `UNLOCKED`（已推演）/ `RESEARCHING`（研究中）/ `AVAILABLE`（可研究）/ `BLOCKED`（不可研究，`blocker` 给中文原因）。
- 未解锁任何道法时 `eraIndex` 用于前端按时代分列；`blocker` 文案由 `DaoRules.can_research` 唯一产生。

### 12.5 不下发的内部字段

| 字段 | 归属 | 不下发理由 |
|---|---|---|
| `tileSnapshots` / `nodeSnapshots` / `peakSnapshots` / `improvementSnapshots` | `Sect` | 迷雾「记忆态」内部缓存；客户端只需 `visibleTiles`/`exploredTiles` |
| `projectQueue` | `SpiritPeak` | 项目队列（建造/建区/洞府/加固）；R4 `queryProjectQueue` 才下发，R3 仅内部推进 |
| `builderCharges` 之外的 `Improvement.charges` | `Improvement` | 预留字段（R3 恒 `0`）；`Improvement.to_dict` 仍照发，客户端忽略 |
| `policyCarry` / `lastPolicySwitchTurn` / `lastEventTurn` | `Sect` | 结算中间态与冷却记账（R6 落地）。`policyCarry["stabilityBonus"]` 是「政令安定」的整数累积，`PolicyRules.process_settlement` 在 `EconomyRules.apply_settlement` **之后**叠加到各峰 `stability` 上——因为 2.0 的 `stability` 是每回合派生的值，不能像 1.0 那样直接累加 |
| `governmentId` / `enactedPolicies` / `automationToggles` / `autoProjectByPeak` | `Sect` | 政体、已颁政令卡、四项自动化开关、逐峰自动项目（R6 落地）；仅由 `queryPolicyOptions` / `queryAutomationState` 按需下发，`view.sects[]` 不含 |
| `missionNodeId` | `Disciple` | 探索任务节点（机缘/秘境，R6 落地）；与 `garrisonNodeId` **互斥**。仅在 `queryDiscipleDetail` 以 `missionNodeId` + `missionNodeName` 下发，`view.disciples[]` 不含 |
| `lastReproduceTurn` | `Disciple` | 繁衍冷却记账（R4 落地） |
| `realmLevel` / `breakthroughPending` / `tribulating` | `Disciple` | 境界等级由 `realm` 派生、突破候选与渡劫中间态；`view.disciples[]` 的 `realm` 已足够表达（R4 落地） |
| `researchQueue` | `Sect` | 研究队列（道法研究）；R4 `queryProjectQueue.researchQueue[]` 才下发 |
| `boostFlags` / `recruitedTotal` / `enemiesDefeated` / `miJingExploredTotal` / `lastRecruitmentTurn` | `Sect` | 成就 boost 一次性标志、累计招募/击败/成功探索秘境数、收徒冷却记账（R4 落地；`miJingExploredTotal` 语义见 §11.1 #23） |
| `discipleSeq` | `GameState` | 弟子 id 单调序号（R4 落地） |
| `capturedFromSectId` | `Disciple` | 被俘来源宗门 id（R5 落地）；仅在 `queryDiscipleDetail` 内下发，`view.disciples[]` 不含——避免暴露「某弟子原是敌方谁的人」这一情报 |
| `siegeTurns` | `SpiritPeak` | 围城已持续回合数（R5 落地）；`UnitRules.update_attrition` 的断粮计数中间态，仅内部推进 |
| `teleportsUsedThisTurn` | `Sect` | 本回合已用传送次数（R5 落地）；回合开始清零，余量由 `queryTeleportOptions.remaining` 表达 |

> R5 补充：`GameNode.garrisonDiscipleIds` 在**己方**节点正常下发（`view.nodes[nodeId]`），
> 对敌方/中立节点由 `StateView.build` 整字段 `erase`（§12.3），否则可白嫖敌节点守军构成。

> 出处：1.0 `PROTOCOL.md` §5.1；2.0 `StateView.build` 未输出上述字段（R1 已实证）。

### 12.6 迷雾下发规则（PRD §4.2）

- 地形/地貌/河流/节点一旦 `explored` **永久保留**；未探索格不下发任何地形信息。
- 己方实体（己方灵峰所在地块、己方归属地块、己方节点所在地块）**实时下发**，不受记忆快照冻结。
- 敌方单位仅在可见格下发；敌方城市/建筑/改良/领地在可见格实时、在 mid-fog 格**冻结为最后可见快照**。
