# data/ —— 权威数值配置

本目录存放**服务端唯一权威**的游戏数值配置。客户端不持有规则数值，所有"能不能做/产出多少/胜率多少"都由服务端按本配置计算后下发。

## gameConfig.json

- **来源**：1.0 工程 `src/main/resources/gameConfig.json`（1217 行，顶层块已逐节核对，见 `docs/REQUIREMENTS_2.0.md`）。
- **迁移任务**：R1 把 1.0 配置复制到本目录后，按下方清单裁剪与扩展，由服务端 `scripts/config/` 加载并经 `ConfigValidator` 校验。
- **当前状态（R1）**：已迁移并裁剪完成，本文件 2144 行；`schemaVersion`/`saveVersion` = `3.0`；裁剪 6 块**已确认全部不存在**；`policy.cards=8`、`daoTree.daos=21`、`warfare.unitClasses=10`。
- **格式约定**：小驼峰键、枚举大写下划线（`ZONG_MEN`、`HILL`、`JIAN_ZHEN_SHI`）；不允许在代码里硬编码本该在配置里的数值。

### 保留的配置块（从 1.0 迁移，2.0 首版）

| 配置块 | 内容要点 |
|---|---|
| `map` | 宽高（20×15）、险地几率 0.1/移动 2、节点生成几率、奢侈品几率；**2.0 在此扩展地形分层（见下）** |
| `disciple` | 基础移动 2、收徒间隔 10、晋升等待 5、心魔、修炼（速度/上限/突破/渡劫） |
| `spiritPeak` | 容量 10/+5、气运上限 100、开峰造价 500/800/350、工期 5、铺张惩罚、防御 10、最高 5 级 |
| `economy` | 节点/弟子产出、维护、工力、声望、势力相关、加速 120、赤字安定 |
| `resources` | 初始资源（400/300/120/0 + 晶2铁2木4）、3 战略材料、3 奢侈品 |
| `combat` | 胜率 0.5、碾压 1.5、伤亡概率、境界/灵根权重、心魔惩罚、回合 1–3、噪声 |
| `building` | 10 建筑造价/工期/材料/流派限定、洞府、加固、收徒、返还 |
| `explore` | 机缘/秘境成功率、材料、冷却、伤亡、富裕奖励 |
| `appointment` | 长老上限、峰主/长老/大殿加成 |
| `ai` | 行动点、倾向、扩张权重、战斗阈值（反应式 AI 用） |
| `faction` | 三流派 flavors、`zongMen/jiaZu/guoJia` 加成、`bloodline` 血脉 |
| `victory` | 240 回合、三流派胜利条件、分数权重 |
| `qiYun` / `powerLevel` | 气运产出；势力等级加权（地块/5 + 高境界弟子×2 + 道法×1 + 建筑等级×1） |
| `daoTree` | 五时代、**21 条道法（daos，含 4 流派专属）**、4 条成就 `boosts`、藏经阁 2 点/回合、节点道点 |
| `vision` | 峰 3、节点 2、弟子境界视野（炼气2/筑基2/金丹3/元婴3/化神4）、迷雾参数 |
| `warfare` | 10 兵种 `unitClasses`、`counters` 相克、9 条 `promotions`、高地/跨河/围城/ZOC/撤退/经验 |
| `city` | 人口、住房、安定、工作半径、5 区域 `district`（+首府区）、邻接 8 条、地块/节点产出 |
| `improvement` | 建造者 3 次、8 改良 `byType`、修缮、掠夺、道路、聚灵/洞府 |
| `policy` | 3 政体 `governments`、10 卡 `cards`（**2.0 删 2 外交卡**）、切换冷却 8 |
| `road` / `teleport` | 道路网减耗/自动修建；传送造价/容量（需 chuan_song） |
| `automation` | 自动化开关、每回合上限、集结/自动探索人数、流派项目偏好 |
| `speed` | 动画/自动播放间隔、批量移动上限 |
| `difficulty` | 初入仙途/正道争锋/群雄噬血 三档（AI 行动点/补贴/倍率） |

### 2.0 新增的地形配置块（设计初值，R1 建、R3 调参）

挂在 `map` 下：

| 子块 | 内容（**括号内为 R1 已落地的实际值，为唯一口径**） |
|---|---|
| `map.baseTerrains` | 3 基底：LING_FIELDS / SPIRIT_PLAIN / BARREN，基础产出（粮/灵/石）＝（3/1/0）、（2/2/0）、（1/0/2） |
| `map.relief` | FLAT/HILL/MOUNTAIN 的 `height`/`moveCost`/`defenseBonus`/`visionBonus`/`passable`/`ratio` ＝（1.0/1/0.0/0/true/0.70）、（1.7/2/0.2/1/true/0.22）、（3.0/—/—/—/false/0.08） |
| `map.features` | SPIRIT_FOREST 灵林：`chance`**0.22**、`moveExtra`1、`defenseBonus`0.2、`yield`{粮+1,灵木+1}、`clearYield`{灵木 2}、`reliefs`[FLAT,HILL]；MIRE 雾泽：`chance`**0.12**、`moveExtra`1、`defenseBonus`−0.1、`yield`{粮+1}、`reliefs`[FLAT] |
| `map.river` | `sourcesMin/Max`1/2、`sourceEdgesMin/Max`1/2、`edgeRatioMin/Max`0.10/0.20、`crossPenalty`0.25、`moveExtra`1、`foodBonus`1 |
| `map.nodeSpawnByTerrain` | LING_TIAN→沃野平地、LING_MAI→丘陵/山岳、JI_YUAN→险地、MI_JING→险地、LING_QUAN→沿河 |
| `map.luxuryByTerrain` / `map.strategicByTerrain` | 奢侈品/战略材料按地形的分布偏好（灵茶/云锦/灵玉；玄铁/天晶/灵木） |
| `map.baseTerrainAlgorithm` | 基底地形生成算法标识（供 `MapGenerator` 选择实现，便于 R3 调参） |
| `map.setup` | 开局初始化参数（每宗峰/宗主/外门弟子、初始资源、AI 名称与流派、地图尺寸上限等） |

> **文档冲突已裁决**：PRD §4.1.4 原写「灵林 15% / 雾泽 8%」，与本表 22% / 12% 冲突；已统一为 **22% / 12%** 并回改 PRD。**数值以本文件对应的 `gameConfig.json` 实际值为准。**

> 复用 1.0 已有字段：`dangerTileChance/dangerTileMoveCost`、`warfare.highGroundBonus=0.15`、`warfare.riverCrossPenalty=0.25`、`terrainDefenseBonus.险地=0.25`、`warfare.terrainDefenseBonus`。

### 裁剪掉的配置块（2.0 首版不加载，标记 `disabled` 或删除）

| 配置块 | 处理 |
|---|---|
| `diplomacy`（`weariness`/`peace`/`trade`/`treaty`） | **删除/禁用**；厌战、外交状态、条约、交易全部移除 |
| `threat`（蛮族巢穴/袭击） | **删除/禁用** |
| `event`（随机事件库、路途事件、待决事件） | **删除/禁用**；机缘/秘境主动探索保留在 `explore` |
| `disaster`（灵泉枯竭/灵脉震动/天罚雷劫/瘴气） | **删除/禁用**；秘境内部 `miJingDisasterChance` 作为探索风险保留 |
| `loyalty`（忠诚/赏赐/叛乱/独立） | **删除/禁用**；城市基础 `stability` 安定保留在 `city` |
| `strategy`（AI 性格/长期战略复盘） | **删除/禁用**；保留 `ai` 基础反应式 |
| `policy.cards` 中 `category=diplomacy` 的 2 张（远交近攻、怀柔四方） | 删除；卡片/政体的 `loyaltyPerTurn` 效果改落 `stability`，`weariness` 效果删除；宗门共治外交槽改治理槽 |

> 裁剪后必须通过 `tools/check.ps1` 的配置校验：服务端启动时若仍引用已删模块字段，直接报错而非静默。
>
> **R1 验证结果**：上述 6 个裁剪块在当前 `gameConfig.json` 中**均已确认不存在**（`diplomacy` / `threat` / `event` / `disaster` / `loyalty` / `strategy` → absent）。
