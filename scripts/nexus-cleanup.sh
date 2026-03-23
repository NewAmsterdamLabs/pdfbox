#!/bin/bash

# Nexus cleanup script for PDFBox artifacts
# Usage:
#   ./nexus-cleanup.sh <version>                    # List components to delete
#   ./nexus-cleanup.sh <version> --delete           # Actually delete the components
#   ./nexus-cleanup.sh --help                       # Show help

set -e

# Configuration
NEXUS_URL="https://nexus3.zola.com/nexus"
REPOSITORY="releases"
GROUP_ID="org.apache.pdfbox"

# Artifacts to clean up
ARTIFACTS=(
    "pdfbox-parent"
    "pdfbox-io"
    "fontbox"
    "xmpbox"
    "pdfbox"
    "preflight"
    "preflight-app"
    "pdfbox-debugger"
    "pdfbox-tools"
    "pdfbox-app"
    "debugger-app"
    "pdfbox-examples"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Parse arguments
DELETE_MODE=false

show_help() {
    echo "Usage: $0 <version> [OPTIONS]"
    echo "  e.g. $0 3.0.6-ZOLA"
    echo "  e.g. $0 3.0.6-ZOLA --delete"
    echo ""
    echo "Options:"
    echo "  --delete    Actually delete the components (default: dry-run mode)"
    echo "  --help      Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  NEXUS_USER     Nexus username (required for operations)"
    echo "  NEXUS_PASS     Nexus password (required for operations)"
    echo ""
}

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    show_help
    exit 0
fi

if [[ -z "${1:-}" ]]; then
    echo "Error: version argument required."
    echo ""
    show_help
    exit 1
fi

VERSIONS=("$1")
shift

if [[ "${1:-}" == "--delete" ]]; then
    DELETE_MODE=true
fi

# Check for credentials
if [[ -z "$NEXUS_USER" ]] || [[ -z "$NEXUS_PASS" ]]; then
    echo -e "${YELLOW}Warning: NEXUS_USER and NEXUS_PASS environment variables not set${NC}"
    echo "Set them with:"
    echo "  export NEXUS_USER='your-username'"
    echo "  export NEXUS_PASS='your-password'"
    echo ""
    if [[ "$DELETE_MODE" == true ]]; then
        echo -e "${RED}Error: Credentials required for delete mode${NC}"
        exit 1
    fi
fi

# Function to search for a component
search_component() {
    local artifact_id=$1
    local version=$2

    local url="${NEXUS_URL}/service/rest/v1/search?repository=${REPOSITORY}&group=${GROUP_ID}&name=${artifact_id}&version=${version}"

    if [[ -n "$NEXUS_USER" ]] && [[ -n "$NEXUS_PASS" ]]; then
        curl -s -u "${NEXUS_USER}:${NEXUS_PASS}" "$url"
    else
        curl -s "$url"
    fi
}

# Function to delete a component
delete_component() {
    local component_id=$1
    local artifact_id=$2
    local version=$3

    local url="${NEXUS_URL}/service/rest/v1/components/${component_id}"

    echo -e "  ${RED}Deleting${NC} ${artifact_id}:${version} (ID: ${component_id})"

    local response=$(curl -s -w "\n%{http_code}" -u "${NEXUS_USER}:${NEXUS_PASS}" -X DELETE "$url")
    local http_code=$(echo "$response" | tail -n1)

    if [[ "$http_code" == "204" ]]; then
        echo -e "    ${GREEN}✓ Successfully deleted${NC}"
        return 0
    else
        echo -e "    ${RED}✗ Failed (HTTP ${http_code})${NC}"
        return 1
    fi
}

# Main execution
echo "========================================"
echo "Nexus Cleanup Script for PDFBox"
echo "========================================"
echo "Repository: ${REPOSITORY}"
echo "Group ID: ${GROUP_ID}"
echo "Versions: ${VERSIONS[*]}"
echo ""

if [[ "$DELETE_MODE" == true ]]; then
    echo -e "${RED}MODE: DELETE${NC}"
    echo ""
    read -p "Are you sure you want to delete these components? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        echo "Aborted."
        exit 0
    fi
else
    echo -e "${GREEN}MODE: DRY-RUN (listing only)${NC}"
fi

echo ""
echo "----------------------------------------"

total_found=0
total_deleted=0
total_failed=0

for version in "${VERSIONS[@]}"; do
    echo ""
    echo -e "${YELLOW}Version: ${version}${NC}"
    echo "----------------------------------------"

    for artifact in "${ARTIFACTS[@]}"; do
        echo -e "\nSearching: ${artifact}:${version}"

        result=$(search_component "$artifact" "$version")

        # Parse the JSON response to get component IDs
        # Using basic grep/sed since jq might not be available
        # Extract only the first "id" field which is the component ID (not asset IDs)
        component_ids=$(echo "$result" | grep -o '"id" : "[^"]*"' | head -1 | cut -d'"' -f4)

        if [[ -z "$component_ids" ]]; then
            echo "  Not found in repository"
        else
            # Since we only get one component ID per search, count is 1
            echo "  Found component"
            total_found=$((total_found + 1))

            while IFS= read -r component_id; do
                if [[ "$DELETE_MODE" == true ]]; then
                    if delete_component "$component_id" "$artifact" "$version"; then
                        total_deleted=$((total_deleted + 1))
                    else
                        total_failed=$((total_failed + 1))
                    fi
                else
                    echo "  Would delete: ${artifact}:${version} (ID: ${component_id})"
                fi
            done <<< "$component_ids"
        fi
    done
done

echo ""
echo "========================================"
echo "Summary"
echo "========================================"
echo "Total components found: ${total_found}"

if [[ "$DELETE_MODE" == true ]]; then
    echo -e "${GREEN}Successfully deleted: ${total_deleted}${NC}"
    if [[ $total_failed -gt 0 ]]; then
        echo -e "${RED}Failed to delete: ${total_failed}${NC}"
    fi
else
    echo ""
    echo "To actually delete these components, run:"
    echo "  $0 --delete"
fi
echo ""
