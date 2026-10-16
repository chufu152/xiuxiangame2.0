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

class Position:
	const ALL: Array[String] = ["ZA_YI", "WAI_MEN", "NEI_MEN", "QIN_CHUAN", "FENG_ZHU", "ZHANG_LAO", "ZONG_ZHU"]

class SpiritRootType:
	const ALL: Array[String] = ["JIN", "MU", "SHUI", "HUO", "TU", "FENG", "LEI", "ZA"]

class UnitClass:
	const PU_TONG: String = "PU_TONG"
	const ALL: Array[String] = [PU_TONG, "JIAN_XIU", "FA_XIU", "TI_XIU", "QI_JI", "FU_XIU", "JI_GUAN", "JIAN_ZHEN_SHI", "XUE_MAI_XIU_SHI", "JI_GUAN_JUN_TUAN"]
	const KINDS: Array[String] = ["MELEE", "RANGED", "ANTI_CAVALRY", "CAVALRY", "SUPPORT", "SIEGE"]

class Building:
	const ALL: Array[String] = ["SHAN_MEN", "ZONG_ZHU_DA_DIAN", "CANG_JING_GE", "XIU_LIAN_FEN_FENG", "DAN_TANG_FEN_FENG", "QI_TANG_FEN_FENG", "JIANG_DAO_FEN_FENG", "HU_SHAN_JIAN_ZHEN", "ZU_CI", "WANG_CHAO_DI_DU"]

class District:
	const ALL: Array[String] = ["SHOU_FU_QU", "XIU_LIAN_QU", "DAN_QI_QU", "CANG_JING_QU", "FA_TAN_QU", "SHI_JI_QU"]

class Improvement:
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
