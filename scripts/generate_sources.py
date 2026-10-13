import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path


def dart_string(value):
    return "'" + value.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\n', '\\n').replace('\r', '\\r') + "'"


def source_symbol(source):
    return '_source' + ''.join(part.capitalize() for part in source['id'].split('-'))


def render_manifest(manifest):
    sources = manifest['sources']
    lines = ["part of 'models.dart';", '']
    for source in sources:
        lines.extend([
            f"const {source_symbol(source)} = SourceSite(",
            '  ' + dart_string(source['id']) + ',',
            '  ' + dart_string(source['name']) + ',',
            '  ' + dart_string(source['description']) + ',',
        ])
        for key in ('groupId', 'groupName', 'entryName', 'restricted', 'default', 'searchMode', 'searchSuggestions', 'metadataFields'):
            name = 'defaultEnabled' if key == 'default' else key
            value = source[key]
            if isinstance(value, list):
                literal = '<String>[' + ', '.join(dart_string(field) for field in value) + ']'
            else:
                literal = str(value).lower() if isinstance(value, bool) else dart_string(value)
            lines.append(f'  {name}: {literal},')
        lines.extend([');', ''])
    selections = {
        '_primarySourceSites': [source for source in sources if not source['restricted']],
        '_restrictedSourceSites': [source for source in sources if source['restricted']],
        '_defaultSourceSites': [source for source in sources if source['default']],
    }
    for name, selected in selections.items():
        inline = f'const {name} = <SourceSite>[' + ', '.join(source_symbol(source) for source in selected) + '];'
        if len(inline) <= 80:
            lines.extend([inline, ''])
        else:
            lines.append(f'const {name} = <SourceSite>[')
            lines.extend('  ' + source_symbol(source) + ',' for source in selected)
            lines.extend(['];', ''])
    lines.append('const _rankingSourceIDs = <String, String>{')
    for board, source in sorted(manifest['rankingSources'].items()):
        lines.append('  ' + dart_string(board) + ': ' + dart_string(source) + ',')
    lines.extend(['};', ''])
    return '\n'.join(lines)


def generate_sources(root, *, check=False, go=None, environment=None):
    go = go or shutil.which('go')
    if not go:
        raise ValueError('生成站源清单需要 Go。')
    host_environment = dict(os.environ if environment is None else environment)
    for name in ('GOOS', 'GOARCH', 'GOARM', 'CC', 'CGO_CFLAGS', 'CGO_LDFLAGS'):
        host_environment.pop(name, None)
    host_environment['CGO_ENABLED'] = '0'
    manifest = json.loads(subprocess.check_output(
        [go, 'run', './cmd/provider_manifest'], cwd=root / 'native', env=host_environment, text=True,
    ))
    content = render_manifest(manifest)
    destination = root / 'lib' / 'source_registry.g.dart'
    current = destination.read_text(encoding='utf-8') if destination.exists() else None
    if check:
        if current != content:
            raise ValueError('站源清单未同步，请执行 python3 scripts/generate_sources.py。')
    elif current != content:
        destination.write_text(content, encoding='utf-8')
    return len(manifest['sources'])


def main():
    parser = argparse.ArgumentParser(description='从 Go Provider 注册表生成 Flutter 站源清单。')
    parser.add_argument('--check', action='store_true', help='只检查已生成清单是否一致')
    options = parser.parse_args()
    try:
        count = generate_sources(Path(__file__).resolve().parents[1], check=options.check)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, str(error) + '\n')
    print(f'站源清单{"一致" if options.check else "已生成"}：{count} 个站源。')


if __name__ == '__main__':
    main()
