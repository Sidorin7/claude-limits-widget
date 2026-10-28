import ClaudeLimitsCore
import Foundation
import os

let log = Logger(subsystem: "com.ivansidorin.claudelimits", category: "usage")

enum FetchResult {
    case success(UsageResponse)
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case failed(String)
}

enum UsageAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Reads Claude Code's login through the `security` tool. Claude Code itself writes the
    /// item with that tool, so reading it this way does not trigger a keychain prompt.
    static func readCredentials() -> OAuthCredentials? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return OAuthCredentials.parse(data)
    }

    static func fetch(token: String) async -> FetchResult {
        var req = URLRequest(url: endpoint, timeoutInterval: 20)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ClaudeLimits/1.0", forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData

        log.info("GET /api/oauth/usage")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            log.info("response \(status)")
            switch status {
            case 200:
                do { return .success(try UsageResponse.decode(data)) }
                catch { return .failed("Не удалось разобрать ответ") }
            case 401, 403:
                return .unauthorized
            case 429:
                let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After")
                return .rateLimited(retryAfter: header.flatMap(TimeInterval.init))
            default:
                return .failed("Ошибка сервера \(status)")
            }
        } catch {
            log.error("network error: \(error.localizedDescription)")
            return .failed("Нет связи с сервером")
        }
    }
}
