/*
 * Copyright (c) 2026 European Commission
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * You may obtain a copy of the Licence at:
 * https://joinup.ec.europa.eu/software/page/eupl
 *
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the Licence is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF
 * ANY KIND, either express or implied. See the Licence for the specific language
 * governing permissions and limitations under the Licence.
 */

import XCTest
@testable import logic_test
@testable import logic_authentication

// MARK: - Test double

/// Drives `KeylessAuthenticating` from a test with a pre-wired result.
///
/// The result is captured as `Result<Void, Error>` so this conformer does not need
/// to import `KeylessSDK` — the protocol intentionally avoids exposing SDK-specific
/// types at its boundary.
private final class StubKeylessAuthenticator: KeylessAuthenticating, @unchecked Sendable {

  let stubbedResult: Result<Void, Error>

  init(result: Result<Void, Error>) {
    self.stubbedResult = result
  }

  func authenticate(onCompletion: @escaping @Sendable (Result<Void, Error>) -> Void) {
    onCompletion(stubbedResult)
  }
}

final class TestPingOneRecognizeBiometryController: EudiTest {

  // MARK: - Helpers

  /// A config with an empty apiKey — simulates an unconfigured developer machine.
  private func makeEmptyConfig() -> PingOneRecognizeConfig {
    // PingOneRecognizeConfig reads from Bundle.main.infoDictionary.
    // In the test process, Keyless API Key is not set, so apiKey will be "".
    return PingOneRecognizeConfig()
  }

  /// A config with a non-empty apiKey — used to let execution reach the
  /// `Keyless.authenticate` call so the injected test double can respond.
  private func makeConfiguredConfig() -> PingOneRecognizeConfig {
    PingOneRecognizeConfig(apiKey: "test-api-key", hosts: [])
  }

  // MARK: - getBiometryType

  func testGetBiometryType_AlwaysReturnsNone() async {
    // Given
    let controller = PingOneRecognizeBiometryController(config: makeEmptyConfig())

    // When
    let type = await controller.getBiometryType()

    // Then
    XCTAssertEqual(type, .none)
  }

  // MARK: - isBiometryAvailable

  func testIsBiometryAvailable_AlwaysReturnsTrue() async {
    // Given
    let controller = PingOneRecognizeBiometryController(config: makeEmptyConfig())

    // When
    let available = await controller.isBiometryAvailable()

    // Then
    XCTAssertTrue(available)
  }

  // MARK: - openSettings

  func testOpenSettings_DoesNotCallAction() async {
    // Given
    let controller = PingOneRecognizeBiometryController(config: makeEmptyConfig())
    // Use a class-based flag to avoid Sendable mutation warnings with @Sendable closure capture
    final class ActionFlag: @unchecked Sendable { var called = false }
    let flag = ActionFlag()

    // When
    await controller.openSettings(action: { flag.called = true })

    // Then: openSettings is a no-op; the action must not be called
    XCTAssertFalse(flag.called, "openSettings(action:) must be a no-op for PingOne Recognize")
  }

  // MARK: - requestBiometricUnlock — pre-configure failure path

  func testRequestBiometricUnlock_WhenApiKeyIsEmpty_ThrowsBiometricError() async {
    // Given: config with empty apiKey (unconfigured developer machine / extension process
    // where Keyless.configure() has never been called)
    let controller = PingOneRecognizeBiometryController(config: makeEmptyConfig())

    // When / Then
    do {
      try await controller.requestBiometricUnlock()
      XCTFail("Expected requestBiometricUnlock to throw when apiKey is empty")
    } catch let error as SystemBiometryError {
      XCTAssertEqual(error, .biometricError,
        "Expected .biometricError when apiKey is empty, got \(error)")
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }

  // MARK: - requestBiometricUnlock — Keyless SDK callback paths

  func testRequestBiometricUnlock_WhenAuthenticatorSucceeds_DoesNotThrow() async {
    // Given: config with a non-empty apiKey (passes the guard) and a stub that
    // fires .success immediately — simulates the Keyless SDK returning a
    // successful authentication result.
    let stub = StubKeylessAuthenticator(result: .success(()))
    let controller = PingOneRecognizeBiometryController(
      config: makeConfiguredConfig(),
      authenticator: stub
    )

    // When / Then: no error thrown
    do {
      try await controller.requestBiometricUnlock()
    } catch {
      XCTFail("Expected requestBiometricUnlock to succeed, got error: \(error)")
    }
  }

  func testRequestBiometricUnlock_WhenAuthenticatorFails_ThrowsBiometricError() async {
    // Given: config with a non-empty apiKey (passes the guard) and a stub that
    // fires .failure — simulates the Keyless SDK returning an authentication error.
    struct StubSDKError: Error {}
    let stub = StubKeylessAuthenticator(result: .failure(StubSDKError()))
    let controller = PingOneRecognizeBiometryController(
      config: makeConfiguredConfig(),
      authenticator: stub
    )

    // When / Then: throws SystemBiometryError.biometricError
    do {
      try await controller.requestBiometricUnlock()
      XCTFail("Expected requestBiometricUnlock to throw when authenticator fails")
    } catch let error as SystemBiometryError {
      XCTAssertEqual(error, .biometricError,
        "Expected .biometricError when Keyless SDK callback returns .failure, got \(error)")
    } catch {
      XCTFail("Unexpected error type: \(error)")
    }
  }
}
