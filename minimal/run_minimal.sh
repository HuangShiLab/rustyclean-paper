#!/bin/bash
# =============================================================================
# RustyClean 极简验证 — 一键运行脚本
# =============================================================================
# 生成 4 个核心数据集，运行 RustyClean vs KneadData，输出结果
# Usage: bash run_minimal.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="$PROJECT_DIR/minimal/data"
RESULTS_DIR="$PROJECT_DIR/minimal/results"
THREADS=8

echo "========================================"
echo "RustyClean 极简验证 — 一键运行"
echo "========================================"
echo "数据集: 4 个核心场景"
echo "工具: RustyClean vs KneadData"
echo "重复: 1 次（验证流程）"
echo ""

# 加载环境
if [ -f "$PROJECT_DIR/minimal_env/env.sh" ]; then
    source "$PROJECT_DIR/minimal_env/env.sh"
else
    echo "ERROR: 环境未设置。请先运行: bash minimal/setup_minimal_env.sh"
    exit 1
fi

mkdir -p "$DATA_DIR"
mkdir -p "$RESULTS_DIR"
mkdir -p "$RESULTS_DIR/logs"
mkdir -p "$RESULTS_DIR/metrics"

# ---------------------------------------------------------------------------
# Step 1: 生成模拟数据
# ---------------------------------------------------------------------------

echo "[Step 1/4] 生成模拟数据..."

# 检查数据是否已存在
if [ -f "$DATA_DIR/60M_90pct/completed.flag" ]; then
    echo "  数据已存在，跳过生成"
else
    echo "  使用 InsilicoSeq 生成 4 个数据集..."
    
    # 定义数据集
    DATASETS=(
        "10M_10pct:10000000:0.10:SE"
        "30M_50pct:30000000:0.50:SE"
        "60M_90pct:60000000:0.90:SE"
        "20M_50pct_PE:20000000:0.50:PE"
    )
    
    for ds_config in "${DATASETS[@]}"; do
        IFS=':' read -r DS_NAME N_READS HOST_PCT MODE <<< "$ds_config"
        
        DS_DIR="$DATA_DIR/$DS_NAME"
        mkdir -p "$DS_DIR"
        
        if [ -f "$DS_DIR/completed.flag" ]; then
            echo "    $DS_NAME 已存在"
            continue
        fi
        
        echo "    生成 $DS_NAME (${N_READS} reads, ${HOST_PCT} host)..."
        
        HOST_READS=$(python -c "print(int($N_READS * $HOST_PCT))")
        MICROBE_READS=$(python -c "print(int($N_READS * (1 - $HOST_PCT)))")
        
        # 使用已有的 generate_enhanced_data.sh 逻辑
        # 这里简化：直接用 Python 生成
        python3 "$SCRIPT_DIR/generate_one_dataset.py" \
            "$DS_DIR" \
            "$N_READS" \
            "$HOST_READS" \
            "$MICROBE_READS" \
            "$MODE" \
            "$HUMAN_GENOME" \
            "$GENOME_DIR/genomes_fasta"
        
        touch "$DS_DIR/completed.flag"
        echo "    $DS_NAME 完成"
    done
fi

# ---------------------------------------------------------------------------
# Step 2: 运行 Benchmark
# ---------------------------------------------------------------------------

echo ""
echo "[Step 2/4] 运行 Benchmark..."

# 初始化性能记录
echo "tool,dataset,rep,runtime_seconds,max_memory_kb,timestamp" > "$RESULTS_DIR/metrics/performance.csv"

run_tool() {
    local tool="$1"
    local dataset="$2"
    local ds_dir="$DATA_DIR/$dataset"
    local rep="$3"
    
    local out_dir="$RESULTS_DIR/$tool/${dataset}_rep${rep}"
    local log="$RESULTS_DIR/logs/${tool}_${dataset}_rep${rep}.log"
    local timefile="$RESULTS_DIR/logs/${tool}_${dataset}_rep${rep}.time"
    
    mkdir -p "$out_dir"
    
    echo "  Running $tool on $dataset (rep $rep)..."
    
    # 记录时间
    if /usr/bin/time -v echo "" >/dev/null 2>&1; then
        /usr/bin/time -v -o "$timefile" bash -c "
            if [ '$tool' = 'rustyclean' ]; then
                if [ -f '$ds_dir/reads_R1.fastq.gz' ]; then
                    $RUSTYCLEAN --r1 '$ds_dir/reads_R1.fastq.gz' --r2 '$ds_dir/reads_R2.fastq.gz' --kraken2-db '$KRAKEN2_DB' -o '$out_dir' -t $THREADS
                else
                    $RUSTYCLEAN --r1 '$ds_dir/reads.fastq.gz' --kraken2-db '$KRAKEN2_DB' -o '$out_dir' -t $THREADS
                fi
            else
                if [ -f '$ds_dir/reads_R1.fastq.gz' ]; then
                    kneaddata --input1 '$ds_dir/reads_R1.fastq.gz' --input2 '$ds_dir/reads_R2.fastq.gz' --output-prefix clean --reference-db '$KNEADDATA_DB' --threads $THREADS --output '$out_dir'
                else
                    kneaddata --unpaired '$ds_dir/reads.fastq.gz' --output-prefix clean --reference-db '$KNEADDATA_DB' --threads $THREADS --output '$out_dir'
                fi
            fi
        " > "$log" 2>&1
        
        runtime=$(grep "Elapsed (wall clock) time" "$timefile" | sed -n 's/.*Elapsed (wall clock) time.*: //p' 2>/dev/null || echo "unknown")
        max_mem=$(grep "Maximum resident set size" "$timefile" | sed -n 's/.*Maximum resident set size (kbytes): //p' 2>/dev/null || echo "unknown")
    else
        { time bash -c "
            if [ '$tool' = 'rustyclean' ]; then
                if [ -f '$ds_dir/reads_R1.fastq.gz' ]; then
                    $RUSTYCLEAN --r1 '$ds_dir/reads_R1.fastq.gz' --r2 '$ds_dir/reads_R2.fastq.gz' --kraken2-db '$KRAKEN2_DB' -o '$out_dir' -t $THREADS
                else
                    $RUSTYCLEAN --r1 '$ds_dir/reads.fastq.gz' --kraken2-db '$KRAKEN2_DB' -o '$out_dir' -t $THREADS
                fi
            else
                if [ -f '$ds_dir/reads_R1.fastq.gz' ]; then
                    kneaddata --input1 '$ds_dir/reads_R1.fastq.gz' --input2 '$ds_dir/reads_R2.fastq.gz' --output-prefix clean --reference-db '$KNEADDATA_DB' --threads $THREADS --output '$out_dir'
                else
                    kneaddata --unpaired '$ds_dir/reads.fastq.gz' --output-prefix clean --reference-db '$KNEADDATA_DB' --threads $THREADS --output '$out_dir'
                fi
            fi
        " ; } > "$log" 2>&1
        
        runtime="unknown"
        max_mem="unknown"
    fi
    
    echo "$tool,$dataset,$rep,$runtime,$max_mem,$(date -Iseconds)" >> "$RESULTS_DIR/metrics/performance.csv"
    echo "    $tool $dataset: runtime=$runtime, mem=$max_mem"
}

# 运行所有组合
for ds_name in 10M_10pct 30M_50pct 60M_90pct 20M_50pct_PE; do
    run_tool "rustyclean" "$ds_name" "1"
    run_tool "kneaddata" "$ds_name" "1"
done

# ---------------------------------------------------------------------------
# Step 3: 准确性分析
# ---------------------------------------------------------------------------

echo ""
echo "[Step 3/4] 准确性分析..."

python3 "$SCRIPT_DIR/analyze_minimal.py" "$DATA_DIR" "$RESULTS_DIR" 2>&1 | tee "$RESULTS_DIR/analysis.log"

# ---------------------------------------------------------------------------
# Step 4: 结果总结
# ---------------------------------------------------------------------------

echo ""
echo "[Step 4/4] 结果总结"
echo ""

# 读取性能数据并打印摘要
python3 << 'PYEOF'
import pandas as pd
import sys

try:
    df = pd.read_csv("results/metrics/performance.csv")
    
    print("=" * 60)
    print("RustyClean 极简验证结果")
    print("=" * 60)
    print()
    
    # Parse time
    def parse_time(t):
        if pd.isna(t) or t == 'unknown': return 0
        parts = str(t).split(':')
        if len(parts) == 3: return int(parts[0])*3600 + int(parts[1])*60 + float(parts[2])
        elif len(parts) == 2: return int(parts[0])*60 + float(parts[1])
        try: return float(parts[0])
        except: return 0
    
    df['runtime_sec'] = df['runtime_seconds'].apply(parse_time)
    
    print("速度对比:")
    for dataset in sorted(df['dataset'].unique()):
        rc = df[(df['dataset']==dataset) & (df['tool']=='rustyclean')]['runtime_sec'].values
        kd = df[(df['dataset']==dataset) & (df['tool']=='kneaddata')]['runtime_sec'].values
        
        if len(rc) > 0 and len(kd) > 0 and rc[0] > 0:
            speedup = kd[0] / rc[0]
            rc_min = rc[0] / 60
            kd_min = kd[0] / 60
            print(f"  {dataset:15s}: RustyClean {rc_min:5.1f} min vs KneadData {kd_min:6.1f} min → {speedup:5.1f}x 加速")
    
    print()
    
    # 准确性
    try:
        acc = pd.read_csv("results/accuracy.csv")
        print("准确性对比 (F1-Score):")
        for tool in ['rustyclean', 'kneaddata']:
            f1 = acc[acc['Tool']==tool]['F1'].mean() if 'F1' in acc.columns else 0
            print(f"  {tool:12s}: {f1:.4f}")
    except:
        print("准确性数据未生成")
    
    print()
    print("=" * 60)
    
except Exception as e:
    print(f"结果读取失败: {e}")
    sys.exit(1)
PYEOF

echo ""
echo "结果文件:"
echo "  $RESULTS_DIR/metrics/performance.csv"
echo "  $RESULTS_DIR/accuracy.csv"
echo "  $RESULTS_DIR/figure_speedup.png"
echo ""
echo "如果结果满意，运行: bash minimal/upgrade_to_standard.sh"
