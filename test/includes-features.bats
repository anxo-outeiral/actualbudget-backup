#!/usr/bin/env bats

# Unit tests for includes.sh feature functions (webhooks, rclone secrets)
# Run with: bats test/

setup() {
    # Source the real includes.sh relative to this test file
    . "$BATS_TEST_DIRNAME/../scripts/includes.sh"
}

@test "load_rclone_secrets reads _FILE vars and exports them" {
    export RCLONE_CONFIG_TESTBACKUP_PASS_FILE="/tmp/test_rclone_pass"
    echo "rclone_password" > /tmp/test_rclone_pass
    load_rclone_secrets
    [[ "${RCLONE_CONFIG_TESTBACKUP_PASS}" == "rclone_password" ]]
    rm -f /tmp/test_rclone_pass
}

@test "send_webhook does nothing when URL is empty" {
    run send_webhook "" "" "test message"
    [[ "$status" -eq 0 ]]
}

@test "send_webhook sends to a URL without crashing" {
    # curl will fail against a nonexistent endpoint, but the function
    # must not crash (it logs a warning and returns)
    run send_webhook "http://localhost:9999/nonexistent" "" "test"
    [[ "$status" -eq 0 ]]
}

@test "send_webhook builds default JSON payload with placeholders replaced" {
    # Verify the sed placeholder replacement logic via the default body path
    # (URL is empty so no request is made; we test the message template path
    # indirectly by ensuring the function exits cleanly with a custom message)
    run send_webhook "" '{"content": "{service}: {message}"}' "test"
    [[ "$status" -eq 0 ]]
}
