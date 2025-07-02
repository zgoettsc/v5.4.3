import Foundation
import ActivityKit

struct TreatmentTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let endTime: Date
        let isActive: Bool
        let totalDuration: TimeInterval // Add this line
    }
    
    let roomName: String
    let roomId: String
}
