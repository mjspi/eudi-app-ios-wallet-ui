# Keyless SDK Developer Setup

The `keyless.mobile-sdk` Swift package is hosted on a private Cloudsmith registry.
Before Xcode or `xcodebuild` can resolve this dependency you must perform a one-time
per-machine setup to register the registry scope and authenticate with your download token.

## One-time setup

Run the following two commands in your terminal (replace `<YOUR_DOWNLOAD_TOKEN>` with
the token you obtain from the team's credential store or an admin):

```sh
swift package-registry set --global --scope keyless https://swift.cloudsmith.io/keyless/partners/
swift package-registry login https://swift.cloudsmith.io/keyless/partners/ --token <YOUR_DOWNLOAD_TOKEN>
```

The first command registers the `keyless` scope globally so Swift Package Manager knows
which registry URL to use for any package whose identity starts with `keyless.`.

The second command stores your credentials in the macOS Keychain (via the system credential
store) — the token is never written to disk in plaintext and must not be committed to source
control.

## Obtaining the token

Contact the team admin or retrieve it from the shared credential store. The token is a
read-only download credential for the Cloudsmith `keyless/partners` repository.

## CI / automated environments

For CI pipelines, set the token as a secret environment variable and pass it with:

```sh
swift package-registry login https://swift.cloudsmith.io/keyless/partners/ --token "$KEYLESS_DOWNLOAD_TOKEN"
```

Run this step before any `xcodebuild` or `swift build` invocation that resolves packages.

## Verifying the setup

After running the setup commands, open the Xcode project (or run
`xcodebuild -resolvePackageDependencies`) and confirm that `KeylessSDKPackage` appears in
the resolved packages list without authentication errors.
