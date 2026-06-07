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

final actor PingOneRecognizeBiometryController: SystemBiometryController {

  private let config: PingOneRecognizeConfig

  init(config: PingOneRecognizeConfig) {
    self.config = config
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
    guard !config.apiKey.isEmpty else {
      throw SystemBiometryError.biometricError
    }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      Keyless.authenticate(
        configuration: BiomAuthConfig(),
        onCompletion: { result in
          switch result {
          case .success:
            continuation.resume()
          case .failure:
            continuation.resume(throwing: SystemBiometryError.biometricError)
          }
        }
      )
    }
  }
}
