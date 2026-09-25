import Foundation
import GymPassCore
import GymPassShared

enum AgentClientError: Error {
    case notRunning
    case badStatus(Int)
    case decodingFailed
}

/// Thin HTTP client for the agent's loopback control API. The endpoint file is
/// re-read on every discovery so agent restarts are picked up automatically.
struct AgentClient: Sendable {
    let endpoint: ControlEndpointFile

    static func discover() -> AgentClient? {
        let url = AppPaths.controlEndpointURL()
        guard let data = try? Data(contentsOf: url),
              let endpoint = try? JSONDecoder().decode(ControlEndpointFile.self, from: data) else {
            return nil
        }
        return AgentClient(endpoint: endpoint)
    }

    private var baseURL: URL {
        URL(string: "http://127.0.0.1:\(endpoint.controlPort)")!
    }

    func status() async throws -> StatusSnapshot {
        try await get(path: AgentProtocol.statusPath, as: StatusSnapshot.self)
    }

    func activity(limit: Int = 200) async throws -> [ActivityEvent] {
        try await get(path: "\(AgentProtocol.activityPath)?limit=\(limit)", as: [ActivityEvent].self)
    }

    func send(_ request: AgentRequest) async throws -> AgentResponse {
        var httpRequest = URLRequest(url: baseURL.appendingPathComponent(AgentProtocol.requestPath))
        httpRequest.httpMethod = "POST"
        httpRequest.setValue(endpoint.token, forHTTPHeaderField: AgentProtocol.controlTokenHeader)
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try JSONEncoder().encode(request)
        httpRequest.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: httpRequest)
        guard let http = response as? HTTPURLResponse else { throw AgentClientError.notRunning }
        guard http.statusCode == 200 else { throw AgentClientError.badStatus(http.statusCode) }
        guard let decoded = try? JSONDecoder().decode(AgentResponse.self, from: data) else {
            throw AgentClientError.decodingFailed
        }
        return decoded
    }

    private func get<T: Decodable>(path: String, as type: T.Type) async throws -> T {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        request.setValue(endpoint.token, forHTTPHeaderField: AgentProtocol.controlTokenHeader)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AgentClientError.notRunning }
        guard http.statusCode == 200 else { throw AgentClientError.badStatus(http.statusCode) }
        guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw AgentClientError.decodingFailed
        }
        return decoded
    }
}
