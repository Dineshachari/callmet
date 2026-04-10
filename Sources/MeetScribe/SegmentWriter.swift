import AVFoundation

final class SegmentWriter {
    private let queue = DispatchQueue(label: "com.dinesh.meetscribe.segmentWriter")
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var systemAudioInput: AVAssetWriterInput?
    private var micAudioInput: AVAssetWriterInput?
    private var started = false

    private var sampleCounts = (video: 0, systemAudio: 0, micAudio: 0)
    private var videoNoPBCount = 0

    func start(url: URL) throws {
        try queue.sync {
            sampleCounts = (0, 0, 0)
            let newWriter = try AVAssetWriter(outputURL: url, fileType: .mov)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1280,
                AVVideoHeightKey: 720
            ]
            let createdVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            createdVideoInput.expectsMediaDataInRealTime = true

            let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: createdVideoInput,
                sourcePixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                    kCVPixelBufferWidthKey as String: 1280,
                    kCVPixelBufferHeightKey as String: 720
                ]
            )

            let stereoAudioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128_000
            ]
            let createdSystemAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: stereoAudioSettings)
            createdSystemAudioInput.expectsMediaDataInRealTime = true

            let micAudioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000
            ]
            let createdMicAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micAudioSettings)
            createdMicAudioInput.expectsMediaDataInRealTime = true

            guard newWriter.canAdd(createdVideoInput),
                  newWriter.canAdd(createdSystemAudioInput),
                  newWriter.canAdd(createdMicAudioInput) else {
                throw NSError(domain: "MeetScribe", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to add one or more writer inputs"])
            }

            newWriter.add(createdVideoInput)
            newWriter.add(createdSystemAudioInput)
            newWriter.add(createdMicAudioInput)

            self.writer = newWriter
            self.videoInput = createdVideoInput
            self.pixelBufferAdaptor = adaptor
            self.systemAudioInput = createdSystemAudioInput
            self.micAudioInput = createdMicAudioInput
            self.started = false
            newWriter.startWriting()
        }
    }

    func appendVideo(_ sample: CMSampleBuffer) {
        queue.async { [weak self] in
            guard let self else { return }
            self.sampleCounts.video += 1

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else {
                self.videoNoPBCount += 1
                return
            }

            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            if self.sampleCounts.video == 1 {
                let w = CVPixelBufferGetWidth(pixelBuffer)
                let h = CVPixelBufferGetHeight(pixelBuffer)
                let pf = CVPixelBufferGetPixelFormatType(pixelBuffer)
                let ioSurface = CVPixelBufferGetIOSurface(pixelBuffer)
                AppTrace.log("writer.firstVideoSample pts=\(pts.seconds) dims=\(w)x\(h) pf=\(pf) ioSurface=\(ioSurface != nil) writerStatus=\(self.writer?.status.rawValue ?? -1)")
            }

            self.startSessionIfNeeded(pts: pts)

            guard let adaptor = self.pixelBufferAdaptor,
                  let input = self.videoInput, input.isReadyForMoreMediaData else { return }

            if !adaptor.append(pixelBuffer, withPresentationTime: pts), self.sampleCounts.video <= 3 {
                AppTrace.log("writer.videoAppendFailed count=\(self.sampleCounts.video) writerStatus=\(self.writer?.status.rawValue ?? -1) error=\(self.writer?.error ?? "none" as Any)")
            }
        }
    }

    func appendSystemAudio(_ sample: CMSampleBuffer) {
        queue.async { [weak self] in
            guard let self else { return }
            self.sampleCounts.systemAudio += 1
            if self.sampleCounts.systemAudio == 1 {
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                AppTrace.log("writer.firstSystemAudioSample pts=\(pts.seconds) writerStatus=\(self.writer?.status.rawValue ?? -1)")
            }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            self.startSessionIfNeeded(pts: pts)
            guard let input = self.systemAudioInput, input.isReadyForMoreMediaData else { return }
            if !input.append(sample), self.sampleCounts.systemAudio <= 3 {
                AppTrace.log("writer.systemAudioAppendFailed writerStatus=\(self.writer?.status.rawValue ?? -1) error=\(self.writer?.error?.localizedDescription ?? "none")")
            }
        }
    }

    func appendMicAudio(_ sample: CMSampleBuffer) {
        queue.async { [weak self] in
            guard let self else { return }
            self.sampleCounts.micAudio += 1
            if self.sampleCounts.micAudio == 1 {
                let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                var fmtInfo = ""
                if let fd = CMSampleBufferGetFormatDescription(sample),
                   let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd) {
                    fmtInfo = " ch=\(asbd.pointee.mChannelsPerFrame) rate=\(asbd.pointee.mSampleRate) bps=\(asbd.pointee.mBitsPerChannel)"
                }
                AppTrace.log("writer.firstMicAudioSample pts=\(pts.seconds)\(fmtInfo) writerStatus=\(self.writer?.status.rawValue ?? -1)")
            }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample)
            self.startSessionIfNeeded(pts: pts)
            guard let input = self.micAudioInput, input.isReadyForMoreMediaData else { return }
            if !input.append(sample), self.sampleCounts.micAudio <= 3 {
                AppTrace.log("writer.micAudioAppendFailed writerStatus=\(self.writer?.status.rawValue ?? -1) error=\(self.writer?.error?.localizedDescription ?? "none")")
            }
        }
    }

    func finish() async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                AppTrace.log("writer.finish video=\(self.sampleCounts.video) videoWritten=\(self.sampleCounts.video - self.videoNoPBCount) videoSkipped=\(self.videoNoPBCount) sysAudio=\(self.sampleCounts.systemAudio) micAudio=\(self.sampleCounts.micAudio)")
                self.videoInput?.markAsFinished()
                self.systemAudioInput?.markAsFinished()
                self.micAudioInput?.markAsFinished()

                guard let writer = self.writer else {
                    continuation.resume()
                    return
                }
                writer.finishWriting {
                    continuation.resume()
                }
            }
        }
    }

    private func startSessionIfNeeded(pts: CMTime) {
        guard !started, let writer else { return }
        let safeStart = CMTimeSubtract(pts, CMTime(seconds: 1.0, preferredTimescale: 600))
        AppTrace.log("writer.startSession samplePts=\(pts.seconds) sessionStart=\(safeStart.seconds) writerStatus=\(writer.status.rawValue)")
        writer.startSession(atSourceTime: safeStart)
        started = true
    }
}
