# Checking a theme's settings file in CI

Theme repos can check their `ThemeSettings.plist` on every push and pull
request with the validator from this repo. Errors fail the job, because an
error means every editor would skip that setting or reject the file.
Warnings don't fail it.

1. Copy [`examples/ci/validate-theme-settings.yml`](../examples/ci/validate-theme-settings.yml)
   to `.github/workflows/` in the theme's repo.
2. Set `THEME_PATH` to the `.theme` bundle (or the `ThemeSettings.plist`)
   in that repo, and `GTS_COMMIT` to the gnustep-themes commit to pin.
3. Push. The job installs GNUstep base and make on Debian 13, fetches the
   pinned validator, builds it and runs `scripts/validate-theme.sh`.

The validator is Foundation-only. It reads the file as a text property list
and never builds or loads the theme's own code, so it needs neither AppKit
nor the theme's dependencies. The same check, locally:

```sh
git clone https://github.com/danjboyd/gnustep-themes
gnustep-themes/scripts/validate-theme.sh path/to/MyTheme.theme
```

Exit status: 0 means no errors, 1 means errors, 2 means a usage or build
problem. The rules are in [schema-v1.md](schema-v1.md).
