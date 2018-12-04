//
//  CryptoManager.swift
//  KeePassium
//
//  Created by Andrei Popleteev on 2018-02-28.
//  Copyright © 2018 Andrei Popleteev. All rights reserved.
//

import Foundation

/// sha256 digest length in bytes
public let SHA256_SIZE = Int(CC_SHA256_DIGEST_LENGTH)

public final class CryptoManager {

    public static func sha256(of buffer: ByteArray) -> ByteArray {
        var hashBytes = [UInt8](repeating: 0, count: SHA256_SIZE)
        buffer.withBytes { (bytes) in
            CC_SHA256(bytes, CC_LONG(bytes.count), &hashBytes)
        }
        return ByteArray(bytes: hashBytes)
    }
    
    public static func sha512(of bytes: ByteArray) -> ByteArray {
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA512_DIGEST_LENGTH))
        bytes.withBytes { (bytes) in
            CC_SHA512(bytes, CC_LONG(bytes.count), &hash)
        }
        return ByteArray(bytes: hash)
    }
    
    /// Returns `count` bytes from a cryptographically secure random number generator
    /// - Throws: CryptoError.rngError
    public static func getRandomBytes(count: Int) throws -> ByteArray {
        let output = ByteArray(count: count)
        let status = output.withMutableBytes { (outBytes: inout [UInt8]) in
            return SecRandomCopyBytes(kSecRandomDefault, outBytes.count, &outBytes)
        }
        if status != errSecSuccess {
            Diag.warning("Failed to generate random bytes [count: \(count), status: \(status)]")
            throw CryptoError.rngError(code: Int(status))
        }
        return output // ByteArray(bytes: outBytes)
    }
    
    /// Returns a 512-bit (64 byte) HMAC key for the given block index.
    /// - Parameter: key - 64-byte original key
    /// - Parameter: blockIndex
    /// - Returns: sha512(blockIndex + key)
    public static func getHMACKey64(key: ByteArray, blockIndex: UInt64) -> ByteArray {
        assert(key.count == 64)
        let merged = ByteArray.concat(blockIndex.data, key)
        return merged.sha512
    }
    
    public static func hmacSHA256(data: ByteArray, key: ByteArray) -> ByteArray {
        assert(key.count == CC_SHA256_BLOCK_BYTES)
        
        let out = ByteArray(count: SHA256_SIZE)
        data.withBytes{ dataBytes in
            key.withBytes{ keyBytes in
                out.withMutableBytes { (outBytes: inout [UInt8]) in
                    CCHmac(
                        CCHmacAlgorithm(kCCHmacAlgSHA256),
                        keyBytes, keyBytes.count,
                        dataBytes, dataBytes.count,
                        &outBytes
                    )
                }
            }
        }
        return out
    }
    
    /// Adds PKCS#7 padding to `data` to ensure `mod blockSize` length.
    public static func addPadding(data: ByteArray, blockSize: Int) {
        var padLength = 16 - data.count % blockSize
        if (padLength == 0) {
            padLength = blockSize
        }
        let padding = Array<UInt8>(repeating: UInt8(padLength), count: padLength)
        data.append(bytes: padding)
    }
    
    /// Removes PKCS#7 padding (in-place).
    /// - Throws: `CryptoError.paddingError`
    public static func removePadding(data: ByteArray) throws {
        guard data.count > 0 else {
            throw CryptoError.paddingError(code: 10)
        }
        
        // check if padding is there and (likely) intact
        let padLength = Int(data[data.count - 1])
        guard (data.count - padLength) >= 0 else {
            throw CryptoError.paddingError(code: 20)
        }
        guard padLength > 0 else {
            // no padding or data corrupt
            throw CryptoError.paddingError(code: 30)
        }

        for i in (data.count - padLength)..<data.count {
            if data[i] != padLength {
                throw CryptoError.paddingError(code: 40)
            }
        }
        data.trim(toCount: data.count - padLength)
    }
}