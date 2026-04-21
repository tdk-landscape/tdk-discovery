"""
Service Registry - Manages discovered services
"""

_DISCOVERY_CACHE = {
    "initialized": False,
    "app_services": [],
    "service_dependencies": {},
    "service_aliases": {},
}

def get_app_services():
    """Returns all discovered application services."""
    return _DISCOVERY_CACHE["app_services"]

def register_service(service_config):
    """Register a new service in the cache."""
    _DISCOVERY_CACHE["app_services"].append(service_config)
    print(f"🔍 Registered: {service_config['name']}")

def get_service_by_name(name):
    """Find a service by its name."""
    for service in get_app_services():
        if service["name"] == name:
            return service
    return None
