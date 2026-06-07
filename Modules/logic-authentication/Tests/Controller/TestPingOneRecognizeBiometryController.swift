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

final class TestPingOneRecognizeBiometryController: EudiTest {

  // MARK: - Helpers

  /// A config with an empty apiKey — simulates an unconfigured developer machine.
  private func makeEmptyConfig() -> PingOneRecognizeConfig {
    // PingOneRecognizeConfig reads from Bundle.main.infoDictionary.
    // In the test process, Keyless API Key is not set, so apiKey will be "".
    return PingOneRecognizeConfig()
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

  // MARK: - requestBiometricUnlock — Keyless SDK paths
  //
  // The success and SDK-failure paths (Keyless.authenticate() callback returning
  // .success or .failure) cannot be unit-tested without calling the real Keyless
  // SDK, which requires a configured server-side tenant and a device enrolled with
  // PingOne Recognize. These paths are covered at the integration level (running
  // the app against a real PingOne Recognize tenant). The pre-configure fast-fail
  // path above confirms the withCheckedThrowingContinuation bridge is correct for
  // the guard-exit branch; the continuation bridge itself is a standard Swift
  // concurrency pattern with no logic to cover beyond what the SDK callback provides.
}
