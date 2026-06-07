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

@preconcurrency import LocalAuthentication
import KeylessSDK
import os.log

private let keylessLogger = Logger(subsystem: "eudi.wallet", category: "PingOneRecognize")

/// Abstraction over `Keyless.authenticate(configuration:onCompletion:)` that enables
/// injection of a test double in unit tests.
///
/// The completion handler uses `Result<Void, Error>` rather than the SDK's concrete
/// `Result<Keyless.AuthenticationSuccess, KeylessSDKError>`, and no `AuthConfig`
/// parameter is exposed, so that conformers outside the `logic-authentication` module
/// (such as test targets that do not link `KeylessSDK`) can implement the protocol
/// without importing `KeylessSDK`.
///
/// The live implementation always passes `BiomAuthConfig()` to the SDK, matching
/// the behaviour of the original direct call in `requestBiometricUnlock()`.
protocol KeylessAuthenticating: Sendable {
  func authenticate(onCompletion: @escaping @Sendable (Result<Void, Error>) -> Void)
  func enroll(onCompletion: @escaping @Sendable (Result<Void, Error>) -> Void)
}

/// Live implementation that delegates directly to `Keyless.authenticate(...)` and `Keyless.enroll(...)`.
struct LiveKeylessAuthenticator: KeylessAuthenticating {
  let externalUserId: String

  func authenticate(onCompletion: @escaping @Sendable (Result<Void, Error>) -> Void) {
    let operationInfo = externalUserId.isEmpty
      ? nil
      : Keyless.OperationInfo(id: UUID().uuidString, externalUserId: externalUserId)
    let authConfig = BiomAuthConfig(
      livenessConfiguration: .LEVEL_1,
      operationInfo: operationInfo,
      presentationStyle: .noCameraPreview
    )
    Keyless.authenticate(configuration: authConfig) { result in
      switch result {
      case .success:
        onCompletion(.success(()))
      case .failure(let error):
        keylessLogger.error("Keyless.authenticate() failed — \(error.localizedDescription, privacy: .public)")
        onCompletion(.failure(error))
      }
    }
  }

  func enroll(onCompletion: @escaping @Sendable (Result<Void, Error>) -> Void) {
    let operationInfo = externalUserId.isEmpty
      ? nil
      : Keyless.OperationInfo(id: UUID().uuidString, externalUserId: externalUserId)
    let enrollConfig = BiomEnrollConfig(
      operationInfo: operationInfo,
      livenessConfiguration: .LEVEL_1,
      presentationStyle: .fullScreen
    )
    Keyless.enroll(configuration: enrollConfig) { result in
      switch result {
      case .success:
        onCompletion(.success(()))
      case .failure(let error):
        keylessLogger.error("Keyless.enroll() failed — \(error.localizedDescription, privacy: .public)")
        onCompletion(.failure(error))
      }
    }
  }
}

/// Calls `Keyless.configure()` once at app startup.
///
/// This entry point lives in `logic-authentication` so that `AppDelegate` (which does not
/// link `KeylessSDK` directly) can trigger SDK initialisation through the module's public API
/// without needing a direct `import KeylessSDK`.
///
/// - Parameter config: The runtime `PingOneRecognizeConfig` read from `Bundle.main.infoDictionary`.
///   When `config.apiKey` is empty the call is a no-op; `Keyless.configure()` is not invoked.
public func configureKeylessSDK(with config: PingOneRecognizeConfig) {
  guard !config.apiKey.isEmpty else {
    print("[PingOneRecognize] configureKeylessSDK: apiKey is empty — skipping")
    keylessLogger.warning("configureKeylessSDK: apiKey is empty — skipping Keyless.configure()")
    return
  }
  print("[PingOneRecognize] configureKeylessSDK: apiKey=\(config.apiKey.prefix(8))… hosts=\(config.hosts)")
  keylessLogger.info("configureKeylessSDK: configuring with hosts: \(config.hosts.joined(separator: ","), privacy: .public)")
  let customLogs = CustomLogsConfiguration(
    enabled: true,
    logLevel: SetupConfig.DEFAULT_LOGGING_LEVEL,
    callback: { event in
      keylessLogger.debug("[KeylessSDK] \(event.eventType, privacy: .public)")
    }
  )
  let setupConfig = SetupConfig(
    apiKey: config.apiKey,
    hosts: config.hosts,
    customLogsConfiguration: customLogs
  )
  Keyless.configure(setupConfiguration: setupConfig) { error in
    if let error {
      print("[PingOneRecognize] Keyless.configure() FAILED: \(error)")
      keylessLogger.error("configureKeylessSDK: Keyless.configure() failed — \(error.localizedDescription, privacy: .public)")
    } else {
      print("[PingOneRecognize] Keyless.configure() succeeded")
      keylessLogger.info("configureKeylessSDK: Keyless.configure() succeeded")
    }
  }
}

final actor PingOneRecognizeBiometryController: SystemBiometryController {

  private let config: PingOneRecognizeConfig
  private let authenticator: any KeylessAuthenticating

  init(
    config: PingOneRecognizeConfig,
    authenticator: (any KeylessAuthenticating)? = nil
  ) {
    self.config = config
    self.authenticator = authenticator ?? LiveKeylessAuthenticator(externalUserId: config.externalUserId)
  }

  public func getBiometryType() async -> LABiometryType {
    .none
  }

  public func isBiometryAvailable() async -> Bool {
    true
  }

  public func openSettings(action: @escaping @Sendable () -> Void) async {
    // no-op: PingOne Recognize has no OS-level permission that requires Settings
  }

  public func requestBiometricUnlock() async throws {
    let apiKey = config.apiKey
    let userId = config.externalUserId
    let auth = authenticator
    guard !apiKey.isEmpty else {
      keylessLogger.error("requestBiometricUnlock: apiKey is empty — failing immediately")
      throw SystemBiometryError.biometricError
    }
    print("[PingOneRecognize] requestBiometricUnlock: isEnrolled=\(Keyless.isEnrolled) user=\(userId)")
    keylessLogger.info("requestBiometricUnlock: isEnrolled=\(Keyless.isEnrolled) user=\(userId, privacy: .public)")
    if !Keyless.isEnrolled {
      print("[PingOneRecognize] not enrolled — starting enrollment")
      keylessLogger.info("requestBiometricUnlock: not enrolled — starting enrollment")
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        auth.enroll { result in
          switch result {
          case .success:
            print("[PingOneRecognize] enrollment succeeded")
            continuation.resume()
          case .failure(let error):
            print("[PingOneRecognize] enrollment FAILED: \(error)")
            continuation.resume(throwing: SystemBiometryError.biometricError)
          }
        }
      }
    }
    print("[PingOneRecognize] calling authenticate for user: \(userId)")
    keylessLogger.info("requestBiometricUnlock: calling authenticate for user: \(userId, privacy: .public)")
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      auth.authenticate { result in
        switch result {
        case .success:
          print("[PingOneRecognize] authenticate succeeded")
          continuation.resume()
        case .failure(let error):
          print("[PingOneRecognize] authenticate FAILED: \(error)")
          continuation.resume(throwing: SystemBiometryError.biometricError)
        }
      }
    }
  }
}
