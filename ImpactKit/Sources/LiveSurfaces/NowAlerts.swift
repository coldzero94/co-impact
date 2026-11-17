import Foundation
import os
import UserNotifications

/// The fallback Now alert (PRODUCT.md → Interruptions): a local notification at the start of a card's Now phase,
/// only when its Live Activity could not be scheduled (Live Activities off, or a request refused). Tapping it runs
/// the card's primary action through Impact, as the Live Activity's button does (owner, 2026-11-17).
@MainActor
public enum NowAlerts {
    /// A pending fallback alert's identifier: this prefix and the card ID.
    nonisolated static let prefix = "now."

    /// Asks for notification permission if it was never asked (PRODUCT.md → Permissions: the first time a card
    /// reaches its Now phase while Impact is open, or from the first card's detail); otherwise does nothing.
    public static func askOnce() async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            liveAlertsLog.error("Notification permission request failed: \((error as NSError).code, privacy: .public)")
        }
    }

    /// Makes the pending fallback alerts exactly `cards`' (their Live Activities could not be scheduled): adds or
    /// updates theirs and removes the rest, so a card done, dismissed, changed, or scheduled after all keeps none.
    static func set(_ cards: [LiveCard]) async {
        let center = UNUserNotificationCenter.current()
        await remove(except: Set(cards.map(\.cardID)))
        for card in cards {
            do {
                try await center.add(request(for: card, now: .now))
            } catch {
                liveAlertsLog.fault("Could not schedule the fallback alert for \(card.cardID, privacy: .private): \((error as NSError).code, privacy: .public)")
            }
        }
    }

    /// Removes the pending fallback alerts of cards not in `cardIDs`. From the background, where Impact cannot
    /// request Live Activities, this is all it does: the alerts of cards still wanted stay.
    static func remove(except cardIDs: Set<String>) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests().map(\.identifier)
            .filter { $0.hasPrefix(prefix) && !cardIDs.contains(String($0.dropFirst(prefix.count))) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }

    /// The alert for `card`: its title and answer, as the Live Activity's start alert shows them, Time Sensitive
    /// (meeting start or leave-by, PRODUCT.md → Interruptions), at the start of its Now phase.
    nonisolated static func request(for card: LiveCard, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = card.title
        content.body = card.answer
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["card": card.cardID]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, card.nowPhase.lowerBound.timeIntervalSince(now)),
                                                        repeats: false)
        return UNNotificationRequest(identifier: prefix + card.cardID, content: content, trigger: trigger)
    }

    /// Lets a tap on a fallback alert run its card's primary action (`RunRequests`, as a run link does), and shows
    /// the alert while Impact is in front. Call once at launch, before a tap can arrive.
    public static func handleTaps() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    private static let delegate = Delegate()

    /// On the main actor: UIKit asserts that a response's completion runs on the main thread, and a nonisolated
    /// async handler completes elsewhere (Impact crashed on a tap in the simulator).
    @MainActor private final class Delegate: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    didReceive response: UNNotificationResponse) async {
            let request = response.notification.request
            guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
                  request.identifier.hasPrefix(NowAlerts.prefix),
                  let cardID = request.content.userInfo["card"] as? String else { return }
            RunRequests.shared.pending = RunRequest(cardID: cardID)
        }

        func userNotificationCenter(_ center: UNUserNotificationCenter,
                                    willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
            [.banner, .list, .sound]
        }
    }
}

let liveAlertsLog = Logger(subsystem: "io.github.coldzero94.impact", category: "alerts")
