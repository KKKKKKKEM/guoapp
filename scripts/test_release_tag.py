import tempfile
import unittest
from pathlib import Path

from release_tag import release_version


class ReleaseTagTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='release-tag-')
        self.addCleanup(self.directory.cleanup)
        self.pubspec = Path(self.directory.name) / 'pubspec.yaml'
        self.pubspec.write_text('name: synthetic_app\nversion: 1.2.3+4\n', encoding='utf-8')

    def test_tag_becomes_invalid_when_source_build_number_changes(self):
        self.assertEqual(release_version('v1.2.3+4', self.pubspec), '1.2.3+4')
        self.pubspec.write_text('version: 1.2.3+5\n', encoding='utf-8')
        with self.assertRaises(ValueError):
            release_version('v1.2.3+4', self.pubspec)

    def test_version_only_tag_cannot_select_an_ambiguous_build(self):
        with self.assertRaises(ValueError):
            release_version('v1.2.3', self.pubspec)

    def test_missing_source_version_cannot_be_published(self):
        self.pubspec.write_text('name: synthetic_app\n', encoding='utf-8')
        with self.assertRaises(ValueError):
            release_version('v1.2.3+4', self.pubspec)


if __name__ == '__main__':
    unittest.main()
