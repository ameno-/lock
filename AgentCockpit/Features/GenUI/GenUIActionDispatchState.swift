import Foundation

enum GenUIActionDispatchStatus: Sendable, Equatable {
    case idle
    case sending
    case succeeded
    case failed
}

struct GenUIActionDispatchState: Sendable, Equatable {
    let status: GenUIActionDispatchStatus
    let message: String?
    let updatedAt: Date

    init(status: GenUIActionDispatchStatus, message: String? = nil, updatedAt: Date = .now) {
        self.status = status
        self.message = message
        self.updatedAt = updatedAt
    }
}
