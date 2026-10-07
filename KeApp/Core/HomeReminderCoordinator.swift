import SwiftUI
import CoreLocation
import CoreMotion
import UserNotifications

/// Local reminders are delivered only after a fresh location and motion check.
/// No advance calendar notification can bypass the home/driving gate.
@MainActor
final class HomeReminderCoordinator: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = HomeReminderCoordinator()
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "us.home-reminders.enabled"); configure() } }
    @Published private(set) var status = "先设置家的位置，再开启自动提醒"
    @Published private(set) var homeLabel = "家的位置未设置"
    @Published private(set) var endTimes: [String: Date]
    @Published private(set) var promises: [Promise]
    @Published private(set) var completed: Set<String>
    struct Promise: Identifiable, Codable { let id: UUID; var text: String; var done: Bool }
    private let defaults = UserDefaults.standard
    private let manager = CLLocationManager()
    private let motion = CMMotionActivityManager()
    private var home: CLLocationCoordinate2D?
    private var location: CLLocation?
    private var safeMotionAt: Date?
    private var motionRevision = 0
    private var timer: Timer?
    private var settingHome = false
    private var inFlight = Set<String>()
    private var overrides = Set(UserDefaults.standard.stringArray(forKey: "us.shift-end-overrides") ?? [])
    private var delivered: Set<String>
    private var dinnerAt: Date?
    private let radius: CLLocationDistance = 150

    override private init() {
        enabled = UserDefaults.standard.bool(forKey: "us.home-reminders.enabled")
        let data = UserDefaults.standard.data(forKey: "us.shift-end-times")
        endTimes = data.flatMap { try? JSONDecoder().decode([String: Date].self, from: $0) } ?? [:]
        promises = UserDefaults.standard.data(forKey: "us.promises").flatMap { try? JSONDecoder().decode([Promise].self, from: $0) } ?? []
        completed = Set(UserDefaults.standard.stringArray(forKey: "us.medicine-completed") ?? [])
        delivered = Set(UserDefaults.standard.stringArray(forKey: "us.medicine-delivered") ?? [])
        dinnerAt = UserDefaults.standard.object(forKey: "us.dinner-at") as? Date
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        if defaults.object(forKey: "us.home.latitude") != nil {
            home = CLLocationCoordinate2D(latitude: defaults.double(forKey: "us.home.latitude"), longitude: defaults.double(forKey: "us.home.longitude"))
            homeLabel = "已设置家的位置"
        }
        configure()
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    func endTime(on date: Date) -> Date? { endTimes[Self.dayKey(date)] }
    func setEndTime(_ time: Date, on date: Date, override: Bool = true) {
        let key = Self.dayKey(date)
        if !override && overrides.contains(key) { return }
        if override { overrides.insert(key); defaults.set(Array(overrides), forKey: "us.shift-end-overrides") }
        endTimes[Self.dayKey(date)] = time
        defaults.set(try? JSONEncoder().encode(endTimes), forKey: "us.shift-end-times")
        refresh()
    }
    func clearEndTime(on date: Date) {
        defaults.removeObject(forKey: "us.shift-plan.override." + Self.dayKey(date))
        overrides.remove(Self.dayKey(date))
        defaults.set(Array(overrides), forKey: "us.shift-end-overrides")
        endTimes.removeValue(forKey: Self.dayKey(date))
        defaults.set(try? JSONEncoder().encode(endTimes), forKey: "us.shift-end-times")
    }
    func setHomeHere() {
        settingHome = true
        manager.requestAlwaysAuthorization()
        manager.requestLocation()
        status = "正在读取当前位置；请只在家里设置"
    }
    func dinnerFinished() {
        dinnerAt = .now
        defaults.set(dinnerAt, forKey: "us.dinner-at")
        refresh()
    }
    func addPromise(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        promises.append(Promise(id: UUID(), text: text, done: false)); savePromises()
    }
    func togglePromise(_ id: UUID) {
        guard let i = promises.firstIndex(where: { $0.id == id }) else { return }
        promises[i].done.toggle(); savePromises()
    }
    private func savePromises() { defaults.set(try? JSONEncoder().encode(promises), forKey: "us.promises") }
    func isCompleted(_ kind: String) -> Bool { completed.contains(Self.dayKey(.now) + ":" + kind) }
    func markCompleted(_ kind: String) {
        completed.insert(Self.dayKey(.now) + ":" + kind)
        defaults.set(Array(completed), forKey: "us.medicine-completed")
    }
    private func configure() {
        timer?.invalidate(); timer = nil
        guard enabled else {
            manager.stopMonitoringSignificantLocationChanges()
            manager.monitoredRegions.forEach { manager.stopMonitoring(for: $0) }
            motion.stopActivityUpdates()
            status = "自动提醒已关闭"; return
        }
        guard let home else { status = "请先设置家的位置"; return }
        guard manager.authorizationStatus == .authorizedAlways else { status = "自动到家检测需要始终允许定位"; return }
        if CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) {
            let region = CLCircularRegion(center: home, radius: radius, identifier: "ke.home-reminders")
            region.notifyOnEntry = true; region.notifyOnExit = true
            manager.startMonitoring(for: region)
        }
        if CLLocationManager.significantLocationChangeMonitoringAvailable() { manager.startMonitoringSignificantLocationChanges() }
        if CMMotionActivityManager.isActivityAvailable() {
            motion.startActivityUpdates(to: .main) { [weak self] activity in
                Task { @MainActor in
                    guard let self else { return }
                    self.motionRevision += 1
                    if let a = activity, a.confidence != .low, !a.automotive, !a.cycling, (a.stationary || a.walking) {
                        self.safeMotionAt = .now
                    } else { self.safeMotionAt = nil }
                    self.evaluate()
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        Task {
            do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
            catch { status = "通知权限未开启" }
        }
        refresh()
    }
    func refresh() {
        reloadShiftPlans()
        guard enabled, home != nil else { return }
        manager.requestLocation()
        refreshMotion()
    }
    private func refreshMotion() {
        guard CMMotionActivityManager.isActivityAvailable() else { safeMotionAt = nil; return }
        let checkedAt = Date()
        let revision = motionRevision
        motion.queryActivityStarting(from: checkedAt.addingTimeInterval(-120), to: checkedAt, to: .main) { [weak self] activities, error in
            Task { @MainActor in
                guard let self, self.motionRevision == revision else { return }
                if error == nil, let activity = activities?.last,
                   activity.confidence != .low, !activity.automotive, !activity.cycling,
                   activity.stationary || activity.walking {
                    self.safeMotionAt = checkedAt
                } else { self.safeMotionAt = nil }
                self.evaluate()
            }
        }
    }
    private func reloadShiftPlans() {
        guard let shifts = defaults.dictionary(forKey: "us.saved-shifts.v2") as? [String: String] else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for key in Array(endTimes.keys) where shifts[key] == nil || shifts[key] == "none" {
            endTimes.removeValue(forKey: key); overrides.remove(key)
            defaults.removeObject(forKey: "us.shift-plan.override." + key)
        }
        for (key, kind) in shifts where !overrides.contains(key) {
            let remotePlan = defaults.data(forKey: "us.shift-plan.remote." + key).flatMap { try? JSONDecoder().decode(ShiftPlan.self, from: $0) }
            guard let date = formatter.date(from: key),
                  let end = (remotePlan ?? ShiftPlan.load(kind: kind, defaults: defaults))?.resolve(on: date)?.end else { continue }
            endTimes[key] = end
        }
        defaults.set(try? JSONEncoder().encode(endTimes), forKey: "us.shift-end-times")
        defaults.set(Array(overrides), forKey: "us.shift-end-overrides")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if settingHome, manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse { manager.requestLocation() }
        configure()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0, latest.horizontalAccuracy <= radius,
              abs(latest.timestamp.timeIntervalSinceNow) < 60 else { status = "位置不确定，提醒暂缓"; return }
        location = latest
        if settingHome {
            home = latest.coordinate; settingHome = false
            defaults.set(latest.coordinate.latitude, forKey: "us.home.latitude")
            defaults.set(latest.coordinate.longitude, forKey: "us.home.longitude")
            homeLabel = "已设置家的位置"; configure()
        }
        evaluate()
    }
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) { if region.identifier == "ke.home-reminders" { refresh() } }
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) { if region.identifier == "ke.home-reminders" { location = nil; safeMotionAt = nil; status = "还没到家，提醒暂缓" } }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { location = nil; status = "位置暂时不可用，提醒暂缓" }
    private func evaluate() {
        guard enabled, let home, let location, abs(location.timestamp.timeIntervalSinceNow) < 60 else { status = "等待新的到家位置，提醒暂缓"; return }
        guard location.distance(from: CLLocation(latitude: home.latitude, longitude: home.longitude)) + location.horizontalAccuracy <= radius else { status = "还没到家，提醒暂缓"; return }
        guard HomeReminderGate.canDeliver(isHome: true, locationAt: location.timestamp,
                                          motionAt: safeMotionAt, speed: location.speed, now: .now)
        else { status = "驾驶或活动状态不确定，提醒暂缓"; return }
        status = "已到家，未检测到驾驶"
        let now = Date()
        if endTimes.values.contains(where: { end in
            let due = end.addingTimeInterval(3600)
            return Calendar.current.isDateInToday(due) && now >= due
        }) { deliver("d3", title: "维生素 D3", body: "已过下班一小时；按你设定的安排，跟晚饭一起吃。") }
        if let dinnerAt, Calendar.current.isDateInToday(dinnerAt) { deliver("dinner", title: "晚饭后提醒", body: "鲁拉西酮 · 按你设定的安排服用。") }
        if let bedtime = Calendar.current.date(bySettingHour: 21, minute: 30, second: 0, of: now), now >= bedtime {
            deliver("bedtime", title: "睡前提醒", body: "碳酸锂晚上那片、劳拉西泮一片半、佐匹克隆一片 · 按你现有的用药安排。")
        }
    }
    private func deliver(_ kind: String, title: String, body: String) {
        let key = Self.dayKey(.now) + ":" + kind
        guard !delivered.contains(key), !completed.contains(key), !inFlight.contains(key) else { return }
        inFlight.insert(key)
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        Task {
            defer { inFlight.remove(key) }
            guard await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .authorized else { status = "通知权限未开启"; return }
            guard enabled, let home, let location,
                  abs(location.timestamp.timeIntervalSinceNow) < 60,
                  location.distance(from: CLLocation(latitude: home.latitude, longitude: home.longitude)) + location.horizontalAccuracy <= radius,
                  HomeReminderGate.canDeliver(isHome: true, locationAt: location.timestamp,
                                              motionAt: safeMotionAt, speed: location.speed, now: .now) else { return }
            do {
                try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "ke.home." + key, content: content, trigger: nil))
                delivered.insert(key); defaults.set(Array(delivered), forKey: "us.medicine-delivered")
            } catch { status = "通知发送失败，等待重试" }
        }
    }
}
