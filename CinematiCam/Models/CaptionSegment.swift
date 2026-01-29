import Foundation

struct CaptionSegment: Identifiable {
    let id = UUID()
    var startTime: TimeInterval
    var endTime: TimeInterval
    var text: String
}
