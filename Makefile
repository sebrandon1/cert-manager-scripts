.PHONY: help install-cert-manager-operator uninstall-cert-manager-operator clean

# Default target
help:
	@echo "cert-manager-scripts Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  install-cert-manager-operator   - Install cert-manager Operator for Red Hat OpenShift"
	@echo "  uninstall-cert-manager-operator - Uninstall cert-manager Operator for Red Hat OpenShift"
	@echo "  clean                           - Clean up temporary files"
	@echo "  help                            - Show this help message"
	@echo ""

# Install cert-manager-operator
install-cert-manager-operator:
	@echo "Installing cert-manager Operator for Red Hat OpenShift..."
	@./install-cert-manager-operator.sh

# Uninstall cert-manager-operator (placeholder for future script)
uninstall-cert-manager-operator:
	@echo "Uninstall script not yet implemented."
	@echo "To manually uninstall, see: https://docs.redhat.com/en/documentation/openshift_container_platform/4.20/html/security_and_compliance/cert-manager-operator-for-red-hat-openshift#cert-manager-uninstalling-operator"

# Clean temporary files
clean:
	@echo "Cleaning temporary files..."
	@find . -name "*.tmp" -delete
	@find . -name ".*.swp" -delete
	@echo "Clean complete."

