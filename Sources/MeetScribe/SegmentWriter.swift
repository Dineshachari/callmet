import AVFoundation

final class SegmentWriter {
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var started = false

    func start(url: URL) throws {
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer?.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: 1280,
            AVVideoHeightKey: 720,
            AVVideoCompressionPropertiesKey: [
                AVVideoExpectedSourceFrameRateKey: 24,
                AVVideoAverageBitRateKey: 3_000_000
            ]
        ]
        let createdVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        createdVideoInput.expectsMediaDataInRealTime = true

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128_000
        ]
        let createdSystemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        createdSystemAudioInput.expectsMediaDataInRealTime = true

        let createdMicAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        createdMicAudioInput.expectsMediaDataInRealTime = true

        guard let writer else { return }
        guard writer.canAdd(createdVideoInput), writer.canAdd(createdSystemAudioInput), writer.canAdd(createdMicAudioInput) else {
            throw NSError(domain: "MeetScribe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to add one or more writer inputs"])
        }

        writer.add(createdVideoInput)
        writer.add(createdSystemAudioInput)
        writer.add(createdMicAudioInput)

        videoInput = createdVideoInput
        systemAudioInput = createdSystemAudioInput
        micAudioInput = createdMicAudioInput
        started = false
        writer.startWriting()
    }

    func appendVideo(_ sample: CMSampleBuffer) {
        startSessionIfNeeded(sample)
        guard let videoInput, videoInput.isReadyForMoreMediaData else { return }
        videoInput.append(sample)
    }

    func appendSystemAudio(_ sample: CMSampleBuffer) {
        startSessionIfNeeded(sample)
        guard let systemAudioInput, systemAudioInput.isReadyForMoreMediaData else { return }
        systemAudioInput.append(sample)
    }

    func appendMicAudio(_ sample: CMSampleBuffer) {
        startSessionIfNeeded(sample)
        guard let micAudioInput, micAudioInput.isReadyForMoreMediaData else { return }
        micAudioInput.append(sample)
    }

    func finish() async {
        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        micAudioInput?.markAsFinished()

        guard let writer else { return }
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }

    private func startSessionIfNeeded(_ sample: CMSampleBuffer) {
        guard !started, let writer else { return }
        writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sample))
        started = true
    }
}
