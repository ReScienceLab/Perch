import Foundation

struct Session: Codable {
    let id: String
    let agent: String
    let sessionId: String
    let workingDir: String
    let title: String
    let note: String
    let priority: String
    let status: String
    let createdAt: String
    let resumeCmd: String

    enum CodingKeys: String, CodingKey {
        case id
        case agent
        case sessionId = "session_id"
        case workingDir = "working_dir"
        case title
        case note
        case priority
        case status
        case createdAt = "created_at"
        case resumeCmd = "resume_cmd"
    }
}
