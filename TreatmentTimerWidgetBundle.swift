import WidgetKit
import SwiftUI

@main
struct TreatmentTimerWidgetBundle: WidgetBundle {
    var body: some Widget {
        TreatmentTimerWidget()
        if #available(iOS 16.1, *) {
            TreatmentTimerLiveActivity()
        }
    }
}
