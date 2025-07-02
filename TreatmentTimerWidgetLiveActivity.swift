//
//  TreatmentTimerWidgetLiveActivity.swift
//  TreatmentTimerWidget
//
//  Created by Zack Goettsche on 6/3/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct TreatmentTimerWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct TreatmentTimerWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TreatmentTimerWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension TreatmentTimerWidgetAttributes {
    fileprivate static var preview: TreatmentTimerWidgetAttributes {
        TreatmentTimerWidgetAttributes(name: "World")
    }
}

extension TreatmentTimerWidgetAttributes.ContentState {
    fileprivate static var smiley: TreatmentTimerWidgetAttributes.ContentState {
        TreatmentTimerWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: TreatmentTimerWidgetAttributes.ContentState {
         TreatmentTimerWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: TreatmentTimerWidgetAttributes.preview) {
   TreatmentTimerWidgetLiveActivity()
} contentStates: {
    TreatmentTimerWidgetAttributes.ContentState.smiley
    TreatmentTimerWidgetAttributes.ContentState.starEyes
}
