#!/usr/bin/env bash
#
# Creates a new X.Y.Z-zola branch from an upstream Apache PDFBox tag.
#
# Run this from the 3.0 branch whenever Apache releases a new 3.x tag.
#
# What it does:
#   1. Verifies the tag exists on upstream (apache/pdfbox)
#   2. Fetches the tag and pushes it to origin (our fork)
#   3. Ensures we're on the 3.0 branch
#   4. Creates a <version>-zola branch from the tag
#   5. Copies scripts/ from 3.0 into the new branch
#   6. Applies Zola-specific changes:
#      - Distribution management in parent/pom.xml (Nexus deploy config)
#      - ZOLA.md documentation
#      - Deploy instructions in README.md
#      - Glyph substitution in GlyphSubstitutionDataExtractor.java (via patch)
#   7. Updates all pom.xml parent versions to <version>-ZOLA
#   8. Pushes the branch to origin
#
# Usage: ./scripts/create-zola-branch.sh <version>
#   e.g. ./scripts/create-zola-branch.sh 3.0.7

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PATCHES_DIR="${SCRIPT_DIR}/patches"

VERSION="${1:-}"

if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "  e.g. $0 3.0.7"
    exit 1
fi

BRANCH_NAME="${VERSION}-zola"

# --- Step 1: Verify the tag exists on upstream ---
echo "==> Checking if tag ${VERSION} exists on upstream..."
if ! git ls-remote --tags upstream "refs/tags/${VERSION}" | grep -q "${VERSION}"; then
    echo "ERROR: Tag ${VERSION} does not exist on upstream (apache/pdfbox)."
    echo "Check available tags: git ls-remote --tags upstream"
    exit 1
fi
echo "    Tag ${VERSION} found on upstream."

# --- Step 2: Fetch the tag and push to origin ---
echo "==> Fetching tag ${VERSION} from upstream..."
git fetch upstream tag "${VERSION}"

echo "==> Pushing tag ${VERSION} to origin..."
git push origin tag "${VERSION}" 2>/dev/null || echo "    Tag already exists on origin, skipping."

# --- Step 3: Ensure we're on 3.0 ---
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT_BRANCH" != "3.0" ]]; then
    echo "ERROR: Must be run from the 3.0 branch (currently on ${CURRENT_BRANCH})."
    exit 1
fi

# --- Step 4: Create branch from the tag ---
echo "==> Creating branch ${BRANCH_NAME} from tag ${VERSION}..."
if git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
    echo "ERROR: Branch ${BRANCH_NAME} already exists locally."
    echo "Delete it first if you want to recreate: git branch -D ${BRANCH_NAME}"
    exit 1
fi
git checkout -b "${BRANCH_NAME}" "${VERSION}"

# --- Step 5: Copy scripts from 3.0 branch ---
echo "==> Copying scripts from 3.0 branch..."
git checkout 3.0 -- scripts/
git add scripts/
git commit -m "Add Zola scripts from 3.0 branch"

# --- Step 6a: Add Zola distribution management and docs ---
echo "==> Adding Zola distribution management and documentation..."

# Add distributionManagement block after </scm> in parent/pom.xml
sed -i '' '/<\/scm>/a\
\
    <!-- distribute to Zola internal repo -->\
  <distributionManagement>\
    <repository>\
        <id>deployment</id>\
        <name>Internal Releases</name>\
        <url>https://nexus3.zola.com/nexus/content/repositories/releases/</url>\
    </repository>\
    <snapshotRepository>\
        <id>deployment</id>\
        <name>Internal Releases</name>\
        <url>https://nexus3.zola.com/nexus/content/repositories/snapshots/</url>\
    </snapshotRepository>\
  </distributionManagement>
' parent/pom.xml

# Add deploy section to README.md before "Contribute" section
sed -i '' '/^Contribute$/i\
Deploy\
------\
APPLIES TO ZOLA ONLY\
You can deploy the artifacts to the Zola Nexus repository by running:\
\
    mvn clean deploy\
' README.md

# Create ZOLA.md
cat > ZOLA.md << 'ZOLA_EOF'
Apache PdfBox has built relatively strong ligature support in version 3
We managed to add some more ligatures to support that are available in version 3.0.2
Unfortunately, we have a special use case that needs time to implement correctly in Apache PdfBox.
We have our own implementation that works for Zola use cases as we work with Latin characters.
If you need to update PdfBox to a new version, run:

    ./scripts/create-zola-branch.sh <version>

This script applies Zola-specific patches and updates the version.
ZOLA_EOF

git add parent/pom.xml README.md ZOLA.md
git commit -m "Add Zola distribution management and documentation"

# --- Step 6b: Apply glyph substitution patch ---
echo "==> Applying Zola glyph substitution patch..."
if ! git apply --check "${PATCHES_DIR}/zola-glyph-substitution.patch" 2>/dev/null; then
    echo "    Patch does not apply cleanly. Trying with 3-way merge..."
    git apply --3way "${PATCHES_DIR}/zola-glyph-substitution.patch"
else
    git apply "${PATCHES_DIR}/zola-glyph-substitution.patch"
fi
git add fontbox/src/main/java/org/apache/fontbox/ttf/gsub/GlyphSubstitutionDataExtractor.java
git commit -m "Implement glyph substitution logic in GlyphSubstitutionDataExtractor for Lookup Type 2"

# --- Step 7: Update pom.xml versions ---
echo "==> Updating pom.xml versions from ${VERSION} to ${VERSION}-ZOLA..."

POM_FILES=(
    pom.xml
    parent/pom.xml
    app/pom.xml
    debugger-app/pom.xml
    debugger/pom.xml
    examples/pom.xml
    fontbox/pom.xml
    io/pom.xml
    pdfbox/pom.xml
    preflight-app/pom.xml
    preflight/pom.xml
    tools/pom.xml
    xmpbox/pom.xml
)

for pom in "${POM_FILES[@]}"; do
    if [ -f "$pom" ]; then
        sed -i '' "s|<version>${VERSION}</version>|<version>${VERSION}-ZOLA</version>|" "$pom"
        echo "    Updated $pom"
    else
        echo "    WARN: $pom not found, skipping"
    fi
done

git add "${POM_FILES[@]}"
git commit -m "Update parent version to ${VERSION}-ZOLA in pom.xml"

# --- Step 8: Push to origin ---
echo "==> Pushing ${BRANCH_NAME} to origin..."
git push -u origin "${BRANCH_NAME}"

echo ""
echo "Done! Branch ${BRANCH_NAME} is ready."
echo "Deploy with: mvn clean deploy"
