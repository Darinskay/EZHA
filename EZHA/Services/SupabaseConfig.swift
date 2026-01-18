import Foundation
import Supabase

enum SupabaseConfig {
    static let client = SupabaseClient(
        supabaseURL: supabaseURL,
        supabaseKey: supabaseAnonKey
    )

    static let oauthRedirectScheme = infoPlistValue(for: "SUPABASE_OAUTH_CALLBACK_SCHEME")

    static let oauthRedirectURL: URL = {
        let urlString = infoPlistValue(for: "SUPABASE_OAUTH_REDIRECT_URL")
        guard let url = URL(string: urlString) else {
            fatalError("Invalid SUPABASE_OAUTH_REDIRECT_URL: \(urlString)")
        }
        return url
    }()

    private static var supabaseURL: URL {
        let urlString = infoPlistValue(for: "SUPABASE_URL")
        guard let url = URL(string: urlString) else {
            fatalError("Invalid SUPABASE_URL: \(urlString)")
        }
        return url
    }

    static var url: URL {
        supabaseURL
    }

    private static var supabaseAnonKey: String {
        infoPlistValue(for: "SUPABASE_ANON_KEY")
    }

    static var anonKey: String {
        supabaseAnonKey
    }

    private static func infoPlistValue(for key: String) -> String {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: key
        ) as? String,
        !value.isEmpty,
        !value.hasPrefix("[PLACEHOLDER]") else {
            fatalError("Missing Info.plist value for \(key).")
        }
        return value
    }
}
