enum ProviderRegistry {
    static func defaultProviders() -> [any UsageProvider] {
        [
            ClaudeUsageProvider(),
            ChatGPTUsageProvider(),
        ]
    }
}
