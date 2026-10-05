//
//  GameSessionStore.swift
//  daves-tiles
//

import Foundation

struct SavedGameSession: Codable {

    static let currentVersion = 1

    let version: Int
    let puzzleImageID: String
    let mode: Game.Mode
    let randomJumps: Bool
    let selectedDifficulty: GameDifficulty
    let showsTileNumbers: Bool
    let presentsGame: Bool
    let selections: [SavedGameSelection]

    init(
        puzzleImageID: String,
        gameType: GameType,
        selectedDifficulty: GameDifficulty,
        showsTileNumbers: Bool,
        presentsGame: Bool,
        gameSelections: [GameSelection]
    ) {
        self.version = Self.currentVersion
        self.puzzleImageID = puzzleImageID
        self.mode = gameType.mode
        self.randomJumps = gameType.randomJumps
        self.selectedDifficulty = selectedDifficulty
        self.showsTileNumbers = showsTileNumbers
        self.presentsGame = presentsGame
        self.selections = gameSelections.map(SavedGameSelection.init)
    }
}

struct SavedGameSelection: Codable {

    let difficulty: GameDifficulty
    let game: SavedGame

    init(_ selection: GameSelection) {
        self.difficulty = selection.difficulty
        self.game = SavedGame(selection.game)
    }

    @MainActor func restoredSelection() -> GameSelection? {
        guard game.tileIdentifiers.count == game.rows * game.columns,
              Set(game.tileIdentifiers) == Set(1...game.tileIdentifiers.count) else {
            return nil
        }
        return GameSelection(
            game: Game(
                id: game.id,
                rows: game.rows,
                columns: game.columns,
                mode: game.mode,
                openTileId: game.openTileID,
                moves: game.moves,
                accumulatedTime: game.accumulatedTime,
                tileIdentifiers: game.tileIdentifiers,
                state: game.state
            ),
            difficulty: difficulty
        )
    }
}

struct SavedGame: Codable {

    let id: UUID
    let rows: Int
    let columns: Int
    let mode: Game.Mode
    let openTileID: Int?
    let moves: Int
    let accumulatedTime: Double
    let tileIdentifiers: [Int]
    let state: Game.State

    init(_ game: Game) {
        self.id = game.id
        self.rows = game.rows
        self.columns = game.columns
        self.mode = game.mode
        self.openTileID = game.openTileId
        self.moves = game.moves
        self.accumulatedTime = game.accumulatedTime
        self.tileIdentifiers = game.tiles.map(\.id)
        self.state = game.state
    }
}

@MainActor enum GameSessionStore {

    private static let defaultsKey = "SavedGameSession"

    static func load() -> SavedGameSession? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let session = try? JSONDecoder().decode(SavedGameSession.self, from: data),
              session.version == SavedGameSession.currentVersion else {
            return nil
        }
        return session
    }

    static func save(_ session: SavedGameSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
