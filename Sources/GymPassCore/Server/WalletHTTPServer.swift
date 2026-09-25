import Foundation
import Hummingbird
import ServiceLifecycle
import NIOCore
import HTTPTypes
import GymPassShared

/// The Apple Wallet pass-update web service. Binds to loopback only and exposes
/// exactly the routes Wallet requires, plus a scoped installation route.
public actor WalletHTTPServer {
    public let host: String
    public let port: Int
    public let stats: ServerStats
    private let service: WalletService
    private let publicHostnameProvider: @Sendable () async -> String?

    private var group: ServiceGroup?
    private var runTask: Task<Void, Never>?

    private static let maxBodyBytes = 64 * 1024

    public init(
        host: String = "127.0.0.1",
        port: Int = 8754,
        service: WalletService,
        stats: ServerStats,
        publicHostnameProvider: @escaping @Sendable () async -> String? = { nil }
    ) {
        self.host = host
        self.port = port
        self.service = service
        self.stats = stats
        self.publicHostnameProvider = publicHostnameProvider
    }

    public func start() async throws {
        let router = buildRouter()
        let configuration = ApplicationConfiguration(
            address: .hostname(host, port: port)
        )
        let app = Application(router: router, configuration: configuration)
        let group = ServiceGroup(
            services: [app],
            gracefulShutdownSignals: [],
            cancellationSignals: []
        )
        self.group = group
        self.runTask = Task {
            do {
                try await group.run()
            } catch {
                Log.server.error("Wallet server stopped: \(String(describing: error), privacy: .public)")
            }
        }
        Log.server.info("Wallet server starting on \(self.host, privacy: .public):\(self.port, privacy: .public)")
    }

    public func stop() async {
        await group?.triggerGracefulShutdown()
        await runTask?.value
        group = nil
        runTask = nil
        Log.server.info("Wallet server stopped")
    }

    // MARK: - Routing

    private func buildRouter() -> Router<BasicRequestContext> {
        let router = Router<BasicRequestContext>()
        let service = self.service
        let stats = self.stats
        let hostnameProvider = self.publicHostnameProvider

        router.get("/health") { _, _ -> Response in
            await stats.record()
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: ResponseBody(byteBuffer: ByteBuffer(string: "{\"status\":\"ok\"}"))
            )
        }

        // Registration
        router.post("/v1/devices/:deviceLibraryIdentifier/registrations/:passTypeIdentifier/:serialNumber") { request, context -> Response in
            await stats.record()
            guard let parameters = Self.registrationParameters(context) else {
                return Self.badRequest()
            }
            guard let token = Self.passAuthorizationToken(request),
                  await service.validatePassToken(passTypeIdentifier: parameters.passType, serialNumber: parameters.serial, token: token) else {
                return Self.unauthorized()
            }
            struct Payload: Decodable { var pushToken: String }
            guard let body = try? await request.body.collect(upTo: Self.maxBodyBytes),
                  let payload = try? JSONDecoder().decode(Payload.self, from: Data(body.readableBytesView)),
                  let pushToken = Data(hexString: payload.pushToken) else {
                return Self.badRequest()
            }
            do {
                let created = try await service.register(
                    deviceLibraryIdentifier: parameters.device,
                    passTypeIdentifier: parameters.passType,
                    serialNumber: parameters.serial,
                    pushToken: pushToken
                )
                return Response(status: created ? .created : .ok)
            } catch {
                return Self.serverError()
            }
        }

        router.delete("/v1/devices/:deviceLibraryIdentifier/registrations/:passTypeIdentifier/:serialNumber") { request, context -> Response in
            await stats.record()
            guard let parameters = Self.registrationParameters(context) else {
                return Self.badRequest()
            }
            guard let token = Self.passAuthorizationToken(request),
                  await service.validatePassToken(passTypeIdentifier: parameters.passType, serialNumber: parameters.serial, token: token) else {
                return Self.unauthorized()
            }
            do {
                try await service.unregister(
                    deviceLibraryIdentifier: parameters.device,
                    passTypeIdentifier: parameters.passType,
                    serialNumber: parameters.serial
                )
                return Response(status: .ok)
            } catch {
                return Self.serverError()
            }
        }

        // Changed-pass lookup. The device library identifier is the shared secret.
        router.get("/v1/devices/:deviceLibraryIdentifier/registrations/:passTypeIdentifier") { request, context -> Response in
            await stats.record()
            guard let device = context.parameters.get("deviceLibraryIdentifier"),
                  let passType = context.parameters.get("passTypeIdentifier") else {
                return Self.badRequest()
            }
            let cursor = request.uri.queryParameters["passesUpdatedSince"].flatMap { Int($0) }
            do {
                let result = try await service.updatedSerialNumbers(
                    deviceLibraryIdentifier: device,
                    passTypeIdentifier: passType,
                    since: cursor
                )
                guard let lastUpdated = result.lastUpdated, !result.serialNumbers.isEmpty else {
                    return Response(status: .noContent)
                }
                let body = ["serialNumbers": result.serialNumbers, "lastUpdated": String(lastUpdated)]
                return Self.json(body)
            } catch {
                return Self.serverError()
            }
        }

        // Pass download with conditional handling.
        router.get("/v1/passes/:passTypeIdentifier/:serialNumber") { request, context -> Response in
            await stats.record()
            guard let passType = context.parameters.get("passTypeIdentifier"),
                  let serial = context.parameters.get("serialNumber") else {
                return Self.badRequest()
            }
            guard let token = Self.passAuthorizationToken(request),
                  await service.validatePassToken(passTypeIdentifier: passType, serialNumber: serial, token: token) else {
                return Self.unauthorized()
            }
            guard let published = try? await service.publishedPass(serialNumber: serial) else {
                return Response(status: .notFound)
            }
            if let ifModifiedSince = request.headers[.ifModifiedSince],
               let clientDate = HTTPDate.parse(ifModifiedSince),
               published.publishedAt <= clientDate {
                var headers = HTTPFields()
                headers[.lastModified] = HTTPDate.format(published.publishedAt)
                return Response(status: .notModified, headers: headers)
            }
            var headers = HTTPFields()
            headers[.contentType] = "application/vnd.apple.pkpass"
            headers[.cacheControl] = "private, no-store, max-age=0"
            headers[.lastModified] = HTTPDate.format(published.publishedAt)
            return Response(status: .ok, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(bytes: published.archive)))
        }

        // Wallet logging. Untrusted; never persisted raw.
        router.post("/v1/log") { request, _ -> Response in
            await stats.record()
            _ = try? await request.body.collect(upTo: Self.maxBodyBytes)
            return Response(status: .ok)
        }

        // Installation (public, scoped, expiring).
        router.get("/install/:token") { _, context -> Response in
            await stats.record()
            guard let token = context.parameters.get("token"),
                  await service.archiveForInstallToken(token) != nil else {
                return Response(status: .notFound)
            }
            let hostname = await hostnameProvider() ?? "GymPass"
            return Self.installPage(token: token, hostname: hostname)
        }

        router.get("/install/:token/pass") { _, context -> Response in
            await stats.record()
            guard let token = context.parameters.get("token"),
                  let result = await service.archiveForInstallToken(token) else {
                return Response(status: .notFound)
            }
            var headers = HTTPFields()
            headers[.contentType] = "application/vnd.apple.pkpass"
            headers[.cacheControl] = "private, no-store, max-age=0"
            headers[.contentDisposition] = "attachment; filename=\"\(result.fileName)\""
            return Response(status: .ok, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(bytes: result.archive)))
        }

        return router
    }

    // MARK: - Helpers

    private static func registrationParameters(_ context: BasicRequestContext) -> (device: String, passType: String, serial: String)? {
        guard let device = context.parameters.get("deviceLibraryIdentifier"),
              let passType = context.parameters.get("passTypeIdentifier"),
              let serial = context.parameters.get("serialNumber") else {
            return nil
        }
        return (device, passType, serial)
    }

    private static func passAuthorizationToken(_ request: Request) -> String? {
        guard let authorization = request.headers[.authorization] else { return nil }
        let prefix = "ApplePass "
        guard authorization.hasPrefix(prefix) else { return nil }
        return String(authorization.dropFirst(prefix.count))
    }

    private static func json(_ value: [String: Any]) -> Response {
        let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data("{}".utf8)
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        headers[.cacheControl] = "no-store"
        return Response(status: .ok, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(bytes: data)))
    }

    private static func unauthorized() -> Response {
        var headers = HTTPFields()
        headers[.contentType] = "application/json"
        return Response(status: .unauthorized, headers: headers)
    }

    private static func badRequest() -> Response {
        Response(status: .badRequest)
    }

    private static func serverError() -> Response {
        Response(status: .internalServerError)
    }

    private static func installPage(token: String, hostname: String) -> Response {
        let html = """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="referrer" content="no-referrer">
        <title>Add GymPass to Wallet</title>
        <style>
        body{font-family:-apple-system,system-ui,sans-serif;background:#f5f5f7;color:#1d1d1f;margin:0;padding:40px;text-align:center}
        .card{max-width:420px;margin:0 auto;background:#fff;border-radius:18px;padding:32px;box-shadow:0 4px 24px rgba(0,0,0,.08)}
        h1{font-size:22px;margin:0 0 8px}p{color:#6e6e73;font-size:15px;line-height:1.5}
        a.button{display:inline-block;margin-top:20px;background:#6A35D4;color:#fff;text-decoration:none;padding:14px 24px;border-radius:12px;font-weight:600}
        </style></head><body><div class="card">
        <h1>Add GymPass to Wallet</h1>
        <p>Tap the button below to add your gym pass to Apple Wallet. This link expires shortly and can be used by anyone who has it.</p>
        <a class="button" href="/install/\(token)/pass">Add to Apple Wallet</a>
        <p style="margin-top:20px;font-size:12px">\(hostname)</p>
        </div></body></html>
        """
        var headers = HTTPFields()
        headers[.contentType] = "text/html; charset=utf-8"
        headers[.cacheControl] = "no-store"
        headers[HTTPField.Name("Content-Security-Policy")!] = "default-src 'none'; style-src 'unsafe-inline'"
        headers[HTTPField.Name("X-Content-Type-Options")!] = "nosniff"
        return Response(status: .ok, headers: headers, body: ResponseBody(byteBuffer: ByteBuffer(string: html)))
    }
}

extension Data {
    /// Decodes a lowercase or uppercase hex string, as used for APNs tokens.
    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0, !cleaned.isEmpty else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
