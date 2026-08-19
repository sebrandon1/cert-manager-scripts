# Contributing Guide

Thank you for contributing to cert-manager-scripts! This guide will help you get started.

## Development Setup

1. **Fork and clone the repository:**
   ```bash
   git clone https://github.com/YOUR_USERNAME/cert-manager-scripts.git
   cd cert-manager-scripts
   ```

2. **Install prerequisites:**
   - `oc` CLI tool
   - `envsubst` (gettext package)
   - `shfmt` for shell script formatting
   - Access to an OpenShift cluster for testing

3. **Install shfmt:**
   ```bash
   # macOS
   brew install shfmt
   
   # Linux
   go install mvdan.cc/sh/v3/cmd/shfmt@latest
   
   # Or download from releases
   # https://github.com/mvdan/sh/releases
   ```

## Making Changes

### Code Style

All shell scripts must follow consistent formatting using `shfmt`:

```bash
# Check formatting + shellcheck (what you should run locally)
make lint

# Auto-format scripts
make fmt

# Format a specific file
shfmt -w scripts/your-script.sh
```

**Formatting rules:**
- 2-space indentation
- Binary operators at start of line allowed
- Switch cases indented

### Testing Your Changes

Before submitting a pull request:

1. **Format and lint check:**
   ```bash
   make lint
   ```

2. **Test on a real cluster:**
   ```bash
   # Log into your test cluster
   oc login <cluster-url>
   
   # Run the affected scripts
   ./scripts/your-modified-script.sh
   
   # Or test the complete workflow
   make install-cert-manager-operator
   make quick-http-test
   ```

3. **Verify cleanup works:**
   ```bash
   make clean
   ```

4. **Test idempotency:**
   ```bash
   # Run your script twice to ensure it's idempotent
   ./scripts/your-script.sh
   ./scripts/your-script.sh  # Should succeed without errors
   ```

## Pull Request Process

1. **Create a feature branch:**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make your changes and commit:**
   ```bash
   git add .
   git commit -m "Add feature: description of your changes"
   ```

3. **Push to your fork:**
   ```bash
   git push origin feature/your-feature-name
   ```

4. **Open a Pull Request** on GitHub

5. **Ensure CI passes:**
   - `make lint` (shfmt + shellcheck)
   - Integration tests (Kind always; OCP needs `CRC_PULL_SECRET`)

### Pull Request Checklist

- [ ] `make lint` passes (shfmt + shellcheck)
- [ ] Tested on a real OpenShift cluster
- [ ] Scripts are idempotent (can run multiple times safely)
- [ ] Documentation updated (README.md or relevant .md files)
- [ ] Troubleshooting notes added for common issues
- [ ] Makefile targets added/updated if applicable
- [ ] Error messages are clear and helpful
- [ ] Scripts have proper error handling (`set -euo pipefail`)

## Continuous Integration

This repository uses GitHub Actions to automatically test changes.

### Workflow: `pre-main.yml`

Runs on every push and pull request to `main`:

1. **Shell format check** — `shfmt -d scripts/ lib/`
2. **ShellCheck** — `shellcheck --severity=error` on `scripts/` and `lib/`
3. **Workload partitioning check** — script present, executable, valid syntax
4. **Structure check** — directory layout, key files, script references
5. **Version query check** — pebble, acme-dns, operator, minio, ubi9-python
6. **Kind integration test** — cert-manager v1.19.0 and v1.20.0
7. **OCP integration test** — CRC via [quick-ocp](https://github.com/palmsoftware/quick-ocp), matrix of OCP 4.20/4.21/4.22 × cert-manager v1.19.0/v1.20.0. Runs `make quick-http-test` (HTTP-01, not DNS-01), API server cert verification, workload partitioning, and network stack detection. Skipped for dependabot.

OCP integration tests need the `CRC_PULL_SECRET` GitHub secret (upstream only). See [CI cluster health](docs/CRC-CLUSTER-HEALTH-IMPROVEMENTS.md) for the CRC health-check flow.

### Running CI Tests Locally

You can run the same checks that CI runs:

```bash
# Format check (always run this before committing)
make lint

# Integration test (requires OpenShift cluster access)
make install-cert-manager-operator
make quick-http-test
```

### CI Failure Troubleshooting

If CI fails:

1. **Format or ShellCheck failure:**
   - Run `make fmt` then `make lint`
   - Commit the formatting changes

2. **Integration test failure:**
   - Check the CI logs for specific errors
   - See [Troubleshooting](docs/troubleshooting.md) for common issues
   - Test locally on your cluster to reproduce
   - Ask for help in the PR comments

## Documentation

### When to Update Documentation

Update documentation when you:
- Add new scripts or features
- Change script behavior or configuration
- Discover new troubleshooting steps
- Add new Makefile targets

### Documentation Files

- **README.md** — overview and quick start
- **[docs/README.md](docs/README.md)** — documentation index
- **[docs/getting-started.md](docs/getting-started.md)** — first-time walkthrough
- **[docs/installation.md](docs/installation.md)** — component install
- **[docs/troubleshooting.md](docs/troubleshooting.md)** — diagnostics
- **[docs/pebble-usage.md](docs/pebble-usage.md)** — Pebble
- **[docs/dns01-setup.md](docs/dns01-setup.md)** — DNS-01
- **[docs/network-support.md](docs/network-support.md)** — IPv4/IPv6/dual-stack
- **[docs/ibu-testing.md](docs/ibu-testing.md)** — IBU certificate validation
- **CONTRIBUTING.md** — this file

### Documentation Style

- Use clear, concise language
- Include code examples
- Add troubleshooting tips for common issues
- Link between related documents
- Keep line length reasonable for readability

## Adding New Scripts

When adding a new script:

1. **Place the script in the appropriate directory and make it executable:**
   ```bash
   touch scripts/new-script.sh
   chmod +x scripts/new-script.sh
   ```

2. **Source `lib/common.sh` — do not redefine colors or logging inline:**
   ```bash
   #!/bin/bash
   set -euo pipefail

   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   source "$SCRIPT_DIR/../lib/common.sh"
   ```

3. **Use shared functions from common.sh:**
   - `require_cmd oc envsubst` and `require_cluster` instead of inline prerequisite checks
   - `print_header "Title"` instead of inline echo header blocks
   - `apply_yaml_template "$YAML_DIR/file.yaml" "ResourceType"` instead of inline envsubst
   - `wait_for_resource "deployment/name" "namespace" "300s"` instead of custom polling loops
   - `ensure_namespace "name"` instead of inline namespace creation
   - `check_deployment_exists "name" "namespace"` for idempotency checks

4. **Add configuration via environment variables:**
   ```bash
   export VARIABLE_NAME="${VARIABLE_NAME:-default-value}"
   ```

5. **Add a Makefile target with a help comment:**
   ```makefile
   new-target: ## Description for make help
   	@./scripts/new-script.sh
   ```

6. **Document the script:**
   - Add to docs/installation.md or appropriate doc
   - Update README.md if it's a major feature
   - Add usage examples

7. **Add YAML manifests:**
   - Place in appropriate `yaml/` subdirectory
   - Use `envsubst` for variable substitution via `apply_yaml_template`

## Getting Help

- **Issues:** bugs and feature requests
- **Pull Requests:** reference related issues in the description

## Code of Conduct

- Be respectful and constructive
- Help others learn and grow
- Focus on the code, not the person
- Welcome newcomers and their contributions

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.

