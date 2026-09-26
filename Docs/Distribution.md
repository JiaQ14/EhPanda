# App Identity and Internal Testing

Local device builds and TestFlight builds use the same app identity:

- App: `dev.ehpanda`
- Share extension: `dev.ehpanda.shareExtension`
- Tests: `dev.ehpanda.tests`

Keep these identifiers identical on `main` and development branches. Do not
rewrite the bundle identifier only in a temporary TestFlight source copy.
Local signing settings remain machine-specific and must not be committed.

## Compatibility

The URL scheme remains `ehpanda://`. Existing Spotlight domains, tab
customization identifiers, notification names, and thumbnail identifiers are
stable keys, not product bundle identifiers. Preserve them when changing the
app identity so existing installations of `dev.ehpanda` retain their state.

Old `app.ehpanda` installations have a separate data container. This change
does not migrate their settings or downloaded files. The historical
`AltStore.json` feed still describes upstream releases with the old identity;
do not relabel those existing IPA downloads as `dev.ehpanda`.

## TestFlight

Archive Release with a supported stable Xcode and automatic signing for the
logged-in developer team. Upload to App Store Connect app `6474061538` with
`method=app-store-connect` and `testFlightInternalTestingOnly=true`.
Distribute only to the personal internal testing group unless explicitly
requested otherwise.

Use a unique build number for each upload, for example by passing
`CURRENT_PROJECT_VERSION=<next-build-number>` to `xcodebuild archive`.
Include the source branch and commit in the TestFlight testing notes.
The personal internal testing group now tracks `main` only. After the new
main build is ready, add it to the group, then remove the superseded main
build and retired comparison builds from that group. Do not permanently
expire or delete their binaries as part of this replacement.

Branches sharing this bundle identifier cannot be installed side by side.
Switch between their builds using TestFlight's Previous Builds list. Treat
the data container as shared when switching: a future incompatible data
migration can make downgrading unsafe.
