import Flutter
import DeviceCheck
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var remindersReady = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if response.notification.request.identifier.hasPrefix("ep-") {
      ReminderChannel.open(response)
      completionHandler()
    } else {
      super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if remindersReady { return }
    remindersReady = true
    ReminderChannel.register(messenger: engineBridge.applicationRegistrar.messenger())
    DeviceCheckChannel.register(messenger: engineBridge.applicationRegistrar.messenger())
    PermissionSettingsChannel.register(messenger: engineBridge.applicationRegistrar.messenger())
  }
}

/// Schedules local reminders without replacing the notification delegate,
/// so OneSignal keeps remote delivery.
enum ReminderChannel {
  private static var channel: FlutterMethodChannel?
  private static var pending: [String: Any]?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "evenplate/reminders", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      if call.method == "pending" {
        result(pending)
        pending = nil
      } else if call.method == "acknowledge" {
        pending = nil
        result(nil)
      } else if call.method == "replace" {
        replace(call.arguments, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func open(_ response: UNNotificationResponse) {
    let data: [String: Any] = ["payload": response.notification.request.content.userInfo["payload"] ?? "{}", "action": response.actionIdentifier]
    pending = data
    channel?.invokeMethod("notification", arguments: data)
  }

  private static func replace(_ args: Any?, result: @escaping FlutterResult) {
    guard let rows = args as? [[String: Any]] else {
      result(FlutterError(code: "bad_args", message: "Expected a list of reminders", details: nil))
      return
    }
    let center = UNUserNotificationCenter.current()
    center.getPendingNotificationRequests { requests in
      let stale = requests.map(\.identifier).filter { $0.hasPrefix("ep-") }
      center.removePendingNotificationRequests(withIdentifiers: stale)
      let group = DispatchGroup()
      var scheduleError: Error?
      let lock = NSLock()
      let category = UNNotificationCategory(identifier: "ep-checkin", actions: [
        UNNotificationAction(identifier: "action_steady", title: "Feeling steady", options: [.foreground]),
        UNNotificationAction(identifier: "action_dip", title: "Low energy", options: [.foreground])
      ], intentIdentifiers: [])
      center.getNotificationCategories { existing in center.setNotificationCategories(existing.union([category])) }
      for row in rows {
        guard
          let id = intValue(row["id"]),
          let title = row["title"] as? String,
          let body = row["body"] as? String,
          let when = intValue(row["when"])
        else { continue }
        let fire = Date(timeIntervalSince1970: Double(when) / 1000.0)
        let interval = fire.timeIntervalSinceNow
        if interval < 1 { continue }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let payload = row["payload"] as? String {
          content.userInfo = ["payload": payload]
        }
        if id >= 100000 { content.categoryIdentifier = "ep-checkin" }
        let trigger: UNNotificationTrigger
        if let repeatKind = row["repeat"] as? String {
          let fields: Set<Calendar.Component> = repeatKind == "weekly" ? [.weekday, .hour, .minute] : [.hour, .minute]
          let parts = Calendar.current.dateComponents(fields, from: fire)
          trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)
        } else {
          trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        }
        let request = UNNotificationRequest(
          identifier: "ep-\(id)",
          content: content,
          trigger: trigger
        )
        group.enter()
        center.add(request) { error in
          lock.lock(); if let error = error { scheduleError = error }; lock.unlock()
          group.leave()
        }
      }
      group.notify(queue: .main) {
        if let error = scheduleError { result(FlutterError(code: "schedule_failed", message: error.localizedDescription, details: nil)) } else { result(nil) }
      }
    }
  }

  private static func intValue(_ value: Any?) -> Int? {
    if let number = value as? Int { return number }
    if let number = value as? NSNumber { return number.intValue }
    return nil
  }
}

// DeviceCheck tokens are ephemeral and must only be sent to the authenticated backend.
enum DeviceCheckChannel {
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "evenplate/devicecheck", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "generateToken" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard DCDevice.current.isSupported else {
        result(FlutterError(code: "unsupported", message: "Device verification requires a supported iPhone.", details: nil))
        return
      }
      DCDevice.current.generateToken { token, error in
        DispatchQueue.main.async {
          if let token = token, error == nil {
            result(token.base64EncodedString())
          } else {
            result(FlutterError(code: "unavailable", message: "Device verification is temporarily unavailable.", details: nil))
          }
        }
      }
    }
  }
}


enum PermissionSettingsChannel {
  private static var channel: FlutterMethodChannel?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "evenplate/permissions", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { call, result in
      guard call.method == "openSettings" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let url = URL(string: UIApplication.openSettingsURLString) else {
        result(false)
        return
      }
      UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
    }
  }
}
