class_name UnitRules
extends RefCounted
## 兵种战术规则的**唯一查询入口**（R5，对齐 1.0 `core/UnitRules.java`，数值只取 `data/gameConfig.json`）。
##
## 全部静态、无状态、只读 config。唯一会写状态的函数是 `update_attrition()`，它只推进
## `SpiritPeak.siegeTurns` 这一内部记账字段（PROTOCOL §12.5），由 `TurnProcessor` 在回合阶段调用。
##
## **2.0 与 1.0 的三处口径差异**（已在 PROTOCOL §11.1 #25 登记，非自由裁量）：
##   1. **地形防御按 2.0 的分层配置**：`map.relief[].defenseBonus` + `map.features[].defenseBonus`
##      叠加，险地再与 `warfare.terrainDefenseBonus["险地"]` 取大。1.0 是按**中文地形名**查单表
##      （`terrainDefenseBonus{平原, 险地}`），而 2.0 地形 id 是英文枚举（`FLAT/HILL/MOUNTAIN`、
##      `SPIRIT_FOREST/MIRE`），直接照搬会全部查不到而恒返回 0。
##   2. **高地加成用海拔比较**：`map.relief[].height`（FLAT 1.0 / HILL 1.7 / MOUNTAIN 3.0），
##      攻方海拔**严格高于**守方时加 `warfare.highGroundBonus`。1.0 用「攻方在险地、守方不在」
##      的布尔判断，与 PRD §4.10「丘陵高地 +15%」不符。
##   3. **跨河减益判边**：2.0 河流是 `HexTile.riverEdges` 的**边属性**（`MoveRules.crosses_river`），
##      不存在 1.0 的「地形名属于 riverTerrains」；故签名取攻守双方地块。
##
## **本文件不做的**：战力计算与胜负结算（`CombatResolver`）、移动代价（`MoveRules`）、
## 传送（`TeleportRules`）。此处只回答「这个兵种在这一格上算什么数」。

## 相克/地形表里「险地」的键名（`warfare.terrainDefenseBonus` 是中文键）。
const DANGER_TERRAIN_KEY: String = "险地"
## 骑兵 `kind`（`warfare.unitClasses[].kind`）：撤退概率吃 `retreatMobileBonus`。
const KIND_CAVALRY: String = "CAVALRY"
## 重伤者撤退减益（1.0 `UnitRules.retreatChance` 硬编码 −0.2，配置无对应键，沿用）。
const INJURED_RETREAT_PENALTY: float = 0.2
## 撤退概率夹取区间（1.0 同源；配置无对应键）。
const RETREAT_CHANCE_MIN: float = 0.05
const RETREAT_CHANCE_MAX: float = 0.95


# ---------------------------------------------------------------------------
# 兵种身份
# ---------------------------------------------------------------------------

## 弟子的兵种；空值/非法值一律视作寻常弟子（1.0 `classOf` 的旧档兼容语义）。
static func class_of(disciple: Disciple) -> String:
	if disciple == null: return Enums.UnitClass.PU_TONG
	if not Enums.UnitClass.ALL.has(disciple.unitClass): return Enums.UnitClass.PU_TONG
	return disciple.unitClass


## 兵种配置块；查不到回落 `PU_TONG`（1.0 `classConfig` 同源）。
static func class_config(config: Dictionary, unit_class: String) -> Dictionary:
	var table: Dictionary = config["warfare"]["unitClasses"]
	if table.has(unit_class): return table[unit_class]
	return table[Enums.UnitClass.PU_TONG]


## 兵种大类（`MELEE`/`RANGED`/`ANTI_CAVALRY`/`CAVALRY`/`SUPPORT`/`SIEGE`）。
static func kind_of(config: Dictionary, disciple: Disciple) -> String:
	return str(class_config(config, class_of(disciple))["kind"])


## 兵种展示名（配置 `displayName`）。
static func class_name_of(config: Dictionary, unit_class: String) -> String:
	return str(class_config(config, unit_class)["displayName"])


# ---------------------------------------------------------------------------
# 兵种数值（含晋升加成）
# ---------------------------------------------------------------------------

## 已习得晋升项在 `key` 上的加成合计（`warfare.promotions[].bonuses`）。
## 可用的 `key`：`attack`/`defense`/`range`/`move`/`siege`/`vision`/`retreat`。
static func promotion_bonus(config: Dictionary, disciple: Disciple, key: String) -> float:
	if disciple == null or disciple.promotions.is_empty(): return 0.0
	var total: float = 0.0
	for promotion: Dictionary in config["warfare"]["promotions"]:
		if not disciple.promotions.has(str(promotion["id"])): continue
		var bonuses: Dictionary = promotion.get("bonuses", {})
		if bonuses.has(key): total += float(bonuses[key])
	return total


static func attack_multiplier(config: Dictionary, disciple: Disciple) -> float:
	return float(class_config(config, class_of(disciple))["attack"]) + promotion_bonus(config, disciple, "attack")


static func defense_multiplier(config: Dictionary, disciple: Disciple) -> float:
	return float(class_config(config, class_of(disciple))["defense"]) + promotion_bonus(config, disciple, "defense")


## 射程（格，含晋升 `range` 加成），下限 1。
static func range_of(config: Dictionary, disciple: Disciple) -> int:
	var base: int = int(class_config(config, class_of(disciple))["range"])
	return maxi(1, base + int(round(promotion_bonus(config, disciple, "range"))))


## 攻城能力（含晋升 `siege` 加成）。
static func siege_bonus(config: Dictionary, disciple: Disciple) -> float:
	return float(class_config(config, class_of(disciple))["siegeBonus"]) + promotion_bonus(config, disciple, "siege")


## 机动加成（含晋升 `move` 加成）。R5 起**对所有兵种**生效（裁决七）。
static func move_bonus(config: Dictionary, disciple: Disciple) -> int:
	var base: int = int(class_config(config, class_of(disciple))["moveBonus"])
	return base + int(round(promotion_bonus(config, disciple, "move")))


## 视野加成（含晋升 `vision` 加成）。
static func vision_bonus(config: Dictionary, disciple: Disciple) -> int:
	var base: int = int(class_config(config, class_of(disciple))["visionBonus"])
	return base + int(round(promotion_bonus(config, disciple, "vision")))


## 守方对**贴身**攻方的反击系数（远程不挨反击由 `CombatResolver` 判距离）。
static func retaliation_of(config: Dictionary, disciple: Disciple) -> float:
	return float(class_config(config, class_of(disciple))["retaliation"])


## 是否攻城单位：攻城能力达 `warfare.siegeRequirement` 才不被城防削输出。
## `+0.0001` 吸收浮点误差（1.0 同源）。
static func is_siege_unit(config: Dictionary, disciple: Disciple) -> bool:
	return siege_bonus(config, disciple) + 0.0001 >= float(config["warfare"]["siegeRequirement"])


## 相克倍率；矩阵无条目返回 1.0（不克不被克）。
static func counter_multiplier(config: Dictionary, attacker_class: String, defender_class: String) -> float:
	var table: Dictionary = config["warfare"]["counters"]
	if not table.has(attacker_class): return 1.0
	var row: Dictionary = table[attacker_class]
	if not row.has(defender_class): return 1.0
	return float(row[defender_class])


# ---------------------------------------------------------------------------
# 地形与驻守
# ---------------------------------------------------------------------------

## 守方所在地块的防御加成：地形层 + 地貌层叠加，险地与之取大。
## 口径见文件头差异 1（丘陵 +0.2 / 灵林 +0.2 / 雾泽 −0.1 / 险地 0.25）。
static func terrain_defense_bonus(config: Dictionary, tile: HexTile) -> float:
	if tile == null: return 0.0
	var map_config: Dictionary = config["map"]
	var bonus: float = 0.0
	var relief: Dictionary = map_config["relief"].get(tile.relief, {})
	bonus += float(relief.get("defenseBonus", 0.0))
	for feature: String in tile.features:
		var feature_config: Dictionary = map_config["features"].get(feature, {})
		bonus += float(feature_config.get("defenseBonus", 0.0))
	if tile.danger:
		var danger: float = float(config["warfare"]["terrainDefenseBonus"].get(DANGER_TERRAIN_KEY, 0.0))
		bonus = maxf(bonus, danger)
	return bonus


## 攻方踞高下击的输出加成：攻方海拔严格高于守方时取 `warfare.highGroundBonus`。
static func high_ground_bonus(config: Dictionary, attacker_tile: HexTile, defender_tile: HexTile) -> float:
	if attacker_tile == null or defender_tile == null: return 0.0
	if _relief_height(config, attacker_tile) <= _relief_height(config, defender_tile): return 0.0
	return float(config["warfare"]["highGroundBonus"])


## 攻方跨河上岸作战的减益（2.0 河流在边上，见文件头差异 3）。
static func river_penalty(config: Dictionary, attacker_tile: HexTile, defender_tile: HexTile) -> float:
	if attacker_tile == null or defender_tile == null: return 0.0
	if not MoveRules.crosses_river(attacker_tile, defender_tile): return 0.0
	return float(config["warfare"]["riverCrossPenalty"])


## 守方驻守己方节点、或站在己方灵峰地块上时的防御加成。
static func garrison_defense_bonus(state: GameState, config: Dictionary, defender: Disciple) -> float:
	if state == null or defender == null: return 0.0
	var bonus: float = float(config["warfare"]["garrisonDefenseBonus"])
	if not defender.garrisonNodeId.is_empty() and state.nodes.has(defender.garrisonNodeId):
		var node: GameNode = state.nodes[defender.garrisonNodeId]
		if node.ownerSectId == defender.sectId: return bonus
	var sect: Sect = _sect_of(state, defender.sectId)
	if sect == null: return 0.0
	for peak: SpiritPeak in sect.spiritPeaks:
		if peak.tileId == defender.tileId: return bonus
	return 0.0


# ---------------------------------------------------------------------------
# 围城与补给
# ---------------------------------------------------------------------------

## 灵峰是否仍有补给线：相邻地块中属己方或无主的数量达 `supplyNeighborsRequired`。
static func has_supply_line(state: GameState, config: Dictionary, peak: SpiritPeak) -> bool:
	if state == null or peak == null or not state.tiles.has(peak.tileId): return true
	var tile: HexTile = state.tiles[peak.tileId]
	var friendly: int = 0
	for coords: Vector2i in Hex.neighbors(Vector2i(tile.q, tile.r)):
		var neighbor_id: String = Hex.id(coords.x, coords.y)
		if not state.tiles.has(neighbor_id): continue
		var neighbor: HexTile = state.tiles[neighbor_id]
		if neighbor.ownerSectId.is_empty() or neighbor.ownerSectId == peak.sectId: friendly += 1
	return friendly >= int(config["warfare"]["supplyNeighborsRequired"])


## 被围灵峰的城防折减：`min(maxDefenseCut, defenseCutPerTurn × siegeTurns)`。
static func siege_defense_cut(config: Dictionary, peak: SpiritPeak) -> float:
	if peak == null: return 0.0
	var per_turn: float = float(config["warfare"]["defenseCutPerTurn"])
	var maximum: float = float(config["warfare"]["maxDefenseCut"])
	return minf(maximum, per_turn * float(maxi(0, peak.siegeTurns)))


## 围城结算：补给断绝则累计被围回合，恢复补给则清零。返回本回合是否仍被围。
## **唯一会写状态的函数**，只写 `SpiritPeak.siegeTurns`（内部记账，PROTOCOL §12.5）。
static func update_attrition(state: GameState, config: Dictionary, peak: SpiritPeak) -> bool:
	if peak == null: return false
	if has_supply_line(state, config, peak):
		peak.siegeTurns = 0
		return false
	peak.siegeTurns += 1
	return true


## 围城到折减上限还需几回合（供 UI 显示围城进度；已达上限返回 0）。
static func turns_to_breach(config: Dictionary, peak: SpiritPeak) -> int:
	if peak == null: return 0
	var per_turn: float = float(config["warfare"]["defenseCutPerTurn"])
	var maximum: float = float(config["warfare"]["maxDefenseCut"])
	if per_turn <= 0.0: return 0
	var needed: int = int(ceil(maximum / per_turn))
	return maxi(0, needed - peak.siegeTurns)


# ---------------------------------------------------------------------------
# ZOC 控制区（裁决一）
# ---------------------------------------------------------------------------

## 该地块被多少个敌方可战单位的控制区覆盖（相邻即施加）。
## **实现与唯一出口在 `MoveRules.zoc_pressure`**：ZOC 是移动代价的一部分，必须与 `step_cost`
## 同源，否则「高亮可达」会与实际可走脱节。此处仅作战术层再导出，不重复实现。
static func zoc_pressure(state: GameState, config: Dictionary, mover_sect: Sect, tile: HexTile) -> int:
	return MoveRules.zoc_pressure(state, config, mover_sect, tile)


## 进入该地块需要额外付出的移动力 = 压力 × `warfare.zocExtraCost`。
static func zoc_extra_cost(state: GameState, config: Dictionary, mover_sect: Sect, tile: HexTile) -> int:
	return MoveRules.zoc_extra_cost(state, config, mover_sect, tile)


# ---------------------------------------------------------------------------
# 撤退
# ---------------------------------------------------------------------------

## 撤退成功率 = `retreatBaseChance` + 晋升 `retreat` + 骑兵 `retreatMobileBonus` − 重伤 0.2，
## 夹取 [0.05, 0.95]。
static func retreat_chance(config: Dictionary, disciple: Disciple) -> float:
	var chance: float = float(config["warfare"]["retreatBaseChance"])
	chance += promotion_bonus(config, disciple, "retreat")
	if kind_of(config, disciple) == KIND_CAVALRY:
		chance += float(config["warfare"]["retreatMobileBonus"])
	if disciple != null and disciple.injured:
		chance -= INJURED_RETREAT_PENALTY
	return clampf(chance, RETREAT_CHANCE_MIN, RETREAT_CHANCE_MAX)


# ---------------------------------------------------------------------------
# 经验 / 等级 / 晋升
# ---------------------------------------------------------------------------

## 按 `warfare.levelThresholds` 换算战功等级（阈值表越界取最高档）。
static func level_for_xp(config: Dictionary, xp: int) -> int:
	var thresholds: Array = config["warfare"]["levelThresholds"]
	var level: int = 0
	for index: int in range(thresholds.size()):
		if xp >= int(thresholds[index]): level = index
	return level


## 发战功经验并结算升级晋升点，返回**本次升了几级**。
static func award_experience(config: Dictionary, disciple: Disciple, xp: int) -> int:
	if disciple == null or xp <= 0: return 0
	disciple.battleXp += xp
	var new_level: int = level_for_xp(config, disciple.battleXp)
	var gained: int = maxi(0, new_level - disciple.battleLevel)
	if gained > 0:
		disciple.battleLevel = new_level
		disciple.promotionPoints += gained * maxi(0, int(config["warfare"]["promotionPointsPerLevel"]))
	return gained


## 可晋升列表：有晋升点 + 等级达标 + 兵种匹配（或通用）+ 未选过。
static func available_promotions(config: Dictionary, disciple: Disciple) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if disciple == null or disciple.promotionPoints <= 0: return options
	for promotion: Dictionary in config["warfare"]["promotions"]:
		if disciple.promotions.has(str(promotion["id"])): continue
		if disciple.battleLevel < int(promotion.get("minLevel", 0)): continue
		var requires: Variant = promotion.get("requiresUnitClass", null)
		if requires != null and str(requires) != class_of(disciple): continue
		options.append(promotion)
	return options


## 可转职兵种列表：每种都给出 `{id, name, allowed, blocker}`。
static func available_unit_classes(state: GameState, config: Dictionary, sect: Sect, disciple: Disciple) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for unit_class: String in Enums.UnitClass.ALL:
		var blocker: String = reclass_blocker(state, config, sect, disciple, unit_class)
		options.append({
			"id": unit_class,
			"name": class_name_of(config, unit_class),
			"allowed": blocker.is_empty(),
			"blocker": blocker,
		})
	return options


# ---------------------------------------------------------------------------
# 转职校验
# ---------------------------------------------------------------------------

## 转职校验：不合格返回原因，合格返回空串。对齐 1.0 `UnitRules.reclassBlocker`。
static func reclass_blocker(state: GameState, config: Dictionary, sect: Sect, disciple: Disciple, target: String) -> String:
	if sect == null or disciple == null: return "参数缺失"
	if not Enums.UnitClass.ALL.has(target): return "非法兵种：" + target
	if class_of(disciple) == target: return "已是" + class_name_of(config, target)
	if disciple.position == Enums.Position.ZONG_ZHU: return "宗主不可亲自改习兵种"
	if disciple.tribulating: return "渡劫中不可转职"
	var unit: Dictionary = class_config(config, target)
	var faction_only: Variant = unit.get("factionOnly", null)
	if faction_only != null and not str(faction_only).is_empty() and str(faction_only) != sect.factionType:
		return "「%s」是%s专属兵种" % [class_name_of(config, target), _faction_name(config, str(faction_only))]
	if not is_unit_unlocked(state, config, sect, target): return "尚未推演「%s」所需道法" % class_name_of(config, target)
	if disciple.reclassCooldown > 0: return "改习兵种冷却中(还需%d回合)" % disciple.reclassCooldown
	if disciple.realmLevel < int(unit.get("minRealmLevel", 0)):
		return "修为需达%d重境界(当前%d)" % [int(unit.get("minRealmLevel", 0)), disciple.realmLevel]
	if disciple.rootGrade < int(unit.get("minRootGrade", 0)):
		return "灵根品级需达%d品" % int(unit.get("minRootGrade", 0))
	var power_cost: int = int(unit.get("reclassSpiritPower", 0))
	if int(sect.resources.get("spiritPower", 0)) < power_cost: return "灵力不足(需%d)" % power_cost
	var stone_cost: int = int(unit.get("reclassSpiritStones", 0))
	if int(sect.resources.get("spiritStones", 0)) < stone_cost: return "灵石不足(需%d)" % stone_cost
	var materials: Dictionary = sect.resources.get("materials", {})
	var needed: Dictionary = unit.get("reclassMaterials", {})
	for material: String in needed:
		if int(materials.get(material, 0)) < int(needed[material]):
			return "战略资源不足(需%sx%d)" % [_material_name(config, material), int(needed[material])]
	return ""


## 兵种是否已解锁：寻常弟子恒可用；其余需道法 `UNLOCK_UNIT`（值为兵种名小写）。
## 口径对齐 1.0 `UnitRules.isUnlocked`（配置里的解锁键是小写，枚举名是大写）。
static func is_unit_unlocked(state: GameState, config: Dictionary, sect: Sect, unit_class: String) -> bool:
	if unit_class == Enums.UnitClass.PU_TONG: return true
	if sect == null: return false
	var faction_only: Variant = class_config(config, unit_class).get("factionOnly", null)
	if faction_only != null and not str(faction_only).is_empty() and str(faction_only) != sect.factionType: return false
	var unlocked: Array = DaoRules.effect_sum(state, config, sect).get("UNLOCK_UNIT", [])
	return unlocked.has(unit_class.to_lower())


## 战斗单元资格（与 AI 口径一致）：受伤/渡劫/宗主/峰主不作为野战兵力。
static func can_fight(disciple: Disciple) -> bool:
	if disciple == null or disciple.injured or disciple.tribulating: return false
	if disciple.position == Enums.Position.ZONG_ZHU: return false
	if disciple.position == Enums.Position.FENG_ZHU: return false
	return not disciple.tileId.is_empty()


# ---------------------------------------------------------------------------
# 内部工具
# ---------------------------------------------------------------------------

static func _relief_height(config: Dictionary, tile: HexTile) -> float:
	var relief: Dictionary = config["map"]["relief"].get(tile.relief, {})
	return float(relief.get("height", 0.0))


static func _sect_of(state: GameState, sect_id: String) -> Sect:
	for sect: Sect in state.sects:
		if sect.id == sect_id: return sect
	return null


static func _faction_name(config: Dictionary, faction: String) -> String:
	var flavors: Dictionary = config["faction"]["flavors"]
	if flavors.has(faction):
		return str((flavors[faction] as Dictionary).get("displayName", faction))
	return faction


static func _material_name(config: Dictionary, material: String) -> String:
	var strategic: Dictionary = config["resources"].get("strategic", {})
	if strategic.has(material):
		return str((strategic[material] as Dictionary).get("displayName", material))
	return material
