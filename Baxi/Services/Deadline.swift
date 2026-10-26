import Foundation

/// Runs async work with a time limit: its value, or nil when it throws or the time runs out. At the
/// limit the work is cancelled and not waited for, so work that ignores cancellation (a location
/// request, a callback API) cannot hold the caller past the limit.
enum Deadline {
    static func run<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () async throws -> T) async -> T? {
        await withCheckedContinuation { (c: CheckedContinuation<T?, Never>) in
            let once = Once(c)
            let worker = Task { once.resume(try? await work()) }
            // A Dispatch timer, not Task.sleep: it fires even while busy work fills Swift's task threads.
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                worker.cancel()
                once.resume(nil)
            }
        }
    }

    /// Resumes the continuation with whichever answer comes first; later ones are dropped.
    private final class Once<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T?, Never>?
        init(_ c: CheckedContinuation<T?, Never>) { continuation = c }
        func resume(_ value: T?) {
            lock.lock(); let c = continuation; continuation = nil; lock.unlock()
            c?.resume(returning: value)
        }
    }
}
