import Foundation
import os

/// Centralised OSLog categories. Use these instead of `print`.
public enum Log {
    private static let subsystem = "com.jackwells.gympass"

    public static let agent = Logger(subsystem: subsystem, category: "agent")
    public static let puregym = Logger(subsystem: subsystem, category: "puregym")
    public static let wallet = Logger(subsystem: subsystem, category: "wallet")
    public static let signing = Logger(subsystem: subsystem, category: "signing")
    public static let apns = Logger(subsystem: subsystem, category: "apns")
    public static let server = Logger(subsystem: subsystem, category: "server")
    public static let tunnel = Logger(subsystem: subsystem, category: "tunnel")
    public static let database = Logger(subsystem: subsystem, category: "database")
    public static let ipc = Logger(subsystem: subsystem, category: "ipc")
    public static let ui = Logger(subsystem: subsystem, category: "ui")
    public static let security = Logger(subsystem: subsystem, category: "security")

    public static func logger(for category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
