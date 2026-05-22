import Foundation

public actor JamfRateLimiter {
    private let maxConcurrentRequests: Int
    private let minimumDelay: Duration
    private var inFlight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var lastCompletion = ContinuousClock.now

    public init(maxConcurrentRequests: Int = 5, minimumDelay: Duration = .milliseconds(120)) {
        self.maxConcurrentRequests = maxConcurrentRequests
        self.minimumDelay = minimumDelay
    }

    public func acquire() async {
        if inFlight < maxConcurrentRequests {
            inFlight += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    public func release(responseDuration: Duration? = nil) {
        inFlight = max(0, inFlight - 1)
        lastCompletion = .now
        guard !waiters.isEmpty, inFlight < maxConcurrentRequests else { return }
        let continuation = waiters.removeFirst()
        inFlight += 1
        Task {
            try? await Task.sleep(for: adjustedDelay(responseDuration: responseDuration))
            continuation.resume()
        }
    }

    private func adjustedDelay(responseDuration: Duration?) -> Duration {
        guard let responseDuration else { return minimumDelay }
        return max(minimumDelay, responseDuration / 10)
    }
}
