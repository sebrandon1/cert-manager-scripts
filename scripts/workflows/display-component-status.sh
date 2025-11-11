#!/bin/bash

set -euo pipefail

echo "=== Component Status ==="
echo ""
echo "cert-manager pods:"
oc get pods -n cert-manager || true
echo ""
echo "Pebble pods:"
oc get pods -n pebble || true
echo ""
echo "ClusterIssuer status:"
oc get clusterissuer -o wide || true
echo ""
echo "Certificate status:"
oc get certificate -n default || true
echo ""
echo "CertificateRequest status:"
oc get certificaterequest -n default || true
echo ""
echo "Order status:"
oc get order -n default || true
echo ""
echo "Challenge status:"
oc get challenge -n default || true
echo ""
echo "Recent cert-manager logs:"
oc logs -n cert-manager deployment/cert-manager --tail=30 || true
