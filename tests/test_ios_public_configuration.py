import json
import tempfile
import unittest
from pathlib import Path

from scripts.copy_ios_public_configuration import copy_configuration, validate_production


class IOSPublicConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.source = self.root / "source"
        self.destination = self.root / "bundle"
        self.source.mkdir()
        self.destination.mkdir()

    def production_file(self, url="https://production123.supabase.co", key="sb_publishable_" + "a" * 32):
        path = self.source / "ProductionPublicConfiguration.json"
        path.write_text(json.dumps({"url": url, "anon_key": key}), encoding="utf-8")
        return path

    def test_release_copies_production_only(self):
        self.production_file()
        (self.destination / "DevelopmentPublicConfiguration.json").write_text("old", encoding="utf-8")
        copy_configuration(self.source, self.destination, "Release", "build", "com.mefrion.app")
        self.assertFalse((self.destination / "DevelopmentPublicConfiguration.json").exists())
        self.assertTrue((self.destination / "ProductionPublicConfiguration.json").exists())

    def test_release_fails_without_production_config(self):
        with self.assertRaises(ValueError):
            copy_configuration(self.source, self.destination, "Release", "build", "com.mefrion.app")

    def test_development_backend_is_rejected_for_release(self):
        path = self.production_file("https://pmrvzpuznwzuejbuhaqm.supabase.co")
        with self.assertRaises(ValueError):
            validate_production(path)

    def test_malformed_url_is_rejected_cleanly(self):
        path = self.production_file("https://production123.supabase.co:bad")
        with self.assertRaises(ValueError):
            validate_production(path)

    def test_secret_and_extra_fields_are_rejected(self):
        path = self.production_file(key="service_role_secret")
        (self.destination / "ProductionPublicConfiguration.json").write_text("stale", encoding="utf-8")
        with self.assertRaises(ValueError):
            copy_configuration(self.source, self.destination, "Release", "build", "com.mefrion.app")
        self.assertFalse((self.destination / "ProductionPublicConfiguration.json").exists())
        path.write_text(json.dumps({"url": "https://production123.supabase.co", "anon_key": "sb_publishable_" + "a" * 32, "service_role": "secret"}), encoding="utf-8")
        with self.assertRaises(ValueError):
            validate_production(path)

    def test_archive_rejects_development_bundle_id(self):
        self.production_file()
        with self.assertRaises(ValueError):
            copy_configuration(self.source, self.destination, "Release", "install", "dev.local.mefrion.prototype")

    def test_debug_removes_production_config(self):
        (self.source / "DevelopmentPublicConfiguration.json").write_text("{}", encoding="utf-8")
        (self.destination / "ProductionPublicConfiguration.json").write_text("old", encoding="utf-8")
        copy_configuration(self.source, self.destination, "Debug", "build", "dev.local.mefrion.prototype")
        self.assertFalse((self.destination / "ProductionPublicConfiguration.json").exists())
        self.assertTrue((self.destination / "DevelopmentPublicConfiguration.json").exists())


if __name__ == "__main__":
    unittest.main()
