//
//  FileManager.swift
//  QuantiLogger
//
//  Created by Martin Troup on 26.10.16.
//  Copyright © 2016 quanti. All rights reserved.
//

import Foundation

/// LogFileManager manages all necessary operations for FileLogger.
class FileLoggerManager {
    /// The class is used as a Singleton, thus should be accesed via instance property !!!
    static let shared = FileLoggerManager()

    let logDirUrl: URL? = {
        do {
            let fileManager = FileManager.default
            let documentDirUrl = try fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let _logDirUrl = documentDirUrl.appendingPathComponent("logs")
            if !fileManager.fileExists(atPath: _logDirUrl.path) {
                try fileManager.createDirectory(at: _logDirUrl, withIntermediateDirectories: true, attributes: nil)
            }
            print("File log directory: \(_logDirUrl).")

            return _logDirUrl
        } catch let error {
            assertionFailure("Failed to create log directory within init() with error: \(error).")
            return nil
        }
    }()

    private(set) var currentLogFileNumber: Int = 0 {
        didSet {
            // Check if currentLogFileNumber got updated, if not - do nothing, thus keep the currentWritableFileHandle opened
            if oldValue == currentLogFileNumber {
                if currentWritableFileHandle == nil {
                    assignNewFileHandle()
                }
            }

            UserDefaults.standard.set(currentLogFileNumber, forKey: QuantiLoggerConstants.UserDefaultsKeys.currentLogFileNumber)

            // Check if new currentLogFileUrl is available (only a safety check, because its part - logDirUrl is Optional
            guard let _currentLogFileUrl = currentLogFileUrl else {
                assertionFailure("New currentLogFileUrl not available while trying to open appropriate currentWritableFileHandler.")
                return
            }

            // Delete the file that is about to be used (it is overriden in a file cycle)
            deleteLogFile(at: _currentLogFileUrl)

            // Open new fileHandle and assign it to currentWritableFileHandle
            assignNewFileHandle()
        }
    }

    var currentLogFileUrl: URL? {
        return logDirUrl?.appendingPathComponent("\(currentLogFileNumber)").appendingPathExtension("log")
    }

    private var currentWritableFileHandle: FileHandle? {
        willSet {
            guard currentWritableFileHandle != newValue else { return }

            currentWritableFileHandle?.closeFile()
        }
    }

    private var dateOfLastLog: Date = Date() {
        didSet {
            UserDefaults.standard.set(dateOfLastLog, forKey: QuantiLoggerConstants.UserDefaultsKeys.dateOfLastLog)
        }
    }
    var numOfLogFiles: Int = 4 {
        willSet(newNumOfLogFiles) {
            if newNumOfLogFiles == 0 {
                assertionFailure("There must be at least 1 log file so FileLogger can be used.")
            }
            if numOfLogFiles > newNumOfLogFiles {
                deleteAllLogFiles()
            }
        }
        didSet {
            UserDefaults.standard.set(numOfLogFiles, forKey: QuantiLoggerConstants.UserDefaultsKeys.numOfLogFiles)
        }
    }

    // Url of the zip file containing all log files.
    var archivedLogFilesUrl: URL? {
        return archivedLogFiles?.url
    }

    // Zip file containing log files
    var archivedLogFiles: Archive? {
        guard let _logDirUrl = logDirUrl else {
            print("\(#function) - logDirUrl is nil.")
            return nil
        }

        let archiveUrl = _logDirUrl.appendingPathComponent("log_files_archive.zip")

        guard let allLogFiles = gettingAllLogFiles(), allLogFiles.count > 0 else {
            print("\(#function) - no log files.")
            return nil
        }

        // Remove old archive if exists
        do {
            try FileManager.default.removeItem(at: archiveUrl)
        } catch let error {
            print("\(#function) - failed to remove old archive file with error \(error).")
        }

        // Create new archive
        guard Archive(url: archiveUrl, accessMode: .create) != nil else {
            print("\(#function) - failed to create the archive.")
            return nil
        }

        // Open newly created archive for update
        guard let archive = Archive(url: archiveUrl, accessMode: .update) else {
            print("\(#function) - failed to open the archive for update.")
            return nil
        }

        // Add all log files to the archive
        do {
            try allLogFiles.forEach { logFileUrl in
                var logFileUrlVar = logFileUrl
                logFileUrlVar.deleteLastPathComponent()
                try archive.addEntry(with: logFileUrl.lastPathComponent, relativeTo: logFileUrlVar, compressionMethod: .deflate)
            }
        } catch let error {
            print("\(#function) - failed to add a log file to the archive with error \(error).")
            return nil
        }

        return archive
    }

    private init() {
        if let _dateOfLastLog = UserDefaults.standard.object(forKey: QuantiLoggerConstants.UserDefaultsKeys.dateOfLastLog) as? Date {
            dateOfLastLog = _dateOfLastLog
        } else {
            UserDefaults.standard.set(dateOfLastLog, forKey: QuantiLoggerConstants.UserDefaultsKeys.dateOfLastLog)
        }

        if let _currentLogFileNumber = UserDefaults.standard.object(forKey: QuantiLoggerConstants.UserDefaultsKeys.currentLogFileNumber) as? Int {
            currentLogFileNumber = _currentLogFileNumber
        } else {
            UserDefaults.standard.set(currentLogFileNumber, forKey: QuantiLoggerConstants.UserDefaultsKeys.currentLogFileNumber)
        }

        if let _numOfLogFiles = UserDefaults.standard.object(forKey: QuantiLoggerConstants.UserDefaultsKeys.numOfLogFiles) as? Int {
            numOfLogFiles = _numOfLogFiles
        } else {
            UserDefaults.standard.set(numOfLogFiles, forKey: QuantiLoggerConstants.UserDefaultsKeys.numOfLogFiles)
        }
    }

    /// Method to reset properties that control the correct flow of storing log files.
    /// - "currentLogFileNumber" represents the current logging file number
    /// - "dateTimeOfLastLog" represents the last date the logger was used
    /// - "numOfLogFiles" represents the number of files that are used for logging, can be set by a user
    func resetPropertiesToDefaultValues() {
        currentWritableFileHandle = nil
        currentLogFileNumber = 0
        dateOfLastLog = Date()
        numOfLogFiles = 4
    }

    /// Method to remove all log files from dedicated log folder. These files are detected by its ".log" suffix.
    func deleteAllLogFiles() {
        guard let aLogFiles = gettingAllLogFiles() else { return }

        aLogFiles.forEach { (aLogFileUrl) in
            deleteLogFile(at: aLogFileUrl)
        }

		resetPropertiesToDefaultValues()
    }

    /// Method to delete a specific log file from dedicated log folder.
    ///
    /// - Parameter fileUrlToDelete: fileName of the log file to be removed
    func deleteLogFile(at fileUrlToDelete: URL) {
        if !FileManager.default.fileExists(atPath: fileUrlToDelete.path) {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileUrlToDelete)
        } catch {
            assertionFailure("Failed to remove log file with error: \(error)")
        }
    }

    /// Method to create a specific log file from dedicated log folder.
    ///
    /// - Parameter fileUrlToAdd: fileName of the log file to be added
    private func createLogFile(at fileUrlToAdd: URL) {
        if FileManager.default.fileExists(atPath: fileUrlToAdd.path) {
            return
        }

        if !FileManager.default.createFile(atPath: fileUrlToAdd.path, contents: nil) {
            assertionFailure("Creating new log file failed.")
        }
    }

    /// Method to open a new file descriptor and assign it to currentWritableFileHandle
    ///
    /// - Parameter fileUrl: fileName of the log file to open file descriptor on
    private func assignNewFileHandle() {
        guard let _currentLogFileUrl = currentLogFileUrl else {
            assertionFailure("Unavailable currentLogFileUrl while trying to assign new currentWritableFileHandle.")
            return
        }

        // Create the file that is about to be used and open its FileHandle (assign it to current WritableFileHandle) if not exists yet.
        createLogFile(at: _currentLogFileUrl)

        // Open new file descriptor (FileHandle)
        do {
            currentWritableFileHandle = try FileHandle(forWritingTo: _currentLogFileUrl)
        } catch let error {
            assertionFailure("Failed to get FileHandle instance (writable file descriptor) for currentLogFileUrl with error: \(error).")
        }
    }

    /// Method to get all log file names from dedicated log folder. These files are detected by its ".log" suffix.
    ///
    /// - Returns: Array of log file names
    func gettingAllLogFiles() -> [URL]? {
        guard let _logDirUrl = logDirUrl else { return nil }

        do {
            let directoryContent = try FileManager.default.contentsOfDirectory(at: _logDirUrl, includingPropertiesForKeys: nil, options: [])
            let logFiles = directoryContent.filter({ (file) -> Bool in
                file.pathExtension == "log"
            })
            return logFiles
        } catch let error {
            assertionFailure("Failed to get log directory content with error: \(error).")
        }

        return nil
    }

    /// Method to write a log message into the current log file.
    ///
    /// - Parameters:
    ///   - message: String logging message
    ///   - withMessageHeader: Log message unified header
    ///   - onLevel: Level of the logging message
    func writeToLogFile(message: String, withMessageHeader messageHeader: String, onLevel level: Level) {
        guard logDirUrl != nil, currentLogFileUrl != nil else {
            assertionFailure("logDirUrl or currentLogFileUrl not available while trying to write a message (log) in it.")
            return
        }

        refreshCurrentLogFileStatus()

        let contentToAppend = "\(QuantiLoggerConstants.FileLogger.logFileRecordSeparator) \(messageHeader) \(message)\n"

        currentWritableFileHandle?.seekToEndOfFile()
        if let _contentToAppend = contentToAppend.data(using: .utf8) {
            currentWritableFileHandle?.write(_contentToAppend)
        }
    }

    /// Method to refresh/set "currentLogFileNumber" and "dateTimeOfLastLog" properties. It is called at the beginning
    /// of writeToLogFile(_, _) method.
    private func refreshCurrentLogFileStatus() {
        let currentDate = Date()
        if currentDate.toFullDateString() != dateOfLastLog.toFullDateString() {
            currentLogFileNumber = (currentLogFileNumber + 1) % numOfLogFiles
            dateOfLastLog = currentDate
        }

        if currentWritableFileHandle == nil {
            assignNewFileHandle()
        }
    }

    /// Method to get String content of a specific log file from dedicated log folder.
    ///
    /// - Parameter fileUrlToRead: fileName of the log file to be read from
    /// - Returns: content of the log file
    func readingContentFromLogFile(at fileUrlToRead: URL) -> String? {
        if !FileManager.default.fileExists(atPath: fileUrlToRead.path) {
            return nil
        }

        do {
            return try String(contentsOf: fileUrlToRead, encoding: .utf8)
        } catch let error {
            assertionFailure("Failed to read \(fileUrlToRead.path) with error: \(error).")
        }

        return nil
    }

    /// Method that parses a log file content into an array of LogFileRecord instances
    ///
    /// - Parameter fileUrlToRead: fileName of a log file to parse
    /// - Returns: array of LogFileRecord instances
    func gettingRecordsFromLogFile(at fileUrlToRead: URL) -> [LogFileRecord]? {
        let logFileContent = readingContentFromLogFile(at: fileUrlToRead)
        guard let _logFileContent = logFileContent else { return nil }

        var arrayOflogFileRecords = _logFileContent.components(separatedBy: QuantiLoggerConstants.FileLogger.logFileRecordSeparator)
        arrayOflogFileRecords.remove(at: 0)
        let logFileRecords = arrayOflogFileRecords.map { (logFileRecordInString) -> LogFileRecord in

            let headerTrimmed = logFileRecordInString
                .prefix(while: { $0 != "]"})
                .dropFirst()

            let header = headerTrimmed.asString() + "]"

            let body = logFileRecordInString
                .suffix(from: headerTrimmed.endIndex)
                .dropFirst(2)
                .asString()

            return LogFileRecord(header: header, body: body)
        }

        return logFileRecords
    }
}
