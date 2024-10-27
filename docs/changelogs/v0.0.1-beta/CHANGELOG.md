# Changelog

All notable changes to this project are documented here.

## [0.0.1-beta] - 2024-10-27

### 🚀 Features

- *(error)* Implement $env.nuitron_error_exit_code
- *(fmt)* Add more style schemes
- *(parse-error)* Add support for NonZeroExitCode
- *(say)* Implement $env.nuitron_shut_up
- *(parse-error)* Support DidYouMean and DateTimeParseError

### 🐛 Bug Fixes

- *(fmt)* [**breaking**] Rename fmt to ft to avoid conflict with built-in fmt

### 📚 Documentation

- *(fmt)* Add command description

### ⚙️ Miscellaneous Tasks

- Add commit linting for pushes and PRs
- Adopt git-cliff to generate changelogs

### ◀️ Revert

- [**breaking**] Deprecate get-os-path-separator

