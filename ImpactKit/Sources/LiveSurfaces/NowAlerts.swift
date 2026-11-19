import Foundation
import os
import UserNotifications

/// The fallback Now alert (PRODUCT.md → Interruptions): a local notification at the start of a card's Now phase,
/// only when its Live Activity could not be scheduled (Live Activities off, a request refused, or Impact in the
/// background, `LiveActivities.sync`). Tapping it runs the card's primary action through Impact, as the Live
/// Activity's button does (owner, 2026-11-17).
@MainActor
public enum NowAlerts {
    /// Every fallback alert's identifier starts with this.
    nonisolated static let prefix = "now."

    /// A fallback alert's identifier: the card ID and its Now phase's start, so a card moved to another time drops
    /// its old alert, as its changed Live Activity ends.
    nonisolated static func identifier(for card: LiveCard) -> String {
        prefix + card.cardID + "@" + String(Int(card.nowPhase.lowerBound.timeIntervalSince1970))
    }

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

    /// Makes the fallback alerts exactly `cards`' (their Live Activities could not be scheduled): adds or updates
    /// theirs and removes the rest, so a card done, dismissed, changed, or scheduled after all keeps none. The alerts
    /// of `inNow`, cards already in their Now phase without an activity, stay: one may be due this instant or shown.
    static func set(_ cards: [LiveCard], keeping inNow: [LiveCard]) async {
        let center = UNUserNotificationCenter.current()
        await remove(except: Set((cards + inNow).map(identifier)))
        // Without permission an add fails (seen in the simulator): wait for it instead of failing on every sync.
        let status = await center.notificationSettings().authorizationStatus
        guard status != .notDetermined, status != .denied else {
            if !cards.isEmpty {
                liveAlertsLog.notice("Notifications are not allowed: \(cards.count, privacy: .public) cards get no Now alert")
            }
            return
        }
        for card in cards {
            // A newer sync replaced this one while it waited: it takes over.
            guard !Task.isCancelled else { return }
            do {
                try await center.add(request(for: card, now: .now))
            } catch {
                liveAlertsLog.fault("Could not schedule the fallback alert for \(card.cardID, privacy: .private): \((error as NSError).code, privacy: .public)")
            }
        }
    }

    /// Removes the fallback alerts, pending or delivered, whose identifiers (`identifier(for:)`) are not in `kept`.
    private static func remove(except kept: Set<String>) async {
        let center = UNUserNotificationCenter.current()
        let isStale = { (id: String) in id.hasPrefix(prefix) && !kept.contains(id) }
        center.removePendingNotificationRequests(withIdentifiers: await center.pendingNotificationRequests()
            .map(\.identifier).filter(isStale))
        center.removeDeliveredNotifications(withIdentifiers: await center.deliveredNotifications()
            .map(\.request.identifier).filter(isStale))
    }

    /// The alert for `card`: its title and answer, as the Live Activity's start alert shows them, at the start of its
    /// Now phase; Time Sensitive for a meeting's start or leave-by, the default level for a focus block (PRODUCT.md →
    /// Interruptions).
    nonisolated static func request(for card: LiveCard, now: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = card.title
        content.body = card.answer
        content.sound = .default
        content.interruptionLevel = card.timeSensitive ? .timeSensitive : .active
        content.userInfo = ["card": card.cardID]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, card.nowPhase.lowerBound.timeIntervalSince(now)),
                                                        repeats: false)
        return UNNotificationRequest(identifier: identifier(for: card), content: content, trigger: trigger)
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
