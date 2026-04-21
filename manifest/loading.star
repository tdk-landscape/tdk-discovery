# =============================================================================
# 📋 TILT SDK - MANIFEST LOADING (CEO Review: rename-service-manifest)
# =============================================================================
# Path: .tilt/topologies/tilt/discovery/manifest/loading.star
# Purpose: Load, synthesize, and apply defaults to manifests
# 
# NEW: Dual-filename support with synthesis-by-default (ASAP timeline)
# Priority: service.json → legacy manifest → synthesize from path
# =============================================================================

load('../../../tilt/manifest/constants.star', 
     'MANIFEST_DEFAULTS', 
     'DEFAULT_SYNCS', 
     'MANIFEST_FILENAME',
     'MANIFEST_FILENAME_NEW',
     'MANIFEST_SEARCH_ORDER',
     'MANIFEST_DEPRECATION_ENABLED',
     'MANIFEST_DEPRECATION_WARNING')
load('../../common/utils.star', 'Utils')
load('../../../platform/docker/constants.star', 'PlatformDockerConstants')
load('../../../../../.tilt/TILT_SERVICE_DEFAULTS.star', 'BASE_PORT_FRONTEND', 'BASE_PORT_BACKEND', 'HEALTH_CHECK_PATH')

# Environment variable to disable deprecation warnings
_DISABLE_WARNINGS = os.environ.get('TDK_DISABLE_MANIFEST_WARNINGS', '') == 'true'
_LEGACY_LOADER_ONLY = os.environ.get('TDK_LEGACY_LOADER_ONLY', '') == 'true'


def _check_prisma_folder(service_path):
    """
    Check if prisma/ directory exists in service path.
    Used to auto-detect has_migrator when not in features.
    """
    check_cmd = "test -d '{path}/prisma' && echo 'yes' || echo 'no'".format(path=service_path)
    result = str(local(check_cmd, quiet=True)).strip()
    return result == 'yes'


def check_prisma_folder(service_path):
    return _check_prisma_folder(service_path)


def get_default_syncs_for_type(app_type, features=None):
    """
    Returns default sync paths based on app type and features.
    """
    if features == None:
        features = []

    syncs = list(DEFAULT_SYNCS.get(app_type, ['src', 'package.json']))

    # Add prisma to syncs if using prisma feature
    if app_type == 'backend' and 'prisma' in features and 'prisma' not in syncs:
        syncs.append('prisma')

    return syncs


def _extract_domain_from_path(service_path, app_name):
    """
    Extract domain from service path or app name.
    
    Convention: services/product/{domain}/{service-name}
    Fallback: First segment of app_name before hyphen
    
    Special handling: profile -> identity
    """
    parts = service_path.rstrip('/').split('/')
    if len(parts) >= 4 and parts[-4] == 'services' and parts[-3] == 'product':
        domain = parts[-2]
        # Normalize profile to identity
        if domain == 'profile':
            return 'identity'
        return domain
    else:
        return app_name.split('-')[0] if '-' in app_name else app_name


def load_manifest(service_path, persist_to_disk=False):
    """
    Load manifest with dual-filename support and synthesis-by-default.
    
    Priority order (CEO Review: rename-service-manifest):
      1. service.json (new preferred filename)
      2. platform-computing-provisioner.manifest.json (legacy, with deprecation warning)
      3. Synthesize from directory structure (synthesis-by-default for standard services)
    
    Args:
        service_path: Path to service directory
        persist_to_disk: If True, sync _internalDeps back to the physical manifest file
        
    Returns:
        Validated manifest dict with all defaults applied
    """
    manifest = None
    manifest_source = None
    manifest_path = None
    
    # Try new filename first (service.json)
    new_manifest_path = service_path + '/' + MANIFEST_FILENAME_NEW
    new_content = read_file(new_manifest_path, default='')
    
    if new_content and str(new_content).strip():
        manifest = decode_json(new_content)
        manifest_source = 'service.json'
        manifest_path = new_manifest_path
    
    # Synthesize from directory structure if no manifest found
    if manifest == None:
        manifest = synthesize_manifest_from_path(service_path)
        manifest_source = 'synthesized'
        manifest_path = service_path  # Virtual path
    
    # Validate JSON parsed correctly
    if manifest == None and manifest_source != 'synthesized':
        fail("""
❌ ═══════════════════════════════════════════════════════════════════
❌  INVALID JSON IN MANIFEST FILE
❌ ═══════════════════════════════════════════════════════════════════
   📁 File: {path}
   Source: {source}
   
   Common issues:
   • Missing closing quote: "appName": "my-app
   • Trailing comma: "port": 4000,}}
   • Missing comma between properties
   • Single quotes instead of double quotes
   
   Fix the JSON syntax and run 'tilt up' again.
❌ ═══════════════════════════════════════════════════════════════════
""".format(path=manifest_path, source=manifest_source))
    
    # Track manifest source for debugging
    manifest['_manifestSource'] = manifest_source
    manifest['_manifestPath'] = manifest_path
    
    # Apply defaults and compute derived values
    validated = apply_manifest_defaults(manifest, service_path)

    return validated


def synthesize_manifest_from_path(service_path):
    return _synthesize_manifest_from_path(service_path)


def apply_manifest_defaults(manifest, service_path):
    return _apply_manifest_defaults(manifest, service_path)


def _synthesize_manifest_from_path(service_path):
    """
    Create a manifest based on directory naming conventions.
    Used when manifest.json doesn't exist (backward compatibility).
    
    Convention: services/product/{domain}/{domain}-{component}-{type}
    Example: services/product/{domain}/{app-name}-{type}
             -> appName: {app-name}-{type}
             -> appType: {type}
             -> domain: {domain}
    """
    parts = service_path.rstrip('/').split('/')
    dir_name = parts[-1] if parts else 'unknown-service'
    
    # Determine appType from directory name suffix
    app_type = 'backend'
    if dir_name.endswith('-frontend'):
        app_type = 'frontend'
    elif dir_name.endswith('-backend'):
        app_type = 'backend'
    elif dir_name.endswith('-migrator'):
        app_type = 'migrator'
    elif dir_name.endswith('-sdk'):
        app_type = 'sdk'
    elif dir_name.endswith('-infra') or dir_name.endswith('-ui'):
        app_type = 'library'
    elif 'lib-' in dir_name or 'platform-' in dir_name:
        app_type = 'library'
    
    return {
        'appName': dir_name,
        'appType': app_type,
        '_synthesized': True,
    }


def _apply_manifest_defaults(manifest, service_path):
    """
    🎯 SMART DEFAULTS: Expand slim manifest to full config.
    
    CEO Review updates (rename-service-manifest):
    - Port is constant per appType (3000 frontend, 4000 backend) — Traefik handles routing
    - Custom dockerfile support via manifest["dockerfile"] field
    - Developer manually provides features (no auto-detection per requirement)
    
    Convention over Configuration:
    - features: ["nats", "prisma"] -> usePrisma=True, useNats=True
    - domain: "appointment" -> databaseName="TDK_appointment"
    - domain: "appointment" -> traefik.host="appointment.backend.beauty.local"
    - domain: "appointment" -> nats.queueGroup="appointment_backend_svc"
    """
    result = dict(manifest)
    
    # Normalize service_path to be relative (strip leading / if present)
    # Docker build context requires relative paths
    if service_path.startswith('/'):
        service_path = service_path[1:]
    
    # Track overrides for logging (task 4.8: override detection)
    overrides = []
    app_name = result.get('appName', '')
    
    # Apply simple defaults
    for key, default_value in MANIFEST_DEFAULTS.items():
        if key not in result or result[key] == None:
            result[key] = default_value
    
    # 🎯 CEO REVIEW: Traefik-native port strategy
    # Port is constant per appType, not dynamically assigned
    # Traefik routes by hostname (e.g., booking.backend.beauty.local), not port
    app_type = result.get('appType', 'backend')
    
    # Set constant port per appType with override detection
    computed_port = None
    if app_type == 'frontend':
        computed_port = BASE_PORT_FRONTEND
    elif app_type == 'backend':
        computed_port = BASE_PORT_BACKEND
    elif app_type == 'migrator':
        computed_port = 7000  # Migrator uses different range
    
    if computed_port != None:
        if 'port' in result and result['port'] != computed_port:
            overrides.append("port: {} (auto: {})".format(result['port'], computed_port))
        result['port'] = computed_port
    
    # 🎯 CEO REVIEW: Custom dockerfile support
    # Validate custom dockerfile exists if specified
    if 'dockerfile' in result:
        custom_dockerfile = result['dockerfile']
        dockerfile_path = service_path + '/' + custom_dockerfile
        dockerfile_exists = local("test -f '{path}' && echo 'yes' || echo 'no'".format(path=dockerfile_path), quiet=True)
        if str(dockerfile_exists).strip() != 'yes':
            fail("""
❌ ═══════════════════════════════════════════════════════════════════
❌  CUSTOM DOCKERFILE NOT FOUND
❌ ═══════════════════════════════════════════════════════════════════
   📁 Service: {service}
   🐳 Dockerfile: {dockerfile}
   
   Manifest specifies custom Dockerfile but it doesn't exist.
   Either:
   • Create {dockerfile} in service directory
   • Remove "dockerfile" field to use auto-generated Dockerfile
❌ ═══════════════════════════════════════════════════════════════════
""".format(service=service_path.split('/')[-1], dockerfile=custom_dockerfile))
    
    # 🎯 FEATURE FLAGS -> BOOLEAN CONFIG
    # NOTE: Developer manually provides features per CEO Review requirement
    # No auto-detection from file existence (e.g., prisma/schema.prisma)
    features = result.get('features', [])
    result['usePrisma'] = 'prisma' in features
    result['useNats'] = 'nats' in features
    result['useTraefik'] = 'traefik' in features or app_type in ['backend', 'sdk']
    
    # Compute HMR port if not set (only for frontend)
    if result.get('hmrPort') == None and app_type == 'frontend':
        result['hmrPort'] = result['port'] + 1000  # 3000 -> 4000
    
    # Extract domain from path if not set
    if 'domain' not in result:
        result['domain'] = _extract_domain_from_path(service_path, app_name)
    
    domain = result['domain']
    
    # 🎯 SMART DATABASE NAME with override detection
    computed_db_name = PlatformDockerConstants.get_db_name(domain)
    if 'databaseName' not in result:
        result['databaseName'] = computed_db_name
    elif result['databaseName'] != computed_db_name:
        overrides.append("databaseName: {} (auto: {})".format(result['databaseName'], computed_db_name))
    
    # 🎯 SMART TRAEFIK CONFIG (Convention over Configuration)
    # Apply to backends and SDKs that need Traefik routing
    if result['useTraefik'] and app_type in ['backend', 'sdk']:
        existing_traefik = result.get('traefik', {})
        # Use apiPath from root level if available, otherwise use default pattern
        root_api_path = result.get('apiPath')
        default_path_prefix = root_api_path if root_api_path else '/api/' + domain
        
        computed_traefik = {
            'host': domain + '.backend.beauty.local',
            'pathPrefix': default_path_prefix,
            'healthCheck': HEALTH_CHECK_PATH,
        }
        
        # Check for overrides
        if existing_traefik.get('host') and existing_traefik.get('host') != computed_traefik['host']:
            overrides.append("traefik.host: {} (auto: {})".format(existing_traefik['host'], computed_traefik['host']))
        if existing_traefik.get('pathPrefix') and existing_traefik.get('pathPrefix') != computed_traefik['pathPrefix']:
            overrides.append("traefik.pathPrefix: {} (auto: {})".format(existing_traefik['pathPrefix'], computed_traefik['pathPrefix']))
        
        result['traefik'] = {
            'host': existing_traefik.get('host', computed_traefik['host']),
            'pathPrefix': existing_traefik.get('pathPrefix', computed_traefik['pathPrefix']),
            'healthCheck': existing_traefik.get('healthCheck', computed_traefik['healthCheck']),
        }
    
    # 🎯 SMART NATS CONFIG
    if result['useNats']:
        existing_nats = result.get('nats', {})
        result['nats'] = {
            'queueGroup': existing_nats.get('queueGroup', domain + '_' + app_type + '_svc'),
            'subjects': existing_nats.get('subjects', [domain + '.>']),
        }
    
    # Compute backend name for frontends with override detection
    if app_type == 'frontend':
        computed_backend = app_name.replace('-frontend', '-backend')
        if 'backendName' not in result:
            result['backendName'] = computed_backend
        elif result['backendName'] != computed_backend:
            overrides.append("backendName: {} (auto: {})".format(result['backendName'], computed_backend))
        
        # 🎯 SMART BASEPATH for frontends (convention: /{domain}s)
        computed_base_path = '/' + domain + 's'
        if 'basePath' not in result:
            result['basePath'] = computed_base_path
        elif result['basePath'] != computed_base_path:
            overrides.append("basePath: {} (auto: {})".format(result['basePath'], computed_base_path))
    
    # 🎯 Always set _servicePath for all manifest types
    result['_servicePath'] = service_path
    
    # 🎯 CENTRALIZED: Use Utils.get_internal_deps() for dependency extraction
    internal_deps = Utils.get_internal_deps(service_path)
    result['_internalDeps'] = sorted(internal_deps)
    
    # 🎯 CENTRALIZED: Use Utils.build_deps_mapping() for path resolution
    result['_internalDepsMapping'] = Utils.build_deps_mapping(service_path, internal_deps)
    
    # 🎯 Log overrides if any were detected and verbose mode is enabled
    if overrides and os.environ.get('TILT_LOG_LEVEL') == 'verbose':
        print("📝 Override(s) detected for {}: {}".format(app_name, ', '.join(overrides)))
    
    return result


def load_related_manifest(frontend_manifest, backend_suffix='-backend'):
    """
    Load the related backend manifest for a frontend service.
    
    CEO Review update: Supports dual-filename and synthesis-by-default.
    
    Args:
        frontend_manifest: The loaded frontend manifest
        backend_suffix: Suffix to replace '-frontend' with
        
    Returns:
        Backend manifest dictionary, or None if not found
    """
    if frontend_manifest.get('appType') != 'frontend':
        return None
    
    service_path = frontend_manifest.get('_servicePath', '')
    backend_path = service_path.replace('-frontend', backend_suffix)
    
    # Use load_manifest which handles dual-filename and synthesis
    return load_manifest(backend_path)


def get_manifest_filename(service_path):
    """
    Determine which manifest filename is being used for a service.
    
    CEO Review addition: Utility for filename detection.
    
    Args:
        service_path: Path to service directory
        
    Returns:
        Filename string or None if neither exists (synthesis will be used)
    """
    # Check new filename first
    new_path = service_path + '/' + MANIFEST_FILENAME_NEW
    if local("test -f '{path}' && echo 'yes' || echo 'no'".format(path=new_path), quiet=True) == 'yes':
        return MANIFEST_FILENAME_NEW
    
    # Check legacy filename
    legacy_path = service_path + '/' + MANIFEST_FILENAME
    if local("test -f '{path}' && echo 'yes' || echo 'no'".format(path=legacy_path), quiet=True) == 'yes':
        return MANIFEST_FILENAME
    
    # Neither exists - synthesis will be used
    return None
