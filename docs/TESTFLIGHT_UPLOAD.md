# TestFlight Upload

Use this repo-local script for PingMobile TestFlight uploads:

```bash
scripts/upload-testflight.sh --bump-build
```

If App Store Connect has closed the current pre-release train, open a new train by bumping the iOS marketing version:

```bash
scripts/upload-testflight.sh --marketing-version 0.1.2 --bump-build
```

Stored non-secret App Store Connect defaults:

- API key ID: `TMC3PCHDCF`
- Issuer ID: `0d693e18-2317-4107-8b26-26afd98e64ae`
- Team ID: `878FAHTFQJ`
- Private key path: `~/.appstoreconnect/private_keys/AuthKey_TMC3PCHDCF.p8`

The `.p8` private key is intentionally not committed.
