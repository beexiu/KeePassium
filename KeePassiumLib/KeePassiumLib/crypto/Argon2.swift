//
//  Argon2.swift
//  KeePassium
//
//  Created by Andrei Popleteev on 2018-03-20.
//  Copyright © 2018 Andrei Popleteev. All rights reserved.
//

import Foundation

/// Swift wrapper for C-code Argon2 hashing function.
public final class Argon2 {
    public static let version: UInt32 = 0x13
    
    private init() {
        // nothing to do
    }
    
    /// Returns Argon2d hash
    ///
    /// - Parameters:
    ///   - data: data to hash
    ///   - salt: salt array
    ///   - nThreads: requested parallelism
    ///   - m_cost: requested memory (in KiB)
    ///   - t_cost: number of iterations
    ///   - version: algorithm version
    ///   - progress: initialized `Progress` instance to track iterations
    /// - Returns: 32-byte hash array
    /// - Throws: CryptoError.argon2Error, ProgressInterruption
    public static func hash(
        data pwd: ByteArray,
        salt: ByteArray,
        parallelism nThreads: UInt32,
        memoryKiB m_cost: UInt32,
        iterations t_cost: UInt32,
        version: UInt32,
        progress: Progress?
        ) throws -> ByteArray
    {
        // 1. Inside this func, we switch to original Argon2 parameter names for clarity.
        // 2. Argon2 implementation in KeePass2 can take the optional "secret key"
        //    and "associated data" parameters. However, we use the reference implementation
        //    of argon2_hash() which ignores these -- so we ignore them too.

        progress?.totalUnitCount = Int64(t_cost)
        progress?.completedUnitCount = 0
        
        //TODO: ugly nesting, refactor
        var outBytes = [UInt8](repeating: 0, count: 32)
        let statusCode = pwd.withBytes {
            (pwdBytes) in
            return salt.withBytes {
                (saltBytes) -> Int32 in
                guard let progress = progress else {
                    // no progress - no callback
                    return argon2_hash(
                        t_cost, m_cost, nThreads, pwdBytes, pwdBytes.count,
                        saltBytes, saltBytes.count, &outBytes, outBytes.count,
                        nil, 0, Argon2_d, version, nil, nil)
                }
                
                // pointer to the object to pass to the callback
                let progressPtr = UnsafeRawPointer(Unmanaged.passUnretained(progress).toOpaque())
                
                return argon2_hash(
                    t_cost, m_cost, nThreads, pwdBytes, pwdBytes.count,
                    saltBytes, saltBytes.count, &outBytes, outBytes.count,
                    nil, 0, Argon2_d, version,
                    // A closure for updating progress from the C code
                    {
                        (pass: UInt32, observer: Optional<UnsafeRawPointer>) -> Int32 in
                        guard let observer = observer else { return 0 /* continue hashing */ }
                        let progress = Unmanaged<Progress>.fromOpaque(observer).takeUnretainedValue()
                        progress.completedUnitCount = Int64(pass)
                        // print("Argon2 pass: \(pass)")
                        let isShouldStop: Int32 = progress.isCancelled ? 1 : 0
                        return isShouldStop
                    },
                    progressPtr)
            }
        }
        progress?.completedUnitCount = Int64(t_cost) // for consistency
        if progress?.isCancelled ?? false {
            throw ProgressInterruption.cancelledByUser()
        }
        if statusCode != ARGON2_OK.rawValue {
            throw CryptoError.argon2Error(code: Int(statusCode))
        }
        return ByteArray(bytes: outBytes)
    }
}