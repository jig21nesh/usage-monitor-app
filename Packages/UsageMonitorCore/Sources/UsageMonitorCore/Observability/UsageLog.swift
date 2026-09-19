import Foundation
import os

/// Unified-logging handles (ADR 0006). Interpolate credentials nowhere; mark only ids, status
/// codes and durations as `.public`.
public enum UsageLog {
    public static let subsystem = "com.curiouspilabs.UsageMonitor"

    public static let polling = Logger(subsystem: subsystem, category: "polling")
    public static let providers = Logger(subsystem: subsystem, category: "providers")
    public static let credentials = Logger(subsystem: subsystem, category: "credentials")
    public static let settings = Logger(subsystem: subsystem, category: "settings")
    public static let signposter = OSSignposter(subsystem: subsystem, category: "network")
}
