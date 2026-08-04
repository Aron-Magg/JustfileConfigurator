# References

Official `just` documentation used to design this template.

- Manual (home): https://just.systems/man/en/
- Modules (`mod`, `mod?` optional since 1.52): https://just.systems/man/en/modules.html
- Recipe attributes (`[unix]`, `[windows]`, `[confirm]`): https://just.systems/man/en/attributes.html
- Settings (`shell`, `working-directory`, `dotenv-load`): https://just.systems/man/en/settings.html
- Functions (`justfile_directory`, path `/` operator): https://just.systems/man/en/functions.html
- Changelog / releases: https://github.com/casey/just/releases

Notes:
- The deprecated `windows-shell` / `windows-powershell` settings are replaced here by the
  `[windows]` recipe attribute.
- Optional modules (`mod?`) require `just` ≥ 1.52.
- Settings values must be constant, so `set working-directory := justfile_directory()` is
  invalid; modules use a literal relative path (`set working-directory := '../..'`) instead.

## Credits

- Suggestion from [Else00](https://github.com/Else00).
