class_name Enums
extends RefCounted

class BaseTerrain:
	const LING_FIELDS: String = "LING_FIELDS"
	const SPIRIT_PLAIN: String = "SPIRIT_PLAIN"
	const BARREN: String = "BARREN"
	const ALL: Array[String] = [LING_FIELDS, SPIRIT_PLAIN, BARREN]

class BaseTerrainAlgorithm:
	const EQUAL_WEIGHT_NO_AUTHORITATIVE_PROBABILITIES: String = "equalWeightNoAuthoritativeProbabilities"
	const ALL: Array[String] = [EQUAL_WEIGHT_NO_AUTHORITATIVE_PROBABILITIES]

class Relief:
	const FLAT: String = "FLAT"
	const HILL: String = "HILL"
	const MOUNTAIN: String = "MOUNTAIN"
	const ALL: Array[String] = [FLAT, HILL, MOUNTAIN]

class Feature:
	const SPIRIT_FOREST: String = "SPIRIT_FOREST"
	const MIRE: String = "MIRE"
	const ALL: Array[String] = [SPIRIT_FOREST, MIRE]

class NodeType:
	const LING_TIAN: String = "LING_TIAN"
	const LING_MAI: String = "LING_MAI"
	const JI_YUAN: String = "JI_YUAN"
	const MI_JING: String = "MI_JING"
	const LING_QUAN: String = "LING_QUAN"
	const LING_FENG: String = "LING_FENG"
	const ALL: Array[String] = [LING_TIAN, LING_MAI, JI_YUAN, MI_JING, LING_QUAN, LING_FENG]
	const SPAWN: Array[String] = [LING_TIAN, LING_MAI, JI_YUAN, MI_JING, LING_QUAN]
	const CHANCE_KEYS: Array[String] = ["lingTian", "lingMai", "jiYuan", "miJing", "lingQuan"]

class FactionType:
	const ZONG_MEN: String = "ZONG_MEN"
	const JIA_ZU: String = "JIA_ZU"
	const GUO_JIA: String = "GUO_JIA"
	const ALL: Array[String] = [ZONG_MEN, JIA_ZU, GUO_JIA]

class Realm:
	const LIAN_QI: String = "LIAN_QI"
	const ZHU_JI: String = "ZHU_JI"
	const JIN_DAN: String = "JIN_DAN"
	const YUAN_YING: String = "YUAN_YING"
	const HUA_SHEN: String = "HUA_SHEN"
	const ALL: Array[String] = [LIAN_QI, ZHU_JI, JIN_DAN, YUAN_YING, HUA_SHEN]
	## R4 新增：境界显示名（纯文案，供事件日志与客户端面板使用）。
	const NAMES: Dictionary = {"LIAN_QI": "炼气", "ZHU_JI": "筑基", "JIN_DAN": "金丹", "YUAN_YING": "元婴", "HUA_SHEN": "化神"}

class Position:
	const ZA_YI: String = "ZA_YI"
	const WAI_MEN: String = "WAI_MEN"
	const NEI_MEN: String = "NEI_MEN"
	const QIN_CHUAN: String = "QIN_CHUAN"
	const FENG_ZHU: String = "FENG_ZHU"
	const ZHANG_LAO: String = "ZHANG_LAO"
	const ZONG_ZHU: String = "ZONG_ZHU"
	const ALL: Array[String] = [ZA_YI, WAI_MEN, NEI_MEN, QIN_CHUAN, FENG_ZHU, ZHANG_LAO, ZONG_ZHU]
	## R4 新增：岗位显示名（纯文案）。
	const NAMES: Dictionary = {"ZA_YI": "杂役", "WAI_MEN": "外门", "NEI_MEN": "内门", "QIN_CHUAN": "亲传", "FENG_ZHU": "峰主", "ZHANG_LAO": "长老", "ZONG_ZHU": "宗主"}

class SpiritRootType:
	const ALL: Array[String] = ["JIN", "MU", "SHUI", "HUO", "TU", "FENG", "LEI", "ZA"]

class UnitClass:
	const PU_TONG: String = "PU_TONG"
	const ALL: Array[String] = [PU_TONG, "JIAN_XIU", "FA_XIU", "TI_XIU", "QI_JI", "FU_XIU", "JI_GUAN", "JIAN_ZHEN_SHI", "XUE_MAI_XIU_SHI", "JI_GUAN_JUN_TUAN"]
	const KINDS: Array[String] = ["MELEE", "RANGED", "ANTI_CAVALRY", "CAVALRY", "SUPPORT", "SIEGE"]

class Building:
	const SHAN_MEN: String = "SHAN_MEN"
	const ZONG_ZHU_DA_DIAN: String = "ZONG_ZHU_DA_DIAN"
	const CANG_JING_GE: String = "CANG_JING_GE"
	const XIU_LIAN_FEN_FENG: String = "XIU_LIAN_FEN_FENG"
	const DAN_TANG_FEN_FENG: String = "DAN_TANG_FEN_FENG"
	const QI_TANG_FEN_FENG: String = "QI_TANG_FEN_FENG"
	const JIANG_DAO_FEN_FENG: String = "JIANG_DAO_FEN_FENG"
	const HU_SHAN_JIAN_ZHEN: String = "HU_SHAN_JIAN_ZHEN"
	const ZU_CI: String = "ZU_CI"
	const WANG_CHAO_DI_DU: String = "WANG_CHAO_DI_DU"
	const ALL: Array[String] = [SHAN_MEN, ZONG_ZHU_DA_DIAN, CANG_JING_GE, XIU_LIAN_FEN_FENG, DAN_TANG_FEN_FENG, QI_TANG_FEN_FENG, JIANG_DAO_FEN_FENG, HU_SHAN_JIAN_ZHEN, ZU_CI, WANG_CHAO_DI_DU]
	## 展示名（出处：REQUIREMENTS_2.0 §4.7 建筑表 / 1.0 `BuildingType`）。
	const NAMES: Dictionary = {"SHAN_MEN": "山门", "ZONG_ZHU_DA_DIAN": "宗主大殿", "CANG_JING_GE": "藏经阁", "XIU_LIAN_FEN_FENG": "修炼分峰", "DAN_TANG_FEN_FENG": "丹堂分峰", "QI_TANG_FEN_FENG": "器堂分峰", "JIANG_DAO_FEN_FENG": "讲道台分峰", "HU_SHAN_JIAN_ZHEN": "护山剑阵", "ZU_CI": "祖祠", "WANG_CHAO_DI_DU": "王朝帝都"}
	## 核心建筑（归首府区/藏经区）；非核心者为分峰（归对应区域）。
	const CORE: Array[String] = [SHAN_MEN, ZONG_ZHU_DA_DIAN, CANG_JING_GE, HU_SHAN_JIAN_ZHEN, ZU_CI, WANG_CHAO_DI_DU]

## 区域类型枚举（内层类名加 `Type` 后缀，避免与全局模型类 `District` 同名冲突）。
class DistrictType:
	const SHOU_FU_QU: String = "SHOU_FU_QU"
	const XIU_LIAN_QU: String = "XIU_LIAN_QU"
	const DAN_QI_QU: String = "DAN_QI_QU"
	const CANG_JING_QU: String = "CANG_JING_QU"
	const FA_TAN_QU: String = "FA_TAN_QU"
	const SHI_JI_QU: String = "SHI_JI_QU"
	const ALL: Array[String] = [SHOU_FU_QU, XIU_LIAN_QU, DAN_QI_QU, CANG_JING_QU, FA_TAN_QU, SHI_JI_QU]
	## 展示名（出处：REQUIREMENTS_2.0 §4.7 区域表 / 1.0 `DistrictType`）。
	const NAMES: Dictionary = {"SHOU_FU_QU": "首府区", "XIU_LIAN_QU": "修炼区", "DAN_QI_QU": "丹器区", "CANG_JING_QU": "藏经区", "FA_TAN_QU": "法坛区", "SHI_JI_QU": "坊市区"}
	## 玩家可建区域（首府区为灵峰自带，不可自由选址）。
	const BUILDABLE: Array[String] = [XIU_LIAN_QU, DAN_QI_QU, CANG_JING_QU, FA_TAN_QU, SHI_JI_QU]

## 改良类型枚举（内层类名加 `Type` 后缀，避免与全局模型类 `Improvement` 同名冲突）。
class ImprovementType:
	const ALL: Array[String] = ["LING_TIAN_TI_TIAN", "LING_KUANG", "CAI_SHI_CHANG", "YAO_YUAN", "JU_LING_ZHEN", "QING_SHI_DAO_LU", "DONG_FU", "LING_QUAN_XIU_SHAN"]

class ResourceKind:
	const ALL: Array[String] = ["spiritPower", "spiritStones", "workPower", "prestige", "qiYun", "food", "daoPoints", "tian_jing", "xuan_tie", "ling_mu", "ling_cha", "yun_jin", "ling_yu"]
	const MATERIALS: Array[String] = ["tian_jing", "xuan_tie", "ling_mu"]
	const LUXURIES: Array[String] = ["ling_cha", "yun_jin", "ling_yu"]

class TurnPhase:
	const PLAYER_ACTION: String = "PLAYER_ACTION"
	const ALL: Array[String] = ["TURN_START", "SPIRIT_PEAK", PLAYER_ACTION, "SETTLEMENT", "AI_ACTION", "VICTORY_CHECK"]

class Instruction:
	const ALL: Array[String] = ["IDLE", "GARRISON", "CULTIVATE", "BUILD", "EXPLORE"]

class Difficulty:
	const ALL: Array[String] = ["easy", "normal", "hard"]
