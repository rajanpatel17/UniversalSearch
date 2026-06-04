//
//  AICallViewModel.swift
//  MintoakBase
//
//  Created by Rajan Patel on 16/12/25.
//  Copyright © 2025 Chaitanya Soni. All rights reserved.
//

import Foundation

final class AICallViewModel {

    // MARK: - Outputs (all callbacks fire on main queue)
    var onTokenSuccess: ((String, String, Bool) -> Void)? // token, roomName, isScreenShared
    var onAgentConnected: ((String) -> Void)?
    var onRoomDeleted: (() -> Void)?
    var onError: ((String) -> Void)?

    // MARK: - Get Token API
    func getToken(name: String, isScreenShared: Bool = false) {

        // URL-encode the name parameter to handle spaces & special characters
        guard let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(Constant.baseUrl)v1/getToken?name=\(encodedName)") else {
            dispatchMain { self.onError?("Invalid URL") }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.addValue(Constant.authToken, forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            if let error {
                self.dispatchMain { self.onError?(error.localizedDescription) }
                return
            }

            guard let data else {
                self.dispatchMain { self.onError?("No data received") }
                return
            }

            do {
                let response = try JSONDecoder().decode(TokenResponse.self, from: data)

                if response.success, let tokenData = response.data {
                    self.dispatchMain { self.onTokenSuccess?(tokenData.token, tokenData.roomName, isScreenShared) }
                } else {
                    self.dispatchMain { self.onError?(response.message) }
                }

            } catch {
                self.dispatchMain { self.onError?("Token parsing failed") }
            }
        }.resume()
    }

    // MARK: - Connect Agent API
    @MainActor func connectAgent(
        name: String,
        roomName: String,
        agentType: String = "video",
        agentName: String = Constant.agentName,
        userContext: String = ""
    ) {
        
        //let sessionId = AnalyticsUtilites.shared.sessionId
        //let loginID = AppData.shared.user.loginID
        let loginID = UserDefaults.standard.string(forKey: "login_id")
        let fcmToken = UserDefaults.standard.string(forKey: "deviceToken")
        let sId = UserDefaults.standard.string(forKey: "sessionId") ?? ""

        let sessionData: [String: CodableValue] = [
            "session_id": .string(sId),
            "mobile_number": .string(loginID ?? ""),
            "fcm_token" : .string(fcmToken ?? "")
        ]
        
        let requestBody = ConnectAgentRequest(
            name: name,
            roomName: roomName,
            agentType: agentType,
            agentName: agentName,
            userContext: userContext,
            sessionData: sessionData,
            chatConversationId: LiveKitCallManager.shared.chatConversationId ?? ""
        )

        guard let url = URL(string: "\(Constant.baseUrl)v1/agent/connectAgent") else {
            dispatchMain { self.onError?("Invalid URL") }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(Constant.authToken, forHTTPHeaderField: "Authorization")

        do {
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            dispatchMain { self.onError?("Failed to encode request") }
            return
        }

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            if let error {
                self.dispatchMain { self.onError?(error.localizedDescription) }
                return
            }

            guard let data else {
                self.dispatchMain { self.onError?("No data received") }
                return
            }

            do {
                let response = try JSONDecoder().decode(ConnectAgentResponse.self, from: data)

                if response.success, let room = response.data?.roomName {
                    self.dispatchMain { self.onAgentConnected?(room) }
                } else {
                    self.dispatchMain { self.onError?(response.message) }
                }

            } catch {
                self.dispatchMain { self.onError?("Agent response parsing failed") }
            }
        }.resume()
    }

    // MARK: - Delete Room API
    func deleteRoom(roomName: String) {

        guard let url = URL(string: "\(Constant.baseUrl)v1/rooms/\(roomName)") else {
            dispatchMain { self.onError?("Invalid URL") }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 30
        request.addValue(Constant.authToken, forHTTPHeaderField: "Authorization")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let self else { return }

            if let error {
                self.dispatchMain { self.onError?(error.localizedDescription) }
                return
            }

            guard let data else {
                self.dispatchMain { self.onError?("No data received") }
                return
            }

            do {
                let response = try JSONDecoder().decode(ConnectAgentResponse.self, from: data)

                if response.success {
                    self.dispatchMain { self.onRoomDeleted?() }
                } else {
                    self.dispatchMain { self.onError?(response.message) }
                }

            } catch {
                self.dispatchMain { self.onRoomDeleted?() }
            }
        }.resume()
    }

    private func dispatchMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }
}
