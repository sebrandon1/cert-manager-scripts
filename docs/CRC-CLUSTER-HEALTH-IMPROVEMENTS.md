# CRC Cluster Health Check Improvements

## Overview

Enhanced CI workflow reliability by adding comprehensive cluster health checks and recovery mechanisms to detect and handle CRC cluster instability issues before they cause test failures.

## Problem

Integration tests were failing with:
```
Unable to connect to the server: dial tcp: lookup api.crc.testing: no such host
```

This indicates CRC cluster DNS resolution failures or cluster crashes mid-test, which are common in CI environments due to:
- Resource constraints
- DNS propagation delays
- Cluster instability after heavy operations
- API server responsiveness issues

## Solution

### 1. Enhanced Cluster Verification Script

**File:** `scripts/workflows/verify-cluster-access.sh`

Comprehensive health checks that verify:
- ✅ oc CLI availability
- ✅ DNS resolution for API server (catches the `no such host` error early)
- ✅ KUBECONFIG validity
- ✅ Cluster authentication
- ✅ API server reachability
- ✅ Node presence and readiness
- ✅ Cluster operator health
- ✅ API responsiveness timing

**Benefits:**
- Catches DNS failures before tests start
- Validates cluster is stable enough for testing
- Provides detailed diagnostic output
- Exits early if cluster is unhealthy

### 2. New Cluster Recovery Script

**File:** `scripts/workflows/recover-cluster.sh`

Attempts to recover from common failure states:
- DNS resolution failures (with refresh attempts)
- Authentication issues (token refresh)
- API server unresponsiveness (with retries)

**Benefits:**
- Automatic recovery from transient issues
- Reduces false-positive test failures
- Extends cluster stability window

### 3. Improved Component Status Display

**File:** `scripts/workflows/display-component-status.sh`

Enhanced to:
- Check cluster accessibility before attempting status queries
- Provide clear error messages when cluster is down
- Gracefully handle individual component query failures
- Give actionable diagnostic information

**Benefits:**
- Prevents confusing error logs when cluster is down
- Helps diagnose whether issue is cluster-wide or component-specific

### 4. Enhanced CI Workflow

**File:** `.github/workflows/pre-main.yml`

Improvements:
1. **Initial Health Check** (after CRC deployment)
   - 5 retry attempts with 30s wait between retries
   - Ensures cluster is fully stable before starting tests

2. **Cluster Stabilization Wait**
   - 30-second wait after initial verification
   - Allows DNS and operators to fully stabilize

3. **Pre-Test Health Checks**
   - Added before HTTP-01 tests (with 3 retries)
   - Added before API server cert tests (with 3 retries)

4. **Cluster Recovery on Retry**
   - Automatic recovery attempt when tests fail
   - Runs `recover-cluster.sh` before retrying failed tests

5. **Final Health Check**
   - Runs after all tests complete (even on failure)
   - Helps diagnose if cluster became unstable during testing

## Workflow Changes Summary

```yaml
Before:
- Deploy CRC
- Run tests (no health checks)
- Test fails with "no such host"

After:
- Deploy CRC
- Initial health check (5 retries, 30s between)
- Wait 30s for stabilization
- Health check before each major test phase (3 retries)
- Auto-recovery on test failure
- Run tests
- Final health check
```

## Expected Impact

### Reduced False Positives
- Early detection of cluster issues prevents misleading test failures
- Recovery mechanisms handle transient failures automatically

### Better Diagnostics
- Clear indication of whether issue is cluster or test-related
- Detailed health information in logs
- Easier troubleshooting when real issues occur

### Improved Reliability
- Multiple retry points with increasing wait times
- Cluster stabilization periods
- Recovery attempts between retries

## Testing Recommendations

1. Monitor next few CI runs to validate improvements
2. Check for reduced "no such host" failures
3. Verify recovery mechanisms are working
4. Adjust retry counts/timeouts if needed

## Maintenance Notes

- Health check thresholds may need tuning based on observed behavior
- Recovery script can be extended with additional recovery strategies
- Consider adding metrics/telemetry for cluster health patterns

## Related Issues

- Addresses GitHub Actions integration test failures due to CRC instability
- Prevents DNS resolution failures from causing test failures
- Improves overall CI reliability for cert-manager testing

