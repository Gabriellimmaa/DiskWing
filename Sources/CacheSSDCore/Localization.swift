import Foundation
private final class ResourceAnchor: NSObject {}

/// Literal keys and interpolation arguments stay separate. File names and paths
/// are arguments, never catalog keys.
public struct LocalizedMessage: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public let key: String
    public let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation value: StringInterpolation) { key = value.key; arguments = value.arguments }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity) }
        public mutating func appendLiteral(_ value: String) { key += value }
        public mutating func appendInterpolation<T>(_ value: T) { key += "%@"; arguments.append(String(describing: value)) }
    }
}

public enum L10n {
    private static let lock = NSLock()
    private static var selected = "system"
    public static var preference: String {
        get { lock.lock(); defer { lock.unlock() }; return selected }
        set { lock.lock(); defer { lock.unlock() }; selected = ["system", "pt-BR", "en"].contains(newValue) ? newValue : "system" }
    }
    public static var isEnglish: Bool {
        let value = preference
        return value == "en" || value == "system" && !(Locale.preferredLanguages.first ?? "en").hasPrefix("pt")
    }
    public static var locale: Locale { Locale(identifier: isEnglish ? "en_US" : "pt_BR") }
    public static var resourceBundle: Bundle? {
        let name = "DiskWing_CacheSSDCore.bundle"
        var candidates: [URL] = []
        let own = Bundle(for: ResourceAnchor.self)
        let roots = [Bundle.main.resourceURL, Bundle.main.bundleURL, own.bundleURL, URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()].compactMap { $0 }
        for root in roots {
            var parent = root
            for _ in 0..<6 {
                candidates.append(parent.appendingPathComponent(name))
                candidates.append(parent.appendingPathComponent("Resources").appendingPathComponent(name))
                parent.deleteLastPathComponent()
            }
        }
        return candidates.compactMap { Bundle(url: $0) }.first
    }
    public static let english: [String: String] = {
        guard let url = resourceBundle?.url(forResource: "en", withExtension: "json"),
              let data = try? Data(contentsOf: url), let values = try? JSONDecoder().decode([String:String].self, from: data) else { return [:] }
        return values
    }()
    public static func text(_ value: LocalizedMessage) -> String {
        let template = isEnglish ? english[value.key] ?? value.key : value.key
        return render(template, arguments: value.arguments)
    }
    private static func render(_ template: String, arguments: [String]) -> String {
        var result = "", remainder = template[...]
        for argument in arguments {
            guard let range = remainder.range(of: "%@") else { break }
            result += remainder[..<range.lowerBound] + argument
            remainder = remainder[range.upperBound...]
        }
        return result + remainder
    }
    /// Only use on application-authored stored messages, never a user file name.
    public static func message(_ value: String) -> String {
        guard isEnglish else { return value }
        if let exact = english[value] { return exact }
        for (pattern, translated) in patterns {
            let range = NSRange(value.startIndex..., in: value)
            guard let match = pattern.firstMatch(in: value, range: range) else { continue }
            let arguments = (1..<match.numberOfRanges).compactMap { Range(match.range(at:$0),in:value).map { String(value[$0]) } }
            return render(translated, arguments: arguments)
        }
        return value
    }
    private static let patterns: [(NSRegularExpression, String)] = english.sorted { $0.key.replacingOccurrences(of:"%@",with:"").count > $1.key.replacingOccurrences(of:"%@",with:"").count }.compactMap { key, translated in
        guard key.contains("%@") else { return nil }
        let expression = key.components(separatedBy: "%@").map(NSRegularExpression.escapedPattern(for:)).joined(separator: "([\\s\\S]*?)")
        guard let regex = try? NSRegularExpression(pattern: "^" + expression + "$") else { return nil }
        return (regex, translated)
    }
}
