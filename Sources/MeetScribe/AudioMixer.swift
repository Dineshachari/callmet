import AVFoundation
import CoreMedia
import Darwin.Mach

final class AudioMixer {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?

    var onBuffer: ((CMSampleBuffer) -> Void)?

    func start() throws {
        let inputNode = engine.inputNode
        try inputNode.setVoiceProcessingEnabled(true)

        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw NSError(domain: "MeetScribe", code: 2, userInfo: [NSLocalizedDescriptionKey: "No microphone input channels available"])
        }
        AppTrace.log("mixer.inputFormat rate=\(inputFormat.sampleRate) ch=\(inputFormat.channelCount)")

        let monoOutput = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: inputFormat.sampleRate,
            channels: 1,
            interleaved: true
        )
        let outputFormat = monoOutput ?? inputFormat
        AppTrace.log("mixer.outputFormat rate=\(outputFormat.sampleRate) ch=\(outputFormat.channelCount)")

        self.outputFormat = outputFormat
        self.converter = inputFormat == outputFormat ? nil : AVAudioConverter(from: inputFormat, to: outputFormat)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, time in
            guard let self else { return }
            let outputFormat = self.outputFormat ?? inputFormat

            let sourceBuffer: AVAudioPCMBuffer
            if let converter = self.converter {
                let ratio = outputFormat.sampleRate / buffer.format.sampleRate
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
                guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }

                var error: NSError?
                let status = converter.convert(to: converted, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                guard status != .error, error == nil else { return }
                guard converted.frameLength > 0 else { return }
                sourceBuffer = converted
            } else {
                sourceBuffer = buffer
            }

            guard let sampleBuffer = self.makeSampleBuffer(from: sourceBuffer, at: time) else { return }
            self.onBuffer?(sampleBuffer)
        }

        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func makeSampleBuffer(from pcmBuffer: AVAudioPCMBuffer, at time: AVAudioTime) -> CMSampleBuffer? {
        guard let outputFormat = outputFormat else { return nil }

        var asbd = outputFormat.streamDescription.pointee
        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else { return nil }

        let frameCount = Int(pcmBuffer.frameLength)
        let byteCount = frameCount * Int(asbd.mBytesPerFrame)
        guard byteCount > 0 else { return nil }

        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else { return nil }

        guard let source = pcmBuffer.audioBufferList.pointee.mBuffers.mData else { return nil }
        let sourceBytes = UnsafeRawPointer(source)
        let copyStatus = CMBlockBufferReplaceDataBytes(
            with: sourceBytes,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: byteCount
        )
        guard copyStatus == kCMBlockBufferNoErr else { return nil }

        let presentation: CMTime
        if time.isHostTimeValid {
            presentation = CMClockMakeHostTimeFromSystemUnits(time.hostTime)
        } else {
            presentation = CMTime(value: time.sampleTime, timescale: CMTimeScale(outputFormat.sampleRate))
        }
        let duration = CMTime(value: Int64(pcmBuffer.frameLength), timescale: CMTimeScale(outputFormat.sampleRate))
        var timing = CMSampleTimingInfo(duration: duration, presentationTimeStamp: presentation, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: frameCount,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr else { return nil }
        return sampleBuffer
    }
}
