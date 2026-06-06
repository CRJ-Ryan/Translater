import Foundation
import Translation
import CryptoKit

/// Translation service with three-engine fallback strategy:
/// 1. Baidu Translate — best quality, requires API credentials (primary)
/// 2. MyMemory — free, no key required
/// 3. Apple on-device — offline, requires pre-installed language models
@available(macOS 15.0, *)
final class TranslationService {
    // MARK: - Configuration

    private var sourceLang = LanguageOption.findByCode("zh")
    private var targetLang = LanguageOption.findByCode("en")

    /// Baidu API credentials (set externally)
    var baiduAppID: String = ""
    var baiduSecretKey: String = ""

    var isBaiduConfigured: Bool {
        !baiduAppID.isEmpty && !baiduSecretKey.isEmpty
    }

    var sourceLanguageName: String { sourceLang.displayName }
    var targetLanguageName: String { targetLang.displayName }

    /// Language pair string for MyMemory API (e.g., "zh|en")
    private var langPair: String {
        "\(sourceLang.code)|\(targetLang.code)"
    }

    // MARK: - State

    private var appleSession: TranslationSession?
    private var currentTask: Task<Void, Never>?
    private var appleAvailable = true

    // MARK: - Public API

    func setLanguages(source: LanguageOption, target: LanguageOption) {
        guard source != sourceLang || target != targetLang else { return }
        sourceLang = source
        targetLang = target
        appleSession = nil
        appleAvailable = true
        print("[Translation] 语言切换: \(source.displayName) → \(target.displayName)")
    }

    func translate(_ text: String, completion: @escaping (String) -> Void) {
        currentTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion("")
            return
        }

        currentTask = Task { [weak self] in
            guard let self = self else { return }

            var result: String?

            // 1. Baidu (primary — best quality, requires credentials)
            if self.isBaiduConfigured {
                do {
                    result = try await self.baiduTranslate(trimmed)
                } catch {
                    print("[Translation] 百度失败: \(error.localizedDescription)")
                }
            }

            // 2. MyMemory (free fallback)
            if result == nil {
                do {
                    result = try await self.mymemoryTranslate(trimmed)
                } catch {
                    print("[Translation] MyMemory 失败: \(error.localizedDescription)")
                }
            }

            // 3. Apple on-device (last resort)
            if result == nil && self.appleAvailable {
                do {
                    result = try await self.appleTranslate(trimmed)
                } catch {
                    print("[Translation] Apple 翻译也失败: \(error.localizedDescription)")
                    self.appleAvailable = false
                }
            }

            if Task.isCancelled { return }

            let finalText = result ?? trimmed
            await MainActor.run { completion(finalText) }
        }
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }

    // MARK: - Baidu Translation

    private func baiduTranslate(_ text: String) async throws -> String {
        let salt = String(Int.random(in: 10000...99999))
        let signStr = baiduAppID + text + salt + baiduSecretKey
        guard let signData = signStr.data(using: .utf8) else {
            throw TranslationServiceError.signError
        }
        let sign = Insecure.MD5.hash(data: signData).map { String(format: "%02x", $0) }.joined()

        var components = URLComponents(string: "https://fanyi-api.baidu.com/api/trans/vip/translate")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "from", value: sourceLang.baiduCode),
            URLQueryItem(name: "to", value: targetLang.baiduCode),
            URLQueryItem(name: "appid", value: baiduAppID),
            URLQueryItem(name: "salt", value: salt),
            URLQueryItem(name: "sign", value: sign),
        ]

        guard let url = components.url else {
            throw TranslationServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TranslationServiceError.networkError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TranslationServiceError.parseError
        }

        // Check for Baidu error
        if let errorCode = json["error_code"] as? String {
            let errorMsg = json["error_msg"] as? String ?? "未知错误"
            print("[Translation] 百度 API 错误 \(errorCode): \(errorMsg)")
            throw TranslationServiceError.baiduError(code: errorCode, message: errorMsg)
        }

        guard let transResult = json["trans_result"] as? [[String: Any]],
              let first = transResult.first,
              let dst = first["dst"] as? String else {
            throw TranslationServiceError.parseError
        }

        print("[Translation] 百度: \"\(text)\" → \"\(dst)\"")
        return dst
    }

    // MARK: - MyMemory Translation (Free, no API key)

    private func mymemoryTranslate(_ text: String) async throws -> String {
        var components = URLComponents(string: "https://api.mymemory.translated.net/get")!
        components.queryItems = [
            URLQueryItem(name: "q", value: text),
            URLQueryItem(name: "langpair", value: langPair),
        ]

        guard let url = components.url else {
            throw TranslationServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw TranslationServiceError.networkError
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseData = json["responseData"] as? [String: Any],
              let translatedText = responseData["translatedText"] as? String else {
            throw TranslationServiceError.parseError
        }

        print("[Translation] MyMemory: \"\(text)\" → \"\(translatedText)\"")
        return translatedText
    }

    // MARK: - Apple Translation (on-device, offline)

    private func appleTranslate(_ text: String) async throws -> String {
        if appleSession == nil {
            let source = Locale.Language(identifier: sourceLang.appleCode)
            let target = Locale.Language(identifier: targetLang.appleCode)

            let availability = LanguageAvailability()
            let status = await availability.status(from: source, to: target)
            print("[Translation] Apple 语言状态: \(status)")

            guard status != .unsupported else {
                throw TranslationServiceError.unsupportedLanguagePair(
                    source: sourceLang.code,
                    target: targetLang.code
                )
            }

            if #available(macOS 26.0, *) {
                let session = TranslationSession(installedSource: source, target: target)
                do {
                    try await session.prepareTranslation()
                    appleSession = session
                    print("[Translation] ✅ Apple 翻译就绪")
                } catch {
                    print("[Translation] ❌ Apple 翻译初始化失败: \(error)")
                    throw error
                }
            } else {
                throw TranslationServiceError.needsMacOS26
            }
        }

        guard let session = appleSession else {
            throw TranslationServiceError.sessionCreationFailed
        }

        let response = try await session.translate(text)
        print("[Translation] Apple: \"\(text)\" → \"\(response.targetText)\"")
        return response.targetText
    }
}

// MARK: - Errors

enum TranslationServiceError: Error, LocalizedError {
    case sessionCreationFailed
    case unsupportedLanguagePair(source: String, target: String)
    case needsMacOS26
    case invalidURL
    case networkError
    case parseError
    case signError
    case baiduError(code: String, message: String)

    var errorDescription: String? {
        switch self {
        case .sessionCreationFailed:
            return "无法创建翻译会话"
        case .unsupportedLanguagePair(let src, let tgt):
            return "不支持的语言对: \(src)→\(tgt)"
        case .needsMacOS26:
            return "需macOS 26+"
        case .invalidURL:
            return "翻译URL无效"
        case .networkError:
            return "网络请求失败"
        case .parseError:
            return "翻译结果解析失败"
        case .signError:
            return "签名生成失败"
        case .baiduError(let code, let msg):
            return "百度翻译错误 [\(code)]: \(msg)"
        }
    }
}
