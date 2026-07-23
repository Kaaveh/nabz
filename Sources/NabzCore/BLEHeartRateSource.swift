import Foundation
import CoreBluetooth

/// CoreBluetooth-backed `HeartRateSource` (PRD §5, §7.1, §9). An actor owns the connection
/// state machine and reconnect scheduling; a companion `NSObject` (`CentralController`) owns the
/// `CBCentralManager` and all `CBPeripheral` objects, confined to a dedicated serial queue.
///
/// Split rationale: `CBCentralManagerDelegate` must be an `@objc`/`NSObject`, which an actor
/// can't be, and `CBPeripheral` isn't `Sendable` — so the delegate keeps every CB object on its
/// own queue and hands the actor only Sendable `BLEEvent`s and `HeartRateSample`s. The dedicated
/// queue also means no main run loop is required for callbacks to fire in a CLI process (R-2).
public actor BLEHeartRateSource: HeartRateSource {
    public nonisolated let samples: AsyncStream<HeartRateSample>
    public nonisolated let connectionState: AsyncStream<ConnectionState>

    private let stateCont: AsyncStream<ConnectionState>.Continuation
    private let central: CentralController
    private var state: ConnectionState = .idle
    private var backoff = Backoff()
    private var rng = SystemRandomNumberGenerator()
    private var reconnectTask: Task<Void, Never>?

    /// - Parameter target: optional `--device` name or UUID (FR-1.3). `nil` → first HR sensor.
    ///   Preference *persistence* is SPEC-06; this spec accepts the resolved identifier only.
    public init(target: String? = nil) {
        var sampleCont: AsyncStream<HeartRateSample>.Continuation!
        samples = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { sampleCont = $0 }
        var stCont: AsyncStream<ConnectionState>.Continuation!
        connectionState = AsyncStream(bufferingPolicy: .bufferingNewest(1)) { stCont = $0 }
        stateCont = stCont

        central = CentralController(target: target, samples: sampleCont, listOnly: false)
        Task { await self.start() }
    }

    private func start() {
        stateCont.yield(state)              // .idle, so consumers have a value immediately
        central.attach(source: self)        // creates the CBCentralManager and begins the flow
    }

    /// Called by the delegate (on its queue) for every CB fact. Runs the pure transition, streams
    /// the new state on change, then drives the side effects the table doesn't capture.
    func handle(_ event: BLEEvent) {
        let previous = state
        state = BLEStateMachine.transition(state, on: event)
        if state != previous {
            stateCont.yield(state)
            nabzLog("state → \(self.state)")
        }

        switch event {
        case .subscribed:
            reconnectTask?.cancel()
            backoff.reset()
        case .dropped, .connectFailed:
            scheduleReconnect()
        case .unauthorized, .poweredOff:
            reconnectTask?.cancel()
        case .scan, .discovered:
            break
        }
    }

    /// Sleep the next backoff interval, then ask the delegate to reconnect the known peripheral.
    /// Infinite retries: a failed attempt yields another `.dropped`/`.connectFailed` that re-arms
    /// this, with the interval growing toward the 30 s cap (FR-1.6).
    private func scheduleReconnect() {
        reconnectTask?.cancel()
        let delay = backoff.next(using: &rng)
        nabzLog("reconnect attempt \(self.backoff.attempt) in \(String(format: "%.1f", delay)) s")
        let central = central
        reconnectTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            central.reconnect()
        }
    }

    /// One-shot scan that lists nearby HR sensors without connecting (FR-1.2, for `--list`).
    /// Runs its own list-only central so it never disturbs a streaming source (R-6).
    public static func discover(scanFor duration: Duration = .seconds(5)) async -> [DiscoveredDevice] {
        let controller = CentralController(target: nil, samples: nil, listOnly: true)
        controller.attach(source: nil)
        try? await Task.sleep(for: duration)
        let devices = controller.snapshot()
        controller.stop()
        return devices
    }
}

/// Owns the `CBCentralManager` and every `CBPeripheral`, all confined to `queue`. Reports facts to
/// the actor as Sendable `BLEEvent`s and yields parsed samples straight to the stream continuation.
/// `@unchecked Sendable` is sound because all mutable state is touched only on `queue`.
final class CentralController: NSObject, @unchecked Sendable {
    // CBUUID isn't Sendable, so it can't be a global; instance `let`s stay confined to `queue`.
    private let heartRateService = CBUUID(string: "180D")
    private let hrMeasurement = CBUUID(string: "2A37")

    private let queue = DispatchQueue(label: "app.nabz.ble")
    private let target: String?
    private let samples: AsyncStream<HeartRateSample>.Continuation?
    private let listOnly: Bool

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var discovered: [UUID: DiscoveredDevice] = [:]
    private weak var source: BLEHeartRateSource?

    init(target: String?, samples: AsyncStream<HeartRateSample>.Continuation?, listOnly: Bool) {
        self.target = target
        self.samples = samples
        self.listOnly = listOnly
        super.init()
    }

    /// Wire up the actor and spin up the central. `source` is nil for list-only discovery.
    func attach(source: BLEHeartRateSource?) {
        queue.async {
            self.source = source
            self.central = CBCentralManager(delegate: self, queue: self.queue)
        }
    }

    func reconnect() {
        queue.async {
            guard let peripheral = self.peripheral else { return }
            self.central.connect(peripheral, options: nil)
        }
    }

    func stop() {
        queue.async {
            guard let central = self.central else { return }
            central.stopScan()
            if let peripheral = self.peripheral { central.cancelPeripheralConnection(peripheral) }
        }
    }

    /// Snapshot of devices seen so far, strongest signal first.
    func snapshot() -> [DiscoveredDevice] {
        queue.sync { discovered.values.sorted { $0.rssi > $1.rssi } }
    }

    private func send(_ event: BLEEvent) {
        guard let source else { return }
        Task { await source.handle(event) }
    }
}

extension CentralController: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        switch manager.state {
        case .poweredOn:
            manager.scanForPeripherals(withServices: [heartRateService],
                                       options: [CBCentralManagerScanOptionAllowDuplicatesKey: listOnly])
            send(.scan)
        case .unauthorized:
            send(.unauthorized)                 // R-1: dedicated state with actionable messaging
        case .poweredOff, .unsupported, .resetting, .unknown:
            send(.poweredOff)
        @unknown default:
            send(.poweredOff)
        }
    }

    func centralManager(_ manager: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? "Unknown"
        discovered[peripheral.identifier] = DiscoveredDevice(
            name: name, identifier: peripheral.identifier.uuidString, rssi: RSSI.intValue)

        guard !listOnly,
              self.peripheral == nil,
              BLEStateMachine.matchesTarget(name: peripheral.name,
                                            identifier: peripheral.identifier.uuidString,
                                            target: target)
        else { return }

        manager.stopScan()
        self.peripheral = peripheral            // retain: CBCentralManager only holds it once connecting
        manager.connect(peripheral, options: nil)
        send(.discovered(name: name))
    }

    func centralManager(_ manager: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([heartRateService])
    }

    func centralManager(_ manager: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        send(.connectFailed(reason: error?.localizedDescription ?? "connect failed"))
    }

    func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        send(.dropped)                          // actor schedules the backed-off reconnect
    }
}

extension CentralController: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == heartRateService }) else {
            send(.connectFailed(reason: "no heart-rate service"))
            return
        }
        peripheral.discoverCharacteristics([hrMeasurement], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == hrMeasurement })
        else {
            send(.connectFailed(reason: "no HR measurement characteristic"))
            return
        }
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard characteristic.isNotifying else { return }
        send(.subscribed(name: peripheral.name ?? "Unknown"))   // fully connected (FR-1.5)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        guard let data = characteristic.value else { return }
        do {
            let sample = try HeartRateMeasurementParser.parse(data, at: Date())
            samples?.yield(sample)
        } catch {
            nabzLog("skipping malformed 0x2A37 payload: \(error)", level: .error)  // FR-2.3
        }
    }
}
