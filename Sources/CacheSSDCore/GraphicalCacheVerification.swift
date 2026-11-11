import Foundation
import CryptoKit
import Darwin

public struct GraphicalQuarantineCopyProof: Codable, Sendable {
    public let sourceSHA256: String?
    public let resultSHA256: String?
    public let referenceSHA256: String?
    public let objectType: String
    public var count: Int
    /// Private operational evidence; public validation reports expose hashes only.
    public var sourceValueBase64: String? = nil
    public var resultValueBase64: String? = nil
    public var referenceValueBase64: String? = nil
}
public struct GraphicalCacheVerificationProof: Codable, Sendable {
    public let policyVersion: Int
    public let verifiedEntries: Int
    public let quarantine: [GraphicalQuarantineCopyProof]
}

/// Provider policy 1 keeps the OS copy's opaque quarantine result unchanged.
/// Every other copy-relevant metadata field and every payload byte stays exact.
enum GraphicalCacheVerification {
    private static let callback: copyfile_callback_t = { _, stage, _, _, _, _ in
        stage == COPYFILE_ERR ? COPYFILE_QUIT : COPYFILE_CONTINUE
    }
    static func verify(source: URL, target: URL, sourceAnchor: URL, targetAnchor: URL,
                       expectedSource: GraphicalCacheDirectoryIdentity, expectedTarget: GraphicalCacheDirectoryIdentity,
                       referenceRoot: URL, referenceAnchor: URL, cancellation: CancellationFlag) throws -> GraphicalCacheVerificationProof {
        let input = try GraphicalCacheFiles.openBoundDirectory(source, under: sourceAnchor, expected: expectedSource)
        defer { close(input) }
        let output = try GraphicalCacheFiles.openBoundDirectory(target, under: targetAnchor, expected: expectedTarget)
        defer { close(output) }
        let referenceIdentity = try GraphicalCacheDirectoryIdentity(referenceRoot)
        guard referenceIdentity.device == expectedTarget.device else { throw failure() }
        let reference = try GraphicalCacheFiles.openBoundDirectory(referenceRoot, under: referenceAnchor, expected: referenceIdentity)
        defer { close(reference) }
        var proof = [String: GraphicalQuarantineCopyProof](), count = 0
        func check(_ parts: [String]) throws {
            guard !cancellation.isCancelled else { throw cancelled() }
            let from = try GraphicalCacheFiles.openLeaf(parts, under: input, device: dev_t(expectedSource.device)); defer { close(from) }
            let to = try GraphicalCacheFiles.openLeaf(parts, under: output, device: dev_t(expectedTarget.device)); defer { close(to) }
            var a = stat(), b = stat()
            guard fstat(from, &a) == 0, fstat(to, &b) == 0, a.st_mode & S_IFMT == b.st_mode & S_IFMT else { throw failure() }
            let directory = a.st_mode & S_IFMT == S_IFDIR
            guard directory || a.st_mode & S_IFMT == S_IFREG else { throw failure() }
            guard try FileTree.metadataDigest(descriptor: from, excludingQuarantine: true) == FileTree.metadataDigest(descriptor: to, excludingQuarantine: true) else { debug("other metadata mismatch at " + parts.joined(separator: "/")); throw failure() }
            let sourcePayload = directory ? nil : try hashFile(from, cancellation: cancellation)
            if !directory {
                guard a.st_size == b.st_size, try sourcePayload == hashFile(to, cancellation: cancellation) else { debug("payload mismatch at " + parts.joined(separator: "/")); throw failure() }
            }
            let sourceQ = try quarantine(from)
            var resultQ = try quarantine(to)
            if sourceQ != nil || resultQ != nil {
                guard sourceQ == nil || resultQ != nil else { throw failure() }
                let name = "reference-" + UUID().uuidString
                if directory { guard mkdirat(reference, name, 0o700) == 0 else { throw failure() } }
                let referenceFD = openat(reference, name, O_RDWR | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC | (directory ? O_DIRECTORY : O_CREAT | O_EXCL), 0o600)
                // macOS does not allow O_RDWR directory descriptors.
                let descriptor = directory && referenceFD < 0 ? openat(reference, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) : referenceFD
                guard descriptor >= 0 else { throw failure() }
                defer { close(descriptor); _ = unlinkat(reference, name, directory ? AT_REMOVEDIR : 0) }
                var expectedQ: Data?, matched = false
                // The platform may include copy-time data in its opaque value.
                // Both operations remain standard metadata copies; no EA is edited.
                for _ in 0..<3 {
                    guard !cancellation.isCancelled else { throw cancelled() }
                    try standardMetadataCopy(from: from, to: to)
                    try standardMetadataCopy(from: from, to: descriptor)
                    resultQ = try quarantine(to); expectedQ = try quarantine(descriptor)
                    if resultQ == expectedQ { matched = true; break }
                }
                guard matched else { throw failure() }
                let originalHash: String? = sourceQ.map { hash($0) }
                let resultHash: String? = resultQ.map { hash($0) }
                let expectedHash: String? = expectedQ.map { hash($0) }
                let sourceIsRepresented: Bool = sourceQ == nil || expectedQ != nil
                let opaqueValuesMatch: Bool = expectedQ == resultQ
                guard sourceIsRepresented, opaqueValuesMatch else {
                    let relativePath: String = parts.joined(separator: "/")
                    let details: [String] = [
                        "opaque reference mismatch at " + relativePath,
                        "source=" + (originalHash ?? "none"),
                        "result=" + (resultHash ?? "none"),
                        "reference=" + (expectedHash ?? "none")
                    ]
                    debug(details.joined(separator: " "))
                    throw failure()
                }
                guard sourceQ == nil || resultQ != nil,
                      try FileTree.metadataDigest(descriptor: from, excludingQuarantine: true) == FileTree.metadataDigest(descriptor: to, excludingQuarantine: true) else { throw failure() }
                if let sourcePayload { guard try hashFile(to, cancellation: cancellation) == sourcePayload else { throw failure() } }
                let objectType: String = directory ? "directory" : "file"
                let keyParts: [String] = [objectType, originalHash ?? "none", resultHash ?? "none"]
                let key: String = keyParts.joined(separator: ":")
                if var existing = proof[key] { existing.count += 1; proof[key] = existing }
                else {
                    guard proof.count < 64 else { throw failure() }
                    var entry = GraphicalQuarantineCopyProof(sourceSHA256: originalHash, resultSHA256: resultHash, referenceSHA256: expectedHash, objectType: objectType, count: 1)
                    entry.sourceValueBase64 = sourceQ?.base64EncodedString()
                    entry.resultValueBase64 = resultQ?.base64EncodedString()
                    entry.referenceValueBase64 = expectedQ?.base64EncodedString()
                    proof[key] = entry
                }
            }
            count += 1; guard count <= 1_000_001 else { throw failure() }
        }
        try check([])
        try walk(input, device: dev_t(expectedSource.device), parts: [], cancellation: cancellation) { try check($0) }
        var targetCount = 1
        try walk(output, device: dev_t(expectedTarget.device), parts: [], cancellation: cancellation) { _ in
            targetCount += 1; guard targetCount <= count else { throw failure() }
        }
        guard targetCount == count else { throw failure() }
        return GraphicalCacheVerificationProof(policyVersion: 1, verifiedEntries: count, quarantine: proof.keys.sorted().compactMap { proof[$0] })
    }
    private static func standardMetadataCopy(from: Int32, to: Int32) throws {
        guard let state = copyfile_state_alloc() else { throw failure() }; defer { copyfile_state_free(state) }
        let pointer = unsafeBitCast(callback, to: UnsafeRawPointer.self)
        guard copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), pointer) == 0,
              fcopyfile(from, to, state, copyfile_flags_t(COPYFILE_METADATA)) == 0 else { throw failure() }
    }
    private static func walk(_ descriptor: Int32, device: dev_t, parts: [String], cancellation: CancellationFlag, visit: ([String]) throws -> Void) throws {
        var root = stat()
        guard parts.count <= 80, fstat(descriptor, &root) == 0, root.st_dev == device,
              root.st_mode & S_IFMT == S_IFDIR, root.st_flags & UInt32(SF_DATALESS) == 0,
              let stream = fdopendir(dup(descriptor)) else { throw failure() }; defer { closedir(stream) }
        while true {
            errno = 0
            guard let entry = readdir(stream) else { guard errno == 0 else { throw failure() }; break }
            try autoreleasepool {
                guard !cancellation.isCancelled else { throw cancelled() }
                var tuple = entry.pointee.d_name
                let name = withUnsafeBytes(of: &tuple) { String(cString: $0.baseAddress!.assumingMemoryBound(to: CChar.self)) }
                if name == "." || name == ".." { return }
                guard Paths.safeComponent(name) else { throw failure() }
                var metadata = stat()
                guard fstatat(descriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0, metadata.st_dev == device,
                      metadata.st_flags & UInt32(SF_DATALESS) == 0 else { throw failure() }
                let childParts = parts + [name]; try visit(childParts)
                if metadata.st_mode & S_IFMT == S_IFDIR {
                    let child = openat(descriptor, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                    guard child >= 0 else { throw failure() }; defer { close(child) }
                    try walk(child, device: device, parts: childParts, cancellation: cancellation, visit: visit)
                } else { guard metadata.st_mode & S_IFMT == S_IFREG else { throw failure() } }
            }
        }
    }
    private static func hashFile(_ descriptor: Int32, cancellation: CancellationFlag) throws -> String {
        var before = stat(); guard fstat(descriptor, &before) == 0, before.st_flags & UInt32(SF_DATALESS) == 0 else { throw failure() }
        let copy = dup(descriptor); guard copy >= 0 else { throw failure() }
        let handle = FileHandle(fileDescriptor: copy, closeOnDealloc: true); defer { try? handle.close() }
        _ = lseek(copy, 0, SEEK_SET); var digest = SHA256(), size: Int64 = 0, finished = false
        while !finished {
            try autoreleasepool {
                guard !cancellation.isCancelled else { throw cancelled() }
                guard let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty else { finished = true; return }
                size += Int64(bytes.count); guard size <= before.st_size else { throw failure() }; digest.update(data: bytes)
            }
        }
        var after = stat()
        guard fstat(descriptor, &after) == 0, size == before.st_size, before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec, before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec else { throw failure() }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func quarantine(_ descriptor: Int32) throws -> Data? {
        let count = fgetxattr(descriptor, "com.apple.quarantine", nil, 0, 0, 0)
        if count < 0, errno == ENOATTR { return nil }
        guard count >= 0, count <= 4_096 else { throw failure() }
        var bytes = [UInt8](repeating: 0, count: max(1, count))
        guard fgetxattr(descriptor, "com.apple.quarantine", &bytes, count, 0, 0) == count else { throw failure() }
        return Data(bytes.prefix(count))
    }
    private static func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func debug(_ text: String) {
        if ProcessInfo.processInfo.environment["DISKWING_RUN_GRAPHICAL_NATIVE_TESTS"] == "1", ProcessInfo.processInfo.environment["DISKWING_GRAPHICAL_OBSERVER_DIAGNOSTICS"] == "1" { print("Generated graphical copy: " + text) }
    }
    private static func cancelled() -> Error { CacheSSDError.message("Operação cancelada; origem preservada.") }
    private static func failure() -> Error { CacheSSDError.message("A cópia ou seus metadados não correspondem à política de cópia do macOS. O original foi preservado.") }
}
