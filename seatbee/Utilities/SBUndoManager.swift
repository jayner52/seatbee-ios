import Foundation

@Observable
final class SBUndoManager {
    private var undoStack: [SeatingPlan] = []
    private var redoStack: [SeatingPlan] = []
    private let maxLevels = 30

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func pushState(_ plan: SeatingPlan) {
        undoStack.append(plan)
        if undoStack.count > maxLevels {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    func undo(current: SeatingPlan) -> SeatingPlan? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return previous
    }

    func redo(current: SeatingPlan) -> SeatingPlan? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return next
    }

    func clear() {
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
