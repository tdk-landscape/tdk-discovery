def by_app_type(manifests, app_type):
    return [m for m in manifests if m.get("appType") == app_type]

def by_stack(manifests, stack):
    return [m for m in manifests if (m.get("stack") or m.get("domain")) == stack]

# Legacy alias for backward compatibility
def by_domain(manifests, domain):
    return by_stack(manifests, domain)
