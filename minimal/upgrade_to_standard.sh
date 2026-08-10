#!/bin/bash
# =============================================================================
# RustyClean 极简验证 — 升级到标准方案
# =============================================================================
# 在极简验证成功后，一键扩展到完整方案
# Usage: bash upgrade_to_standard.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

echo "========================================"
echo "RustyClean 极简验证 → 标准方案升级"
echo "========================================"
echo ""

# 检查极简方案结果是否存在
if [ ! -f "$PROJECT_DIR/minimal/results/metrics/performance.csv" ]; then
    echo "ERROR: 未找到极简方案结果"
    echo "请先运行: bash minimal/run_minimal.sh"
    exit 1
fi

echo "极简方案结果已确认存在"
echo ""

# ---------------------------------------------------------------------------
# Step 1: 备份极简方案结果
# ---------------------------------------------------------------------------

echo "[Step 1/5] 备份极简方案结果..."

BACKUP_DIR="$PROJECT_DIR/results/minimal_baseline"
mkdir -p "$BACKUP_DIR"
cp -r "$PROJECT_DIR/minimal/results/"* "$BACKUP_DIR/" 2>/dev/null || true
echo "  备份到: $BACKUP_DIR"

# ---------------------------------------------------------------------------
# Step 2: 生成增强数据集（14个新数据集）
# ---------------------------------------------------------------------------

echo ""
echo "[Step 2/5] 生成增强数据集..."
echo "  将生成额外的 14 个数据集（已存在的 4 个会跳过）"
echo ""

bash "$PROJECT_DIR/scripts/generate_enhanced_data.sh" "$PROJECT_DIR/data/enhanced" "$PROJECT_DIR/minimal_env/genomes"

# 将极简的 4 个数据集也链接到增强目录
for ds in 10M_10pct 30M_50pct 60M_90pct 20M_50pct_PE; do
    if [ -d "$PROJECT_DIR/minimal/data/$ds" ] && [ ! -d "$PROJECT_DIR/data/enhanced/$ds" ]; then
        ln -s "$PROJECT_DIR/minimal/data/$ds" "$PROJECT_DIR/data/enhanced/$ds" 2>/dev/null || true
    fi
done

# ---------------------------------------------------------------------------
# Step 3: 运行完整 Benchmark（3 次重复）
# ---------------------------------------------------------------------------

echo ""
echo "[Step 3/5] 运行完整 Benchmark（3 次重复）..."
echo "  预计时间: 8-16 小时"
echo ""

bash "$PROJECT_DIR/scripts/run_benchmark.sh" "$PROJECT_DIR/data/enhanced" "$PROJECT_DIR/results"

# ---------------------------------------------------------------------------
# Step 4: 下游分析
# ---------------------------------------------------------------------------

echo ""
echo "[Step 4/5] 运行下游分析..."
echo "  包括: Taxonomy, Assembly, Diversity, CheckM2"
echo "  预计时间: 4-8 小时"
echo ""

bash "$PROJECT_DIR/scripts/downstream_analysis.sh" "$PROJECT_DIR/results" "$PROJECT_DIR/data/enhanced"

# ---------------------------------------------------------------------------
# Step 5: 生成投稿级可视化
# ---------------------------------------------------------------------------

echo ""
echo "[Step 5/5] 生成投稿级可视化..."
echo ""

# 准确性分析
python "$PROJECT_DIR/scripts/analyze_accuracy.py" "$PROJECT_DIR/data/enhanced" "$PROJECT_DIR/results"

# 基础性能可视化
python "$PROJECT_DIR/scripts/analyze_performance.py" "$PROJECT_DIR/results"

# 投稿级图表
python "$PROJECT_DIR/scripts/plot_publication_figures.py" "$PROJECT_DIR/results" "$PROJECT_DIR/analysis/figures"

# 生成报告
python "$PROJECT_DIR/scripts/generate_report.py" "$PROJECT_DIR/results" "$PROJECT_DIR/analysis/report.md"

# ---------------------------------------------------------------------------
# 完成
# ---------------------------------------------------------------------------

echo ""
echo "========================================"
echo "升级完成！"
echo "========================================"
echo ""
echo "完整结果位于:"
echo "  $PROJECT_DIR/results/       — Benchmark 原始输出"
echo "  $PROJECT_DIR/analysis/      — 分析和可视化"
echo "  $PROJECT_DIR/analysis/figures/ — 投稿级图表 (svg, pdf, tiff, png)"
echo ""
echo "投稿级图表:"
echo "  figure_1_runtime.svg         — 运行时间对比"
echo "  figure_2_memory_throughput.svg — 内存和吞吐量"
echo "  figure_3_accuracy.svg        — 准确性对比"
echo "  figure_4_comprehensive.svg   — 综合评估"
echo ""
echo "最终报告:"
echo "  $PROJECT_DIR/analysis/report.md"
