# =============================================================================
# 🗺️ TOPOLOGIES - DISCOVERY CONFIG
# =============================================================================

load("./constants.star", "SERVICES_ROOT")
load("../../platform/docker/constants.star", "PlatformDockerConstants")
load("../../../../spec.master", "DEFAULTS")

# FOCUS release phase service lists
# These define which services are included in each release phase
FOCUS_PRE_ALPHA = DEFAULTS.get("pre_alpha_services", [])
FOCUS_ALPHA = DEFAULTS.get("alpha_services", [])
FOCUS_BETA = DEFAULTS.get("beta_services", [])

# -----------------------------------------------------------------------------
# 🎛️ SERVICE DEFAULTS
# -----------------------------------------------------------------------------
# LOADED FROM: spec.master (in project root)
# PURPOSE: Single source of truth for service enable/disable configuration
# 
# 📖 To modify which services run, edit: spec.master
# -----------------------------------------------------------------------------


def get_global_config():
    verdaccio_url_docker = os.environ.get(
        "VERDACCIO_URL_DOCKER",
        PlatformDockerConstants.VERDACCIO_URL_DOCKER,
    )
    return {
        "verdaccio_url_local": PlatformDockerConstants.VERDACCIO_URL_LOCAL,
        "verdaccio_url_docker": verdaccio_url_docker,
        "npm_registry": PlatformDockerConstants.VERDACCIO_NPM_REGISTRY,
        "internal_scope": "@" + PlatformDockerConstants.PROJECT_NAME + "/",
        "library_roots": {
            "platform": "shared-platform-engineering",
            "product": "shared-product-engineering",
            "ddd": "shared-ddd-layers",
        },
        # Relative to .tilt/topologies/tilt/discovery/
        "services_root": SERVICES_ROOT,
        "database": PlatformDockerConstants.DB_CONFIG,
        "docker": {
            "base_image": PlatformDockerConstants.BUN_IMAGE,
            "nginx_image": "nginx:alpine",
            "golden_l1_image": PlatformDockerConstants.PROJECT_NAME_HYPHEN + "-l1:latest",
            "golden_l2_image": PlatformDockerConstants.PROJECT_NAME_HYPHEN + "-l2:latest",
            "golden_l3_backend_image": PlatformDockerConstants.PROJECT_NAME_HYPHEN + "-l3-backend:latest",
            "golden_l3_frontend_image": PlatformDockerConstants.PROJECT_NAME_HYPHEN + "-l3-frontend:latest",
            "golden_l3_migrator_image": PlatformDockerConstants.PROJECT_NAME_HYPHEN + "-l3-migrator:latest",
            "golden_l4_backend_image": PlatformDockerConstants.PROJECT_NAME_HYPHEN + "-l4-backend:latest",
            "golden_l4_frontend_image": PlatformDockerConstants.PROJECT_NAME_HYPHEN + "-l4-frontend:latest",
            "golden_l4_migrator_image": PlatformDockerConstants.PROJECT_NAME_HYPHEN + "-l4-migrator:latest",
            "network_prefix": PlatformDockerConstants.PROJECT_NAME + "_",
        },
        "ports": {
            "backend": 3000,
            "frontend": 80,
            "postgres": 5432,
            "nats": 4222,
            "verdaccio": PlatformDockerConstants.VERDACCIO_PORT,
        },
    }


GLOBAL_CONFIG = get_global_config()

INFRA_SERVICES = [
    {"name": "database-management", "memory": 1152},
    {"name": "proxy", "memory": 384},
    {"name": "api-gateway", "memory": 512},
    {"name": "verdaccio", "memory": 128},
    {"name": "infisical", "memory": 192},
    {"name": "monitoring", "memory": 1536},
    {"name": "elk", "memory": 1024},
    {"name": "debezium", "memory": 448},
]

CORE_INFRA = [
    "init-networks",
    "golden-layers-build",
    "postgres",
    "nats",
    "verdaccio",
    "verdaccio-connect-network",
    "traefik",
]

INFRA_DOMAIN_MAP = {
    "golden-layers-build": "golden-image",
    "postgres": "database-management",
    "nats": "database-management",
    "redis": "database-management",
    "traefik": "proxy",
    "verdaccio": "verdaccio",
    "infisical": "infisical",
    "infisical-db": "infisical",
    "infisical-redis": "infisical",
}

OPTIONAL_INFRA = {
    "monitoring": ["signoz-frontend", "signoz-otel-collector", "signoz-query-service", "clickhouse", "elasticsearch", "skywalking-oap", "skywalking-ui"],
    "infisical": ["infisical", "infisical-db", "infisical-redis"],
    "elk": ["elasticsearch", "logstash", "kibana"],
    "debezium": ["kafka", "zookeeper", "nats-http-bridge", "debezium-connect", "enhanced-connector-setup"],
}

# -----------------------------------------------------------------------------
# 🎛️ SERVICE DEFAULTS
# -----------------------------------------------------------------------------
# Loaded from: spec.master (in project root)
# See that file for service enable/disable configuration
# DEFAULTS variable imported at top of file via load()
# -----------------------------------------------------------------------------

DDD_LIBS = [
    {"name": "domain", "path": "shared-ddd-layers/domain"},
    {"name": "infrastructure", "path": "shared-ddd-layers/infrastructure"},
    {"name": "application", "path": "shared-ddd-layers/application"},
    {"name": "presentation", "path": "shared-ddd-layers/presentation"},
]

PLATFORM_LIBS_EXPLICIT = [
    "platform-logger",
    "platform-computing-runtime",
    "platform-computing-provisioner",
    "platform-eventing",
    "platform-identity-client",
    "platform-shell-lifecycle",
    "platform-prisma-toolkit",
]

PLATFORM_CLI_TOOLS = [
    "platform-test-runner",
    "platform-roadmap-generator",
    "platform-tsconfig-generator",
    "platform-mdblaster",
]

PLATFORM_LIBS_FRONTEND = [
]

PRODUCT_LIBS_FRONTEND = [
    "introvertic/ui",
]

PRODUCT_LIBS_EXPLICIT = [
    "product-domain-types",
    "product-constants",
    "product-identity-unified",
    "product-appointment-unified",
]

# Export DEFAULTS and focus filters for use by other modules via Config struct
Config = struct(
    DEFAULTS = DEFAULTS,
    FOCUS_PRE_ALPHA = FOCUS_PRE_ALPHA,
    FOCUS_ALPHA = FOCUS_ALPHA,
    FOCUS_BETA = FOCUS_BETA,
)
