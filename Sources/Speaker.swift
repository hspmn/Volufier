import Foundation
import CoreBluetooth

final class Speaker: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum Phase { case idle, scanning, connecting, model, reading, ready, applying, failed }
    private let service = CBUUID(string: "48093A01-1A48-11E9-AB14-D663BD873D93")
    private let notifyID = CBUUID(string: "48090001-1A48-11E9-AB14-D663BD873D93")
    private let writeID = CBUUID(string: "48090002-1A48-11E9-AB14-D663BD873D93")
    private var manager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writer: CBCharacteristic?
    private var decoder = Frames.Decoder()
    private var code: UInt8 = 0xec
    private var excluded = Set<UUID>()
    private var timer: Timer?
    private var retryDelay = 10.0
    private var readback: Timer?
    private var requested: Int?
    private var queuedLevel: Int?
    private var rememberedID: UUID?
    private(set) var sound = SoundSettings()
    private(set) var soundMessage = ""
    private(set) var soundBusy = false
    private var usingAdvanced = false
    private var needsAdvancedRead = false
    private var soundQueue: [SoundSettings.Group] = []
    private var awaiting: SoundSettings.Group?
    private var pendingEdit: SoundSettings.Edit?
    private var soundTimer: Timer?
    private var readTask: DispatchWorkItem?
    private var active = false
    private var verified = false

    private(set) var phase: Phase = .idle
    private(set) var status = "Disconnected"
    private(set) var volume: Int?
    var changed: (() -> Void)?

    private func show(_ phase: Phase, _ message: String) {
        self.phase = phase
        status = message
        changed?()
        NSLog("Volufier • %@", message)
    }

    private func deadline(_ seconds: Double, _ action: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in action() }
    }

    func start(advanced: Bool = false) {
        stop()
        usingAdvanced = advanced
        active = true
        excluded.removeAll()
        if let manager { update(manager) }
        else {
            show(.connecting, "Waiting for Bluetooth access…")
            manager = CBCentralManager(delegate: self, queue: .main)
        }
    }

    func ensureConnection(advanced: Bool) {
        if !active || phase == .failed { start(advanced: advanced); return }
        let entering = advanced && !usingAdvanced
        usingAdvanced = advanced
        needsAdvancedRead = advanced && (needsAdvancedRead || entering)
        if needsAdvancedRead, phase == .ready { refreshSound() }
        if !advanced { resetSound() }
    }

    func refreshLevel() {
        if phase == .ready { send(Frames.volume) }
    }

    private func clearLink() {
        timer?.invalidate()
        readback?.invalidate()
        if manager?.isScanning == true { manager?.stopScan() }
        resetSound()
        queuedLevel = nil
        if let p = peripheral {
            p.delegate = nil
            manager?.cancelPeripheralConnection(p)
        }
        peripheral = nil
        writer = nil
        volume = nil
        requested = nil
        verified = false
        decoder = Frames.Decoder()
        code = 0xec
    }

    func stop() {
        active = false
        clearLink()
        show(.idle, "Disconnected")
    }

    private func fail(_ message: String) {
        clearLink()
        show(.failed, message)
        guard active, manager?.state == .poweredOn else { return }
        let interval = retryDelay
        retryDelay = min(120, retryDelay * 2)
        deadline(interval) { [weak self] in
            guard let self, self.active else { return }
            self.start(advanced: self.usingAdvanced)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if active { update(central) }
    }

    private func update(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let id = rememberedID, let p = central.retrievePeripherals(withIdentifiers: [id]).first {
                connect(p)
            } else { scan() }
        case .poweredOff: fail("Turn on Bluetooth on this Mac.")
        case .unauthorized: fail("Allow Volufier in System Settings → Privacy & Security → Bluetooth.")
        case .unsupported: fail("Bluetooth Low Energy is unavailable on this Mac.")
        default: clearLink(); show(.connecting, "Waiting for Bluetooth…")
        }
    }

    private func scan() {
        guard active, let manager, manager.state == .poweredOn else { return }
        show(.scanning, "Looking for your MR5…")
        manager.scanForPeripherals(withServices: nil)
        deadline(14) { [weak self] in
            self?.fail("No available MR5. Wake the speakers, close ConneX on your phone and try again.")
        }
        for p in manager.retrieveConnectedPeripherals(withServices: [service]) where !excluded.contains(p.identifier) {
            connect(p)
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData ad: [String: Any], rssi RSSI: NSNumber) {
        guard phase == .scanning, !excluded.contains(p.identifier) else { return }
        let name = ((ad[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? "").uppercased()
        let services = ad[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let isEdifier = (ad[CBAdvertisementDataManufacturerDataKey] as? Data)?.starts(with: [0xe0,0x07]) == true
        if name == "EDIFIER BLE" || name.contains("MR5") || isEdifier || services.contains(service)
            || services.contains(CBUUID(string: "3A01")) {
            connect(p)
        }
    }

    private func connect(_ p: CBPeripheral) {
        if manager?.isScanning == true { manager?.stopScan() }
        peripheral = p
        p.delegate = self
        show(.connecting, "Checking the speaker…")
        manager?.connect(p)
        deadline(7) { [weak self] in self?.nextCandidate() }
    }

    private func nextCandidate() {
        if let p = peripheral { excluded.insert(p.identifier); if rememberedID == p.identifier { rememberedID = nil } }
        clearLink()
        scan()
    }

    func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
        guard p === peripheral, phase == .connecting else { return }
        p.discoverServices([service])
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        if p === peripheral { nextCandidate() }
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard p === peripheral else { return }
        if verified { fail("Speaker disconnected. Reconnect when it’s available.") }
        else { nextCandidate() }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard p === peripheral else { return }
        guard error == nil, let s = p.services?.first(where: { $0.uuid == service }) else { nextCandidate(); return }
        p.discoverCharacteristics([notifyID, writeID], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard p === peripheral else { return }
        guard error == nil, let chars = s.characteristics,
              let n = chars.first(where: { $0.uuid == notifyID && $0.properties.contains(.notify) }),
              let w = chars.first(where: { $0.uuid == writeID && $0.properties.contains(.writeWithoutResponse) })
        else { nextCandidate(); return }
        writer = w
        p.setNotifyValue(true, for: n)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        guard p === peripheral, c.uuid == notifyID else { return }
        guard error == nil, c.isNotifying else { nextCandidate(); return }
        show(.model, "Identifying the MR5…")
        identify()
    }

    private func identify() {
        guard send(Frames.model) else { return }
        deadline(2) { [weak self] in
            guard let self else { return }
            if self.code == 0xec { self.code = 0x06; self.identify() }
            else { self.nextCandidate() }
        }
    }

    @discardableResult private func send(_ command: UInt8, payload: [UInt8] = []) -> Bool {
        guard let p = peripheral, p.state == .connected, let writer, p.canSendWriteWithoutResponse else {
            fail("The speaker connection is busy. Reconnect to read its volume.")
            return false
        }
        p.writeValue(Frames.request(command, code: code, payload: payload), for: writer, type: .withoutResponse)
        return true
    }

    var intendedLevel: Int? { queuedLevel ?? requested ?? volume }

    func set(_ target: Int) {
        if phase == .applying, verified, (0...30).contains(target) { queuedLevel = target; return }
        guard phase == .ready, verified, let current = volume, (0...30).contains(target), target != current else { return }
        requested = target
        show(.applying, "Setting speaker volume…")
        guard send(Frames.setVolume, payload: [UInt8(target)]) else { return }
        readback = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
            guard let self, self.phase == .applying else { return }
            self.send(Frames.volume)
        }
        deadline(3) { [weak self] in self?.fail("The speaker did not confirm its volume. Reconnect to read it again.") }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard p === peripheral, c.uuid == notifyID else { return }
        guard error == nil, let data = c.value else { fail("Lost the speaker’s reply. Reconnect to try again."); return }
        for r in decoder.append(data) {
            if usingAdvanced, verified, let group = SoundSettings.Group(rawValue: r.command) {
                receiveSound(group, r.payload)
                continue
            }
            if r.command == Frames.model, phase == .model {
                guard Frames.isMR5(r.payload) else { nextCandidate(); return }
                verified = true
                rememberedID = p.identifier
                show(.reading, "Reading master volume…")
                guard send(Frames.volume) else { return }
                deadline(3) { [weak self] in self?.fail("The MR5 did not report its master volume. Try reconnecting.") }
            } else if r.command == Frames.volume, verified, let value = Frames.level(r.payload) {
                let firstReading = volume == nil
                retryDelay = 10
                volume = value
                // A delayed poll or knob notification can arrive while a write is in flight.
                if phase == .applying && requested != value { continue }
                timer?.invalidate()
                readback?.invalidate()
                requested = nil
                if phase != .ready { show(.ready, "Connected") } else { changed?() }
                if usingAdvanced && (firstReading || needsAdvancedRead) { refreshSound() }
                if let level = queuedLevel { queuedLevel = nil; set(level) }

            }
        }
    }

    private func resetSound() {
        soundTimer?.invalidate()
        readTask?.cancel()
        soundQueue = []
        awaiting = nil
        pendingEdit = nil
        sound = SoundSettings()
        soundBusy = false
        soundMessage = ""
    }

    func refreshSound() {
        guard usingAdvanced, verified, phase == .ready, !soundBusy else { return }
        resetSound()
        needsAdvancedRead = false
        soundQueue = SoundSettings.Group.allCases
        soundBusy = true
        nextSoundRead()
    }

    private func nextSoundRead() {
        guard !soundQueue.isEmpty else {
            soundBusy = false
            changed?()
            return
        }
        let group = soundQueue.removeFirst()
        awaiting = group
        guard send(group.rawValue) else { return }
        scheduleSoundTimeout(group)
    }

    private func scheduleSoundTimeout(_ group: SoundSettings.Group) {
        soundTimer?.invalidate()
        soundTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            guard let self, self.awaiting == group else { return }
            if self.pendingEdit != nil { self.soundMessage = "Change unconfirmed. Refresh to read the speaker again." }
            else { self.soundMessage = "Some settings are unavailable. Refresh to try again." }
            _ = self.sound.read(group, [])
            self.finishSoundRead()
        }
    }

    private func finishSoundRead() {
        soundTimer?.invalidate()
        readTask?.cancel()
        pendingEdit = nil
        awaiting = nil
        nextSoundRead()
        changed?()
    }

    private func receiveSound(_ group: SoundSettings.Group, _ bytes: [UInt8]) {
        let valid = sound.read(group, bytes)
        guard awaiting == group else { changed?(); return }
        if !valid { soundMessage = "This speaker returned an unsupported setting." }
        if valid, let edit = pendingEdit, !sound.confirms(edit) { return }
        finishSoundRead()
    }

    func editSound(_ edit: SoundSettings.Edit) {
        guard usingAdvanced, verified, phase == .ready, !soundBusy, !sound.confirms(edit),
              let (command, bytes, group) = sound.command(for: edit) else { return }
        pendingEdit = edit
        awaiting = group
        soundBusy = true
        soundMessage = ""
        changed?()
        guard send(command, payload: bytes) else { return }
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.awaiting == group, self.pendingEdit != nil else { return }
            self.send(group.rawValue)
        }
        readTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: task)
        scheduleSoundTimeout(group)
    }
}
