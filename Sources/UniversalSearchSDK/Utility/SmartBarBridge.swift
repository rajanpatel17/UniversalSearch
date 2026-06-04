//
//  DateUtility.swift
//  MintoakBase
//
//  Created by Rajan Patel on 10/12/25.
//

import Foundation
import UIKit

// MARK: - SmartBar Type Definitions

/// Intent category enum - matches SmartBar module
enum IntentCategory: String, Codable {
    case collect = "COLLECT"
    case sales = "SALES"
    case transactions = "TRANSACTIONS"
    case reports = "REPORTS"
    case settlement = "SETTLEMENT"
    case team = "TEAM"
    case rewards = "REWARDS"
    case help = "HELP"
    
    var displayName: String {
        switch self {
        case .collect: return "Collect Payment"
        case .sales: return "Sales"
        case .transactions: return "Transactions"
        case .reports: return "Reports"
        case .settlement: return "Settlement"
        case .team: return "Team"
        case .rewards: return "Rewards"
        case .help: return "Help"
        }
    }
}

/// Action type enum
enum ActionType: String, Codable {
    case navigate
    case showUI
    case download
    case action
}

/// Text segment for parsed suggestions
struct TextSegment: Identifiable {
    let id = UUID()
    let text: String
    let isTag: Bool
    let tagName: String?
    let tagValue: String?
}

/// SmartBar suggestion model
struct SmartBarSuggestion: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let intentId: String
    let category: IntentCategory
    let icon: String
    let score: Double
    let slots: [String: String]
    let isHighlighted: Bool
    
    static func == (lhs: SmartBarSuggestion, rhs: SmartBarSuggestion) -> Bool {
        lhs.id == rhs.id
    }
    
    /// Parse tagged text into attributed segments
    var parsedSegments: [TextSegment] {
        var segments: [TextSegment] = []
        var currentIndex = text.startIndex
        
        let pattern = "\\{([^:]+):([^}]+)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [TextSegment(text: text, isTag: false, tagName: nil, tagValue: nil)]
        }
        
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        
        for match in matches {
            // Add text before this match
            if let range = Range(match.range, in: text), range.lowerBound > currentIndex {
                let beforeText = String(text[currentIndex..<range.lowerBound])
                if !beforeText.isEmpty {
                    segments.append(TextSegment(text: beforeText, isTag: false, tagName: nil, tagValue: nil))
                }
            }
            
            // Add the tag
            if let fullRange = Range(match.range, in: text),
               let nameRange = Range(match.range(at: 1), in: text),
               let valueRange = Range(match.range(at: 2), in: text) {
                let tagName = String(text[nameRange])
                let tagValue = String(text[valueRange])
                segments.append(TextSegment(text: tagValue, isTag: true, tagName: tagName, tagValue: tagValue))
                currentIndex = fullRange.upperBound
            }
        }
        
        // Add remaining text
        if currentIndex < text.endIndex {
            let remainingText = String(text[currentIndex...])
            if !remainingText.isEmpty {
                segments.append(TextSegment(text: remainingText, isTag: false, tagName: nil, tagValue: nil))
            }
        }
        
        return segments.isEmpty ? [TextSegment(text: text, isTag: false, tagName: nil, tagValue: nil)] : segments
    }
}

// MARK: - Intent Definition

struct IntentDefinition {
    let id: String
    let category: IntentCategory
    let triggers: [String: [String]] // language code -> triggers
    let keywords: [String]
    let icon: String
    let defaultSlots: [String: String]
}

// MARK: - SmartBar Bridge

/// Bridge class to integrate SmartBar logic with existing UIKit components
/// Provides fast, offline-first intent detection with multilingual support
class SmartBarBridge {
    
    // MARK: - Singleton
    
    static let shared = SmartBarBridge()
    
    // MARK: - Configuration
    
    /// Minimum query length to trigger suggestions
    private let minQueryLength = 2
    
    /// Confidence threshold for showing suggestions
    private let confidenceThreshold: Double = 0.4
    
    /// Maximum suggestions to return
    private let maxSuggestions = 5
    
    // MARK: - Caching
    
    /// Cache for suggestion results
    private let suggestionCache = NSCache<NSString, NSArray>()
    
    /// Statistics for testing
    struct CacheStats {
        var hits: Int = 0
        var misses: Int = 0
        var totalRequests: Int = 0
        
        var hitRate: Double {
            guard totalRequests > 0 else { return 0 }
            return Double(hits) / Double(totalRequests) * 100
        }
    }
    
    private(set) var stats = CacheStats()
    
    // MARK: - Intent Registry
    
    private let intents: [IntentDefinition] = [
        // Settlement
        IntentDefinition(id: "settle_today", category: .settlement,
            triggers: ["hi": ["aaj ka settlement", "aaj settlement", "settlement aaj"],
                      "en": ["today settlement", "settlement today", "todays settlement", "settlement", "settle", "settelment", "settlment"],
                      "hinglish": ["settlement kitna", "kitna settle hua", "settle dikhao", "settlemen"]],
            keywords: ["settlement", "settle", "paisa", "bank", "settel", "settl"],
            icon: "🏦", defaultSlots: ["date": "today"]),
        
        IntentDefinition(id: "settle_yesterday", category: .settlement,
            triggers: ["hi": ["kal ka settlement", "kal settlement"],
                      "en": ["yesterday settlement", "settlement yesterday", "yesterdays settlement"],
                      "hinglish": ["kal kitna settle hua", "kal settle"]],
            keywords: ["settlement", "settle", "kal", "yesterday"],
            icon: "🏦", defaultSlots: ["date": "yesterday"]),
        
        // Sales
        IntentDefinition(id: "sales_today", category: .sales,
            triggers: ["hi": ["aaj ki sale", "aaj ka bikri", "aaj kitna hua"],
                      "en": ["today sales", "sales today", "todays collection"],
                      "hinglish": ["aaj ka collection", "kitna sale hua aaj"]],
            keywords: ["sale", "sales", "bikri", "collection", "kitna hua"],
            icon: "📊", defaultSlots: ["date": "today"]),
        
        IntentDefinition(id: "sales_yesterday", category: .sales,
            triggers: ["hi": ["kal ki sale", "kal ka bikri"],
                      "en": ["yesterday sales", "sales yesterday"],
                      "hinglish": ["kal ka collection"]],
            keywords: ["sale", "sales", "bikri", "kal", "yesterday"],
            icon: "📊", defaultSlots: ["date": "yesterday"]),
        
        IntentDefinition(id: "payment_breakdown", category: .sales,
            triggers: ["hi": ["payment breakdown", "payment mode wise"],
                      "en": ["payment breakdown", "payment mode analysis"],
                      "hinglish": ["payment wise dikhao", "mode wise breakdown"]],
            keywords: ["breakdown", "payment mode", "analysis", "upi", "card"],
            icon: "📊", defaultSlots: ["type": "payment-breakdown"]),
        
        // Transactions
        IntentDefinition(id: "txn_recent", category: .transactions,
            triggers: ["hi": ["recent transaction", "haal ki transaction"],
                      "en": ["recent transactions", "last transactions", "latest transactions"],
                      "hinglish": ["recent txn", "last 3 transaction"]],
            keywords: ["recent", "last", "latest", "transactions", "txn"],
            icon: "📜", defaultSlots: ["count": "3"]),
        
        IntentDefinition(id: "txn_search_amount", category: .transactions,
            triggers: ["hi": ["rupay wala transaction", "rupay ka payment"],
                      "en": ["transaction for", "payment of", "find transaction"],
                      "hinglish": ["wala txn", "wala transaction"]],
            keywords: ["rupay", "rupees", "transaction", "txn", "payment", "wala"],
            icon: "🔍", defaultSlots: [:]),
        
        // Performance
        IntentDefinition(id: "performance_graph", category: .sales,
            triggers: ["hi": ["performance dikhao", "graph dikhao", "trend dikhao"],
                      "en": ["show performance", "performance graph", "sales trend"],
                      "hinglish": ["performance kaise hai", "graph dikha do"]],
            keywords: ["performance", "graph", "trend", "chart"],
            icon: "📈", defaultSlots: ["type": "performance"]),
        
        // QR
        IntentDefinition(id: "collect_qr", category: .collect,
            triggers: ["hi": ["qr dikhao", "mera qr", "qr code dikhao"],
                      "en": ["show qr", "my qr", "qr code", "display qr"],
                      "hinglish": ["qr dikha do", "apna qr"]],
            keywords: ["qr", "kyuaar"],
            icon: "📲", defaultSlots: [:]),
        
        // Reports
        IntentDefinition(id: "report_download", category: .reports,
            triggers: ["hi": ["report download", "report bhejo"],
                      "en": ["download report", "export report", "get report"],
                      "hinglish": ["report download karo", "report chahiye"]],
            keywords: ["report", "download", "export"],
            icon: "📥", defaultSlots: ["report_type": "transaction"]),
        
        // Help
        IntentDefinition(id: "order_requests", category: .help,
            triggers: ["hi": ["order status", "request status"],
                      "en": ["my orders", "my requests", "order status"],
                      "hinglish": ["order kahan hai", "request ka status"]],
            keywords: ["order", "request", "ticket", "service"],
            icon: "📋", defaultSlots: [:]),
        
        IntentDefinition(id: "help_soundbox", category: .help,
            triggers: ["hi": ["soundbox problem", "soundbox nahi bol raha"],
                      "en": ["soundbox issue", "soundbox not working"],
                      "hinglish": ["soundbox mein problem"]],
            keywords: ["soundbox", "sound box", "awaaz"],
            icon: "🔊", defaultSlots: ["device": "soundbox"]),
        
        IntentDefinition(id: "settings_open", category: .help,
            triggers: ["hi": ["settings khole", "setting mein jao"],
                      "en": ["open settings", "go to settings", "app settings"],
                      "hinglish": ["setting dikhao", "setting kholo"]],
            keywords: ["settings", "setting", "preferences"],
            icon: "⚙️", defaultSlots: [:]),
        
        IntentDefinition(id: "loan_apply", category: .help,
            triggers: ["hi": ["loan chahiye", "loan ke liye apply"],
                      "en": ["apply for loan", "get loan", "loan application"],
                      "hinglish": ["loan apply karna hai"]],
            keywords: ["loan", "apply", "credit"],
            icon: "💳", defaultSlots: [:]),
    ]
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Get suggestions for a query (fast, local-first)
    func getSuggestions(for query: String, completion: @escaping ([SmartBarSuggestion]) -> Void) {
        guard query.count >= minQueryLength else {
            completion([])
            return
        }
        
        let suggestions = getSuggestionsSync(for: query)
        completion(suggestions)
    }
    
    /// Get suggestions synchronously
    func getSuggestionsSync(for query: String) -> [SmartBarSuggestion] {
        let normalized = normalizeQuery(query)
        guard normalized.count >= minQueryLength else { return [] }
        
        let cacheKey = normalized as NSString
        stats.totalRequests += 1
        
        // 1. Check cache
        if let cached = suggestionCache.object(forKey: cacheKey) as? [SmartBarSuggestion] {
            stats.hits += 1
            #if DEBUG
            print("[SmartBar-Cache] HIT: '\(normalized)' (Rate: \(String(format: "%.1f", stats.hitRate))%)")
            #endif
            return cached
        }
        
        // 2. Perform matching
        stats.misses += 1
        #if DEBUG
        print("[SmartBar-Cache] MISS: '\(normalized)'")
        #endif
        
        var matches: [(intent: IntentDefinition, score: Double)] = []
        
        for intent in intents {
            let score = matchScore(normalized, intent: intent)
            if score >= confidenceThreshold {
                matches.append((intent, score))
            }
        }
        
        // Sort by score and take top results
        matches.sort { $0.score > $1.score }
        let topMatches = matches.prefix(maxSuggestions)
        
        let suggestions = topMatches.enumerated().map { index, match in
            createSuggestion(from: match.intent, score: match.score, isHighlighted: index == 0)
        }
        
        // 3. Save to cache
        suggestionCache.setObject(suggestions as NSArray, forKey: cacheKey)
        
        return suggestions
    }
    
    /// Reset cache statistics
    func resetCacheStats() {
        stats = CacheStats()
        suggestionCache.removeAllObjects()
        print("[SmartBar-Cache] Cache and stats reset")
    }
    
    /// Print current cache performance
    func printCacheStats() {
        print("--- SmartBar Cache Stats ---")
        print("Total Requests: \(stats.totalRequests)")
        print("Hits:           \(stats.hits)")
        print("Misses:         \(stats.misses)")
        print("Hit Rate:       \(String(format: "%.1f", stats.hitRate))%")
        print("----------------------------")
    }
    
    /// Map SmartBar intent to existing SearchType
    func mapIntentToSearchType(_ intentId: String) -> SearchType {
        switch intentId {
        case "settle_today", "settle_yesterday", "settle_pending":
            return .settlement
        case "sales_today", "sales_yesterday", "sales_failed", "sales_by_mode", "payment_breakdown":
            return .genUI
        case "txn_search_amount", "txn_search_mobile", "txn_refund", "txn_recent":
            return .recentTransactions
        case "performance_graph":
            return .transactionPerformance
        case "collect_qr", "collect_qr_amount", "collect_link":
            return .deeplink
        case "reward_cashback":
            return .genUI
        case "report_download", "report_settlement":
            return .report
        case "help_soundbox", "help_bank", "help_kyc", "order_requests", "loan_apply", "order_paper_roll", "settings_open":
            return .helpnsupport
        case "team_add":
            return .deeplink
        default:
            return .content
        }
    }
    
    /// Format suggestion for SuggestionCell
    func formatSuggestionForCell(
        _ suggestion: SmartBarSuggestion,
        font: UIFont,
        textColor: UIColor,
        tagColor: UIColor
    ) -> NSAttributedString {
        let attributedText = NSMutableAttributedString()
        
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let tagAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: tagColor,
            .backgroundColor: tagColor.withAlphaComponent(0.15)
        ]
        
        for segment in suggestion.parsedSegments {
            if segment.isTag {
                if attributedText.length > 0, attributedText.string.last != " " {
                    attributedText.append(NSAttributedString(string: " ", attributes: baseAttributes))
                }
                let tagText = " \(segment.text) "
                attributedText.append(NSAttributedString(string: tagText, attributes: tagAttributes))
            } else {
                attributedText.append(NSAttributedString(string: segment.text, attributes: baseAttributes))
            }
        }
        
        return attributedText
    }
    
    /// Get plain text from suggestion
    func plainText(from suggestion: SmartBarSuggestion) -> String {
        return suggestion.parsedSegments.map { $0.text }.joined()
    }
    
    // MARK: - Private Methods
    
    private func normalizeQuery(_ query: String) -> String {
        return query.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "  ", with: " ")
    }
    
    private func matchScore(_ query: String, intent: IntentDefinition) -> Double {
        var maxScore: Double = 0
        let queryWords = query.split(separator: " ").map { String($0) }
        
        // Check triggers across all languages
        for (_, triggers) in intent.triggers {
            for trigger in triggers {
                let triggerNormalized = trigger.lowercased()
                let triggerWords = triggerNormalized.split(separator: " ").map { String($0) }
                
                // Exact match
                if query == triggerNormalized {
                    return 1.0
                }
                
                // Contains match
                if query.contains(triggerNormalized) || triggerNormalized.contains(query) {
                    let score = Double(min(query.count, triggerNormalized.count)) / Double(max(query.count, triggerNormalized.count))
                    maxScore = max(maxScore, score * 0.95)
                }
                
                // Word-level fuzzy matching
                var wordMatchCount = 0
                var fuzzyMatchScore: Double = 0
                
                for queryWord in queryWords {
                    for triggerWord in triggerWords {
                        // Exact word match
                        if queryWord == triggerWord {
                            wordMatchCount += 1
                            fuzzyMatchScore += 1.0
                            break
                        }
                        
                        // Prefix match (e.g., "set" matches "settlement")
                        if triggerWord.hasPrefix(queryWord) && queryWord.count >= 3 {
                            wordMatchCount += 1
                            fuzzyMatchScore += 0.85
                            break
                        }
                        
                        // Fuzzy match using Levenshtein distance
                        let distance = levenshteinDistance(queryWord, triggerWord)
                        let maxLen = max(queryWord.count, triggerWord.count)
                        let similarity = 1.0 - (Double(distance) / Double(maxLen))
                        
                        // Accept if similarity > 70% (allows 1-2 character typos)
                        if similarity > 0.7 {
                            wordMatchCount += 1
                            fuzzyMatchScore += similarity * 0.8
                            break
                        }
                    }
                }
                
                if wordMatchCount > 0 {
                    let avgFuzzyScore = fuzzyMatchScore / Double(max(queryWords.count, triggerWords.count))
                    maxScore = max(maxScore, avgFuzzyScore * 0.9)
                }
            }
        }
        
        // Keyword matching with fuzzy support
        var keywordScore: Double = 0
        for keyword in intent.keywords {
            let keywordLower = keyword.lowercased()
            
            // Direct contain
            if query.contains(keywordLower) {
                keywordScore += 1.0
                continue
            }
            
            // Fuzzy keyword matching
            for queryWord in queryWords {
                // Prefix match
                if keywordLower.hasPrefix(queryWord) && queryWord.count >= 3 {
                    keywordScore += 0.8
                    break
                }
                
                // Levenshtein fuzzy match
                let distance = levenshteinDistance(queryWord, keywordLower)
                let maxLen = max(queryWord.count, keywordLower.count)
                let similarity = 1.0 - (Double(distance) / Double(maxLen))
                
                if similarity > 0.7 {
                    keywordScore += similarity * 0.7
                    break
                }
            }
        }
        
        if keywordScore > 0 {
            let normalizedKeywordScore = min(keywordScore / Double(intent.keywords.count), 1.0) * 0.75
            maxScore = max(maxScore, normalizedKeywordScore)
        }
        
        return maxScore
    }
    
    /// Levenshtein distance for fuzzy matching
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        let m = s1Array.count
        let n = s2Array.count
        
        if m == 0 { return n }
        if n == 0 { return m }
        
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: n + 1), count: m + 1)
        
        for i in 0...m { matrix[i][0] = i }
        for j in 0...n { matrix[0][j] = j }
        
        for i in 1...m {
            for j in 1...n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,      // deletion
                    matrix[i][j - 1] + 1,      // insertion
                    matrix[i - 1][j - 1] + cost // substitution
                )
            }
        }
        
        return matrix[m][n]
    }
    
    private func createSuggestion(from intent: IntentDefinition, score: Double, isHighlighted: Bool) -> SmartBarSuggestion {
        let text = generateSuggestionText(for: intent)
        
        return SmartBarSuggestion(
            text: text,
            intentId: intent.id,
            category: intent.category,
            icon: intent.icon,
            score: score,
            slots: intent.defaultSlots,
            isHighlighted: isHighlighted
        )
    }
    
    private func generateSuggestionText(for intent: IntentDefinition) -> String {
        let dateSlot = intent.defaultSlots["date"] ?? "today"
        
        switch intent.id {
        case "settle_today", "settle_yesterday":
            return "Settlement for {date:\(dateSlot)}"
        case "settle_pending":
            return "{status:Pending} settlement"
        case "sales_today", "sales_yesterday":
            return "Sales for {date:\(dateSlot)}"
        case "payment_breakdown":
            return "Payment {type:breakdown}"
        case "collect_qr":
            return "Show my {type:QR code}"
        case "txn_recent":
            return "Recent {count:3} transactions"
        case "txn_search_amount":
            return "Find transaction by {type:amount}"
        case "performance_graph":
            return "Performance {type:graph}"
        case "order_requests":
            return "My {type:orders and requests}"
        case "report_download":
            return "Download {type:transaction} report"
        case "help_soundbox":
            return "Soundbox {topic:help}"
        case "settings_open":
            return "Open {screen:settings}"
        case "loan_apply":
            return "Apply for {type:loan}"
        default:
            return intent.id.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
