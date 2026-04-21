# TDK Discovery

Service discovery plugin for the TDK Landscape platform.

## Purpose

Auto-discovers services from `service.json` manifests across the codebase:
- Filesystem scanning
- Manifest validation
- Service registry management
- Auto-discovery daemon (watches for new services)

## Directory Structure

```
manifest/
├── loading.star          # service.json loading and validation
├── validation.star       # Schema validation
└── constants.star        # Manifest constants

snapshot/
├── service_snapshot.py   # Python snapshot utilities
└── diff.star            # Change detection

daemon/
├── discovery_daemon.star       # Continuous monitoring
└── incremental_discovery.star  # Dynamic registration

registry.star           # Service registry and caching
```

## Usage

```starlark
load("ext://github.com/tdk-landscape/tdk-discovery", "tdk_discovery")

services = tdk_discovery.scan({
    "roots": ["./services", "./shared"],
    "auto_discover": True
})
```

## Features

- ✅ Two-pass discovery (registry → resources)
- ✅ Incremental updates (no Tilt restart needed)
- ✅ Focus mode (only discover within focused domains)
- ✅ Snapshot-based change detection

## License

MIT
