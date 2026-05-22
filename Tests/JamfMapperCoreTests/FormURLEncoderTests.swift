import Foundation
import JamfMapperCore
import Testing

@Test func formEncoderEscapesOAuthSensitiveCharacters() async throws {
    let body = String(
        data: FormURLEncoder.encode([
            ("client_id", "abc 123"),
            ("grant_type", "client_credentials"),
            ("client_secret", "a+b&c=d/with space%")
        ]),
        encoding: .utf8
    )

    #expect(body == "client_id=abc+123&grant_type=client_credentials&client_secret=a%2Bb%26c%3Dd%2Fwith+space%25")
}
