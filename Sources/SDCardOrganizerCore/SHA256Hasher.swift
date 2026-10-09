import Foundation
import CryptoKit

/// Cienkie opakowanie wokół CryptoKit SHA256, ułatwiające testowanie
/// i strumieniowe hashowanie dużych plików.
public struct SHA256Hasher {
    private var hasher = SHA256()

    public init() {}

    public mutating func update(_ bytes: ArraySlice<UInt8>) {
        bytes.withUnsafeBytes { hasher.update(bufferPointer: $0) }
    }

    public mutating func update(_ data: Data) {
        hasher.update(data: data)
    }

    public func finalize() -> String {
        hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
