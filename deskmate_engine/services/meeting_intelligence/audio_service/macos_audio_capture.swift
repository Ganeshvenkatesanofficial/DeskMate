import Foundation
import ScreenCaptureKit
import AVFoundation

@available(macOS 13.0, *)
class AssetWriterRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    var writer: AVAssetWriter?
    var input: AVAssetWriterInput?
    var isStarted = false
    let outputURL: URL
    
    init(url: URL) {
        self.outputURL = url
        super.init()
        try? FileManager.default.removeItem(at: url)
        guard let w = try? AVAssetWriter(outputURL: url, fileType: .wav) else {
            fputs("Failed to init AVAssetWriter\n", stderr)
            exit(1)
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let inp = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        inp.expectsMediaDataInRealTime = true
        if w.canAdd(inp) {
            w.add(inp)
            self.writer = w
            self.input = inp
        }
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid else { return }
        guard let w = writer, let inp = input else { return }
        if !isStarted {
            w.startWriting()
            w.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            isStarted = true
        }
        if inp.isReadyForMoreMediaData {
            inp.append(sampleBuffer)
        }
    }
    
    func finish() async {
        guard let w = writer, let inp = input, isStarted else { return }
        inp.markAsFinished()
        await w.finishWriting()
    }
}

@available(macOS 13.0, *)
func runCapture(outputPath: String) async {
    let outUrl = URL(fileURLWithPath: outputPath)
    let recorder = AssetWriterRecorder(url: outUrl)
    
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            fputs("No display found\n", stderr)
            exit(1)
        }
        
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 16000
        config.channelCount = 1
        config.excludesCurrentProcessAudio = true
        config.width = 16
        config.height = 16
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        
        let stream = SCStream(filter: filter, configuration: config, delegate: recorder)
        try stream.addStreamOutput(recorder, type: .audio, sampleHandlerQueue: DispatchQueue(label: "audio.writer"))
        try await stream.startCapture()
        
        // Signal readiness to parent process
        print("READY")
        fflush(stdout)
        
        // Keep running until stdin has data or EOF, or process signal
        let stdinHandle = FileHandle.standardInput
        _ = stdinHandle.availableData
        
        try await stream.stopCapture()
        await recorder.finish()
        print("STOPPED")
        fflush(stdout)
    } catch {
        fputs("Capture error: \(error)\n", stderr)
        exit(1)
    }
    exit(0)
}

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: macos_audio_capture <output_wav_path>\n", stderr)
    exit(1)
}

let outputPath = CommandLine.arguments[1]

if #available(macOS 13.0, *) {
    Task {
        await runCapture(outputPath: outputPath)
    }
    dispatchMain()
} else {
    fputs("macOS 13.0 or higher required\n", stderr)
    exit(1)
}
