class_name VisionCalculator
extends RefCounted

static func recalculate(state: GameState, config: Dictionary) -> void:
	for sect: Sect in state.sects:
		var visible: Dictionary = {}
		# R4 回填：已解锁道法的 `VISION_BONUS`（`fa_xiu`/`tian_ji` 各 +1），经 `DaoRules.effect_sum` 唯一出口。
		var sect_bonus: int = DaoRules.vision_bonus(state, config, sect)
		for peak: SpiritPeak in sect.spiritPeaks:
			_reveal(state, peak.tileId, int(config["vision"]["peakVision"]), visible, config, sect_bonus)
		for node: GameNode in state.nodes.values():
			if node.ownerSectId == sect.id: _reveal(state, node.tileId, int(config["vision"]["nodeVision"]), visible, config, sect_bonus)
		for disciple: Disciple in sect.disciples:
			var radius: int = int(config["vision"]["discipleVisionByRealm"][disciple.realm]) + int(config["warfare"]["unitClasses"][disciple.unitClass]["visionBonus"])
			_reveal(state, disciple.tileId, radius, visible, config, sect_bonus)
		sect.visibleTiles.clear()
		for key: String in state.tiles:
			if visible.has(key):
				sect.visibleTiles.append(key)
				if not sect.exploredTiles.has(key): sect.exploredTiles.append(key)
		sect.exploredTiles.sort()
		sect.visibleTiles.sort()
		for key: String in sect.visibleTiles:
			var tile: HexTile = state.tiles[key]
			sect.tileSnapshots[key] = tile.to_dict()
			if not tile.nodeId.is_empty() and state.nodes.has(tile.nodeId):
				var node: GameNode = state.nodes[tile.nodeId]
				sect.nodeSnapshots[node.id] = node.to_dict()
		for peak_id: String in sect.peakSnapshots.keys():
			if visible.has(sect.peakSnapshots[peak_id]["tileId"]): sect.peakSnapshots.erase(peak_id)
		for owner: Sect in state.sects:
			for peak: SpiritPeak in owner.spiritPeaks:
				if owner == sect or visible.has(peak.tileId): sect.peakSnapshots[peak.id] = peak.to_dict()

static func _reveal(state: GameState, center: String, radius: int, visible: Dictionary, config: Dictionary, sect_bonus: int = 0) -> void:
	var tile: HexTile = state.tiles[center]
	radius += sect_bonus + int(config["map"]["relief"][tile.relief]["visionBonus"])
	for candidate: HexTile in state.tiles.values():
		if not bool(config["vision"]["enabled"]) or Hex.distance(Vector2i(tile.q, tile.r), Vector2i(candidate.q, candidate.r)) <= radius: visible[candidate.id] = true
