# =============================================================================
# 👁️ DISCOVERY DAEMON - Continuous Service Monitoring
# =============================================================================
# Monitors filesystem for new services and triggers incremental registration
# =============================================================================

load("./service_snapshot.star", "ServiceSnapshot")
load("./registry.star", "CacheOps")
load("../manifest/loader.star", "ManifestLoader")
load("../../../../.tilt/TILT_SERVICE_DEFAULTS.star", "get_discovery_config")

_DISCOVERY_CONFIG = get_discovery_config()

def run_discovery_daemon(
    scan_interval_seconds=_DISCOVERY_CONFIG["scan_interval_seconds"],
    focus_mode=False,
    focus_domains=[],
    auto_init_new=True,
    on_new_service=None,
    verbose=False
):
    """
    Run the discovery daemon with continuous monitoring loop.
    
    This function is designed to be called as a serve_cmd in a local_resource,
    running continuously to monitor for new services.
    
    Args:
        scan_interval_seconds: Seconds between scans (default: from get_discovery_config)
        focus_mode: Whether focus mode is active
        focus_domains: List of domains to focus on (empty = all)
        auto_init_new: Whether to auto-init new services
        on_new_service: Callback function for new service detection
        verbose: Enable verbose logging
    """
    print("🔍 Discovery daemon starting...")
    print("  └─ Scan interval: {}s".format(scan_interval_seconds))
    print("  └─ Focus mode: {}".format("enabled" if focus_mode else "disabled"))
    print("  └─ Auto-init: {}".format("enabled" if auto_init_new else "disabled"))
    
    # Initialize snapshot if it doesn't exist
    if not ServiceSnapshot.exists():
        initial_services = ServiceSnapshot.scan()
        ServiceSnapshot.save(initial_services)
        print("✅ Initial snapshot created: {} services".format(len(initial_services)))
    
    # Continuous monitoring loop
    while True:
        start_time = 0
        
        # Load previous snapshot
        old_snapshot = ServiceSnapshot.load_from_file()
        
        # Scan for current services
        current_services = ServiceSnapshot.scan()
        
        # Compare to find changes
        diff = ServiceSnapshot.diff(old_snapshot, current_services)
        
        # Handle new services
        if diff.added_count > 0:
            if verbose:
                print("🔍 Detected {} new service(s)".format(diff.added_count))
            
            for service_path in diff.added:
                _handle_new_service(
                    service_path,
                    focus_mode=focus_mode,
                    focus_domains=focus_domains,
                    auto_init=auto_init_new,
                    verbose=verbose,
                    on_new_service=on_new_service
                )
        
        # Handle removed services (optional - just log for now)
        if diff.removed_count > 0 and verbose:
            print("🗑️  Detected {} removed service(s)".format(diff.removed_count))
            for service_path in diff.removed:
                print("  - {}".format(service_path))
        
        # Update snapshot if there were changes
        if diff.added_count > 0 or diff.removed_count > 0:
            ServiceSnapshot.save(current_services)
            if verbose:
                print("📸 Snapshot updated: {} services".format(len(current_services)))
        
        # Calculate sleep time (account for scan duration)
        elapsed = 0 - start_time
        sleep_time = max(0, scan_interval_seconds - elapsed)
        
        # Sleep before next scan
        if sleep_time > 0:
            sleep(sleep_time)

def _handle_new_service(
    service_path,
    focus_mode=False,
    focus_domains=[],
    auto_init=True,
    verbose=False,
    on_new_service=None
):
    """
    Process a newly detected service.
    
    Args:
        service_path: Path to service.json
        focus_mode: Whether to filter by domain
        focus_domains: Allowed domains
        auto_init: Whether to auto-init the service
        verbose: Verbose logging
        on_new_service: Optional callback
    """
    # Extract service directory
    service_dir = service_path.rsplit("/", 1)[0] if "/" in service_path else service_path
    
    # Check for package.json (complete service structure)
    package_json_path = service_dir + "/package.json"
    if not _file_exists(package_json_path):
        print("⏳ Waiting for package.json in {}".format(service_dir))
        return
    
    # Load and validate manifest
    load_result = ManifestLoader.load_from_file(service_path)
    if load_result.error:
        print("❌ Invalid manifest: {}".format(service_path))
        print("   └─ Error: {}".format(load_result.error))
        return
    
    manifest = load_result.manifest
    if not manifest:
        print("❌ Empty manifest: {}".format(service_path))
        return
    
    # Get service name
    service_name = manifest.get("appName", "")
    if not service_name:
        print("❌ Missing appName in: {}".format(service_path))
        return
    
    # Check for duplicates
    if CacheOps.has(service_name):
        if verbose:
            print("ℹ️  Service already registered: {}".format(service_name))
        return
    
    # Check focus mode
    domain = manifest.get("domain", "")
    if focus_mode and focus_domains and domain not in focus_domains:
        print("📋 Focus mode: Skipping {} (domain: {})".format(service_name, domain))
        return
    
    # Log detection
    print("🔍 New service detected: {}".format(service_name))
    print("  └─ Path: {}".format(service_path))
    print("  └─ Domain: {}".format(domain))
    print("  └─ Type: {}".format(manifest.get("appType", "unknown")))
    
    # Call callback if provided
    if on_new_service:
        on_new_service(service_name, service_path, manifest, auto_init)

def _file_exists(path):
    """Check if a file exists."""
    result = local(
        "test -f {} && echo 'yes' || echo 'no'".format(path),
        quiet=True,
        echo_off=True
    )
    return str(result).strip() == "yes"

def time_now():
    """Get current time in seconds (for timing)."""
    result = local("date +%s", quiet=True, echo_off=True)
    return int(str(result).strip())

def sleep(seconds):
    """Sleep for specified seconds."""
    local("sleep {}".format(seconds), quiet=True, echo_off=True)

# Export daemon functions
DiscoveryDaemon = struct(
    run=run_discovery_daemon,
)
