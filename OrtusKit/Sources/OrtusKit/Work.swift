// What waits for the person: approval routes at their turn, and tasks.
import Foundation

public struct ReviewStep: Decodable, Equatable {
    public let n: Int
    public let title: String?
    public let kind: String?
    public let state: String
    public let name: String?
}

public struct Review: Decodable, Equatable, Identifiable {
    public let id: String
    public let doc: String
    public let name: String?
    public let state: String
    public let note: String?
    public let steps: [ReviewStep]

    /// The step that is the person's (the current one).
    public var current: ReviewStep? { steps.first { $0.state == "current" } }
    public var signs: Bool { current?.kind == "sign" }
}

public struct WorkTask: Decodable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let state: String?
    public let dueAt: Int64?
    public let projectName: String?
    public var done: Bool { state == "done" }
}

extension Client {
    public func waitingReviews() async throws -> [Review] {
        struct Answer: Decodable { let waiting: [Review] }
        let a: Answer = try await call("GET", "/docs/reviews/mine")
        return a.waiting
    }

    /// Approves or signs (approve: true) or sends back with a comment.
    public func decide(_ review: Review, approve: Bool, comment: String = "") async throws {
        struct Ignored: Decodable {}
        let _: Ignored = try await call("POST", "/docs/reviews/\(review.id)/decide", json: ["approve": approve, "comment": comment])
    }

    public func myTasks() async throws -> [WorkTask] {
        struct Answer: Decodable { let tasks: [WorkTask] }
        let a: Answer = try await call("GET", "/tasks/mine")
        return a.tasks
    }

    public func setDone(_ task: WorkTask, _ done: Bool) async throws {
        struct Ignored: Decodable {}
        let _: Ignored = try await call("PATCH", "/tasks/tasks/\(task.id)", json: ["state": done ? "done" : "todo"])
    }
}
