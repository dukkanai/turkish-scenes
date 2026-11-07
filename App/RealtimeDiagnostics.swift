import Foundation

/// A bounded, memory-only timeline. Entries are reviewed enum values, never
/// error descriptions, service text, URLs, headers, transcripts or identifiers.
enum RealtimeDiagnosticCode: String, CaseIterable {
    case starting, socketOpened, sessionReady, stopped
    case permissionDenied, missingKey, keychainReadFailed
    case setupTimeout, networkOffline, networkTimeout, networkDNS, networkTLS, networkLost, networkOther
    case socketClosed, serviceRejected, responseFailed, responseInterrupted
    case outgoingJSON, incomingJSON, invalidEvent, invalidAudio, invalidTool, toolRejected
    case sendBackpressure, audioSetup, audioConversion, audioPlayback, audioTeardown
    case progressWrite, progressUnavailable
}

struct RealtimeDiagnosticEntry: Identifiable, Equatable {
    let id: Int
    let code: RealtimeDiagnosticCode
}

struct RealtimeDiagnostics {
    private(set) var entries: [RealtimeDiagnosticEntry] = []
    private var sequence = 0
    static let capacity = 24
    mutating func record(_ code: RealtimeDiagnosticCode) {
        // Coalesce repeated callback failures without losing the original stage.
        guard entries.last?.code != code else { return }
        sequence += 1
        entries.append(RealtimeDiagnosticEntry(id: sequence, code: code))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    static func networkCode(_ error: Error) -> RealtimeDiagnosticCode {
        let error = error as NSError
        guard error.domain == NSURLErrorDomain else { return .networkOther }
        switch error.code {
        case URLError.notConnectedToInternet.rawValue: return .networkOffline
        case URLError.timedOut.rawValue: return .networkTimeout
        case URLError.cannotFindHost.rawValue, URLError.dnsLookupFailed.rawValue: return .networkDNS
        case URLError.secureConnectionFailed.rawValue, URLError.serverCertificateHasBadDate.rawValue,
             URLError.serverCertificateUntrusted.rawValue, URLError.serverCertificateHasUnknownRoot.rawValue,
             URLError.serverCertificateNotYetValid.rawValue, URLError.clientCertificateRejected.rawValue,
             URLError.clientCertificateRequired.rawValue: return .networkTLS
        case URLError.networkConnectionLost.rawValue, URLError.cannotConnectToHost.rawValue: return .networkLost
        default: return .networkOther
        }
    }
}

/// Bounds both PCM bytes and non-audio messages before allocating another send task.
struct RealtimeSendBudget {
    private(set) var bytes = 0
    private(set) var messages = 0
    static let maximumBytes = 144_000
    static let maximumMessages = 192
    mutating func reserve(audioBytes: Int) -> Bool {
        guard audioBytes >= 0, audioBytes <= Self.maximumBytes,
              messages < Self.maximumMessages, bytes <= Self.maximumBytes - audioBytes else { return false }
        bytes += audioBytes; messages += 1
        return true
    }
    mutating func release(audioBytes: Int) {
        bytes = max(0, bytes - max(0, audioBytes)); messages = max(0, messages - 1)
    }
}
