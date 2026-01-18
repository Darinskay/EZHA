import Foundation
import Supabase

final class AIAnalysisService {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseConfig.client) {
        self.supabase = supabase
    }

    func analyze(text: String, imagePath: String?, inputType: String) async throws -> MacroEstimate {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && imagePath == nil {
            throw AnalysisError.emptyInput
        }

        let request = AIAnalysisRequest(
            text: trimmed.isEmpty ? nil : trimmed,
            imagePath: imagePath,
            inputType: inputType
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
            calories: Int(round(calories)),
            protein: Int(round(protein)),
            carbs: Int(round(carbs)),
            fat: Int(round(fat)),
            confidence: payload.confidence,
            source: source,
            notes: notes
        )
    }

    private func requestEstimate(
        request: AIAnalysisRequest,
        accessToken: String
    ) async throws -> AIAnalysisResponse {
        let url = SupabaseConfig.url.appendingPathComponent("functions/v1/ai-estimate")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.httpBody = try JSONEncoder().encode(request)

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
}

private struct AIAnalysisResponse: Decodable {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let confidence: Double?
    let source: String?
    let notes: String?
    let error: String?
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
