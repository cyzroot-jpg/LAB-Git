# Git 实战考试（git-exam）

一套覆盖真实开发中常见 Git 问题（提交 / 合并 / 冲突 / 撤销 / 找回 / 推送）的**动手实验考试**。
每题给你一个可复现的“案发现场”，你亲自动手解决，通过自动校验后拿到 flag。

- flag 格式：`flag:cyz-NO.<题号>-<随机数>`
- 共 **35** 题，全部自动化校验（`check` 通过才输出 flag）
- 环境安全：练习用的“远程仓库”是一个**本地裸仓库**（行为与 GitHub 完全一致），不会污染你真正的 GitHub 仓库

---

## 一、准备

需要：一台装了 `git` 的机器。Windows 用户请使用 **Git Bash**（安装 Git for Windows 时自带）。

```bash
# 1. 克隆本工具（clone 到你的练习目录，例如 D:\infor\gitLearn\exgit）
git clone -b git-exam https://github.com/cyzroot-jpg/LAB-Git.git exgit
cd exgit/git-exam

# 2. 初始化练习环境（只需执行一次）
bash exam.sh init
```

`init` 会在当前目录下的 `.exam-work/` 里创建：

```
.exam-work/
  remote.git   # 本地裸仓库，扮演“远程仓库 / GitHub”
  repo/        # 你的练习仓库，其 origin 指向 remote.git
```

之后所有 git 操作都在 `.exam-work/repo` 里进行。

> 想换位置？设置环境变量 `EXAM_HOME`，例如：
> `EXAM_HOME=/d/gitlab/exam bash exam.sh init`

---

## 二、使用流程

对每一题：

```bash
# 1. 看题目
bash exam.sh info 4

# 2. 搭建该题的起始环境（会自动重置练习仓库，保证隔离）
bash exam.sh setup 4

# 3. 进入练习仓库，按题目要求动手操作
cd .exam-work/repo
... 你的解决动作 ...

# 4. 回到工具目录，校验答案拿 flag
cd -
bash exam.sh check 4
```

常用命令：

| 命令 | 作用 |
|------|------|
| `bash exam.sh list` | 列出全部 35 题 |
| `bash exam.sh info <题号>` | 查看某题任务与提示 |
| `bash exam.sh setup <题号>` | 搭建该题起始环境（自动重置） |
| `bash exam.sh check <题号>` | 校验答案，通过则打印 flag |
| `bash exam.sh reset` | 把练习仓库重置到初始状态 |
| `bash exam.sh spoil <题号>` | 应用参考答案（自我检测用，做题时别点） |

---

## 三、题目总览

### 合并与冲突
| # | 题目 |
|---|------|
| 1 | push 被远程拒绝 (non-fast-forward) |
| 2 | 快进合并 (fast-forward) |
| 3 | 三方合并 (生成 merge commit) |
| 4 | 合并内容冲突：手动解决 |
| 5 | 冲突选边 (--ours / --theirs) |
| 6 | 修改/删除冲突 (modify/delete) |
| 7 | 双方新增同名文件 (add/add) |
| 8 | 二进制文件冲突 |
| 9 | 撤销一次合并 (reset) |
| 10 | 用 revert 撤销一个合并提交 |
| 11 | pull --rebase 避免产生 merge commit |

### 变基与挑拣
| # | 题目 |
|---|------|
| 12 | rebase 到最新的 main |
| 13 | rebase 冲突的解决 |
| 14 | rebase -i 压缩提交 (squash) |
| 15 | rebase -i 修改历史提交信息 (reword) |
| 16 | cherry-pick 单个提交 |
| 17 | cherry-pick 冲突 |
| 18 | 提交到了错误的分支 |

### 撤销 / 回退 / 找回
| # | 题目 |
|---|------|
| 19 | 撤销最近一次未推送的提交（保留改动） |
| 20 | 用 revert 撤销已推送的提交 |
| 21 | 撤回已推送的提交（reset + 强推） |
| 22 | 撤销未提交的工作区改动 |
| 23 | 取消暂存 (unstage) |
| 24 | 恢复被误删的文件 |
| 25 | amend 修改最近一次提交 |
| 26 | amend 后从 reflog 找回被覆盖的提交 |
| 27 | 从 reflog 找回 reset --hard 丢掉的提交 |
| 28 | 找回被误删的分支 |

### 暂存 / 状态 / 其它
| # | 题目 |
|---|------|
| 29 | stash 暂存与恢复 |
| 30 | stash pop 冲突 |
| 31 | 在 detached HEAD 上提交并保住成果 |
| 32 | .gitignore 对已跟踪文件不生效 |
| 33 | 删除远程分支并 prune 本地 |
| 34 | 创建、推送与查看注解标签 |
| 35 | 找回被 force push 覆盖的提交 |

---

## 四、规则

1. 每题先用 `setup` 搭环境，再做，最后 `check`。
2. `check` 通过会输出 `flag:cyz-NO.<题号>-<随机数>`，这就是你的成绩。
3. 做题时建议**只在练习仓库 `.exam-work/repo` 里操作**，不要碰工具目录。
4. 搞砸了随时 `bash exam.sh reset` 重来，或重新 `setup <题号>`。
5. 想验证是不是环境坏了：`bash exam.sh spoil <题号>` 应用参考答案后再 `check`，应当通过。

---

## 五、目录结构

```
git-exam/
  exam.sh     # 全部逻辑：init / list / info / setup / check / reset / spoil
  README.md   # 本文件
```

祝你考试顺利，全部拿到 flag！