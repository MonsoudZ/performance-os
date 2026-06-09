import Foundation

struct WearablePairingResponse: Decodable {
    struct Device: Decodable {
        let id: Int
        let platform: String
        let name: String
    }

    let device: Device
    let accessToken: String
    let syncURL: URL

    enum CodingKeys: String, CodingKey {
        case device
        case accessToken = "access_token"
        case syncURL = "sync_url"
    }
}

struct WearablePairingClient {
    enum PairingError: Error {
        case invalidResponse
    }

    let registrationURL: URL
    let session: URLSession

    init(registrationURL: URL, session: URLSession = .shared) {
        self.registrationURL = registrationURL
        self.session = session
    }

    func pair(
        installationID: UUID,
        deviceName: String,
        csrfToken: String
    ) async throws -> WearablePairingResponse {
        var request = URLRequest(url: registrationURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "wearable_device": [
                "platform": "ios_healthkit",
                "external_id": installationID.uuidString,
                "name": deviceName
            ]
        ])

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            throw PairingError.invalidResponse
        }
        return try JSONDecoder().decode(WearablePairingResponse.self, from: data)
    }
}
