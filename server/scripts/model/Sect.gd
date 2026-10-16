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

func public_info() -> Dictionary:
	return {"id": id, "name": name, "factionType": factionType, "player": player}
