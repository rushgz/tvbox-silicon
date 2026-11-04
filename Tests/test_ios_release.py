import importlib.util
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("ios_release", ROOT / "Scripts/publish-ios-release.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class IOSReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.archive, self.directory = root / "App.xcarchive", root / "ipa"
        app = self.archive / "Products/Applications/Yingxia.app"
        app.mkdir(parents=True)
        self.directory.mkdir()
        self.info = {"CFBundleIdentifier": "com.jo32.yingxia.ios",
                     "CFBundleShortVersionString": "1.8.8", "CFBundleVersion": "46"}
        (app / "Info.plist").write_bytes(plistlib.dumps(self.info))
        self.environment = {"GITHUB_REPOSITORY": "rushgz/tvbox-silicon", "GITHUB_SHA": "a" * 40,
                            "GITHUB_RUN_ID": "12345", "GITHUB_OUTPUT": str(root / "output"),
                            "GITHUB_STEP_SUMMARY": str(root / "summary")}

    def ipa(self, name, info=None):
        path = self.directory / name
        with zipfile.ZipFile(path, "w") as package:
            package.writestr("Payload/Yingxia.app/Info.plist", plistlib.dumps(info or self.info))
        return path

    def publisher(self, exists=False, fail_upload=False):
        calls, notes = [], []

        def run(command, **kwargs):
            calls.append(command)
            if "--notes-file" in command:
                notes.append(Path(command[command.index("--notes-file") + 1]).read_text())
            if command[1:3] == ["release", "upload"] and fail_upload:
                raise subprocess.CalledProcessError(1, command)
            return subprocess.CompletedProcess(command, 0 if exists or command[2] != "view" else 1)

        return run, calls, notes

    def test_signed_and_unsigned_exports_use_the_archived_version_and_same_release_path(self):
        for signed, original in [(True, "Yingxia.ipa"), (False, "TVBox-iOS-unsigned.ipa")]:
            with self.subTest(signed=signed):
                for existing in self.directory.glob("*.ipa"):
                    existing.unlink()
                self.ipa(original)
                run, calls, notes = self.publisher()
                tag, asset = release.publish(self.archive, self.directory, signed, self.environment, run)
                self.assertEqual(asset.name, "1.8.8-adapt-ios16.ipa")
                self.assertEqual(tag, "v1.8.8-adapt-ios16-12345")
                create = next(call for call in calls if call[2] == "create")
                self.assertEqual(create[create.index("--target") + 1], "a" * 40)
                self.assertTrue(any(call[2] == "upload" and str(asset) in call for call in calls))
                self.assertIn("Signing: Signed" if signed else "Signing: Unsigned", notes[0])

    def test_rerun_updates_the_same_release_and_replaces_the_asset(self):
        self.ipa("1.8.8-adapt-ios16.ipa")
        run, calls, _ = self.publisher(exists=True)
        release.publish(self.archive, self.directory, False, self.environment, run)
        self.assertTrue(any(call[2] == "edit" for call in calls))
        self.assertFalse(any(call[2] == "create" for call in calls))
        self.assertIn("--clobber", calls[-1])

    def test_each_new_run_gets_a_separate_release(self):
        self.ipa("Yingxia.ipa")
        run, _, _ = self.publisher()
        first, _ = release.publish(self.archive, self.directory, False, self.environment, run)
        second, _ = release.publish(self.archive, self.directory, False,
                                    {**self.environment, "GITHUB_RUN_ID": "12346"}, run)
        self.assertNotEqual(first, second)

    def test_wrong_version_and_ambiguous_exports_are_not_published(self):
        self.ipa("wrong.ipa", {**self.info, "CFBundleShortVersionString": "1.8.7"})
        run, calls, _ = self.publisher()
        with self.assertRaisesRegex(ValueError, "does not match"):
            release.publish(self.archive, self.directory, False, self.environment, run)
        self.assertEqual(calls, [])
        self.ipa("another.ipa")
        with self.assertRaisesRegex(ValueError, "exactly one exported"):
            release.publish(self.archive, self.directory, False, self.environment, run)
        self.assertEqual(calls, [])

    def test_upload_failure_fails_the_step_instead_of_reporting_success(self):
        self.ipa("Yingxia.ipa")
        run, _, _ = self.publisher(fail_upload=True)
        with self.assertRaises(subprocess.CalledProcessError):
            release.publish(self.archive, self.directory, False, self.environment, run)
        self.assertFalse(Path(self.environment["GITHUB_OUTPUT"]).exists())


if __name__ == "__main__":
    unittest.main()
