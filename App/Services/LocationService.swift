import CoreLocation
import PumpedCore

/// The one-shot location fetch at workout start (spec §8): asks for When-In-Use permission the
/// first time, then waits a short while for a fix.
///
/// UI tests never touch Core Location: `-ui-testing-location <lat>,<lon>` stands in for a fix, and
/// without it the location is unavailable.
@MainActor
final class LocationService: NSObject {
    static let shared = LocationService()

    /// How long to wait for a fix before falling back to the gym picker.
    static let timeout: Duration = .seconds(8)
    /// A fix this recent and this accurate is used straight away.
    private static let maxCachedAge: TimeInterval = 120
    private static let maxCachedAccuracy: CLLocationAccuracy = 100

    private var manager: CLLocationManager?
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private var fixWaiters: [CheckedContinuation<LocationFix, Never>] = []

    func currentFix(timeout: Duration = LocationService.timeout) async -> LocationFix {
        if let stub = Self.uiTestingFix() { return stub }

        let manager = self.manager ?? makeManager()
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
            await withCheckedContinuation { authorizationWaiters.append($0) }
        }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .denied, .restricted:
            return .denied
        default:
            return .unavailable
        }

        if let cached = manager.location,
           -cached.timestamp.timeIntervalSinceNow < Self.maxCachedAge,
           cached.horizontalAccuracy >= 0, cached.horizontalAccuracy <= Self.maxCachedAccuracy {
            return .located(Self.coordinate(cached))
        }

        let timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.finishFix(.unavailable)
        }
        defer { timeoutTask.cancel() }
        return await withCheckedContinuation { continuation in
            fixWaiters.append(continuation)
            if fixWaiters.count == 1 { manager.requestLocation() }
        }
    }

    private func makeManager() -> CLLocationManager {
        let manager = CLLocationManager()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.delegate = self
        self.manager = manager
        return manager
    }

    private func finishAuthorization() {
        guard manager?.authorizationStatus != .notDetermined else { return }
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func finishFix(_ fix: LocationFix) {
        let waiters = fixWaiters
        fixWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: fix) }
    }

    private nonisolated static func coordinate(_ location: CLLocation) -> Coordinate {
        Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    private static func uiTestingFix() -> LocationFix? {
        let arguments = CommandLine.arguments
        guard arguments.contains("-ui-testing-reset-store") else { return nil }
        guard let index = arguments.firstIndex(of: "-ui-testing-location"), index + 1 < arguments.count else {
            return .unavailable
        }
        let parts = arguments[index + 1].split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return .unavailable }
        return .located(Coordinate(latitude: parts[0], longitude: parts[1]))
    }
}

extension LocationService: CLLocationManagerDelegate {
    // Core Location calls back on the thread the manager was made on, which is the main thread.
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { finishAuthorization() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = Self.coordinate(location)
        MainActor.assumeIsolated { finishFix(.located(coordinate)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        MainActor.assumeIsolated { finishFix(.unavailable) }
    }
}
