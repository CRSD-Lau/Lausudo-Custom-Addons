"""Publish only an explicit alpha preview from GitHub CI. Author: Neil Mitchell."""
import json
import os
from pathlib import Path
import subprocess
import suite


def gh(*arguments):
    return subprocess.check_output(['gh', *arguments], text=True).strip()


def main():
    if os.environ.get('GITHUB_ACTIONS') != 'true' or os.environ.get('GITHUB_REF') != 'refs/heads/main':
        raise ValueError('Release publishing requires the main-branch GitHub workflow')
    data, modules = suite.catalog()
    tag = 'v' + data['version']
    if os.environ.get('RELEASE_TAG') != tag or '-alpha.' not in tag:
        raise ValueError('Only the exact catalog alpha tag can be published here')
    repository = os.environ['GITHUB_REPOSITORY']
    checks = json.loads(gh('api', '--paginate', '--slurp', 'repos/' + repository + '/commits/' + os.environ['GITHUB_SHA'] + '/check-runs'))
    successful = {c['name'] for page in checks for c in page['check_runs']
                  if c['status'] == 'completed' and c['conclusion'] == 'success'
                  and c.get('app', {}).get('slug') == 'github-actions'}
    if not {'validate (ubuntu-latest)', 'validate (windows-latest)'} <= successful:
        raise ValueError('Both exact-commit validation jobs must pass before publication')
    releases = json.loads(gh('api', '--paginate', '--slurp', 'repos/' + repository + '/releases'))
    if any(r['tag_name'] == tag for page in releases for r in page):
        raise ValueError('Release already exists; inspect it instead of replacing its assets')
    tags = json.loads(gh('api', '--paginate', '--slurp', 'repos/' + repository + '/tags'))
    if any(t['name'] == tag for page in tags for t in page): raise ValueError('Tag already exists')
    assets = []
    for selection in [None, *[[key] for key in modules]]:
        archive = suite.build(selected=selection)
        assets.extend([archive, archive.with_suffix('.sha256')])
    notes = suite.ROOT / 'dist/release-notes.md'
    notes.write_text('Lausudo Suite preview: modular addons, opt-in visual profiles, and setup documentation.\n\n'
                     'Includes one all-modules ZIP and individual module ZIPs with bundled dependencies. '
                     'Compare each download with its matching SHA-256 file.\n\n'
                     'New profile adapters and public addon adaptations have offline tests; in-game acceptance remains outstanding. '
                     'This is not an exact owner UI export or a full client recovery backup. '
                     'See docs/RELEASE-CHECKLIST.md and CHANGELOG.md in the repository.\n', encoding='utf-8')
    gh('release', 'create', tag, '--repo', repository, '--target', os.environ['GITHUB_SHA'], '--draft',
       '--prerelease', '--title', data['name'] + ' ' + data['version'], '--notes-file', str(notes),
       *[str(path) for path in assets])
    pages = json.loads(gh('api', '--paginate', '--slurp', 'repos/' + repository + '/releases'))
    release = next(r for page in pages for r in page if r['tag_name'] == tag)
    remote = json.loads(gh('api', '--paginate', '--slurp', 'repos/' + repository + '/releases/' + str(release['id']) + '/assets'))
    by_name = {a['name']: a for page in remote for a in page}
    if set(by_name) != {p.name for p in assets}: raise ValueError('Uploaded asset inventory mismatch; release left draft')
    for path in assets:
        asset = by_name[path.name]
        if asset['size'] != path.stat().st_size or asset.get('digest') != 'sha256:' + suite.digest(path.read_bytes()):
            raise ValueError('Uploaded asset hash mismatch; release left draft')
    gh('release', 'edit', tag, '--repo', repository, '--draft=false', '--prerelease', '--latest=false')
    print('Published verified preview:', tag)


if __name__ == '__main__': main()
