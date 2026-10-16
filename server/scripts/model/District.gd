class_name District
extends RefCounted
## 城市区域（R3）：灵峰辐射范围内独立占地的一块功能分区。
##
## 字段对齐 docs/PROTOCOL_2.0.md §4 `queryCityDetail.districts[]`
## `{id, name, type, typeName, level, populationAssigned, buildings[]}`，另带 `tileId`（落位地块）。
##
## `SHOU_FU_QU` 首府区由灵峰自带（开局铺设），收纳核心建筑；其余 5 种由 `foundDistrict` 建成。
## `buildings` 存该区域已收纳的建筑**类型名**（与 `SpiritPeak.buildings` 的键一致）。

var id: String = ""
var name: String = ""
var type: String = ""
var typeName: String = ""
var level: int = 1
var populationAssigned: int = 0
var buildings: Array[String] = []
var tileId: String = ""

func to_dict() -> Dictionary:
	return {"id": id, "name": name, "type": type, "typeName": typeName, "level": level, "populationAssigned": populationAssigned, "buildings": buildings.duplicate(), "tileId": tileId}
