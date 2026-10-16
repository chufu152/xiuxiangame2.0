class_name GameState
extends RefCounted

var width: int = 0
var height: int = 0
var seed: int = 0
var difficulty: String = ""
var turn: int = 1
var phase: String = Enums.TurnPhase.PLAYER_ACTION
var playerSectId: String = ""
var tiles: Dictionary = {}
var nodes: Dictionary = {}
var spawnTiles: Array[String] = []
var sects: Array[Sect] = []
var rng: RngService = null
# 河流有向边路径仅供权威规则与验收使用，不进入玩家视图。
var riverPaths: Array[Array] = []
var gameOver: bool = false
var eventLog: Array[String] = []
