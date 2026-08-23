# Releasing a signed build

Redline ships as source because a downloadable binary has to be notarized or
Gatekeeper refuses to open it at all. `scripts/release.sh` does the whole
signed, notarized, stapled DMG flow. It needs two pieces of one-time setup:

1. A **Developer ID Application** certificate, free with an Apple Developer
   membership. developer.apple.com/account, Certificates, +, then download the
   `.cer` and double-click to install it.
2. Stored notary credentials, using an app-specific password from
   appleid.apple.com:

```
xcrun notarytool store-credentials redline-notary \
  --apple-id <your-apple-id> --team-id <YOUR_TEAM_ID> --password <app-specific-password>
```

Then each release is:

```
./scripts/release.sh 1.2
gh release upload v1.2 build/dist/Redline-1.2.dmg --clobber
```

Both `notarytool` and `stapler` ship with the Xcode Command Line Tools, so full
Xcode is not required here either. The certificate is the only missing piece.

Run for v1.1 and accepted by Apple on the first attempt. The hardened runtime
does not interfere with the `dlopen` of IOKit, which was the step most likely to
be rejected.

If `security find-identity` shows zero identities right after installing a
certificate, the usual cause is a missing Apple intermediate rather than
anything wrong with the certificate. The leaf names its own intermediate in its
AIA field, `certs.apple.com/devidg2.der` for a G2 Developer ID.
