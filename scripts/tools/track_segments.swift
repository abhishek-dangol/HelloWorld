// Prints every track's edit segments (and empty gaps) of a video file.
// Usage: swift track_segments.swift <file.mov>
import AVFoundation
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let asset = AVURLAsset(url: url)
print("asset duration", CMTimeGetSeconds(asset.duration))
for track in asset.tracks {
    print("track", track.mediaType.rawValue, "range", CMTimeGetSeconds(track.timeRange.start), "+", CMTimeGetSeconds(track.timeRange.duration))
    for s in track.segments {
        let m = s.timeMapping
        print(String(format: "   %@ target %.4f..%.4f  source %.4f..%.4f", s.isEmpty ? "EMPTY" : "media",
                     CMTimeGetSeconds(m.target.start), CMTimeGetSeconds(m.target.end),
                     CMTimeGetSeconds(m.source.start), CMTimeGetSeconds(m.source.end)))
    }
}
