# =============================================================================
# 📋 TILT SDK - MANIFEST NORMALIZATION & DISCOVERY
# =============================================================================
# Path: .tilt/topologies/tilt/discovery/manifest/normalize.star
# Purpose: Normalize manifests and provide helper accessors
# =============================================================================

load('../../../tilt/manifest/constants.star', 'MANIFEST_DEFAULTS', 'MANIFEST_FILENAME')
load('./loading.star', 'apply_manifest_defaults', 'check_prisma_folder', 'get_default_syncs_for_type')
load('./validation.star', 'validate_manifest')
load('../../common/utils.star', 'Utils')
load('../../../platform/docker/constants.star', 'PlatformDockerConstants')
load('../../../../../.tilt/TILT_TECH_STACK.star', 'RUNTIME', 'MESSAGING')


def _load_and_normalize(manifest_path, warn_only=True):
    """
    🎯 MAIN ENTRY POINT: Load manifest and normalize to full resource config.
    
    This function is the bridge between the discovery system (registry.star)
    and the manifest loading system. It:
    
    1. Reads the JSON file
    2. Validates the structure
    3. Normalizes with smart defaults
    4. Computes labels, syncs, has_migrator
    5. Returns a resource-ready configuration
    
    Args:
        manifest_path: Full path to manifest file
        warn_only: If True, return None on error instead of failing
        
    Returns:
        Normalized manifest dict or None on error (if warn_only=True)
    """
    # Read manifest file
    content = read_file(manifest_path, default='')
    
    if not content or not str(content).strip():
        if warn_only:
            print("   ⚠️  Empty or missing manifest: " + manifest_path)
            return None
        fail("Empty or missing manifest: " + manifest_path)
    
    # Parse JSON
    manifest = decode_json(content)
    if manifest == None:
        if warn_only:
            print("   ⚠️  Invalid JSON in manifest: " + manifest_path)
            return None
        fail("Invalid JSON in manifest: " + manifest_path)
    
    # Validate
    issues = validate_manifest(manifest)
    if issues:
        if warn_only:
            for issue in issues:
                print("   ⚠️  " + manifest_path + ": " + issue)
            return None
        fail("Manifest validation failed:\n" + "\n".join(issues))
    
    # Extract service path from manifest path
    service_path = manifest_path.rsplit('/', 1)[0]
    
    # Apply smart defaults
    normalized = apply_manifest_defaults(manifest, service_path)
    
    # Compute additional fields for registry compatibility
    app_name = normalized.get('appName', '')
    app_type = normalized.get('appType', 'backend')
    domain = normalized.get('domain', '')
    features = normalized.get('features', [])
    
    # 🎯 AUTO-COMPUTE labels from domain
    normalized['labels'] = ['app.' + domain]
    
    # 🎯 AUTO-DETECT has_migrator
    has_migrator = 'prisma' in features
    if not has_migrator:
        has_migrator = check_prisma_folder(service_path)
    normalized['has_migrator'] = has_migrator
    
    # 🎯 AUTO-COMPUTE syncs if not specified
    if normalized.get('syncs') == None:
        normalized['syncs'] = get_default_syncs_for_type(app_type, features)
    
    # 🎯 COMPUTE dockerfile path
    dockerfile = normalized.get('dockerfile', 'Dockerfile')
    normalized['dockerfile_path'] = app_name + '/' + dockerfile
    
    # 🎯 MARK as frontend if applicable
    if app_type == 'frontend':
        normalized['frontend'] = True
    
    # 🎯 EXTRACT dependencies for registry (supports both new and legacy fields)
    manifest_deps = normalized.get('dependencies')
    if manifest_deps == None:
        manifest_deps = normalized.get('internalDependencies', [])
    normalized['serviceDependencies'] = manifest_deps

    return normalized


def _discover_manifests_in_path(root_path):
    """
    Discover all manifest files under a root path.
    
    Args:
        root_path: Directory to search (e.g., 'services/product')
        
    Returns:
        List of manifest file paths
    """
    find_cmd = "find {root} -name '{filename}' -type f 2>/dev/null | sort".format(
        root=root_path,
        filename=MANIFEST_FILENAME
    )
    result = str(local(find_cmd, quiet=True))
    
    manifests = []
    if result:
        for line in result.strip().split('\n'):
            if line and line.strip():
                manifests.append(line.strip())
    
    return manifests


def _load_all_manifests(root_path, warn_only=True):
    """
    Load and normalize all manifests under a root path.
    
    Args:
        root_path: Directory to search (e.g., 'services/product')
        warn_only: If True, skip invalid manifests with warnings
        
    Returns:
        List of normalized manifest dicts
    """
    manifest_paths = _discover_manifests_in_path(root_path)
    manifests = []
    
    for path in manifest_paths:
        normalized = _load_and_normalize(path, warn_only=warn_only)
        if normalized:
            manifests.append(normalized)
    
    return manifests


def _get_port(manifest):
    """Get the service port from manifest."""
    return manifest.get('port', MANIFEST_DEFAULTS['port'])


def _get_database_url(manifest, host='localhost', port=5432):
    """
    Generate DATABASE_URL from manifest.
    
    Args:
        manifest: Manifest dictionary
        host: Database host (default: localhost)
        port: Database port (default: 5432)
        
    Returns:
        PostgreSQL connection string
    """
    db_name = manifest.get('databaseName', PlatformDockerConstants.get_db_name(manifest.get('domain', 'app')))
    return PlatformDockerConstants.get_tilt_database_url_template().format(
        host=host,
        port=port,
        db=db_name,
    )


def _print_summary(manifests):
    """
    Print formatted summary of loaded manifests.
    
    Args:
        manifests: List of manifest dictionaries
    """
    print("")
    print("📋 ═══════════════════════════════════════════════════════════════")
    print("📋  LOADED MANIFESTS")
    print("📋 ═══════════════════════════════════════════════════════════════")
    
    for m in manifests:
        status = "✅" if not m.get('_synthesized') else "⚡"
        app_name = m.get('appName', 'unknown')
        app_type = m.get('appType', 'unknown')
        port = m.get('port', 0)
        domain = m.get('domain', 'unknown')
        
        print("   {status} {name} | {type} | Port: {port} | Domain: {domain}".format(
            status=status,
            name=app_name,
            type=app_type,
            port=port,
            domain=domain,
        ))
    
    print("📋 ═══════════════════════════════════════════════════════════════")
    print("")


def _generate_manifest_template(app_name, domain, app_type='backend', port=4000):
    """
    🎯 TEMPLATE GENERATOR: Returns a string with a standard manifest.
    """
    template = {
        "$schema": "https://" + PlatformDockerConstants.EMAIL_DOMAIN + "/schemas/manifest-schema.json",
        "appName": app_name,
        "appType": app_type,
        "domain": domain,
        "port": port,
        "replicas": 1,
        "features": [MESSAGING, "infisical"],
        "internalDependencies": [],
        "runtime": RUNTIME
    }
    return Utils.encode_json(template)


def load_and_normalize(manifest_path, warn_only=True):
    return _load_and_normalize(manifest_path, warn_only=warn_only)


def discover_manifests_in_path(root_path):
    return _discover_manifests_in_path(root_path)


def load_all_manifests(root_path, warn_only=True):
    return _load_all_manifests(root_path, warn_only=warn_only)


def get_port(manifest):
    return _get_port(manifest)


def get_database_url(manifest, host='localhost', port=5432):
    return _get_database_url(manifest, host=host, port=port)


def print_summary(manifests):
    return _print_summary(manifests)


def generate_manifest_template(app_name, domain, app_type='backend', port=4000):
    return _generate_manifest_template(app_name, domain, app_type=app_type, port=port)
