//
//  MailData.swift
//  QuantiLogger
//
//  Created by Alžbeta Gogoláková on 18.08.2021.
//

import Foundation

public struct MailData {
    public let subject: String
    public let recipients: [String]?
    public let message: String
    public let attachments: [AttachmentData]?
}

public struct AttachmentData {
    public let data: Data
    public let mimeType: String
    public let fileName: String
}
