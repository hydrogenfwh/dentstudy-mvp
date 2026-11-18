"""Exercise release command routing without SDK downloads or signing secrets."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[2] / 'mobile/release.sh'


class MobileReleaseTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='dentstudy-release-')
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / 'project with spaces'
        self.mobile = self.root / 'mobile'
        self.bin = self.root / 'bin'
        for folder in ('mobile/android', 'mobile/ios/Runner.xcodeproj', 'bin',
                       'sdk/platform-tools', 'sdk/platforms', 'sdk/build-tools'):
            (self.root / folder).mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SOURCE, self.mobile / 'release.sh')
        (self.mobile / 'pubspec.yaml').write_text('version: 1.2.3+123\n')
        (self.mobile / 'android/key.properties').touch()
        (self.mobile / 'ios/Runner.xcodeproj/project.pbxproj').write_text(
            'DEVELOPMENT_TEAM = ABC1234567;\n')
        for path in (self.bin / 'java', self.bin / 'pod', self.bin / 'xcodebuild',
                     self.root / 'sdk/platform-tools/adb'):
            path.write_text('#!/bin/sh\nexit 0\n')
            path.chmod(0o755)
        self.log = self.root / 'flutter-args'
        flutter = self.bin / 'flutter'
        flutter.write_text('#!/bin/sh\nprintf "%s\\n" "$@" > "$RELEASE_TEST_LOG"\n')
        flutter.chmod(0o755)
        self.env = dict(os.environ, PATH=f'{self.bin}:/usr/bin:/bin',
                        JAVA_HOME=str(self.root), ANDROID_HOME=str(self.root / 'sdk'),
                        FLUTTER_BIN=str(flutter), RELEASE_TEST_LOG=str(self.log))

    def run_release(self, target):
        return subprocess.run(['/bin/bash', str(self.mobile / 'release.sh'), target],
                              cwd=self.root, env=self.env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    def test_check_never_builds(self):
        result = self.run_release('check')
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.log.exists())

    def test_missing_android_credentials_stop_before_build(self):
        (self.mobile / 'android/key.properties').unlink()
        result = self.run_release('android')
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertFalse(self.log.exists())

    def test_missing_ios_team_stops_before_build(self):
        (self.mobile / 'ios/Runner.xcodeproj/project.pbxproj').write_text('')
        result = self.run_release('ios')
        self.assertEqual(result.returncode, 1, result.stdout)
        self.assertFalse(self.log.exists())

    def test_both_builds_use_production_api_and_pubspec_version(self):
        for platform, kind in [('android', 'appbundle'), ('ios', 'ipa')]:
            with self.subTest(platform=platform):
                result = self.run_release(platform)
                self.assertEqual(result.returncode, 0, result.stdout)
                args = self.log.read_text().splitlines()
                self.assertEqual(args[:3], ['build', kind, '--release'])
                self.assertIn('--dart-define=API_URL=https://dentstudy.uno/api', args)
                self.assertIn('--dart-define=APP_VERSION=1.2.3', args)
                self.assertTrue(any(a.startswith('--dart-define=BUILD_TIME=') and
                                    a.endswith('北京时间') for a in args))

    def test_unknown_target_is_rejected(self):
        self.assertEqual(self.run_release('upload').returncode, 2)
        self.assertFalse(self.log.exists())


if __name__ == '__main__':
    unittest.main()
