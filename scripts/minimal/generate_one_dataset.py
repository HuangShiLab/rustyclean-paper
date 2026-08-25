#!/usr/bin/env python3
"""
RustyClean 极简验证 — 单数据集生成脚本
用法: python generate_one_dataset.py <output_dir> <n_reads> <host_reads> <microbe_reads> <mode> <human_genome> <microbe_genome_dir>
"""

import sys
import os
import subprocess
import json

def main():
    if len(sys.argv) < 7:
        print("Usage: python generate_one_dataset.py <output_dir> <n_reads> <host_reads> <microbe_reads> <mode> <human_genome> <microbe_genome_dir>")
        sys.exit(1)
    
    output_dir = sys.argv[1]
    n_reads = int(sys.argv[2])
    host_reads = int(sys.argv[3])
    microbe_reads = int(sys.argv[4])
    mode = sys.argv[5]  # SE or PE
    human_genome = sys.argv[6]
    microbe_genome_dir = sys.argv[7]
    
    os.makedirs(output_dir, exist_ok=True)
    
    # Check if insilicoseq is available
    try:
        subprocess.run(["iss", "--version"], capture_output=True, check=True)
    except:
        print("ERROR: insilicoseq (iss) not found. Install: conda install -c bioconda insilicoseq")
        sys.exit(1)
    
    # Generate microbial reads
    if microbe_reads > 0:
        print(f"  Generating {microbe_reads} microbial reads...")
        
        # Combine microbial genomes
        combined_microbe = os.path.join(output_dir, "microbial_input.fasta")
        if not os.path.exists(combined_microbe):
            if os.path.isdir(microbe_genome_dir) and os.listdir(microbe_genome_dir):
                with open(combined_microbe, 'w') as out:
                    for f in os.listdir(microbe_genome_dir):
                        if f.endswith('.fasta') or f.endswith('.fa'):
                            with open(os.path.join(microbe_genome_dir, f)) as inp:
                                out.write(inp.read())
            else:
                # Fallback: create minimal test
                with open(combined_microbe, 'w') as f:
                    f.write(">ECOLI_TEST\nATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCGATCG\n"
                    )
        
        # Generate abundance profile (even)
        abundance_file = os.path.join(output_dir, "abundance.txt")
        with open(abundance_file, 'w') as f:
            f.write("species_1\t1.0\n")
        
        # Run insilicoseq
        microbe_prefix = os.path.join(output_dir, "microbe")
        cmd = [
            "iss", "generate",
            "--genomes", combined_microbe,
            "--abundance_file", abundance_file,
            "--model", "miseq",
            "--n_reads", str(microbe_reads),
            "--output", microbe_prefix,
            "--cpus", "4"
        ]
        subprocess.run(cmd, check=True, capture_output=True)
    
    # Generate host reads
    if host_reads > 0:
        print(f"  Generating {host_reads} host reads...")
        host_prefix = os.path.join(output_dir, "host")
        cmd = [
            "iss", "generate",
            "--genomes", human_genome,
            "--model", "miseq",
            "--n_reads", str(host_reads),
            "--output", host_prefix,
            "--cpus", "4"
        ]
        subprocess.run(cmd, check=True, capture_output=True)
    
    # Merge and create ground truth
    print("  Merging and labeling...")
    
    if mode == "PE":
        # Paired-end
        microbe_r1 = os.path.join(output_dir, "microbe_R1.fastq")
        microbe_r2 = os.path.join(output_dir, "microbe_R2.fastq")
        host_r1 = os.path.join(output_dir, "host_R1.fastq")
        host_r2 = os.path.join(output_dir, "host_R2.fastq")
        
        # Combine R1
        with open(os.path.join(output_dir, "reads_R1.fastq"), 'w') as out:
            if microbe_reads > 0 and os.path.exists(microbe_r1):
                with open(microbe_r1) as f:
                    out.write(f.read())
            if host_reads > 0 and os.path.exists(host_r1):
                with open(host_r1) as f:
                    out.write(f.read())
        
        # Combine R2
        with open(os.path.join(output_dir, "reads_R2.fastq"), 'w') as out:
            if microbe_reads > 0 and os.path.exists(microbe_r2):
                with open(microbe_r2) as f:
                    out.write(f.read())
            if host_reads > 0 and os.path.exists(host_r2):
                with open(host_r2) as f:
                    out.write(f.read())
        
        # Ground truth labels
        with open(os.path.join(output_dir, "ground_truth_labels.txt"), 'w') as out:
            # Microbe reads first
            if microbe_reads > 0 and os.path.exists(microbe_r1):
                with open(microbe_r1) as f:
                    for i, line in enumerate(f):
                        if i % 4 == 0:
                            read_id = line.strip()[1:].split()[0]
                            out.write(f"{read_id}\tmicrobe\n")
            # Host reads after
            if host_reads > 0 and os.path.exists(host_r1):
                with open(host_r1) as f:
                    for i, line in enumerate(f):
                        if i % 4 == 0:
                            read_id = line.strip()[1:].split()[0]
                            out.write(f"{read_id}\thost\n")
        
        # Compress
        subprocess.run(["pigz", "-p", "4", os.path.join(output_dir, "reads_R1.fastq")], check=False)
        subprocess.run(["pigz", "-p", "4", os.path.join(output_dir, "reads_R2.fastq")], check=False)
        
    else:
        # Single-end
        microbe_file = os.path.join(output_dir, "microbe_reads.fastq")
        host_file = os.path.join(output_dir, "host_reads.fastq")
        
        with open(os.path.join(output_dir, "reads.fastq"), 'w') as out:
            if microbe_reads > 0 and os.path.exists(microbe_file):
                with open(microbe_file) as f:
                    out.write(f.read())
            if host_reads > 0 and os.path.exists(host_file):
                with open(host_file) as f:
                    out.write(f.read())
        
        # Ground truth labels
        with open(os.path.join(output_dir, "ground_truth_labels.txt"), 'w') as out:
            if microbe_reads > 0 and os.path.exists(microbe_file):
                with open(microbe_file) as f:
                    for i, line in enumerate(f):
                        if i % 4 == 0:
                            read_id = line.strip()[1:].split()[0]
                            out.write(f"{read_id}\tmicrobe\n")
            if host_reads > 0 and os.path.exists(host_file):
                with open(host_file) as f:
                    for i, line in enumerate(f):
                        if i % 4 == 0:
                            read_id = line.strip()[1:].split()[0]
                            out.write(f"{read_id}\thost\n")
        
        # Compress
        subprocess.run(["pigz", "-p", "4", os.path.join(output_dir, "reads.fastq")], check=False)
    
    # Metadata
    metadata = {
        "dataset_name": os.path.basename(output_dir),
        "total_reads": n_reads,
        "host_percentage": host_reads / n_reads if n_reads > 0 else 0,
        "host_reads": host_reads,
        "microbial_reads": microbe_reads,
        "read_mode": mode,
        "read_length": 150,
        "simulator": "InsilicoSeq"
    }
    with open(os.path.join(output_dir, "metadata.json"), 'w') as f:
        json.dump(metadata, f, indent=2)
    
    print(f"  Dataset {output_dir} complete")

if __name__ == '__main__':
    main()
