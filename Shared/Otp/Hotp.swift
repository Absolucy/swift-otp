//
//  Hotp.swift
//  PlaygroundOTP
//
//  Created by Aspen on 4/5/21.
//

import Combine
import CryptoKit
import Foundation

// This is just an implementation of RFC 4226.
// A simpler explaination is available on Wikipedia: https://en.wikipedia.org/wiki/HMAC-based_One-Time_Password
public func hotpCode(key: Data, digits: Double = 6, counter: UInt64) -> UInt64 {
	// First, we counter our 64-bit counter into 8 big-endian bytes.
	let counterBytes = withUnsafeBytes(of: counter.bigEndian, Array.init)
	assert(counterBytes.count == 8)
	// Technically HOTP and TOTP support more than SHA-1, but 99.9% of all codes are SHA-1.
	// Anyways, we hash the big-endian counter using our key as well, the key.
	let digest = Data(HMAC<Insecure.SHA1>.authenticationCode(for: counterBytes, using: SymmetricKey(data: key)))
	// Now, get the last byte of the HMAC digest, and modulo it by 16, to get our starting index, aka "i"
	let i = digest.last! % 16
	// Truncate our digest, getting the 4 bytes starting at i.
	let truncated = digest[i ..< i + 4]
	var code: UInt32 = 0
	// Convert the truncated bytes into a unsigned 32-bit int, then modulo it by 2^31
	// We have to copy the bytes, else we risk a crash from unaligned memory.
	// Swift plz add from_be/le/ne_bytes like Rust has.
	// Source: https://stackoverflow.com/a/38024025
	assert(withUnsafeMutableBytes(of: &code) { truncated.copyBytes(to: $0) } == MemoryLayout.size(ofValue: code))
	// And to finish this up, we modulo the code by 2^31, then 10^digits.
	return UInt64(code % UInt32(pow(2.0, 31))) % UInt64(pow(10, Double(digits)))
}
