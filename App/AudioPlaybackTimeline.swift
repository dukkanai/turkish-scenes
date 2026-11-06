import Foundation

/// Pure sample-clock bookkeeping, independent of AVAudioEngine and network access.
struct AudioPlaybackTimeline {
    private struct Span {
        var start: Int64
        var end: Int64
    }
    private struct Item {
        var id: String
        var spans: [Span]
        func heard(at frame: Int64) -> Int64 {
            spans.reduce(0) { $0 + max(0, min($1.end, frame) - $1.start) }
        }
        var frames: Int64 { spans.reduce(0) { $0 + $1.end - $1.start } }
    }
    private var items: [Item] = []
    private(set) var tail: Int64 = 0
    private let maximumBufferedFrames: Int64 = 90 * 24000
    /// Return a future player sample time; nil means bounded buffering was exceeded.
    mutating func append(itemID: String, frames: Int64, renderedFrame: Int64) -> Int64? {
        guard frames > 0 else { return nil }
        let buffered = items.reduce(Int64(0)) { $0 + $1.frames - $1.heard(at: renderedFrame) }
        guard frames <= maximumBufferedFrames - buffered else { return nil }
        // Keep the newest item even when drained: further deltas may extend it.
        while items.count > 1, let first = items.first, first.heard(at: renderedFrame) == first.frames {
            items.removeFirst()
        }
        // The player clock continues during starvation. Do not schedule new audio in the past.
        let start = max(tail, renderedFrame + 512)
        let end = start + frames
        if let last = items.indices.last, items[last].id == itemID {
            if let span = items[last].spans.indices.last, items[last].spans[span].end == start {
                items[last].spans[span].end = end
            } else { items[last].spans.append(Span(start: start, end: end)) }
        } else { items.append(Item(id: itemID, spans: [Span(start: start, end: end)])) }
        tail = end
        return start
    }
    /// Include the currently audible item and all future queued items. A fully heard
    /// last item is included too, so a late delta cannot restart it after interruption.
    func truncations(at renderedFrame: Int64) -> [(String, Int)] {
        items.enumerated().compactMap { index, item in
            let heard = item.heard(at: renderedFrame)
            guard heard < item.frames || index == items.count - 1 else { return nil }
            return (item.id, Int(heard * 1000 / 24000))
        }
    }
    mutating func reset() { items = []; tail = 0 }
}
