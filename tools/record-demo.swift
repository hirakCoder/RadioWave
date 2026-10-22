// Records ONE app's window + that app's audio to a .mov using ScreenCaptureKit (macOS 14+).
// Nothing else on screen is captured, and no other app's audio.
//   swift record-demo.swift out.mov 25 RadioWave            # app's largest window (re-opens the popover)
//   swift record-demo.swift out.mov 25 Terminal radiowave-demo  # that app's window whose title contains the text
import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreMedia

// A window-scoped capture needs a window-server connection; a bare CLI has none and aborts with
// CGS_REQUIRE_INIT. Touching NSApplication initializes it.
_ = NSApplication.shared

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "demo.mov"
let seconds = args.count > 2 ? Double(args[2]) ?? 25 : 25
let appName = (args.count > 3 ? args[3] : "RadioWave").lowercased()
let titlePart = args.count > 4 ? args[4].lowercased() : nil

final class Rec: NSObject, SCStreamOutput, SCStreamDelegate {
    let writer: AVAssetWriter
    let vIn: AVAssetWriterInput
    let aIn: AVAssetWriterInput
    var started = false
    var frames = 0, audioBufs = 0

    init(url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 5_000_000]])
        vIn.expectsMediaDataInRealTime = true
        aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000])
        aIn.expectsMediaDataInRealTime = true
        writer.add(vIn); writer.add(aIn)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sb.isValid else { return }
        if type == .screen {
            guard let atts = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let st = atts.first?[.status] as? Int, st == SCFrameStatus.complete.rawValue else { return }
        }
        let ts = CMSampleBufferGetPresentationTimeStamp(sb)
        if !started {
            guard type == .screen else { return }
            started = true
            writer.startWriting(); writer.startSession(atSourceTime: ts)
        }
        if type == .screen, vIn.isReadyForMoreMediaData { vIn.append(sb); frames += 1 }
        if type == .audio, aIn.isReadyForMoreMediaData { aIn.append(sb); audioBufs += 1 }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { print("stream stopped:", error) }
}

let sem = DispatchSemaphore(value: 0)
Task {
    do {
        // The popover is transient (any click elsewhere closes it), so open it right before capture
        // and retry a few times: the app's largest on-screen window, not the 22-px status item.
        func findWindow() async throws -> SCWindow? {
            // Title mode also looks on other Spaces (a window on another Space still captures fine).
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: titlePart == nil)
            var wins = content.windows.filter { ($0.owningApplication?.applicationName ?? "").lowercased().contains(appName) }
            if let titlePart { wins = wins.filter { ($0.title ?? "").lowercased().contains(titlePart) } }
            let w = wins.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
            return (w?.frame.width ?? 0) > 100 ? w : nil
        }
        func openPopover() {
            let t = Process(); t.launchPath = "/usr/bin/osascript"
            t.arguments = ["-e", "tell application \"System Events\" to tell process \"RadioWave\" to click menu bar item 1 of menu bar 2"]
            try? t.run(); t.waitUntilExit()
        }
        var found: SCWindow? = try await findWindow()
        var tries = 0
        while found == nil && tries < 3 && titlePart == nil { openPopover(); try await Task.sleep(nanoseconds: 700_000_000); found = try await findWindow(); tries += 1 }
        guard let win = found else { print("no window for \(appName) after \(tries) attempts"); exit(1) }
        let filter = SCContentFilter(desktopIndependentWindow: win)
        let cfg = SCStreamConfiguration()
        let scale = 2
        cfg.width = Int(win.frame.width) * scale; cfg.height = Int(win.frame.height) * scale
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.capturesAudio = true; cfg.excludesCurrentProcessAudio = true
        cfg.sampleRate = 48000; cfg.channelCount = 2
        cfg.showsCursor = false
        let rec = try Rec(url: URL(fileURLWithPath: outPath), width: cfg.width, height: cfg.height)
        let stream = SCStream(filter: filter, configuration: cfg, delegate: rec)
        let q = DispatchQueue(label: "rec")
        try stream.addStreamOutput(rec, type: .screen, sampleHandlerQueue: q)
        try stream.addStreamOutput(rec, type: .audio, sampleHandlerQueue: q)
        try await stream.startCapture()
        print("recording window \(win.windowID) (\(Int(win.frame.width))x\(Int(win.frame.height))) for \(Int(seconds))s …")
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try await stream.stopCapture()
        rec.vIn.markAsFinished(); rec.aIn.markAsFinished()
        await rec.writer.finishWriting()
        print("done frames=\(rec.frames) audioBuffers=\(rec.audioBufs) status=\(rec.writer.status.rawValue)")
    } catch { print("error:", error) }
    sem.signal()
}
sem.wait()
