import Foundation

/// Raw response from Cursor usage endpoints.
///
/// Cursor's dashboard API is not a public contract, so the parser intentionally
/// accepts a few shapes:
/// - a `limits` / `bars` array with generic kind + percent fields;
/// - nested objects named like `first_party_models`, `api`, `on_demand`;
/// - spend-style objects with `used` / `limit` rather than a direct percent.
struct UsageResponse: Decodable {
    let bars: [BarSpec]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(JSONValue.self)
        bars = UsageMapper.bars(from: raw.objectValue ?? [:])
    }
}

enum JSONValue: Decodable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .null
        }
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var stringValue: String? {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value { return String(Int(value)) }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object, .array, .null:
            return nil
        }
    }

    var numberValue: Double? {
        switch self {
        case .number(let value):
            return value
        case .string(let value):
            return Double(value.replacingOccurrences(of: ",", with: "."))
        case .object, .array, .bool, .null:
            return nil
        }
    }
}

// MARK: - View model

/// One rendered bar with everything the icon, tooltip, and menu need.
struct BarSpec {
    let kind: String
    let label: String
    let letter: String
    let percent: Double
    let severity: String
    let resetsAt: Date?
    let valueText: String?

    /// True when this bucket is actually exhausted, not merely warning.
    var isBlocking: Bool {
        if percent >= 100 { return true }
        switch severity.lowercased() {
        case "exceeded", "over_limit", "overlimit", "blocked", "exhausted", "limit_reached", "limited":
            return true
        default:
            return false
        }
    }
}

enum UsageMapper {
    private struct Bucket {
        let kind: String
        let label: String
        let letter: String
        let objectNames: [String]
        let kindNames: [String]
    }

    private static let buckets: [Bucket] = [
        Bucket(
            kind: "first_party_models",
            label: "First-party models",
            letter: "f",
            objectNames: ["first_party_models", "firstPartyModels", "first_party", "firstParty", "included_models", "includedModels"],
            kindNames: ["first_party_models", "firstpartymodels", "first_party", "firstparty", "models", "included_models"]
        ),
        Bucket(
            kind: "api",
            label: "API",
            letter: "a",
            objectNames: ["api", "api_usage", "apiUsage", "api_quota", "apiQuota"],
            kindNames: ["api", "api_usage", "apiusage", "api_quota"]
        ),
        Bucket(
            kind: "on_demand",
            label: "On-demand",
            letter: "o",
            objectNames: ["on_demand", "onDemand", "on_demand_spend", "onDemandSpend", "usage_based_pricing", "usageBasedPricing", "spend"],
            kindNames: ["on_demand", "ondemand", "on_demand_spend", "usage_based_pricing", "spend"]
        ),
    ]

    static func bars(from root: [String: JSONValue]) -> [BarSpec] {
        if let dashboard = barsFromDashboardUsage(root), dashboard.count == 3 {
            return dashboard
        }

        let generic = barsFromGenericArrays(root)
        if generic.count >= 3 {
            return ordered(generic)
        }

        var result = generic
        for bucket in buckets where !result.contains(where: { $0.kind == bucket.kind }) {
            if let object = findObject(namedAnyOf: bucket.objectNames, in: .object(root)),
               let bar = bar(for: bucket, object: object) {
                result.append(bar)
            }
        }

        return ordered(result)
    }

    static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        if let millis = Double(s), millis > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: millis / 1000)
        }
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    private static func barsFromDashboardUsage(_ root: [String: JSONValue]) -> [BarSpec]? {
        guard let planUsage = value(for: "planUsage", in: root)?.objectValue else { return nil }
        let reset = parseDate(firstString(["billingCycleEnd", "currentPeriodEnd", "periodEnd"], in: root))

        let firstParty = firstNumber(["autoPercentUsed", "auto_percent_used"], in: planUsage) ?? 0
        let api = firstNumber(["apiPercentUsed", "api_percent_used"], in: planUsage) ?? 0

        var onDemandUsed = 0.0
        var onDemandLimit = 0.0
        var limitType = "user"
        if let spend = value(for: "spendLimitUsage", in: root)?.objectValue {
            limitType = firstString(["limitType", "limit_type"], in: spend) ?? "user"
            if limitType == "team" {
                onDemandUsed = firstNumber(["pooledUsed", "pooled_used", "totalSpend"], in: spend) ?? 0
                onDemandLimit = firstNumber(["pooledLimit", "pooled_limit"], in: spend) ?? 0
            } else {
                onDemandUsed = firstNumber(["individualUsed", "individual_used", "totalSpend"], in: spend) ?? 0
                onDemandLimit = firstNumber(["individualLimit", "individual_limit"], in: spend) ?? 0
            }
        }
        let onDemandPercent = onDemandLimit > 0 ? (onDemandUsed / onDemandLimit) * 100 : 0

        return [
            BarSpec(
                kind: "first_party_models",
                label: "First-party models",
                letter: "f",
                percent: max(0, min(100, firstParty)),
                severity: severity(for: firstParty),
                resetsAt: reset,
                valueText: nil
            ),
            BarSpec(
                kind: "api",
                label: "API",
                letter: "a",
                percent: max(0, min(100, api)),
                severity: severity(for: api),
                resetsAt: reset,
                valueText: nil
            ),
            BarSpec(
                kind: "on_demand",
                label: "On-demand",
                letter: "o",
                percent: max(0, min(100, onDemandPercent)),
                severity: severity(for: onDemandPercent),
                resetsAt: reset,
                valueText: "\(formatCents(onDemandUsed)) / \(formatCents(onDemandLimit))"
            ),
        ]
    }

    private static func barsFromGenericArrays(_ root: [String: JSONValue]) -> [BarSpec] {
        for key in ["limits", "bars", "usage", "quotas", "items"] {
            if let array = value(for: key, in: root)?.arrayValue {
                let bars = array.compactMap { value -> BarSpec? in
                    guard let object = value.objectValue else { return nil }
                    return barFromGenericObject(object)
                }
                if !bars.isEmpty { return bars }
            }
        }
        return []
    }

    private static func barFromGenericObject(_ object: [String: JSONValue]) -> BarSpec? {
        let rawKind = firstString(["kind", "type", "name", "id", "scope"], in: object) ?? ""
        guard let bucket = bucket(for: rawKind) else { return nil }
        return bar(for: bucket, object: object)
    }

    private static func bar(for bucket: Bucket, object: [String: JSONValue]) -> BarSpec? {
        guard let percent = percent(in: object) else { return nil }
        let label = firstString(["label", "title", "display_name", "displayName"], in: object) ?? bucket.label
        let severity = firstString(["severity", "state", "status"], in: object) ?? severity(for: percent)
        let reset = firstString(["resets_at", "resetsAt", "reset_at", "resetAt", "resetTime", "periodEnd", "currentPeriodEnd"], in: object)
        let valueText = detailsText(for: bucket, object: object)

        return BarSpec(
            kind: bucket.kind,
            label: label,
            letter: bucket.letter,
            percent: max(0, min(100, percent)),
            severity: severity,
            resetsAt: parseDate(reset),
            valueText: valueText
        )
    }

    private static func percent(in object: [String: JSONValue]) -> Double? {
        if let direct = firstNumber([
            "percent", "percentage", "used_percent", "usedPercent",
            "usage_percent", "usagePercent", "used_percentage", "usedPercentage"
        ], in: object) {
            return direct
        }

        if let ratio = firstNumber(["ratio", "usageRatio", "usedRatio", "utilization", "utilisation"], in: object) {
            return normalizePercent(ratio)
        }

        let used = firstNumber(["used", "usage", "consumed", "spent", "current", "amount", "value"], in: object)
        let limit = firstNumber(["limit", "quota", "max", "total", "included", "monthlyLimit", "monthly_limit"], in: object)
        if let used, let limit, limit > 0 {
            return normalizePercent(used / limit)
        }
        return nil
    }

    private static func detailsText(for bucket: Bucket, object: [String: JSONValue]) -> String? {
        let used = firstNumber(["used", "usage", "consumed", "spent", "current", "amount"], in: object)
        let limit = firstNumber(["limit", "quota", "max", "total", "included", "monthlyLimit", "monthly_limit"], in: object)
        guard let used, let limit else {
            return firstString(["text", "details", "subtitle", "description"], in: object)
        }

        if bucket.kind == "on_demand" || hasCurrency(in: object) {
            return "\(formatMoney(used, in: object)) / \(formatMoney(limit, in: object))"
        }
        return "\(formatNumber(used)) / \(formatNumber(limit))"
    }

    private static func hasCurrency(in object: [String: JSONValue]) -> Bool {
        firstString(["currency", "currencyCode"], in: object) != nil ||
        object.keys.map(normalize).contains { $0.contains("spend") || $0.contains("cost") || $0.contains("money") }
    }

    private static func formatMoney(_ value: Double, in object: [String: JSONValue]) -> String {
        let currency = firstString(["currency", "currencyCode"], in: object)?.uppercased() ?? "USD"
        let symbol = currency == "USD" ? "$" : "\(currency) "
        let normalized = object.keys.map(normalize).contains(where: { $0.contains("cents") }) ? value / 100 : value
        return symbol + formatNumber(normalized)
    }

    private static func formatCents(_ value: Double) -> String {
        "$" + formatNumber(value / 100)
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.2f", value)
    }

    private static func normalizePercent(_ value: Double) -> Double {
        if value >= 0 && value <= 1 { return value * 100 }
        return value
    }

    private static func severity(for percent: Double) -> String {
        if percent >= 95 { return "critical" }
        if percent >= 80 { return "warning" }
        return "normal"
    }

    private static func ordered(_ bars: [BarSpec]) -> [BarSpec] {
        bars.sorted { a, b in
            (buckets.firstIndex { $0.kind == a.kind } ?? 99) < (buckets.firstIndex { $0.kind == b.kind } ?? 99)
        }
    }

    private static func bucket(for raw: String) -> Bucket? {
        let key = normalize(raw)
        return buckets.first { bucket in
            bucket.kindNames.map(normalize).contains(key) || bucket.kindNames.map(normalize).contains { key.contains($0) }
        }
    }

    private static func findObject(namedAnyOf names: [String], in value: JSONValue) -> [String: JSONValue]? {
        let wanted = Set(names.map(normalize))
        switch value {
        case .object(let object):
            for (key, child) in object where wanted.contains(normalize(key)) {
                if let found = child.objectValue { return found }
            }
            for child in object.values {
                if let found = findObject(namedAnyOf: names, in: child) { return found }
            }
        case .array(let array):
            for child in array {
                if let found = findObject(namedAnyOf: names, in: child) { return found }
            }
        case .string, .number, .bool, .null:
            return nil
        }
        return nil
    }

    private static func value(for key: String, in object: [String: JSONValue]) -> JSONValue? {
        let wanted = normalize(key)
        return object.first { normalize($0.key) == wanted }?.value
    }

    private static func firstString(_ keys: [String], in object: [String: JSONValue]) -> String? {
        for key in keys {
            if let value = value(for: key, in: object)?.stringValue,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func firstNumber(_ keys: [String], in object: [String: JSONValue]) -> Double? {
        for key in keys {
            if let value = value(for: key, in: object)?.numberValue {
                return value
            }
        }
        return nil
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
