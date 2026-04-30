import Foundation

/// Wraps the two error families the poller can produce so `UsageStore` /
/// `UsagePopover` can render them uniformly.
enum AppError: Error {
    case tokenRead(TokenReader.ReadError)
    case api(AnthropicAPI.APIError)
}
