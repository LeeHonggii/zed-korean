#!/usr/bin/env bash
# 매주: 에이전트(Claude·Codex) 먼저, 그다음 Zed 본체
DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$DIR/update_agents.sh"
bash "$DIR/update_upstream.sh"
