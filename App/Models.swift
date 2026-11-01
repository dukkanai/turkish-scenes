import Foundation

struct Film: Codable {
    let id: String
    let title: String
    let youtubeID: String
    let version: Int
    let sourceSHA256: String
    let segments: [Segment]
}
struct Segment: Codable, Identifiable {
    let id: String
    let number: Int
    let startMS: Int
    let endMS: Int
    let turkish: String
    let arabic: String
    let words: [WordOccurrence]
    let expressions: [String]
    let editorialStatus: String
    let appendix: [String]
}
struct WordOccurrence: Codable, Identifiable {
    let id: String
    let text: String
    let explanation: String
}
