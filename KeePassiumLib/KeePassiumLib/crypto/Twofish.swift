//
//  Twofish.swift
//  KeePassium
//
//  Created by Andrei Popleteev on 2018-04-09.
//  Copyright © 2018 Andrei Popleteev. All rights reserved.
//

import Foundation

public final class Twofish {
    public static let blockSize = 16
    private var key: SecureByteArray
    private var initVector: SecureByteArray
    private var internalKey: Twofish_key
    
    init(key: ByteArray, iv: ByteArray) {
        precondition(key.count <= 32, "Twofish key must be within 32 bytes")
        precondition(iv.count == Twofish.blockSize, "Twofish expects \(Twofish.blockSize)-byte IV")
        
        self.key = SecureByteArray(key)
        self.initVector = SecureByteArray(iv)
        self.internalKey = Twofish_key()
    }
    
    deinit {
        erase()
    }
    
    public func erase() {
        key.erase()
        initVector.erase()
        Twofish_clear_key(&internalKey)
    }
    
    /// Encrypts `data` bytes in-place.
    /// - Throws: `CryptoError`, `ProgressInterruption`
    func encrypt(data: ByteArray, progress: Progress?) throws  {
        CryptoManager.addPadding(data: data, blockSize: Twofish.blockSize)
        let nBlocks: Int = data.count / Twofish.blockSize
        
        progress?.totalUnitCount = Int64(nBlocks / 100) + 1 // +1 in case there are less than 100 blocks
        progress?.completedUnitCount = 0
        
        let initStatus = Twofish_initialise()
        guard initStatus == 0 else { throw CryptoError.twofishError(code: Int(initStatus)) }
        
        let keyPrepStatus = key.withMutableBytes { (keyBytes: inout [UInt8]) in
            return Twofish_prepare_key(&keyBytes, Int32(keyBytes.count), &internalKey)
        }
        guard keyPrepStatus == 0 else { throw CryptoError.twofishError(code: Int(keyPrepStatus)) }
        
        var outBuffer = [UInt8](repeating: 0, count: Twofish.blockSize)
        var block = [UInt8](repeating: 0, count: Twofish.blockSize)
        var iv = self.initVector.bytesCopy()
        for iBlock in 0..<nBlocks {
            let blockStartPos = iBlock * Twofish.blockSize
            for i in 0..<Twofish.blockSize {
                block[i] = data[blockStartPos + i] ^ iv[i]
            }
            Twofish_encrypt(&internalKey, &block, &outBuffer)
            for i in 0..<Twofish.blockSize {
                iv[i] = outBuffer[i]
                data[blockStartPos + i] = outBuffer[i]
            }
            if (iBlock % 100 == 0) {
                progress?.completedUnitCount += 1
                if progress?.isCancelled ?? false { break }
            }
        }
        Twofish_clear_key(&internalKey)
        progress?.completedUnitCount = progress!.totalUnitCount
        if progress?.isCancelled ?? false {
            throw ProgressInterruption.cancelledByUser()
        }
    }
    
    /// - Throws: `CryptoError`, `ProgressInterruption`
    func decrypt(data: ByteArray, progress: Progress?) throws {
        print("twofish key \(key.asHexString)")
        print("twofish iv \(initVector.asHexString)")
        print("twofish cipher \(data.prefix(32).asHexString)")

        let nBlocks: Int = data.count / Twofish.blockSize
        progress?.totalUnitCount = Int64(nBlocks / 100)
        progress?.completedUnitCount = 0

        let initStatus = Twofish_initialise()
        guard initStatus == 0 else { throw CryptoError.twofishError(code: Int(initStatus)) }
        
        let keyPrepStatus = key.withMutableBytes { (keyBytes: inout [UInt8]) in
            return Twofish_prepare_key(&keyBytes, Int32(keyBytes.count), &internalKey)
        }
        guard keyPrepStatus == 0 else { throw CryptoError.twofishError(code: Int(keyPrepStatus)) }
        
        var iv = self.initVector.bytesCopy()
        data.withMutableBytes { (dataBytes: inout [UInt8]) in
            var block = Array<UInt8>(repeating: 0, count: Twofish.blockSize)
            for iBlock in 0..<nBlocks {
                let blockStartPos = iBlock * Twofish.blockSize
                Twofish_decrypt(&internalKey, &dataBytes + blockStartPos, &block)
                for i in 0..<Twofish.blockSize {
                    block[i] ^= iv[i]
                }
                memcpy(&iv, &dataBytes + blockStartPos, Twofish.blockSize)
                memcpy(&dataBytes + blockStartPos, &block, Twofish.blockSize)
                if (iBlock % 100 == 0) {
                    progress?.completedUnitCount += 1
                    if progress?.isCancelled ?? false { break }
                }
            }
        }
        Twofish_clear_key(&internalKey)
        progress?.completedUnitCount = progress!.totalUnitCount
        if progress?.isCancelled ?? false {
            throw ProgressInterruption.cancelledByUser()
        }
        try CryptoManager.removePadding(data: data) // throws CryptoError
        print("twofish plain \(data.prefix(32).asHexString)")
    }
}