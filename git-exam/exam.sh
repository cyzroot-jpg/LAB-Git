#!/usr/bin/env bash
# ===================== git-exam toolkit =====================
# 一套“Git 实战考试”环境，覆盖真实开发中常见的提交/合并/推送问题。
# 用法见 README.md 或执行：  bash exam.sh help
# ============================================================
set -u

# ---------- 路径与全局 ----------
EXAM_HOME="${EXAM_HOME:-$PWD/.exam-work}"
REMOTE="$EXAM_HOME/remote.git"
REPO="$EXAM_HOME/repo"

# ---------- 颜色 ----------
if [ -t 1 ]; then
  R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; B=$'\033[36m'; N=$'\033[0m'; BOLD=$'\033[1m'
else
  R=; G=; Y=; B=; N=; BOLD=
fi

# ---------- 基础封装 ----------
g()  { git -C "$REPO" "$@"; }
c()  { g add -A >/dev/null 2>&1; g commit -qm "$1"; }
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s\n' "${G}$*${N}"; }
warn() { printf '%s\n' "${Y}$*${N}"; }
err()  { printf '%s\n' "${R}$*${N}"; }

has_markers() {
  [ -f "$REPO/$1" ] && grep -q -E '^(<<<<<<<|=======|>>>>>>>)' "$REPO/$1" 2>/dev/null
}
in_merge()   { [ -f "$REPO/.git/MERGE_HEAD" ]; }
in_rebase()  { [ -d "$REPO/.git/rebase-merge" ] || [ -d "$REPO/.git/rebase-apply" ]; }
tree_of()    { g rev-parse "$1^{tree}"; }
tree_eq()    { [ "$(tree_of "$1")" = "$(tree_of "$2")" ]; }
parent_count(){ g rev-list --parents -n1 "$1" | awk '{print NF-1}'; }

# ---------- 初始化练习仓库 ----------
cmd_init() {
  rm -rf "$EXAM_HOME"
  mkdir -p "$EXAM_HOME"
  git init -q --bare -b main "$REMOTE"
  git clone -q "$REMOTE" "$REPO" 2>/dev/null
  g config user.name "exam"
  g config user.email "exam@example.com"
  g config core.autocrlf false
  g config advice.detachedHead false
  g config pull.rebase false

  printf 'A\n' > "$REPO/a.txt"
  printf '# Exam Repo\n' > "$REPO/README.md"
  g add -A >/dev/null; g commit -qm "init"

  printf 'B\n' > "$REPO/b.txt"
  printf 'line1\nmiddle\nline3\n' > "$REPO/shared.txt"
  printf 'keep\n' > "$REPO/keep.txt"
  g add -A >/dev/null; g commit -qm "add b, shared and keep"

  g tag base
  g push -q origin main
  ok "练习环境已创建：$EXAM_HOME"
  say  "  裸远程(模拟 GitHub): $REMOTE"
  say  "  练习仓库          : $REPO"
}

# ---------- 每题开始前重置练习仓库（隔离） ----------
fresh() {
  g rebase --abort >/dev/null 2>&1 || true
  g merge --abort >/dev/null 2>&1 || true
  g cherry-pick --abort >/dev/null 2>&1 || true
  g revert --abort >/dev/null 2>&1 || true
  g checkout -qf main >/dev/null 2>&1 || true
  g reset -q --hard base >/dev/null 2>&1 || true
  # 删除除 main 外的本地分支
  g for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null | while IFS= read -r b; do
    [ "$b" = main ] || g branch -qD "$b" >/dev/null 2>&1 || true
  done
  g clean -qfdx -e .gitignore-check >/dev/null 2>&1 || g clean -qfdx >/dev/null 2>&1 || true
  g stash clear >/dev/null 2>&1 || true
  # 删除远程上除 main 外的分支
  g ls-remote --heads origin 2>/dev/null | awk '{print $2}' | sed 's#refs/heads/##' | while IFS= read -r rb; do
    [ -z "$rb" ] || [ "$rb" = main ] || g push -q origin --delete "$rb" >/dev/null 2>&1 || true
  done
  # 把远程 main 强制恢复为 base
  g push -qf origin base:main >/dev/null 2>&1 || true
  g fetch -q origin >/dev/null 2>&1 || true
  g checkout -qf main >/dev/null 2>&1 || true
  rm -f "$EXAM_HOME"/*.expected 2>/dev/null || true
}

# =====================================================================
# 题目元数据：标题 / 任务 / 提示
# =====================================================================
declare -A TITLE TASK HINT
TITLE[1]="push 被远程拒绝 (non-fast-forward)"
TASK[1]="本地 main 和远程 main 各自有新提交，发生了分叉。请把本地 main 同步并成功推送到远程，使远程 main 与本地 main 一致，且两边改动（local.txt 与 remote.txt）都保留。"
HINT[1]="push 被拒是因为远程有你没有的提交。先 git pull（或 merge origin/main）整合，再 push。"

TITLE[2]="快进合并 (fast-forward)"
TASK[2]="分支 feature 领先 main 一个提交，且 main 没有自己的新提交。请把 feature 合并进 main，要求不产生多余信息、完成后 main 指向 feature 的提交。"
HINT[2]="这种无分叉情况下 git merge feature 会自动快进。"

TITLE[3]="三方合并 (生成 merge commit)"
TASK[3]="main 和 feature 各有独立提交，已分叉。请把 feature 合并进 main，要求生成一个合并提交（merge commit），并且 main 上同时包含两边的改动。"
HINT[3]="分叉时 git merge feature 会生成带两个父提交的合并 commit。"

TITLE[4]="合并内容冲突：手动解决"
TASK[4]="main 和 feature 都改了 conflict.txt 的中间一行。请把 feature 合并进 main，并把冲突解决为如下内容（三行）：\n  top\n  resolved\n  bottom\n解决后不要残留冲突标记，并完成提交。"
HINT[4]="编辑 conflict.txt，删掉 <<<<<<< ======= >>>>>>> 标记，保留 top/resolved/bottom，然后 git add + git commit。"

TITLE[5]="冲突选边 (--ours / --theirs)"
TASK[5]="合并 feature 时 conflict.txt 发生冲突。请解决冲突：整份文件采用 feature（对方）那一版的内容。"
HINT[5]="git checkout --theirs conflict.txt 然后 git add 它，再 commit。"

TITLE[6]="修改/删除冲突 (modify/delete)"
TASK[6]="feature 删除了 docs.txt，而 main 修改了 docs.txt，合并时冲突。请解决：保留被修改后的 docs.txt（内容为 'DOCS-v2'），并完成合并。"
HINT[6]="git add docs.txt 表示“保留修改后的文件”（若工作区被删了，用 git checkout main -- docs.txt 取回）。"

TITLE[7]="双方新增同名文件 (add/add)"
TASK[7]="main 和 feature 各自新建了 new.txt 且内容不同，合并时 add/add 冲突。请解决为内容 'combined'，并完成合并。"
HINT[7]="直接把 new.txt 内容改成 combined，git add new.txt，git commit。"

TITLE[8]="二进制文件冲突"
TASK[8]="logo.bin 是二进制文件，main 和 feature 各改了一版，合并无法自动合并。请解决冲突：采用 feature 那一版（内容为 'LOGO-THEIRS-v2' 加两个二进制字节），并完成合并。"
HINT[8]="git checkout --theirs logo.bin; git add logo.bin; git commit"

TITLE[9]="撤销一次合并 (reset)"
TASK[9]="main 上已经做过一次 feature 的合并（产生了合并提交）。现在想彻底撤销这次合并，把 main 恢复到合并前的状态。目标提交已用分支 premerge 标记。"
HINT[9]="git reset --hard premerge"

TITLE[10]="用 revert 撤销一个合并提交"
TASK[10]="main 上有一个把 feature 并入的合并提交，feature 新增了 feat.txt。请用 revert 撤销这个合并提交（保留历史），使 main 上不再包含 feat.txt。"
HINT[10]="git revert -m 1 <合并提交>"

TITLE[11]="pull --rebase 避免产生 merge commit"
TASK[11]="本地 main 与远程 main 分叉。请在不产生合并提交（历史保持一条直线）的前提下同步远程改动，并成功推送，使远程与本地一致。"
HINT[11]="git pull --rebase origin main; git push origin main"

TITLE[12]="rebase 到最新的 main"
TASK[12]="feature 基于旧提交开发，main 已前进。请把 feature 变基到 main 之上，使 main 成为 feature 的祖先，且 feature 上仍是那几个提交（内容不变）。"
HINT[12]="git checkout feature; git rebase main"

TITLE[13]="rebase 冲突的解决"
TASK[13]="把 feature 变基到 main 时发生冲突（同一文件同一处被改）。请解决冲突（保留内容 'REBASED'），并完成变基（feature 最终位于 main 之上）。"
HINT[13]="解决冲突 → git add → git rebase --continue"

TITLE[14]="rebase -i 压缩提交 (squash)"
TASK[14]="feature 上有 3 个提交。请把它们压缩成 1 个提交（内容不变），使 feature 相对 base 只多出一个提交。"
HINT[14]="git rebase -i base，把后两个提交标为 squash（s）"

TITLE[15]="rebase -i 修改历史提交信息 (reword)"
TASK[15]="feature 上有 3 个提交，其中中间那个的信息是 BAD。请只把这条提交信息改成 GOOD（其它不动）。"
HINT[15]="git rebase -i base，把中间那条标为 reword（r）"

TITLE[16]="cherry-pick 单个提交"
TASK[16]="feature 上有三个提交：分别新增 x1.txt / x2.txt / x3.txt。请只把新增 x2.txt 的那条提交挑到 main 上，使 main 有 x2.txt（内容 'two'）但没有 x1.txt、x3.txt 的新增。"
HINT[16]="git checkout main; git cherry-pick <新增 x2.txt 的提交哈希>；哈希可用 git log feature 找到"

TITLE[17]="cherry-pick 冲突"
TASK[17]="feature 修改了 shared.txt，main 也改了同一处。请把 feature 修改 shared.txt 的那条提交 cherry-pick 到 main，解决冲突（保留内容 'PICKED'），并完成提交。"
HINT[17]="git cherry-pick <hash>，解决冲突后 git add + git cherry-pick --continue（或 git commit）"

TITLE[18]="提交到了错误的分支"
TASK[18]="不小心把提交 'oops' 提交到了 main（它新增了 oops.txt）。请把这个提交移动到分支 feature 上，并让 main 回到 base。"
HINT[18]="git branch feature; git reset --hard HEAD~1  (在 main 上)"

TITLE[19]="撤销最近一次未推送的提交（保留改动）"
TASK[19]="main 上多了一个提交 temp（新增 work.txt）。请撤销这个提交，但保留其改动并处于「已暂存(staged)」状态，使 main 回到 base。"
HINT[19]="git reset --soft HEAD~1"

TITLE[20]="用 revert 撤销已推送的提交"
TASK[20]="远程 main 上有一个提交把 a.txt 改成了 BAD。请用 revert 生成反向提交来撤销它，并推送到远程，使远程 a.txt 恢复为 A、且历史保留（不是强推）。"
HINT[20]="git revert <bad提交>; git push origin main"

TITLE[21]="撤回已推送的提交（reset + 强推）"
TASK[21]="远程 main 上被推送了两个坏提交 bad1、bad2。请把远程 main 强制退回到 base（改写远程历史）。"
HINT[21]="git reset --hard base; git push --force-with-lease origin main"

TITLE[22]="撤销未提交的工作区改动"
TASK[22]="你修改了 a.txt（尚未提交）。请放弃这些修改，使 a.txt 恢复原样、工作区干净。"
HINT[22]="git restore a.txt  或  git checkout -- a.txt"

TITLE[23]="取消暂存 (unstage)"
TASK[23]="你把新建的 temp.txt 加入了暂存区。请把它从暂存区移出，但保留文件在磁盘上（变为未跟踪）。"
HINT[23]="git restore --staged temp.txt  或  git reset temp.txt"

TITLE[24]="恢复被误删的文件"
TASK[24]="你把已跟踪的 keep.txt 从工作区删除了（还未提交）。请把它恢复回来。"
HINT[24]="git restore keep.txt  或  git checkout -- keep.txt"

TITLE[25]="amend 修改最近一次提交（补文件+改信息）"
TASK[25]="最近一次提交信息是 'add f'，只提交了 f.txt，但你忘了把 g.txt 一起提交。请修改这次提交：信息改为 'add f and g'，并包含 f.txt 与 g.txt（保持相对 base 只多一个提交）。"
HINT[25]="git add g.txt; git commit --amend -m 'add f and g'"

TITLE[26]="amend 后从 reflog 找回被覆盖的提交"
TASK[26]="你先做了一个提交（新增 secret.txt，内容 ORIGINAL），随后用 amend 覆盖了它，原提交变成游离对象。请把这个原始提交找回来，并新建分支 recovered 指向它（要求 recovered 里 secret.txt 内容为 ORIGINAL）。"
HINT[26]="git reflog 找到 amend 前的提交哈希，然后 git branch recovered <hash>"

TITLE[27]="从 reflog 找回 reset --hard 丢掉的提交"
TASK[27]="main 上曾有提交 precious（新增 precious.txt），但被 reset --hard 回退了，提交丢了。请把它找回，并新建分支 recovered 指向它（recovered 里要有 precious.txt）。"
HINT[27]="git reflog 找到 precious 的哈希，git branch recovered <hash>"

TITLE[28]="找回被误删的分支"
TASK[28]="分支 lost（含提交 lost.txt）被删除了。请把它恢复回来，使分支 lost 重新存在且包含 lost.txt。"
HINT[28]="git reflog 找到该提交哈希，git branch lost <hash>"

TITLE[29]="stash 暂存与恢复"
TASK[29]="你在 main 上修改了 a.txt（内容 'STASHED-A'，尚未提交）。现在需要临时去 hotfix 分支做一个提交，再去回来恢复你的改动。要求：\n  1) 用 stash 暂存你 main 上的改动；\n  2) 切到 hotfix，新建 fix.txt 并提交（信息任意）；\n  3) 切回 main；\n  4) 用 stash 恢复你的改动。\n完成后：位于 main、a.txt 仍是未提交的 'STASHED-A'、stash 列表为空、hotfix 上有 fix.txt 的提交。"
HINT[29]="git stash → git checkout hotfix → 提交 fix.txt → git checkout main → git stash pop"

TITLE[30]="stash pop 冲突"
TASK[30]="你先修改了 shared.txt 并 stash，随后 main 提交了另一处对 shared.txt 的修改，然后 pop stash 导致冲突。请解决冲突（保留内容 'STASHED'），并清理 stash（列表为空）。"
HINT[30]="解决 shared.txt 冲突 → git add → git stash drop（或 pop 已自动 drop）"

TITLE[31]="在 detached HEAD 上提交并保住成果"
TASK[31]="你处于游离头指针(detached HEAD)状态，并且已经在该状态下做了一个提交。请把这个提交用一个新分支 savepoint 保住，使其不会丢失。"
HINT[31]="git branch savepoint  或  git checkout -b savepoint"

TITLE[32]=".gitignore 对已跟踪文件不生效"
TASK[32]="log.txt 已经被 Git 跟踪，即使写入 .gitignore 也仍会被跟踪。请让 Git 停止跟踪 log.txt（从索引移除并提交该改动），同时保留磁盘上的文件；并把 log.txt 加入 .gitignore。完成后 git status 应保持干净（不再显示 log.txt）。"
HINT[32]="git rm --cached log.txt; echo 'log.txt' >> .gitignore; git add .gitignore; git commit -m '...'"

TITLE[33]="删除远程分支并 prune 本地"
TASK[33]="远程存在分支 feature-x。请删除远程的 feature-x，并清理本地对应的远程跟踪分支 origin/feature-x。"
HINT[33]="git push origin --delete feature-x; git fetch --prune（或 git remote prune origin）"

TITLE[34]="创建、推送与查看注解标签"
TASK[34]="请为 base 提交创建一个注解标签(annotated tag) v1.0，并推送到远程。"
HINT[34]="git tag -a v1.0 -m 'release 1.0' base; git push origin v1.0"

TITLE[35]="找回被 force push 覆盖的提交"
TASK[35]="远程 main 上曾有一个提交（新增 rescue.txt），后来被强制推送覆盖，远程已经没有了，但本地 reflog 里还留有它。请把它找回，并推送到远程分支 rescued。"
HINT[35]="git reflog 找到该提交哈希，git branch rescued <hash>; git push origin rescued"

declare -A FLAG
FLAG[1]=146170; FLAG[2]=984279; FLAG[3]=297462; FLAG[4]=490481; FLAG[5]=219213
FLAG[6]=684730; FLAG[7]=267172; FLAG[8]=677732; FLAG[9]=992333; FLAG[10]=476241
FLAG[11]=332937; FLAG[12]=523720; FLAG[13]=898617; FLAG[14]=220810; FLAG[15]=212176
FLAG[16]=687057; FLAG[17]=200305; FLAG[18]=871294; FLAG[19]=628673; FLAG[20]=995755
FLAG[21]=514183; FLAG[22]=472826; FLAG[23]=869230; FLAG[24]=767642; FLAG[25]=981693
FLAG[26]=695246; FLAG[27]=784112; FLAG[28]=705376; FLAG[29]=922997; FLAG[30]=760496
FLAG[31]=332662; FLAG[32]=167786; FLAG[33]=368350; FLAG[34]=374529; FLAG[35]=100359

N_QUESTIONS=35

# =====================================================================
# 起始环境搭建（每题一个 setup_N 函数）
# =====================================================================
setup_1() {
  g checkout -qf main
  printf 'local\n' > "$REPO/local.txt"; c "local change"
  g checkout -qb _tmp base
  printf 'remote\n' > "$REPO/remote.txt"; c "remote change"
  g push -q origin _tmp:main
  g checkout -qf main
  g branch -qD _tmp
}
setup_2() {
  g checkout -qb feature base
  printf 'feature\n' > "$REPO/feature.txt"; c "feature work"
  g checkout -qf main
}
setup_3() {
  g checkout -qb feature base
  printf 'feature\n' > "$REPO/feature.txt"; c "feature work"
  g checkout -qf main
  printf 'main\n' > "$REPO/main.txt"; c "main work"
}
setup_4() {
  g checkout -qb feature base
  printf 'top\nfeat-side\nbottom\n' > "$REPO/conflict.txt"; c "feature edit"
  g checkout -qf main
  printf 'top\nmain-side\nbottom\n' > "$REPO/conflict.txt"; c "main edit"
}
setup_5() {
  g checkout -qb feature base
  printf 'top\ntheirs-version\nbottom\n' > "$REPO/conflict.txt"; c "feature edit"
  g checkout -qf main
  printf 'top\nours-version\nbottom\n' > "$REPO/conflict.txt"; c "main edit"
}
setup_6() {
  printf 'DOCS-v1\n' > "$REPO/docs.txt"; g add -A >/dev/null; g commit -qm "add docs"
  g checkout -qb feature
  g rm -q docs.txt; c "delete docs"
  g checkout -qf main
  printf 'DOCS-v2\n' > "$REPO/docs.txt"; c "edit docs"
}
setup_7() {
  g checkout -qb feature base
  printf 'feature-version\n' > "$REPO/new.txt"; c "feature new"
  g checkout -qf main
  printf 'main-version\n' > "$REPO/new.txt"; c "main new"
}
setup_8() {
  g checkout -qb feature base
  printf 'LOGO-THEIRS-v2\x00\x02' > "$REPO/logo.bin"; c "theirs logo"
  g checkout -qf main
  printf 'LOGO-OURS-v1\x00\x01' > "$REPO/logo.bin"; c "ours logo"
}
setup_9() {
  g checkout -qb feature base
  printf 'feat\n' > "$REPO/feat.txt"; c "feature work"
  g checkout -qf main
  g branch premerge
  g merge -q --no-ff feature -m "merge feature"
}
setup_10() {
  g checkout -qb feature base
  printf 'feat\n' > "$REPO/feat.txt"; c "feature work"
  g checkout -qf main
  g branch premerge
  g merge -q --no-ff feature -m "merge feature"
}
setup_11() {
  g checkout -qf main
  printf 'local\n' > "$REPO/local.txt"; c "local change"
  g checkout -qb _tmp base
  printf 'remote\n' > "$REPO/remote.txt"; c "remote change"
  g push -q origin _tmp:main
  g checkout -qf main
  g branch -qD _tmp
}
setup_12() {
  g checkout -qb feature base
  printf 'f1\n' > "$REPO/f1.txt"; c "feature 1"
  printf 'f2\n' > "$REPO/f2.txt"; c "feature 2"
  g checkout -qf main
  printf 'main\n' > "$REPO/main.txt"; c "main work"
}
setup_13() {
  g checkout -qb feature base
  printf 'top\nREBASE-ME\nbottom\n' > "$REPO/rb.txt"; c "feature edit rb"
  g checkout -qf main
  printf 'top\nMAIN-SIDE\nbottom\n' > "$REPO/rb.txt"; c "main edit rb"
}
setup_14() {
  g checkout -qb feature base
  printf 'one\n' > "$REPO/one.txt"; c "commit 1"
  printf 'two\n' > "$REPO/two.txt"; c "commit 2"
  printf 'three\n' > "$REPO/three.txt"; c "commit 3"
  g checkout -qf main
}
setup_15() {
  g checkout -qb feature base
  printf 'one\n' > "$REPO/one.txt"; c "commit 1"
  printf 'two\n' > "$REPO/two.txt"; c "BAD"
  printf 'three\n' > "$REPO/three.txt"; c "commit 3"
  g checkout -qf main
}
setup_16() {
  g checkout -qb feature base
  printf 'one\n' > "$REPO/x1.txt"; c "add x1.txt"
  printf 'two\n' > "$REPO/x2.txt"; c "add x2.txt"
  printf 'three\n' > "$REPO/x3.txt"; c "add x3.txt"
  g checkout -qf main
}
setup_17() {
  g checkout -qb feature base
  printf 'top\nPICKED\nbottom\n' > "$REPO/shared.txt"; c "feature edit shared"
  g checkout -qf main
  printf 'top\nMAIN-SIDE\nbottom\n' > "$REPO/shared.txt"; c "main edit shared"
}
setup_18() {
  g checkout -qf main
  printf 'oops\n' > "$REPO/oops.txt"; c "oops"
}
setup_19() {
  g checkout -qf main
  printf 'work\n' > "$REPO/work.txt"; c "temp"
}
setup_20() {
  g checkout -qf main
  printf 'BAD\n' > "$REPO/a.txt"; c "make a bad"
  g push -q origin main
}
setup_21() {
  g checkout -qf main
  printf 'bad1\n' > "$REPO/bad1.txt"; c "bad1"
  printf 'bad2\n' > "$REPO/bad2.txt"; c "bad2"
  g push -q origin main
}
setup_22() {
  g checkout -qf main
  printf 'MODIFIED\n' > "$REPO/a.txt"
}
setup_23() {
  g checkout -qf main
  printf 'temp\n' > "$REPO/temp.txt"
  g add temp.txt >/dev/null 2>&1
}
setup_24() {
  g checkout -qf main
  rm -f "$REPO/keep.txt"
}
setup_25() {
  g checkout -qf main
  printf 'f\n' > "$REPO/f.txt"; c "add f"
  printf 'g\n' > "$REPO/g.txt"
}
setup_26() {
  g checkout -qf main
  printf 'ORIGINAL\n' > "$REPO/secret.txt"; c "add secret"
  printf 'CHANGED\n' > "$REPO/secret.txt"
  g add -A >/dev/null; g commit -q --amend -m "add secret (amended)"
}
setup_27() {
  g checkout -qf main
  printf 'precious\n' > "$REPO/precious.txt"; c "precious"
  g reset -q --hard base
}
setup_28() {
  g checkout -qb lost base
  printf 'lost\n' > "$REPO/lost.txt"; c "lost work"
  g checkout -qf main
  g branch -qD lost
}
setup_29() {
  g checkout -qb hotfix base
  printf 'HOTFIX\n' > "$REPO/a.txt"; c "hotfix"
  g checkout -qf main
  printf 'STASHED-A\n' > "$REPO/a.txt"
}
setup_30() {
  g checkout -qf main
  printf 'top\nSTASHED\nbottom\n' > "$REPO/shared.txt"
  g stash >/dev/null 2>&1
  printf 'top\nAFTER\nbottom\n' > "$REPO/shared.txt"; c "change after stash"
}
setup_31() {
  g checkout -qf main
  printf 'p\n' > "$REPO/p.txt"; c "a work commit"
  local target
  target=$(g rev-parse HEAD)
  echo "$target" > "$EXAM_HOME/q31.expected"
  g checkout -qf "$target"
}
setup_32() {
  g checkout -qf main
  printf 'log line\n' > "$REPO/log.txt"; c "add log.txt"
}
setup_33() {
  g checkout -qb feature-x base
  printf 'fx\n' > "$REPO/fx.txt"; c "feature-x work"
  g push -q origin feature-x
  g checkout -qf main
  g branch -qD feature-x
  g fetch -q origin
}
setup_34() { g checkout -qf main; }
setup_35() {
  g checkout -qf main
  printf 'rescue\n' > "$REPO/rescue.txt"; c "rescue work"
  local target
  target=$(g rev-parse HEAD)
  echo "$target" > "$EXAM_HOME/q35.expected"
  g push -q origin main
  g reset -q --hard base
  g push -qf origin main
}

# =====================================================================
# 校验（每题一个 verify_N 函数，返回 0 表示通过）
# =====================================================================
verify_1() {
  g fetch -q origin
  [ "$(g rev-parse main)" = "$(g rev-parse origin/main)" ] || return 1
  g cat-file -e main:local.txt 2>/dev/null || return 1
  g cat-file -e main:remote.txt 2>/dev/null || return 1
}
verify_2() {
  [ "$(g rev-parse main)" = "$(g rev-parse feature)" ] || return 1
  [ "$(g rev-parse main)" != "$(g rev-parse base)" ] || return 1
}
verify_3() {
  [ "$(parent_count main)" -eq 2 ] || return 1
  g cat-file -e main:feature.txt 2>/dev/null || return 1
  g cat-file -e main:main.txt 2>/dev/null || return 1
}
verify_4() {
  has_markers conflict.txt && return 1
  [ "$(g show main:conflict.txt)" = "$(printf 'top\nresolved\nbottom')" ] || return 1
}
verify_5() {
  has_markers conflict.txt && return 1
  [ "$(g show main:conflict.txt)" = "$(printf 'top\ntheirs-version\nbottom')" ] || return 1
}
verify_6() {
  in_merge && return 1
  [ "$(parent_count main)" -eq 2 ] || return 1
  g cat-file -e main:docs.txt 2>/dev/null || return 1
  [ "$(g show main:docs.txt)" = "DOCS-v2" ] || return 1
}
verify_7() {
  has_markers new.txt && return 1
  [ "$(g show main:new.txt)" = "combined" ] || return 1
}
verify_8() {
  printf 'LOGO-THEIRS-v2\x00\x02' > "$EXAM_HOME/_exp.bin"
  cmp -s "$EXAM_HOME/_exp.bin" "$REPO/logo.bin" || return 1
  rm -f "$EXAM_HOME/_exp.bin"
}
verify_9() {
  [ "$(g rev-parse main)" = "$(g rev-parse premerge)" ] || return 1
}
verify_10() {
  [ "$(tree_of main)" = "$(tree_of premerge)" ] || return 1
  [ "$(g rev-parse main)" != "$(g rev-parse premerge)" ] || return 1
}
verify_11() {
  g fetch -q origin
  [ -z "$(g log --merges base..main)" ] || return 1
  [ "$(g rev-parse main)" = "$(g rev-parse origin/main)" ] || return 1
  g cat-file -e main:local.txt 2>/dev/null || return 1
  g cat-file -e main:remote.txt 2>/dev/null || return 1
}
verify_12() {
  g merge-base --is-ancestor main feature || return 1
  [ -z "$(g log --merges main..feature)" ] || return 1
  g cat-file -e feature:f1.txt 2>/dev/null || return 1
  g cat-file -e feature:f2.txt 2>/dev/null || return 1
}
verify_13() {
  in_rebase && return 1
  g merge-base --is-ancestor main feature || return 1
  [ "$(g show feature:rb.txt)" = "$(printf 'top\nREBASED\nbottom')" ] || return 1
}
verify_14() {
  [ "$(g rev-list --count base..feature)" -eq 1 ] || return 1
  g cat-file -e feature:one.txt 2>/dev/null || return 1
  g cat-file -e feature:two.txt 2>/dev/null || return 1
  g cat-file -e feature:three.txt 2>/dev/null || return 1
}
verify_15() {
  local bad good
  bad=$(g log --format=%s feature | grep -c '^BAD$')
  good=$(g log --format=%s feature | grep -c '^GOOD$')
  [ "$bad" -eq 0 ] && [ "$good" -eq 1 ] || return 1
  [ "$(g rev-list --count base..feature)" -eq 3 ] || return 1
}
verify_16() {
  g cat-file -e main:x2.txt 2>/dev/null || return 1
  [ "$(g show main:x2.txt)" = "two" ] || return 1
  [ "$(g show main:x1.txt 2>/dev/null || echo absent)" = "absent" ] || return 1
  [ "$(g show main:x3.txt 2>/dev/null || echo absent)" = "absent" ] || return 1
}
verify_17() {
  has_markers shared.txt && return 1
  [ "$(g show main:shared.txt)" = "$(printf 'top\nPICKED\nbottom')" ] || return 1
}
verify_18() {
  [ "$(g rev-parse main)" = "$(g rev-parse base)" ] || return 1
  g cat-file -e feature:oops.txt 2>/dev/null || return 1
}
verify_19() {
  [ "$(g rev-parse main)" = "$(g rev-parse base)" ] || return 1
  g diff --cached --name-only | grep -qx 'work.txt' || return 1
}
verify_20() {
  g fetch -q origin
  [ "$(g show origin/main:a.txt)" = "A" ] || return 1
  [ "$(g rev-list --count base..origin/main)" -ge 2 ] || return 1
}
verify_21() {
  g fetch -q origin
  [ "$(g rev-parse origin/main)" = "$(g rev-parse base)" ] || return 1
}
verify_22() {
  [ "$(g show HEAD:a.txt)" = "A" ] || return 1
  [ -z "$(g status --porcelain)" ] || return 1
}
verify_23() {
  [ -f "$REPO/temp.txt" ] || return 1
  [ -z "$(g diff --cached --name-only)" ] || return 1
  g status --porcelain | grep -q '^?? temp.txt' || return 1
}
verify_24() {
  [ -f "$REPO/keep.txt" ] || return 1
  [ "$(cat "$REPO/keep.txt")" = "keep" ] || return 1
}
verify_25() {
  [ "$(g log -1 --format=%s)" = "add f and g" ] || return 1
  g cat-file -e HEAD:f.txt 2>/dev/null || return 1
  g cat-file -e HEAD:g.txt 2>/dev/null || return 1
  [ "$(g rev-list --count base..HEAD)" -eq 1 ] || return 1
}
verify_26() {
  g rev-parse --verify -q recovered >/dev/null || return 1
  [ "$(g show recovered:secret.txt 2>/dev/null)" = "ORIGINAL" ] || return 1
}
verify_27() {
  g rev-parse --verify -q recovered >/dev/null || return 1
  g cat-file -e recovered:precious.txt 2>/dev/null || return 1
}
verify_28() {
  g rev-parse --verify -q lost >/dev/null || return 1
  g cat-file -e lost:lost.txt 2>/dev/null || return 1
}
verify_29() {
  [ "$(g symbolic-ref --short -q HEAD)" = "main" ] || return 1
  [ "$(g show HEAD:a.txt)" = "A" ] || return 1
  [ "$(cat "$REPO/a.txt")" = "STASHED-A" ] || return 1
  [ -z "$(g stash list)" ] || return 1
  g cat-file -e hotfix:fix.txt 2>/dev/null || return 1
}
verify_30() {
  [ -z "$(g stash list)" ] || return 1
  [ "$(g show HEAD:shared.txt)" = "$(printf 'top\nSTASHED\nbottom')" ] || return 1
}
verify_31() {
  g rev-parse --verify -q savepoint >/dev/null || return 1
  local exp; exp=$(cat "$EXAM_HOME/q31.expected" 2>/dev/null)
  [ "$(g rev-parse savepoint)" = "$exp" ] || return 1
}
verify_32() {
  [ -f "$REPO/log.txt" ] || return 1
  g ls-files --error-unmatch log.txt >/dev/null 2>&1 && return 1
  [ -z "$(g status --porcelain)" ] || return 1
}
verify_33() {
  g fetch -q --prune origin
  ! g ls-remote --heads origin 2>/dev/null | grep -q 'refs/heads/feature-x' || return 1
  ! g for-each-ref --format='%(refname:short)' refs/remotes/origin 2>/dev/null | grep -qx 'origin/feature-x' || return 1
}
verify_34() {
  [ "$(g cat-file -t v1.0 2>/dev/null)" = "tag" ] || return 1
  g ls-remote --tags origin 2>/dev/null | grep -q 'refs/tags/v1.0' || return 1
  [ "$(g rev-parse v1.0^{commit})" = "$(g rev-parse base)" ] || return 1
}
verify_35() {
  local exp; exp=$(cat "$EXAM_HOME/q35.expected" 2>/dev/null)
  [ -n "$exp" ] || return 1
  local remote_hash
  remote_hash=$(g ls-remote --heads origin rescued 2>/dev/null | awk '{print $1}')
  [ "$remote_hash" = "$exp" ] || return 1
}

# =====================================================================
# 参考答案（仅供自测，做题时请勿查看）
# =====================================================================
solve_1()  { git -C "$REPO" pull -q --no-edit origin main && git -C "$REPO" push -q origin main; }
solve_2()  { g checkout -qf main; g merge -q --ff-only feature; }
solve_3()  { g checkout -qf main; g merge -q --no-ff feature -m "merge feature"; }
solve_4()  { g checkout -qf main; g merge --no-edit feature >/dev/null 2>&1; printf 'top\nresolved\nbottom\n' > "$REPO/conflict.txt"; g add conflict.txt; g commit -qm "resolve"; }
solve_5()  { g checkout -qf main; g merge --no-edit feature >/dev/null 2>&1; g checkout --theirs conflict.txt; g add conflict.txt; g commit -qm "take theirs"; }
solve_6()  { g checkout -qf main; g merge --no-edit feature >/dev/null 2>&1; g checkout main -- docs.txt 2>/dev/null || printf 'DOCS-v2\n' > "$REPO/docs.txt"; g add docs.txt; g commit -qm "keep modified docs"; }
solve_7()  { g checkout -qf main; g merge --no-edit feature >/dev/null 2>&1; printf 'combined\n' > "$REPO/new.txt"; g add new.txt; g commit -qm "resolve new"; }
solve_8()  { g checkout -qf main; g merge --no-edit feature >/dev/null 2>&1; g checkout --theirs logo.bin; g add logo.bin; g commit -qm "take theirs logo"; }
solve_9()  { g checkout -qf main; g reset -q --hard premerge; }
solve_10() { g checkout -qf main; g revert --no-edit -m 1 HEAD; }
solve_11() { g checkout -qf main; g pull -q --rebase origin main; g push -q origin main; }
solve_12() { g checkout -qf feature; g rebase -q main; }
solve_13() { g checkout -qf feature; g rebase main >/dev/null 2>&1 || true; printf 'top\nREBASED\nbottom\n' > "$REPO/rb.txt"; g add rb.txt; GIT_EDITOR=true git -C "$REPO" rebase --continue >/dev/null 2>&1; }
solve_14() { g checkout -qf feature; GIT_SEQUENCE_EDITOR="sed -i '2,3s/^pick/squash/'" GIT_EDITOR=true git -C "$REPO" rebase -i base >/dev/null 2>&1; }
solve_15() { g checkout -qf feature; GIT_SEQUENCE_EDITOR="sed -i '2s/^pick/reword/'" GIT_EDITOR="sed -i '1s/.*/GOOD/'" git -C "$REPO" rebase -i base >/dev/null 2>&1; }
solve_16() { local h; h=$(g log --format='%H %s' feature | awk '/add x2.txt/{print $1}'); g checkout -qf main; git -C "$REPO" cherry-pick "$h" >/dev/null 2>&1; }
solve_17() { local h; h=$(g log --format='%H %s' feature | awk '/feature edit shared/{print $1}'); g checkout -qf main; g cherry-pick "$h" >/dev/null 2>&1; printf 'top\nPICKED\nbottom\n' > "$REPO/shared.txt"; g add shared.txt; g cherry-pick --continue >/dev/null 2>&1 || g commit -qm "picked"; }
solve_18() { g checkout -qf main; g branch feature; g reset -q --hard base; }
solve_19() { g checkout -qf main; g reset -q --soft HEAD~1; }
solve_20() { g checkout -qf main; g revert --no-edit HEAD; g push -q origin main; }
solve_21() { g checkout -qf main; g reset -q --hard base; g push -qf --force-with-lease origin main; }
solve_22() { g checkout -q -- a.txt; }
solve_23() { g reset -q temp.txt; }
solve_24() { g checkout -qf -- keep.txt; }
solve_25() { g checkout -qf main; g add g.txt; g commit -q --amend -m "add f and g"; }
solve_26() { local h; h=$(g reflog --format='%H %gs' | awk '/add secret$/{print $1; exit}'); g branch recovered "$h"; }
solve_27() { local h; h=$(g reflog --format='%H %gs' | awk '/precious/{print $1; exit}'); g branch recovered "$h"; }
solve_28() { local h; h=$(g reflog --format='%H %gs' | awk '/lost work/{print $1; exit}'); g branch lost "$h"; }
solve_29() { g stash -q; g checkout -q hotfix; printf 'fix\n' > "$REPO/fix.txt"; g add -A; g commit -qm "hotfix fix"; g checkout -q main; g stash pop -q; }
solve_30() { g stash pop >/dev/null 2>&1 || true; printf 'top\nSTASHED\nbottom\n' > "$REPO/shared.txt"; g add shared.txt; g commit -qm "resolve stash" >/dev/null 2>&1; g stash clear 2>/dev/null || true; }
solve_31() { g branch savepoint; }
solve_32() { g rm -q --cached log.txt; printf 'log.txt\n' >> "$REPO/.gitignore"; g add .gitignore; g commit -qm "stop tracking log.txt"; }
solve_33() { g push -q origin --delete feature-x; g fetch -q --prune origin; }
solve_34() { g tag -a v1.0 -m "release 1.0" base; g push -q origin v1.0; }
solve_35() { local h; h=$(cat "$EXAM_HOME/q35.expected"); g branch rescued "$h" >/dev/null 2>&1; g push -q origin rescued; }

# =====================================================================
# CLI
# =====================================================================
need_init() {
  if [ ! -d "$REPO/.git" ]; then
    err "练习环境尚未初始化，请先执行： bash exam.sh init"
    exit 1
  fi
}
valid_n() {
  case "$1" in ''|*[!0-9]*) return 1;; esac
  [ "$1" -ge 1 ] && [ "$1" -le "$N_QUESTIONS" ]
}

cmd_list() {
  say "${BOLD}Git 实战考试 —— 题目列表（共 $N_QUESTIONS 题）${N}"
  say ""
  local i
  for i in $(seq 1 "$N_QUESTIONS"); do
    printf '  %2d) %s\n' "$i" "${TITLE[$i]}"
  done
  say ""
  say "查看某题：  bash exam.sh info <题号>"
  say "搭建环境：  bash exam.sh setup <题号>"
  say "提交校验：  bash exam.sh check <题号>"
}

cmd_info() {
  local n=$1; valid_n "$n" || { err "题号无效"; exit 1; }
  say "${BOLD}第 $n 题：${TITLE[$n]}${N}"
  say ""
  say "${B}[任务]${N}"
  printf '%b\n' "${TASK[$n]}"
  say ""
  say "${Y}[提示]${N} ${HINT[$n]}"
  say ""
  say "练习仓库位置： $REPO"
  say "（在该仓库内完成操作，然后执行  bash exam.sh check $n ）"
}

cmd_setup() {
  local n=$1; valid_n "$n" || { err "题号无效"; exit 1; }
  need_init
  fresh
  "setup_$n"
  ok "第 $n 题环境已就绪：${TITLE[$n]}"
  say "练习仓库： $REPO"
  say "完成操作后执行： bash exam.sh check $n"
}

cmd_check() {
  local n=$1; valid_n "$n" || { err "题号无效"; exit 1; }
  need_init
  if "verify_$n" >/dev/null 2>&1; then
    ok "通过！第 $n 题解答正确。"
    printf '%s\n' "${G}${BOLD}flag:cyz-NO.$n-${FLAG[$n]}${N}"
  else
    err "未通过：第 $n 题当前状态还不满足要求。"
    say "提示：${HINT[$n]}"
    exit 1
  fi
}

cmd_spoil() {
  local n=$1; valid_n "$n" || { err "题号无效"; exit 1; }
  need_init
  "solve_$n"
  ok "已应用第 $n 题参考答案（仅用于自我验证环境是否可用）。"
}

cmd_reset() {
  need_init; fresh; ok "练习仓库已重置到初始状态。"
}

cmd_help() {
  cat <<'EOF'
git-exam —— Git 实战考试工具

用法：
  bash exam.sh init            初始化练习环境（首次必须执行）
  bash exam.sh list            列出所有题目
  bash exam.sh info   <题号>   查看题目任务与提示
  bash exam.sh setup  <题号>   搭建该题的起始环境
  bash exam.sh check  <题号>   校验解答，通过则输出 flag
  bash exam.sh reset           把练习仓库重置到初始状态
  bash exam.sh spoil  <题号>   应用参考答案（自我检测用，作弊勿点）

说明：
  * 练习仓库位于 $EXAM_HOME/repo，其 origin 是一个本地裸仓库(模拟远程)。
  * 所有 git 操作都在该练习仓库里进行。
  * 通过后 flag 形如： flag:cyz-NO.<题号>-<随机数>
EOF
}

main() {
  local cmd=${1:-help}
  case "$cmd" in
    init)  cmd_init;;
    list)  cmd_list;;
    info)  cmd_info "${2:-}";;
    setup) cmd_setup "${2:-}";;
    check) cmd_check "${2:-}";;
    reset) cmd_reset;;
    spoil) cmd_spoil "${2:-}";;
    help|-h|--help) cmd_help;;
    *) err "未知命令：$cmd"; cmd_help; exit 1;;
  esac
}
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  main "$@"
fi