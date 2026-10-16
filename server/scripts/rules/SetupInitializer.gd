class_name SetupInitializer
extends RefCounted

static func initialize(state: GameState, params: Dictionary, config: Dictionary, rng: RngService) -> void:
	var setup: Dictionary = config["map"]["setup"]
	var difficulty: Dictionary = config["difficulty"]["levels"][state.difficulty]
	for index: int in range(int(setup["sectCount"])):
		var sect: Sect = Sect.new()
		sect.id = "sect_%d" % index
		sect.player = index == 0
		sect.name = str(params["sectName"]) if sect.player else str(setup["aiNames"][index - 1])
		sect.factionType = str(params["playerFaction"]) if sect.player else str(setup["aiFactions"][index - 1])
		sect.resources = config["resources"]["initial"].duplicate(true)
		sect.resources["spiritStones"] += difficulty["playerStartStonesBonus"] if sect.player else difficulty["aiStartStonesBonus"]
		if not sect.player: sect.resources["workPower"] += difficulty["aiStartWorkPowerBonus"]
		var peak: SpiritPeak = SpiritPeak.new()
		peak.id = "peak_%d" % index
		peak.name = sect.name + "主峰"
		peak.sectId = sect.id
		peak.tileId = state.spawnTiles[index]
		peak.level = int(setup["peakLevel"])
		peak.population = int(config["city"]["startPopulation"])
		peak.capacity = int(config["spiritPeak"]["baseDiscipleCapacity"])
		peak.defense = int(config["spiritPeak"]["baseDefense"])
		peak.qiYun = int(setup["peakQiYun"])
		peak.qiYunMax = int(config["spiritPeak"]["baseQiYunMax"])
		peak.stability = float(config["city"]["stabilityBase"])
		peak.housing = int(config["city"]["housingBase"]) + peak.level * int(config["city"]["housingPerPeakLevel"])
		peak.food = 0.0
		peak.foodProgress = 0.0
		peak.freeWorkers = peak.population
		sect.spiritPeaks.append(peak)
		var tile: HexTile = state.tiles[peak.tileId]
		tile.ownerSectId = sect.id
		var capital_district: District = District.new()
		capital_district.id = "capital_%d" % index
		capital_district.name = Enums.DistrictType.NAMES[Enums.DistrictType.SHOU_FU_QU]
		capital_district.type = Enums.DistrictType.SHOU_FU_QU
		capital_district.typeName = Enums.DistrictType.NAMES[Enums.DistrictType.SHOU_FU_QU]
		capital_district.level = 1
		capital_district.tileId = tile.id
		peak.districts.append(capital_district)
		tile.districtId = capital_district.id
		if not tile.nodeId.is_empty(): state.nodes[tile.nodeId].ownerSectId = sect.id
		for unit_index: int in range(1 + int(setup["outerCount"])):
			var disciple: Disciple = Disciple.new()
			disciple.id = "disciple_%d_%d" % [index, unit_index]
			disciple.name = sect.name + ("宗主" if unit_index == 0 else "外门%d" % unit_index)
			disciple.sectId = sect.id
			disciple.tileId = peak.tileId
			disciple.realm = str(setup["leaderRealm"] if unit_index == 0 else setup["outerRealm"])
			disciple.position = str(setup["leaderPosition"] if unit_index == 0 else setup["outerPosition"])
			disciple.rootGrade = int(setup["rootGrade"])
			var roots: Array = setup["rootTypes"]
			for root_index: int in range(int(setup["rootCount"])):
				disciple.spiritRoots.append(str(roots[rng.next_int(0, roots.size() - 1)]))
			disciple.unitClass = str(setup["unitClass"])
			# 移动力公式唯一来源：开局与每回合开始共用 MoveRules，避免两处漂移。
			var move_points: int = MoveRules.calculate_max_move_points(disciple, config)
			disciple.maxMovePoints = move_points
			disciple.movePoints = move_points
			disciple.attacksRemaining = int(config["warfare"]["attacksPerTurn"])
			if unit_index == 0:
				disciple.assignedPeakId = peak.id
				peak.fengZhuId = disciple.id
				if sect.factionType == Enums.FactionType.JIA_ZU:
					disciple.bloodLine = true
					disciple.directLine = true
					disciple.generation = int(setup["generation"])
			sect.disciples.append(disciple)
		state.sects.append(sect)
	state.playerSectId = state.sects[0].id
