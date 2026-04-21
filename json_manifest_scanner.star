# json_manifest_scanner.star
# 
# Purpose: Low-level JSON manifest file discovery using shell `find` command
# Use: discover_json_manifests(root_path) returns list of manifest file paths
#
# NOTE: This is the "manual" scanner - it finds files in a specific folder.
# For auto-discovery from Tilt's discovery system, use discovery.star instead.

load("../manifest/constants.star", "MANIFEST_FILENAME_NEW")

def discover_json_manifests(root_path):
    """
    Discover all JSON manifest files in a given root path.
    
    Args:
        root_path: Relative path from .tilt/topologies/tilt/discovery/
                   e.g., "../../../../services/product"
    
    Returns:
        List of manifest file paths (strings)
    """
    # Search for service.json files only (migration complete - legacy no longer supported)
    cmd = "find " + root_path + " -type f -name '" + MANIFEST_FILENAME_NEW + "' 2>/dev/null | sort"
    result = str(local(cmd, quiet=True))
    
    manifests = []
    if result:
        for line in result.strip().split("\n"):
            line = line.strip()
            if line and MANIFEST_FILENAME_NEW in line:
                manifests.append(line)

    return manifests
