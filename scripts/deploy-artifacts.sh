#!/bin/bash

# ==============================================
# deploy-artifacts.sh
# Automated artifact deployment for FastFilter Java
# ==============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Global variables
DEPLOYMENT_TARGET=""
VERSION=""
DRY_RUN=false
SKIP_TESTS=false

# Usage information
show_usage() {
    cat << EOF
FastFilter Java - Artifact Deployment Script

Usage: $0 [OPTIONS] TARGET

TARGETS:
  snapshot         Deploy SNAPSHOT to GitHub Packages
  release          Deploy RELEASE to GitHub Packages  
  central          Deploy RELEASE to Maven Central
  all              Deploy to all configured repositories

OPTIONS:
  -v, --version VERSION    Override version (auto-detected from pom.xml)
  -d, --dry-run           Perform dry run without actual deployment
  -s, --skip-tests        Skip running tests before deployment
  -h, --help              Show this help message

EXAMPLES:
  $0 snapshot                           # Deploy snapshot to GitHub Packages
  $0 release -v 1.0.3                  # Deploy release version 1.0.3
  $0 central                            # Deploy to Maven Central
  $0 all --skip-tests                   # Deploy everywhere, skip tests

ENVIRONMENT:
  Set up credentials using: ./scripts/setup-github-credentials.sh
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                VERSION="$2"
                shift 2
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -s|--skip-tests)
                SKIP_TESTS=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            snapshot|release|central|all)
                DEPLOYMENT_TARGET="$1"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    if [[ -z "$DEPLOYMENT_TARGET" ]]; then
        log_error "Deployment target is required"
        show_usage
        exit 1
    fi
}

# Detect current version from POM
detect_version() {
    if [[ -z "$VERSION" ]]; then
        VERSION=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
        log_info "Auto-detected version: $VERSION"
    fi
    
    if [[ "$VERSION" == *"-SNAPSHOT" ]] && [[ "$DEPLOYMENT_TARGET" == "release" || "$DEPLOYMENT_TARGET" == "central" ]]; then
        log_error "Cannot deploy SNAPSHOT version ($VERSION) as release"
        log_info "Either change version to non-SNAPSHOT or use 'snapshot' target"
        exit 1
    fi
    
    if [[ "$VERSION" != *"-SNAPSHOT" ]] && [[ "$DEPLOYMENT_TARGET" == "snapshot" ]]; then
        log_warning "Deploying non-SNAPSHOT version ($VERSION) to snapshot repository"
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Maven
    if ! command -v mvn &> /dev/null; then
        log_error "Maven is not installed"
        exit 1
    fi
    
    # Check GitHub CLI
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI is not installed"
        log_info "Install with: brew install gh (macOS) or sudo apt install gh (Linux)"
        exit 1
    fi
    
    # Check GitHub authentication
    if ! gh auth status &> /dev/null; then
        log_error "Not authenticated with GitHub CLI"
        log_info "Run: gh auth login"
        exit 1
    fi
    
    # Check Maven settings
    if [[ ! -f "$HOME/.m2/settings.xml" ]]; then
        log_warning "Maven settings.xml not found"
        log_info "Run: ./scripts/setup-github-credentials.sh"
    fi
    
    log_success "Prerequisites check completed"
}

# Run tests
run_tests() {
    if [[ "$SKIP_TESTS" == "true" ]]; then
        log_warning "Skipping tests as requested"
        return 0
    fi
    
    log_info "Running tests before deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would run tests"
        return 0
    fi
    
    if ! mvn clean test -B; then
        log_error "Tests failed. Deployment aborted."
        log_info "Use --skip-tests to bypass (not recommended)"
        exit 1
    fi
    
    log_success "All tests passed"
}

# Set version if different
set_version() {
    local current_version=$(mvn help:evaluate -Dexpression=project.version -q -DforceStdout)
    
    if [[ "$VERSION" != "$current_version" ]]; then
        log_info "Updating version from $current_version to $VERSION"
        
        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "DRY RUN: Would set version to $VERSION"
            return 0
        fi
        
        mvn versions:set -DnewVersion="$VERSION" -B
        mvn versions:commit -B
        log_success "Version updated to $VERSION"
    fi
}

# Deploy to GitHub Packages (snapshots)
deploy_github_snapshot() {
    log_info "Deploying SNAPSHOT to GitHub Packages..."
    
    local deploy_cmd="mvn clean deploy -Pgithub-packages-snapshot -Ddeploy.github.snapshot=true -B"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would execute: $deploy_cmd"
        return 0
    fi
    
    if $deploy_cmd; then
        log_success "Successfully deployed SNAPSHOT to GitHub Packages"
        show_deployment_info "github-snapshot"
    else
        log_error "Failed to deploy SNAPSHOT to GitHub Packages"
        exit 1
    fi
}

# Deploy to GitHub Packages (releases)
deploy_github_release() {
    log_info "Deploying RELEASE to GitHub Packages..."
    
    local deploy_cmd="mvn clean deploy -Pgithub-packages -Ddeploy.github=true -B"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would execute: $deploy_cmd"
        return 0
    fi
    
    if $deploy_cmd; then
        log_success "Successfully deployed RELEASE to GitHub Packages"
        show_deployment_info "github-release"
    else
        log_error "Failed to deploy RELEASE to GitHub Packages"
        exit 1
    fi
}

# Deploy to Maven Central
deploy_maven_central() {
    log_info "Deploying to Maven Central..."
    
    # Check GPG setup for signing
    if ! command -v gpg &> /dev/null; then
        log_error "GPG is not installed. Required for Maven Central deployment."
        exit 1
    fi
    
    local deploy_cmd="mvn clean deploy -Pmaven-central -Ddeploy.central=true -B"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would execute: $deploy_cmd"
        return 0
    fi
    
    log_warning "Maven Central deployment requires manual approval in Nexus Repository Manager"
    log_info "URL: https://s01.oss.sonatype.org/"
    
    if $deploy_cmd; then
        log_success "Successfully deployed to Maven Central staging repository"
        show_deployment_info "maven-central"
    else
        log_error "Failed to deploy to Maven Central"
        exit 1
    fi
}

# Show deployment information
show_deployment_info() {
    local target="$1"
    local repo_info=$(gh repo view --json owner,name --jq '.owner.login + "/" + .name')
    
    echo
    log_success "=== Deployment Information ==="
    echo
    
    case "$target" in
        "github-snapshot"|"github-release")
            echo "🎉 Artifact deployed to GitHub Packages!"
            echo
            echo "Repository: $repo_info"
            echo "Version: $VERSION"
            echo "Package URL: https://github.com/FastFilter/fastfilter_java/packages"
            echo
            echo "To use in your project:"
            echo "  <dependency>"
            echo "    <groupId>io.github.fastfilter</groupId>"
            echo "    <artifactId>fastfilter</artifactId>"
            echo "    <version>$VERSION</version>"
            echo "  </dependency>"
            echo
            echo "Add to your settings.xml or pom.xml:"
            echo "  <repository>"
            echo "    <id>github</id>"
            echo "    <url>https://maven.pkg.github.com/FastFilter/fastfilter_java</url>"
            echo "  </repository>"
            ;;
        "maven-central")
            echo "🎉 Artifact deployed to Maven Central staging!"
            echo
            echo "Version: $VERSION"
            echo "Staging URL: https://s01.oss.sonatype.org/"
            echo "Search URL: https://search.maven.org/artifact/io.github.fastfilter/fastfilter"
            echo
            echo "Manual steps required:"
            echo "  1. Login to Nexus Repository Manager"
            echo "  2. Review staging repository"
            echo "  3. Close and release the staging repository"
            echo "  4. Artifacts will sync to Maven Central within 2-4 hours"
            ;;
    esac
}

# Create GitHub release
create_github_release() {
    if [[ "$VERSION" == *"-SNAPSHOT" ]]; then
        log_info "Skipping GitHub release creation for SNAPSHOT version"
        return 0
    fi
    
    log_info "Creating GitHub release for version $VERSION..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "DRY RUN: Would create GitHub release v$VERSION"
        return 0
    fi
    
    # Check if release already exists
    if gh release view "v$VERSION" &> /dev/null; then
        log_warning "Release v$VERSION already exists"
        return 0
    fi
    
    # Create release with auto-generated notes
    if gh release create "v$VERSION" \
        --title "FastFilter Java v$VERSION" \
        --generate-notes \
        target/*.jar jmh/target/benchmarks.jar; then
        log_success "GitHub release v$VERSION created"
    else
        log_warning "Failed to create GitHub release (deployment was still successful)"
    fi
}

# Main deployment logic
deploy() {
    case "$DEPLOYMENT_TARGET" in
        "snapshot")
            deploy_github_snapshot
            ;;
        "release")
            deploy_github_release
            if [[ "$VERSION" != *"-SNAPSHOT" ]]; then
                create_github_release
            fi
            ;;
        "central")
            deploy_maven_central
            if [[ "$VERSION" != *"-SNAPSHOT" ]]; then
                create_github_release
            fi
            ;;
        "all")
            if [[ "$VERSION" == *"-SNAPSHOT" ]]; then
                deploy_github_snapshot
            else
                deploy_github_release
                deploy_maven_central
                create_github_release
            fi
            ;;
        *)
            log_error "Unknown deployment target: $DEPLOYMENT_TARGET"
            exit 1
            ;;
    esac
}

# Main execution
main() {
    echo "==============================================";
    echo "FastFilter Java - Artifact Deployment";
    echo "==============================================";
    echo
    
    parse_arguments "$@"
    check_prerequisites
    detect_version
    
    echo
    log_info "Deployment Configuration:"
    echo "  Target: $DEPLOYMENT_TARGET"
    echo "  Version: $VERSION"
    echo "  Dry Run: $DRY_RUN"
    echo "  Skip Tests: $SKIP_TESTS"
    echo
    
    if [[ "$DRY_RUN" == "false" ]]; then
        read -p "Proceed with deployment? [y/N]: " -r
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Deployment cancelled by user"
            exit 0
        fi
    fi
    
    set_version
    run_tests
    deploy
    
    echo
    log_success "=== Deployment Complete ==="
    
    if [[ "$DRY_RUN" == "true" ]]; then
        echo
        log_info "This was a dry run. No actual deployment occurred."
        log_info "Remove --dry-run flag to perform actual deployment."
    fi
}

# Run main function
main "$@"