import CoreLocation
import OSLog
import UIKit
import UserNotifications

@MainActor
final class PushRegistrationCoordinator {
    static let shared = PushRegistrationCoordinator()

    private let tokenKey = "app.apnsDeviceToken"
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KeApp",
        category: "PushRegistration"
    )

    private init() {}

    /// APNs 建议每次启动都重新注册；这个调用本身不会弹通知权限框。
    func prepareAtLaunch() {
#if targetEnvironment(simulator)
        return
#else
        UIApplication.shared.registerForRemoteNotifications()
        Task { await uploadStoredTokenIfPossible() }
#endif
    }

    /// 返回值表示这一次是否弹过通知权限，供权限编排避免紧接着再弹定位。
    func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        var prompted = false

        if settings.authorizationStatus == .notDetermined {
            prompted = true
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                logger.error("通知权限请求失败：\(error.localizedDescription, privacy: .public)")
            }
        }

#if !targetEnvironment(simulator)
        UIApplication.shared.registerForRemoteNotifications()
#endif
        await uploadStoredTokenIfPossible()
        return prompted
    }

    func receivedDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(token, forKey: tokenKey)
        Task { await uploadStoredTokenIfPossible() }
    }

    func retryStoredToken() {
        Task { await uploadStoredTokenIfPossible() }
    }

    private func uploadStoredTokenIfPossible() async {
        guard let token = UserDefaults.standard.string(forKey: tokenKey),
              !token.isEmpty else { return }
        do {
            _ = try await APIClient.shared.registerAPNsToken(
                token,
                deviceName: UIDevice.current.name
            )
        } catch APIError.unauthorized {
            // 登录成功后 ChatViewModel 会再试；token 留在本机，不丢。
        } catch {
            logger.error("APNs token 上报失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}

@MainActor
final class CompanionPermissionCoordinator {
    static let shared = CompanionPermissionCoordinator()

    private init() {}

    func sessionDidBecomeReady() {
        PushRegistrationCoordinator.shared.retryStoredToken()
        LocationContextReporter.shared.refreshIfAuthorized()
    }

    /// 第一次完成对话优先解释通知；下一次再请求定位，避免系统权限框连着砸下来。
    func conversationDidComplete() {
        Task {
            let showedPushPrompt = await PushRegistrationCoordinator.shared
                .requestAuthorizationIfNeeded()
            if !showedPushPrompt {
                LocationContextReporter.shared.requestAuthorizationIfNeeded()
            }
        }
    }
}

@MainActor
final class LocationContextReporter: NSObject, CLLocationManagerDelegate {
    static let shared = LocationContextReporter()

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "KeApp",
        category: "LocationContext"
    )
    private let lastLatitudeKey = "app.location.lastLatitude"
    private let lastLongitudeKey = "app.location.lastLongitude"
    private let lastDateKey = "app.location.lastReportDate"
    private var isReporting = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 200
        manager.pausesLocationUpdatesAutomatically = true
    }

    func prepareAtLaunch() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startSignificantChanges()
        case .notDetermined, .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    func refreshIfAuthorized() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startSignificantChanges(requestCurrentLocation: true)
        case .notDetermined, .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    func requestAuthorizationIfNeeded() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        switch manager.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            startSignificantChanges(requestCurrentLocation: true)
        case .restricted, .denied:
            break
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            startSignificantChanges(requestCurrentLocation: true)
        case .restricted, .denied:
            manager.stopMonitoringSignificantLocationChanges()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last(where: { location in
            location.horizontalAccuracy >= 0
                && abs(location.timestamp.timeIntervalSinceNow) < 600
        }) else { return }
        reportIfNeeded(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard (error as? CLError)?.code != .locationUnknown else { return }
        logger.error("定位更新失败：\(error.localizedDescription, privacy: .public)")
    }

    private func startSignificantChanges(requestCurrentLocation: Bool = false) {
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else { return }
        manager.startMonitoringSignificantLocationChanges()
        if requestCurrentLocation, UIApplication.shared.applicationState == .active {
            manager.requestLocation()
        }
    }

    private func reportIfNeeded(_ location: CLLocation) {
        guard !isReporting, shouldReport(location) else { return }
        isReporting = true

        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "location-context")
        Task {
            defer {
                isReporting = false
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
            }

            let place = await readablePlace(for: location)
            do {
                _ = try await APIClient.shared.reportLocation(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    accuracy: location.horizontalAccuracy,
                    place: place
                )
                remember(location)
            } catch APIError.unauthorized {
                // 未登录或 cookie 失效时不记成功，下次位置事件仍会重试。
            } catch {
                logger.error("位置上报失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func shouldReport(_ location: CLLocation) -> Bool {
        let defaults = UserDefaults.standard
        guard let lastDate = defaults.object(forKey: lastDateKey) as? Date else { return true }
        let last = CLLocation(
            latitude: defaults.double(forKey: lastLatitudeKey),
            longitude: defaults.double(forKey: lastLongitudeKey)
        )
        return location.distance(from: last) >= 200
            || Date.now.timeIntervalSince(lastDate) >= 6 * 60 * 60
    }

    private func remember(_ location: CLLocation) {
        let defaults = UserDefaults.standard
        defaults.set(location.coordinate.latitude, forKey: lastLatitudeKey)
        defaults.set(location.coordinate.longitude, forKey: lastLongitudeKey)
        defaults.set(Date.now, forKey: lastDateKey)
    }

    private func readablePlace(for location: CLLocation) async -> String? {
        do {
            guard let placemark = try await geocoder.reverseGeocodeLocation(location).first else {
                return nil
            }
            let candidates = [
                placemark.areasOfInterest?.first,
                placemark.name,
                placemark.subLocality,
                placemark.locality,
                placemark.administrativeArea,
            ]
            var values: [String] = []
            for candidate in candidates {
                guard let candidate else { continue }
                let value = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, !values.contains(value) else { continue }
                values.append(value)
                if values.count == 2 { break }
            }
            let place = values.joined(separator: " · ")
            return place.isEmpty ? nil : String(place.prefix(120))
        } catch {
            logger.error("反向地理编码失败：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
