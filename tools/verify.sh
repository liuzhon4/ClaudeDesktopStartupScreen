#!/bin/zsh
# ClauEd 项目自检：构建 → 部署目标 → 离屏探针 → 配置一致性 → 文档链接与品牌残留
# 用法：./tools/verify.sh  或  make check
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

FAIL=0
ok()  { print -r -- "✅ $1" }
bad() { print -r -- "❌ $1"; FAIL=1 }

print -r -- "== 1/5 构建 =="
if ./build.sh >/tmp/claued-verify-build.log 2>&1; then
  ok "build"
else
  bad "build"
  tail -20 /tmp/claued-verify-build.log
  exit 1
fi

print -r -- "== 2/5 部署目标 =="
minos=$(otool -l ClauEd.app/Contents/MacOS/ClauEd | awk '/LC_BUILD_VERSION/{f=1} f && /minos/{print $2; exit}')
if [ "$minos" = "13.0" ]; then
  ok "minos $minos"
else
  bad "minos ${minos:-unknown}（期望 13.0）"
fi

print -r -- "== 3/5 离屏探针 =="
probe=$(swift tools/wk_probe.swift fork/splash.html 2>&1)
expected_audio=$(find assets -maxdepth 1 -name '*.mp3' 2>/dev/null | wc -l | tr -d ' ')
if print -r -- "$probe" | grep -q '"marks":12' && print -r -- "$probe" | grep -q "\"audioKeys\":$expected_audio"; then
  ok "wk_probe（12 条星芒 / $expected_audio 个本地音频）"
else
  bad "wk_probe"
  print -r -- "$probe" | tail -10
fi

print -r -- "== 4/5 配置一致性（DEFAULTS / html / example / main.swift）=="
python3 - "$ROOT" <<'PY'
import re, sys, json, pathlib
root = pathlib.Path(sys.argv[1])
js = (root / 'fork/splash.js').read_text()
html = (root / 'fork/splash.html').read_text()

def parse(body, pat):
    d = {}
    for line in body.split('\n'):
        m = re.match(pat, line)
        if m:
            d[m.group(1)] = m.group(2).strip().rstrip(',')
    return d

a = parse(re.search(r'var DEFAULTS = \{(.*?)\n  \}', js, re.S).group(1),
          r"\s*(\w+):\s*(.+?),?\s*(//.*)?$")
b = parse(re.search(r'window\.__CLAUDE_DEFAULT_CFG__ = \{(.*?)\n  \}', html, re.S).group(1),
          r"\s*(\w+):\s*(.+?),?\s*$")

def norm(v):
    try:
        return float(v)
    except ValueError:
        return v.strip("'\"")

errs = []
diff = [(k, a[k], b[k]) for k in sorted(set(a) & set(b)) if norm(a[k]) != norm(b[k])]
only_a, only_b = sorted(set(a) - set(b)), sorted(set(b) - set(a))
if diff:
    errs.append('DEFAULTS 值不一致: %r' % (diff,))
if only_a or only_b:
    errs.append('键不一致 js-only=%r html-only=%r' % (only_a, only_b))

ex = set(json.loads((root / 'extras/config.example.json').read_text()).keys())
sw = (root / 'src/main.swift').read_text()
keys = set(re.findall(r'obj\["(\w+)"\]', sw)) - {
    'lastShown', 'userThemeMode',  # state.json / Claude config
    'theme',  # 注入时由 themeOverride / Claude / 系统外观解析得到，不是 config.json 输入键
    'model', 'effort', 'lastFocusedAt', 'isArchived',  # Code 会话元数据，不是启动器配置
}
missing = sorted(keys - ex)
if missing:
    errs.append('config.example.json 缺键: %r' % (missing,))

block = re.search(r'func defaultConfigObject\(\).*?return \[(.*?)\n    \]\n\}', sw, re.S)
default_keys = set(re.findall(r'^\s*"(\w+)":', block.group(1), re.M)) if block else set()
if default_keys != ex:
    errs.append('Swift 默认配置与 example 键不一致: swift-only=%r example-only=%r' % (
        sorted(default_keys - ex), sorted(ex - default_keys)))

print('\n'.join(errs) if errs else 'CONFIG_OK')
sys.exit(1 if errs else 0)
PY
if [ $? -eq 0 ]; then ok "config sync"; else bad "config sync"; fi

print -r -- "== 5/5 文档链接与品牌残留 =="
python3 - "$ROOT" <<'PY'
import re, sys, pathlib, urllib.parse
root = pathlib.Path(sys.argv[1])
bad = []

for doc in root.rglob('*.md'):
    rel = doc.relative_to(root).as_posix()
    if '移植调研-原始报告' in rel or '.backup-' in rel or rel.startswith('dist/'):
        continue
    text = doc.read_text(errors='ignore')
    text = re.sub(r'```.*?```', '', text, flags=re.S)
    for m in re.finditer(r'\[[^\]]*\]\(([^)]+)\)', text):
        link = m.group(1)
        if link.startswith(('http', '#', 'mailto:')):
            continue
        path = urllib.parse.unquote(link.split('#')[0])
        if path and not (doc.parent / path).exists():
            bad.append('%s -> %s' % (rel, link))

for sub in ('fork', 'src', 'tools', 'resources'):
    for path in (root / sub).rglob('*'):
        if path.name == 'verify.sh':
            continue  # 本脚本的检查清单本身就包含这些词
        if path.is_file() and path.suffix in {'.js', '.css', '.swift', '.sh', '.py', '.html'}:
            text = path.read_text(errors='ignore')
            for brand in ('DeepSeek', 'DEEPSEEK', '深度求索', '豪叔', 'Edward'):
                if brand in text:
                    bad.append('%s 含旧品牌 %s' % (path.relative_to(root), brand))

print('\n'.join(bad) if bad else 'DOCS_OK')
sys.exit(1 if bad else 0)
PY
if [ $? -eq 0 ]; then ok "docs & branding"; else bad "docs & branding"; fi

echo
if [ "$FAIL" = 0 ]; then
  print -r -- "✅ 全部检查通过"
else
  print -r -- "❌ 有检查未通过"
fi
exit "$FAIL"
