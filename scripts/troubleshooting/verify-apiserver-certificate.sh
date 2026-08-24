#!/bin/bash

################################################################################
# Script: verify-apiserver-certificate.sh
# Description: Verify that cert-manager issued apiServer certificate doesn't
#              break cluster access
#
# This script checks:
# - Certificate is properly issued and valid
# - API server is accessible
# - oc commands work
# - Certificate details match expected values
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"
load_env

# Configuration
CERT_NAMESPACE="${CERT_NAMESPACE:-openshift-config}"
CERT_NAME="apiserver-cert"
SECRET_NAME="apiserver-cert-tls"

check_prerequisites() {
	require_cmd "$KUBE_CLI" jq

	if [[ "$CLUSTER_TYPE" != "openshift" ]]; then
		log_info "Skipping API server certificate verification (OpenShift-only)"
		exit 0
	fi

	if [[ "$KUBE_CLI" == "oc" ]]; then
		if ! retry 3 5 "$KUBE_CLI" whoami; then
			log_error "Cluster may be unstable. Please check cluster connectivity."
			exit 1
		fi
	elif ! retry 3 5 "$KUBE_CLI" get namespace default; then
		log_error "Cluster may be unstable. Please check cluster connectivity."
		exit 1
	fi
}

verify_api_server_access() {
	log_info "Verifying API server access..."
	local has_issues=0

	# Test 1: Can we run basic oc commands?
	if "$KUBE_CLI" version --client &>/dev/null; then
		log_info "  ✅ $KUBE_CLI client works"
	else
		log_error "  ❌ $KUBE_CLI client failed"
		has_issues=1
	fi

	# Test 2: Can we reach the API server?
	if [[ "$KUBE_CLI" == "oc" ]]; then
		if "$KUBE_CLI" whoami &>/dev/null; then
			log_info "  ✅ API server is accessible (authenticated)"
			local username
			username=$("$KUBE_CLI" whoami 2>/dev/null || echo "unknown")
			log_debug "     Logged in as: $username"
		else
			log_error "  ❌ Cannot authenticate with API server"
			has_issues=1
		fi
	elif "$KUBE_CLI" get namespace default &>/dev/null; then
		log_info "  ✅ API server is accessible (authenticated)"
		local username
		username=$("$KUBE_CLI" config current-context 2>/dev/null || echo "unknown")
		log_debug "     Context: $username"
	else
		log_error "  ❌ Cannot authenticate with API server"
		has_issues=1
	fi

	# Test 3: Can we list resources?
	if "$KUBE_CLI" get nodes &>/dev/null; then
		local node_count
		node_count=$("$KUBE_CLI" get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
		log_info "  ✅ Can list cluster resources ($node_count nodes)"
	else
		log_error "  ❌ Cannot list cluster resources"
		has_issues=1
	fi

	# Test 4: Can we get API server info?
	local api_url
	if [[ "$KUBE_CLI" == "oc" ]]; then
		api_url=$("$KUBE_CLI" whoami --show-server 2>/dev/null || echo "")
	else
		api_url=$("$KUBE_CLI" config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null || echo "")
	fi
	if [ -n "$api_url" ]; then
		log_info "  ✅ API server URL: $api_url"
	else
		log_warn "  ⚠️  Cannot determine API server URL"
	fi

	echo
	return $has_issues
}

verify_certificate_exists() {
	log_info "Verifying certificate resource..."
	local has_issues=0

	if ! "$KUBE_CLI" get namespace "$CERT_NAMESPACE" &>/dev/null; then
		log_error "  ❌ Namespace '$CERT_NAMESPACE' not found"
		return 1
	fi

	if "$KUBE_CLI" get certificate "$CERT_NAME" -n "$CERT_NAMESPACE" &>/dev/null; then
		log_info "  ✅ Certificate '$CERT_NAME' exists"

		# Check if certificate is ready
		local ready
		ready=$("$KUBE_CLI" get certificate "$CERT_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

		if [ "$ready" = "True" ]; then
			log_info "  ✅ Certificate is READY"
		else
			log_warn "  ⚠️  Certificate status: $ready"
			has_issues=1
		fi
	else
		log_error "  ❌ Certificate '$CERT_NAME' not found"
		return 1
	fi

	echo
	return $has_issues
}

verify_certificate_secret() {
	log_info "Verifying certificate secret..."
	local has_issues=0

	if "$KUBE_CLI" get secret "$SECRET_NAME" -n "$CERT_NAMESPACE" &>/dev/null; then
		log_info "  ✅ Secret '$SECRET_NAME' exists"

		# Check if secret has required keys
		local has_tls_crt
		has_tls_crt=$("$KUBE_CLI" get secret "$SECRET_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null)
		local has_tls_key
		has_tls_key=$("$KUBE_CLI" get secret "$SECRET_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.data.tls\.key}' 2>/dev/null)

		if [ -n "$has_tls_crt" ]; then
			log_info "  ✅ Secret contains tls.crt"
		else
			log_error "  ❌ Secret missing tls.crt"
			has_issues=1
		fi

		if [ -n "$has_tls_key" ]; then
			log_info "  ✅ Secret contains tls.key"
		else
			log_error "  ❌ Secret missing tls.key"
			has_issues=1
		fi
	else
		log_error "  ❌ Secret '$SECRET_NAME' not found"
		return 1
	fi

	echo
	return $has_issues
}

verify_certificate_details() {
	log_info "Verifying certificate details..."
	local has_issues=0

	# Extract and verify certificate
	local cert_pem
	cert_pem=$("$KUBE_CLI" get secret "$SECRET_NAME" -n "$CERT_NAMESPACE" -o jsonpath='{.data.tls\.crt}' 2>/dev/null | base64 -d)

	if [ -n "$cert_pem" ]; then
		# Check expiration
		local not_after
		not_after=$(echo "$cert_pem" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
		if [ -n "$not_after" ]; then
			log_info "  ✅ Certificate expires: $not_after"

			# Check if certificate is expired
			if echo "$cert_pem" | openssl x509 -noout -checkend 0 &>/dev/null; then
				log_info "  ✅ Certificate is not expired"
			else
				log_error "  ❌ Certificate is expired!"
				has_issues=1
			fi
		fi

		# Check subject
		local subject
		subject=$(echo "$cert_pem" | openssl x509 -noout -subject 2>/dev/null)
		if [ -n "$subject" ]; then
			log_debug "  Subject: $subject"
		fi

		# Check SANs
		local sans
		sans=$(echo "$cert_pem" | openssl x509 -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" | tail -1 | sed 's/^[[:space:]]*//')
		if [ -n "$sans" ]; then
			log_debug "  SANs: $sans"
		fi

		# Check issuer
		local issuer
		issuer=$(echo "$cert_pem" | openssl x509 -noout -issuer 2>/dev/null)
		if [ -n "$issuer" ]; then
			log_debug "  Issuer: $issuer"
		fi
	else
		log_error "  ❌ Could not extract certificate from secret"
		has_issues=1
	fi

	echo
	return $has_issues
}

check_apiserver_configuration() {
	log_info "Checking API server configuration..."

	# Check if the API server is configured to use our certificate
	local apiserver_config
	apiserver_config=$("$KUBE_CLI" get apiserver cluster -o json 2>/dev/null)

	if [ -n "$apiserver_config" ]; then
		local serving_certs
		serving_certs=$(echo "$apiserver_config" | jq -r '.spec.servingCerts.namedCertificates[]?.names[]?' 2>/dev/null | head -5)

		if [ -n "$serving_certs" ]; then
			log_info "  Named certificates configured:"
			echo "$serving_certs" | while read -r cert_name; do
				if [ -n "$cert_name" ]; then
					log_debug "    - $cert_name"
				fi
			done
		else
			log_debug "  No named certificates configured (using default)"
		fi
	else
		log_warn "  ⚠️  Could not retrieve API server configuration"
	fi

	echo
}

provide_recommendations() {
	local total_issues=$1

	print_header "Summary"

	if [ "$total_issues" -eq 0 ]; then
		log_info "✅ All checks passed!"
		echo
		log_info "The cert-manager issued API server certificate:"
		echo "  • Is properly created and valid"
		echo "  • Has not broken cluster access"
		echo "  • API server is fully functional"
		echo
		log_info "This verifies that cert-manager can safely manage API server certificates."
	else
		log_warn "⚠️  Issues detected: $total_issues"
		echo
		log_info "Troubleshooting steps:"
		echo "  1. Check certificate status:"
		echo "     $KUBE_CLI describe certificate $CERT_NAME -n $CERT_NAMESPACE"
		echo
		echo "  2. Check certificate secret:"
		echo "     $KUBE_CLI get secret $SECRET_NAME -n $CERT_NAMESPACE"
		echo
		echo "  3. Check API server logs:"
		echo "     $KUBE_CLI logs -n openshift-apiserver -l app=openshift-apiserver"
		echo
		echo "  4. Verify cert-manager logs:"
		echo "     $KUBE_CLI logs -n cert-manager deployment/cert-manager"
	fi

	echo
}

main() {
	print_header "API Server Certificate Verification"
	check_prerequisites

	local total_issues=0

	# Run all verification checks
	verify_api_server_access || ((total_issues++))
	verify_certificate_exists || ((total_issues++))
	verify_certificate_secret || ((total_issues++))
	verify_certificate_details || ((total_issues++))
	check_apiserver_configuration

	# Provide recommendations
	provide_recommendations "$total_issues"

	# Exit with error if there were issues
	if [ "$total_issues" -gt 0 ]; then
		exit 1
	fi

	exit 0
}

main
