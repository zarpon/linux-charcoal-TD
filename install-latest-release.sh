#!/usr/bin/env bash
# Download and install the packages from the latest Charcoal GitHub Release.
set -Eeuo pipefail

umask 022

readonly DEFAULT_REPOSITORY="zarpon/linux-charcoal-TD"
repository="${CHARCOAL_REPOSITORY:-$DEFAULT_REPOSITORY}"
release_api="${CHARCOAL_RELEASE_API:-https://api.github.com/repos/${repository}/releases/latest}"
github_token="${GITHUB_TOKEN:-${GH_TOKEN:-}}"

workdir=""
readonly_was_enabled=0

die() {
  echo "charcoal-installer: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "comando obrigatório não encontrado: $1"
}

cleanup() {
  local status=$?
  trap - EXIT

  if (( readonly_was_enabled )); then
    echo "Restaurando o modo somente-leitura do SteamOS..."
    if ! steamos-readonly enable; then
      echo "charcoal-installer: não foi possível reativar o modo somente-leitura" >&2
      status=1
    fi
  fi

  if [[ -n "$workdir" ]]; then
    rm -rf -- "$workdir"
  fi

  exit "$status"
}

download() {
  local url="$1"
  local destination="$2"
  local accept="$3"
  local -a headers=(
    --header "Accept: ${accept}"
    --header "X-GitHub-Api-Version: 2022-11-28"
  )

  if [[ -n "$github_token" ]]; then
    headers+=(--header "Authorization: Bearer ${github_token}")
  fi

  curl --fail --silent --show-error --location --retry 3 --connect-timeout 15 \
    --max-time 300 --proto '=https' --tlsv1.2 "${headers[@]}" \
    --output "$destination" -- "$url"
}

if (( EUID != 0 )); then
  die "execute com sudo, por exemplo: sudo bash install-latest-release.sh"
fi

for command in curl python3 sha256sum pacman steamos-readonly uname mktemp find sort; do
  require_command "$command"
done

[[ "$(uname -m)" == "x86_64" ]] || die "esta Release fornece pacotes x86_64"

trap cleanup EXIT
workdir="$(mktemp -d "${TMPDIR:-/tmp}/charcoal-install.XXXXXX")"
release_json="$workdir/release.json"
manifest="$workdir/release-assets.tsv"
package_dir="$workdir/packages"
mkdir -p -- "$package_dir"

if ! download "$release_api" "$release_json" "application/vnd.github+json"; then
  die "não foi possível consultar a última Release de ${repository}"
fi

if ! python3 - "$release_json" >"$manifest" <<'PY'
import json
import os
import re
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    release = json.load(stream)

if not isinstance(release, dict):
    raise SystemExit("a resposta da API não é uma Release válida")
if release.get("message"):
    raise SystemExit(f"a API do GitHub recusou a consulta: {release['message']}")

tag = release.get("tag_name") or release.get("name")
if not isinstance(tag, str) or not tag or any(char in tag for char in "\r\n\t"):
    raise SystemExit("a Release não possui uma identificação válida")

assets = release.get("assets")
if not isinstance(assets, list):
    raise SystemExit("a Release não possui assets válidos")

def asset_url(item):
    name = item.get("name")
    url = item.get("browser_download_url") or item.get("url")
    if not isinstance(name, str) or not isinstance(url, str) or not url:
        raise SystemExit("um asset da Release não possui nome ou URL válidos")
    if name != os.path.basename(name) or any(char in name for char in "\\/\r\n\t"):
        raise SystemExit(f"nome de asset inválido: {name!r}")
    if any(char in url for char in "\r\n\t"):
        raise SystemExit("URL de asset inválida")
    return name, url

zip_pattern = re.compile(r"linux-charcoal-[A-Za-z0-9][A-Za-z0-9._+~-]*\.zip\Z")
zip_assets = []
checksum_assets = []
for item in assets:
    name, url = asset_url(item)
    if zip_pattern.fullmatch(name):
        zip_assets.append((name, url))
    elif name == "RELEASE-ZIP-SHA256SUM":
        checksum_assets.append((name, url))

if len(zip_assets) != 1:
    raise SystemExit(
        f"esperado exatamente um ZIP do Charcoal na última Release; encontrados {len(zip_assets)}"
    )
if len(checksum_assets) != 1:
    raise SystemExit(
        "a última Release não possui exatamente um asset RELEASE-ZIP-SHA256SUM"
    )

zip_name, zip_url = zip_assets[0]
checksum_name, checksum_url = checksum_assets[0]
print("\t".join((tag, zip_name, zip_url, checksum_name, checksum_url)))
PY
then
  die "não foi possível validar os assets da última Release"
fi

IFS=$'\t' read -r release_tag zip_name zip_url checksum_name checksum_url <"$manifest"
[[ -n "$release_tag" && -n "$zip_name" && -n "$zip_url" && -n "$checksum_name" && -n "$checksum_url" ]] \
  || die "o manifesto da Release está incompleto"

zip_path="$workdir/$zip_name"
checksum_path="$workdir/$checksum_name"

echo "Release selecionada: $release_tag"
echo "Baixando $zip_name..."
download "$zip_url" "$zip_path" "application/octet-stream" \
  || die "falha ao baixar o ZIP da Release"
echo "Baixando $checksum_name..."
download "$checksum_url" "$checksum_path" "text/plain" \
  || die "falha ao baixar o checksum da Release"

if ! python3 - "$checksum_path" "$zip_name" <<'PY'
import pathlib
import re
import sys

checksum_file = pathlib.Path(sys.argv[1])
expected_name = sys.argv[2]
lines = checksum_file.read_text(encoding="utf-8").splitlines()
line_pattern = re.compile(r"([0-9a-fA-F]{64}) [ *]([^/\\\r\n]+)\Z")

if len(lines) != 1:
    raise SystemExit("o checksum do ZIP deve conter exatamente uma linha")
match = line_pattern.fullmatch(lines[0])
if not match or match.group(2) != expected_name:
    raise SystemExit("o checksum do ZIP não corresponde ao asset selecionado")
PY
then
  die "o arquivo de checksum do ZIP é inválido"
fi

(
  cd -- "$workdir"
  sha256sum --check --strict --status "$checksum_name"
) || die "o SHA-256 do ZIP da Release não confere"

if ! python3 - "$zip_path" "$package_dir" <<'PY'
import os
import re
import shutil
import sys
import zipfile

archive_path, destination = sys.argv[1:]
package_pattern = re.compile(
    r"linux-charcoal-[A-Za-z0-9][A-Za-z0-9._+~-]*-x86_64\.pkg\.tar\.zst\Z"
)

try:
    archive = zipfile.ZipFile(archive_path)
except (OSError, zipfile.BadZipFile) as error:
    raise SystemExit(f"ZIP inválido: {error}")

with archive:
    members = archive.infolist()
    names = [member.filename for member in members]
    if len(names) != len(set(names)):
        raise SystemExit("o ZIP contém entradas duplicadas")

    selected = {}
    for member in members:
        name = member.filename
        if name == "SHA256SUMS" or package_pattern.fullmatch(name):
            if os.path.basename(name) != name:
                raise SystemExit(f"entrada ZIP com caminho inválido: {name!r}")
            selected[name] = member

    if "SHA256SUMS" not in selected:
        raise SystemExit("o ZIP não contém SHA256SUMS")

    packages = sorted(name for name in selected if package_pattern.fullmatch(name))
    if not packages:
        raise SystemExit("o ZIP não contém pacotes Charcoal x86_64")

    for name in ["SHA256SUMS", *packages]:
        target = os.path.join(destination, name)
        with archive.open(selected[name]) as source, open(target, "xb") as output:
            shutil.copyfileobj(source, output)
PY
then
  die "não foi possível extrair os pacotes da Release"
fi

mapfile -t packages < <(find "$package_dir" -maxdepth 1 -type f \
  -name 'linux-charcoal-*-x86_64.pkg.tar.zst' -print | sort)
((${#packages[@]} > 0)) || die "nenhum pacote Charcoal foi extraído da Release"

if ! python3 - "$package_dir/SHA256SUMS" "${packages[@]}" <<'PY'
import pathlib
import re
import sys

checksum_file = pathlib.Path(sys.argv[1])
expected = {pathlib.Path(path).name for path in sys.argv[2:]}
seen = {}
line_pattern = re.compile(r"([0-9a-fA-F]{64}) [ *]([^/\\\r\n]+)\Z")

for number, raw_line in enumerate(checksum_file.read_text(encoding="utf-8").splitlines(), 1):
    match = line_pattern.fullmatch(raw_line)
    if not match:
        raise SystemExit(f"linha inválida em SHA256SUMS: {number}")
    digest, name = match.groups()
    if name in seen:
        raise SystemExit(f"checksum duplicado para {name}")
    seen[name] = digest.lower()

if set(seen) != expected:
    missing = sorted(expected - set(seen))
    unexpected = sorted(set(seen) - expected)
    raise SystemExit(
        f"SHA256SUMS não corresponde aos pacotes extraídos; faltando={missing}, extras={unexpected}"
    )
PY
then
  die "SHA256SUMS não corresponde aos pacotes da Release"
fi

(
  cd -- "$package_dir"
  sha256sum --check --strict --status SHA256SUMS
) || die "o SHA-256 de um ou mais pacotes não confere"

readonly_status="$(steamos-readonly status 2>&1 || true)"
case "${readonly_status,,}" in
  *enabled*)
    readonly_was_enabled=1
    echo "Desativando temporariamente o modo somente-leitura do SteamOS..."
    steamos-readonly disable || die "não foi possível desativar o modo somente-leitura"
    ;;
  *disabled*)
    ;;
  *)
    die "não foi possível determinar o estado de steamos-readonly"
    ;;
esac

echo "Instalando ${#packages[@]} pacote(s) da Release..."
pacman -U --needed --noconfirm -- "${packages[@]}"

echo "Instalação concluída. Reinicie e confirme com: uname -r"
