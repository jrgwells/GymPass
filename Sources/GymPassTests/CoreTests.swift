import Foundation
import GymPassCore
import GymPassShared

func coreTestCases() -> [TestCase] {
    [
        TestCase("scheduler.balancedHonoursFloor") { context in
            let policy = RefreshPolicy(mode: .balanced, floorIntervalSeconds: 300)
            let now = Date()
            let qr = QRStatus(present: true, retrievedAt: now, expiresAt: now.addingTimeInterval(7 * 24 * 3600), refreshAfter: now.addingTimeInterval(60))
            let delay = RefreshScheduler.nextDelay(policy: policy, qr: qr, failures: 0, hasPublishedPass: true, jitter: 0)
            context.expectEqual(delay, 300)
        },
        TestCase("scheduler.conservativeUsesExpiry") { context in
            let policy = RefreshPolicy(mode: .conservative, floorIntervalSeconds: 300, expirySafetyMarginSeconds: 3600)
            let now = Date()
            let qr = QRStatus(present: true, retrievedAt: now, expiresAt: now.addingTimeInterval(7200), refreshAfter: now.addingTimeInterval(60))
            let delay = RefreshScheduler.nextDelay(policy: policy, qr: qr, failures: 0, hasPublishedPass: true, jitter: 0)
            context.expect(delay > 3500 && delay <= 3600, "expected ~1h, got \(delay)")
        },
        TestCase("scheduler.backoffIsBoundedAndIncreasing") { context in
            let policy = RefreshPolicy(floorIntervalSeconds: 300)
            let first = RefreshScheduler.nextDelay(policy: policy, qr: nil, failures: 1, hasPublishedPass: false, jitter: 0)
            let later = RefreshScheduler.nextDelay(policy: policy, qr: nil, failures: 20, hasPublishedPass: false, jitter: 0)
            context.expectEqual(first, 600)
            context.expect(later <= RefreshScheduler.maximumDelay, "backoff exceeded maximum")
            context.expect(later > first, "backoff did not increase")
        },
        TestCase("scheduler.clampedToMinimum") { context in
            let policy = RefreshPolicy(floorIntervalSeconds: 1)
            let delay = RefreshScheduler.nextDelay(policy: policy, qr: nil, failures: 0, hasPublishedPass: false, jitter: 0)
            context.expectEqual(delay, RefreshScheduler.minimumDelay)
        },
        TestCase("scheduler.immediateTriggers") { context in
            context.expect(RefreshTrigger.manual.isImmediate)
            context.expect(RefreshTrigger.startup.isImmediate)
            context.expect(!RefreshTrigger.scheduled.isImmediate)
        },
        TestCase("redactor.removesPlantedSecrets") { context in
            let input = """
            user=athlete@example.com authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc.def
            code=exerp:checkin:1234-5678-9abc url=https://x/install/AbCdEfGhIjKlMnOpQrStUvWxYz012345
            X-GymPass-Control-Token: super-secret-control-token
            ApplePass abcdef1234567890
            """
            let output = Redactor.redact(input)
            context.expect(!output.contains("athlete@example.com"))
            context.expect(!output.contains("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.abc.def"))
            context.expect(!output.contains("exerp:checkin:1234-5678-9abc"))
            context.expect(!output.contains("AbCdEfGhIjKlMnOpQrStUvWxYz012345"))
            context.expect(!output.contains("super-secret-control-token"))
        },
        TestCase("redactor.urlDropsSensitiveQuery") { context in
            let url = URL(string: "https://example.com/v1/devices/D?passesUpdatedSince=99&token=secret")!
            let redacted = Redactor.redact(url: url)
            context.expect(!redacted.contains("secret"))
            context.expect(!redacted.contains("99"))
        },
        TestCase("puregym.qrDecoding") { context in
            let json = """
            {"QrCode":"exerp:checkin:abc-1723637307-deadbeef","RefreshAt":"2025-08-14T12:08:27.4349618Z","ExpiresAt":"2025-08-21T12:02:27.4349618Z","RefreshIn":"0:01:00","ExpiresIn":"167:55:00"}
            """
            let qr = try JSONDecoder().decode(PureGymQRCode.self, from: Data(json.utf8))
            context.expectEqual(qr.code, "exerp:checkin:abc-1723637307-deadbeef")
            context.expectEqual(qr.refreshIn, 60)
            context.expectEqual(qr.expiresIn, 167 * 3600 + 55 * 60)
            context.expectNotNil(qr.refreshAt)
            context.expectNotNil(qr.expiresAt)
        },
        TestCase("puregym.gymDecoding") { context in
            let json = """
            [{"id":318,"name":"Yeovil","latitude":"50.945449","longitude":"-2.671796"},{"id":234,"name":"Bagshot","latitude":null,"longitude":null}]
            """
            let gyms = try JSONDecoder().decode([PureGymGym].self, from: Data(json.utf8))
            context.expectEqual(gyms.count, 2)
            context.expectEqual(gyms[0].latitude, 50.945449)
            context.expectNil(gyms[1].latitude)
        },
        TestCase("puregym.longDurations") { context in
            context.expectEqual(GymPassDate.parseDuration("167:55:00"), 167 * 3600 + 55 * 60)
            context.expectEqual(GymPassDate.parseDuration("1:02:03:04"), (24 + 2) * 3600 + 3 * 60 + 4)
        },
        TestCase("crypto.roundTripAndTamper") { context in
            let box = CryptoBox(key: CryptoBox.randomKey())
            let sealed = try box.seal("hello world")
            context.expectEqual(try box.openString(sealed), "hello world")
            var tampered = sealed
            tampered[tampered.count - 1] ^= 0xFF
            context.expectThrows("tampered ciphertext should not decrypt") {
                _ = try box.open(tampered)
            }
        },
        TestCase("crypto.wrongKeyFails") { context in
            let sealed = try CryptoBox(key: CryptoBox.randomKey()).seal("secret")
            context.expectThrows("wrong key should fail") {
                _ = try CryptoBox(key: CryptoBox.randomKey()).open(sealed)
            }
        },
    ]
}
