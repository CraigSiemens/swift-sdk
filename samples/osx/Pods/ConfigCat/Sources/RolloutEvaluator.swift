import Foundation
import CommonCrypto
import os.log

class RolloutEvaluator {
    fileprivate static let log: OSLog = OSLog(subsystem: Bundle(for: RolloutEvaluator.self).bundleIdentifier!, category: "Rollout Evaluator")
    fileprivate static let comparatorTexts = [
        "IS ONE OF",
        "IS NOT ONE OF",
        "CONTAINS",
        "DOES NOT CONTAIN",
        "IS ONE OF (SemVer)",
        "IS NOT ONE OF (SemVer)",
        "< (SemVer)",
        "<= (SemVer)",
        "> (SemVer)",
        ">= (SemVer)",
        "= (Number)",
        "<> (Number)",
        "< (Number)",
        "<= (Number)",
        "> (Number)",
        ">= (Number",
    ]

    func evaluate<Value>(json: Any?, key: String, user: User?) -> Value? {
        guard let json = json as? [String: Any] else {
            return nil
        }
                
        let rolloutRules = json[Config.rolloutRules] as? [[String: Any]] ?? []
        let rolloutPercentageItems = json[Config.rolloutPercentageItems] as? [[String: Any]] ?? []
        
        guard let user = user else {
            if rolloutRules.count > 0 || rolloutPercentageItems.count > 0 {
                os_log(
                    """
                    Evaluating get_value(%@). UserObject missing!
                    You should pass a UserObject to get_value(),
                    in order to make targeting work properly.
                    Read more: https://configcat.com/docs/advanced/user-object/
                    """,
                    log: .default, type: .default, key)
            }
            
            return json[Config.value] as? Value
        }
                
        for rule in rolloutRules {
            if let comparisonAttribute = rule[Config.comparisonAttribute] as? String,
                let comparisonValue = rule[Config.comparisonValue] as? String,
                let comparator = rule[Config.comparator] as? Int,
                let userValue = user.getAttribute(for: comparisonAttribute) {
                
                if comparisonValue.isEmpty || userValue.isEmpty {
                    os_log("%@", log: .default, type: .info,
                           formatNoMatchRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue))
                    continue
                }
                
                switch comparator {
                // IS ONE OF
                case 0:
                    let splitted = comparisonValue.components(separatedBy: ",")
                        .map {val in val.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)}
                    
                    if splitted.contains(userValue) {
                        os_log("%@", log: .default, type: .info,
                               formatMatchRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                               value: rule[Config.value] as? String ?? ""))
                        return rule[Config.value] as? Value
                    }
                // IS NOT ONE OF
                case 1:
                    let splitted = comparisonValue.components(separatedBy: ",")
                        .map {val in val.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)}
                    
                    if !splitted.contains(userValue) {
                        os_log("%@", log: .default, type: .info,
                               formatMatchRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                               value: rule[Config.value] as? String ?? ""))
                        return rule[Config.value] as? Value
                    }
                // CONTAINS
                case 2:
                    if userValue.contains(comparisonValue) {
                        os_log("%@", log: .default, type: .info,
                               formatMatchRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                               value: rule[Config.value] as? String ?? ""))
                        return rule[Config.value] as? Value
                    }
                // DOES NOT CONTAIN
                case 3:
                    if !userValue.contains(comparisonValue) {
                        os_log("%@", log: .default, type: .info,
                               formatMatchRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                               value: rule[Config.value] as? String ?? ""))
                        return rule[Config.value] as? Value
                    }
                // IS ONE OF (Semantic version), IS NOT ONE OF (Semantic version)
                case 4...5:
                    let splitted = comparisonValue.components(separatedBy: ",")
                        .map {val in val.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)}
                        .filter {val -> Bool in return !val.isEmpty}
                                        
                    // The rule will be ignored if we found an invalid semantic version
                    if let invalidValue = (splitted.first {val -> Bool in Version(val) == nil}) {
                        os_log("%@", log: .default, type: .error,
                               formatValidationErrorRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                                         error: "Invalid semantic version: \(invalidValue)"))
                        continue
                    }
                    if Version(userValue) == nil {
                        os_log("%@", log: .default, type: .error,
                               formatValidationErrorRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                                         error: "Invalid semantic version: \(userValue)"))
                        continue
                    }
                                        
                    if comparator == 4 { // IS ONE OF
                        if Version(userValue) == nil {
                            os_log("%@", log: .default, type: .error,
                                   formatValidationErrorRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                                             error: "Invalid semantic version: \(userValue)"))
                            continue
                        }
                        
                        if let userValueVersion = Version(userValue) {
                            if (splitted.first {val -> Bool in userValueVersion.isEqualWithoutMetadata(Version(val))} != nil) {
                                os_log("%@", log: .default, type: .info,
                                       formatMatchRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                                       value: rule[Config.value] as? String ?? ""))
                                return rule[Config.value] as? Value
                            }
                        }
                    } else { // IS NOT ONE OF
                        if Version(userValue) == nil {
                            os_log("%@", log: .default, type: .error,
                                   formatValidationErrorRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                                             error: "Invalid semantic version: \(userValue)"))
                            continue
                        }
                        
                        if let userValueVersion = Version(userValue) {
                            if let invalidValue = (splitted.first {val -> Bool in userValueVersion.isEqualWithoutMetadata(Version(val))}) {
                                os_log("%@", log: .default, type: .error,
                                       formatValidationErrorRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                                                 error: "Invalid semantic version: \(invalidValue)"))
                                continue
                            }

                            os_log("%@", log: .default, type: .info,
                                   formatMatchRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                                   value: rule[Config.value] as? String ?? ""))
                            return rule[Config.value] as? Value
                        }
                    }
                // LESS THAN, LESS THAN OR EQUALS TO, GREATER THAN, GREATER THAN OR EQUALS TO (Semantic version)
                case 6...9:
                    let comparison = comparisonValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    if Version(userValue) == nil {
                        os_log("%@", log: .default, type: .error,
                               formatValidationErrorRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                                         error: "Invalid semantic version: \(userValue)"))
                        continue
                    }
                    
                    if Version(comparison) == nil {
                        os_log("%@", log: .default, type: .error,
                               formatValidationErrorRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                                         error: "Invalid semantic version: \(comparison)"))
                        continue
                    }
                    if let userValueVersion = Version(userValue),
                        let comparisonValueVersion = Version(comparison) {
                        let userValueVersionWithoutMetadata = Version(major: userValueVersion.major,
                                                                      minor: userValueVersion.minor,
                                                                      patch: userValueVersion.patch,
                                                                      prereleaseIdentifiers: userValueVersion.prereleaseIdentifiers)
                        let comparisonValueVersionWithoutMetadata = Version(major: comparisonValueVersion.major,
                                                                            minor: comparisonValueVersion.minor,
                                                                            patch: comparisonValueVersion.patch,
                                                                            prereleaseIdentifiers: comparisonValueVersion.prereleaseIdentifiers)
                        if (comparator == 6 && userValueVersionWithoutMetadata < comparisonValueVersionWithoutMetadata)
                            || (comparator == 7 && userValueVersionWithoutMetadata <= comparisonValueVersionWithoutMetadata)
                            || (comparator == 8 && userValueVersionWithoutMetadata > comparisonValueVersionWithoutMetadata)
                            || (comparator == 9 && userValueVersionWithoutMetadata >= comparisonValueVersionWithoutMetadata) {
                            os_log("%@", log: .default, type: .info,
                                   formatMatchRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                                   value: rule[Config.value] as? String ?? ""))
                            return rule[Config.value] as? Value
                        }
                    }
                case 10...15:
                    if let userValueFloat = Float(userValue.replacingOccurrences(of: ",", with: ".")),
                        let comparisonValueFloat = Float(comparisonValue.replacingOccurrences(of: ",", with: ".")) {
                        if (comparator == 10 && userValueFloat == comparisonValueFloat)
                            || (comparator == 11 && userValueFloat != comparisonValueFloat)
                            || (comparator == 12 && userValueFloat < comparisonValueFloat)
                            || (comparator == 13 && userValueFloat <= comparisonValueFloat)
                            || (comparator == 14 && userValueFloat > comparisonValueFloat)
                            || (comparator == 15 && userValueFloat >= comparisonValueFloat) {
                            os_log("%@", log: .default, type: .info,
                                   formatMatchRule(comparisonAttribute: comparisonAttribute, userValue: userValue, comparator: comparator, comparisonValue: comparisonValue,
                                                   value: rule[Config.value] as? String ?? ""))
                            return rule[Config.value] as? Value
                        }
                    }
                default:
                    continue
                }
            }
        }

        if (rolloutPercentageItems.count > 0){
            let hashCandidate = key + user.identifier
            if let hash = hashCandidate.sha1hex?.prefix(7) {
                let hashString = String(hash)
                if let num = Int(hashString, radix: 16) {
                    let scaled = num % 100
                    
                    var bucket = 0
                    for rule in rolloutPercentageItems {
                        if let percentage = rule[Config.percentage] as? Int {
                            bucket += percentage
                            if scaled < bucket {
                                os_log("Evaluating %% options. Returning %@", log: .default, type: .info, rule[Config.value] as? String ?? "")
                                return rule[Config.value] as? Value
                            }
                        }
                    }
                }
            }
        }

        os_log("Returning %@", log: .default, type: .info, json[Config.value] as? String ?? "")
        return json[Config.value] as? Value
    }
    
    private func formatMatchRule(comparisonAttribute: String, userValue: String, comparator: Int, comparisonValue: String, value: String) -> String {
        return String(format: "Evaluating rule: [%@:%@] [%@] [%@] => match, returning: %@",
                      comparisonAttribute, userValue, RolloutEvaluator.comparatorTexts[comparator], comparisonValue, value)
    }
    
    private func formatNoMatchRule(comparisonAttribute: String, userValue: String, comparator: Int, comparisonValue: String) -> String {
        return String(format: "Evaluating rule: [%@:%@] [%@] [%@] => no match",
                      comparisonAttribute, userValue, RolloutEvaluator.comparatorTexts[comparator], comparisonValue)
    }
    
    private func formatValidationErrorRule(comparisonAttribute: String, userValue: String, comparator: Int, comparisonValue: String, error: String) -> String {
        return String(format: "Evaluating rule: [%@:%@] [%@] [%@] => SKIP rule. Validation error: %@",
                      comparisonAttribute, userValue, RolloutEvaluator.comparatorTexts[comparator], comparisonValue, error)
    }
}

fileprivate extension String {
    var sha1hex: String? {
        if let utf8Data = data(using: .utf8, allowLossyConversion: false) {
            return utf8Data.digestSHA1.hexString
        }
        return nil
    }
}

fileprivate extension Data {
    var digestSHA1: Data {
        var bytes: [UInt8] = Array(repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        withUnsafeBytes {
            _ = CC_SHA1($0, CC_LONG(count), &bytes)
        }
        return Data(bytes: bytes)
    }
    
    var hexString: String {
        return map { String(format: "%02x", UInt8($0)) }.joined()
    }
}

fileprivate extension Version {
    func isEqualWithoutMetadata(_ other: Version?) -> Bool {
        if let other = other {
            return major == other.major && minor == other.minor && patch == other.patch
                && prereleaseIdentifiers == other.prereleaseIdentifiers
        }
        return false
    }
}