import Foundation
import GymPassCore
import GymPassShared

private struct ServerHarness {
    let db: DatabaseManager
    let service: WalletService
    let server: WalletHTTPServer
    let port: Int
    let passToken: String
    let serial = "SERIAL-1"
    let passType = "pass.com.jackwells.gympass.test"
}

private func startServer() async throws -> ServerHarness {
    let path = FileManager.default.temporaryDirectory
        .appendingPathComponent("gympass-server-\(UUID().uuidString).sqlite").path
    let db = try DatabaseManager(path: path)
    try await db.migrate()
    let crypto = CryptoBox(key: CryptoBox.randomKey())
    let service = WalletService(db: db, secrets: InMemorySecretStore(), crypto: crypto)
    try await service.setPassIdentity(passTypeIdentifier: "pass.com.jackwells.gympass.test", serialNumber: "SERIAL-1", teamIdentifier: "TESTTEAM123")
    let token = try await service.ensurePassToken(serialNumber: "SERIAL-1")

    let state = PassState(
        serialNumber: "SERIAL-1",
        passTypeIdentifier: "pass.com.jackwells.gympass.test",
        revision: 1,
        contentHash: "identity",
        archiveBlob: try crypto.seal(Data("PKPASS-BYTES".utf8)),
        publishedAt: Date(),
        lastModifiedHTTP: HTTPDate.format(Date()),
        lastGeneratedAt: Date(),
        lastWalletChangeAt: nil
    )
    try await db.publish(state, outbox: [])

    let port = 18000 + Int.random(in: 0..<2000)
    let server = WalletHTTPServer(host: "127.0.0.1", port: port, service: service, stats: ServerStats())
    try await server.start()
    try await waitForHealth(port: port)
    return ServerHarness(db: db, service: service, server: server, port: port, passToken: token)
}

private func waitForHealth(port: Int) async throws {
    let url = URL(string: "http://127.0.0.1:\(port)/health")!
    for _ in 0..<50 {
        if let (_, response) = try? await URLSession.shared.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            return
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw GymPassError.internalError("Server did not become ready")
}

private struct HTTPCall {
    let status: Int
    let body: Data
    let response: HTTPURLResponse
}

private func call(_ method: String, _ path: String, port: Int, token: String? = nil, body: Data? = nil, headers: [String: String] = [:]) async throws -> HTTPCall {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
    request.httpMethod = method
    request.httpBody = body
    if let token { request.setValue("ApplePass \(token)", forHTTPHeaderField: "Authorization") }
    for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw GymPassError.transport("No HTTP response")
    }
    return HTTPCall(status: http.statusCode, body: data, response: http)
}

func serverTestCases() -> [TestCase] {
    [
        TestCase("server.fullRegistrationAndDownloadFlow") { context in
            let harness = try await startServer()
            defer { Task { await harness.server.stop() } }
            let port = harness.port

            let health = try await call("GET", "/health", port: port)
            context.expectEqual(health.status, 200)
            context.expect(String(data: health.body, encoding: .utf8)?.contains("ok") == true)

            context.expectEqual(try await call("GET", "/v1/passes/\(harness.passType)/\(harness.serial)", port: port).status, 401)
            context.expectEqual(try await call("GET", "/v1/passes/\(harness.passType)/\(harness.serial)", port: port, token: "nope").status, 401)

            let pushBody = Data("{\"pushToken\":\"aabbccdd\"}".utf8)
            let created = try await call("POST", "/v1/devices/DEV-1/registrations/\(harness.passType)/\(harness.serial)", port: port, token: harness.passToken, body: pushBody, headers: ["Content-Type": "application/json"])
            context.expectEqual(created.status, 201)

            let existing = try await call("POST", "/v1/devices/DEV-1/registrations/\(harness.passType)/\(harness.serial)", port: port, token: harness.passToken, body: pushBody, headers: ["Content-Type": "application/json"])
            context.expectEqual(existing.status, 200)

            let malformed = try await call("POST", "/v1/devices/DEV-2/registrations/\(harness.passType)/\(harness.serial)", port: port, token: harness.passToken, body: Data("{\"pushToken\":\"zzzz\"}".utf8), headers: ["Content-Type": "application/json"])
            context.expectEqual(malformed.status, 400)

            let lookup = try await call("GET", "/v1/devices/DEV-1/registrations/\(harness.passType)", port: port)
            context.expectEqual(lookup.status, 200)
            let lookupObject = try JSONSerialization.jsonObject(with: lookup.body) as? [String: Any]
            context.expect((lookupObject?["serialNumbers"] as? [String])?.contains(harness.serial) == true, "lookup should include the serial")
            context.expectEqual(lookupObject?["lastUpdated"] as? String, "1")

            let noContent = try await call("GET", "/v1/devices/DEV-1/registrations/\(harness.passType)?passesUpdatedSince=1", port: port)
            context.expectEqual(noContent.status, 204)

            let download = try await call("GET", "/v1/passes/\(harness.passType)/\(harness.serial)", port: port, token: harness.passToken)
            context.expectEqual(download.status, 200)
            context.expectEqual(download.body, Data("PKPASS-BYTES".utf8))
            context.expectEqual(download.response.value(forHTTPHeaderField: "Content-Type"), "application/vnd.apple.pkpass")

            let future = HTTPDate.format(Date().addingTimeInterval(3600))
            let notModified = try await call("GET", "/v1/passes/\(harness.passType)/\(harness.serial)", port: port, token: harness.passToken, headers: ["If-Modified-Since": future])
            context.expectEqual(notModified.status, 304)

            context.expectEqual(try await call("DELETE", "/v1/devices/DEV-1/registrations/\(harness.passType)/\(harness.serial)", port: port, token: harness.passToken).status, 200)
            context.expectEqual(try await call("GET", "/admin/secrets", port: port).status, 404)

            await harness.server.stop()
        },
        TestCase("server.installationLinkServesPass") { context in
            let harness = try await startServer()
            defer { Task { await harness.server.stop() } }
            let link = try await harness.service.createInstallLink(hostname: "wallet.example.com")
            let port = harness.port

            let page = try await call("GET", "/install/\(link.token)", port: port)
            context.expectEqual(page.status, 200)
            let html = String(data: page.body, encoding: .utf8) ?? ""
            context.expect(html.contains("Add to Apple Wallet"), "install page should mention Wallet")
            context.expect(!html.contains("exerp:checkin"), "install page must not leak the gym code")

            let pass = try await call("GET", "/install/\(link.token)/pass", port: port)
            context.expectEqual(pass.status, 200)
            context.expectEqual(pass.body, Data("PKPASS-BYTES".utf8))
            context.expectEqual(pass.response.value(forHTTPHeaderField: "Content-Type"), "application/vnd.apple.pkpass")

            context.expectEqual(try await call("GET", "/install/unknown-token", port: port).status, 404)
            await harness.server.stop()
        },
    ]
}
