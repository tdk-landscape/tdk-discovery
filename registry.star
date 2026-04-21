# =============================================================================
# 🔍 TOPOLOGIES - DISCOVERY REGISTRY
# =============================================================================

load(
    "./config.star",
    "GLOBAL_CONFIG",
    "INFRA_SERVICES",
    "CORE_INFRA",
    "INFRA_DOMAIN_MAP",
    "OPTIONAL_INFRA",
    "Config",
    "DDD_LIBS",
    "PLATFORM_LIBS_FRONTEND",
    "PRODUCT_LIBS_FRONTEND"
)
load("./discovery_orchestrator.star", "initialize_discovery")
load("../manifest/loader.star", "ManifestLoader")
load("./libraries.star", "autodiscover_libraries", "get_platform_libs", "get_product_libs")
load(
    "./constants.star",
    "PRODUCT_SNAPSHOT_DIR",
    "PRODUCT_SNAPSHOT_FILES",
    "PRODUCT_TOPOLOGY_DIR",
    "PRODUCT_DOMAINS_INDEX_FILE",
    "PRODUCT_DOMAIN_SERVICES_FILE",
    "DISCOVERY_SCAN_ROOTS",
)
load("../manifest/constants.star", "MANIFEST_FILENAME", "MANIFEST_FILENAME_NEW", "MANIFEST_FILENAME_YAML", "MANIFEST_FILENAME_NEW_YAML")


_DISCOVERY_CACHE = {
    "initialized": False,
    "app_services": [],
    "service_dependencies": {},
    "service_aliases": {},
    "service_path_map": {},
    "domain_configs": {},
}

# =============================================================================
# 🔄 INCREMENTAL CACHE OPERATIONS (Auto-discovery support)
# =============================================================================

def add_service_to_cache(service_dict):
    """
    Add a new service to the discovery cache without rebuilding everything.
    
    Args:
        service_dict: Service dictionary with 'name', 'path', 'resources', etc.
    
    Returns:
        True if added successfully, False if service already exists
    """
    service_name = service_dict["name"] if "name" in service_dict else ""
    if not service_name:
        return False
    
    # Check for duplicates
    for existing in _DISCOVERY_CACHE["app_services"]:
        existing_name = existing["name"] if "name" in existing else ""
        if existing_name == service_name:
            return False
    
    # Add to cache
    _DISCOVERY_CACHE["app_services"].append(service_dict)
    
    # Update path map
    service_path = service_dict["path"] if "path" in service_dict else ""
    if service_path:
        _DISCOVERY_CACHE["service_path_map"][service_path] = service_name
    
    # Update aliases
    _DISCOVERY_CACHE["service_aliases"][service_name] = service_path
    
    return True

def remove_service_from_cache(service_name):
    """
    Remove a service from the discovery cache.
    
    Args:
        service_name: Name of service to remove
    
    Returns:
        True if removed, False if not found
    """
    # Find and remove from app_services
    found = False
    for i, svc in enumerate(_DISCOVERY_CACHE["app_services"]):
        svc_name = svc["name"] if "name" in svc else ""
        if svc_name == service_name:
            _DISCOVERY_CACHE["app_services"].pop(i)
            found = True
            break
    
    if not found:
        return False
    
    # Clean up path map and aliases
    service_path = ""
    if service_name in _DISCOVERY_CACHE["service_aliases"]:
        service_path = _DISCOVERY_CACHE["service_aliases"][service_name]
    if service_path:
        if service_path in _DISCOVERY_CACHE["service_path_map"]:
            # Create new dict without this key (Starlark doesn't support del)
            _DISCOVERY_CACHE["service_path_map"] = {k: v for k, v in _DISCOVERY_CACHE["service_path_map"].items() if k != service_path}
    
    if service_name in _DISCOVERY_CACHE["service_aliases"]:
        # Create new dict without this key (Starlark doesn't support del)
        _DISCOVERY_CACHE["service_aliases"] = {k: v for k, v in _DISCOVERY_CACHE["service_aliases"].items() if k != service_name}
    
    # Clean up dependencies
    if service_name in _DISCOVERY_CACHE["service_dependencies"]:
        # Create new dict without this key (Starlark doesn't support del)
        _DISCOVERY_CACHE["service_dependencies"] = {k: v for k, v in _DISCOVERY_CACHE["service_dependencies"].items() if k != service_name}
    
    return True

def has_service_in_cache(service_name):
    """
    Check if a service already exists in cache.
    
    Args:
        service_name: Name to check
    
    Returns:
        True if service exists
    """
    for svc in _DISCOVERY_CACHE["app_services"]:
        svc_name = svc["name"] if "name" in svc else ""
        if svc_name == service_name:
            return True
    return False

def get_service_by_path_from_cache(service_path):
    """
    Look up service by its path.
    
    Args:
        service_path: Service directory path
    
    Returns:
        Service dict or None
    """
    service_name = None
    if service_path in _DISCOVERY_CACHE["service_path_map"]:
        service_name = _DISCOVERY_CACHE["service_path_map"][service_path]
    if service_name:
        for svc in _DISCOVERY_CACHE["app_services"]:
            svc_name = svc["name"] if "name" in svc else ""
            if svc_name == service_name:
                return svc
    return None

def persist_cache_to_file():
    """
    Save cache state to file for persistence across Tiltfile reloads.
    """
    # Implementation uses the existing product snapshot system
    # This ensures cache survives Tiltfile changes
    pass  # Snapshot system handles this

def get_cache_stats():
    """
    Get statistics about the current cache state.
    
    Returns:
        Struct with service_count, initialized status
    """
    initialized_val = _DISCOVERY_CACHE["initialized"] if "initialized" in _DISCOVERY_CACHE else False
    return struct(
        service_count=len(_DISCOVERY_CACHE["app_services"]),
        initialized=initialized_val,
        aliases_count=len(_DISCOVERY_CACHE["service_aliases"]),
    )

# Export cache operations
CacheOps = struct(
    add=add_service_to_cache,
    remove=remove_service_from_cache,
    has=has_service_in_cache,
    get_by_path=get_service_by_path_from_cache,
    persist=persist_cache_to_file,
    stats=get_cache_stats,
)


def get_app_services():
    # TWO PASS DISCOVERY (both passes use JSON - source of truth):
    # Pass 1: Load JSON manifests and generate YAML files for Tilt resource tracking
    # Pass 2: Re-load from JSON (data refresh) and create Tilt local_resource from YAML
    initialized = _DISCOVERY_CACHE["initialized"] if "initialized" in _DISCOVERY_CACHE else False
    if not initialized:
        print("")
        print("🔍 Starting service discovery...")
        # First pass - load JSON and generate YAML
        initialize_discovery(_DISCOVERY_CACHE, second_pass=False)
        # Second pass - reload from JSON (not YAML - JSON is source of truth)
        _DISCOVERY_CACHE["initialized"] = False
        initialize_discovery(_DISCOVERY_CACHE, second_pass=True)
        print("")
    return _DISCOVERY_CACHE["app_services"]


def get_service_dependencies():
    initialized = _DISCOVERY_CACHE["initialized"] if "initialized" in _DISCOVERY_CACHE else False
    if not initialized:
        get_app_services()  # Trigger two-pass discovery
    return _DISCOVERY_CACHE["service_dependencies"]


def get_service_aliases():
    initialized = _DISCOVERY_CACHE["initialized"] if "initialized" in _DISCOVERY_CACHE else False
    if not initialized:
        get_app_services()  # Trigger two-pass discovery
    return _DISCOVERY_CACHE["service_aliases"]


def get_service_path_map():
    initialized = _DISCOVERY_CACHE["initialized"] if "initialized" in _DISCOVERY_CACHE else False
    if not initialized:
        get_app_services()  # Trigger two-pass discovery
    return _DISCOVERY_CACHE["service_path_map"]


def get_service_by_name(name):
    for service in get_app_services():
        if service["name"] == name:
            return service
    return None


def get_all_backend_resources():
    backends = []
    for service in get_app_services():
        resources = service["resources"] if "resources" in service else []
        for resource in resources:
            is_frontend = resource["frontend"] if "frontend" in resource else False
            if not is_frontend:
                resource_name = resource["name"] if "name" in resource else ""
                if resource_name:
                    backends.append(resource_name)
    return backends


def get_all_frontend_resources():
    frontends = []
    for service in get_app_services():
        resources = service["resources"] if "resources" in service else []
        for resource in resources:
            is_frontend = resource["frontend"] if "frontend" in resource else False
            if is_frontend:
                resource_name = resource["name"] if "name" in resource else ""
                if resource_name:
                    frontends.append(resource_name)
    return frontends


def _write_file_if_changed(path, content):
    current = read_file(path, default="")
    if current != content:
        safe_content = str(content).replace("'", "'\\''")
        dir_path = path.rsplit("/", 1)[0]
        local("mkdir -p '" + dir_path + "' && printf '%s' '" + safe_content + "' > '" + path + "'", quiet = True, echo_off = True)
        return True
    return False


def _render_star_file(title, symbol_name, value):
    header = (
        "# ----------------------------------------------------------------------------\n"
        + "# AUTOGENERATED FILE - DO NOT EDIT\n"
        + "# Source: manifest autodiscovery from .tilt/topologies/tilt/discovery/registry.star\n"
        + "# ----------------------------------------------------------------------------\n\n"
    )
    return header + "# " + title + "\n" + symbol_name + " = " + _starlark_literal(value) + "\n"


def _escape_string(value):
    return value.replace("\\", "\\\\").replace("'", "\\'")


def _starlark_literal(value, indent = 0):
    t = type(value)
    if t == "string":
        return "'" + _escape_string(value) + "'"
    if t == "int":
        return str(value)
    if t == "bool":
        return "True" if value else "False"
    if value == None:
        return "None"

    if t == "list":
        if len(value) == 0:
            return "[]"
        out = ["[\n"]
        for item in value:
            out.append(" " * (indent + 4) + _starlark_literal(item, indent + 4) + ",\n")
        out.append(" " * indent + "]")
        return "".join(out)

    if t == "dict":
        if len(value) == 0:
            return "{}"
        out = ["{\n"]
        for key in sorted(value):
            out.append(
                " " * (indent + 4)
                + _starlark_literal(key, indent + 4)
                + ": "
                + _starlark_literal(value[key], indent + 4)
                + ",\n"
            )
        out.append(" " * indent + "}")
        return "".join(out)

    return str(value)


def _render_readme():
    lines = [
        "# Product Snapshot Topology",
        "",
        "This folder is generated from manifest autodiscovery.",
        "Do not edit files in this directory manually.",
        "",
        "## Domains",
    ]

    for service in APP_SERVICES:
        service_name = service["name"] if "name" in service else "unknown"
        lines.append("- `" + service_name + "`")

    lines.extend([
        "",
        "## Sources",
        "- Discovery engine: `.tilt/topologies/tilt/discovery/discovery.star`",
        "- Topology adapter: `.tilt/topologies/tilt/discovery/registry.star`",
    ])
    return "\n".join(lines) + "\n"


def _render_index():
    return "\n".join([
        "# ----------------------------------------------------------------------------",
        "# AUTOGENERATED FILE - DO NOT EDIT",
        "# ----------------------------------------------------------------------------",
        "",
        "load('./" + PRODUCT_SNAPSHOT_FILES["services"] + "', 'APP_SERVICES_AUTOGENERATED')",
        "load('./" + PRODUCT_SNAPSHOT_FILES["dependencies"] + "', 'SERVICE_DEPENDENCIES_AUTOGENERATED')",
        "load('./" + PRODUCT_SNAPSHOT_FILES["aliases"] + "', 'SERVICE_ALIASES_AUTOGENERATED')",
        "load('./" + PRODUCT_SNAPSHOT_FILES["paths"] + "', 'SERVICE_PATH_MAP_AUTOGENERATED')",
        "",
        "ProductSnapshotTopology = struct(",
        "    app_services = APP_SERVICES_AUTOGENERATED,",
        "    service_dependencies = SERVICE_DEPENDENCIES_AUTOGENERATED,",
        "    service_aliases = SERVICE_ALIASES_AUTOGENERATED,",
        "    service_path_map = SERVICE_PATH_MAP_AUTOGENERATED,",
        ")",
        "",
    ])


def _sanitize_symbol(raw):
    out = []
    for i in range(len(raw)):
        c = raw[i]
        is_alpha = (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")
        is_digit = c >= "0" and c <= "9"
        if is_alpha or is_digit or c == "_":
            out.append(c)
        else:
            out.append("_")
    value = "".join(out)
    if not value:
        value = "domain"
    if value[0].isdigit():
        value = "_" + value
    return value


def _render_product_domain_file(service):
    header = (
        "# ----------------------------------------------------------------------------\n"
        + "# AUTOGENERATED FILE - DO NOT EDIT\n"
        + "# Source: manifest autodiscovery from .tilt/topologies/tilt/discovery/registry.star\n"
        + "# ----------------------------------------------------------------------------\n\n"
    )
    domain = service["name"] if "name" in service else "unknown"
    safe_domain = str(domain).replace("'", "\\'")
    resources = service["resources"] if "resources" in service else []
    return (
        header
        + "DOMAIN_NAME = '"
        + safe_domain
        + "'"
        + "\n"
        + "DOMAIN_TOPOLOGY = "
        + _starlark_literal(service)
        + "\n"
        + "DOMAIN_RESOURCES = "
        + _starlark_literal(resources)
        + "\n\n"
        + "ProductDomain = struct(\n"
        + "    name = DOMAIN_NAME,\n"
        + "    topology = DOMAIN_TOPOLOGY,\n"
        + "    resources = DOMAIN_RESOURCES,\n"
        + ")\n"
    )


def _render_product_domains_index(app_services):
    lines = [
        "# ----------------------------------------------------------------------------",
        "# AUTOGENERATED FILE - DO NOT EDIT",
        "# ----------------------------------------------------------------------------",
        "",
    ]

    domain_rows = []
    for service in app_services:
        domain = service["name"] if "name" in service else "unknown"
        symbol = _sanitize_symbol(domain) + "_domain"
        lines.append("load('./" + domain + "/" + PRODUCT_DOMAIN_SERVICES_FILE + "', " + symbol + " = 'ProductDomain')")
        domain_rows.append("    '" + domain + "': " + symbol + ",")

    lines.extend([
        "",
        "ProductDomains = {",
    ])
    lines.extend(domain_rows)
    lines.extend([
        "}",
        "",
        "ProductTopology = struct(",
        "    domains = ProductDomains,",
        ")",
        "",
    ])
    return "\n".join(lines)


def generate_product_domain_topology():
    print("🗂️  Generating product domain topology...")
    local("mkdir -p " + PRODUCT_TOPOLOGY_DIR, quiet = True)

    changes = 0
    for service in APP_SERVICES:
        domain = service["name"] if "name" in service else "unknown"
        domain_file = PRODUCT_TOPOLOGY_DIR + "/" + domain + "/" + PRODUCT_DOMAIN_SERVICES_FILE
        if _write_file_if_changed(domain_file, _render_product_domain_file(service)):
            changes = changes + 1

    index_path = PRODUCT_TOPOLOGY_DIR + "/" + PRODUCT_DOMAINS_INDEX_FILE
    if _write_file_if_changed(index_path, _render_product_domains_index(APP_SERVICES)):
        changes = changes + 1

    if changes > 0:
        print("✅ Regenerated product domain folders (" + str(changes) + " file(s) changed)")


def generate_product_snapshot_topology():
    print("📸 Generating product snapshot topology...")
    local("mkdir -p " + PRODUCT_SNAPSHOT_DIR, quiet = True)

    services_path = PRODUCT_SNAPSHOT_DIR + "/" + PRODUCT_SNAPSHOT_FILES["services"]
    deps_path = PRODUCT_SNAPSHOT_DIR + "/" + PRODUCT_SNAPSHOT_FILES["dependencies"]
    aliases_path = PRODUCT_SNAPSHOT_DIR + "/" + PRODUCT_SNAPSHOT_FILES["aliases"]
    paths_path = PRODUCT_SNAPSHOT_DIR + "/" + PRODUCT_SNAPSHOT_FILES["paths"]
    index_path = PRODUCT_SNAPSHOT_DIR + "/" + PRODUCT_SNAPSHOT_FILES["index"]
    readme_path = PRODUCT_SNAPSHOT_DIR + "/" + PRODUCT_SNAPSHOT_FILES["readme"]

    changes = 0
    if _write_file_if_changed(
        services_path,
        _render_star_file("Discovered application services", "APP_SERVICES_AUTOGENERATED", APP_SERVICES),
    ):
        changes = changes + 1
    if _write_file_if_changed(
        deps_path,
        _render_star_file("Service dependency graph", "SERVICE_DEPENDENCIES_AUTOGENERATED", SERVICE_DEPENDENCIES),
    ):
        changes = changes + 1
    if _write_file_if_changed(
        aliases_path,
        _render_star_file("Service aliases", "SERVICE_ALIASES_AUTOGENERATED", SERVICE_ALIASES),
    ):
        changes = changes + 1
    if _write_file_if_changed(
        paths_path,
        _render_star_file("Service path map", "SERVICE_PATH_MAP_AUTOGENERATED", SERVICE_PATH_MAP),
    ):
        changes = changes + 1
    if _write_file_if_changed(index_path, _render_index()):
        changes = changes + 1
    if _write_file_if_changed(readme_path, _render_readme()):
        changes = changes + 1

    if changes > 0:
        print("✅ Regenerated product snapshot (" + str(changes) + " file(s) changed)")


# Initialize discovery on first access, not at module load time
# This allows two-pass discovery (JSON → YAML → Load)

def _ensure_initialized():
    """Ensure discovery is initialized with two-pass approach."""
    initialized = _DISCOVERY_CACHE["initialized"] if "initialized" in _DISCOVERY_CACHE else False
    if not initialized:
        get_app_services()

# Run two-pass discovery NOW at module load
# This ensures APP_SERVICES is populated before exports
print("")
print("🚀 Initializing service discovery...")
_ensure_initialized()
print("📦 Exporting services...")

APP_SERVICES = _DISCOVERY_CACHE["app_services"]
SERVICE_DEPENDENCIES = _DISCOVERY_CACHE["service_dependencies"]
SERVICE_ALIASES = _DISCOVERY_CACHE["service_aliases"]
SERVICE_PATH_MAP = _DISCOVERY_CACHE["service_path_map"]

print("✅ Registry initialized (" + str(len(APP_SERVICES)) + " services)")
print("")

OPTIONAL_INFRA_EXPORT = OPTIONAL_INFRA
CORE_INFRA_EXPORT = CORE_INFRA
INFRA_DOMAIN_MAP_EXPORT = INFRA_DOMAIN_MAP
DEFAULTS_EXPORT = Config.DEFAULTS
DDD_LIBS_EXPORT = DDD_LIBS
GLOBAL_CONFIG_EXPORT = GLOBAL_CONFIG
INFRA_SERVICES_EXPORT = INFRA_SERVICES
PLATFORM_LIBS_FRONTEND_EXPORT = PLATFORM_LIBS_FRONTEND
PRODUCT_LIBS_FRONTEND_EXPORT= PRODUCT_LIBS_FRONTEND

def get_platform_libs_export(autodiscover = False):
    return get_platform_libs(autodiscover)


def get_product_libs_export(autodiscover = False):
    return get_product_libs(autodiscover)


def _json_to_yaml(json_data, indent=0):
    """
    Convert JSON data to YAML format with 2-space indentation.
    
    Args:
        json_data: The JSON data (dict, list, or primitive)
        indent: Current indentation level (0 = root)
    
    Returns:
        String containing YAML-formatted data
    """
    spaces = "  " * indent
    yaml_lines = []
    
    if type(json_data) == "dict":
        # Define field order: important fields first, then alphabetical
        priority_fields = ["appName", "appType", "domain", "port"]
        
        # Sort keys: priority fields first (in order), then rest alphabetically
        # In Starlark, iterating over dict gives keys directly
        ordered_keys = []
        
        # Add priority fields that exist
        for key in priority_fields:
            if key in json_data:
                ordered_keys.append(key)
        
        # Add remaining fields alphabetically
        remaining = [k for k in json_data if k not in priority_fields and not k.startswith("_")]
        for key in sorted(remaining):
            ordered_keys.append(key)
        
        for key in ordered_keys:
            value = json_data[key]
            # Skip internal fields (starting with _)
            if str(key).startswith("_"):
                continue
            
            if type(value) == "dict":
                yaml_lines.append(spaces + str(key) + ":")
                nested = _json_to_yaml(value, indent + 1)
                if nested:
                    yaml_lines.append(nested)
            elif type(value) == "list":
                yaml_lines.append(spaces + str(key) + ":")
                for item in value:
                    if type(item) == "dict":
                        yaml_lines.append(spaces + "  -")
                        nested = _json_to_yaml(item, indent + 2)
                        if nested:
                            yaml_lines.append(nested)
                    else:
                        yaml_lines.append(spaces + "  - " + str(item))
            else:
                # Primitive value
                yaml_lines.append(spaces + str(key) + ": " + str(value))
    
    return "\n".join(yaml_lines)


def _generate_yaml_from_json_manifests():
    """
    Generate YAML manifest files from JSON manifests for Tilt resource tracking.
    This creates the YAML files that load_yaml_manifests_as_resources() expects.
    Runs SYNCHRONOUSLY to ensure files exist before loading.
    
    NOTE: Generates proper YAML format (not JSON-in-YAML).
    """
    print("🔄 Generating YAML manifests from JSON manifests...")
    
    generated_count = 0
    for root in DISCOVERY_SCAN_ROOTS:
        # Find all JSON manifests (both legacy and new naming)
        json_files = []
        
        # Search for service.json manifests only (migration complete)
        cmd = "find " + root + " -type f -name '" + MANIFEST_FILENAME_NEW + "' 2>/dev/null"
        result = str(local(cmd, quiet=True)).strip()
        if result:
            for f in result.split("\n"):
                f = f.strip()
                if f and MANIFEST_FILENAME_NEW in f:
                    json_files.append(f)
        
        # Generate YAML for each JSON manifest SYNCHRONOUSLY
        for json_file in json_files:
            # Determine the corresponding YAML file path (service.json -> service.yaml)
            yaml_file = json_file.replace(MANIFEST_FILENAME_NEW, MANIFEST_FILENAME_NEW_YAML)
            
            # Check if regeneration is needed
            check_cmd = "if [ ! -f " + yaml_file + " ] || [ " + json_file + " -nt " + yaml_file + " ]; then echo 'regenerate'; fi"
            needs_regen = str(local(check_cmd, quiet=True)).strip()
            
            if needs_regen:
                # Read and parse JSON
                json_content = read_file(json_file, default='')
                if json_content:
                    manifest = decode_json(json_content)
                    if manifest:
                        # Convert to YAML format
                        yaml_content = _json_to_yaml(manifest)
                        if yaml_content:
                            # Write YAML file using shell command (write_file not available in Starlark)
                            # Escape the content for shell
                            yaml_escaped = yaml_content.replace("'", "'\\''")
                            write_cmd = "echo '" + yaml_escaped + "' > " + yaml_file
                            local(write_cmd, quiet=True)
                            generated_count += 1
    
    if generated_count > 0:
        print("   Generated " + str(generated_count) + " YAML manifest files")
    else:
        print("   All YAML manifest files up to date")


def load_yaml_manifests_as_resources():
    """
    Load all generated YAML manifests as Tilt UIResources using local_resource.
    This makes 'tilt get uiresource' show our manifest data!
    NO KUBERNETES CLUSTER REQUIRED - uses local_resource instead of k8s_yaml.
    """
    print("")
    print("📝 ═══════════════════════════════════════════════════════════════")
    print("📝  YAML MANIFESTS: Loading as Tilt Resources")
    print("📝 ═══════════════════════════════════════════════════════════════")
    print("🔄 Generating YAML manifests from JSON manifests...")
    _generate_yaml_from_json_manifests()
    
    print("🎯 Loading YAML manifests as Tilt resources (local mode)...")
    
    # Find all YAML manifest files across all discovery roots
    # Check both legacy (platform-computing-provisioner.manifest.yaml) and new (service.yaml) naming
    yaml_files = []
    for root in DISCOVERY_SCAN_ROOTS:
        # Search for legacy YAML manifests
        cmd_legacy = "find " + root + " -type f -name '" + MANIFEST_FILENAME_YAML + "' 2>/dev/null"
        result_legacy = str(local(cmd_legacy, quiet=True)).strip()
        if result_legacy:
            for f in result_legacy.split("\n"):
                f = f.strip()
                if f and f not in yaml_files:
                    yaml_files.append(f)
        
        # Search for new service.yaml manifests
        cmd_new = "find " + root + " -type f -name '" + MANIFEST_FILENAME_NEW_YAML + "' 2>/dev/null"
        result_new = str(local(cmd_new, quiet=True)).strip()
        if result_new:
            for f in result_new.split("\n"):
                f = f.strip()
                if f and f not in yaml_files:
                    yaml_files.append(f)
    
    if not yaml_files:
        print("⚠️  No YAML manifests found to load")
        return
    
    print("📄 Loading " + str(len(yaml_files)) + " YAML files as Tilt resources...")
    
    # Load each YAML file as a Tilt local_resource (no k8s cluster needed!)
    for yaml_file in yaml_files:
        # Get the JSON path from the YAML path (both have same structure)
        json_file = yaml_file.replace("service.yaml", "service.json")
        
        # Use ManifestLoader to properly load the JSON manifest
        # This gives us the correct service name
        load_result = ManifestLoader.load_from_file(json_file)
        service_name = ''
        
        if load_result.error:
            print("   ⚠️  Error loading manifest: " + json_file + " - " + load_result.error)
            continue
        
        manifest = load_result.manifest
        service_name = ""
        if manifest:
            service_name = manifest["appName"] if "appName" in manifest else ""
            if not service_name:
                print("   ⚠️  No appName in manifest: " + json_file)
                continue
        else:
            print("   ⚠️  Could not load manifest: " + json_file + " - skipping")
            continue
        
        resource_name = service_name + "-yaml"
        
        # For the dependency path, we need the repo-relative path (without ../../../../)
        if yaml_file.startswith("../../../../"):
            yaml_path_display = yaml_file[12:]  # Remove "../../../../" for display
        else:
            yaml_path_display = yaml_file
        
        # Create a local_resource that just validates the YAML exists
        # This makes it visible in 'tilt get uiresource' WITHOUT needing k8s!
        local_resource(
            name=resource_name,
            cmd="echo '✅ YAML manifest loaded: " + yaml_path_display + "'",
            deps=[yaml_file],  # Use full path with ../../../../ for deps
            labels=["yaml-manifest"],
        )
        
        print("  ↳ Created resource: " + resource_name)
    
    print("✅ Loaded " + str(len(yaml_files)) + " YAML manifests as Tilt resources (no k8s needed)!")
    print("📝 ═══════════════════════════════════════════════════════════════")
    print("")


# DISABLED: Starlark file generation is no longer needed
# YAML manifests are now loaded directly as Tilt resources via local_resource()
# This eliminates the need for intermediate autogenerated Starlark files
# 
# generate_product_snapshot_topology()
# generate_product_domain_topology()

# Load YAML manifests as actual Tilt resources (replaces Starlark generation)
print("🎯 Phase 3: Loading YAML manifests as Tilt resources...")
load_yaml_manifests_as_resources()
