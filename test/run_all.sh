#!/usr/bin/env bash
# Run all shellclaw tests
#
# Usage:
#   ./test/run_all.sh          # run everything
#   ./test/test_log.sh         # run one suite

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

overall_exit=0

for test_file in "$SCRIPT_DIR"/test_*.sh; do
    echo ""
    bash "$test_file" || overall_exit=1
    echo ""
done

echo "=============================="
if [[ "$overall_exit" -eq 0 ]]; then
    echo "All test suites passed."
else
    echo "Some test suites FAILED."
fi

exit "$overall_exit"
