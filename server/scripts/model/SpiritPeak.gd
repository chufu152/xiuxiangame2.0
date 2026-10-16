class_name SpiritPeak
extends RefCounted

var id: String = ""
var name: String = ""
var sectId: String = ""
var tileId: String = ""
var capital: bool = true
var level: int = 0
var population: int = 0
var capacity: int = 0
var defense: int = 0
var qiYun: int = 0
var qiYunMax: int = 0
var stability: float = 0.0
var housing: int = 0
var fengZhuId: String = ""
var buildings: Dictionary = {}
var districts: Array[Dictionary] = []

func to_dict() -> Dictionary:
	return {"id": id, "name": name, "sectId": sectId, "tileId": tileId, "capital": capital, "level": level, "population": population, "capacity": capacity, "defense": defense, "qiYun": qiYun, "qiYunMax": qiYunMax, "stability": stability, "housing": housing, "fengZhuId": fengZhuId, "buildings": buildings.duplicate(true), "districts": districts.duplicate(true)}
