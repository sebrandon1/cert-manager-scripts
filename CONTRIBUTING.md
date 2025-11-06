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
# Check formatting (what CI runs)
shfmt -d .

# Auto-format all scripts
shfmt -w .

# Format specific file
shfmt -w script-name.sh
```

**Formatting rules:**
- 2-space indentation
- Binary operators at start of line allowed
- Switch cases indented

### Testing Your Changes

Before submitting a pull request:

1. **Format check:**
   ```bash
   # Using Make (recommended)
   make lint
   
   # Or directly with shfmt
   shfmt -d scripts/
   ```

2. **Test on a real cluster:**
   ```bash
   # Log into your test cluster
   oc login <cluster-url>
   
   # Run the affected scripts
   ./scripts/your-modified-script.sh
   
   # Or test the complete workflow
   make install-cert-manager-operator
   make quick-test
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
   - Shell format check must pass
   - Integration tests must pass (requires `CRC_PULL_SECRET` secret)

### Pull Request Checklist

- [ ] Code follows shell script formatting (shfmt)
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

The CI pipeline runs on every push and pull request with two jobs:

#### 1. Shell Format Check
- Validates all shell scripts with `shfmt`
- Ensures consistent formatting across the codebase
- **Must pass** before integration tests run

#### 2. Integration Test (OCP 4.19 + cert-manager)
- Deploys a real OpenShift 4.19 cluster using [quick-ocp](https://github.com/palmsoftware/quick-ocp)
- Installs cert-manager-operator
- Runs the complete `make quick-test` workflow:
  - Installs fake DNS for air-gapped testing
  - Installs Pebble ACME server
  - Creates DNS-01 ClusterIssuer
  - Requests wildcard certificate
  - Validates certificate issuance
- Displays detailed results and logs on failure

**Note:** Integration tests require the `CRC_PULL_SECRET` GitHub secret for deploying the OCP cluster. This is only available in the upstream repository.

### Running CI Tests Locally

You can run the same checks that CI runs:

```bash
# Format check (always run this before committing)
make lint

# Integration test (requires OpenShift cluster access)
make install-cert-manager-operator
make quick-test
```

### CI Failure Troubleshooting

If CI fails:

1. **Format check failure:**
   - Run `shfmt -w scripts/` to auto-format all scripts
   - Or check what needs fixing with `make lint`
   - Commit the formatting changes

2. **Integration test failure:**
   - Check the CI logs for specific errors
   - See [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) for common issues
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

- **README.md** - Overview, quick start, and key links
- **INSTALLATION.md** - Detailed installation instructions
- **TROUBLESHOOTING.md** - Common issues and solutions
- **PEBBLE-USAGE.md** - Pebble-specific usage and examples
- **NETWORK-SUPPORT.md** - IPv4/IPv6/dual-stack testing
- **DNS01-SETUP.md** - DNS-01 challenge configuration
- **CONTRIBUTING.md** - This file

### Documentation Style

- Use clear, concise language
- Include code examples
- Add troubleshooting tips for common issues
- Link between related documents
- Keep line length reasonable for readability

## Adding New Scripts

When adding a new script:

1. **Place the script in the `scripts/` directory:**
   ```bash
   # Create your new script
   touch scripts/new-script.sh
   chmod +x scripts/new-script.sh
   ```

2. **Follow the existing pattern:**
   - Check prerequisites at the start
   - Use colored output functions (log_info, log_warn, log_error)
   - Make scripts idempotent
   - Display helpful next steps

3. **Add configuration via environment variables:**
   ```bash
   export VARIABLE_NAME="${VARIABLE_NAME:-default-value}"
   ```

4. **Add error handling:**
   ```bash
   set -euo pipefail
   ```

5. **Add a Makefile target:**
   ```makefile
   new-target:
       @./scripts/new-script.sh
   ```

6. **Document the script:**
   - Add to INSTALLATION.md or appropriate doc
   - Update README.md if it's a major feature
   - Add usage examples

7. **Add YAML manifests:**
   - Place in appropriate `yaml/` subdirectory
   - Use `envsubst` for variable substitution
   - Document variables in script comments

## Getting Help

- **Issues:** Open an issue for bugs or feature requests
- **Discussions:** Use GitHub Discussions for questions
- **Pull Requests:** Reference related issues in your PR description

## Code of Conduct

- Be respectful and constructive
- Help others learn and grow
- Focus on the code, not the person
- Welcome newcomers and their contributions

## License

By contributing, you agree that your contributions will be licensed under the Apache 2.0 License.

