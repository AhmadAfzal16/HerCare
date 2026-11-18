import Flutter
import UIKit
import CoreLocation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var careLocation: CareLocationBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    careLocation?.dispose()
    careLocation = CareLocationBridge(
      messenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}

// Opt-in, one-shot approximate positioning for the public care directory.
// Coordinates remain in memory and are never logged, persisted or uploaded.
private final class CareLocationBridge: NSObject, CLLocationManagerDelegate {
  private let channel: FlutterMethodChannel
  private var manager: CLLocationManager?
  private var pending: FlutterResult?
  private var requestID: UUID?
  private var permissionTimeout: DispatchWorkItem?
  private var acquisitionTimeout: DispatchWorkItem?
  private var acquiring = false
  private var backgroundObserver: NSObjectProtocol?
  private var foregroundObserver: NSObjectProtocol?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "com.hercare/care_location", binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Approximate location is unavailable.", details: nil))
        return
      }
      switch call.method {
      case "getCurrentApproximatePosition":
        self.request(result)
      case "cancelCurrentApproximatePosition":
        self.finish(self.failure("cancelled", "Location request cancelled."))
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self = self else { return }
      self.finish(self.failure("cancelled", "Location request stopped in the background."))
    }
    // Permission prompts can temporarily make the app inactive. Do not cancel
    // them; only start acquisition once the foreground app becomes active.
    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      guard let self = self, let manager = self.manager else { return }
      self.authorizationChanged(manager)
    }
  }

  private func failure(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }

  private func authorization(_ manager: CLLocationManager) -> CLAuthorizationStatus {
    if #available(iOS 14.0, *) { return manager.authorizationStatus }
    return CLLocationManager.authorizationStatus()
  }

  private func request(_ result: @escaping FlutterResult) {
    guard UIApplication.shared.applicationState == .active else {
      result(failure("unavailable", "Open the care directory before using approximate location."))
      return
    }
    guard pending == nil else {
      result(failure("request_in_progress", "A location request is already in progress."))
      return
    }
    let manager = CLLocationManager()
    if #available(iOS 14.0, *) {
      manager.desiredAccuracy = kCLLocationAccuracyReduced
    } else {
      manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }
    manager.allowsBackgroundLocationUpdates = false
    manager.pausesLocationUpdatesAutomatically = true
    pending = result
    requestID = UUID()
    self.manager = manager
    manager.delegate = self
    switch authorization(manager) {
    case .notDetermined:
      let id = requestID
      let timeout = DispatchWorkItem { [weak self] in
        guard let self = self, self.requestID == id else { return }
        self.finish(self.failure("timeout", "Location permission was not completed. You can select a city instead."))
      }
      permissionTimeout = timeout
      DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
      manager.requestWhenInUseAuthorization()
    case .authorizedWhenInUse, .authorizedAlways:
      startAcquisition(manager)
    case .denied, .restricted:
      finish(failure("permission_denied", "Location access is unavailable. You can select a city instead."))
    @unknown default:
      finish(failure("unavailable", "Approximate location is unavailable."))
    }
  }

  private func authorizationChanged(_ manager: CLLocationManager) {
    guard self.manager === manager, pending != nil else { return }
    switch authorization(manager) {
    case .authorizedWhenInUse, .authorizedAlways:
      startAcquisition(manager)
    case .denied, .restricted:
      finish(failure("permission_denied", "Location access is unavailable. You can select a city instead."))
    case .notDetermined:
      break
    @unknown default:
      finish(failure("unavailable", "Approximate location is unavailable."))
    }
  }

  private func startAcquisition(_ manager: CLLocationManager) {
    guard self.manager === manager, pending != nil, !acquiring,
      UIApplication.shared.applicationState == .active else { return }
    acquiring = true
    permissionTimeout?.cancel()
    permissionTimeout = nil
    let id = requestID
    let timeout = DispatchWorkItem { [weak self] in
      guard let self = self, self.requestID == id else { return }
      self.finish(self.failure("timeout", "No current approximate location was found. You can select a city instead."))
    }
    acquisitionTimeout = timeout
    DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: timeout)
    manager.requestLocation()
  }

  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    authorizationChanged(manager)
  }

  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
    if #available(iOS 14.0, *) { return }
    authorizationChanged(manager)
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard self.manager === manager, pending != nil, acquiring else { return }
    guard UIApplication.shared.applicationState != .background else {
      finish(failure("cancelled", "Location request stopped in the background."))
      return
    }
    let now = Date()
    guard let fix = locations.reversed().first(where: { location in
      let age = now.timeIntervalSince(location.timestamp)
      return location.coordinate.latitude.isFinite && location.coordinate.longitude.isFinite &&
        (-90.0...90.0).contains(location.coordinate.latitude) && (-180.0...180.0).contains(location.coordinate.longitude) &&
        location.horizontalAccuracy.isFinite && location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 10000 &&
        age.isFinite && age >= -30 && age <= 120
    }) else {
      finish(failure("unavailable", "The location fix was too old or imprecise. You can select a city instead."))
      return
    }
    let recordedAt = fix.timestamp.timeIntervalSince1970 * 1000
    guard recordedAt.isFinite && recordedAt >= 0 && recordedAt <= 8640000000000000 else {
      finish(failure("unavailable", "A current approximate location was not found."))
      return
    }
    finish([
      "latitude": (fix.coordinate.latitude * 100).rounded() / 100,
      "longitude": (fix.coordinate.longitude * 100).rounded() / 100,
      "accuracy": max(1500, fix.horizontalAccuracy),
      "recorded_at": Int64(recordedAt.rounded(.towardZero))
    ])
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    guard self.manager === manager, pending != nil else { return }
    let denied = (error as? CLError)?.code == .denied
    finish(failure(denied ? "permission_denied" : "unavailable", "A current approximate location was not found. You can select a city instead."))
  }

  private func finish(_ value: Any?) {
    let reply = pending
    pending = nil
    requestID = nil
    acquiring = false
    permissionTimeout?.cancel()
    acquisitionTimeout?.cancel()
    permissionTimeout = nil
    acquisitionTimeout = nil
    manager?.delegate = nil
    manager?.stopUpdatingLocation()
    manager = nil
    reply?(value)
  }

  func dispose() {
    finish(failure("cancelled", "Location request cancelled."))
    channel.setMethodCallHandler(nil)
    if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) }
    if let observer = foregroundObserver { NotificationCenter.default.removeObserver(observer) }
    backgroundObserver = nil
    foregroundObserver = nil
  }

  deinit {
    permissionTimeout?.cancel()
    acquisitionTimeout?.cancel()
    manager?.delegate = nil
    manager?.stopUpdatingLocation()
    if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) }
    if let observer = foregroundObserver { NotificationCenter.default.removeObserver(observer) }
  }
}
