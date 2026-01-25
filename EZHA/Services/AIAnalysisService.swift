import Foundation
import Supabase

final class AIAnalysisService {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseConfig.client) {
        self.supabase = supabase
    }

    func analyzeStream(
        text: String,
        imagePath: String?,
        inputType: String
    ) async throws -> AsyncThrowingStream<AIStreamEvent, Error> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && imagePath == nil {
            throw AnalysisError.emptyInput
        }

        let request = AIAnalysisRequest(
            text: trimmed.isEmpty ? nil : trimmed,
            imagePath: imagePath,
            inputType: inputType,
            stream: true
        )
        var session = try await supabase.auth.session
        if session.isExpired {
            session = try await supabase.auth.refreshSession()
        }

        do {
            #if DEBUG
            logJwtClaims(session.accessToken)
            #endif
            return try await requestEstimateStream(request: request, accessToken: session.accessToken)
        } catch let error as AnalysisError {
            if case .unauthorized = error {
                session = try await supabase.auth.refreshSession()
                #if DEBUG
                logJwtClaims(session.accessToken)
                #endif
                return try await requestEstimateStream(request: request, accessToken: session.accessToken)
            }
            throw error
        }
    }

    func analyze(text: String, imagePath: String?, inputType: String) async throws -> MacroEstimate {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && imagePath == nil {
            throw AnalysisError.emptyInput
        }

        let request = AIAnalysisRequest(
            text: trimmed.isEmpty ? nil : trimmed,
            imagePath: imagePath,
            inputType: inputType,
            stream: nil
        )
        var session = try await supabase.auth.session
        if session.isExpired {
            session = try await supabase.auth.refreshSession()
        }
        let payload: AIAnalysisResponse
        do {
            #if DEBUG
            logJwtClaims(session.accessToken)
            #endif
            payload = try await requestEstimate(request: request, accessToken: session.accessToken)
        } catch let error as AnalysisError {
            if case .unauthorized = error {
                session = try await supabase.auth.refreshSession()
                #if DEBUG
                logJwtClaims(session.accessToken)
                #endif
                payload = try await requestEstimate(request: request, accessToken: session.accessToken)
            } else {
                throw error
            }
        }

        if let error = payload.error {
            throw AnalysisError.remote(error)
        }

        guard let calories = payload.calories,
              let protein = payload.protein,
              let carbs = payload.carbs,
              let fat = payload.fat,
              let source = payload.source,
              let notes = payload.notes else {
            throw AnalysisError.invalidResponse
        }

        return MacroEstimate(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            confidence: payload.confidence,
            source: source,
            foodName: payload.foodName,
            notes: notes
        )
    }

    private func requestEstimate(
        request: AIAnalysisRequest,
        accessToken: String
    ) async throws -> AIAnalysisResponse {
        let urlRequest = try makeURLRequest(request: request, accessToken: accessToken)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.invalidResponse
        }
        guard !data.isEmpty else {
            throw AnalysisError.invalidResponse
        }

        let payload = try JSONDecoder().decode(AIAnalysisResponse.self, from: data)
#if DEBUG
        if let responseText = String(data: data, encoding: .utf8) {
            print("AI estimate status: \(httpResponse.statusCode), body: \(responseText)")
        } else {
            print("AI estimate status: \(httpResponse.statusCode), body: [non-utf8]")
        }
#endif
        if !(200..<300).contains(httpResponse.statusCode) {
            if let message = payload.error {
                throw AnalysisError.remote(message)
            }
            let responseText = String(data: data, encoding: .utf8)
            if httpResponse.statusCode == 401 {
                throw AnalysisError.unauthorized(responseText)
            }
            if let responseText, !responseText.isEmpty {
                throw AnalysisError.remote("Edge Function returned \(httpResponse.statusCode): \(responseText)")
            }
            throw AnalysisError.remote("Edge Function returned a non-2xx status code: \(httpResponse.statusCode)")
        }

        return payload
    }

    private func requestEstimateStream(
        request: AIAnalysisRequest,
        accessToken: String
    ) async throws -> AsyncThrowingStream<AIStreamEvent, Error> {
        let urlRequest = try makeURLRequest(request: request, accessToken: accessToken)
        let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnalysisError.invalidResponse
        }

        if !(200..<300).contains(httpResponse.statusCode) {
            if httpResponse.statusCode == 401 {
                throw AnalysisError.unauthorized(nil)
            }
            throw AnalysisError.remote("Edge Function returned a non-2xx status code: \(httpResponse.statusCode)")
        }

        return AsyncThrowingStream { continuation in
            Task {
                var currentEvent: String = ""
                var dataLines: [String] = []

                do {
                    for try await line in bytes.lines {
                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                let payload = dataLines.joined(separator: "\n")
                                handleStreamEvent(
                                    event: currentEvent,
                                    data: payload,
                                    continuation: continuation
                                )
                            }
                            currentEvent = ""
                            dataLines = []
                            continue
                        }

                        if line.hasPrefix("event:") {
                            currentEvent = line.replacingOccurrences(of: "event:", with: "")
                                .trimmingCharacters(in: .whitespaces)
                            continue
                        }

                        if line.hasPrefix("data:") {
                            let dataLine = line.replacingOccurrences(of: "data:", with: "")
                                .trimmingCharacters(in: .whitespaces)
                            dataLines.append(dataLine)
                        }
                    }

                    if !dataLines.isEmpty {
                        let payload = dataLines.joined(separator: "\n")
                        handleStreamEvent(
                            event: currentEvent,
                            data: payload,
                            continuation: continuation
                        )
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func handleStreamEvent(
        event: String,
        data: String,
        continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation
    ) {
        switch event {
        case "status":
            if let payload = decodeEventPayload(data: data),
               let stage = payload["stage"] as? String {
                continuation.yield(.status(stage))
            }
        case "delta":
            if let payload = decodeEventPayload(data: data),
               let delta = payload["delta"] as? String,
               !delta.isEmpty {
                continuation.yield(.delta(delta))
            }
        case "result":
            if let payload = decodeEventPayload(data: data),
               let resultData = try? JSONSerialization.data(withJSONObject: payload),
               let decoded = try? JSONDecoder().decode(AIAnalysisResponse.self, from: resultData),
               let estimate = decodeEstimate(from: decoded) {
                continuation.yield(.result(estimate))
            }
        case "error":
            if let payload = decodeEventPayload(data: data),
               let message = payload["error"] as? String {
                continuation.yield(.error(message))
            }
        default:
            break
        }
    }

    private func decodeEstimate(from payload: AIAnalysisResponse) -> MacroEstimate? {
        guard let calories = payload.calories,
              let protein = payload.protein,
              let carbs = payload.carbs,
              let fat = payload.fat,
              let source = payload.source,
              let notes = payload.notes else {
            return nil
        }

        return MacroEstimate(
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            confidence: payload.confidence,
            source: source,
            foodName: payload.foodName,
            notes: notes
        )
    }

    private func decodeEventPayload(data: String) -> [String: Any]? {
        guard let data = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    private func makeURLRequest(
        request: AIAnalysisRequest,
        accessToken: String
    ) throws -> URLRequest {
        let url = SupabaseConfig.url.appendingPathComponent("functions/v1/ai-estimate")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if request.stream == true {
            urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        return urlRequest
    }
}

#if DEBUG
private func logJwtClaims(_ token: String) {
    let parts = token.split(separator: ".")
    guard parts.count >= 2 else {
        print("AI estimate JWT claims: [invalid token format]")
        return
    }

    let header = String(parts[0])
    let payload = String(parts[1])
    let headerInfo = decodeJwtHeader(header)
    guard let data = decodeBase64Url(payload),
          let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        print("AI estimate JWT claims: [unable to decode]")
        return
    }

    let iss = jsonObject["iss"] ?? "n/a"
    let ref = jsonObject["ref"] ?? "n/a"
    let aud = jsonObject["aud"] ?? "n/a"
    let sub = jsonObject["sub"] ?? "n/a"
    let iat = jsonObject["iat"] ?? "n/a"
    let exp = jsonObject["exp"] ?? "n/a"
    print("AI estimate JWT claims: iss=\(iss), ref=\(ref), aud=\(aud), sub=\(sub), iat=\(iat), exp=\(exp), \(headerInfo)")
}

private func decodeJwtHeader(_ header: String) -> String {
    guard let data = decodeBase64Url(header),
          let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return "header=[unavailable]"
    }
    let alg = jsonObject["alg"] ?? "n/a"
    let kid = jsonObject["kid"] ?? "n/a"
    return "header: alg=\(alg), kid=\(kid)"
}

private func decodeBase64Url(_ value: String) -> Data? {
    var base64 = value.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    let padding = 4 - base64.count % 4
    if padding < 4 {
        base64 += String(repeating: "=", count: padding)
    }
    return Data(base64Encoded: base64)
}
#endif

private struct AIAnalysisRequest: Encodable {
    let text: String?
    let imagePath: String?
    let inputType: String
    let stream: Bool?
}

private struct AIAnalysisResponse: Decodable {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let confidence: Double?
    let source: String?
    let foodName: String?
    let notes: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case calories
        case protein
        case carbs
        case fat
        case confidence
        case source
        case foodName = "food_name"
        case notes
        case error
    }
}

enum AnalysisError: LocalizedError {
    case emptyInput
    case remote(String)
    case invalidResponse
    case unauthorized(String?)

    var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Please enter a food description or attach a photo."
        case .remote(let message):
            return message
        case .invalidResponse:
            return "Analysis returned an invalid response."
        case .unauthorized(let details):
            if let details, !details.isEmpty {
                return "Your session expired. \(details)"
            }
            return "Your session expired. Please log in again."
        }
    }
}

enum AIStreamEvent {
    case status(String)
    case delta(String)
    case result(MacroEstimate)
    case error(String)
}
