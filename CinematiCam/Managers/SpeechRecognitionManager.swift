import Foundation
import Speech

class SpeechRecognitionManager {

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    func requestPermission(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                let granted = status == .authorized
                if granted {
                    print("Speech recognition permission granted")
                } else {
                    print("Speech recognition permission denied")
                }
                completion(granted)
            }
        }
    }

    func isAvailable() -> Bool {
        return speechRecognizer?.isAvailable ?? false
    }

    func transcribe(videoURL: URL, completion: @escaping ([CaptionSegment]?, Error?) -> Void) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            completion(nil, NSError(domain: "SpeechRecognition", code: -1, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer not available"]))
            return
        }

        let request = SFSpeechURLRecognitionRequest(url: videoURL)
        request.shouldReportPartialResults = false

        recognizer.recognitionTask(with: request) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Transcription error: \(error.localizedDescription)")
                    completion(nil, error)
                    return
                }

                guard let result = result, result.isFinal else {
                    return
                }

                let segments = self.createCaptionSegments(from: result.bestTranscription)
                print("Transcription complete: \(segments.count) segments")
                completion(segments, nil)
            }
        }
    }

    private func createCaptionSegments(from transcription: SFTranscription) -> [CaptionSegment] {
        var segments: [CaptionSegment] = []
        var currentWords: [String] = []
        var segmentStartTime: TimeInterval = 0
        var segmentEndTime: TimeInterval = 0

        let maxWordsPerSegment = 6

        for (index, segment) in transcription.segments.enumerated() {
            if currentWords.isEmpty {
                segmentStartTime = segment.timestamp
            }

            currentWords.append(segment.substring)
            segmentEndTime = segment.timestamp + segment.duration

            let shouldBreak = currentWords.count >= maxWordsPerSegment ||
                (index < transcription.segments.count - 1 &&
                 transcription.segments[index + 1].timestamp - segmentEndTime > 0.5)

            if shouldBreak || index == transcription.segments.count - 1 {
                let text = currentWords.joined(separator: " ")
                let caption = CaptionSegment(
                    startTime: segmentStartTime,
                    endTime: segmentEndTime,
                    text: text
                )
                segments.append(caption)
                currentWords = []
            }
        }

        return segments
    }
}
