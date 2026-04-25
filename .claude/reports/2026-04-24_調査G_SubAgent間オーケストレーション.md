# 調査G: Sub-agents 間オーケストレーション機構

## 調査概要

**調査目的**: ユーザー要件「Management エージェント = 他エージェントのオーケストレーション」の実装方法を確定
**実施日**: 2026-04-24

## 🔑 決定的な発見

公式ドキュメント（Sub-agents ページ 714 行目）に明記：

> **「Subagents cannot spawn other subagents」**
>
> 「If your workflow requires nested delegation, use Skills or chain subagents from the main conversation.」

**含意**: Sub-agent から別の Sub-agent を呼び出すことは **公式に不可能**。

## A. Sub-agent 間呼び出しの公式機構

### A-1. frontmatter フィールド
- `tools: Agent(worker, researcher)` で Agent ツールの許可リスト指定可能
- ただしこれは **メインセッションから** Agent を spawn するためのもの
- Sub-agent 本体から Agent ツールを使っても別 Sub-agent は spawn **できない**

### A-2. 結論
- Sub-agent から別 Sub-agent を呼ぶ公式方法 **なし**
- 代替: (a) メインセッションから順次/並列 spawn、(b) Skill で orchestrate、(c) Agent Teams

## B. メインセッションからのオーケストレーション

### Agent ツール（旧 Task ツール）
- メインセッションの Claude が `Agent` ツールで Sub-agent を spawn
- 並列起動可能（1 メッセージで複数の tool call）
- 各 Sub-agent は独立コンテキストで作業し、結果をメインセッションに返す

## C. Agent Teams 機能の詳細

- **ステータス**: 実験的（Experimental）
- **有効化**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
- **制限**:
  - Session resumption with in-process teammates 非サポート
  - Task status lag あり
  - Shutdown が遅い
  - One team per session
  - No nested teams

**結論**: 実験段階のため **ベースキットには含めない**（CLAUDE.md で参考情報として言及する程度）

## D. Orchestrator 実装案の評価

| 案 | 実現可能性 | 評価 |
|---|---|---|
| 案1: Sub-agent として実装 | ❌ **不可能** | 公式仕様で Sub-agent から Sub-agent を呼べない |
| 案2: Skill として実装 | ✅ **完全に可能** | Skill は main session 実行、Agent ツール経由で複数 Sub-agent spawn 可能 |
| 案3: CLAUDE.md にガイドラインのみ | ✅ 可能 | サンプルとしては弱い |

## 最終判断

**✅ Orchestrator は Skill として `.claude/skills/orchestrate/SKILL.md` に実装**

### 実装方針

1. **`.claude/skills/orchestrate/SKILL.md` を新規作成**:
   ```yaml
   ---
   name: orchestrate
   description: Coordinates specialized agents for complex multi-phase or parallel tasks. Use when a task requires orchestrating multiple specialized agents.
   disable-model-invocation: true
   allowed-tools: Agent, Read, Grep, Bash
   ---
   ```
   - `disable-model-invocation: true` で手動トリガー
   - Parallel research pattern、Sequential chain pattern を例示

2. **`.claude/agents/orchestrator.md` は作成しない**:
   - 公式仕様により Sub-agent orchestrator は機能しないため

3. **CLAUDE.md にマルチエージェント戦略の簡単な言及**

## 参考資料

- https://code.claude.com/docs/en/sub-agents
- https://code.claude.com/docs/en/best-practices
