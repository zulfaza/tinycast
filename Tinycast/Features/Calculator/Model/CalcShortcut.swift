import Foundation

/// Calculator-only chords, kept separate from row actions owned by other palette screens.
enum CalcShortcut: Equatable, Sendable {
    case pasteAnswer
    case copyUnformattedAnswer
    case copyQuestionAndAnswer

    static func resolve(
        isReturn: Bool, isC: Bool, command: Bool, shift: Bool, option: Bool, control: Bool
    ) -> Self? {
        if isReturn {
            guard !shift, !option, command || control else { return nil }
            return .pasteAnswer
        }
        guard isC, option, command || control else { return nil }
        return shift ? .copyQuestionAndAnswer : .copyUnformattedAnswer
    }
}
