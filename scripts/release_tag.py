import argparse
import os
import re
from pathlib import Path


def release_version(tag, pubspec):
    match = re.search(r'^version:\s*([\w.+-]+)\s*$', pubspec.read_text(encoding='utf-8'), re.MULTILINE)
    if not match:
        raise ValueError('pubspec.yaml 缺少合法版本号。')
    version = match.group(1)
    expected = 'v' + version
    if tag != expected:
        raise ValueError(f'Tag 与源码版本不一致：需要 {expected}，收到 {tag or "空 Tag"}。')
    return version


def main():
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description='核对构建 Tag 与 pubspec.yaml 的完整版本号。')
    parser.add_argument('--tag', default=os.environ.get('GITHUB_REF_NAME', ''))
    parser.add_argument('--pubspec', type=Path, default=root / 'pubspec.yaml')
    options = parser.parse_args()
    try:
        version = release_version(options.tag, options.pubspec)
        output = os.environ.get('GITHUB_OUTPUT')
        if output:
            with Path(output).open('a', encoding='utf-8') as stream:
                stream.write(f'version={version}\ntag={options.tag}\n')
    except (OSError, ValueError) as error:
        parser.exit(1, str(error) + '\n')
    print(f'版本 Tag 验证通过：{options.tag}（源码 {version}）。')


if __name__ == '__main__':
    main()
