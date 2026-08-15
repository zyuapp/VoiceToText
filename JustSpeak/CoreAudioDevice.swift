import CoreAudio
import Foundation

enum CoreAudioDevice {
    static func uniqueID(for deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &dataSize,
            &uid
        ) == noErr, let uid else { return nil }

        return uid.takeUnretainedValue() as String
    }

    static func deviceID(for uniqueID: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uniqueID = uniqueID as CFString
        var deviceID = kAudioObjectUnknown
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = withUnsafePointer(to: &uniqueID) { uniqueIDPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uniqueIDPointer,
                &dataSize,
                &deviceID
            )
        }

        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }
}
