class_name StateView
extends RefCounted

static func build(state: GameState, config: Dictionary) -> Dictionary:
	var player: Sect = null
	for sect: Sect in state.sects:
		if sect.id == state.playerSectId: player = sect
	# 自有实体（己方主峰所在地块、己方归属地块、己方节点所在地块）在任何视野状态下都必须实时，
	# 不能被最后可见快照冻结——否则拆峰/改良/产出变化在玩家自己的地盘上不可见。
	var self_owned: Dictionary = {}
	for peak: SpiritPeak in player.spiritPeaks: self_owned[peak.tileId] = true
	for tile: HexTile in state.tiles.values():
		if tile.ownerSectId == player.id: self_owned[tile.id] = true
		elif not tile.nodeId.is_empty() and state.nodes.has(tile.nodeId) and state.nodes[tile.nodeId].ownerSectId == player.id: self_owned[tile.id] = true
	var tiles: Dictionary = {}
	for tile: HexTile in state.tiles.values():
		if player.visibleTiles.has(tile.id) or self_owned.has(tile.id):
			player.tileSnapshots[tile.id] = tile.to_dict()
			if not tile.nodeId.is_empty() and state.nodes.has(tile.nodeId):
				var node: GameNode = state.nodes[tile.nodeId]
				player.nodeSnapshots[node.id] = node.to_dict()
		if player.exploredTiles.has(tile.id) and player.tileSnapshots.has(tile.id):
			tiles[tile.id] = player.tileSnapshots[tile.id].duplicate(true)
		else:
			var shell: Dictionary = tile.to_dict()
			for field: String in shell:
				if field not in ["id", "q", "r"]: shell[field] = null
			tiles[tile.id] = shell
	var nodes: Dictionary = {}
	for tile_data: Dictionary in tiles.values():
		if tile_data["nodeId"] != null and player.nodeSnapshots.has(tile_data["nodeId"]):
			var node_id: String = tile_data["nodeId"]
			var snapshot: Dictionary = player.nodeSnapshots[node_id].duplicate(true)
			if snapshot["ownerSectId"] != player.id:
				# 资源储量、产出、冷却与驻守编成是敌方/中立内部信息，不是固定地图地形。
				# R5：`garrisonDiscipleIds` 一并隐藏——否则可白嫖敌节点的守军构成。
				for field: String in ["reserve", "output", "cooldown", "garrisonDiscipleIds"]: snapshot.erase(field)
			nodes[node_id] = snapshot
	# 改良（R3）：与节点/灵峰同一套迷雾规则——己方/可见格实时，explored-but-not-visible 冻结为最后可见快照。
	# 先清理已不存在于世界的旧快照（被掠夺/拆除后不留幽灵改良），再对可见格实时刷新。
	for remembered_id: String in player.improvementSnapshots.keys():
		if _improvement_by_id(state, remembered_id) == null: player.improvementSnapshots.erase(remembered_id)
	for tile: HexTile in state.tiles.values():
		if (player.visibleTiles.has(tile.id) or self_owned.has(tile.id)) and not tile.improvementId.is_empty():
			var live: Improvement = _improvement_by_id(state, tile.improvementId)
			if live != null: player.improvementSnapshots[live.id] = live.to_dict()
	var improvements: Dictionary = {}
	for tile_data: Dictionary in tiles.values():
		if tile_data["improvementId"] != null and player.improvementSnapshots.has(tile_data["improvementId"]):
			var imp_id: String = tile_data["improvementId"]
			improvements[imp_id] = player.improvementSnapshots[imp_id].duplicate(true)
	var sects: Array[Dictionary] = []
	for sect: Sect in state.sects:
		var public: Dictionary = sect.public_info()
		var disciples: Array[Dictionary] = []
		var peaks: Array[Dictionary] = []
		for disciple: Disciple in sect.disciples:
			if sect.player or player.visibleTiles.has(disciple.tileId): disciples.append(disciple.to_dict())
		for remembered_id: String in player.peakSnapshots.keys():
			var old: Dictionary = player.peakSnapshots[remembered_id]
			# 己方主峰永远是实时的，不进快照；旧快照必须清掉，否则拆峰后会残留幽灵峰。
			if old["sectId"] == sect.id and (sect.player or player.visibleTiles.has(old["tileId"])): player.peakSnapshots.erase(remembered_id)
		for peak: SpiritPeak in sect.spiritPeaks:
			if sect.player or player.visibleTiles.has(peak.tileId): player.peakSnapshots[peak.id] = peak.to_dict()
		# 快照独立于当前实体列表：隐蔽拆除/易主不改变最后看见的城市。
		for snapshot: Dictionary in player.peakSnapshots.values():
			if snapshot["sectId"] == sect.id:
				var remembered: Dictionary = snapshot.duplicate(true)
				if not sect.player: remembered.erase("fengZhuId")
				peaks.append(remembered)
		public["disciples"] = disciples
		public["spiritPeaks"] = peaks
		if sect.player:
			public["resources"] = sect.resources.duplicate(true)
			# R4：道统树面板数据。**仅己方**下发（敌方道统属隐藏信息）。
			# 三态与 blocker 由服务端算好，客户端零规则（PROTOCOL §12.4）。
			public["unlockedDaoIds"] = sect.unlockedDaoIds.duplicate()
			public["daoOptions"] = _dao_options(state, config, sect)
		sects.append(public)
	var heights: Dictionary = {}
	for relief: String in Enums.Relief.ALL: heights[relief] = config["map"]["relief"][relief]["height"]
	return {"metadata": {"turn": state.turn, "phase": state.phase, "mapWidth": state.width, "mapHeight": state.height, "playerSectId": state.playerSectId, "randomSeed": str(state.seed), "difficultyId": state.difficulty}, "turn": state.turn, "phase": state.phase, "mapWidth": state.width, "mapHeight": state.height, "playerSectId": state.playerSectId, "randomSeed": str(state.seed), "difficultyId": state.difficulty, "gameOver": state.gameOver, "winType": "", "winnerSectId": "", "pendingVictoryChoices": [], "tiles": tiles, "nodes": nodes, "improvements": improvements, "sects": sects, "visibleTiles": player.visibleTiles.duplicate(), "exploredTiles": player.exploredTiles.duplicate(), "eventLog": state.eventLog.duplicate(), "renderHints": {"reliefHeight": heights}}


static func _improvement_by_id(state: GameState, improvement_id: String) -> Improvement:
	if improvement_id.is_empty():
		return null
	for sect: Sect in state.sects:
		for improvement: Improvement in sect.improvements:
			if improvement.id == improvement_id:
				return improvement
	return null


## R4：21 条道法的面板视图（含三态 `state` 与 `blocker`、按本宗折扣后的实际费用与工期）。
static func _dao_options(state: GameState, config: Dictionary, sect: Sect) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dao: Dao in DaoRules.all_daos(config):
		var status: Dictionary = DaoRules.dao_state(state, config, sect, dao.id)
		var entry: Dictionary = dao.to_dict()
		entry["eraIndex"] = DaoRules.era_index(config, dao.era)
		entry["daoPointCost"] = DaoRules.dao_point_cost(config, dao)
		entry["spiritPowerCost"] = DaoRules.work_cost(config, dao)
		entry["turns"] = DaoRules.research_turns(config, sect, dao)
		entry["state"] = str(status["state"])
		entry["blocker"] = str(status["blocker"])
		out.append(entry)
	return out
