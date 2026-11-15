#if os(iOS)
import ActivityKit
import Foundation
import os

extension LiveCard: ActivityAttributes {
    /// Empty: the activity shows only what it was scheduled with, and timer text moves on its own.
    public struct ContentState: Codable, Hashable, Sendable {}
}

/// Keeps Impact's Live Activities equal to the cards that should have one (`ImpactEngine.liveActivityCards`).
@MainActor
public enum LiveActivities {
    /// Ends activities no longer wanted (done, dismissed, changed, or past), and schedules the missing ones to
    /// start with their Now phase, which alerts once (PRODUCT.md → Interruptions); one already in its Now phase
    /// starts at once, without an alert, since Impact is open.
    /// shortcut: when scheduling fails, nothing else alerts yet; the fallback notification (PRODUCT.md →
    /// Interruptions) comes with notification permission.
    /// shortcut: an activity the user swiped away is scheduled again once the system forgets it.
    public static func sync(_ cards: [LiveCard], now: Date) async {
        var kept: Set<LiveCard> = []
        for activity in Activity<LiveCard>.activities where activity.activityState != .ended {
            if cards.contains(activity.attributes) {
                kept.insert(activity.attributes)
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveLog.info("Live Activities are off for Impact; none scheduled")
            return
        }
        for card in cards where !kept.contains(card) {
            let content = ActivityContent(state: LiveCard.ContentState(), staleDate: card.nowPhase.upperBound)
            do {
                if now >= card.nowPhase.lowerBound {
                    _ = try Activity.request(attributes: card, content: content, pushType: nil)
                } else {
                    _ = try Activity.request(
                        attributes: card, content: content, pushType: nil, style: .standard,
                        alertConfiguration: AlertConfiguration(title: "\(card.title)", body: "\(card.answer)", sound: .default),
                        start: card.nowPhase.lowerBound)
                }
            } catch {
                liveLog.fault("Could not schedule a Live Activity: \(String(describing: type(of: error)), privacy: .public) \((error as NSError).code, privacy: .public)")
            }
        }
    }
}

let liveLog = Logger(subsystem: "io.github.coldzero94.impact", category: "live")
#endif
