#!/usr/bin/env python3
"""
🧪 Tests for service_snapshot.py

Run with: python3 -m pytest test_service_snapshot.py -v
Or: python3 test_service_snapshot.py
"""

import json
import os
import sys
import tempfile
import shutil
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from service_snapshot import (
    save_snapshot,
    load_snapshot,
    diff_snapshots,
    get_current_services,
)


class TestSaveSnapshot:
    """Tests for save_snapshot function."""
    
    def test_save_creates_file(self, tmp_path):
        """Test that save_snapshot creates the snapshot file."""
        # Change to temp directory
        original_dir = os.getcwd()
        os.chdir(tmp_path)
        
        try:
            services = ["services/a/service.json", "services/b/service.json"]
            save_snapshot(services)
            
            snapshot_file = Path(".tilt/service-snapshot.json")
            assert snapshot_file.exists(), "Snapshot file should be created"
            
            # Verify content
            with open(snapshot_file) as f:
                data = json.load(f)
                assert data["count"] == 2
                assert data["services"] == services
                assert "timestamp" in data
        finally:
            os.chdir(original_dir)
    
    def test_save_creates_directory(self, tmp_path):
        """Test that save_snapshot creates the .tilt directory if needed."""
        original_dir = os.getcwd()
        os.chdir(tmp_path)
        
        try:
            services = ["services/test/service.json"]
            save_snapshot(services)
            
            assert Path(".tilt").exists(), ".tilt directory should be created"
        finally:
            os.chdir(original_dir)


class TestLoadSnapshot:
    """Tests for load_snapshot function."""
    
    def test_load_existing(self, tmp_path):
        """Test loading an existing snapshot."""
        original_dir = os.getcwd()
        os.chdir(tmp_path)
        
        try:
            # Create a snapshot first
            services = ["services/a/service.json"]
            save_snapshot(services)
            
            # Load it
            snapshot = load_snapshot()
            
            assert snapshot["count"] == 1
            assert snapshot["services"] == services
            assert "timestamp" in snapshot
        finally:
            os.chdir(original_dir)
    
    def test_load_nonexistent(self, tmp_path):
        """Test loading when snapshot doesn't exist."""
        original_dir = os.getcwd()
        os.chdir(tmp_path)
        
        try:
            snapshot = load_snapshot()
            
            assert snapshot["count"] == 0
            assert snapshot["services"] == []
            assert snapshot["timestamp"] is None
        finally:
            os.chdir(original_dir)
    
    def test_load_invalid_json(self, tmp_path):
        """Test loading when snapshot has invalid JSON."""
        original_dir = os.getcwd()
        os.chdir(tmp_path)
        
        try:
            # Create invalid snapshot
            Path(".tilt").mkdir(parents=True, exist_ok=True)
            with open(".tilt/service-snapshot.json", "w") as f:
                f.write("not valid json")
            
            snapshot = load_snapshot()
            
            # Should return empty snapshot on error
            assert snapshot["count"] == 0
            assert snapshot["services"] == []
        finally:
            os.chdir(original_dir)


class TestDiffSnapshots:
    """Tests for diff_snapshots function."""
    
    def test_detect_added(self):
        """Test detecting added services."""
        old = {"services": ["a/service.json", "b/service.json"]}
        new = ["a/service.json", "b/service.json", "c/service.json"]
        
        added, removed = diff_snapshots(old, new)
        
        assert added == {"c/service.json"}
        assert removed == set()
    
    def test_detect_removed(self):
        """Test detecting removed services."""
        old = {"services": ["a/service.json", "b/service.json", "c/service.json"]}
        new = ["a/service.json", "b/service.json"]
        
        added, removed = diff_snapshots(old, new)
        
        assert added == set()
        assert removed == {"c/service.json"}
    
    def test_detect_both(self):
        """Test detecting both added and removed."""
        old = {"services": ["a/service.json", "b/service.json"]}
        new = ["b/service.json", "c/service.json"]
        
        added, removed = diff_snapshots(old, new)
        
        assert added == {"c/service.json"}
        assert removed == {"a/service.json"}
    
    def test_no_changes(self):
        """Test when nothing changed."""
        old = {"services": ["a/service.json", "b/service.json"]}
        new = ["a/service.json", "b/service.json"]
        
        added, removed = diff_snapshots(old, new)
        
        assert added == set()
        assert removed == set()
    
    def test_empty_old(self):
        """Test when old snapshot is empty."""
        old = {"services": []}
        new = ["a/service.json", "b/service.json"]
        
        added, removed = diff_snapshots(old, new)
        
        assert added == {"a/service.json", "b/service.json"}
        assert removed == set()


class TestGetCurrentServices:
    """Tests for get_current_services function."""
    
    def test_finds_services(self, tmp_path):
        """Test finding service.json files."""
        original_dir = os.getcwd()
        os.chdir(tmp_path)
        
        try:
            # Create test directory structure
            (Path("services/product/a") / "a-backend").mkdir(parents=True)
            (Path("services/product/a") / "a-backend" / "service.json").touch()
            
            (Path("services/product/b") / "b-backend").mkdir(parents=True)
            (Path("services/product/b") / "b-backend" / "service.json").touch()
            
            services = get_current_services("services/product")
            
            assert len(services) == 2
            assert all("service.json" in s for s in services)
        finally:
            os.chdir(original_dir)
    
    def test_empty_result(self, tmp_path):
        """Test when no services exist."""
        original_dir = os.getcwd()
        os.chdir(tmp_path)
        
        try:
            # Create empty directory
            Path("services/product").mkdir(parents=True)
            
            services = get_current_services("services/product")
            
            assert services == []
        finally:
            os.chdir(original_dir)
    
    def test_nonexistent_root(self, tmp_path):
        """Test when scan root doesn't exist."""
        original_dir = os.getcwd()
        os.chdir(tmp_path)
        
        try:
            services = get_current_services("nonexistent/path")
            
            assert services == []
        finally:
            os.chdir(original_dir)


def run_tests():
    """Run all tests with basic output."""
    import tempfile
    import inspect
    
    print("🧪 Running service_snapshot tests...")
    print("=" * 50)
    
    passed = 0
    failed = 0
    
    test_classes = [
        TestSaveSnapshot,
        TestLoadSnapshot,
        TestDiffSnapshots,
        TestGetCurrentServices,
    ]
    
    for test_class in test_classes:
        print(f"\n📦 {test_class.__name__}")
        
        # Get all test methods
        for method_name in dir(test_class):
            if method_name.startswith("test_"):
                test_method = getattr(test_class(), method_name)
                
                # Check if method needs tmp_path parameter
                sig = inspect.signature(test_method)
                needs_tmp_path = len(sig.parameters) > 0
                
                # Create temp directory for test
                with tempfile.TemporaryDirectory() as tmp_dir:
                    try:
                        if needs_tmp_path:
                            test_method(Path(tmp_dir))
                        else:
                            test_method()
                        print(f"  ✓ {method_name}")
                        passed += 1
                    except AssertionError as e:
                        print(f"  ✗ {method_name}: {e}")
                        failed += 1
                    except Exception as e:
                        print(f"  ✗ {method_name}: Exception - {e}")
                        failed += 1
    
    print("\n" + "=" * 50)
    print(f"📊 Results: {passed} passed, {failed} failed")
    
    if failed == 0:
        print("🎉 All tests passed!")
        return 0
    else:
        print(f"⚠️  {failed} test(s) failed")
        return 1


if __name__ == "__main__":
    sys.exit(run_tests())
