"""
Discovery Daemon - Continuous service monitoring
"""

load("./registry.star", "register_service", "get_app_services")

def start_daemon(ctx):
    """
    Start the discovery daemon with polling.
    
    Args:
        ctx: Configuration with scan_interval, roots, etc.
    """
    scan_interval = ctx.get("scan_interval", 5)
    roots = ctx.get("roots", ["./services"])
    
    print(f"👁️  Discovery daemon started (interval: {scan_interval}s)")
    print(f"   Scanning: {', '.join(roots)}")

def check_for_new_services():
    """Poll for new services and register them."""
    print("🔍 Checking for new services...")
    # Implementation would compare snapshot to current state
