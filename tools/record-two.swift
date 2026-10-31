// Records TWO windows (RadioWave's popover + a Terminal window) in ONE ScreenCaptureKit stream, so the
// panes share a clock and audio — no cross-stream sync to worry about. Everything else on the display
// is excluded (black). Crop the two regions in post; their display coordinates are printed at start.
//   swift record-two.swift out.mov 30 "allowedtools bash"
import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreMedia

_ = NSApplication.shared  // window-server connection, else CGS_REQUIRE_INIT abort

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "two.mov"
let seconds = args.count > 2 ? Double(args[2]) ?? 30 : 30
let termTitle = (args.count > 3 ? args[3] : "claude").lowercased()
let scale = args.count > 4 ? Double(args[4]) ?? 1.5 : 1.5

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
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000]])
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
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let pop = content.windows.filter { ($0.owningApplication?.applicationName ?? "").lowercased().contains("radiowave") }
            .max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height })
        let term = content.windows.first { ($0.owningApplication?.applicationName ?? "").lowercased().contains("terminal")
            && ($0.title ?? "").lowercased().contains(termTitle) }
        guard let pop, pop.frame.width > 100 else { print("no RadioWave popover on screen"); exit(1) }
        guard let term else { print("no Terminal window titled *\(termTitle)*"); exit(1) }
        // Both windows must sit on one display; pick the display that contains the popover.
        guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: pop.frame.midX, y: pop.frame.midY)) }) else { print("no display"); exit(1) }
        let filter = SCContentFilter(display: display, including: [pop, term])
        let cfg = SCStreamConfiguration()
        cfg.width = Int(Double(display.width) * scale); cfg.height = Int(Double(display.height) * scale)
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
        // Regions in OUTPUT pixels (display-relative × scale) so post can crop without guessing.
        func region(_ w: SCWindow) -> String {
            let x = (w.frame.origin.x - display.frame.origin.x) * scale, y = (w.frame.origin.y - display.frame.origin.y) * scale
            return "\(Int(x)) \(Int(y)) \(Int(w.frame.width * scale)) \(Int(w.frame.height * scale))"
        }
        print("recording display \(display.displayID) \(cfg.width)x\(cfg.height) for \(Int(seconds))s | popover: \(region(pop)) | terminal: \(region(term))")
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        try await stream.stopCapture()
        rec.vIn.markAsFinished(); rec.aIn.markAsFinished()
        await rec.writer.finishWriting()
        print("done frames=\(rec.frames) audioBuffers=\(rec.audioBufs) status=\(rec.writer.status.rawValue)")
    } catch { print("error:", error) }
    sem.signal()
}
sem.wait()
