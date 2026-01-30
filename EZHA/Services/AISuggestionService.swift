import Auth
import Foundation
import Supabase

final class AISuggestionService {
    private let supabase: SupabaseClient

    init(supabase: SupabaseClient = SupabaseConfig.client) {
        self.supabase = supabase
    }

    func fetchSuggestions(request: AISuggestionRequest) async throws -> [AISuggestionPayload] {
        var session = try await freshSession()
        let payload: AISuggestionResponse

        do {
            payload = try await requestSuggestions(request: request, accessToken: session.accessToken)
        } catch let error as SuggestionError {
            if case .unauthorized = error {
                session = try await refreshSessionOrSignOut()
                payload = try await requestSuggestions(request: request, accessToken: session.accessToken)
            } else {
                throw error
            }
        }

        if let error = payload.error {
            throw SuggestionError.remote(error)
        }

        guard let suggestions = payload.suggestions, !suggestions.isEmpty else {
            throw SuggestionError.invalidResponse
        }

        return suggestions
    }

    private func requestSuggestions(
        request: AISuggestionRequest,
        accessToken: String
    ) async throws -> AISuggestionResponse {
        let urlRequest = try makeURLRequest(request: request, accessToken: accessToken)
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SuggestionError.invalidResponse
        }
        guard !data.isEmpty else {
            throw SuggestionError.invalidResponse
        }

        let payload = try JSONDecoder().decode(AISuggestionResponse.self, from: data)
#if DEBUG
        if let responseText = String(data: data, encoding: .utf8) {
            print("AI suggestions status: \(httpResponse.statusCode), body: \(responseText)")
        } else {
            print("AI suggestions status: \(httpResponse.statusCode), body: [non-utf8]")
        }
#endif
        if !(200..<300).contains(httpResponse.statusCode) {
            if let message = payload.error {
                throw SuggestionError.remote(message)
            }
            let responseText = String(data: data, encoding: .utf8)
            if httpResponse.statusCode == 401 {
                throw SuggestionError.unauthorized(responseText)
            }
            if let responseText, !responseText.isEmpty {
                throw SuggestionError.remote("Edge Function returned \(httpResponse.statusCode): \(responseText)")
            }
            throw SuggestionError.remote("Edge Function returned a non-2xx status code: \(httpResponse.statusCode)")
        }

        return payload
    }

    private func makeURLRequest(
        request: AISuggestionRequest,
        accessToken: String
    ) throws -> URLRequest {
        // [PLACEHOLDER] Ensure Supabase Edge Function "ai-suggestions" exists and matches the contract.
        let url = SupabaseConfig.url.appendingPathComponent("functions/v1/ai-suggestions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        return urlRequest
    }

    private func freshSession() async throws -> Session {
        do {
            return try await SupabaseConfig.currentSession()
        } catch let error as AuthError {
            try? await supabase.auth.signOut()
            throw SuggestionError.unauthorized(error.localizedDescription)
        } catch let error as URLError {
            throw SuggestionError.network(error.localizedDescription)
        } catch {
            throw SuggestionError.remote("Unable to verify session: \(error.localizedDescription)")
        }
    }

    private func refreshSessionOrSignOut() async throws -> Session {
        do {
            return try await supabase.auth.refreshSession()
        } catch let error as AuthError {
            try? await supabase.auth.signOut()
            throw SuggestionError.unauthorized(error.localizedDescription)
        } catch let error as URLError {
            throw SuggestionError.network(error.localizedDescription)
        } catch {
            throw SuggestionError.remote("Unable to refresh session: \(error.localizedDescription)")
        }
    }
}

struct AISuggestionRequest: Encodable {
    let remaining: AISuggestionMacros
    let mealType: String
    let maxPrepMinutes: Int
    let count: Int
    let ingredientNotes: String?
    let variationNote: String?
    let units: String

    enum CodingKeys: String, CodingKey {
        case remaining
        case mealType = "meal_type"
        case maxPrepMinutes = "max_prep_minutes"
        case count
        case ingredientNotes = "ingredient_notes"
        case variationNote = "variation_note"
        case units
    }
}

struct AISuggestionMacros: Encodable {
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
}

struct AISuggestionResponse: Decodable {
    let suggestions: [AISuggestionPayload]?
    let error: String?
}

struct AISuggestionPayload: Decodable {
    let title: String
    let description: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let notes: String?
}

enum SuggestionError: LocalizedError {
    case invalidResponse
    case unauthorized(String?)
    case network(String)
    case remote(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Suggestions returned an invalid response."
        case .unauthorized(let details):
            if let details, !details.isEmpty {
                return "Your session expired. \(details)"
            }
            return "Your session expired. Please log in again."
        case .network(let details):
            return "Network error: \(details). Please check your connection and try again."
        case .remote(let message):
            return message
        }
    }
}
