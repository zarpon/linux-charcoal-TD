#!/usr/bin/env bash
set -Eeuo pipefail

curl --fail --location --retry 4 --retry-all-errors \
  https://raw.githubusercontent.com/firelzrd/poc-selector/f2e9d6027ec8a9167365acd828016da9c8bd28e1/patches/stable/0001-6.18.3-poc-selector-v2.6.1r2.patch \
  -o 6.16-poc-selector-v2.6.1r2.patch

test -s 6.16-poc-selector-v2.6.1r2.patch
grep -Fq 'Subject: [PATCH] 6.18.3-poc-selector-v2.6.1r2' 6.16-poc-selector-v2.6.1r2.patch
grep -Fq 'Andrea Righi, Mario Roy, and Eric Naim' 6.16-poc-selector-v2.6.1r2.patch

python3 - <<'PY'
import json
from pathlib import Path

manifest_path = Path('automation/patch-sources.json')
manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
by_name = {item['name']: item for item in manifest['components']}
versions = {
    'zram_ir': '1.2',
    'adios': '3.2.0',
    'bore': '6.8.0-rc1',
    'poc_selector': '2.6.1r2',
    'nap': '0.5.0',
}
for name, version in versions.items():
    by_name[name]['local_port_project_version'] = version
by_name['poc_selector']['local_port'] = '6.16-poc-selector-v2.6.1r2.patch'
by_name['bore_sched_ext_coexistence']['local_port_upstream_sha256'] = (
    'cdf138cdb94fcb4e2988bd7d2873a51522fdb7212ec314fde202facaf8210b5c'
)
manifest_path.write_text(
    json.dumps(manifest, indent=2, sort_keys=False) + '\n', encoding='utf-8'
)

workflow_path = Path('.github/workflows/push.yml')
workflow = workflow_path.read_text(encoding='utf-8')
old_compile = (
    '          python3 -m py_compile automation/resolve-latest-patches.py '
    'automation/finalize-pkgbuild-checksums.py\n'
)
new_compile = (
    '          python3 -m py_compile automation/resolve-latest-patches.py '
    'automation/validate-patch-lock.py '
    'automation/finalize-pkgbuild-checksums.py\n'
)
if old_compile in workflow:
    workflow = workflow.replace(old_compile, new_compile, 1)
elif new_compile not in workflow:
    raise SystemExit('push workflow compile anchor changed')
old_resolve = (
    '          python3 automation/resolve-latest-patches.py --write '
    '| tee logs/resolver.log\n'
)
validation = (
    '          python3 automation/validate-patch-lock.py '
    '| tee logs/patch-lock-validation.log\n'
)
if validation not in workflow:
    if workflow.count(old_resolve) != 1:
        raise SystemExit('push workflow resolver anchor changed')
    workflow = workflow.replace(old_resolve, old_resolve + validation, 1)
workflow_path.write_text(workflow, encoding='utf-8')

docs_path = Path('PATCH-SOURCES.md')
docs = docs_path.read_text(encoding='utf-8')
old_docs = (
    '- Patches com porta local continuam consultando o upstream atual. '
    'Uma alteração no SHA-256 oficial interrompe o build até que a porta '
    'seja atualizada e validada.\n'
)
new_docs = (
    '- Patches com porta local continuam consultando o upstream atual. '
    'Uma alteração de versão ou do SHA-256 aprovado interrompe o build '
    'até que a porta seja atualizada e validada.\n'
)
if old_docs in docs:
    docs = docs.replace(old_docs, new_docs, 1)
elif new_docs not in docs:
    raise SystemExit('documentation anchor changed')
docs_path.write_text(docs, encoding='utf-8')
PY

python3 -m py_compile \
  automation/resolve-latest-patches.py \
  automation/validate-patch-lock.py \
  tests/test_patch_source_policy.py \
  tests/test_patch_lock_validation.py
python3 -m unittest discover -s tests -p 'test_patch*.py' -v
bash -n PKGBUILD
