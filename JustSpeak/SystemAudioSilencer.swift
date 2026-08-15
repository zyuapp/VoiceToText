import CoreAudio
import Foundation

final class SystemAudioSilencer {
    private enum SavedProperty: Codable {
        case mute(element: UInt32, value: UInt32)
        case volume(element: UInt32, value: Float32)

        var address: AudioObjectPropertyAddress {
            switch self {
            case .mute(let element, _):
                return Self.address(kAudioDevicePropertyMute, element)
            case .volume(let element, _):
                return Self.address(kAudioDevicePropertyVolumeScalar, element)
            }
        }

        private static func address(
            _ selector: AudioObjectPropertySelector,
            _ element: AudioObjectPropertyElement
        ) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
        }
    }

    private static let recoveryKey = "systemAudioSilencerRecovery"
    private static let maximumRestoreRetries = 3
    private var savedProperties = SystemAudioSilencer.loadSavedProperties()
    private var isSilencing = false
    private var isListening = false
    private var restoreRetryCount = 0
    private var restoreRetryWorkItem: DispatchWorkItem?
    private lazy var deviceChangeListener: AudioObjectPropertyListenerBlock = {
        [weak self] _, _ in
        self?.handleDeviceChange()
    }

    func recover() {
        guard !savedProperties.isEmpty else { return }
        restore()
    }

    func silence() {
        guard !isSilencing else { return }
        cancelRestoreRetry()
        isSilencing = true
        updateDeviceListener()
        refreshSilencedDevices()
    }

    func restore() {
        isSilencing = false
        beginRestoreAttempts()
    }

    private func beginRestoreAttempts() {
        restoreRetryCount = 0
        restoreSavedDevices()
        updateDeviceListener()
        scheduleRestoreRetryIfNeeded()
    }

    private func handleDeviceChange() {
        if isSilencing {
            refreshSilencedDevices()
        } else {
            beginRestoreAttempts()
        }
    }

    private func refreshSilencedDevices() {
        guard isSilencing else { return }

        let currentDevices = [
            defaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice),
            defaultDevice(for: kAudioHardwarePropertyDefaultSystemOutputDevice)
        ].compactMap { $0 }.reduce(into: [String: AudioDeviceID]()) { result, deviceID in
            guard let uid = CoreAudioDevice.uniqueID(for: deviceID) else { return }
            result[uid] = deviceID
        }

        for uid in Array(savedProperties.keys) where currentDevices[uid] == nil {
            restore(uid)
        }

        for (uid, deviceID) in currentDevices {
            if let properties = savedProperties[uid] {
                for property in properties {
                    _ = applyForcedValue(for: property, to: deviceID)
                }
            } else if !silence(deviceID, uid: uid) {
                print("System audio could not be muted for output device \(deviceID)")
            }
        }
    }

    private func silence(_ deviceID: AudioDeviceID, uid: String) -> Bool {
        let muteAddress = SavedProperty.mute(
            element: kAudioObjectPropertyElementMain,
            value: 0
        ).address

        if let originalMute: UInt32 = readSettableProperty(muteAddress, from: deviceID),
           saveAndApply(
               .mute(element: kAudioObjectPropertyElementMain, value: originalMute),
               to: deviceID,
               uid: uid
           ) {
            return true
        }

        let masterVolumeAddress = SavedProperty.volume(
            element: kAudioObjectPropertyElementMain,
            value: 0
        ).address

        if let originalVolume: Float32 = readSettableProperty(
            masterVolumeAddress,
            from: deviceID
        ), saveAndApply(
            .volume(element: kAudioObjectPropertyElementMain, value: originalVolume),
            to: deviceID,
            uid: uid
        ) {
            return true
        }

        let channelCount = outputChannelCount(for: deviceID)
        guard channelCount > 0 else { return false }

        var didMuteChannel = false
        for channel in 1...channelCount {
            let property = SavedProperty.volume(
                element: AudioObjectPropertyElement(channel),
                value: 0
            )
            guard let originalVolume: Float32 = readSettableProperty(
                property.address,
                from: deviceID
            ) else { continue }

            if saveAndApply(
                .volume(
                    element: AudioObjectPropertyElement(channel),
                    value: originalVolume
                ),
                to: deviceID,
                uid: uid
            ) {
                didMuteChannel = true
            }
        }
        return didMuteChannel
    }

    private func saveAndApply(
        _ property: SavedProperty,
        to deviceID: AudioDeviceID,
        uid: String
    ) -> Bool {
        savedProperties[uid, default: []].append(property)
        persistSavedProperties()

        guard applyForcedValue(for: property, to: deviceID) else {
            savedProperties[uid]?.removeLast()
            if savedProperties[uid]?.isEmpty == true {
                savedProperties.removeValue(forKey: uid)
            }
            persistSavedProperties()
            return false
        }
        return true
    }

    private func applyForcedValue(
        for property: SavedProperty,
        to deviceID: AudioDeviceID
    ) -> Bool {
        switch property {
        case .mute:
            return write(UInt32(1), to: property.address, on: deviceID)
        case .volume:
            return write(Float32(0), to: property.address, on: deviceID)
        }
    }

    private func restoreSavedDevices() {
        for uid in Array(savedProperties.keys) {
            restore(uid)
        }
    }

    private func scheduleRestoreRetryIfNeeded() {
        guard !isSilencing,
              !savedProperties.isEmpty,
              restoreRetryCount < Self.maximumRestoreRetries,
              restoreRetryWorkItem == nil else { return }

        restoreRetryCount += 1
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.restoreRetryWorkItem = nil
            self.restoreSavedDevices()
            self.updateDeviceListener()
            self.scheduleRestoreRetryIfNeeded()
        }
        restoreRetryWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
    }

    private func cancelRestoreRetry() {
        restoreRetryWorkItem?.cancel()
        restoreRetryWorkItem = nil
        restoreRetryCount = 0
    }

    private func restore(_ uid: String) {
        guard let deviceID = deviceID(for: uid),
              let properties = savedProperties[uid] else { return }

        let remainingProperties = properties.filter {
            !restore($0, on: deviceID)
        }

        if remainingProperties.isEmpty {
            savedProperties.removeValue(forKey: uid)
        } else {
            savedProperties[uid] = remainingProperties
        }
        persistSavedProperties()
    }

    private func restore(
        _ property: SavedProperty,
        on deviceID: AudioDeviceID
    ) -> Bool {
        switch property {
        case .mute(_, let originalValue):
            guard let currentValue: UInt32 = readSettableProperty(
                property.address,
                from: deviceID
            ) else { return false }
            guard currentValue == 1 else { return true }
            return write(originalValue, to: property.address, on: deviceID)
        case .volume(_, let originalValue):
            guard let currentValue: Float32 = readSettableProperty(
                property.address,
                from: deviceID
            ) else { return false }
            guard currentValue == 0 else { return true }
            return write(originalValue, to: property.address, on: deviceID)
        }
    }

    private func defaultDevice(
        for selector: AudioObjectPropertySelector
    ) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = kAudioObjectUnknown
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        ) == noErr, deviceID != kAudioObjectUnknown else { return nil }

        return deviceID
    }

    private func deviceID(for uid: String) -> AudioDeviceID? {
        CoreAudioDevice.deviceID(for: uid)
    }

    private func outputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = SavedProperty.volume(
            element: kAudioObjectPropertyElementMain,
            value: 0
        ).address
        address.mSelector = kAudioDevicePropertyStreamConfiguration
        var dataSize: UInt32 = 0

        guard AudioObjectGetPropertyDataSize(
            deviceID,
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else { return 0 }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }

        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            rawBuffer
        ) == noErr else { return 0 }

        let bufferList = rawBuffer.bindMemory(to: AudioBufferList.self, capacity: 1)
        return UnsafeMutableAudioBufferListPointer(bufferList)
            .reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private func readSettableProperty<T>(
        _ propertyAddress: AudioObjectPropertyAddress,
        from deviceID: AudioDeviceID
    ) -> T? {
        var address = propertyAddress
        guard AudioObjectHasProperty(deviceID, &address) else { return nil }

        var isSettable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(
            deviceID,
            &address,
            &isSettable
        ) == noErr, isSettable.boolValue else { return nil }

        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        var dataSize = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            value
        ) == noErr else { return nil }

        return value.pointee
    }

    private func write(
        _ value: UInt32,
        to propertyAddress: AudioObjectPropertyAddress,
        on deviceID: AudioDeviceID
    ) -> Bool {
        var address = propertyAddress
        var value = value
        return AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<UInt32>.size),
            &value
        ) == noErr
    }

    private func write(
        _ value: Float32,
        to propertyAddress: AudioObjectPropertyAddress,
        on deviceID: AudioDeviceID
    ) -> Bool {
        var address = propertyAddress
        var value = value
        return AudioObjectSetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            UInt32(MemoryLayout<Float32>.size),
            &value
        ) == noErr
    }

    private func updateDeviceListener() {
        if isSilencing || !savedProperties.isEmpty {
            startListeningForDeviceChanges()
        } else {
            stopListeningForDeviceChanges()
        }
    }

    private func startListeningForDeviceChanges() {
        guard !isListening else { return }
        isListening = true

        for selector in deviceChangeSelectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectAddPropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                .main,
                deviceChangeListener
            )
        }
    }

    private func stopListeningForDeviceChanges() {
        guard isListening else { return }
        isListening = false

        for selector in deviceChangeSelectors {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                .main,
                deviceChangeListener
            )
        }
    }

    private var deviceChangeSelectors: [AudioObjectPropertySelector] {
        [
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice,
            kAudioHardwarePropertyDevices
        ]
    }

    private func persistSavedProperties() {
        let defaults = UserDefaults.standard
        guard !savedProperties.isEmpty else {
            defaults.removeObject(forKey: Self.recoveryKey)
            return
        }

        do {
            defaults.set(
                try JSONEncoder().encode(savedProperties),
                forKey: Self.recoveryKey
            )
        } catch {
            print("System audio recovery state could not be saved: \(error)")
        }
    }

    private static func loadSavedProperties() -> [String: [SavedProperty]] {
        guard let data = UserDefaults.standard.data(forKey: recoveryKey) else {
            return [:]
        }

        do {
            return try JSONDecoder().decode(
                [String: [SavedProperty]].self,
                from: data
            )
        } catch {
            print("System audio recovery state could not be loaded: \(error)")
            return [:]
        }
    }
}
