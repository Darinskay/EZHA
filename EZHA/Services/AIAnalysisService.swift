import Foundation
import Supabase

final class AIAnalysisService {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseConfig.client) {
        self.supabase = supabase
    }

    func analyze(text: String, hasPhoto: Bool) async throws -> MacroEstimate {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AnalysisError.emptyInput
        }

        let request = AIAnalysisRequest(text: trimmed, inputType: hasPhoto ? "photo+text" : "text")
        var session = try await supabase.auth.session
        if session.isExpired {
            session = try await supabase.auth.refreshSession()
        }
#if DEBUG
        await debugValidateAccessToken(session.accessToken)
#endif
        let payload: AIAnalysisResponse
        do {
            payload = try await requestEstimate(request: request, accessToken: session.accessToken)
        } catch let error as AnalysisError {
            if case .unauthorized = error {
                #if DEBUG
                debugPrintTokenDetails(session.accessToken)
                #endif
                session = try await supabase.auth.refreshSession()
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

private struct AIAnalysisRequest: Encodable {
    let text: String
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
            return "Please enter a food description."
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

#if DEBUG
private func debugPrintTokenDetails(_ token: String) {
    guard let payload = decodeJWTPayload(token) else {
        print("JWT debug: unable to decode token payload.")
        return
    }
    let iss = payload["iss"] as? String ?? "unknown"
    let ref = payload["ref"] as? String ?? "unknown"
    let aud = payload["aud"] as? String ?? "unknown"
    let role = payload["role"] as? String ?? "unknown"
    let sub = payload["sub"] as? String ?? "unknown"
    let exp = payload["exp"] as? Double ?? 0
    print("JWT debug: iss=\(iss), ref=\(ref), aud=\(aud), role=\(role), sub=\(sub), exp=\(exp)")
}

private func decodeJWTPayload(_ token: String) -> [String: Any]? {
    let parts = token.split(separator: ".")
    guard parts.count >= 2 else { return nil }
    var base64 = String(parts[1])
    let padding = 4 - (base64.count % 4)
    if padding < 4 {
        base64.append(String(repeating: "=", count: padding))
    }
    base64 = base64.replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    guard let data = Data(base64Encoded: base64) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
}

@MainActor
private func debugValidateAccessToken(_ token: String) async {
    let url = SupabaseConfig.url.appendingPathComponent("auth/v1/user")
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
    do {
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("JWT debug: auth/v1/user status=\(status)")
    } catch {
        print("JWT debug: auth/v1/user failed: \(error.localizedDescription)")
    }
}
#endif
