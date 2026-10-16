import AppKit
import CoreAudio
import CoreMediaIO

/// Detects that the user is probably in a call or presenting, so breaks can wait.
/// Uses only system state that needs no permission prompt:
///   - microphone: some process is capturing audio input (CoreAudio)
///   - camera: a video device is running (CoreMediaIO)
///   - screen sharing: Zoom's share helper is running (other apps share inside a call,
///     which the mic check already covers)
enum CallDetector {
    private static var cached = false
    private static var checkedAt = Date.distantPast

    /// Cached for a couple of seconds; called from the 1 s scheduler tick.
    static func isInCall() -> Bool {
        if Date().timeIntervalSince(checkedAt) < 2 { return cached }
        cached = isMicrophoneInUse() || isCameraInUse() || isZoomSharing()
        checkedAt = Date()
        return cached
    }

    // MARK: - Microphone

    static func isMicrophoneInUse() -> Bool {
        if #available(macOS 14.0, *) {
            return anyProcessCapturingInput()
        }
        return anyInputDeviceRunning()
    }

    /// Per-process check (macOS 14+). Accurate even for headsets like AirPods, where the
    /// device-level "running" flag is also set by plain music playback.
    @available(macOS 14.0, *)
    private static func anyProcessCapturingInput() -> Bool {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for process in objects(kAudioHardwarePropertyProcessObjectList) {
            guard uint32(process, kAudioProcessPropertyIsRunningInput) != 0 else { continue }
            if pid(process) != ownPID { return true }
        }
        return false
    }

    /// Fallback for macOS 13: any device with input streams that is running.
    private static func anyInputDeviceRunning() -> Bool {
        objects(kAudioHardwarePropertyDevices).contains { device in
            hasInputStreams(device) && uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) != 0
        }
    }

    private static func objects(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    @available(macOS 14.0, *)
    private static func pid(_ process: AudioObjectID) -> pid_t {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else { return 0 }
        return value
    }

    private static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    // MARK: - Camera

    static func isCameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == noErr else { return false }

        address.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)
        for device in devices {
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(device, &address, 0, nil, runningSize, &runningSize, &running) == noErr,
               running != 0 {
                return true
            }
        }
        return false
    }

    // MARK: - Screen sharing

    /// Zoom runs a separate "CptHost" helper only while sharing the screen.
    static func isZoomSharing() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "us.zoom.CptHost" || $0.localizedName == "CptHost"
        }
    }
}
