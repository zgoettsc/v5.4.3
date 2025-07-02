import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.1, *)
struct TreatmentTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TreatmentTimerAttributes.self) { context in
            // Lock screen/banner UI
            LockScreenLiveActivityView(context: context)
                .widgetURL(URL(string: "widget-extension://\(context.attributes.roomId)"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: isTimerActive(context) ? "timer" : "bell.fill")
                            .foregroundColor(isTimerActive(context) ? .purple : .red)
                        Text(context.attributes.roomName)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if isTimerActive(context) {
                        // FIXED: Only show timer if we're sure it's active AND not expired
                        let remaining = max(0, context.state.endTime.timeIntervalSinceNow)
                        if remaining > 0 {
                            Text(context.state.endTime, style: .timer)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.purple)
                                .multilineTextAlignment(.trailing)
                        } else {
                            Text("EXPIRED")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                    } else {
                        Text("EXPIRED")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if isTimerActive(context) {
                        Text("Treatment Timer")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Timer Ended")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            } compactLeading: {
                Image(systemName: isTimerActive(context) ? "timer" : "bell.fill")
                    .foregroundColor(isTimerActive(context) ? .purple : .red)
            } compactTrailing: {
                if isTimerActive(context) {
                    // FIXED: Double-check remaining time even when isActive is true
                    let remaining = max(0, context.state.endTime.timeIntervalSinceNow)
                    if remaining > 0 {
                        Text(context.state.endTime, style: .timer)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.purple)
                            .frame(width: 40, alignment: .trailing)
                    } else {
                        Text("EXPIRED")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                            .frame(width: 40, alignment: .trailing)
                    }
                } else {
                    Text("EXPIRED")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                        .frame(width: 40, alignment: .trailing)
                }
            } minimal: {
                Image(systemName: isTimerActive(context) ? "timer" : "bell.fill")
                    .foregroundColor(isTimerActive(context) ? .purple : .red)
            }
            .widgetURL(URL(string: "widget-extension://\(context.attributes.roomId)"))
        }
    }
    
    // BULLETPROOF: Check both isActive AND current time, with safety margin
    private func isTimerActive(_ context: ActivityViewContext<TreatmentTimerAttributes>) -> Bool {
        let remaining = context.state.endTime.timeIntervalSinceNow
        return context.state.isActive && remaining > 0.5 // 0.5 second safety margin
    }
}

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<TreatmentTimerAttributes>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: isTimerActive() ? "timer" : "bell.fill")
                    .foregroundColor(isTimerActive() ? .purple : .red)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.roomName)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if isTimerActive() {
                        Text("Treatment Timer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Timer Ended")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    if isTimerActive() {
                        // FIXED: Additional check for remaining time
                        let remaining = max(0, context.state.endTime.timeIntervalSinceNow)
                        if remaining > 0 {
                            Text(context.state.endTime, style: .timer)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.purple)
                                .multilineTextAlignment(.trailing)
                            
                            Text("remaining")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("EXPIRED")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                            
                            Text("Time for next treatment")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    } else {
                        Text("EXPIRED")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.red)
                        
                        Text("Time for next treatment")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            
            ProgressView(value: progressValue())
                .progressViewStyle(LinearProgressViewStyle())
                .tint(isTimerActive() ? .purple : .red)
                .frame(height: 6)
        }
        .padding()
        .background(Color(.systemBackground))
        .activityBackgroundTint(Color.clear)
        .activitySystemActionForegroundColor(isTimerActive() ? .purple : .red)
    }
    
    // BULLETPROOF: Check both isActive AND current time, with safety margin
    private func isTimerActive() -> Bool {
        let remaining = context.state.endTime.timeIntervalSinceNow
        return context.state.isActive && remaining > 0.5 // 0.5 second safety margin
    }
    
    private func progressValue() -> Double {
        if !isTimerActive() {
            return 1.0 // Show completed when expired
        }
        
        let remaining = max(0, context.state.endTime.timeIntervalSinceNow)
        let total = context.state.totalDuration
        return max(0, min(1, (total - remaining) / total))
    }
}
