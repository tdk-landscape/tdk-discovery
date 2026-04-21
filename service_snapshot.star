# =============================================================================
# 📸 SERVICE SNAPSHOT - Starlark Interface
# =============================================================================
# Provides Starlark functions for snapshot-based incremental service discovery
# =============================================================================

# Python script path (relative to Tiltfile)
_SNAPSHOT_SCRIPT = ".tilt/topologies/tilt/discovery/service_snapshot.py"

def _run_snapshot_command(cmd):
    """Run a snapshot command via Python script."""
    result = local(
        "python3 " + _SNAPSHOT_SCRIPT + " " + cmd,
        quiet=True,
        echo_off=True
    )
    return str(result)

def save_snapshot(services):
    """
    Save current service list to snapshot file.
    
    Args:
        services: List of service.json file paths
    """
    # Use Python to save snapshot directly
    result = local(
        "cd " + config.main_dir + " && python3 " + _SNAPSHOT_SCRIPT + " save",
        quiet=True,
        echo_off=True
    )
    
    return str(result)

def load_from_file():
    """
    Load previous snapshot from file.
    
    Returns:
        Dict with 'timestamp', 'services', 'count'
    """
    result = _run_snapshot_command("load")
    
    # Parse JSON result
    if result and result.strip():
        # In Starlark, we can't use try/except, so we just try to decode
        parsed = decode_json(result)
        if parsed:
            return parsed
    
    # Return empty snapshot on error
    return {
        "timestamp": None,
        "services": [],
        "count": 0
    }

def diff_snapshots(old_snapshot, current_services):
    """
    Compare old snapshot with current services.
    
    Args:
        old_snapshot: Previous snapshot dict
        current_services: Current list of service paths
    
    Returns:
        Struct with 'added' and 'removed' lists
    """
    old_set = {}
    for svc in old_snapshot.get("services", []):
        old_set[svc] = True
    
    current_set = {}
    for svc in current_services:
        current_set[svc] = True
    
    # Find added services
    added = []
    for svc in current_services:
        if svc not in old_set:
            added.append(svc)
    
    # Find removed services
    removed = []
    for svc in old_snapshot.get("services", []):
        if svc not in current_set:
            removed.append(svc)
    
    return struct(
        added=added,
        removed=removed,
        added_count=len(added),
        removed_count=len(removed)
    )

def get_current_services(scan_roots=["services/product"]):
    """
    Scan filesystem for current service.json files.
    
    Args:
        scan_roots: List of root directories to scan
    
    Returns:
        List of service.json file paths (relative to project root)
    """
    all_services = []
    
    for root in scan_roots:
        # Use find command to locate service.json files
        cmd = "find " + root + " -type f -name 'service.json' 2>/dev/null | sort"
        result = local(cmd, quiet=True, echo_off=True)
        
        if result:
            lines = str(result).strip().split("\n")
            for line in lines:
                line = line.strip()
                if line:
                    all_services.append(line)
    
    return all_services

def snapshot_exists():
    """Check if snapshot file exists."""
    result = local(
        "test -f .tilt/service-snapshot.json && echo 'yes' || echo 'no'",
        quiet=True,
        echo_off=True
    )
    return str(result).strip() == "yes"

# Export public API
ServiceSnapshot = struct(
    save=save_snapshot,
    load_from_file=load_from_file,
    diff=diff_snapshots,
    scan=get_current_services,
    exists=snapshot_exists,
)
