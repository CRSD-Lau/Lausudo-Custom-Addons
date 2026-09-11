"""Lausudo Suite catalog, public builder and verifier. Author: Neil Mitchell."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ASSETS = {'.lua', '.toc', '.xml', '.ttf', '.tga', '.blp', '.txt', '.md'}
PRIVATE = {'wtf', 'account', 'savedvariables', 'screenshots', 'logs', 'cache', '.private-staging'}
TEXT = {'.lua', '.toc', '.xml', '.txt', '.md', '.json', '.ps1', '.py', '.yml'}
SECRET = re.compile(r'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|xox[baprs]-[A-Za-z0-9-]{20,}|-----BEGIN (?:RSA |OPENSSH )?PRIVATE KEY-----)')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_name(name):
    parts = name.split('/')
    if not name or '\\' in name or ':' in name or any(p in {'', '.', '..'} for p in parts):
        raise ValueError('Unsafe archive or source path')
    if any(p.casefold() in PRIVATE or 'loginui' in p.casefold() for p in parts):
        raise ValueError('Private path rejected')
    if any(p.endswith((' ', '.')) or re.fullmatch(r'(?i)(con|prn|aux|nul|com[1-9]|lpt[1-9])(?:\..*)?', p) for p in parts):
        raise ValueError('Windows-unsafe path rejected')


def no_links(path):
    for item in [path, *path.parents]:
        if item.exists() or item.is_symlink():
            info = item.lstat()
            if stat.S_ISLNK(info.st_mode) or getattr(info, 'st_file_attributes', 0) & 0x400:
                raise ValueError('Symlink or reparse point rejected')


def read_public(path):
    no_links(path)
    data = path.read_bytes()
    if path.suffix.lower() in TEXT and SECRET.search(data.decode('utf-8', errors='replace')):
        raise ValueError('Credential-shaped content rejected; value withheld')
    return data


def windows_file(folder, relative):
    """Resolve TOC entries using the target Windows client's case rules."""
    current = folder
    for component in relative.split('/'):
        if not current.is_dir(): return False
        matches = [p for p in current.iterdir() if p.name.casefold() == component.casefold()]
        if len(matches) != 1: return False
        current = matches[0]
        no_links(current)
    return current.is_file()


def resolve(modules, selected):
    result, visiting = [], set()
    def visit(key):
        if key not in modules: raise ValueError('Unknown module: ' + key)
        if key in visiting: raise ValueError('Dependency cycle')
        if key in result: return
        visiting.add(key)
        for dependency in modules[key]['requires']: visit(dependency)
        visiting.remove(key)
        result.append(key)
    for key in selected: visit(key)
    return result


def catalog(root=ROOT):
    data = json.loads(read_public(root / 'suite.json'))
    if data['name'] != 'Lausudo Suite' or not re.fullmatch(r'\d+\.\d+\.\d+(?:-[a-z]+\.\d+)?', data['version']):
        raise ValueError('Invalid suite name/version')
    modules = {m['id']: m for m in data['modules']}
    if len(modules) != len(data['modules']) or any(not re.fullmatch('[a-z][a-z0-9-]*', k) for k in modules):
        raise ValueError('Invalid or duplicate module ID')
    seen = set()
    for module in modules.values():
        for addon in module['addons']:
            safe_name(addon)
            if not re.fullmatch(r'(?:addons|third_party/addons)/[A-Za-z0-9_]+', addon):
                raise ValueError('Source must be a repository addon folder')
            key = PurePosixPath(addon).name.casefold()
            if key in seen: raise ValueError('Duplicate addon folder')
            seen.add(key)
    resolve(modules, list(modules))
    return data, modules


def source_files(root, modules, selected):
    files = {}
    for key in resolve(modules, selected):
        for addon in modules[key]['addons']:
            folder = root / addon
            no_links(folder)
            if not folder.is_dir() or not (folder / (folder.name + '.toc')).is_file():
                raise ValueError('Addon folder/TOC missing: ' + addon)
            for directory, dirs, names in os.walk(folder, followlinks=False):
                for name in dirs: no_links(Path(directory) / name)
                for name in sorted(names):
                    path = Path(directory) / name
                    relative = path.relative_to(folder).as_posix()
                    safe_name(relative)
                    if path.suffix.lower() not in ASSETS: raise ValueError('Unapproved asset type: ' + path.suffix)
                    files['Interface/AddOns/' + folder.name + '/' + relative] = path
    for name in ['README.md', 'LICENSE', 'THIRD-PARTY-NOTICES.md', 'suite.json', 'CONTRIBUTING.md', 'CHANGELOG.md']:
        files[name] = root / name
    for name in ['INSTALL.md', 'MODULES.md', 'PROFILES.md', 'CLIENT-ENHANCEMENTS.md', 'BACKUP-AND-SHARING.md', 'RELEASE-CHECKLIST.md']:
        files['docs/' + name] = root / 'docs' / name
    files['docs/images/crisp-fct-tidyplates-preview.png'] = root / 'docs/images/crisp-fct-tidyplates-preview.png'
    files['third_party/README.md'] = root / 'third_party/README.md'
    for path in (root / 'licenses').glob('*'):
        if path.is_file(): files['licenses/' + path.name] = path
    files['tools/Inspect-Client.ps1'] = root / 'tools/Inspect-Client.ps1'
    lowered = set()
    for name in files:
        safe_name(name)
        if name.casefold() in lowered: raise ValueError('Case-colliding package paths')
        lowered.add(name.casefold())
    return files


def validate(root=ROOT):
    data, modules = catalog(root)
    files = source_files(root, modules, list(modules))
    for path in files.values():
        raw = read_public(path)
        if path.suffix == '.toc':
            text = raw.decode('utf-8-sig')
            if not re.search(r'^## Interface: 30300\s*$', text, re.M): raise ValueError('Unsupported TOC interface')
            for line in text.splitlines():
                line = line.strip()
                if line and not line.startswith('#'):
                    ref = line.replace('\\', '/')
                    safe_name(ref)
                    if not windows_file(path.parent, ref):
                        raise ValueError('TOC entry missing or ambiguous: ' + path.relative_to(root).as_posix() + ' -> ' + ref)
    core = (root / 'addons/LausudoSuite/LausudoSuite.toc').read_text()
    if '## Version: ' + data['version'] not in core: raise ValueError('Suite version mismatch')
    if (root / '.git').exists():
        tracked = subprocess.check_output(['git', '-C', str(root), 'ls-files', '-z']).decode('utf-8').split('\0')
        for name in filter(None, tracked):
            safe_name(name)
            path = root / name
            if path.suffix.lower() in {'.wtf', '.zip', '.7z', '.rar', '.exe', '.dll', '.mpq', '.pyc'} or path.name == '.env':
                raise ValueError('Private or generated file tracked in public Git')
            if path.is_file(): read_public(path)
    for folder in ['addons', 'third_party', 'tools', 'tests', 'docs', '.github']:
        for directory, dirs, names in os.walk(root / folder, followlinks=False):
            dirs[:] = [d for d in dirs if d != '__pycache__']
            for name in dirs:
                path = Path(directory) / name
                safe_name(path.relative_to(root).as_posix()); no_links(path)
            for name in names:
                path = Path(directory) / name
                safe_name(path.relative_to(root).as_posix()); read_public(path)
    return len(files)


def write_entry(archive, name, data):
    info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    archive.writestr(info, data)


def build(root=ROOT, selected=None):
    validate(root)
    data, modules = catalog(root)
    chosen = resolve(modules, selected or list(modules))
    files = source_files(root, modules, chosen)
    label = 'all' if selected is None else '+'.join(sorted(set(selected)))
    output = root / 'dist'
    no_links(output)
    output.mkdir(exist_ok=True)
    destination = output / ('Lausudo-Suite-' + data['version'] + '-' + label + '.zip')
    no_links(destination)
    manifest = {'name': data['name'], 'version': data['version'], 'author': 'Neil Mitchell',
                'lastModifiedBy': 'Neil Mitchell', 'modules': chosen, 'files': {}}
    with zipfile.ZipFile(destination, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        archive.comment = b'Author: Neil Mitchell; Last Modified By: Neil Mitchell'
        for name, path in sorted(files.items()):
            raw = read_public(path)
            manifest['files'][name] = {'sha256': digest(raw), 'size': len(raw)}
            write_entry(archive, name, raw)
        write_entry(archive, 'package-manifest.json', (json.dumps(manifest, sort_keys=True, indent=2) + '\n').encode())
    verify(destination)
    checksum = destination.with_suffix('.sha256')
    no_links(checksum)
    checksum.write_text(digest(destination.read_bytes()) + '  ' + destination.name + '\n', encoding='utf-8')
    return destination


def verify(path):
    with zipfile.ZipFile(path) as archive:
        names, lowered = archive.namelist(), set()
        for info in archive.infolist():
            safe_name(info.filename)
            if info.filename.casefold() in lowered: raise ValueError('Duplicate ZIP member')
            lowered.add(info.filename.casefold())
            if stat.S_ISLNK(info.external_attr >> 16): raise ValueError('ZIP symlink rejected')
            if info.file_size > 64 * 1024 * 1024: raise ValueError('Oversized suite member')
        if sum(i.file_size for i in archive.infolist()) > 512 * 1024 * 1024: raise ValueError('Oversized suite')
        manifest = json.loads(archive.read('package-manifest.json'))
        if set(names) != set(manifest['files']) | {'package-manifest.json'}: raise ValueError('Unexpected or missing ZIP member')
        for name, expected in manifest['files'].items():
            raw = archive.read(name)
            if len(raw) != expected['size'] or digest(raw) != expected['sha256']: raise ValueError('Package hash mismatch')
    return len(manifest['files'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['list', 'validate', 'build', 'verify'])
    parser.add_argument('--module', action='append', dest='modules')
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    if args.command == 'list':
        for key, module in catalog()[1].items(): print(key + ': ' + module['name'] + ' [' + module['status'] + ']')
    elif args.command == 'validate': print('Validated public package files:', validate())
    elif args.command == 'build': print(build(selected=args.modules))
    elif args.command == 'verify':
        if not args.archive: parser.error('--archive is required for verify')
        print('Verified package file hashes:', verify(args.archive))


if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        print('ERROR:', error, file=sys.stderr)
        sys.exit(1)
