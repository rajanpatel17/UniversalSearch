//
//  AICallModel.swift
//  MintoakBase
//
//  Created by Rajan Patel on 16/12/25.
//

import Foundation

// MARK: - Token Models

struct TokenResponse: Codable {
    let success: Bool
    let data: TokenData?
    let message: String
}

struct TokenData: Codable {
    let token: String
    let roomName: String

    enum CodingKeys: String, CodingKey {
        case token
        case roomName = "room_name"
    }
}

// MARK: - Agent Models

struct ConnectAgentRequest: Codable {
    let name: String
    let roomName: String
    let agentType: String
    let agentName: String
    let userContext: String
    let sessionData: [String: CodableValue]
    let chatConversationId: String

    enum CodingKeys: String, CodingKey {
        case name
        case roomName = "room_name"
        case agentType = "agent_type"
        case agentName = "agent_name"
        case userContext = "user_context"
        case sessionData = "session_data"
        case chatConversationId = "chat_conversation_id"
    }
}

enum CodableValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        }
    }
}

struct ConnectAgentResponse: Codable {
    let success: Bool
    let data: ConnectAgentData?
    let message: String
}

struct ConnectAgentData: Codable {
    let roomName: String

    enum CodingKeys: String, CodingKey {
        case roomName = "room_name"
    }
}

struct UserContext: Codable {
    let userQuery: String
}
