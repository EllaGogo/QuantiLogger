//
//  SystemLogger.swift
//  QuantiLogger
//
//  Created by Martin Troup on 05/06/2017.
//  Copyright © 2017 quanti. All rights reserved.
//

import Foundation
import os

/// Pre-built logger that wraps system os_logger
public class SystemLogger: Logging {

    private var logger: OSLog?

    public init(subsystem: String, category: String) {
        if #available(iOS 10, *) {
            logger = OSLog(subsystem: subsystem, category: category)
        }
    }

    private func systemLevel(forLevel level: Level) -> OSLogType {
        if #available(iOS 10, *) {
            switch level {
            case .info:
                return .info
            case .debug:
                return .debug
            case .verbose, .warn, .error:
                return .default
            case .system:
                return .fault
            case .process:
                return .error
            }
        } else {
            return .default
        }
    }

    public var levels: [Level] = [.info]

    public func log(_ message: String, onLevel level: Level) {
        guard let _logger = logger else { return }

        if #available(iOS 10, *) {
            let staticMessage = "\(messageHeader(forLevel: level)) \(message)"
            os_log("%@", log: _logger, type: systemLevel(forLevel: level), staticMessage)
        }
    }
}
