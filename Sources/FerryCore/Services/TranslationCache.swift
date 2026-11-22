import Foundation

/// Canonical cache key identifying a unique translation or writing-refinement request.
///
/// Two requests share a key if and only if they produce the exact same LLM prompt/payload
/// against the same provider, endpoint, and model (e.g., `.auto` resolving to `.zhCN` matches
/// an explicit `.zhCN` request for the same text).
public struct TranslationCacheKey: Codable, Hashable, Sendable {
    public let sourceText: String
    /// Effective target language (`nil` when a writing mode preserves the source language).
    public let resolvedTarget: TargetLanguage?
    public let mode: TranslationMode
    public let provider: ProviderKind
    public let model: String
    public let endpoint: String
    /// Whether the dictionary lookup prompt is active for this request.
    public let wordLookup: Bool

    public init(
        sourceText: String,
        resolvedTarget: TargetLanguage?,
        mode: TranslationMode,
        provider: ProviderKind,
        model: String,
        endpoint: String,
        wordLookup: Bool
    ) {
        self.sourceText = sourceText
        self.resolvedTarget = resolvedTarget
        self.mode = mode
        self.provider = provider
        self.model = model
        self.endpoint = endpoint
        self.wordLookup = wordLookup
    }

    private enum CodingKeys: String, CodingKey {
        case sourceText, resolvedTarget, mode, provider, model, endpoint, wordLookup
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceText = try c.decode(String.self, forKey: .sourceText)
        resolvedTarget = try c.decodeIfPresent(TargetLanguage.self, forKey: .resolvedTarget)
        mode = try c.decodeIfPresent(TranslationMode.self, forKey: .mode) ?? .translate
        provider = try c.decode(ProviderKind.self, forKey: .provider)
        model = try c.decode(String.self, forKey: .model)
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint) ?? provider.defaultBaseURL
        wordLookup = try c.decodeIfPresent(Bool.self, forKey: .wordLookup) ?? false
    }

    /// Builds a canonical key matching `LLMTranslatorService.makePayload(...)`.
    public static func make(
        text: String,
        targetLanguage: TargetLanguage,
        config: TranslationRequestConfig
    ) -> TranslationCacheKey {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTarget: TargetLanguage? = config.mode.preservesSourceLanguage(for: targetLanguage)
            ? nil
            : targetLanguage.resolvedTarget(for: trimmed)
        let effectiveModel = config.profile.effectiveModel
        let endpoint = config.profile.normalizedBaseURL ?? config.provider.defaultBaseURL
        let effectiveWordLookup = config.mode == .translate
            && config.wordLookup
            && !LLMTranslatorService.isDedicatedTranslationModel(effectiveModel)
            && TranslationPrompt.isLookupTerm(trimmed)

        return TranslationCacheKey(
            sourceText: trimmed,
            resolvedTarget: resolvedTarget,
            mode: config.mode,
            provider: config.provider,
            model: effectiveModel,
            endpoint: endpoint,
            wordLookup: effectiveWordLookup
        )
    }
}

/// Single persisted entry stored inside `TranslationLRUCache`.
public struct TranslationCacheEntry: Codable, Equatable, Sendable {
    public let key: TranslationCacheKey
    public let translatedText: String
    public let updatedAt: Date

    public init(key: TranslationCacheKey, translatedText: String, updatedAt: Date = Date()) {
        self.key = key
        self.translatedText = translatedText
        self.updatedAt = updatedAt
    }
}

/// Pure Swift O(1) Least-Recently-Used (LRU) cache for translation results.
///
/// Backed by an index-based doubly-linked list and hash map so lookups, updates,
/// promotions, and evictions all run in O(1) time with value semantics and zero retain cycles.
public struct TranslationLRUCache: Sendable {
    public static let defaultCapacity = 500
    /// Skip caching excessively long texts so disk persistence stays fast and lightweight.
    public static let maxCacheableTextLength = 16_000

    private struct Node: Sendable {
        var entry: TranslationCacheEntry
        var prev: Int?
        var next: Int?
    }

    public let capacity: Int
    public private(set) var hitCount: Int = 0

    private var nodes: [Node] = []
    private var freeIndices: [Int] = []
    private var indexByKey: [TranslationCacheKey: Int] = [:]
    private var head: Int? // Most recently used
    private var tail: Int? // Least recently used

    public init(capacity: Int = TranslationLRUCache.defaultCapacity) {
        self.capacity = max(0, capacity)
    }

    public var count: Int {
        indexByKey.count
    }

    public var isEmpty: Bool {
        indexByKey.isEmpty
    }

    /// Looks up a cached translation, promoting it to most-recently-used on hit.
    public mutating func get(_ key: TranslationCacheKey) -> TranslationCacheEntry? {
        guard let index = indexByKey[key] else { return nil }
        moveToHead(index)
        hitCount += 1
        return nodes[index].entry
    }

    /// Looks up a cached translation without changing LRU order or hit count.
    public func peek(_ key: TranslationCacheKey) -> TranslationCacheEntry? {
        guard let index = indexByKey[key] else { return nil }
        return nodes[index].entry
    }

    /// Inserts or updates a cached translation and promotes it to most-recently-used.
    /// Evicts the least-recently-used entry when capacity is exceeded.
    public mutating func set(_ translatedText: String, for key: TranslationCacheKey, now: Date = Date()) {
        let trimmedOutput = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard capacity > 0,
              !key.sourceText.isEmpty,
              !trimmedOutput.isEmpty,
              key.sourceText.count <= Self.maxCacheableTextLength,
              trimmedOutput.count <= Self.maxCacheableTextLength
        else {
            return
        }

        let entry = TranslationCacheEntry(key: key, translatedText: trimmedOutput, updatedAt: now)

        if let existingIndex = indexByKey[key] {
            nodes[existingIndex].entry = entry
            moveToHead(existingIndex)
            return
        }

        let newIndex = allocateNode(entry: entry)
        indexByKey[key] = newIndex
        attachToHead(newIndex)

        if indexByKey.count > capacity {
            evictTail()
        }
    }

    /// Removes a specific key from the cache, returning its entry if present.
    @discardableResult
    public mutating func remove(_ key: TranslationCacheKey) -> TranslationCacheEntry? {
        guard let index = indexByKey.removeValue(forKey: key) else { return nil }
        let entry = nodes[index].entry
        detach(index)
        freeIndices.append(index)
        return entry
    }

    /// Empties the cache and resets session hit statistics.
    public mutating func clear() {
        nodes.removeAll()
        freeIndices.removeAll()
        indexByKey.removeAll()
        head = nil
        tail = nil
        hitCount = 0
    }

    /// Returns all cached entries ordered from most-recently-used to least-recently-used.
    public func orderedEntries() -> [TranslationCacheEntry] {
        var result: [TranslationCacheEntry] = []
        result.reserveCapacity(indexByKey.count)
        var current = head
        while let idx = current {
            result.append(nodes[idx].entry)
            current = nodes[idx].next
        }
        return result
    }

    /// Replaces the cache contents with persisted entries (expected in MRU-to-LRU order).
    public mutating func load(entries: [TranslationCacheEntry]) {
        clear()
        guard capacity > 0 else { return }

        var inserted = 0
        for entry in entries {
            guard inserted < capacity else { break }
            guard !entry.key.sourceText.isEmpty,
                  !entry.translatedText.isEmpty,
                  entry.key.sourceText.count <= Self.maxCacheableTextLength,
                  entry.translatedText.count <= Self.maxCacheableTextLength,
                  indexByKey[entry.key] == nil
            else {
                continue
            }
            let idx = allocateNode(entry: entry)
            indexByKey[entry.key] = idx
            attachToTail(idx)
            inserted += 1
        }
    }

    // MARK: - Doubly-Linked List Operations

    private mutating func allocateNode(entry: TranslationCacheEntry) -> Int {
        if let reused = freeIndices.popLast() {
            nodes[reused] = Node(entry: entry, prev: nil, next: nil)
            return reused
        }
        nodes.append(Node(entry: entry, prev: nil, next: nil))
        return nodes.count - 1
    }

    private mutating func moveToHead(_ index: Int) {
        guard head != index else { return }
        detach(index)
        attachToHead(index)
    }

    private mutating func detach(_ index: Int) {
        let prevIndex = nodes[index].prev
        let nextIndex = nodes[index].next

        if let prevIndex {
            nodes[prevIndex].next = nextIndex
        } else {
            head = nextIndex
        }

        if let nextIndex {
            nodes[nextIndex].prev = prevIndex
        } else {
            tail = prevIndex
        }

        nodes[index].prev = nil
        nodes[index].next = nil
    }

    private mutating func attachToHead(_ index: Int) {
        nodes[index].prev = nil
        nodes[index].next = head
        if let oldHead = head {
            nodes[oldHead].prev = index
        } else {
            tail = index
        }
        head = index
    }

    private mutating func attachToTail(_ index: Int) {
        nodes[index].next = nil
        nodes[index].prev = tail
        if let oldTail = tail {
            nodes[oldTail].next = index
        } else {
            head = index
        }
        tail = index
    }

    private mutating func evictTail() {
        guard let lruIndex = tail else { return }
        let key = nodes[lruIndex].entry.key
        detach(lruIndex)
        indexByKey.removeValue(forKey: key)
        freeIndices.append(lruIndex)
    }
}
