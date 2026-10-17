class_name MapGenerator
extends RefCounted

static func generate(width: int, height: int, rng: RngService, config: Dictionary) -> GameState:
	var state: GameState = GameState.new()
	state.width = width
	state.height = height
	state.rng = rng
	var map_config: Dictionary = config["map"]
	for r: int in range(height):
		for q: int in range(width):
			var tile: HexTile = HexTile.new()
			tile.id = Hex.id(q, r)
			tile.q = q
			tile.r = r
			tile.baseTerrain = Enums.BaseTerrain.ALL[rng.next_int(0, Enums.BaseTerrain.ALL.size() - 1)]
			state.tiles[tile.id] = tile
	_select_spawns(state)
	var protected: Dictionary = _protected_tiles(state, int(map_config["setup"]["safeRadius"]))
	_generate_relief(state, protected, rng, map_config)
	for tile: HexTile in state.tiles.values():
		for feature: String in Enums.Feature.ALL:
			var definition: Dictionary = map_config["features"][feature]
			if definition["reliefs"].has(tile.relief) and rng.chance(float(definition["chance"])):
				tile.features.append(feature)
				break
		if not protected.has(tile.id): tile.danger = rng.chance(float(map_config["dangerTileChance"]))
	_generate_rivers(state, rng, map_config)
	_generate_nodes(state, rng, config)
	_secure_resources(state, config)
	_generate_luxuries(state, rng, config)
	return state

static func _select_spawns(state: GameState) -> void:
	var targets: Array[Vector2i] = [Vector2i(state.width / 2, state.height / 2), Vector2i(1, 1), Vector2i(state.width - 2, 1), Vector2i(1, state.height - 2)]
	for target: Vector2i in targets:
		var nearest: String = ""
		var best: int = 2147483647
		for tile: HexTile in state.tiles.values():
			if state.spawnTiles.has(tile.id): continue
			var distance: int = Hex.distance(target, Vector2i(tile.q, tile.r))
			if distance < best:
				best = distance
				nearest = tile.id
		state.spawnTiles.append(nearest)

static func _protected_tiles(state: GameState, radius: int) -> Dictionary:
	var protected: Dictionary = {}
	for tile: HexTile in state.tiles.values():
		for spawn: String in state.spawnTiles:
			if Hex.distance(Vector2i(tile.q, tile.r), Hex.coords(spawn)) <= radius:
				protected[tile.id] = true
	# 在分配山岳之前保留连接出生点的最短通道，避免事后清山改变比例。
	for index: int in range(1, state.spawnTiles.size()):
		var current: Vector2i = Hex.coords(state.spawnTiles[index])
		var target: Vector2i = Hex.coords(state.spawnTiles[0])
		while current != target:
			protected[Hex.id(current.x, current.y)] = true
			var next: Vector2i = current
			var best: int = Hex.distance(current, target)
			for neighbor: Vector2i in Hex.neighbors(current):
				if state.tiles.has(Hex.id(neighbor.x, neighbor.y)) and Hex.distance(neighbor, target) < best:
					next = neighbor
					best = Hex.distance(neighbor, target)
			current = next
	return protected

static func _generate_relief(state: GameState, protected: Dictionary, rng: RngService, map_config: Dictionary) -> void:
	# 连续正弦山脊场排名；同一个随机源生成相位。没有独立噪声随机实例。
	var phase: float = rng.next_float() * TAU
	var direction: float = rng.next_float() * TAU
	var offset: float = rng.next_float() * TAU
	var scores: Dictionary = {}
	var candidates: Array[String] = []
	for tile: HexTile in state.tiles.values():
		var x: float = float(tile.q) / maxi(state.width - 1, 1)
		var y: float = float(tile.r) / maxi(state.height - 1, 1)
		var along: float = x * cos(direction) + y * sin(direction)
		var across: float = -x * sin(direction) + y * cos(direction)
		scores[tile.id] = cos(across * TAU + phase + 0.35 * sin(along * TAU + offset)) + 0.2 * cos(along * TAU + offset)
		if not protected.has(tile.id): candidates.append(tile.id)
	candidates.sort_custom(func(a: String, b: String) -> bool: return float(scores[a]) > float(scores[b]))
	var mountain_count: int = mini(roundi(state.tiles.size() * float(map_config["relief"][Enums.Relief.MOUNTAIN]["ratio"])), candidates.size())
	var mountains: Dictionary = {}
	# 以连续场最高点扩展邻接山脊，禁止将高排名孤点直接当山脉。
	while mountains.size() < mountain_count:
		var chosen: String = ""
		var best_score: float = -INF
		for key: String in candidates:
			if mountains.has(key): continue
			var connected: bool = mountains.is_empty()
			for neighbor: Vector2i in Hex.neighbors(Hex.coords(key)):
				connected = connected or mountains.has(Hex.id(neighbor.x, neighbor.y))
			if connected and float(scores[key]) > best_score:
				chosen = key
				best_score = float(scores[key])
		if chosen.is_empty():
			for key: String in candidates:
				if not mountains.has(key):
					chosen = key
					break
		mountains[chosen] = true
		state.tiles[chosen].relief = Enums.Relief.MOUNTAIN
	var flat_reserves: Dictionary = {}
	for spawn: String in state.spawnTiles:
		var reserve: String = spawn
		for neighbor: Vector2i in Hex.neighbors(Hex.coords(spawn)):
			var key: String = Hex.id(neighbor.x, neighbor.y)
			if state.tiles.has(key):
				reserve = key
				break
		for neighbor: Vector2i in Hex.neighbors(Hex.coords(spawn)):
			var key: String = Hex.id(neighbor.x, neighbor.y)
			if state.tiles.has(key) and not state.spawnTiles.has(key):
				reserve = key
				break
		flat_reserves[reserve] = true
	if flat_reserves.size() == state.tiles.size():
		flat_reserves.erase(state.spawnTiles[0])
	var hills: Array[String] = []
	for tile: HexTile in state.tiles.values():
		if not mountains.has(tile.id) and not flat_reserves.has(tile.id): hills.append(tile.id)
	hills.sort_custom(func(a: String, b: String) -> bool: return float(scores[a]) > float(scores[b]))
	var hill_count: int = mini(roundi(state.tiles.size() * float(map_config["relief"][Enums.Relief.HILL]["ratio"])), hills.size())
	for index: int in range(hill_count): state.tiles[hills[index]].relief = Enums.Relief.HILL

static func _vertex_key(point: Vector3) -> String:
	return "%d:%d" % [roundi(point.x * 1000), roundi(point.z * 1000)]

static func _river_graph(state: GameState, rng: RngService, map_config: Dictionary) -> Dictionary:
	var vertices: Dictionary = {}
	var edges: Array[Dictionary] = []
	var seen: Dictionary = {}
	for tile: HexTile in state.tiles.values():
		for edge: int in range(6):
			var endpoints: Array[Vector3] = Hex.edge_vertices(tile.q, tile.r, edge)
			var a: String = _vertex_key(endpoints[0])
			var b: String = _vertex_key(endpoints[1])
			var keys: Array[String] = [a, b]
			keys.sort()
			var key: String = "|".join(keys)
			var neighbor: Vector2i = Vector2i(tile.q, tile.r) + Hex.DIRECTIONS[edge]
			var boundary: bool = not state.tiles.has(Hex.id(neighbor.x, neighbor.y))
			var tile_height: float = float(map_config["relief"][tile.relief]["height"])
			for vertex: String in [a, b]:
				if not vertices.has(vertex): vertices[vertex] = {"height": tile_height, "edges": [], "boundary": false}
				vertices[vertex]["height"] = maxf(float(vertices[vertex]["height"]), tile_height)
				vertices[vertex]["boundary"] = bool(vertices[vertex]["boundary"]) or boundary
			if seen.has(key): continue
			seen[key] = true
			var index: int = edges.size()
			var neighbor_id: String = Hex.id(neighbor.x, neighbor.y)
			var source_high: bool = tile.relief != Enums.Relief.FLAT or (state.tiles.has(neighbor_id) and state.tiles[neighbor_id].relief != Enums.Relief.FLAT)
			edges.append({"a": a, "b": b, "tileId": tile.id, "edge": edge, "noise": rng.next_float(), "sourceHigh": source_high})
			vertices[a]["edges"].append(index)
			vertices[b]["edges"].append(index)
	return {"vertices": vertices, "edges": edges}

static func _generate_rivers(state: GameState, rng: RngService, map_config: Dictionary) -> void:
	var graph: Dictionary = _river_graph(state, rng, map_config)
	var vertices: Dictionary = graph["vertices"]
	var edges: Array[Dictionary] = graph["edges"]
	var river_config: Dictionary = map_config["river"]
	var minimum: int = ceili(edges.size() * float(river_config["edgeRatioMin"]))
	var maximum: int = floori(edges.size() * float(river_config["edgeRatioMax"]))
	var starts: Array[String] = []
	for vertex: String in vertices:
		if float(vertices[vertex]["height"]) >= float(map_config["relief"][Enums.Relief.HILL]["height"]): starts.append(vertex)
	# 高海拔优先，边界河源也允许（小图所有位置都在边界）。
	starts.sort_custom(func(a: String, b: String) -> bool: return float(vertices[a]["height"]) > float(vertices[b]["height"]))
	var used_edges: Dictionary = {}
	var target_sources: int = rng.next_int(int(river_config["sourcesMin"]), int(river_config["sourcesMax"]))
	for source: int in range(target_sources):
		var wanted: int = ceili(float(minimum - used_edges.size()) / (target_sources - source))
		if wanted <= 0: break
		var path: Array[Dictionary] = []
		for start: String in starts:
			path = _find_river_path(start, vertices, edges, used_edges, wanted, maximum - used_edges.size())
			if not path.is_empty(): break
		if path.is_empty(): continue
		state.riverPaths.append(path)
		for segment: Dictionary in path:
			used_edges[segment["graphEdge"]] = true
			var tile: HexTile = state.tiles[segment["tileId"]]
			var edge: int = segment["edge"]
			if not tile.riverEdges.has(edge): tile.riverEdges.append(edge)
			var neighbor: Vector2i = Vector2i(tile.q, tile.r) + Hex.DIRECTIONS[edge]
			var key: String = Hex.id(neighbor.x, neighbor.y)
			if state.tiles.has(key):
				var opposite: int = Hex.opposite(edge)
				if not state.tiles[key].riverEdges.has(opposite): state.tiles[key].riverEdges.append(opposite)
			segment.erase("graphEdge")
	for tile: HexTile in state.tiles.values(): tile.riverEdges.sort()

static func _find_river_path(start: String, vertices: Dictionary, edges: Array[Dictionary], used: Dictionary, minimum: int, maximum: int) -> Array[Dictionary]:
	var route: Array[String] = [start]
	var route_edges: Array[int] = []
	var visited: Dictionary = {start: true}
	var initial_options: Array = _river_options(start, vertices, edges, used, visited, false)
	initial_options = initial_options.filter(func(index: int) -> bool: return bool(edges[index]["sourceHigh"]))
	var options: Array[Array] = [initial_options]
	var work: int = 0
	var budget: int = edges.size() * 30
	while not route.is_empty() and work < budget:
		work += 1
		var current: String = route[-1]
		if route_edges.size() >= minimum and bool(vertices[current]["boundary"]):
			var result: Array[Dictionary] = []
			for index: int in range(route_edges.size()):
				var edge: Dictionary = edges[route_edges[index]]
				result.append({"tileId": edge["tileId"], "edge": edge["edge"], "startIndex": 0 if route[index] == edge["a"] else 1, "fromHeight": vertices[route[index]]["height"], "toHeight": vertices[route[index + 1]]["height"], "endsAtBoundary": index == route_edges.size() - 1, "graphEdge": route_edges[index]})
			return result
		if options[-1].is_empty() or route_edges.size() >= maximum:
			visited.erase(route.pop_back())
			options.pop_back()
			if not route_edges.is_empty(): route_edges.pop_back()
			continue
		var edge_index: int = options[-1].pop_back()
		var candidate: Dictionary = edges[edge_index]
		var next: String = candidate["b"] if current == candidate["a"] else candidate["a"]
		if visited.has(next): continue
		visited[next] = true
		route.append(next)
		route_edges.append(edge_index)
		options.append(_river_options(next, vertices, edges, used, visited, route_edges.size() >= minimum - 1))
	return []

static func _river_options(current: String, vertices: Dictionary, edges: Array[Dictionary], used: Dictionary, visited: Dictionary, prefer_boundary: bool) -> Array:
	var result: Array[int] = []
	for index: int in vertices[current]["edges"]:
		if used.has(index): continue
		var edge: Dictionary = edges[index]
		var next: String = edge["b"] if current == edge["a"] else edge["a"]
		if not visited.has(next) and float(vertices[next]["height"]) <= float(vertices[current]["height"]): result.append(index)
	result.sort_custom(func(a: int, b: int) -> bool:
		var a_next: String = edges[a]["b"] if current == edges[a]["a"] else edges[a]["a"]
		var b_next: String = edges[b]["b"] if current == edges[b]["a"] else edges[b]["a"]
		var a_score: float = float(edges[a]["noise"]) + float(vertices[a_next]["height"]) + (10.0 if prefer_boundary and vertices[a_next]["boundary"] else 0.0)
		var b_score: float = float(edges[b]["noise"]) + float(vertices[b_next]["height"]) + (10.0 if prefer_boundary and vertices[b_next]["boundary"] else 0.0)
		return a_score < b_score)
	return result

static func _matches(tile: HexTile, preference: Dictionary) -> bool:
	if preference.has("baseTerrains") and not preference["baseTerrains"].has(tile.baseTerrain): return false
	if preference.has("reliefs") and not preference["reliefs"].has(tile.relief): return false
	if preference.has("danger") and bool(preference["danger"]) != tile.danger: return false
	if bool(preference.get("riverRequired", false)) and tile.riverEdges.is_empty(): return false
	return true

static func _generate_nodes(state: GameState, rng: RngService, config: Dictionary) -> void:
	for tile: HexTile in state.tiles.values():
		for index: int in range(Enums.NodeType.SPAWN.size()):
			var type: String = Enums.NodeType.SPAWN[index]
			if _matches(tile, config["map"]["nodeSpawnByTerrain"][type]) and rng.chance(float(config["map"]["nodeSpawnChance"][Enums.NodeType.CHANCE_KEYS[index]])):
				_add_node(state, tile, type, config)
				break

static func _add_node(state: GameState, tile: HexTile, type: String, config: Dictionary) -> void:
	var node: GameNode = GameNode.new()
	node.id = "node_" + tile.id
	node.tileId = tile.id
	node.type = type
	# R6：显示名 = 类型名 + 全图序号（1.0 `GameEngine` `setName(type.getDisplayName() + idCounter)` 同义）。
	# 序号取「已有节点数 + 1」，生成顺序确定 → 同种子逐字一致。
	node.name = "%s%d" % [str(Enums.NodeType.NAMES.get(type, type)), state.nodes.size() + 1]
	node.level = int(config["map"]["setup"]["nodeLevel"])
	match type:
		Enums.NodeType.LING_TIAN: node.output = float(config["economy"]["lingTianBaseOutput"])
		Enums.NodeType.LING_MAI:
			node.output = float(config["economy"]["lingMaiBaseOutput"])
			node.reserve = float(config["economy"]["lingMaiTotalReserveBase"])
		Enums.NodeType.LING_QUAN: node.output = float(config["economy"]["lingQuanBaseOutput"])
	state.nodes[node.id] = node
	tile.nodeId = node.id

static func _secure_resources(state: GameState, config: Dictionary) -> void:
	for spawn: String in state.spawnTiles:
		var found: bool = false
		var nearest_flat: HexTile = null
		for tile: HexTile in state.tiles.values():
			if Hex.distance(Hex.coords(spawn), Vector2i(tile.q, tile.r)) > int(config["map"]["setup"]["safeRadius"]): continue
			if not tile.riverEdges.is_empty() or (not tile.nodeId.is_empty() and state.nodes[tile.nodeId].type == Enums.NodeType.LING_TIAN): found = true
			if tile.relief == Enums.Relief.FLAT and tile.nodeId.is_empty(): nearest_flat = tile
		if not found and nearest_flat != null:
			nearest_flat.baseTerrain = Enums.BaseTerrain.LING_FIELDS
			_add_node(state, nearest_flat, Enums.NodeType.LING_TIAN, config)

static func _generate_luxuries(state: GameState, rng: RngService, config: Dictionary) -> void:
	for tile: HexTile in state.tiles.values():
		if not rng.chance(float(config["resources"]["luxurySpawnChance"])): continue
		var options: Array[String] = []
		for luxury: String in Enums.ResourceKind.LUXURIES:
			var preference: Dictionary = config["map"]["luxuryByTerrain"][luxury]
			var matches: bool = preference.get("baseTerrains", []).has(tile.baseTerrain) or preference.get("reliefs", []).has(tile.relief)
			for feature: String in tile.features: matches = matches or preference.get("features", []).has(feature)
			if not tile.nodeId.is_empty(): matches = matches or preference.get("nodeTypes", []).has(state.nodes[tile.nodeId].type)
			if matches: options.append(luxury)
		if not options.is_empty(): tile.luxuryType = options[rng.next_int(0, options.size() - 1)]
