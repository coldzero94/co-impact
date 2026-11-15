#if os(iOS)
import ActivityKit
import Foundation
import os

extension LiveCard: ActivityAttributes {
    /// Empty: the activity shows only what it was requested with, and timer text moves on its own.
    public struct ContentState: Codable, Hashable, Sendable {}
}

/// Keeps Impact's Live Activities equal to the cards that should have one (`HomeSnapshot.liveActivityCards`).
@MainActor
public enum LiveActivities {
    /// Ends the activities no longer wanted (done, dismissed, changed, past, or pushed out by an earlier card),
    /// which works from the background too. With `request`, which needs Impact in front, also requests the missing
    /// ones (`LiveCard.toRequest`): scheduled ones start with their Now phase and alert then (PRODUCT.md →
    /// Interruptions; whether the alert shows under a Focus is unverified, ARCHITECTURE.md → To verify).
    /// shortcut: when a request fails, nothing else alerts yet; the fallback notification (PRODUCT.md →
    /// Interruptions) comes with notification permission.
    /// shortcut: an activity the user swiped away is requested again once the system forgets it.
    public static func sync(_ cards: [LiveCard], request: Bool) async {
        var existing: Set<LiveCard> = []
        for activity in Activity<LiveCard>.activities where activity.activityState != .ended {
            if cards.contains(activity.attributes) {
                existing.insert(activity.attributes)
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        // A newer sync replaced this one, or Impact left the front, while it waited: nothing below waits, so only
        // one sync requests, and only in front.
        guard request, !Task.isCancelled else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            liveLog.notice("Live Activities are off for Impact: \(cards.count, privacy: .public) cards get no Now alert")
            return
        }
        let (startNow, schedule) = LiveCard.toRequest(wanted: cards, existing: existing, now: .now)
        for card in startNow + schedule {
            let content = ActivityContent(state: LiveCard.ContentState(), staleDate: card.nowPhase.upperBound)
            let scheduled = schedule.contains(card)
            do {
                if scheduled {
                    _ = try Activity.request(
                        attributes: card, content: content, pushType: nil, style: .standard,
                        alertConfiguration: AlertConfiguration(title: "\(card.title)", body: "\(card.answer)", sound: .default),
                        start: card.nowPhase.lowerBound)
                } else {
                    _ = try Activity.request(attributes: card, content: content, pushType: nil)
                }
            } catch {
                liveLog.fault("Could not \(scheduled ? "schedule" : "start", privacy: .public) the Live Activity for \(card.cardID, privacy: .private): \(String(describing: type(of: error)), privacy: .public) \((error as NSError).code, privacy: .public)")
            }
        }
    }
}

let liveLog = Logger(subsystem: "io.github.coldzero94.impact", category: "live")
#endif
