import Foundation
import Darwin

/// APFS firmlinks are not ordinary symlinks and realpath does not collapse
/// /System/Volumes/Data/Users to /Users. Only accept an alias proven by identity.
public enum DataVolumePaths {
    public static let dataRoot = URL(fileURLWithPath: "/System/Volumes/Data", isDirectory: true)

    public static func alias(of url: URL, dataRoot: URL = DataVolumePaths.dataRoot) -> URL? {
        let original = url.standardizedFileURL
        guard original.isFileURL, dataRoot.isFileURL, !Paths.contains(original, in: dataRoot),
              isUnredirectedExistingPath(original) else { return nil }
        let candidate = dataRoot.appendingPathComponent(String(original.path.dropFirst()))
        guard isUnredirectedExistingPath(candidate), sameObject(original, candidate) else { return nil }
        return candidate
    }

    public static func canonicalHomeItem(_ url: URL, home: URL, dataRoot: URL = DataVolumePaths.dataRoot) -> URL {
        guard let alternateHome = alias(of: home, dataRoot: dataRoot),
              Paths.contains(url, in: alternateHome),
              isUnredirectedExistingPath(url) else { return url }
        let relative = String(url.standardizedFileURL.path.dropFirst(alternateHome.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let canonical = relative.isEmpty ? home : home.appendingPathComponent(relative)
        guard isUnredirectedExistingPath(canonical), sameObject(url, canonical) else { return url }
        return canonical
    }

    /// Foundation collapses legitimate APFS Data firmlinks when resolving
    /// symlinks. Inspect every actual entry instead, requiring an existing leaf
    /// and refusing symbolic links or non-directory ancestors.
    public static func isUnredirectedExistingPath(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let components = Array(url.standardizedFileURL.pathComponents.dropFirst())
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for (index, component) in components.enumerated() {
            current.appendPathComponent(component)
            var metadata = stat()
            guard lstat(current.path, &metadata) == 0, metadata.st_mode & S_IFMT != S_IFLNK else { return false }
            if index < components.count - 1 && metadata.st_mode & S_IFMT != S_IFDIR { return false }
        }
        return true
    }

    /// URL enumeration can emit /Users paths even for a Data-root scan. Keep
    /// the selected lexical root only after proving that both entries are the
    /// same object. A leaf link may be represented as metadata, never followed.
    static func scopedScanEntry(_ emitted: URL, within root: URL, dataRoot: URL = DataVolumePaths.dataRoot) -> URL? {
        guard emitted.isFileURL, root.isFileURL, dataRoot.isFileURL else { return nil }
        // Preserve the enumerator's physical spelling. Foundation can shorten
        // /private/var to /var, which would no longer match the selected prefix.
        let item = emitted
        if Paths.contains(item, in: root) { return item }
        guard Paths.contains(root, in: dataRoot), !Paths.contains(item, in: dataRoot) else { return nil }
        let candidate = dataRoot.appendingPathComponent(String(item.path.dropFirst()))
        guard Paths.contains(candidate, in: root), isUnredirectedExistingPath(root),
              isUnredirectedExistingPath(item.deletingLastPathComponent()),
              isUnredirectedExistingPath(candidate.deletingLastPathComponent()),
              sameObject(item, candidate, allowingSymbolicLeaf: true) else { return nil }
        return candidate
    }

    private static func sameObject(_ lhs: URL, _ rhs: URL, allowingSymbolicLeaf: Bool = false) -> Bool {
        var left = stat(), right = stat()
        return lstat(lhs.path, &left) == 0 && lstat(rhs.path, &right) == 0 &&
            (left.st_mode & S_IFMT) == (right.st_mode & S_IFMT) &&
            (allowingSymbolicLeaf || left.st_mode & S_IFMT != S_IFLNK) &&
            left.st_dev == right.st_dev && left.st_ino == right.st_ino
    }
}
