#!/bin/bash
# =============================================================================
# Icos Visual E2E Audit Runner
# =============================================================================
#
# This script runs the full Maestro visual audit suite against the running app.
#
# Prerequisites:
#   1. Install Maestro:  brew tap mobile-dev-inc/tap && brew install maestro
#   2. Have a simulator/emulator running
#   3. App installed on the device:
#      - Android: flutter build apk --debug && flutter install
#      - iOS:     flutter build ios --debug --simulator && flutter install
#
# Usage:
#   ./scripts/run-visual-audit.sh              # Run all flows
#   ./scripts/run-visual-audit.sh single 04    # Run single flow (04_puzzle_gameplay)
#   ./scripts/run-visual-audit.sh report       # Run all + generate HTML report
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MAESTRO_DIR="$PROJECT_DIR/.maestro"
OUTPUT_DIR="$PROJECT_DIR/maestro-screenshots"
REPORT_DIR="$PROJECT_DIR/maestro-report"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo -e "${BLUE}============================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}============================================================${NC}"
    echo ""
}

check_prerequisites() {
    print_header "Checking Prerequisites"

    # Check Maestro
    if ! command -v maestro &> /dev/null; then
        echo -e "${RED}Maestro is not installed.${NC}"
        echo ""
        echo "Install it with:"
        echo "  brew tap mobile-dev-inc/tap"
        echo "  brew install maestro"
        echo ""
        echo "Or:"
        echo "  curl -Ls \"https://get.maestro.mobile.dev\" | bash"
        exit 1
    fi
    echo -e "${GREEN}  Maestro installed: $(maestro --version 2>/dev/null || echo 'OK')${NC}"

    # Check for running device/simulator
    if command -v adb &> /dev/null && adb devices | grep -q "device$"; then
        echo -e "${GREEN}  Android device/emulator detected${NC}"
    elif command -v xcrun &> /dev/null && xcrun simctl list devices booted 2>/dev/null | grep -q "Booted"; then
        echo -e "${GREEN}  iOS Simulator detected${NC}"
    else
        echo -e "${YELLOW}  Warning: No running device/emulator detected.${NC}"
        echo "  Please start a simulator or connect a device."
        echo ""
        echo "  Android: Start an emulator from Android Studio"
        echo "  iOS:     open -a Simulator"
        echo ""
    fi

    echo ""
}

run_all_flows() {
    print_header "Running Full Visual Audit (19 flows)"

    mkdir -p "$OUTPUT_DIR"

    echo -e "Screenshots will be saved to: ${BLUE}$OUTPUT_DIR${NC}"
    echo ""

    maestro test \
        --test-output-dir="$OUTPUT_DIR" \
        "$MAESTRO_DIR"

    echo ""
    echo -e "${GREEN}Visual audit complete!${NC}"
    echo -e "Screenshots saved to: ${BLUE}$OUTPUT_DIR${NC}"
    echo ""
    echo "Review the screenshots directory to inspect every screen visually."
}

run_single_flow() {
    local flow_num="$1"
    local flow_file

    flow_file=$(find "$MAESTRO_DIR/flows" -name "${flow_num}_*" -type f | head -1)

    if [ -z "$flow_file" ]; then
        echo -e "${RED}No flow found matching: ${flow_num}${NC}"
        echo ""
        echo "Available flows:"
        ls -1 "$MAESTRO_DIR/flows/" | sed 's/\.yaml//'
        exit 1
    fi

    print_header "Running Single Flow: $(basename "$flow_file")"

    mkdir -p "$OUTPUT_DIR"

    maestro test \
        --test-output-dir="$OUTPUT_DIR" \
        "$flow_file"

    echo ""
    echo -e "${GREEN}Flow complete!${NC}"
    echo -e "Screenshots saved to: ${BLUE}$OUTPUT_DIR${NC}"
}

run_with_report() {
    print_header "Running Full Audit with HTML Report"

    mkdir -p "$OUTPUT_DIR"
    mkdir -p "$REPORT_DIR"

    maestro test \
        --test-output-dir="$OUTPUT_DIR" \
        --format html \
        --output "$REPORT_DIR/visual-audit-report.html" \
        "$MAESTRO_DIR"

    echo ""
    echo -e "${GREEN}Visual audit complete!${NC}"
    echo -e "Screenshots: ${BLUE}$OUTPUT_DIR${NC}"
    echo -e "HTML Report: ${BLUE}$REPORT_DIR/visual-audit-report.html${NC}"
    echo ""

    # Try to open the report
    if command -v open &> /dev/null; then
        echo "Opening report in browser..."
        open "$REPORT_DIR/visual-audit-report.html"
    fi
}

list_flows() {
    print_header "Available Flows"
    echo "  ID  | Flow Name"
    echo "  ----|------------------------------------------"
    for f in "$MAESTRO_DIR/flows/"*.yaml; do
        name=$(basename "$f" .yaml)
        num=$(echo "$name" | cut -d'_' -f1)
        desc=$(echo "$name" | cut -d'_' -f2-)
        printf "  %s  | %s\n" "$num" "$desc"
    done
    echo ""
    echo "Usage:"
    echo "  ./scripts/run-visual-audit.sh              # Run all"
    echo "  ./scripts/run-visual-audit.sh single 04    # Run flow 04"
    echo "  ./scripts/run-visual-audit.sh report       # All + HTML report"
    echo "  ./scripts/run-visual-audit.sh list         # List flows"
}

# =============================================================================
# Main
# =============================================================================

check_prerequisites

case "${1:-all}" in
    all)
        run_all_flows
        ;;
    single)
        if [ -z "${2:-}" ]; then
            echo -e "${RED}Please specify a flow number: ./scripts/run-visual-audit.sh single 04${NC}"
            exit 1
        fi
        run_single_flow "$2"
        ;;
    report)
        run_with_report
        ;;
    list)
        list_flows
        ;;
    *)
        echo "Usage: $0 {all|single <num>|report|list}"
        exit 1
        ;;
esac
