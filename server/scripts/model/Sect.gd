class_name Sect
extends RefCounted

var id: String = ""
var name: String = ""
var factionType: String = Enums.FactionType.ZONG_MEN
var player: bool = false
var resources: Dictionary = {}
var disciples: Array[Disciple] = []
var spiritPeaks: Array[SpiritPeak] = []
var visibleTiles: Array[String] = []
var exploredTiles: Array[String] = []
var tileSnapshots: Dictionary = {}
var nodeSnapshots: Dictionary = {}
var peakSnapshots: Dictionary = {}
## R3 新增：改良「最后可见快照」缓存（改良 id -> `Improvement.to_dict()`），供 `view.improvements{}`
## 在 explored-but-not-visible 格按迷雾规则冻结下发（见 PROTOCOL §12.6）。
var improvementSnapshots: Dictionary = {}
## R3 新增：本宗已修筑的改良（`queryImprovementOptions`、道路网刷新、`view.improvements{}` 的来源）。
## 项目队列放在灵峰上（`SpiritPeak.projectQueue`），与 PROTOCOL §4 `queryProjectQueue{peakId,…}` 口径一致。
var improvements: Array[Improvement] = []
## R4 新增：已推演道法 id（`DaoRules.can_research` 前置链、`ImprovementRules._has_unlocked_dao` 门控、
## `DiscipleRules.tribulate` 成功率加成的唯一来源）。道法为宗门级，故挂在宗门上。
var unlockedDaoIds: Array[String] = []
## R4 新增：宗门级研究队列（道法研究，逐回合在 `SPIRIT_PEAK` 推进）。
## 与灵峰的建造项目队列**分池**（R4 提示词裁决二），`queryProjectQueue` 分列下发。
var researchQueue: Array[ResearchProject] = []
## R4 新增（**内部记账，不下发 view**，见 PROTOCOL §12.5）：成就 boost 一次性触发标志。
var boostFlags: Dictionary = {}
## R4 新增（**内部记账，不下发 view**）：累计收徒人数（`boost_recruit_5` 条件）；
## 与当前存活弟子数无关，叛逃/陨落不回退。
var recruitedTotal: int = 0
## R4 新增（**内部记账，不下发 view**）：累计击败敌人数（`boost_first_win` 条件，R5 起递增）。
var enemiesDefeated: int = 0
## R4 新增（**内部记账，不下发 view**）：累计**成功探索秘境**次数（`boost_first_mijing` 条件）。
## 语义是「实际探过秘境」（`exploreMiJing` 成功），**不是**「视野里看见过秘境节点」——
## 后者开局即成立，会白送 30 道点并让该成就永久失效。R5 落地 `exploreMiJing` 时递增。
var miJingExploredTotal: int = 0
## R4 新增（**内部记账，不下发 view**）：最近一次收徒大典入队的回合（`recruitmentBaseInterval` 冷却）。
var lastRecruitmentTurn: int = 0
## R5 新增（**内部记账，不下发 view**）：本回合已用传送次数（`TURN_START` 清零）。
## 可传送次数 = `teleport.capacityBase` + 在守自有灵脉节点数 × `capacityPerOwnLingMaiNode`（封顶 `capacityMax`）。
var teleportsUsedThisTurn: int = 0
## R6 新增：当前政体 id（`policy.governments[].id`）。空串 = 未立政体，
## `PolicyRules.government_of` 回退配置首政体（宗门共治），与 1.0 `PolicyService.governmentOf` 一致。
var governmentId: String = ""
## R6 新增：已颁行政令卡 id（`policy.cards[].id`，颁行顺序；`enactPolicy` 追加、`revokePolicy` 移除）。
## 槽位占用按 `category` 统计，超槽位时由 `trim_policies_to_slots` 按颁行顺序裁剪。
var enactedPolicies: Array[String] = []
## R6 新增（**内部记账，不下发 view**，见 PROTOCOL §12.5）：政令小数累积账户。
## `stability`/`prestige` 存每回合 `perTurn` 累加的余数（向零截断落地，避免整数丢失）；
## `stabilityBonus` 存已落地的安定整数叠加值（`SETTLEMENT` 时叠加到各峰 `stability`）。
var policyCarry: Dictionary = {}
## R6 新增（**内部记账，不下发 view**）：最近一次切换政体的回合（`policy.switchCooldownTurns` 冷却）。
## 0 = 从未切换，`switch_cooldown_left` 视作无冷却。
var lastPolicySwitchTurn: int = 0
## R6 新增：自动化开关（`improve`/`repair`/`road`/`explore` -> bool）。
## 缺键 = 跟随 `automation.defaultAuto*`，见 `AutomationRules.toggle_of`。
var automationToggles: Dictionary = {}
## R6 新增：逐峰自动项目开关（peakId -> bool）。缺键 = 跟随 `automation.defaultAutoProject`。
var autoProjectByPeak: Dictionary = {}
## R7 新增：势力等级派生缓存（裁决六，**不是声望折算**）。由
## `VictoryRules.refresh_power_level` 按 `powerLevel.*` 四权重重算；`appointment` 长老名额与
## 宗门流胜利条件都读它，故每次判定前必须刷新（1.0 `refreshPowerLevel` 同语义）。
var powerLevel: int = 0
## R7 新增：已覆灭（`VictoryRules.check_defeat` 命中）。覆灭宗门的弟子/灵峰已清空，
## `_run_ai_action` 跳过、胜负判定跳过（1.0 `Sect.eliminated` 同语义）。
var defeated: bool = false
## R7 新增（**内部记账，不下发 view**）：最近一次自动存档的回合，避免同一回合重复落盘。
var lastAutoSaveTurn: int = 0
## R7 新增（**内部记账，不下发 view**）：上一回合宗主是否处于「外出」状态
## （有宗主但不在首都，或首都未建宗主大殿）。`TurnProcessor._run_turn_start` 只在
## **状态翻转时**记一条事件，避免每回合刷屏。
var zongZhuOutside: bool = false

func public_info() -> Dictionary:
	return {"id": id, "name": name, "factionType": factionType, "player": player}
