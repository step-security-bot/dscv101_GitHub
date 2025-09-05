#!/usr/bin/env bash

# scripts/update-deps.sh

# Manual dependency update script with safety checks

set -euo pipefail

# Colors for output

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration

BACKUP_DIR="./flake-backups"
CONFIG_NAME="blazar"  # Change this to match your NixOS configuration name

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

# Create backup

create_backup() {
local backup_name="flake.lock.$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
cp flake.lock "$BACKUP_DIR/$backup_name"
log_info "Created backup: $BACKUP_DIR/$backup_name"
echo "$BACKUP_DIR/$backup_name"
}

# Show current flake status

show_status() {
log_info "Current flake status:"
echo
nix flake metadata --json | jq -r '.locks.nodes | to_entries[] | select(.value.original) | "  (.key): (.value.locked.rev // .value.locked.narHash // "unknown")[0:8] ((.value.locked.lastModified // 0 | strftime("%Y-%m-%d")))"'
echo
}

# Check for security advisories

check_security() {
log_info "Checking for recent security advisories…"

```
if command -v curl >/dev/null; then
    local recent_count
    recent_count=$(curl -s "https://discourse.nixos.org/c/announcements/security/67.json" | 
                  jq -r --arg date "$(date -d '7 days ago' '+%Y-%m-%d')" '[.topic_list.topics[] | select(.created_at > $date)] | length' 2>/dev/null || echo "0")
    
    if [ "$recent_count" -gt 0 ]; then
        log_warning "Found $recent_count recent security announcements (last 7 days)"
        log_warning "Consider running a security-focused update"
    else
        log_success "No recent security announcements found"
    fi
else
    log_warning "curl not available - skipping security check"
fi
echo
```

}

# Test the configuration

test_config() {
local test_failed=false

```
log_info "Testing flake configuration..."

# Test flake check
if nix flake check --show-trace; then
    log_success "Flake check passed"
else
    log_error "Flake check failed"
    test_failed=true
fi

# Test build
log_info "Testing build..."
if nix build ".#nixosConfigurations.$CONFIG_NAME.config.system.build.toplevel" --show-trace; then
    log_success "Build test passed"
else
    log_error "Build test failed"
    test_failed=true
fi

if [ "$test_failed" = true ]; then
    return 1
fi

return 0
```

}

# Run security scan

security_scan() {
log_info "Running security vulnerability scan…"

```
if ! command -v nix >/dev/null; then
    log_error "Nix not found in PATH"
    return 1
fi

local system_path
system_path=$(nix build ".#nixosConfigurations.$CONFIG_NAME.config.system.build.toplevel" --print-out-paths 2>/dev/null)

if [ -z "$system_path" ]; then
    log_error "Failed to build system for security scan"
    return 1
fi

local scan_output
scan_output=$(mktemp)

if nix run nixpkgs#vulnix -- --system x86_64-linux --json "$system_path" > "$scan_output" 2>/dev/null; then
    local vuln_count critical_count
    vuln_count=$(jq 'length' "$scan_output" 2>/dev/null || echo "0")
    critical_count=$(jq '[.[] | select(.severity == "CRITICAL" or .severity == "HIGH")] | length' "$scan_output" 2>/dev/null || echo "0")
    
    echo
    if [ "$critical_count" -gt 0 ]; then
        log_error "Found $critical_count critical/high severity vulnerabilities (total: $vuln_count)"
        log_warning "Consider updating vulnerable packages"
    elif [ "$vuln_count" -gt 0 ]; then
        log_warning "Found $vuln_count non-critical vulnerabilities"
    else
        log_success "No known vulnerabilities detected"
    fi
else
    log_warning "Security scan failed or vulnix not available"
fi

rm -f "$scan_output"
echo
```

}

# Restore from backup

restore_backup() {
local backup_file="$1"

```
if [ ! -f "$backup_file" ]; then
    log_error "Backup file not found: $backup_file"
    return 1
fi

cp "$backup_file" flake.lock
log_success "Restored from backup: $backup_file"
```

}

# Update functions

update_all() {
log_info "Updating all flake inputs…"
nix flake update
}

update_nixpkgs() {
log_info "Updating nixpkgs only…"
nix flake lock --update-input nixpkgs
}

update_specific() {
local input="$1"
log_info "Updating input: $input"
nix flake lock --update-input "$input"
}

update_security() {
log_info "Updating security-critical inputs…"
local security_inputs=("nixpkgs" "home-manager" "nixos-hardware")

```
for input in "${security_inputs[@]}"; do
    if nix flake metadata --json | jq -e ".locks.nodes[\"$input\"]" >/dev/null 2>&1; then
        log_info "Updating $input..."
        nix flake lock --update-input "$input" || log_warning "Failed to update $input"
    else
        log_warning "Input $input not found in flake"
    fi
done
```

}

# Show usage

usage() {
cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
status              Show current flake input status
security-check      Check for recent security advisories
security-scan       Run vulnerability scan on current system

update-all         Update all flake inputs
update-nixpkgs     Update only nixpkgs
update-security    Update security-critical inputs only
update-input INPUT Update specific input

test               Test current configuration

backup             Create backup of current flake.lock
restore BACKUP     Restore from backup file
list-backups       List available backups

Options:
--no-test          Skip testing after update
--no-backup        Skip creating backup before update
--config NAME      Override NixOS configuration name (default: $CONFIG_NAME)

Examples:
$0 status                           # Show current status
$0 update-all                       # Update everything with full testing
$0 update-nixpkgs --no-test         # Quick nixpkgs update without testing
$0 update-input home-manager        # Update specific input
$0 security-scan                    # Check for vulnerabilities
$0 restore ./flake-backups/flake.lock.20241201_120000
EOF
}

# Main script logic

main() {
local command="${1:-}"
local no_test=false
local no_backup=false

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        --no-test)
            no_test=true
            shift
            ;;
        --no-backup)
            no_backup=true
            shift
            ;;
        --config)
            CONFIG_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [ -z "$command" ]; then
                command="$1"
            fi
            shift
            ;;
    esac
done

# Ensure we're in a flake directory
if [ ! -f "flake.nix" ]; then
    log_error "No flake.nix found in current directory"
    exit 1
fi

case "$command" in
    status)
        show_status
        ;;
    security-check)
        check_security
        ;;
    security-scan)
        security_scan
        ;;
    backup)
        create_backup
        ;;
    list-backups)
        if [ -d "$BACKUP_DIR" ]; then
            log_info "Available backups:"
            ls -la "$BACKUP_DIR/"
        else
            log_info "No backups found"
        fi
        ;;
    restore)
        local backup_file="${2:-}"
        if [ -z "$backup_file" ]; then
            log_error "Please specify backup file to restore"
            exit 1
        fi
        restore_backup "$backup_file"
        ;;
    test)
        test_config
        ;;
    update-all|update-nixpkgs|update-security)
        # Create backup unless disabled
        local backup_file=""
        if [ "$no_backup" = false ]; then
            backup_file=$(create_backup)
        fi
        
        # Perform update
        case "$command" in
            update-all)
                update_all
                ;;
            update-nixpkgs)
                update_nixpkgs
                ;;
            update-security)
                update_security
                ;;
        esac
        
        # Test unless disabled
        if [ "$no_test" = false ]; then
            if ! test_config; then
                log_error "Tests failed after update"
                if [ -n "$backup_file" ]; then
                    log_info "Restoring from backup..."
                    restore_backup "$backup_file"
                fi
                exit 1
            fi
            
            # Run security scan
            security_scan
        fi
        
        log_success "Update completed successfully"
        ;;
    update-input)
        local input="${2:-}"
        if [ -z "$input" ]; then
            log_error "Please specify input name to update"
            exit 1
        fi
        
        # Create backup unless disabled
        local backup_file=""
        if [ "$no_backup" = false ]; then
            backup_file=$(create_backup)
        fi
        
        update_specific "$input"
        
        # Test unless disabled
        if [ "$no_test" = false ]; then
            if ! test_config; then
                log_error "Tests failed after update"
                if [ -n "$backup_file" ]; then
                    log_info "Restoring from backup..."
                    restore_backup "$backup_file"
                fi
                exit 1
            fi
        fi
        
        log_success "Input $input updated successfully"
        ;;
    ""|help)
        usage
        ;;
    *)
        log_error "Unknown command: $command"
        usage
        exit 1
        ;;
esac
}

# Run main function
main "$@"
