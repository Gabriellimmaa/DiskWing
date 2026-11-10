#!/usr/bin/env python3
"""Build a verified DiskWing bundle and immutable candidate archive on macOS."""
from pathlib import Path
import argparse
import base64
import os
import plistlib
import shutil
import subprocess
import uuid
import re
import json
import importlib.util

PROJECT = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location('diskwing_release_evidence', PROJECT / 'scripts/release_evidence.py')
release_evidence = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(release_evidence)
BUNDLE_ID = 'com.cachessd.app'  # Preserve the local alpha's identity and preferences.


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--acceptance-bundle', action='store_true', help='Isolated dev-only DiskWing Samples application domain.')
    parser.add_argument('--profile', choices=['dev', 'candidate', 'production'], default='dev')
    parser.add_argument('--scratch', type=Path, default=PROJECT / '.build')
    parser.add_argument('--configuration', choices=['debug', 'release'], default='release')
    parser.add_argument('--output', type=Path, default=PROJECT / 'dist/DiskWing.app')
    parser.add_argument('--version', default='0.2.0-dev')
    parser.add_argument('--build-number', default='3')
    parser.add_argument('--sign-identity', default='-')
    parser.add_argument('--with-updater', action='store_true')
    parser.add_argument('--feed-url')
    parser.add_argument('--public-ed-key')
    parser.add_argument('--notary-profile', help='Existing notarytool Keychain profile; no credentials are written to the checkout.')
    return parser.parse_args(argv)


def release_settings(args):
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.]+)?', args.version) or re.fullmatch(r'[0-9]{1,18}', args.build_number) is None or int(args.build_number) < 1:
        raise ValueError('Use a semantic version and a positive numeric build number.')
    if args.acceptance_bundle and (args.profile != 'dev' or args.with_updater or args.notary_profile):
        raise ValueError('Samples bundles are dev-only without updater or notarization.')
    developer_id = args.sign_identity.startswith('Developer ID Application: ')
    if args.profile == 'production' and (not developer_id or not args.notary_profile or args.configuration != 'release' or not args.with_updater):
        raise ValueError('Production requires a release build, signed updater, Developer ID Application and a notarization profile.')
    if args.notary_profile and not developer_id:
        raise ValueError('Notarization requires a Developer ID Application identity.')
    if not args.with_updater:
        if args.feed_url or args.public_ed_key:
            raise ValueError('Update settings require --with-updater.')
        return {}
    from urllib.parse import urlsplit
    feed = urlsplit(args.feed_url or '')
    if not developer_id or feed.scheme != 'https' or not feed.hostname or feed.username or feed.password or feed.fragment or feed.query:
        raise ValueError('The updater requires Developer ID and a public HTTPS appcast without credentials or query parameters.')
    try:
        key = base64.b64decode(args.public_ed_key or '', validate=True)
    except (ValueError, TypeError) as error:
        raise ValueError('Invalid public Ed25519 key.') from error
    if len(key) != 32:
        raise ValueError('The public Ed25519 key must contain exactly 32 bytes.')
    return {'SUFeedURL': args.feed_url, 'SUPublicEDKey': args.public_ed_key,
            'SUEnableAutomaticChecks': False, 'SUAutomaticallyUpdate': False,
            'SUSendProfileInfo': False, 'SUEnableSystemProfiling': False}


def sign_bundle(stage, identity, helper_identifier='com.cachessd.helper'):
    options = ['--force', '--sign', identity, '--options', 'runtime']
    if identity != '-':
        options += ['--timestamp']
    framework = stage / 'Contents/Frameworks/Sparkle.framework'
    if framework.exists():
        # Sign nested code from the inside out. Never use --deep to sign.
        paths = []
        for path in framework.rglob('*'):
            if path.is_symlink():
                continue
            if path.is_file():
                with path.open('rb') as file:
                    magic = file.read(4)
                if magic in [b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca']:
                    paths.append(path)
            elif path.suffix in ['.app', '.xpc']:
                paths.append(path)
        for path in sorted(paths, key=lambda p: len(p.parts), reverse=True) + [framework]:
            subprocess.run(['codesign'] + options + [str(path)], check=True)
    helper = stage / 'Contents/MacOS/CacheSSDHelper'
    subprocess.run(['codesign'] + options + ['--identifier', helper_identifier, str(helper)], check=True)
    subprocess.run(['codesign'] + options + [str(stage)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(stage)], check=True)


def notarize(stage, profile):
    archive = stage.parent / (stage.stem + '-notary.zip')
    try:
        subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(stage), str(archive)], check=True)
        result = subprocess.check_output(['xcrun', 'notarytool', 'submit', str(archive), '--keychain-profile', profile, '--wait', '--output-format', 'json'], text=True)
        if json.loads(result).get('status') != 'Accepted':
            raise ValueError('Apple did not accept this build for notarization. The previous app was preserved.')
        subprocess.run(['xcrun', 'stapler', 'staple', str(stage)], check=True)
        subprocess.run(['xcrun', 'stapler', 'validate', str(stage)], check=True)
        subprocess.run(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(stage)], check=True)
    finally:
        archive.unlink(missing_ok=True)


def localized_usage_descriptions(info):
    english = {
        'NSDocumentsFolderUsageDescription': 'Scan document names and sizes and review actions chosen by you.',
        'NSDownloadsFolderUsageDescription': 'Find large downloaded files and review available actions.',
        'NSDesktopFolderUsageDescription': 'Scan Desktop files when you choose this folder.',
        'NSRemovableVolumesUsageDescription': 'Scan the selected SSD and copy caches after your review.'
    }
    return {'en': english, 'pt-BR': {key: info[key] for key in english}}


def validate_output(output, bundle_id=BUNDLE_ID):
    if output.is_symlink() or output.suffix != '.app':
        raise ValueError('Output must be a regular .app directory, without a symbolic link.')
    if output.exists():
        try:
            with (output / 'Contents/Info.plist').open('rb') as file:
                identifier = plistlib.load(file).get('CFBundleIdentifier')
        except (OSError, plistlib.InvalidFileException) as error:
            raise ValueError('Refusing to replace a directory without a DiskWing identity.') from error
        if identifier != bundle_id:
            raise ValueError('Refusing to replace an unrelated application.')


def main(argv=None):
    args = parse_args(argv)
    update_settings = release_settings(args)
    bundle_id = BUNDLE_ID + ('.acceptance' if args.acceptance_bundle else '')
    display_name = 'DiskWing Samples' if args.acceptance_bundle else 'DiskWing'
    if args.acceptance_bundle and args.output == PROJECT / 'dist/DiskWing.app':
        args.output = PROJECT / 'dist/DiskWingAcceptance.app'
    commit, dirty = release_evidence.source_identity(PROJECT, args.profile)
    validate_output(args.output.absolute(), bundle_id)
    output = args.output.resolve()
    scratch = args.scratch.resolve()
    if scratch == PROJECT or scratch in PROJECT.parents:
        raise ValueError('Scratch must be a dedicated build directory, not the checkout or its parent.')
    for name in ['Sources', 'Tests', 'Assets', 'design', 'docs', '.git', '.local']:
        protected = PROJECT / name
        if scratch == protected or protected in scratch.parents or output == protected or protected in output.parents:
            raise ValueError('Build artifacts must not replace source, Git, or private migration directories.')
    scratch.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(scratch / 'ModuleCache'))
    env['DISKWING_ENABLE_UPDATER'] = '1' if args.with_updater else '0'
    swift = ['swift', 'build', '--package-path', str(PROJECT), '--scratch-path', str(scratch), '-c', args.configuration]
    swift += ['--arch', 'arm64']
    subprocess.run(swift + ['-j', '2'], check=True, env=env)
    binary_dir = Path(subprocess.check_output(swift + ['--show-bin-path'], text=True, env=env).strip())
    output.parent.mkdir(parents=True, exist_ok=True)
    stage_root = output.parent / ('.DiskWing-build-' + str(uuid.uuid4()))
    stage = stage_root / output.name
    backup = output.parent / ('.DiskWing-previous-' + str(uuid.uuid4()) + '.app')
    try:
        macos = stage / 'Contents/MacOS'
        resources = stage / 'Contents/Resources'
        macos.mkdir(parents=True)
        resources.mkdir()
        for name in ['CacheSSD', 'CacheSSDHelper']:
            shutil.copyfile(binary_dir / name, macos / name)
            (macos / name).chmod(0o755)
            if args.configuration == 'release':
                subprocess.run(['strip', '-S', '-x', str(macos / name)], check=True)
        for bundle in binary_dir.glob('DiskWing_*.bundle'):
            shutil.copytree(bundle, resources / bundle.name, symlinks=True)
        if args.with_updater:
            framework = next((scratch / 'artifacts').glob('sparkle/Sparkle/Sparkle.xcframework/macos-*/Sparkle.framework'), None)
            if framework is None:
                raise ValueError('Resolved Sparkle framework was not found.')
            (stage / 'Contents/Frameworks').mkdir()
            shutil.copytree(framework, stage / 'Contents/Frameworks/Sparkle.framework', symlinks=True)
            shutil.copyfile(PROJECT / 'LICENSES/Sparkle.txt', resources / 'Sparkle-LICENSE.txt')
        info = {
            'CFBundleDevelopmentRegion': 'pt_BR', 'CFBundleExecutable': 'CacheSSD',
            'CFBundleIdentifier': bundle_id, 'CFBundleName': display_name,
            'CFBundleDisplayName': display_name, 'CFBundlePackageType': 'APPL',
            'CFBundleShortVersionString': args.version, 'CFBundleVersion': args.build_number,
            'CFBundleLocalizations': ['en', 'pt-BR'],
            'LSMinimumSystemVersion': '14.0', 'LSApplicationCategoryType': 'public.app-category.utilities',
            'NSPrincipalClass': 'NSApplication', 'NSHighResolutionCapable': True,
            'NSSupportsAutomaticGraphicsSwitching': True,
            'NSHumanReadableCopyright': 'Copyright 2026 Gabriel Lima and DiskWing contributors. MIT License.',
            'NSDocumentsFolderUsageDescription': 'Analise nomes e tamanhos dos documentos e revise ações escolhidas por você.',
            'NSDownloadsFolderUsageDescription': 'Encontre arquivos grandes nos Downloads e revise as ações disponíveis.',
            'NSDesktopFolderUsageDescription': 'Analise os arquivos da Mesa quando você escolher essa pasta.',
            'NSRemovableVolumesUsageDescription': 'Analise o SSD selecionado e copie caches após sua revisão.',
            'CFBundleIconFile': 'AppIcon.icns'
        }
        info['DiskWingBuildProfile'] = args.profile
        info['DiskWingSourceDirty'] = dirty
        if commit: info['DiskWingBuildCommit'] = commit
        info.update(update_settings)
        for language, descriptions in localized_usage_descriptions(info).items():
            directory = resources / (language + '.lproj')
            directory.mkdir()
            (directory / 'InfoPlist.strings').write_text('\n'.join(json.dumps(key) + ' = ' + json.dumps(value, ensure_ascii=False) + ';' for key, value in descriptions.items()) + '\n')
        shutil.copyfile(PROJECT / 'Assets/AppIcon.icns', resources / 'AppIcon.icns')
        shutil.copyfile(PROJECT / 'LICENSE', resources / 'LICENSE')
        shutil.copyfile(PROJECT / 'THIRD_PARTY_NOTICES.md', resources / 'THIRD_PARTY_NOTICES.md')
        with (stage / 'Contents/Info.plist').open('wb') as file:
            plistlib.dump(info, file)
        privacy = {
            'NSPrivacyTracking': False, 'NSPrivacyCollectedDataTypes': [],
            'NSPrivacyAccessedAPITypes': [
                {'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryDiskSpace', 'NSPrivacyAccessedAPITypeReasons': ['85F4.1', 'E174.1']},
                {'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryFileTimestamp', 'NSPrivacyAccessedAPITypeReasons': ['3B52.1', 'C617.1']}
            ]
        }
        with (resources / 'PrivacyInfo.xcprivacy').open('wb') as file:
            plistlib.dump(privacy, file)
        # Only strip these packaging attributes from the newly generated bundle.
        for attribute in ['com.apple.FinderInfo', 'com.apple.ResourceFork']:
            subprocess.run(['/usr/bin/xattr', '-dr', attribute, str(stage)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        sign_bundle(stage, args.sign_identity, 'com.cachessd.helper' + ('.acceptance' if args.acceptance_bundle else ''))
        if args.notary_profile:
            notarize(stage, args.notary_profile)
        if args.profile != 'dev' and release_evidence.source_identity(PROJECT, args.profile) != (commit, dirty):
            raise ValueError('Source identity changed during the candidate build.')
        manifest_path, _ = release_evidence.package_candidate(stage, output.parent, commit=commit, dirty=dirty, version=args.version, build_number=args.build_number, profile=args.profile, developer_id=args.sign_identity.startswith('Developer ID Application: '), notarized=bool(args.notary_profile), updater=args.with_updater, acceptance=args.acceptance_bundle)
        validate_output(output, bundle_id)
        if output.exists():
            output.rename(backup)
        try:
            stage.rename(output)
        except BaseException:
            if backup.exists():
                backup.rename(output)
            raise
        if backup.exists():
            shutil.rmtree(backup)
    finally:
        if stage_root.exists():
            shutil.rmtree(stage_root)
    print(output)
    print(manifest_path)


if __name__ == '__main__':
    main()
