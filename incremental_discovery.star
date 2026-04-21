# =============================================================================
# 📈 INCREMENTAL DISCOVERY - Register New Services Dynamically
# =============================================================================
# Handles registration of newly detected services without full Tilt restart
# =============================================================================

load("./registry.star", "CacheOps", "get_app_services", "_DISCOVERY_CACHE")
load("./discovery_orchestrator.star", "_normalize_manifest")
load("../resources/orchestrator/generators/manifest_resource.star", "ManifestResource")
load("../manifest/loader.star", "ManifestLoader")
load("../../../../.tilt/TILT_SERVICE_DEFAULTS.star", "BASE_PORT_BACKEND")

def register_new_service(service_path, manifest, ctx, auto_init=True, verbose=False):
    """
    Register a newly discovered service and create its Tilt resources.
    
    Args:
        service_path: Path to service directory
        manifest: Loaded manifest dict
        ctx: Tilt context with generators and config
        auto_init: Whether to auto-init resources
        verbose: Enable verbose logging
    
    Returns:
        Struct with success status and created resources
    """
    service_name = manifest.get("appName", "")
    app_type = manifest.get("appType", "backend")
    domain = manifest.get("domain", "")
    
    if verbose:
        print("🚀 Registering new service: {}".format(service_name))
    
    # Normalize manifest to discovery format
    resource = _normalize_manifest(manifest, service_path)
    
    # Build service structure
    service_dict = {
        "name": service_name,
        "path": service_path,
        "labels": ["app." + service_name],
        "resources": [resource],
    }
    
    # Add to cache
    if not CacheOps.add(service_dict):
        print("⚠️  Failed to add {} to cache (may already exist)".format(service_name))
        return struct(success=False, error="cache_add_failed")
    
    # Create Tilt resources
    created_resources = []
    
    # Create config-gen resource
    config_gen_name = _create_config_gen_resource(
        service_name,
        resource,
        service_path,
        manifest,
        ctx,
        auto_init
    )
    created_resources.append(config_gen_name)
    
    # Create Docker build resource
    docker_resource = _create_docker_resource(
        service_name,
        resource,
        service_path,
        manifest,
        ctx
    )
    if docker_resource:
        created_resources.append(docker_resource)
    
    # Create additional resources based on app type
    if app_type == "frontend":
        frontend_resources = _create_frontend_resources(
            service_name,
            resource,
            service_path,
            manifest,
            ctx,
            auto_init
        )
        created_resources.extend(frontend_resources)
    
    # Log success
    print("✅ Auto-registered: {}".format(service_name))
    print("  └─ Domain: {}".format(domain))
    print("  └─ Type: {}".format(app_type))
    print("  └─ Resources: {} created".format(len(created_resources)))
    
    return struct(
        success=True,
        service_name=service_name,
        resources=created_resources,
        count=len(created_resources)
    )

def _create_config_gen_resource(service_name, resource, service_path, manifest, ctx, auto_init):
    """Create config-gen resource for a service."""
    # Get backend manifest if frontend
    backend_manifest = None
    if resource.get("frontend", False):
        backend_name = resource.get("backendName", service_name.replace("-frontend", "-backend"))
        backend_manifest = _get_backend_manifest(backend_name)
    
    # Use ManifestResource to create config-gen
    resource_config = {
        "name": resource.get("name", service_name),
        "port": resource.get("port", BASE_PORT_BACKEND),
        "_manifest": manifest,
    }
    
    config_gen_name = ManifestResource.create_config_resource(
        service_name,
        resource_config,
        service_path,
        manifest,
        backend_manifest,
        ctx
    )
    
    return config_gen_name

def _create_docker_resource(service_name, resource, service_path, manifest, ctx):
    """Create Docker build resource for a service."""
    # Docker resource is created through the orchestrator
    # This is handled when the config-gen resource runs
    # Return the expected resource name for tracking
    return service_name

def _create_frontend_resources(service_name, resource, service_path, manifest, ctx, auto_init):
    """Create additional resources for frontend services."""
    resources = []
    
    # Frontend dev server resource is auto-created by the orchestrator
    # when processing the manifest
    
    return resources

def _get_backend_manifest(backend_name):
    """Look up backend manifest for a frontend service."""
    # Search in current cache
    for service in CacheOps.stats().services:
        if service.get("name") == backend_name:
            resources = service.get("resources", [])
            for res in resources:
                if res.get("_manifest"):
                    return res.get("_manifest")
    return None

def validate_service_structure(service_path):
    """
    Validate that a service has complete structure before registration.
    
    Args:
        service_path: Path to service directory
    
    Returns:
        Struct with valid status and missing files
    """
    required_files = ["service.json", "package.json"]
    missing = []
    
    for filename in required_files:
        filepath = service_path + "/" + filename
        result = local(
            "test -f {} && echo 'yes' || echo 'no'".format(filepath),
            quiet=True,
            echo_off=True
        )
        if str(result).strip() != "yes":
            missing.append(filename)
    
    return struct(
        valid=len(missing) == 0,
        missing=missing,
        has_service_json="service.json" not in missing,
        has_package_json="package.json" not in missing
    )

def check_duplicate_service(service_name):
    """
    Check if a service name already exists.
    
    Args:
        service_name: Name to check
    
    Returns:
        Struct with duplicate status and existing info
    """
    if CacheOps.has(service_name):
        # Find existing service path
        for svc in get_app_services():
            if svc.get("name") == service_name:
                return struct(
                    duplicate=True,
                    existing_path=svc.get("path", "unknown"),
                    message="Service '{}' already exists at {}".format(
                        service_name,
                        svc.get("path", "unknown")
                    )
                )
    
    return struct(duplicate=False)

# Export public API
IncrementalDiscovery = struct(
    register=register_new_service,
    validate_structure=validate_service_structure,
    check_duplicate=check_duplicate_service,
)
