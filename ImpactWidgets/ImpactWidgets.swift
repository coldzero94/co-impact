import LiveSurfaces
import SwiftUI
import WidgetKit

/// The widget extension: only the entry point. Layouts live in ImpactKit's LiveSurfaces module.
@main
struct ImpactWidgets: WidgetBundle {
    var body: some Widget {
        LiveCardActivity()
    }
}
