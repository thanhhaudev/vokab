import Foundation
import UserNotifications
import VokabKit

/// Posts capture-resolved notifications with View / Undo actions (SPEC §5, §6).
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private let categoryId = "vokab.capture"
    /// Duplicate captures: View only — no Undo, since the entry id is the user's
    /// pre-existing entry and deleting it would destroy original data.
    private let dupCategoryId = "vokab.capture.dup"
    private let quotaCategoryId = "vokab.quota"
    private let failedCategoryId = "vokab.capture.failed"
    private let undoActionId = "vokab.undo"
    private let viewActionId = "vokab.view"
    private let retryActionId = "vokab.retry"

    /// Maps notification identifier → entry id, for Undo.
    private var pendingUndo: [String: Int64] = [:]
    /// Maps notification identifier → entry id, for View (every resolved capture,
    /// including duplicates).
    private var pendingView: [String: Int64] = [:]
    /// Maps notification identifier → entry id, for Retry.
    private var pendingRetry: [String: Int64] = [:]
    weak var env: AppEnvironment?

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let undo = UNNotificationAction(identifier: undoActionId, title: "Undo", options: [.destructive])
        let view = UNNotificationAction(identifier: viewActionId, title: "View", options: [.foreground])
        let retry = UNNotificationAction(identifier: retryActionId, title: "Retry", options: [])
        let category = UNNotificationCategory(identifier: categoryId, actions: [view, undo],
                                              intentIdentifiers: [], options: [])
        let dupCategory = UNNotificationCategory(identifier: dupCategoryId, actions: [view],
                                                 intentIdentifiers: [], options: [])
        let quotaCategory = UNNotificationCategory(identifier: quotaCategoryId, actions: [view],
                                                   intentIdentifiers: [], options: [])
        let failedCategory = UNNotificationCategory(identifier: failedCategoryId, actions: [retry, view],
                                                    intentIdentifiers: [], options: [])
        center.setNotificationCategories([category, dupCategory, quotaCategory, failedCategory])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postResolved(summary: String, entryId: Int64?, wasDuplicate: Bool) {
        let content = UNMutableNotificationContent()
        content.title = wasDuplicate ? "Already in vokab" : "Added to vokab"
        content.body = summary
        content.categoryIdentifier = wasDuplicate ? dupCategoryId : categoryId
        let id = UUID().uuidString
        // Only a genuinely new capture can be undone (Undo deletes by id).
        if let entryId, !wasDuplicate { pendingUndo[id] = entryId }
        // View opens the entry's detail for any resolved capture (incl. duplicates).
        if let entryId { pendingView[id] = entryId }
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func postQuotaAlert(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = quotaCategoryId
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func postFailed(word: String, entryId: Int64) {
        let content = UNMutableNotificationContent()
        content.title = L.t("Analysis failed", "Phân tích thất bại")
        content.body = word.isEmpty ? L.t("Tap Retry to try again.", "Bấm Thử lại để chạy lại.")
                                    : L.t("\u{201C}\(word)\u{201D} failed. Tap Retry.", "\u{201C}\(word)\u{201D} lỗi. Bấm Thử lại.")
        content.categoryIdentifier = failedCategoryId
        let id = UUID().uuidString
        pendingRetry[id] = entryId
        pendingView[id] = entryId
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.identifier
        switch response.actionIdentifier {
        case undoActionId:
            if let entryId = pendingUndo[id] { try? env?.entries.delete(id: entryId) }
        case viewActionId:
            if let entryId = pendingView[id] { CaptureController.shared.openCaptureResult(entryId) }
            else { CaptureController.shared.openLibrary() }
        case retryActionId:
            if let entryId = pendingRetry[id] {
                try? env?.entries.markAnalyzingAgain(id: entryId)
                if let env { Task { await env.captureWorker.enqueueAnalysis(entryId: entryId) } }
            }
        default:
            break
        }
        pendingUndo[id] = nil
        pendingView[id] = nil
        pendingRetry[id] = nil
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
