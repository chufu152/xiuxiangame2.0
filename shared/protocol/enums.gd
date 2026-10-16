class_name Enums
extends RefCounted
## 游戏枚举字符串常量（大写下划线，序列化后即为该字符串）。
##
## 唯一权威：docs/REQUIREMENTS_2.0.md §3.3（逻辑 ID）与第 4 章（玩法枚举）。
##
## R0 只留空框架：本里程碑不涉及任何玩法枚举，故不定义任何成员。
## 后续里程碑按需逐项填充，填充时保持「大写下划线 + ALL 数组」的统一形状：
##   - R1：BaseTerrain（基底地形）、Relief（海拔）、Feature（地貌）、
##         NodeType（节点）、FactionType（势力流派）
##   - R2：Realm（境界）、Position（岗位）、SpiritRootType（灵根）、TurnPhase（回合阶段）
##   - R3：Building（建筑）、District（区域）、Improvement（改良）、
##         ResourceKind（资源）、MaterialType（战略材料）、LuxuryType（奢侈品）
##   - R5：UnitClass（兵种）
##   - R6：Government（政体）、PolicyCategory（政令分类）
##   - R7：VictoryRoute（胜利路线）、Difficulty（难度）
##
## 约定：规则层 / 配置 / 协议一律引用本文件，禁止散落枚举字符串字面量。
## 注意：内部类名不得与 Godot 原生类同名（如 Resource / Material），需要时加后缀。
