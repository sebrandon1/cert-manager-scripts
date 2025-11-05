# DNS-01 Challenge Setup Guide

This guide shows you how to set up **fully local DNS-01 challenge testing** on your OpenShift cluster without any external dependencies.

## What You'll Get

✅ Local DNS server (acme-dns) for ACME challenges  
✅ Pebble ACME server using your local DNS  
✅ cert-manager configured for DNS-01  
✅ Ability to test wildcard certificates  
✅ **No external DNS provider needed**  
✅ **No real DNS records needed**

## Quick Start

### Step 1: Install Local DNS Server

```bash
./install-local-dns.sh
```

This installs **acme-dns** - a lightweight DNS server with an API designed specifically for ACME challenges.

### Step 2: Reinstall Pebble to Use Local DNS

```bash
# Delete existing Pebble
oc delete namespace pebble

# Reinstall pointing to acme-dns
DNS_SERVER=acme-dns.acme-dns.svc.cluster.local:53 PEBBLE_ALWAYS_VALID=1 ./install-pebble.sh
```

Now Pebble will query your local acme-dns server for DNS validation!

### Step 3: Install cert-manager Webhook for acme-dns

The cert-manager webhook allows cert-manager to create DNS records in acme-dns.

```bash
# Install the acme-dns webhook
helm repo add cert-manager-webhook-acmedns https://k3rnelpan1c-dev.github.io/cert-manager-webhook-acmedns
helm repo update

helm install cert-manager-webhook-acmedns \
  cert-manager-webhook-acmedns/cert-manager-webhook-acmedns \
  -n cert-manager \
  --set groupName=acme.mycompany.com
```

Or manually deploy:
```bash
kubectl apply -f https://raw.githubusercontent.com/k3rnelpan1c-dev/cert-manager-webhook-acmedns/master/deploy/manifests.yaml
```

### Step 4: Register with acme-dns

Create an account in acme-dns for each domain you want to test:

```bash
# Register a domain
oc run --rm -i acmedns-register --image=curlimages/curl --restart=Never -- \
  curl -X POST http://acme-dns.acme-dns.svc.cluster.local:8080/register

# Save the output - you'll need the credentials
```

Example output:
```json
{
  "username": "eabcdb41-d89f-4580-bb05-cd43c5d53b79",
  "password": "pbAXVjlIOE01xbut7YnAbkhMQIkcwoHO0ek2j4Q0",
  "fulldomain": "d420c923-bbd7-4056-ab64-c3ca54c9b3cf.acme-dns.local",
  "subdomain": "d420c923-bbd7-4056-ab64-c3ca54c9b3cf",
  "allowfrom": []
}
```

### Step 5: Create DNS-01 ClusterIssuer

Create a secret with your acme-dns credentials:

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: acmedns-credentials
  namespace: cert-manager
type: Opaque
stringData:
  acmedns.json: |
    {
      "*.example.com": {
        "username": "YOUR_USERNAME",
        "password": "YOUR_PASSWORD",
        "fulldomain": "YOUR_FULLDOMAIN",
        "subdomain": "YOUR_SUBDOMAIN",
        "serverurl": "http://acme-dns.acme-dns.svc.cluster.local:8080"
      }
    }
EOF
```

Create the ClusterIssuer:

```bash
cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: pebble-dns01-issuer
spec:
  acme:
    server: https://pebble.pebble.svc.cluster.local:14000/dir
    skipTLSVerify: true
    email: test@example.com
    privateKeySecretRef:
      name: pebble-dns01-account-key
    solvers:
    - dns01:
        acmeDNS:
          host: http://acme-dns.acme-dns.svc.cluster.local:8080
          accountSecretRef:
            name: acmedns-credentials
            key: acmedns.json
EOF
```

### Step 6: Test with a Wildcard Certificate

```bash
cat <<EOF | oc apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-cert-test
  namespace: default
spec:
  secretName: wildcard-cert-tls
  issuerRef:
    name: pebble-dns01-issuer
    kind: ClusterIssuer
  dnsNames:
  - "*.example.com"
  - "example.com"
EOF
```

### Step 7: Verify

```bash
# Watch certificate status
watch oc get certificate -n default

# Check if cert is ready
oc get certificate wildcard-cert-test -n default

# View the certificate
oc get secret wildcard-cert-tls -n default -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Your OCP Cluster                       │
│                                                          │
│  ┌──────────────┐      ┌─────────────┐                 │
│  │ cert-manager │─────→│  acme-dns   │                 │
│  │              │      │  (DNS API)  │                 │
│  └──────┬───────┘      └──────┬──────┘                 │
│         │                      │                         │
│         │  ACME                │  DNS                    │
│         │  Protocol            │  Queries                │
│         │                      │                         │
│         ↓                      ↓                         │
│  ┌──────────────┐      ┌─────────────┐                 │
│  │   Pebble     │─────→│  acme-dns   │                 │
│  │ (ACME Server)│      │ (DNS Server)│                 │
│  └──────────────┘      └─────────────┘                 │
│                                                          │
│  Everything runs locally - no external dependencies!    │
└─────────────────────────────────────────────────────────┘
```

## How It Works

1. **cert-manager** requests a certificate from **Pebble**
2. **Pebble** says "prove ownership with DNS-01 challenge"
3. **cert-manager** creates a TXT record in **acme-dns** via API
4. **Pebble** queries **acme-dns** to verify the TXT record
5. With `PEBBLE_ALWAYS_VALID=1`, validation auto-succeeds
6. **Pebble** issues the certificate
7. **cert-manager** stores it in a Secret

## Benefits of This Setup

✅ **Completely Local** - Everything runs in your cluster  
✅ **No External Dependencies** - No Route53, CloudFlare, etc needed  
✅ **Test Wildcard Certs** - DNS-01 is required for wildcards  
✅ **Fast** - No waiting for DNS propagation  
✅ **Repeatable** - Same setup works on any OCP cluster  
✅ **Safe** - No rate limits, no real certificates  

## Troubleshooting

### acme-dns Not Starting

```bash
oc logs -n acme-dns deployment/acme-dns
oc describe pod -n acme-dns
```

### Pebble Can't Reach acme-dns

```bash
# Test DNS resolution from Pebble
oc run --rm -i dns-test --image=busybox --restart=Never -n pebble -- \
  nslookup acme-dns.acme-dns.svc.cluster.local
```

### Certificate Stuck in Pending

```bash
# Check challenge status
oc describe challenge -n default

# Check cert-manager logs
oc logs -n cert-manager deployment/cert-manager -f

# Check Pebble logs
oc logs -n pebble deployment/pebble -f
```

### Webhook Not Working

```bash
# Check webhook deployment
oc get pods -n cert-manager | grep webhook

# Check webhook logs
oc logs -n cert-manager deployment/cert-manager-webhook-acmedns
```

## Alternative: Simpler Setup with Always-Valid

If you just want to test the mechanics without full DNS setup:

1. Keep `PEBBLE_ALWAYS_VALID=1`
2. Use a dummy DNS-01 solver configuration
3. Pebble will auto-validate without checking DNS

This is less realistic but useful for testing cert-manager functionality.

## References

- [acme-dns GitHub](https://github.com/joohoi/acme-dns)
- [cert-manager acme-dns webhook](https://github.com/k3rnelpan1c-dev/cert-manager-webhook-acmedns)
- [Pebble Documentation](https://github.com/letsencrypt/pebble)
- [cert-manager DNS-01 Guide](https://cert-manager.io/docs/configuration/acme/dns01/)

