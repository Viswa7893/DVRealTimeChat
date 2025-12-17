//
//  AuthService.swift
//  DVRealTimeChat
//
//  Created by Durga Viswanadh on 14/12/25.
//

import Foundation
import Combine

@MainActor
class AuthService: ObservableObject {
    @Published var currentUser: UserResponse?
    @Published var authToken: String?
    @Published var isAuthenticated = false
    
    private let baseURL = "http://127.0.0.1:8080/api"
    
    // Shared JSON Decoder with proper configuration
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    init() {
        // Load saved token
        if let token = UserDefaults.standard.string(forKey: "auth_token") {
            self.authToken = token
            Task {
                await loadCurrentUser()
            }
        }
    }
    
    // MARK: - Register
    func register(name: String, email: String, password: String) async throws -> UserResponse {
        let url = URL(string: "\(baseURL)/auth/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "name": name,
            "email": email,
            "password": password
        ]
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        if httpResponse.statusCode == 409 {
            throw AuthError.emailAlreadyExists
        }
        
        guard httpResponse.statusCode == 200 else {
            // Print response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("âŒ Server response: \(jsonString)")
            }
            throw AuthError.serverError(httpResponse.statusCode)
        }
        
        // Debug: Print raw response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("ðŸ“¥ Register response: \(jsonString)")
        }
        
        let loginResponse = try decoder.decode(LoginResponse.self, from: data)
        
        // Save token
        self.authToken = loginResponse.token
        self.currentUser = loginResponse.user
        self.isAuthenticated = true
        UserDefaults.standard.set(loginResponse.token, forKey: "auth_token")
        
        return loginResponse.user
    }
    
    // MARK: - Login
    func login(email: String, password: String) async throws -> UserResponse {
        print("🌐 Making login request to: \(baseURL)/auth/login")
        
        let url = URL(string: "\(baseURL)/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = [
            "email": email,
            "password": password
        ]
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw AuthError.invalidResponse
        }
        
        print("📡 HTTP Status Code: \(httpResponse.statusCode)")
        
        guard httpResponse.statusCode == 200 else {
            // Print response for debugging
            if let jsonString = String(data: data, encoding: .utf8) {
                print("❌ Server response: \(jsonString)")
            }
            throw AuthError.invalidCredentials
        }
        
        // Debug: Print raw response
        if let prettyJSON = prettyPrintJSON(data) {
            print("📥 Login response :\n\(prettyJSON)")
        }

        
        let loginResponse = try decoder.decode(LoginResponse.self, from: data)
        objectWillChange.send()
        
        // Save token
        self.authToken = loginResponse.token
        self.currentUser = loginResponse.user
        self.isAuthenticated = true
        UserDefaults.standard.set(loginResponse.token, forKey: "auth_token")
        
        print("✅ AuthService updated - isAuthenticated: \(self.isAuthenticated)")
        print("✅ Token saved to UserDefaults")
        
        return loginResponse.user
    }
    
    // MARK: - Load Current User
    func loadCurrentUser() async {
        guard let token = authToken else { return }
        
        let url = URL(string: "\(baseURL)/auth/me")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let user = try decoder.decode(UserResponse.self, from: data)
            self.currentUser = user
            self.isAuthenticated = true
        } catch {
            print("âŒ Failed to load current user: \(error)")
            self.logout()
        }
    }
    
    // MARK: - Logout
    func logout() {
        self.authToken = nil
        self.currentUser = nil
        self.isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: "auth_token")
    }
    
    func prettyPrintJSON(_ data: Data) -> String? {
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(
                withJSONObject: jsonObject,
                options: [.prettyPrinted]
            )
            return String(data: prettyData, encoding: .utf8)
        } catch {
            print("❌ JSON pretty print failed:", error)
            return nil
        }
    }
}

// MARK: - Models
struct LoginResponse: Codable {
    let user: UserResponse
    let token: String
}

struct UserResponse: Codable, Identifiable {
    let id: UUID
    let name: String
    let email: String
    let avatarURL: String?
    let isOnline: Bool
    let lastSeen: Date?
    
    // Computed property to get String ID for SwiftUI
    var stringId: String {
        id.uuidString
    }
}

enum AuthError: LocalizedError {
    case invalidCredentials
    case emailAlreadyExists
    case invalidResponse
    case serverError(Int)
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .emailAlreadyExists:
            return "Email already registered"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let code):
            return "Server error: \(code)"
        case .networkError:
            return "Network error occurred"
        }
    }
}
