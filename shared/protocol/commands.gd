class_name Commands
extends RefCounted
## 命令名常量（lowerCamelCase，与 1.0 同名）。
##
## 唯一权威：docs/REQUIREMENTS_2.0.md §6.7「2.0 命令清单（69 条 + ping）」。
## 规则层 / 网络层 / 客户端一律引用本文件常量，**禁止散落命令名字符串字面量**。
##
## R0 只登记 ping；后续里程碑在此追加（每追加一条，同步更新 hello.implementedCommands）。

const PING: String = "ping"
const NEW_GAME: String = "newGame"
const GET_STATE: String = "getState"

# --- R2：回合状态机 + 六边形移动 ---
const FINISH_TURN: String = "finishTurn"
const BEGIN_PLAYER_TURN: String = "beginPlayerTurn"
const NEXT_TURN: String = "nextTurn"
const MOVE_DISCIPLE: String = "moveDisciple"
const QUERY_MOVE_RANGE: String = "queryMoveRange"

# --- R3：经济结算 + 灵峰/城市 + 建筑/区域/劳力/改良/道路 ---
const FOUND_SPIRIT_PEAK: String = "foundSpiritPeak"
const APPOINT_BUILDER: String = "appointBuilder"
const CONSTRUCT_BUILDING: String = "constructBuilding"
const QUERY_BUILD_OPTIONS: String = "queryBuildOptions"
const OPEN_CAVE: String = "openCave"
const FORTIFY_PEAK: String = "fortifyPeak"
const FOUND_DISTRICT: String = "foundDistrict"
const QUERY_DISTRICT_SITES: String = "queryDistrictSites"
const ASSIGN_WORKER: String = "assignWorker"
const UNASSIGN_WORKER: String = "unassignWorker"
const QUERY_ASSIGNABLE_TILES: String = "queryAssignableTiles"
const QUERY_CITY_DETAIL: String = "queryCityDetail"
const BUILD_IMPROVEMENT: String = "buildImprovement"
const REPAIR_IMPROVEMENT: String = "repairImprovement"
const QUERY_IMPROVEMENT_OPTIONS: String = "queryImprovementOptions"

# --- R4：道统科技树 + 修炼/突破/渡劫 + 项目/研究队列 + 收徒 ---
const RESEARCH_DAO: String = "researchDao"
const HOLD_RECRUITMENT: String = "holdRecruitment"
const QUERY_PROJECT_QUEUE: String = "queryProjectQueue"
const CANCEL_PROJECT: String = "cancelProject"
const ACCELERATE_PROJECT: String = "accelerateProject"
