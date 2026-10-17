class_name FactionRules
extends RefCounted
## 三流派特性的**唯一实现出口**（PRD `REQUIREMENTS_2.0.md` §1.1）。
##
## 只读 `faction.*` 配置，不内联任何数值；所有倍率都返回「已应用」的结果，调用方直接用。
##
## 已落地（R3/R4 范围内、PRD 原文明确）：
##   - 宗门流 `buildSpeedBonus`        → 营造工期缩短（「营造 +30%」）
##   - 宗门流 `subPeakCostReduction`   → 副峰（分峰）建筑造价降低（「副峰花费 −20%」）
##   - 宗门流 `uniqueBuildingDefenseBonus` → 护山剑阵落成防御加成（在 `CityAction._complete_building` 内）
##   - 家族流 `peakBuildCostPenalty`   → 建筑造价上浮（「建峰花费 +50%」）
##   - 家族流 `bloodLineSpeedBonus`    → 血脉弟子修炼加速（「血脉修炼 +40%」）
##   - 家族流 `zuCiCultivationBonus`   → 本宗有祖祠时血脉弟子再加速（「祖祠修炼 +25%」）
##
## **未落地**（PRD 未给可计算口径或属后续里程碑）见 `docs/PROTOCOL_2.0.md` §11.2。

## 副峰（分峰）建筑：受 `subPeakCostReduction` 影响。
## 取值与 `Enums.Building` 的 4 个 `*_FEN_FENG` 一致，不含核心建筑。
const SUB_PEAK_BUILDINGS: Array[String] = [
	"XIU_LIAN_FEN_FENG", "DAN_TANG_FEN_FENG", "QI_TANG_FEN_FENG", "JIANG_DAO_FEN_FENG",
]

const ZONG_MEN: String = "ZONG_MEN"
const JIA_ZU: String = "JIA_ZU"
const GUO_JIA: String = "GUO_JIA"


## 营造工期：宗门流按 `buildSpeedBonus` 缩短（四舍五入，下限 1 回合）。
## 适用：建筑、区域、洞府、灵峰加固——凡「营造」类项目一律走本函数。
static func build_turns(config: Dictionary, sect: Sect, base_turns: int) -> int:
	var turns: int = base_turns
	if sect != null and sect.factionType == ZONG_MEN:
		var bonus: float = float(config["faction"]["zongMen"]["buildSpeedBonus"])
		turns = int(round(float(base_turns) * (1.0 - bonus)))
	return maxi(1, turns)


## 建筑造价：宗门流副峰 −`subPeakCostReduction`；家族流全体 +`peakBuildCostPenalty`。
## 两者互斥（一个宗只有一个流派），故用 if/elif 而非累乘。
static func building_cost(config: Dictionary, sect: Sect, building_type: String, base_cost: int) -> int:
	if sect == null:
		return base_cost
	var cost: float = float(base_cost)
	if sect.factionType == ZONG_MEN and SUB_PEAK_BUILDINGS.has(building_type):
		cost *= 1.0 - float(config["faction"]["zongMen"]["subPeakCostReduction"])
	elif sect.factionType == JIA_ZU:
		cost *= 1.0 + float(config["faction"]["jiaZu"]["peakBuildCostPenalty"])
	return maxi(1, int(round(cost)))


## 修炼速度倍率：仅家族流的**血脉弟子**受益（非血脉弟子不受 `bloodLineSpeedBonus` 影响）。
## 本宗任一灵峰有祖祠（`ZU_CI`）时再乘 `zuCiCultivationBonus`。
static func cultivation_multiplier(config: Dictionary, sect: Sect, disciple: Disciple) -> float:
	if sect == null or disciple == null or not disciple.bloodLine:
		return 1.0
	if sect.factionType != JIA_ZU:
		return 1.0
	var multiplier: float = 1.0 + float(config["faction"]["jiaZu"]["bloodLineSpeedBonus"])
	if sect_building_count(sect, "ZU_CI") > 0:
		multiplier *= 1.0 + float(config["faction"]["jiaZu"]["zuCiCultivationBonus"])
	return multiplier


## 宗级建筑计数（跨该宗所有灵峰）。
static func sect_building_count(sect: Sect, building_type: String) -> int:
	if sect == null:
		return 0
	var count: int = 0
	for peak: SpiritPeak in sect.spiritPeaks:
		count += CityRules.building_count(peak, building_type)
	return count
