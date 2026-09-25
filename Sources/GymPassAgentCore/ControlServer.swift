import Foundation
import Hummingbird
import ServiceLifecycle
import NIOCore
import HTTPTypes
import GymPassCore
import GymPassShared

/// Loopback-only control API used by the GUI to talk to the agent. It is never
/// exposed through the tunnel. Authentication uses a random per-launch token
/// written to a user-only file.
public actor ControlServer {
    public let host: String
    public let port: Int
    public let token: String

    private let handler: @Sendable (AgentRequest) async -> AgentResponse
    private let statusProvider: @Sendable () async -> StatusSnapshot
    private let activityProvider: @Sendable (Int) async -> [ActivityEvent]

    private var group: ServiceGroup?
    private var runTask: Task<Void, Never>?

    public init(
        host: String = "127.0.0.1",
        port: Int,
        token: String,
        handler: @escaping @Sendable (AgentRequest) async -> AgentResponse,
        statusProvider: @escaping @Sendable () async -> StatusSnapshot,
        activityProvider: @escaping @Sendable (Int) async -> [ActivityEvent]
    ) {
        self.host = host
        self.port = port
        self.token = token
        self.handler = handler
        self.statusProvider = statusProvider
        self.activityProvider = activityProvider
    }

    public func start() async throws {
        let router = buildRouter()
        let configuration = ApplicationConfiguration(address: .hostname(host, port: port))
        let app = Application(router: router, configuration: configuration)
        let group = ServiceGroup(services: [app], gracefulShutdownSignals: [], cancellationSignals: [])
        self.group = group
        self.runTask = Task {
            do { try await group.run() } catch {
                Log.ipc.error("Control server stopped: \(String(describing: error), privacy: .public)")
            }
        }
        Log.ipc.info("Control server starting on \(self.host, privacy: .public):\(self.port, privacy: .public)")
    }

    public func stop() async {
        await group?.triggerGracefulShutdown()
        await runTask?.value
        group = nil
        runTask = nil
    }

    private func buildRouter() -> Router<BasicRequestContext> {
        let router = Router<BasicRequestContext>()
        let token = self.token
        let handler = self.handler
        let statusProvider = self.statusProvider
        let activityProvider = self.activityProvider

        router.get("/health") { _, _ -> Response in
            Response(status: .ok, body: ResponseBody(byteBuffer: ByteBuffer(string: "{\"status\":\"ok\"}")))
        }

        router.get("/control/status") { request, _ -> Response in
            guard Self.isAuthorized(request, token: token) else { return Self.unauthorized() }
            let snapshot = await statusProvider()
            return Self.encode(snapshot)
        }

        router.post("/control/request") { request, _ -> Response in
            guard Self.isAuthorized(request, token: token) else { return Self.unauthorized() }
            guard let body = try? await request.body.collect(upTo: 4 * 1024 * 1024),
                  let agentRequest = try? JSONDecoder().decode(AgentRequest.self, from: Data(body.readableBytesView)) else {
                return Self.badRequest()
            }
            let response = await handler(agentRequest)
            return Self.encode(response)
        }

        router.get("/control/activity") { request, _ -> Response in
            guard Self.isAuthorized(request, token: token) else { return Self.unauthorized() }
            let limit = request.uri.queryParameters["limit"].flatMap { Int($0) } ?? 200
            let events = await activityProvider(limit)
            return Self.encode(events)
        }

        return router
    }

    private static func isAuthorized(_ request: Request, token: String) -> Bool {
        guard let provided = request.headers[HTTPField.Name(AgentProtocol.controlTokenHeader)!] else { return false }
        return constantTimeEquals(provided, token)
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8)
        let y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var difference: UInt8 = 0
        for index in 0..<x.count { difference |= x[index] ^ y[index] }
        return difference == 0
    }

    private static func encode<T: Encodable>(_ value: T) -> Response {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        headers[.cacheControl] = "no-store"
        return Response(status: .ok, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }

    private static func unauthorized() -> Response {
        Response(status: .unauthorized)
    }

    private static func badRequest() -> Response {
        Response(status: .badRequest)
    }
}
