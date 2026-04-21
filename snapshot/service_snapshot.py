"""
Service Snapshot - Python-based filesystem scanning
"""

import json
import os
from pathlib import Path

def scan_for_manifests(roots):
    """Scan directories for service.json files."""
    manifests = []
    for root in roots:
        for path in Path(root).rglob("service.json"):
            with open(path) as f:
                manifest = json.load(f)
                manifests.append({
                    "path": str(path),
                    "manifest": manifest
                })
    return manifests

def save_snapshot(manifests, output_path):
    """Save snapshot to disk."""
    with open(output_path, 'w') as f:
        json.dump(manifests, f, indent=2)

def load_snapshot(path):
    """Load snapshot from disk."""
    with open(path) as f:
        return json.load(f)

def detect_changes(old_snapshot, new_snapshot):
    """Detect added/removed/updated services."""
    old_paths = {m["path"] for m in old_snapshot}
    new_paths = {m["path"] for m in new_snapshot}
    
    added = new_paths - old_paths
    removed = old_paths - new_paths
    
    return {"added": list(added), "removed": list(removed)}
