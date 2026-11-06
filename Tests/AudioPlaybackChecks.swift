import Foundation

@main struct AudioPlaybackChecks {
    static func expect(_ actual: [(String, Int)], _ expected: [(String, Int)], _ message: String) {
        precondition(actual.count == expected.count, message)
        for (left, right) in zip(actual, expected) {
            precondition(left.0 == right.0 && left.1 == right.1, message)
        }
    }
    static func main() {
        var queue = AudioPlaybackTimeline()
        precondition(queue.append(itemID: "A", frames: 24000, renderedFrame: 0) == 512)
        precondition(queue.append(itemID: "B", frames: 24000, renderedFrame: 0) == 24512,
                     "A new response must begin after the preceding audio tail")
        expect(queue.truncations(at: 0), [("A", 0), ("B", 0)], "Unheard items have zero offset")
        expect(queue.truncations(at: 12512), [("A", 500), ("B", 0)], "Partial current item and future item")
        expect(queue.truncations(at: 24512), [("B", 0)], "Exact boundary excludes fully heard A")
        expect(queue.truncations(at: 36512), [("B", 500)], "Fully heard A is omitted; partially heard B retains its offset")
        expect(queue.truncations(at: 100000), [("B", 1000)], "Clamp offset to received audio duration")

        var gaps = AudioPlaybackTimeline()
        precondition(gaps.append(itemID: "A", frames: 24000, renderedFrame: 0) == 512)
        precondition(gaps.append(itemID: "A", frames: 24000, renderedFrame: 50000) == 50512,
                     "Audio arriving after starvation must not be scheduled in the past")
        expect(gaps.truncations(at: 50000), [("A", 1000)], "Silence before resumed audio is excluded")
        expect(gaps.truncations(at: 62512), [("A", 1500)], "Starvation gaps are not heard audio")

        var contiguous = AudioPlaybackTimeline()
        precondition(contiguous.append(itemID: "A", frames: 12000, renderedFrame: 0) == 512)
        precondition(contiguous.append(itemID: "A", frames: 12000, renderedFrame: 0) == 12512)
        expect(contiguous.truncations(at: 24512), [("A", 1000)], "Adjacent deltas share one item offset")

        var cap = AudioPlaybackTimeline()
        precondition(cap.append(itemID: "A", frames: 90 * 24000, renderedFrame: 0) == 512)
        precondition(cap.append(itemID: "B", frames: 1, renderedFrame: 0) == nil, "Reject over 90 seconds")
        precondition(cap.tail == 512 + 90 * 24000, "Rejected append must not mutate timeline")
        precondition(cap.append(itemID: "B", frames: 24000, renderedFrame: 24512) != nil,
                     "Played audio frees buffering capacity")
        precondition(cap.append(itemID: "invalid", frames: 0, renderedFrame: 0) == nil)
        precondition(cap.append(itemID: "invalid", frames: -1, renderedFrame: 0) == nil)

        queue.reset()
        precondition(queue.tail == 0)
        expect(queue.truncations(at: 0), [], "Reset removes all previous items")
        precondition(queue.append(itemID: "C", frames: 24000, renderedFrame: 0) == 512)
        expect(queue.truncations(at: 12512), [("C", 500)], "New player generation starts clean")
        print("PASS: continuous item queues, partial/future truncation, starvation gaps, reset and 90-second cap")
    }
}
