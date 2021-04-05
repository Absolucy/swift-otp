//
//  OtpInfo.swift
//  PlaygroundOTP
//
//  Created by Aspen on 4/5/21.
//

import Foundation

public struct OtpInfo: Identifiable, Hashable {
	public static func == (lhs: OtpInfo, rhs: OtpInfo) -> Bool {
		lhs.id == rhs.id || (lhs.issuer == rhs.issuer && lhs.name == rhs.name && lhs.entry == rhs.entry)
	}

	public let id = UUID()
	public var issuer: String?
	public var name: String?
	public var entry: OtpEntry

	public init(issuer: String? = nil, name: String? = nil, entry: OtpEntry) {
		self.issuer = issuer
		self.name = name
		self.entry = entry
	}
}
