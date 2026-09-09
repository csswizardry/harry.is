#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

post_arg=''
source_arg=''
name_override=''
dry_run=0
force=0
work_dir=''
commit_started=0
commit_finished=0
post_path=''
backup_post=''
target_small=''
target_medium=''
target_main=''
backup_small=''
backup_medium=''
backup_main=''

usage() {
  cat <<'EOF'
Prepare responsive hero assets and wire them into a Jekyll post.

Usage:
  prepare-hero-assets.sh --post POST --source IMAGE [OPTIONS]

Required:
  --post PATH       A Markdown file below _posts/ or _drafts/.
  --source PATH     A sips-readable, 16:9 image of at least 1920x1080px.

Options:
  --name STEM       Override the inferred, lowercase filename stem.
  --dry-run         Validate and show the planned changes without writing files.
  --force           Replace existing generated assets.
  -h, --help        Show this help.

Outputs:
  STEM-small.jpg     960x540
  STEM-medium.jpg    1440x810
  STEM-main.jpg      1920x1080

The 16x9 JPEG placeholder is ImageOptim-processed, Base64-encoded, and stored
in the post front matter. An external source image is never modified or removed.
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

trash_if_present() {
  if [ -e "$1" ]; then
    trash "$1" >/dev/null 2>&1 || true
  fi
}

restore_target() {
  local target="$1"
  local backup="$2"

  if [ -n "$backup" ] && [ -e "$backup" ]; then
    cp -p "$backup" "$target"
  else
    trash_if_present "$target"
  fi
}

cleanup() {
  local exit_status=$?

  if [ "$commit_started" -eq 1 ] && [ "$commit_finished" -eq 0 ]; then
    restore_target "$target_small" "$backup_small"
    restore_target "$target_medium" "$backup_medium"
    restore_target "$target_main" "$backup_main"
    if [ -n "$backup_post" ] && [ -e "$backup_post" ]; then
      cp -p "$backup_post" "$post_path"
    fi
    printf 'Rolled back incomplete changes.\n' >&2
  fi

  if [ -n "$work_dir" ] && [ -e "$work_dir" ]; then
    trash_if_present "$work_dir"
  fi

  exit "$exit_status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

absolute_path() {
  local input="$1"
  local directory
  local filename

  directory=$(dirname "$input")
  filename=$(basename "$input")
  (cd "$directory" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$filename")
}

front_matter_value() {
  local key="$1"
  local file="$2"

  awk -v key="$key" '
    NR == 1 {
      if ($0 != "---") exit 2
      in_front_matter = 1
      next
    }
    in_front_matter && $0 == "---" { exit }
    in_front_matter && index($0, key ":") == 1 {
      sub("^[^:]+:[[:space:]]*", "")
      gsub(/^['\''\"]|['\''\"]$/, "")
      print
      exit
    }
  ' "$file"
}

image_property() {
  local property="$1"
  local file="$2"

  sips -g "$property" "$file" 2>/dev/null |
    awk -v property="$property" '$1 == property ":" { print $2; exit }'
}

validate_generated_image() {
  local file="$1"
  local expected_width="$2"
  local expected_height="$3"
  local width
  local height
  local format

  width=$(image_property pixelWidth "$file")
  height=$(image_property pixelHeight "$file")
  format=$(image_property format "$file")

  [ "$width" = "$expected_width" ] || fail "$(basename "$file") is ${width:-unknown}px wide; expected ${expected_width}px."
  [ "$height" = "$expected_height" ] || fail "$(basename "$file") is ${height:-unknown}px high; expected ${expected_height}px."
  [ "$format" = 'jpeg' ] || fail "$(basename "$file") is ${format:-an unknown format}; expected JPEG."
}

stage_post() {
  local input="$1"
  local output="$2"
  local main_url="$3"
  local placeholder="$4"
  local has_responsive=0

  if [ -n "$(front_matter_value hero_responsive "$input")" ]; then
    has_responsive=1
  fi

  awk \
    -v main_url="$main_url" \
    -v placeholder="$placeholder" \
    -v has_responsive="$has_responsive" '
    NR == 1 {
      if ($0 != "---") exit 10
      in_front_matter = 1
      print
      next
    }

    in_front_matter && $0 == "---" {
      if (!saw_main) {
        print "main: " main_url
        print "hero_responsive: true"
        saw_responsive = 1
      } else if (!saw_responsive) {
        print "hero_responsive: true"
      }
      if (!saw_placeholder) print "placeholder: '\''" placeholder "'\''"
      in_front_matter = 0
      closed_front_matter = 1
      print
      next
    }

    in_front_matter && /^main:[[:space:]]*/ {
      print "main: " main_url
      saw_main = 1
      if (!has_responsive) {
        print "hero_responsive: true"
        saw_responsive = 1
      }
      next
    }

    in_front_matter && /^hero_responsive:[[:space:]]*/ {
      print "hero_responsive: true"
      saw_responsive = 1
      next
    }

    in_front_matter && /^placeholder:[[:space:]]*/ {
      print "placeholder: '\''" placeholder "'\''"
      saw_placeholder = 1
      next
    }

    { print }

    END {
      if (!closed_front_matter) exit 11
    }
  ' "$input" > "$output" || fail "Could not update the front matter in ${input}."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --post)
      [ "$#" -ge 2 ] || fail '--post requires a path.'
      post_arg="$2"
      shift 2
      ;;
    --source)
      [ "$#" -ge 2 ] || fail '--source requires a path.'
      source_arg="$2"
      shift 2
      ;;
    --name)
      [ "$#" -ge 2 ] || fail '--name requires a filename stem.'
      name_override="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --force)
      force=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown option: $1"
      ;;
  esac
done

[ "$(id -u)" -ne 0 ] || fail 'Do not run this script as root.'
[ -n "$post_arg" ] || fail '--post is required.'
[ -n "$source_arg" ] || fail '--source is required.'

for command in awk base64 defaults imageoptim sips stat trash; do
  command -v "$command" >/dev/null 2>&1 || fail "Required command not found: ${command}"
done

post_path=$(absolute_path "$post_arg") || fail "Post directory does not exist: $(dirname "$post_arg")"
source_path=$(absolute_path "$source_arg") || fail "Source directory does not exist: $(dirname "$source_arg")"

[ -f "$post_path" ] || fail "Post not found: ${post_path}"
[ -f "$source_path" ] || fail "Source image not found: ${source_path}"

case "$post_path" in
  "$REPO_ROOT"/_posts/*.md|"$REPO_ROOT"/_drafts/*.md) ;;
  *) fail 'The post must be a Markdown file below this repository’s _posts/ or _drafts/ directory.' ;;
esac

[ "$(front_matter_value layout "$post_path")" = 'masthead' ] || fail 'The post must use layout: masthead.'

source_width=$(image_property pixelWidth "$source_path")
source_height=$(image_property pixelHeight "$source_path")
[ -n "$source_width" ] && [ -n "$source_height" ] || fail 'sips could not read the source image dimensions.'

[ $((source_width * 9)) -eq $((source_height * 16)) ] ||
  fail "Source is ${source_width}x${source_height}; provide an exact 16:9 crop."
[ "$source_width" -ge 1920 ] && [ "$source_height" -ge 1080 ] ||
  fail "Source is ${source_width}x${source_height}; provide at least 1920x1080px."

lossy_enabled=$(defaults read net.pornel.ImageOptim LossyEnabled 2>/dev/null || true)
imageoptim_quality=$(defaults read net.pornel.ImageOptim JpegOptimMaxQuality 2>/dev/null || true)
[ "$lossy_enabled" = '1' ] || fail 'Enable lossy minification in ImageOptim before running this pipeline.'
[ -n "$imageoptim_quality" ] || fail 'Could not read ImageOptim’s JPEG quality preference.'
awk -v quality="$imageoptim_quality" 'BEGIN { exit !(quality >= 79 && quality <= 81) }' ||
  fail "ImageOptim JPEG quality is ${imageoptim_quality}; set it to approximately 80 first."

current_main=$(front_matter_value main "$post_path")
if [ -n "$current_main" ]; then
  case "$current_main" in
    /img/content/*-main.jpg|/img/content/*-main.jpeg|/img/content/*-main.png) ;;
    *) fail "Existing main path does not follow the expected naming convention: ${current_main}" ;;
  esac
  destination_url_dir=$(dirname "$current_main")
  inferred_name=$(basename "$current_main")
  inferred_name=${inferred_name%-main.jpg}
  inferred_name=${inferred_name%-main.jpeg}
  inferred_name=${inferred_name%-main.png}
else
  post_filename=$(basename "$post_path")
  case "$post_filename" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) ;;
    *) fail 'The post filename must begin YYYY-MM-DD so the asset directory can be inferred.' ;;
  esac
  post_year=${post_filename%%-*}
  post_remainder=${post_filename#*-}
  post_month=${post_remainder%%-*}
  destination_url_dir="/img/content/${post_year}/${post_month}"
  inferred_name=$(basename "$source_path")
  inferred_name=${inferred_name%.*}
  inferred_name=${inferred_name%-main}
fi

asset_name=${name_override:-$inferred_name}
case "$asset_name" in
  ''|*[!a-z0-9-]*|-*|*-) fail 'The inferred name must contain lowercase letters, numbers, and internal hyphens only; use --name to override it.' ;;
esac

destination_dir="${REPO_ROOT}${destination_url_dir}"
target_small="${destination_dir}/${asset_name}-small.jpg"
target_medium="${destination_dir}/${asset_name}-medium.jpg"
target_main="${destination_dir}/${asset_name}-main.jpg"
main_url="${destination_url_dir}/${asset_name}-main.jpg"

printf 'Post: %s\n' "$post_path"
printf 'Source: %s (%sx%s)\n' "$source_path" "$source_width" "$source_height"
printf 'ImageOptim: lossy, JPEG quality %s\n' "$imageoptim_quality"
printf 'Small: %s\n' "$target_small"
printf 'Medium: %s\n' "$target_medium"
printf 'Main: %s\n' "$target_main"
printf 'Front matter main: %s\n' "$main_url"

if [ "$dry_run" -eq 1 ]; then
  printf 'Dry run complete; no files were changed.\n'
  exit 0
fi

if [ "$force" -eq 0 ]; then
  for target in "$target_small" "$target_medium" "$target_main"; do
    [ ! -e "$target" ] || fail "Output already exists: ${target}. Re-run with --force to replace it."
  done
fi

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/harry-is-hero.XXXXXX")
generated_small="${work_dir}/${asset_name}-small.jpg"
generated_medium="${work_dir}/${asset_name}-medium.jpg"
generated_main="${work_dir}/${asset_name}-main.jpg"
generated_placeholder="${work_dir}/${asset_name}-placeholder.jpg"
staged_post="${work_dir}/$(basename "$post_path")"

sips -s format jpeg -s formatOptions best --resampleHeightWidth 540 960 "$source_path" --out "$generated_small" >/dev/null
sips -s format jpeg -s formatOptions best --resampleHeightWidth 810 1440 "$source_path" --out "$generated_medium" >/dev/null
sips -s format jpeg -s formatOptions best --resampleHeightWidth 1080 1920 "$source_path" --out "$generated_main" >/dev/null
sips -s format jpeg -s formatOptions best --resampleHeightWidth 9 16 "$source_path" --out "$generated_placeholder" >/dev/null

imageoptim --no-color "$generated_small" "$generated_medium" "$generated_main" "$generated_placeholder"

validate_generated_image "$generated_small" 960 540
validate_generated_image "$generated_medium" 1440 810
validate_generated_image "$generated_main" 1920 1080
validate_generated_image "$generated_placeholder" 16 9

placeholder_base64=$(base64 < "$generated_placeholder" | tr -d '\r\n')
[ -n "$placeholder_base64" ] || fail 'The Base64 placeholder was empty.'

stage_post "$post_path" "$staged_post" "$main_url" "$placeholder_base64"
[ "$(front_matter_value main "$staged_post")" = "$main_url" ] || fail 'Staged main front matter did not validate.'
[ "$(front_matter_value hero_responsive "$staged_post")" = 'true' ] || fail 'Staged responsive marker did not validate.'
[ "$(front_matter_value placeholder "$staged_post")" = "$placeholder_base64" ] || fail 'Staged placeholder front matter did not validate.'

mkdir -p "$destination_dir"
backup_dir="${work_dir}/backups"
mkdir -p "$backup_dir"

if [ -e "$target_small" ]; then backup_small="${backup_dir}/small.jpg"; cp -p "$target_small" "$backup_small"; fi
if [ -e "$target_medium" ]; then backup_medium="${backup_dir}/medium.jpg"; cp -p "$target_medium" "$backup_medium"; fi
if [ -e "$target_main" ]; then backup_main="${backup_dir}/main.jpg"; cp -p "$target_main" "$backup_main"; fi
backup_post="${backup_dir}/post.md"
cp -p "$post_path" "$backup_post"

commit_started=1
cp -p "$generated_small" "$target_small"
cp -p "$generated_medium" "$target_medium"
cp -p "$generated_main" "$target_main"
cp -p "$staged_post" "$post_path"
commit_finished=1

printf 'Created responsive hero assets:\n'
for target in "$target_small" "$target_medium" "$target_main"; do
  printf '  %8s bytes  %s\n' "$(stat -f '%z' "$target")" "$target"
done
printf 'Updated front matter: %s\n' "$post_path"
