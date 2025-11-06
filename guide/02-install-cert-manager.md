# Install cert-manager Operator

This guide will install the cert-manager operator on your OpenShift cluster.

## Step 1: Install cert-manager Operator

Run the installation:

```bash
make install-cert-manager-operator
```

This will:
- Create the cert-manager-operator namespace
- Install the OperatorGroup
- Create the Subscription to install cert-manager

## Step 2: Wait for Installation

The operator will take a few moments to install. Wait for it to be ready:

```bash
oc wait --for=jsonpath='{.status.phase}'=Succeeded csv -l operators.coreos.com/cert-manager-operator.cert-manager-operator -n cert-manager-operator --timeout=300s
```

Or watch the installation progress:

```bash
oc get csv -n cert-manager-operator -w
```

Press `Ctrl+C` to stop watching once you see `Succeeded` phase.

## Step 3: Verify cert-manager Pods

Check that all cert-manager pods are running:

```bash
oc get pods -n cert-manager
```

You should see pods like:
- `cert-manager-*`
- `cert-manager-webhook-*`
- `cert-manager-cainjector-*`

All should be in `Running` status.

## What's Next?

Now that cert-manager is installed, let's set up Pebble as our ACME server for testing.

---

**[← Previous: Prerequisites](01-prerequisites.md)** | **[Next Step: Install Pebble →](03-install-pebble.md)**

