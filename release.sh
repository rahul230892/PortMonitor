#!/bin/bash
set -e

if [ -z "$1" ]; then
  echo "Usage: ./release.sh <version> (e.g. ./release.sh 1.1.0)"
  exit 1
fi

VERSION=$1
ZIP_FILE="PortMonitor.zip"
TAP_DIR="/opt/homebrew/Library/Taps/rahul230892/homebrew-tap"
CASK_FILE="${TAP_DIR}/Casks/portmonitor.rb"

# 1. Check gh is installed and logged in
if ! command -v gh &> /dev/null; then
  echo "GitHub CLI (gh) is not installed. Please run: brew install gh"
  exit 1
fi

if ! gh auth status &> /dev/null; then
  echo "You are not logged into GitHub CLI!"
  echo "Please run: gh auth login"
  exit 1
fi

# 2. Check if repo has a remote
if ! git remote get-url origin &> /dev/null; then
  echo "No remote repository found. Creating one..."
  # Create a public repo by default since Homebrew casks usually need public zip access
  gh repo create PortMonitor --public --source=. --remote=origin --push
fi

# 3. Build & Zip
echo "Building PortMonitor..."
./build.sh

# 4. Commit and push current changes
echo "Committing code..."
git add .
git diff-index --quiet HEAD || git commit -m "Bump version to $VERSION"
git push origin dev || git push origin main || git push origin master

# 5. Create GitHub Release
echo "Creating GitHub Release v${VERSION}..."
gh release create "v${VERSION}" "${ZIP_FILE}" --title "PortMonitor v${VERSION}" --notes "Automated release of v${VERSION}"

# 6. Update Homebrew Tap
echo "Updating Homebrew Tap..."
SHA256=$(shasum -a 256 "${ZIP_FILE}" | awk '{ print $1 }')
GITHUB_USERNAME=$(gh api user -q ".login")

cat <<EOF > "${CASK_FILE}"
cask "portmonitor" do
  version "${VERSION}"
  sha256 "${SHA256}"

  url "https://github.com/${GITHUB_USERNAME}/PortMonitor/releases/download/v#{version}/PortMonitor.zip"
  name "PortMonitor"
  desc "macOS Port Monitor"
  homepage "https://github.com/${GITHUB_USERNAME}/PortMonitor"

  app "PortMonitor.app"

  postflight do
    system_command "xattr",
                   args: ["-cr", "#{appdir}/PortMonitor.app"],
                   sudo: false
  end

  caveats <<~EOS
    If you get a "damaged" or "cannot be opened" error, run:
      xattr -cr /Applications/PortMonitor.app
  EOS
end
EOF

# 7. Push updated Tap
echo "Pushing Tap updates..."
cd "${TAP_DIR}"
git add Casks/portmonitor.rb
git commit -m "Update portmonitor to v${VERSION}"
git push

echo ""
echo "✅ Release v${VERSION} successfully published to GitHub and Homebrew!"
echo "Users can now update by running: brew reinstall portmonitor"
