#!/bin/bash

# ==============================================
# setup-github-credentials.sh
# Automated GitHub credentials setup for FastFilter Java
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

# Check if gh CLI is installed
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) is not installed. Please install it first:"
        echo "  macOS: brew install gh"
        echo "  Ubuntu: sudo apt install gh"
        echo "  Windows: choco install gh"
        exit 1
    fi
    
    log_info "GitHub CLI version: $(gh --version | head -1)"
}

# Check if user is authenticated
check_gh_auth() {
    if ! gh auth status &> /dev/null; then
        log_warning "Not authenticated with GitHub CLI"
        log_info "Starting GitHub authentication..."
        gh auth login --scopes "repo,packages:write,packages:read"
        log_success "GitHub authentication completed"
    else
        log_success "Already authenticated with GitHub CLI"
        gh auth status
    fi
}

# Get repository information
get_repo_info() {
    REPO_OWNER=$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || echo "")
    REPO_NAME=$(gh repo view --json name --jq '.name' 2>/dev/null || echo "")
    
    if [[ -z "$REPO_OWNER" || -z "$REPO_NAME" ]]; then
        log_error "Could not determine repository information"
        log_info "Make sure you're in a GitHub repository directory"
        exit 1
    fi
    
    log_info "Repository: $REPO_OWNER/$REPO_NAME"
}

# Setup repository secrets for GitHub Actions
setup_github_secrets() {
    log_info "Setting up GitHub repository secrets..."
    
    # Generate a GitHub token with appropriate permissions
    log_info "Creating GitHub token for Maven deployment..."
    
    # Get current GitHub token
    GITHUB_TOKEN=$(gh auth token)
    
    # Set GITHUB_TOKEN secret (for Actions)
    echo "$GITHUB_TOKEN" | gh secret set GITHUB_TOKEN
    log_success "GITHUB_TOKEN secret set"
    
    # Generate username (GitHub username for Maven)
    GITHUB_USERNAME=$(gh api user --jq '.login')
    echo "$GITHUB_USERNAME" | gh secret set MAVEN_USERNAME
    log_success "MAVEN_USERNAME secret set to: $GITHUB_USERNAME"
    
    # Use GitHub token as Maven password for GitHub Packages
    echo "$GITHUB_TOKEN" | gh secret set MAVEN_PASSWORD
    log_success "MAVEN_PASSWORD secret set (using GitHub token)"
    
    # Optional: GPG setup for signing
    setup_gpg_signing
}

# Setup GPG signing (optional)
setup_gpg_signing() {
    log_info "Setting up GPG signing (optional)..."
    
    read -p "Do you want to set up GPG signing for releases? [y/N]: " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        setup_gpg_keys
    else
        log_info "Skipping GPG signing setup"
        # Set empty GPG passphrase to disable signing
        echo "" | gh secret set GPG_PASSPHRASE
    fi
}

# Setup GPG keys
setup_gpg_keys() {
    log_info "Setting up GPG keys for artifact signing..."
    
    # Check if GPG is installed
    if ! command -v gpg &> /dev/null; then
        log_error "GPG is not installed. Please install it first:"
        echo "  macOS: brew install gnupg"
        echo "  Ubuntu: sudo apt install gnupg"
        echo "  Windows: Download from https://gpg4win.org/"
        return 1
    fi
    
    # List existing keys
    log_info "Existing GPG keys:"
    gpg --list-secret-keys --keyid-format=long || log_warning "No GPG keys found"
    
    read -p "Do you want to create a new GPG key? [y/N]: " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        create_gpg_key
    fi
    
    # Get GPG key ID
    log_info "Available GPG keys:"
    gpg --list-secret-keys --keyid-format=long
    
    read -p "Enter the GPG key ID to use (or press Enter to skip): " GPG_KEY_ID
    if [[ -n "$GPG_KEY_ID" ]]; then
        # Export GPG private key
        GPG_PRIVATE_KEY=$(gpg --armor --export-secret-keys "$GPG_KEY_ID")
        echo "$GPG_PRIVATE_KEY" | gh secret set GPG_PRIVATE_KEY
        log_success "GPG_PRIVATE_KEY secret set"
        
        # Get GPG passphrase
        read -s -p "Enter GPG passphrase (or press Enter for no passphrase): " GPG_PASSPHRASE
        echo
        echo "$GPG_PASSPHRASE" | gh secret set GPG_PASSPHRASE
        log_success "GPG_PASSPHRASE secret set"
    fi
}

# Create new GPG key
create_gpg_key() {
    log_info "Creating new GPG key..."
    
    read -p "Enter your name: " GPG_NAME
    read -p "Enter your email: " GPG_EMAIL
    
    cat > /tmp/gpg_key_config << EOF
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: $GPG_NAME
Name-Email: $GPG_EMAIL
Expire-Date: 2y
Passphrase: 
%commit
EOF
    
    gpg --batch --generate-key /tmp/gpg_key_config
    rm /tmp/gpg_key_config
    
    log_success "GPG key created successfully"
    log_info "Don't forget to upload your public key to key servers:"
    log_info "  gpg --keyserver keyserver.ubuntu.com --send-keys <KEY_ID>"
}

# Setup local development environment
setup_local_env() {
    log_info "Setting up local development environment..."
    
    # Create .env.local with credentials
    if [[ ! -f ".env.local" ]]; then
        cat > .env.local << EOF
# Local development environment
# Generated by setup-github-credentials.sh

# GitHub credentials
GITHUB_TOKEN=$(gh auth token)
GITHUB_USERNAME=$(gh api user --jq '.login')

# Maven deployment
MAVEN_USERNAME=$(gh api user --jq '.login')
MAVEN_PASSWORD=$(gh auth token)

# Repository information
GITHUB_REPOSITORY=$REPO_OWNER/$REPO_NAME
GITHUB_REPOSITORY_OWNER=$REPO_OWNER

# Package registry
PACKAGE_REGISTRY_URL=https://maven.pkg.github.com/$REPO_OWNER/$REPO_NAME
EOF
        log_success "Created .env.local with GitHub credentials"
        log_warning "Keep .env.local secure and never commit it to git"
    else
        log_info ".env.local already exists, skipping creation"
    fi
}

# Setup Maven settings.xml
setup_maven_settings() {
    log_info "Setting up Maven settings.xml..."
    
    MAVEN_HOME=${MAVEN_HOME:-$HOME/.m2}
    SETTINGS_FILE="$MAVEN_HOME/settings.xml"
    
    # Create .m2 directory if it doesn't exist
    mkdir -p "$MAVEN_HOME"
    
    # Backup existing settings.xml
    if [[ -f "$SETTINGS_FILE" ]]; then
        cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing settings.xml"
    fi
    
    GITHUB_USERNAME=$(gh api user --jq '.login')
    GITHUB_TOKEN=$(gh auth token)
    
    cat > "$SETTINGS_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0
          http://maven.apache.org/xsd/settings-1.0.0.xsd">
    
    <servers>
        <!-- GitHub Packages -->
        <server>
            <id>github</id>
            <username>$GITHUB_USERNAME</username>
            <password>$GITHUB_TOKEN</password>
        </server>
        
        <!-- GitHub Packages (alternative) -->
        <server>
            <id>github-packages</id>
            <username>$GITHUB_USERNAME</username>
            <password>$GITHUB_TOKEN</password>
        </server>
        
        <!-- Maven Central (if using OSSRH) -->
        <server>
            <id>ossrh</id>
            <username>\${env.MAVEN_CENTRAL_USERNAME}</username>
            <password>\${env.MAVEN_CENTRAL_PASSWORD}</password>
        </server>
    </servers>
    
    <profiles>
        <profile>
            <id>github</id>
            <repositories>
                <repository>
                    <id>github</id>
                    <url>https://maven.pkg.github.com/$REPO_OWNER/$REPO_NAME</url>
                    <snapshots>
                        <enabled>true</enabled>
                    </snapshots>
                    <releases>
                        <enabled>true</enabled>
                    </releases>
                </repository>
            </repositories>
        </profile>
    </profiles>
    
    <activeProfiles>
        <activeProfile>github</activeProfile>
    </activeProfiles>
</settings>
EOF
    
    log_success "Maven settings.xml configured for GitHub Packages"
    log_info "Settings file: $SETTINGS_FILE"
}

# Verify setup
verify_setup() {
    log_info "Verifying setup..."
    
    # Check GitHub authentication
    if gh auth status &> /dev/null; then
        log_success "✓ GitHub CLI authenticated"
    else
        log_error "✗ GitHub CLI not authenticated"
    fi
    
    # Check repository secrets
    log_info "Repository secrets:"
    gh secret list | grep -E "(GITHUB_TOKEN|MAVEN_USERNAME|MAVEN_PASSWORD|GPG_)" || log_warning "Some secrets may be missing"
    
    # Check local environment
    if [[ -f ".env.local" ]]; then
        log_success "✓ Local environment file created"
    else
        log_warning "⚠ Local environment file not found"
    fi
    
    # Check Maven settings
    if [[ -f "$HOME/.m2/settings.xml" ]]; then
        log_success "✓ Maven settings.xml configured"
    else
        log_warning "⚠ Maven settings.xml not found"
    fi
}

# Main execution
main() {
    echo "==============================================";
    echo "FastFilter Java - GitHub Credentials Setup";
    echo "==============================================";
    echo
    
    log_info "Starting automated GitHub credentials setup..."
    
    check_gh_cli
    check_gh_auth
    get_repo_info
    
    echo
    log_info "Repository: $REPO_OWNER/$REPO_NAME"
    echo
    
    read -p "Continue with credential setup? [Y/n]: " -r
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        log_info "Setup cancelled by user"
        exit 0
    fi
    
    setup_github_secrets
    setup_local_env
    setup_maven_settings
    verify_setup
    
    echo
    log_success "=== Setup Complete ==="
    echo
    log_info "Next steps:"
    echo "  1. Test deployment: mvn deploy -Pgithub-packages"
    echo "  2. Check GitHub Packages: https://github.com/$REPO_OWNER/$REPO_NAME/packages"
    echo "  3. Review workflow files for deployment automation"
    echo
    log_warning "Keep your credentials secure:"
    echo "  - Never commit .env.local to git"
    echo "  - Regularly rotate your GitHub tokens"
    echo "  - Use repository secrets for CI/CD"
}

# Run main function
main "$@"