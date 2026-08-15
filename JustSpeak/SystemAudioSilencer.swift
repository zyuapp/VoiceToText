import CoreAudio
import Foundation

final class SystemAudioSilencer {
    private enum SavedProperty {
        case mute(AudioObjectPropertyAddress, UInt32)
        case volume(AudioObjectPropertyAddress, Float32)
    }

    private var savedProperties: [AudioDeviceID: [SavedProperty]] = [:]
    private var isSilencing = false
    private var isListening = false
    private lazy var deviceChangeListener: AudioObjectPropertyListenerBlock = {
        [weak self] _, _ in
        self?.refreshSilencedDevices()
    }

    func silence() {
        guard !isSilencing else { return }
        isSilencing = true
        startListeningForOutputChanges()
        refreshSilencedDevices()
    }

    func restore() {
        guard isSilencing || !savedProperties.isEmpty else { return }
        isSilencing = false
        stopListeningForOutputChanges()

        for deviceID in Array(savedProperties.keys) {
            restore(deviceID)
        }
    }

    private func refreshSilencedDevices() {
        guard isSilencing else { return }

        let currentDeviceIDs = Set([
            defaultDevice(for: kAudioHardwarePropertyDefaultOutputDevice),
            defaultDevice(for: kAudioHardwarePropertyDefaultSystemOutputDevice)
        ].compactMap { $0 })

        for deviceID in Array(savedProperties.keys) where !currentDeviceIDs.contains(deviceID) {
            restore(deviceID)
        }

        for deviceID in currentDeviceIDs where savedProperties[deviceID] == nil {
            let properties = silence(deviceID)
            if properties.isEmpty {
                print("System audio could not be muted for output device \(deviceID)")
            } else {
                savedProperties[deviceID] = properties
            }
        }
    }

    private func silence(_ deviceID: AudioDeviceID) -> [SavedProperty] {
        let muteAddress = propertyAddress(
            selector: kAudioDevicePropertyMute,
            element: kAudioObjectPropertyElementMain
        )

        if let originalMute: UInt32 = readSettableProperty(muteAddress, from: deviceID),
           write(UInt32(1), to: muteAddress, on: deviceID) {
            return [.mute(muteAddress, originalMute)]
        }

        let masterVolumeAddress = propertyAddress(
            selector: kAudioDevicePropertyVolumeScalar,
            element: kAudioObjectPropertyElementMain
        )

        if let originalVolume: Float32 = readSettableProperty(masterVolumeAddress, from: deviceID),
           write(Float32(0), to: masterVolumeAddress, on: deviceID) {
            return [.volume(masterVolumeAddress, originalVolume)]
        }

        let channelCount = outputChannelCount(for: deviceID)
        guard channelCount > 0 else { return [] }

        return (1...channelCount).compactMap { channel in
            let address = propertyAddress(
                selector: kAudioDevicePropertyVolumeScalar,
                element: AudioObjectPropertyElement(channel)
            )
            guard let originalVolume: Float32 = readSettableProperty(address, from: deviceID),
                  write(Float32(0), to: address, on: deviceID) else { return nil }
            return .volume(address, originalVolume)
        }
    }

    private func restore(_ deviceID: AudioDeviceID) {
        guard let properties = savedProperties.removeValue(forKey: deviceID) else { return }

        for property in properties {
            let restored: Bool
            switch property {
            case .mute(let address, let value):
                restored = write(value, to: address, on: deviceID)
            case .volume(let address, let value):
                restored = write(value, to: address, on: deviceID)
            }

            if !restored {
                print("System audio state could not be restored for output device \(deviceID)")
            }
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

    private func outputChannelCount(for deviceID: AudioDeviceID) -> Int {
        var address = propertyAddress(
            selector: kAudioDevicePropertyStreamConfiguration,
            element: kAudioObjectPropertyElementMain
        )
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

    private func propertyAddress(
        selector: AudioObjectPropertySelector,
        element: AudioObjectPropertyElement
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
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

    private func startListeningForOutputChanges() {
        guard !isListening else { return }
        isListening = true

        for selector in outputDeviceSelectors {
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

    private func stopListeningForOutputChanges() {
        guard isListening else { return }
        isListening = false

        for selector in outputDeviceSelectors {
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

    private var outputDeviceSelectors: [AudioObjectPropertySelector] {
        [
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultSystemOutputDevice
        ]
    }
}
