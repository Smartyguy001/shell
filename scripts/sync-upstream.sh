#!/usr/bin/env bash
set -euo pipefail

upstream="https://github.com/caelestia-dots/shell"
remote="origin"
no_push=0
skip_rebase=0

usage() {
    cat <<'EOF'
Usage: scripts/sync-upstream.sh [--no-push] [--skip-rebase]
       [--upstream URL] [--remote NAME]
EOF
}

while (($#)); do
    case "$1" in
        --no-push)
            no_push=1
            ;;
        --skip-rebase)
            skip_rebase=1
            ;;
        --upstream)
            (($# >= 2)) || { usage >&2; exit 2; }
            upstream="$2"
            shift
            ;;
        --remote)
            (($# >= 2)) || { usage >&2; exit 2; }
            remote="$2"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

die() {
    echo "sync-upstream: $*" >&2
    exit 1
}

start_branch="$(git symbolic-ref --quiet --short HEAD || true)"
[[ -n "$start_branch" ]] || die "must start on a branch"
[[ -f patches.list ]] || die "patches.list not found"

mapfile -t patch_lines < <(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' patches.list)
declare -a branches=()
declare -a prs=()
declare -a recorded_heads=()
declare -a dependencies=()

for line in "${patch_lines[@]}"; do
    read -r branch pr recorded_head note <<< "$line"
    [[ -n "${branch:-}" && -n "${pr:-}" && -n "${recorded_head:-}" ]] ||
        die "invalid patches.list line: $line"
    branches+=("$branch")
    prs+=("$pr")
    recorded_heads+=("$recorded_head")
    dependency="main"
    for token in $note; do
        if [[ "$token" == depends:* ]]; then
            dependency="${token#depends:}"
        fi
    done
    dependencies+=("$dependency")
done

git fetch --force "$upstream" main:refs/upstream/main
git switch main

local_commits="$(git rev-list refs/upstream/main..main)"
if [[ -n "$local_commits" ]]; then
    echo "main has local commits not in upstream:" >&2
    git log --oneline refs/upstream/main..main >&2
    exit 1
fi

git merge --ff-only refs/upstream/main
if (( ! no_push )); then
    git push "$remote" main
fi

git config rerere.enabled true

if (( ! skip_rebase )); then
    for i in "${!branches[@]}"; do
        branch="${branches[$i]}"
        base="${dependencies[$i]}"
        if [[ "$base" != "main" ]]; then
            found=0
            for prior in "${branches[@]:0:i}"; do
                [[ "$prior" == "$base" ]] && found=1
            done
            (( found )) || die "dependency $base for $branch must appear earlier in patches.list"
        fi
        git rebase "$base" "$branch" || {
            echo "CONFLICT in $branch — resolve, \`git rebase --continue\`, rerun with --skip-rebase" >&2
            exit 1
        }
        if (( ! no_push )); then
            git push --force-with-lease "$remote" "$branch"
        fi
    done
else
    echo "Skipping patch rebases (--skip-rebase)."
fi

git checkout -B live main
for branch in "${branches[@]}"; do
    if ! git merge --no-ff --no-edit "$branch"; then
        git merge --abort || true
        echo "CONFLICT while rebuilding live from $branch" >&2
        exit 1
    fi
done
if (( ! no_push )); then
    git push --force-with-lease "$remote" live
fi

if [[ -f scripts/qml-lint-conventions.py ]]; then
    if ! python3 scripts/qml-lint-conventions.py; then
        echo "Warning: QML lint conventions reported issues." >&2
    fi
fi

if command -v gh >/dev/null 2>&1; then
    printf '%-34s %-5s %-10s %s\n' "branch" "PR" "state" "status"
    for i in "${!branches[@]}"; do
        branch="${branches[$i]}"
        pr="${prs[$i]}"
        recorded_head="${recorded_heads[$i]}"
        [[ "$pr" != "-" ]] || continue

        if ! response="$(gh api "repos/caelestia-dots/shell/pulls/$pr" --jq '[.state, .merged, .head.sha] | @tsv')"; then
            echo "Could not query PR $pr for $branch" >&2
            continue
        fi
        IFS=$'\t' read -r state merged current_head <<< "$response"
        if [[ "$merged" == "true" ]]; then
            status="MERGED → delete patch branch"
        elif [[ "$recorded_head" != "-" && "$recorded_head" != "$current_head" ]]; then
            status="NEW COMMITS (recorded $recorded_head, now $current_head) → review diff: git fetch $upstream pull/$pr/head && git diff $recorded_head $current_head"
        else
            status="unchanged"
        fi
        printf '%-34s %-5s %-10s %s\n' "$branch" "$pr" "$state" "$status"
    done
fi

git switch "$start_branch"
