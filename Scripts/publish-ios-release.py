#!/usr/bin/env python3
"""Publish the signed or unsigned IPA produced by the iOS workflow."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
from urllib.parse import quote
import zipfile


def prepare_ipa(archive: Path, directory: Path):
    apps = list((archive / "Products/Applications").glob("*.app"))
    if len(apps) != 1:
        raise ValueError("Expected exactly one archived application")
    info = plistlib.loads((apps[0] / "Info.plist").read_bytes())
    version = str(info["CFBundleShortVersionString"])
    build = str(info["CFBundleVersion"])
    if not re.fullmatch(r"\d+(?:\.\d+){1,3}", version) or not build.isdecimal():
        raise ValueError("Invalid archived application version/build")
    candidates = list(directory.glob("*.ipa"))
    if len(candidates) != 1:
        raise ValueError("Expected exactly one exported signed or unsigned IPA")
    source = candidates[0]
    with zipfile.ZipFile(source) as package:
        manifests = [name for name in package.namelist()
                     if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
        if len(manifests) != 1:
            raise ValueError("IPA must contain exactly one application")
        exported = plistlib.loads(package.read(manifests[0]))
        for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion"):
            if exported.get(key) != info.get(key):
                raise ValueError(f"Exported IPA does not match the archive: {key}")
        if package.testzip() is not None:
            raise ValueError("IPA failed ZIP integrity validation")
    asset = directory / f"{version}-adapt-ios16.ipa"
    if source != asset:
        source.rename(asset)
    return asset, version, build


def publish(archive: Path, directory: Path, signed: bool, environment=None, run=None):
    env = os.environ if environment is None else environment
    execute = subprocess.run if run is None else run
    repo, sha, run_id = (env[key] for key in ("GITHUB_REPOSITORY", "GITHUB_SHA", "GITHUB_RUN_ID"))
    if not re.fullmatch(r"[\w.-]+/[\w.-]+", repo) or not re.fullmatch(r"[a-fA-F0-9]{40}", sha) or not run_id.isdecimal():
        raise ValueError("Invalid GitHub repository, commit or run ID")
    asset, version, build = prepare_ipa(archive, directory)
    tag = f"v{version}-adapt-ios16-{run_id}"
    title = f"Yingxia {version} · iOS 16 (build {build})"
    url = f"https://github.com/{repo}/releases/tag/{quote(tag, safe='')}"
    signing = "Signed" if signed else "Unsigned (for a compatible sideloading method such as TrollStore)"
    notes = (f"iOS 16 adaptation of Yingxia {version}, build {build}.\n\n"
             f"- IPA: `{asset.name}`\n- Signing: {signing}\n"
             f"- Commit: {sha}\n- Build: https://github.com/{repo}/actions/runs/{run_id}\n")
    with tempfile.TemporaryDirectory(prefix="ios-release-") as temp:
        body = Path(temp) / "notes.md"
        body.write_text(notes)
        existing = execute(["gh", "release", "view", tag, "--repo", repo], capture_output=True, text=True)
        if existing.returncode == 0:
            command = ["gh", "release", "edit", tag, "--repo", repo]
        else:
            command = ["gh", "release", "create", tag, "--repo", repo, "--target", sha, "--latest"]
        execute([*command, "--title", title, "--notes-file", str(body)], check=True)
        execute(["gh", "release", "upload", tag, str(asset), "--repo", repo, "--clobber"], check=True)
    if env.get("GITHUB_OUTPUT"):
        with Path(env["GITHUB_OUTPUT"]).open("a") as output:
            output.write(f"version={version}\nipa_path={asset}\nrelease_tag={tag}\nrelease_url={url}\n")
    if env.get("GITHUB_STEP_SUMMARY"):
        with Path(env["GITHUB_STEP_SUMMARY"]).open("a") as summary:
            summary.write(f"### iOS 16 Release\n\n[{asset.name}]({url})\n\n{signing}.\n")
    print(f"Published {asset.name}: {url}")
    return tag, asset


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--ipa-directory", type=Path, required=True)
    parser.add_argument("--signed", choices=("true", "false"), required=True)
    args = parser.parse_args()
    publish(args.archive, args.ipa_directory, args.signed == "true")
