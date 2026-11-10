#!/usr/bin/env python3
"""Build an ad-hoc signed DiskWing bundle from this checkout on macOS."""
from pathlib import Path
import argparse
import os
import plistlib
import shutil
import subprocess
import uuid

PROJECT = Path(__file__).resolve().parent
BUNDLE_ID = 'com.cachessd.app'  # Preserve the local alpha's identity and preferences.


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scratch', type=Path, default=PROJECT / '.build')
    parser.add_argument('--configuration', choices=['debug', 'release'], default='release')
    parser.add_argument('--output', type=Path, default=PROJECT / 'dist/DiskWing.app')
    return parser.parse_args(argv)


def validate_output(output):
    if output.is_symlink() or output.suffix != '.app':
        raise ValueError('Output must be a regular .app directory, without a symbolic link.')
    if output.exists():
        try:
            with (output / 'Contents/Info.plist').open('rb') as file:
                identifier = plistlib.load(file).get('CFBundleIdentifier')
        except (OSError, plistlib.InvalidFileException) as error:
            raise ValueError('Refusing to replace a directory without a DiskWing identity.') from error
        if identifier != BUNDLE_ID:
            raise ValueError('Refusing to replace an unrelated application.')


def main(argv=None):
    args = parse_args(argv)
    validate_output(args.output.absolute())
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
    swift = ['swift', 'build', '--package-path', str(PROJECT), '--scratch-path', str(scratch), '-c', args.configuration]
    subprocess.run(swift + ['-j', '2'], check=True, env=env)
    binary_dir = Path(subprocess.check_output(swift + ['--show-bin-path'], text=True, env=env).strip())
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = output.parent / ('.DiskWing-build-' + str(uuid.uuid4()) + '.app')
    backup = output.parent / ('.DiskWing-previous-' + str(uuid.uuid4()) + '.app')
    try:
        macos = stage / 'Contents/MacOS'
        resources = stage / 'Contents/Resources'
        macos.mkdir(parents=True)
        resources.mkdir()
        for name in ['CacheSSD', 'CacheSSDHelper']:
            shutil.copyfile(binary_dir / name, macos / name)
            (macos / name).chmod(0o755)
        info = {
            'CFBundleDevelopmentRegion': 'pt_BR', 'CFBundleExecutable': 'CacheSSD',
            'CFBundleIdentifier': BUNDLE_ID, 'CFBundleName': 'DiskWing',
            'CFBundleDisplayName': 'DiskWing', 'CFBundlePackageType': 'APPL',
            'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '2',
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
        subprocess.run(['codesign', '--force', '--sign', '-', '--identifier', 'com.cachessd.helper', '--options', 'runtime', str(macos / 'CacheSSDHelper')], check=True)
        subprocess.run(['codesign', '--force', '--sign', '-', '--options', 'runtime', str(stage)], check=True)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(stage)], check=True)
        validate_output(output)
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
        if stage.exists():
            shutil.rmtree(stage)
    print(output)


if __name__ == '__main__':
    main()
