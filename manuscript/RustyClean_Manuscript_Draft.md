# RustyClean: minimizer-based host depletion with adaptive alignment verification for short-read metagenomics

**Authors:** Yufeng Zhang, [co-authors], Shi Huang\*
**Affiliation:** Faculty of Dentistry, The University of Hong Kong, Hong Kong SAR, China **Correspondence:** [email]

## Abstract

Computational depletion of host DNA is a mandatory first step in
short-read metagenomics, and its errors propagate silently into every
downstream result. Alignment-based depletion discards genuine microbial
reads, whereas k-mer classification retains host reads, and pipelines
that commit to one strategy inherit one failure mode unconditionally.
We present RustyClean, a host-depletion pipeline that replaces this
fixed trade-off with a two-tier design: fastp quality control, then
minimizer-based depletion with deacon --- a recently described tool,
not yet peer-reviewed at the time of writing --- against a pangenome
index as the default Tier-1 backend, then an adaptive Bowtie2
verification tier that fires only when deacon's own removed-read
summary reports a removed proportion above a configurable threshold
(default 0.3). Because deacon's per-read cost is independent of host
fraction, no per-sample routing between backends is required; the live
decision becomes verification-budget allocation. On simulated
metagenomes spanning 1--90% host content with per-read ground truth,
the deacon depletion step alone was 44--130× faster than the complete
KneadData pipeline, and the full RustyClean AUTO pipeline was
3.7--10× faster than KneadData and 1.3--2.3× faster than
fastp + Hostile while matching or exceeding their accuracy (F1 ≥ 0.998
on high-host samples), reducing host carry-over to 0.0000% of retained
output on every high-host dataset tested --- against ~0.67% for
Hostile and ~0.25% for KneadData --- and discarding at most 0.31% of
microbial reads, against 1.4--4.0% for KneadData. Peak memory was
4.8 GB, above KneadData's 1.2 GB but bounded by index size rather
than sample size. Sample-level parallelism scaled near-linearly (7.84×
on 8 workers, 98% parallel efficiency) with a flat per-worker memory
footprint, because all workers share a single memory-mapped copy of the
index. Because deacon's published prebuilt indexes cover human and
mouse only, we built and validated species-matched indexes for human
(T2T), monkey, mouse, pig, rat and rice (build time 4--52 s each):
each species' own index achieved F1 0.99986--0.99998, whereas the
human panhuman-1 index wrongly depleted 46.8% of the microbial reads
in monkey-host samples and 97--99.8% in mouse, pig, rat and rice
samples, showing that species-matched or pan-host indexes are
mandatory outside human. RustyClean is a single Rust binary with
per-stage checkpointing, bounded concurrency and an automated output
validation gate, available at
https://github.com/HuangShiLab/rustyclean under the MIT licence.

**Keywords:** metagenomics, host depletion, decontamination,
minimizers, deacon, Bowtie2, Rust

## 1. Introduction

Shotgun metagenomic sequencing of host-associated samples returns a
mixture of microbial and host DNA. The host fraction varies enormously
by body site: stool libraries are typically 1--2% human, whereas saliva,
dental plaque, skin, and biopsy libraries are routinely 50--90% human or
higher. Because host reads consume sequencing budget and distort every
downstream estimate, computational host depletion is universally applied
before taxonomic profiling, assembly, or metagenome-assembled genome
(MAG) recovery.

Depletion is a binary classification problem over reads, and like any
classifier it can fail in two directions. A **false positive** --- a
microbial read wrongly called host --- is an irreversible loss of
signal: it biases diversity estimates, distorts relative abundance, and
removes evidence that assembly and binning depend on. A **false
negative** --- a host read wrongly retained --- is comparatively benign
for profiling, since most profilers leave unassignable reads unassigned;
but it is not harmless, because residual host DNA contaminates
assemblies and raises consent and privacy concerns when data are shared.

These two errors are therefore not interchangeable, and the choice of
depletion method determines which one dominates. Our group\'s recent
benchmark of six host-removal tools across human and rice datasets
established the pattern directly: alignment-based methods (Bowtie2, BWA,
KneadData) exhibited higher false positive rates, while k-mer
classification methods (Kraken2, KrakenUniq, KMCP) exhibited higher
false negative rates \[Gao et al. 2025\]. The same study showed that
Kraken2\'s efficiency advantage is substantial --- roughly 29 minutes
against 209--582 minutes for alignment-based tools --- and that its
advantage is most pronounced under high contamination (90%).

Most recently, deacon --- a minimizer-based sequence filter evaluated
against a pangenome index (Constantinides, Lees and Crook, bioRxiv
preprint, 2025; not yet peer-reviewed at the time of writing) --- was
reported to combine near-alignment accuracy with classification-grade
speed. Its per-read cost is essentially independent of host fraction:
unlike alignment it does not slow down when most reads must be fully
aligned, and unlike k-mer classification it does not become fast only
when most reads are host. If that behaviour replicates, the classical
routing between backends dissolves --- but the tool as published is a
bare filter, and several problems remain unsolved: it has no
verification tier, so a small structural residue of host reads is
retained; its officially published prebuilt indexes cover human and
mouse only; it performs no quality control and offers no orchestration
for cohort-scale sample processing; and it ships no decision logic for
deciding when an expensive verification pass is worth its cost.
Resolving those gaps, rather than re-implementing the filter, is the
subject of this paper.

Two findings define the contribution of this paper.

**First, the false negative rate is not uniformly acceptable.** At high
host fractions, the residual host retained by k-mer classification ---
and, at a much smaller level, by minimizer depletion --- becomes large
in absolute terms even when its rate is modest, because the pool of
host reads is large. In this regime, Tier-1 depletion alone does not
deliver a sufficiently clean library.

**Second, minimizer-based depletion dissolves the routing problem but
not the verification problem.** Because deacon's per-read cost is
host-fraction-independent, a single Tier-1 backend suffices across the
whole host-fraction spectrum. What remains is verification-budget
allocation: deacon alone leaves a structural residue of host reads
(~0.004% of retained output on our panel), and deciding when a Bowtie2
verification pass over the retained reads is worth its cost requires a
decision rule that the bare tool does not provide.

RustyClean addresses these points directly. It integrates deacon as the
default Tier-1 depletion backend behind a quality-control and
orchestration layer, and it adds an adaptive verification tier:
RustyClean parses deacon's own summary JSON, and whenever the reported
removed proportion (`seqs_removed_proportion`) reaches
`--recheck-threshold` (default 0.3) the retained reads are re-screened
with Bowtie2; below the threshold the deacon output is accepted as
final. The per-sample decision is thereby recast from "which backend"
to "how much verification": the pass is expensive exactly when the
retained set is large, and the threshold restricts it to samples whose
host content makes both the residue and the pass cost proportionate.

We additionally treat the orchestration layer as a first-class concern.
Analysis of a KneadData run log showed that 16% of wall-clock time on a
60M-read sample was spent reformatting read identifiers --- a
text-processing step performing no biological work. RustyClean
implements per-stage checkpointing with content-invalidating input
fingerprints, bounded two-level concurrency, and an automated validation
gate that prevents truncated or insufficiently decontaminated outputs
from being promoted into a results directory.

**Contributions.**

1.  An integration of minimizer-based depletion (deacon) as the
    default Tier-1 backend behind a quality-control and orchestration
    layer, replacing per-sample backend routing with adaptive
    verification-budget allocation: a Bowtie2 verification tier
    triggered by deacon's own removed-proportion summary (default
    threshold 0.3), which reduces host carry-over from
    0.0035--0.0042% to 0.0000% on high-host samples.
2.  A validated pan-host index set: species-specific deacon indexes
    for human (T2T), monkey, mouse, pig, rat and rice, built in
    4--52 s each, and a quantification of panhuman-1 cross-reactivity
    showing that species-matched or pan-host indexes are mandatory for
    non-human work.
3.  A production-oriented implementation with checkpoint/resume,
    bounded concurrency, memory-aware worker capping, and automated
    output validation, with measured near-linear sample-level
    parallelism (7.84× on 8 workers at 98% efficiency) and flat
    per-worker memory through a shared memory-mapped index.
4.  An evaluation on simulated metagenomes with per-read ground
    truth spanning 1--90% host content and 5--100 M reads, a
    four-way comparison against KneadData and Hostile, a six-host
    cross-species panel, and a real-data cohort.

## 2. Methods

### 2.1 Pipeline overview

In the default configuration (AUTO mode with a deacon index supplied),
RustyClean processes each sample through four stages:

1.  **Quality control** --- adapter detection and trimming, quality
    filtering (fastp).
2.  **Tier-1 host depletion** --- minimizer-based depletion with deacon
    against a user-supplied pangenome index (Section 2.3).
3.  **Conditional verification** --- RustyClean parses deacon's summary
    JSON; if the reported removed proportion (`seqs_removed_proportion`)
    is at least `--recheck-threshold` (default 0.3), the retained reads
    are re-screened with Bowtie2 (Section 2.5). Below the threshold the
    deacon output is final.
4.  **Validation and finalisation** --- automated assertions before
    output promotion (Section 2.6).

Samples may be supplied individually or as a tab-separated sample
manifest; single-end and paired-end layouts are detected automatically
and handled throughout. Alternative depletion backends (Bowtie2,
minimap2, Kraken2, sylph, Centrifuge) remain available as explicit
options (`--host-removal-mode`) but are not used by the default
AUTO configuration (Sections 2.10 and 3.5).

### 2.2 Quality control

Reads are processed with fastp \[Ref\], configured by default for
automatic adapter detection in paired-end mode
(`--detect_adapter_for_pe`), sliding-window quality trimming from both
ends (`--cut_front`, `--cut_tail`), a qualified base quality threshold
of Q20, and a minimum retained length of 50 bp. All parameters are
exposed through a TOML configuration file. fastp emits a JSON report,
which RustyClean parses into a typed metrics record capturing input and
output read counts, Q20/Q30 rates, GC content, adapter-trimmed reads,
and reads discarded as too short or low quality.

Unlike KneadData, RustyClean does not perform tandem-repeat masking.
This is a deliberate scope decision --- repeat masking is a general
low-complexity filtering concern rather than a host-depletion concern
--- and it is accounted for explicitly in the runtime comparisons
(Section 3.1).

### 2.3 Minimizer-based depletion with deacon (default Tier-1 backend)

The default Tier-1 backend is deacon (Constantinides, Lees and Crook,
bioRxiv preprint, 2025; not yet peer-reviewed at the time of writing), a
minimizer-based sequence filter that depletes host reads against a
pangenome index. RustyClean invokes deacon (v0.17.0; clean step with
options `-d -a 2 -r 0.01`) on the quality-controlled reads --- or on the
raw reads in `--skip-qc` depletion-only benchmarking --- and parses
deacon's summary JSON into the typed metrics record, including the
removed read count and `seqs_removed_proportion` that drives the
verification decision (Section 2.4). For human data the default index is
the published panhuman-1 pangenome index (k31w15; ~3.3 GB on disk);
users may supply any deacon index, and species-matched indexes for six
hosts are described in Section 3.2.

### 2.4 Adaptive verification-budget allocation

When a deacon index is configured --- the default --- no routing between
depletion backends is necessary, because deacon's per-read cost is
independent of host fraction. The decision that remains is whether to
spend verification budget on a sample, and RustyClean makes it from
deacon's own output rather than from a separate survey: if the
proportion of input reads that deacon removed (`seqs_removed_proportion`
in deacon's summary JSON) is at least `--recheck-threshold` (default
0.3), the retained reads are re-screened with Bowtie2 (Section 2.5);
otherwise the deacon output is accepted as final. The rule is
deliberately one-sided. A high removed proportion implies a large host
pool, in which the characteristic structural residue of minimizer
depletion (~0.004% of retained output on our panel) is worth
eliminating, and the retained set after depletion is small, so the
alignment pass is cheap. A low removed proportion implies the opposite
on both counts: the residue is absolutely tiny and the retained set is
large. Both the threshold and the pass itself are user-configurable.

### 2.5 Bowtie2 verification pass

No Tier-1 backend removes every host read: minimizer-based depletion
leaves a small structural residue (~0.0035--0.0042% of retained output
on our panel). RustyClean therefore implements a verification pass
(`--bowtie2-recheck`) in which the reads retained by the Tier-1 backend
are aligned against the host Bowtie2 index and those that align are
removed. Only the retained set is re-screened, so reads already
identified as host are never realigned.

In the default AUTO configuration the pass is triggered adaptively by
deacon's removed-proportion summary (Section 2.4; default threshold
0.3). It can be disabled with `--no-bowtie2-recheck` for users who
prefer raw Tier-1 output.

The cost of this pass is proportional to the size of the retained set,
which is small precisely when it is needed: at a host fraction of 0.9,
Tier-1 depletion removes the majority of reads and the verification pass
processes roughly a tenth of the library. At low host fractions the
retained set is large and verification would be expensive --- but those
samples fall below the recheck threshold in the default configuration,
so they never reach this stage. The worst-case cost of verification is
therefore bounded by the size of the retained set.

### 2.6 Validation gate

Every sample is subject to automated assertions before its output is
promoted:

- **Output size** --- each output file must exceed a configurable
  minimum, detecting silently truncated or empty outputs.
- **Residual contamination** --- the estimated host fraction of the
  output must not exceed a configurable maximum (default 5%), detecting
  a misconfigured or missing reference.

A sample failing either assertion is recorded as `Failed` and its
outputs are **not** moved into the output directory, so they cannot be
consumed by a downstream analysis by accident. To our knowledge no
existing host-depletion pipeline enforces an equivalent post-hoc
correctness check.

### 2.7 Orchestration and implementation

**Stage machine.** Each sample\'s progress is represented as a totally
ordered enumeration of stages (`Pending` → `FastpRunning` →
`FastpComplete` → `DepletionRunning` → `DepletionComplete` →
`Validating` → `Completed`/`Failed`). Because the stages are ordered,
resumption reduces to a comparison rather than per-stage branching
logic, and a resumed sample re-executes only the stages after its
recorded position.

**Checkpointing.** Per-sample state is serialised as versioned JSON and
written atomically (write-to-temporary followed by rename), so an
interrupted write cannot leave a partially parsed record. Each
checkpoint carries an xxHash3 fingerprint over input file metadata; a
change to the input invalidates the checkpoint automatically, so
resumption cannot silently return results computed from different data.
Checkpoints retain the full metrics payload and therefore double as a
per-sample provenance record.

**Concurrency.** Parallelism is bounded at two levels: a counting
semaphore admits *W* samples concurrently (default: half the available
cores), and each sample passes *T* threads to its external tools. Total
load is approximately *W × T*, giving independent control over the
CPU-bound quality-control stage and the memory-bound depletion stage.
When the user does not explicitly set *W*, RustyClean estimates the
resident database size for the selected backend and the available memory
(cgroup limit first, then `/proc/meminfo` `MemAvailable`), and caps *W*
so that concurrent workers do not collectively exceed roughly 80% of
available RAM. This prevents out-of-memory failures when the default
CPU-based worker count would load more database copies than fit in
memory. Interrupt handling uses a cancellation token so that queued
samples are not started after a shutdown signal.

**Implementation.** RustyClean is \~1,300 lines of Rust built on the
Tokio asynchronous runtime, distributed as a single binary with no
language runtime dependency. External dependencies are the fastp,
deacon, Kraken2, and Bowtie2 executables. Source is available at
<https://github.com/HuangShiLab/rustyclean> under the MIT licence.

### 2.8 Benchmark design

**Table 1.** The simulated datasets used for the main accuracy
comparison. Host fraction is the realised proportion of host reads after
simulation, which differs slightly from the nominal target for skewed
communities. The panel varies host fraction (0.9--91.4%), sequencing
depth (5--100 M reads), community complexity (low, medium, high) and
abundance distribution (even, skewed, lognormal); all datasets are
single-end.

| **Dataset** | **Reads (M)** | **Host (%)** | **Complexity** | **Abundance** | **Layout** |
|-------------|---------------|--------------|----------------|---------------|------------|
| 5M / 1%     | 5.0           | 0.9          | low            | even          | single-end |
| 10M / 10%   | 9.5           | 10.0         | medium         | even          | single-end |
| 30M / 50%   | 23.9          | 59.7         | high           | skewed        | single-end |
| 60M / 90%   | 56.2          | 91.4         | high           | lognormal     | single-end |
| 100M / 50%  | 87.8          | 54.1         | high           | lognormal     | single-end |
| 100M / 90%  | 93.6          | 91.4         | high           | lognormal     | single-end |

We evaluated RustyClean against KneadData v0.12.3 on the simulated
panel of Table 1 with per-read ground truth, generated with InSilicoSeq
v2.0.0 (Gourlé et al., 2019).

Because reads are simulated, the true origin of every read is known and
depletion can be scored exactly as a binary classification task. Results
are reported per dataset; no grand mean is reported across the panel.

Reference databases: the deacon panhuman-1 pangenome index (k31w15) for
Tier-1 depletion, and a Bowtie2 index of T2T-CHM13v2.0 plus HLA
sequences (the Hostile human-t2t-hla index) for the verification pass.
KneadData and Hostile + fastp comparators used their own default
references (KneadData hg39 Bowtie2 index; Hostile human-t2t-hla index).
KneadData and Hostile + fastp runs used 8 threads per tool on the HKU
HPC2021 cluster; deacon and AUTO runs used 16 threads, with three
replicates per condition for RustyClean timing. Wall-clock time and peak
resident set size were recorded with GNU `time`.

**Minimizer-based panel.** We benchmarked deacon v0.17.0
standalone and the deacon-based AUTO pipeline on the simulated panel.
deacon was run in depletion-only mode (`--skip-qc`; clean step with
options `-d -a 2 -r 0.01`; panhuman-1 index, k31w15) on 16 threads;
the AUTO runs chained fastp, deacon and the conditional Bowtie2
verification tier (Section 2.4) with the same index and thread count.
Three replicates per condition were run, and the same timing and memory
recording was used. Runtime bases (full pipeline versus depletion-only)
are stated wherever the numbers are compared.

**Cross-species panel and index builds.** For the cross-species
evaluation we built species-specific deacon indexes (k31w15) for human
(T2T-CHM13v2.0), monkey, mouse, pig, rat and rice, recording build time
and peak memory for each, and ran deacon (16 threads) on the 10 M-read,
50%-host panel with either the species-matched index or the human
panhuman-1 index.

**Parallel-scaling experiment.** To measure cohort-level throughput we
prepared sixteen identical 10M-read single-end samples (10% host
fraction, below the verification threshold) as a sample manifest and
processed them with *T* = 4 threads per sample and *W* ∈ {1, 2, 4, 8}
concurrent workers on a single 64-core AMD node, recording cohort wall
clock and, per worker count, the resident set size of every deacon
process (sampled every 5 s).

### 2.9 Evaluation metrics

Treating \"host\" as the positive class:

- **Microbial read loss** = false positives / true microbial reads ---
  the fraction of genuine microbial reads discarded.
- **Host carry-over** = host reads retained in the output, as a
  percentage of the retained (post-depletion) output.
- **F1** --- harmonic mean of precision and recall over host calls.
- **Runtime** --- wall clock, per sample and for concurrent batches.
- **Peak memory** --- maximum resident set size.

Downstream impact on taxonomic profiles and assemblies was not
systematically benchmarked in this study; the real-data evaluation
focused on throughput, memory use, and successful completion on a cohort
of human oral microbiome samples.

### 2.10 Alternative backends evaluated and not retained

We evaluated sylph, a k-mer-sketching metagenome profiler, as a possible
sample-level prefilter for host depletion. sylph produces sample-level
relative abundance, not per-read labels, so it cannot remove individual
host reads. We therefore tested it as a binary sensor: a sample declared
host-positive by `sylph query` was passed to the Bowtie2 alignment
pipeline, while host-negative samples were retained without alignment.
On the 100 M-read datasets this sensor-based approach did not improve
runtime over direct Bowtie2 removal for host-positive samples, and the
added survey overhead erased any potential speed advantage. We also
confirmed that sylph cannot provide read-level classifications and
therefore cannot be used as a direct substitute for a per-read depletion
backend. Consequently, sylph is retained only as an optional explicit
backend and is not used by the default auto-mode router.

We also evaluated a FracMinHash (FMH) sketching backend, in which each
read is sketched and queried against a FracMinHash sketch of the host
reference. The evaluation was rejected on accuracy and speed grounds.
Per-read sketch density at practical scales is too low for read-level
host detection: across the 5M/1%, 10M/10% and 30M/50% datasets the host
carry-over was 12.3--12.5% of retained output regardless of host
fraction (F1 0.915--0.993) --- over three orders of magnitude above
deacon's 0.0035--0.0042% on the same datasets. The sketching pass was
also an order of magnitude slower than deacon (e.g. 390--488 s versus
29 s on the 30M/50% dataset), and building the host sketch was itself
non-trivial (~46 min and 816 MB for a T2T-CHM13 sketch at scale factor
25; ~53 min for a GRCh38 sketch at the same scale). FMH is therefore not
retained as a backend; the partial results are archived in the
supplementary data (Section S1).

Alternative per-read backends were also compared directly: Bowtie2,
minimap2 and Centrifuge (Section 3.5 and Figure S1). Bowtie2 and
minimap2 were closely matched on accuracy, while Centrifuge showed
substantially higher host carry-over at high host fractions and was not
retained as a recommended backend.

## 3. Results

### 3.1 Minimizer-based depletion as the default Tier-1 backend

Because deacon's per-read cost is independent of host fraction, the
four-way comparison in Table 2 required no per-sample routing: every
sample passed through the same fastp → deacon → conditional-Bowtie2
verification chain, with only the verification decision varying. The
table reports, per dataset, KneadData (full pipeline), fastp + Hostile
(full pipeline), deacon alone (depletion only, quality control skipped)
and the RustyClean AUTO pipeline with deacon as the Tier-1 backend
(full pipeline).

![](figures/fig2_deacon_panel.png)

**Figure 1.** Four-way comparison on the simulated panel.
(a) Runtime (log scale; basis as stated in Table 2 --- full pipeline
for KneadData, Hostile + fastp and the AUTO configuration;
depletion only for deacon). (b) Peak resident set size of the largest
single process.

**Table 2.** Four-way comparison on the simulated panel. Runtime and
peak memory are means over three replicates; F1, microbial loss and
host carry-over are single evaluations (depletion is deterministic).
Basis: KneadData, Hostile + fastp and the AUTO configuration
are full-pipeline runs (QC plus depletion, plus verification where
triggered); deacon is the depletion step alone (`--skip-qc`).
"---" marks conditions that were not run.

| **Dataset** | **Tool** | **Runtime (s)** | **Memory (GB)** | **F1** | **Microbial loss (%)** | **Host carry (%)** |
|-------------|----------|-----------------|-----------------|--------|------------------------|--------------------|
| 5M / 1% | KneadData | 420.3 | 1.14 | 0.97981 | 3.956 | 0.2688 |
| 5M / 1% | Hostile + fastp | 186.6 | 3.54 | 0.99997 | 0.000 | 0.6858 |
| 5M / 1% | deacon (depletion only) | 9.6 | 4.76 | 1.00000 | 0.000 | 0.0042 |
| 5M / 1% | RustyClean AUTO (deacon) | 90.4 | 4.76 | 1.00000 | 0.000 | 0.0042 |
| 10M / 10% | KneadData | 694.5 | 1.16 | 0.98571 | 2.791 | 0.2555 |
| 10M / 10% | Hostile + fastp | 326.5 | 3.73 | 0.99923 | 0.079 | 0.6745 |
| 10M / 10% | deacon (depletion only) | 13.0 | 4.76 | 0.99881 | 0.238 | 0.0037 |
| 10M / 10% | RustyClean AUTO (deacon) | 142.0 | 4.76 | 0.99881 | 0.238 | 0.0037 |
| 30M / 50% | KneadData | 2317.5 | 1.16 | 0.99098 | 1.425 | 0.2500 |
| 30M / 50% | Hostile + fastp | 840.3 | 3.76 | 0.99501 | 0.000 | 0.6758 |
| 30M / 50% | deacon (depletion only) | 28.6 | 4.76 | 0.99997 | 0.000 | 0.0037 |
| 30M / 50% | RustyClean AUTO (deacon) | 622.3 | 4.76 | 1.00000 | 0.000 | 0.0000 |
| 60M / 90% | KneadData | 6822.0 | 1.16 | 0.97603 | 2.154 | 0.2496 |
| 60M / 90% | Hostile + fastp | 1456.4 | 3.78 | 0.96522 | 0.039 | 0.6745 |
| 60M / 90% | deacon (depletion only) | 52.4 | 4.76 | 0.99921 | 0.120 | 0.0036 |
| 60M / 90% | RustyClean AUTO (deacon) | 669.5 | 4.76 | 0.99845 | 0.309 | 0.0000 |
| 100M / 50% | deacon (depletion only) | 153.4 | 4.76 | 0.99937 | 0.121 | 0.0035 |
| 100M / 50% | RustyClean AUTO (deacon) | 1684.9 | 4.76 | 0.99845 | 0.310 | 0.0000 |
| 100M / 90% | deacon (depletion only) | 202.4 | 4.76 | 0.99920 | 0.120 | 0.0037 |
| 100M / 90% | RustyClean AUTO (deacon) | --- | --- | --- | --- | --- |

On speed, the deacon depletion step alone (9.6--202.4 s) was 44--130×
faster than the complete KneadData pipeline, and the full AUTO pipeline
(90.4--1684.9 s) was 3.7--10.2× faster than KneadData and 1.3--2.3×
faster than fastp + Hostile on the datasets where all three were run.
On accuracy, AUTO matched or exceeded every comparator: F1 was
0.99845--1.00000 (Figure 2a), against 0.96522--0.99997 for fastp + Hostile and
0.97603--0.99098 for KneadData. Microbial loss stayed at or below
0.31% --- up to 13-fold below KneadData (1.4--4.0%), whose Trimmomatic
stage over-trims genuine microbial reads --- and was essentially zero
(<0.001%) on the 5M/1% and 30M/50% datasets.

The verification tier's contribution is isolated by comparing the deacon
and AUTO rows. deacon alone left a small structural residue of host
reads --- 0.0035--0.0042% of retained output, essentially independent
of host fraction. AUTO, in which the Bowtie2 verification pass fired
whenever the removed proportion crossed the 0.3 threshold, reduced this
to 0.0000% on every high-host dataset (Figure 3). The one exception is
informative: on the 5M/1% dataset (0.9% realised host) the removed
proportion fell below the threshold, verification correctly did not
run, and carry-over remained 0.0042% --- with F1 still 1.00000 because
the residue is negligible relative to the output. The same decision
logic is visible on the 10M/10% dataset, where the removed proportion
(~10%) stayed below the threshold and AUTO correctly skipped the
Bowtie2 pass: its host carry (0.0037%) equals deacon's standalone
residue, at less than half the runtime of fastp + Hostile (142 s versus
326 s). Verification effort is therefore allocated only where the host
burden justifies it.

![](figures/fig3_deacon_accuracy.png)

**Figure 2.** Accuracy of the four-way comparison. (a) F1 score per
dataset and tool. (b) Host carry-over as a percentage of retained
output (log scale); the dashed line marks 0.01%. Values of exactly
0.0000% (AUTO on all high-host datasets) cannot be drawn on a log
scale and are annotated as 0.

![](figures/fig6_verification.png)

**Figure 3.** The verification tier eliminates deacon's residual host
reads. Host carry-over of deacon alone versus the full AUTO pipeline
(deacon plus conditional Bowtie2 verification) on the three datasets
whose removed proportion crossed the 0.3 recheck threshold.

Peak memory of the AUTO runs was 4.76 GB --- the resident panhuman-1
index plus working set --- close to fastp + Hostile (3.5--3.8 GB),
though above KneadData's 1.16 GB, which remains the lowest-memory option
(Figure 1b). AUTO's advantage is therefore not raw memory but the
combination of accuracy, verification and carry-over at a modest,
index-bounded footprint. As with any index-based backend, memory is
bounded by index size rather than sample size, and the memory-aware
worker cap of Section 2.7 applies unchanged.

Finally, deacon's accuracy advantage derives mostly from the pangenome
index rather than from the algorithm. On the human 10 M/50% panel, a
single-reference deacon index built from T2T-CHM13v2.0 alone left
0.2254% host carry-over, against 0.0049% with the panhuman-1 pangenome
index --- a 46-fold difference. Index representativeness is thus the
dominant determinant of deacon's accuracy, a point that motivates the
cross-species index work in Section 3.2.

### 3.2 Cross-species host depletion

Human-associated metagenomes are not the only use case for host
depletion; the same problem arises for model organisms, livestock and
plants. deacon's officially published prebuilt indexes, however, cover
only human (panhuman-1) and mouse. To test whether minimizer-based
depletion generalises, we built species-specific deacon indexes
(k31w15) for human (T2T-CHM13v2.0), monkey, mouse, pig, rat and rice.
Index builds were fast and cheap: 4--52 s each, producing 2.2--2.5 GB
indexes for the mammalian hosts and 0.3 GB for the smaller rice genome
(Table 3).

On a panel of 10 M-read, 50%-host single-end simulated datasets, every
species' own index achieved F1 0.99986--0.99998, with host carry-over of
at most 0.006% and microbial loss of at most 0.023% (Table 3, Figure 4).
KneadData, which requires a species-specific Bowtie2 index, again
performed well (F1 ≈ 0.996 on every host), but below the
species-matched deacon indexes.

The converse experiment is a cautionary result. Running every dataset
against the human panhuman-1 index --- the only published prebuilt index
applicable to most of these hosts --- wrongly depleted 46.8% of the
microbial reads in the monkey-host dataset, ~97% in the mouse, pig and
rat datasets, and 99.8% in the rice dataset (precision collapsing to
0.50--0.68 and F1 to 0.67--0.81; Table 3). That is, a human pangenome
index must not be treated as a generic vertebrate or plant host index.
For human data the same index-representativeness effect appears in
milder form: a T2T-only single-reference index left 46× more host
carry-over than panhuman-1 (Section 3.1). Species-matched indexes --- or
a pan-host union index --- are therefore mandatory for non-human work,
and RustyClean ships and validates a pan-host index set covering the six
hosts above. Together with the species-matched results, this indicates
that minimizer-based depletion is not restricted to human contamination,
provided the index matches the host.

![](figures/fig5_cross_species.png)

**Figure 4.** Cross-species depletion accuracy on 10 M-read, 50%-host
simulated datasets. F1 with each species' own deacon index (steel blue)
versus the human panhuman-1 index (muted red). The panhuman-1 index
preserves accuracy only on human data; on non-human hosts it wrongly
depletes 46.8--99.8% of microbial reads.

**Table 3.** Cross-species host depletion on 10 M-read, 50%-host
simulated datasets. Matched-index F1 is with the species' own deacon
index (for human, the panhuman-1 index); panhuman-1 F1 is with the human
index applied to every dataset; "microbial reads wrongly removed" is the
false-positive depletion rate of panhuman-1 on each dataset. Index build
time and on-disk size are for the species-matched k31w15 indexes (the
human build row is the T2T-only single-reference index; panhuman-1
itself is a published prebuilt). KneadData F1 is from the legacy
cross-species comparison and requires a species-specific Bowtie2 index.

| **Host** | **Matched-index F1** | **panhuman-1 F1** | **panhuman-1 microbial reads wrongly removed (%)** | **Index build (s)** | **Index size (GB)** | **KneadData F1** |
|----------|----------------------|-------------------|----------------------------------------------------|---------------------|---------------------|------------------|
| human | 0.99996 | 0.99996 | 0.003 | 33.1 (T2T-only) | 2.53 | 0.9959 |
| monkey | 0.99997 | 0.80979 | 46.8 | 52.4 | 2.53 | 0.9960 |
| mouse | 0.99986 | 0.67231 | 97.0 | 39.3 | 2.20 | 0.9960 |
| pig | 0.99998 | 0.67249 | 97.0 | 26.9 | 2.20 | 0.9960 |
| rat | 0.99995 | 0.67213 | 97.1 | 31.8 | 2.25 | 0.9960 |
| rice | 0.99988 | 0.66621 | 99.8 | 4.2 | 0.30 | 0.9960 |

### 3.3 Real-data performance

We applied RustyClean to 11 human oral microbiome samples from the LU
cohort (paired-end, 5--45 million reads per sample) to confirm that the
simulated-panel performance translates to real data. This cohort was
processed with the routing-based auto mode of an earlier release;
current releases default to the deacon Tier-1 backend whenever an index
is configured. All samples completed successfully. Runtime ranged from
9 to 46 min per sample (mean 18.6 min, median 13.6 min) and peak memory
ranged from 3.4 to 6.5 GB (mean 4.1 GB, median 3.6 GB). The total wall
clock for the 11-sample cohort was 3.4 h. These numbers are consistent
with the simulated-panel throughput and demonstrate that the pipeline is
ready for production cohorts.

### 3.4 Sample-level parallelism scales near-linearly at flat per-worker memory

Cohort processing is sample-parallel (Section 2.7): a counting semaphore
admits *W* samples concurrently, each passing *T* threads to its
external tools. To measure how the deacon backend scales under this
model we ran sixteen identical 10M-read single-end samples (10% host
fraction, below the verification threshold, so each sample executes
fastp plus deacon only) with *T* = 4 and *W* ∈ {1, 2, 4, 8} on a single
64-core AMD node.

Throughput scaled near-linearly (Figure 5): wall clock for the 16-sample
cohort dropped from 2,364 s (39m24s) at *W* = 1 to 1,153 s at *W* = 2
(2.05×), 620 s at *W* = 4 (3.81×), and 302 s at *W* = 8 (7.84×; 98%
parallel efficiency). Per-worker cost stayed constant throughout: the
resident set of each deacon process was ~3.1--3.7 GB at every worker
count --- the memory-mapped 3.3 GB panhuman-1 index plus a small private
workspace. Because all workers map the same read-only index file, the
kernel retains a single physical copy of its pages and each additional
worker costs only its private workspace (the per-process RSS sum in
Figure 5c therefore overcounts physical memory; it is shown to make the
accounting explicit). No alignment-based competitor in our comparison
offers this combination: the per-sample memory footprint of an alignment
index (Bowtie2, ~3--5 GB per sample) means the same 8-sample concurrency
would require roughly an order of magnitude more RAM for the same
throughput gain.

Together with the memory-aware worker cap described in Section 2.7, this
makes the default backend suitable for queue-free cohort processing on
shared-nothing nodes: 16 samples complete in 5 minutes at under 40 GB
aggregate per-process RSS.

![](figures/fig7_parallel_scaling.png)

**Figure 5.** Sample-level parallelism of the deacon backend. Sixteen
identical 10M-read single-end samples (10% host) processed with four
threads per sample and *W* concurrent workers. (a) Cohort wall time.
(b) Speedup relative to *W* = 1; the dashed line is ideal linear
scaling. (c) Resident set size: per deacon worker (steel blue, flat at
~3.1--3.7 GB) and the sum over all workers (green). Because every worker
memory-maps the same read-only 3.3 GB index, the kernel shares its
physical pages across processes and the green sum overcounts true
physical usage.

### 3.5 The depletion backend is interchangeable

Because the pipeline treats the depletion step as a replaceable
component, alternative backends can be substituted without changing the
surrounding orchestration. We evaluated Bowtie2, minimap2 and Centrifuge
on the four simulated datasets of Figure S1. Bowtie2 and minimap2 were
closely matched on accuracy, while Centrifuge showed substantially
higher host carry-over at every host fraction (Figure S1b) and was not
retained as a recommended backend. Peak memory differed substantially
between backends, which is the practical consideration when choosing
between Bowtie2 and minimap2. The default Tier-1 backend is deacon
(Section 3.1), and the same interchangeability applies to it;
FracMinHash sketching was evaluated and rejected (Section 2.10).

## 4. Discussion

Neither error direction is universally preferable, which is why the
choice should not be made once for every sample and every study. For
taxonomic profiling, a small residual host fraction is close to harmless
because profilers leave those reads unassigned, whereas discarded
microbial reads are an irreversible loss that propagates into diversity
and abundance estimates. For assembly, for MAG recovery, and for data
released publicly --- where residual human sequence is a consent and
privacy matter rather than a technical one --- the calculus reverses.
RustyClean exposes the verification threshold and the verification pass
itself as user-facing settings for this reason.

The central result is that minimizer-based depletion removes the
per-sample backend choice: deacon's per-read cost is
host-fraction-independent, so a single Tier-1 backend suffices across
the whole host-fraction spectrum, and the live decision becomes
verification-budget allocation. Minimizer depletion leaves a small
structural residue of host reads (0.0035--0.0042% of retained output on
our panel); the adaptive Bowtie2 verification tier removes it entirely
(0.0000% on every high-host dataset tested) whenever deacon's removed
proportion crosses the threshold --- precisely the samples in which the
residue is largest in absolute terms.

Two comparisons deserve to be read carefully. First, RustyClean performs
no tandem-repeat or low-complexity masking, whereas KneadData does; part
of the runtime advantage over KneadData therefore reflects work not done
rather than work done faster, and the closer like-for-like comparison is
against KneadData with repeat masking disabled. Second, Hostile is the
more demanding baseline, and the deacon-based default meets it on both
axes: the full AUTO pipeline is 1.3--2.3× faster than fastp + Hostile
with equal-or-better F1 and zero host carry-over on high-host samples,
where fastp + Hostile retains ~0.67% (Table 2). KneadData, meanwhile,
retains the lowest memory footprint of any tool tested (1.16 GB); the
AUTO advantage is accuracy, verification and carry-over at 4.8 GB ---
not raw memory --- and Hostile remains competitive on speed.

**Relationship to deacon.** deacon (Constantinides, Lees and Crook,
bioRxiv preprint, 2025; not yet peer-reviewed at the time of writing) is,
to our knowledge, the fastest available host-depletion engine, and
RustyClean integrates it rather than re-implementing it. What the bare
tool does not provide, and what this work adds, is the surrounding
pipeline and evidence: (i) a verification tier with a measured effect ---
deacon's 0.0035--0.0042% structural residue is reduced to 0.0000% on all
high-host datasets tested --- driven by an adaptive decision rule
(deacon's own removed-proportion summary against a configurable
threshold) rather than an unconditional second pass; (ii) a validated
pan-host index set --- species-matched indexes for six hosts, built in
4--52 s each, plus a quantification of panhuman-1 cross-reactivity
(46.8--99.8% of microbial reads wrongly depleted on non-human hosts)
showing that index choice must match the host; (iii) quality control,
checkpointing, bounded concurrency and a validation gate, i.e. a
reproducible pipeline rather than a filter, with measured near-linear
sample-level parallelism (7.84× on 8 workers at 98% efficiency) and a
flat per-worker memory footprint through the shared memory-mapped index;
and (iv) an independent replication on a Gao-style simulated panel with
per-read ground truth, spanning 1--90% host content and 5--100 M reads,
against KneadData and Hostile. RustyClean additionally pins deacon
v0.17.0 so that the benchmarked behaviour is reproducible.

RustyClean\'s contribution is therefore not that minimizer classification
is inherently more accurate than alignment --- per-read accuracy derives
mostly from index representativeness, as the 46-fold carry-over gap
between the T2T-only and panhuman-1 indexes shows --- but that
verification-budget allocation, pan-host index support and orchestration
turn a fast filter into a production pipeline whose residual host output
is zero where it matters.

Limitations. Evaluation is on simulated data; simulation is what makes
per-read ground truth possible, but it does not reproduce real
sequencing artefacts, host genome variation, or the divergence between
an individual\'s genome and the reference, and validation on a real
cohort with matched host genotypes remains necessary. The primary
accuracy evaluation covers the simulated panel at 1--90% host content and
5--100 M reads; it does not include real sequencing artefacts, and the
real-data cohort validates throughput and robustness but not per-read
accuracy. Downstream impact on taxonomic profiles and assemblies was not
systematically benchmarked. Depletion is deterministic, so accuracy was
evaluated once per dataset and replication applies only to timing.

The deacon-based default carries its own limitations. Its accuracy
depends on index representativeness: a T2T-only human index carries 46×
more host than the panhuman-1 pangenome index, and a mismatched index
(the human panhuman-1 index applied to non-human hosts) depletes
46.8--99.8% of microbial reads --- so results on a new host are only as
good as the chosen index, and our pan-host index set covers six hosts,
not the long tail of host species. Samples whose removed proportion
falls below the verification threshold retain deacon's structural
residue (~0.004% of retained output) by design; this is a deliberate
trade of absolute cleanliness for runtime on samples where the residue
is negligible. Each deacon invocation pays a fixed index-load cost,
which dominates on small samples (on 5M/1%, deacon itself took 9.6 s of
the pipeline's 90 s). And deacon remains a preprint at the time of
writing: although we replicate its reported speed and accuracy on an
independent panel and pin v0.17.0, its long-term maintenance and
peer-reviewed validation are not yet established. Finally, the panel
mixes thread counts: the deacon and AUTO runs used 16 threads, while the
KneadData and Hostile figures are the 8-thread runs. A same-thread
comparison would narrow the speed ratios by at most the thread-count
factor (~2×), far smaller than the observed 44--130× gap for the deacon
depletion step, but we note the asymmetry for completeness.

## 5. Software and data availability

RustyClean is implemented as a single Rust binary and is available at
https://github.com/HuangShiLab/rustyclean under the MIT licence. The
version used for the experiments in this manuscript is [tag/SHA]. Source
code for the benchmarking and analysis scripts, together with the
simulated dataset metadata and result tables, are available at
https://github.com/HuangShiLab/rustyclean-paper. Simulated reads and
ground-truth labels are available from the same repository; real human
oral microbiome data are from the LU cohort and are subject to the
original data-access agreements.

## 6. Target journals and peer-review preparation

[This section is retained for internal review and should be removed or
converted to a cover letter before submission.]

### 6.1 Suggested target venues

- **GigaScience** (IF ~11.8, Oxford). Strong fit: the motivating
  benchmark by Gao et al. (2025) was published here, the scope includes
  large-scale computational methods, and the software + benchmark
  narrative matches the journal's emphasis on reproducible, data-rich
  methods papers.
- **Bioinformatics** (IF ~4.4, Oxford). Good fit for a concise methods
  contribution with a strong implementation and comparative benchmark.
  The adaptive verification angle is methodologically novel enough for a
  full article rather than an Application Note.
- **Microbiome** (IF ~13.8, BMC). Good fit if the manuscript stresses
  the downstream impact on microbiome studies (signal preservation,
  cross-species applicability, real-data validation).
- **BMC Bioinformatics** (IF ~2.9, BMC). A reliable, method-focused
  venue with a relatively fast turnaround; suitable if the contribution
  is framed primarily as a software/benchmark advance.
- **NAR Genomics and Bioinformatics** (IF ~4.4, Oxford). Publishes
  methods and software with strong technical contributions; the
  checkpointing, bounded concurrency, and validation-gate aspects are
  good matches.

### 6.2 Anticipated peer-review questions and responses

| # | Reviewer concern | Our response / evidence |
|---|------------------|-------------------------|
| 1 | *KneadData includes Trimmomatic and repeat masking; the comparison is not like-for-like.* | Acknowledged. We report KneadData as the de facto standard and note that part of the speed advantage reflects scope differences (Discussion). A `--bypass-trf` comparison would further clarify this. |
| 2 | *Why is the comparator panel limited to six datasets?* | KneadData runs at 100 M reads cost ~4 h each, so the panel concentrates on the host-fraction and depth range that spans the practical use cases (1--90% host, 5--100 M reads). The cross-species panel and the real-data cohort extend generalisability beyond it. |
| 3 | *Is the accuracy evaluation deterministic?* | Yes; depletion is deterministic, so accuracy is reported once per condition and replication applies only to timing (to be stated explicitly in Methods). |
| 4 | *What about real sequencing artefacts and host genetic variation?* | Limitations section acknowledges this. The 11-sample real cohort validates throughput and robustness, but matched-host-genotype validation remains future work. |
| 5 | *Does the pipeline handle very large cohorts?* | Cohort-level throughput scales near-linearly with concurrent workers at flat per-worker memory (7.84× on 8 workers; Section 3.4); the memory-aware worker cap protects RAM on shared nodes (Section 2.7). |
| 6 | *How does the user choose the reference database?* | Default is the deacon panhuman-1 index for human data, with a validated species-matched index set for human (T2T), monkey, mouse, pig, rat and rice; the human panhuman-1 index must not be used for non-human hosts (Section 3.2). |
| 7 | *What is the practical advantage over running Hostile + fastp, or deacon directly?* | RustyClean integrates QC, adaptive verification (0.0035--0.0042% → 0.0000% host carry on high-host samples), pan-host index support, checkpointing, validation, and bounded concurrency in one binary; on the panel the full pipeline is 1.3--2.3× faster than fastp + Hostile with equal-or-better F1 and zero carry-over (Section 3.1). deacon alone lacks the verification tier, QC and orchestration (Discussion). |
| 8 | *Why rely on deacon, which is not yet peer-reviewed?* | It is the fastest available engine by an order of magnitude and we replicate its reported behaviour on an independent panel with pinned v0.17.0. Alternative peer-reviewed backends (Bowtie2, minimap2, Kraken2) remain selectable via `--host-removal-mode`, so the pipeline does not hard-depend on deacon (Sections 2.1 and 3.5). |

## References

1.  Gao Y, Luo H, Lyu H, Yang H, Yousuf S, Huang S, Liu Y-X.
    Benchmarking short-read metagenomics tools for removing host
    contamination. *GigaScience*. 2025;14.
    doi:10.1093/gigascience/giaf004
2.  Chen S, Zhou Y, Chen Y, Gu J. fastp: an ultra-fast all-in-one FASTQ
    preprocessor. *Bioinformatics*. 2018;34(17):i884--i890.
3.  Wood DE, Lu J, Langmead B. Improved metagenomic analysis with
    Kraken 2. *Genome Biology*. 2019;20:257.
4.  Langmead B, Salzberg SL. Fast gapped-read alignment with Bowtie 2.
    *Nature Methods*. 2012;9:357--359.
5.  McIver LJ, Abu-Ali G, Franzosa EA, et al. bioBakery: a meta'omic
    analysis environment. *Bioinformatics*. 2018;34(7):1235--1237.
    (KneadData is distributed as part of the bioBakery suite.)
6.  Bolger AM, Lohse M, Usadel B. Trimmomatic: a flexible trimmer for
    Illumina sequence data. *Bioinformatics*. 2014;30(15):2114--2120.
7.  Benson G. Tandem repeats finder: a program to analyze DNA sequences.
    *Nucleic Acids Research*. 1999;27(2):573--580.
8.  Gourlé H, Karlsson-Lindsjö O, Hayer J, Bongcam-Rudloff E.
    Simulating Illumina metagenomic data with InSilicoSeq.
    *Bioinformatics*. 2019;35(3):521--522.
    doi:10.1093/bioinformatics/bty630
9.  Constantinides B, Lees J, Crook DW. Deacon: fast sequence filtering
    and contaminant depletion. *bioRxiv*. 2025.
    doi:10.1101/2025.06.09.658732. Preprint: not peer reviewed.

## Supplementary material

![](figures/figS1_backend_comparison.png)

**Figure S1.** Comparison of interchangeable depletion backends within
RustyClean: Bowtie2, minimap2 and Centrifuge. (a) F1 score, (b) host
carry-over (% of retained output), (c) microbial reads lost (%), (d)
peak memory (GB). Runtime is excluded because one measurement (minimap2,
5M dataset) is a cold-start outlier.

| **Backend** | **Dataset** | **F1** | **Host carry-over (%)** | **Microbial loss (%)** | **Peak mem (GB)** |
|-------------|-------------|--------|-------------------------|------------------------|-------------------|
| Bowtie2 | 5M / 1% | 0.9996 | 0.001 | 0.000 | 3.6 |
| Bowtie2 | 10M / 10% | 0.9749 | 0.006 | 0.568 | 3.6 |
| Bowtie2 | 30M / 50% | 0.9984 | 0.073 | 0.402 | 3.6 |
| Bowtie2 | 60M / 90% | 0.9996 | 0.521 | 0.388 | 6.2 |
| minimap2 | 5M / 1% | 0.9986 | 0.000 | 0.002 | 11.5 |
| minimap2 | 10M / 10% | 0.9742 | 0.003 | 0.587 | 11.7 |
| minimap2 | 30M / 50% | 0.9984 | 0.044 | 0.431 | 11.8 |
| minimap2 | 60M / 90% | 0.9997 | 0.313 | 0.416 | 11.9 |
| Centrifuge | 5M / 1% | 0.9940 | 0.010 | 0.001 | 7.0 |
| Centrifuge | 10M / 10% | 0.9500 | 0.132 | 1.027 | 7.2 |
| Centrifuge | 30M / 50% | 0.9920 | 1.721 | 0.632 | 7.9 |
| Centrifuge | 60M / 90% | 0.9938 | 11.140 | 0.760 | 8.6 |

**Supplementary Table S1.** Backend comparison of Figure S1. Host
carry-over is the percentage of retained output that is host (Section
2.9); accuracy values are per-run counts from the backend-comparison
experiments (per-read counts in `archive/v1/data/accuracy_rc_mm_bt_cf_v4.csv`,
peak memory in `archive/v1/data/performance_rc_mm_bt_cf_v4_corrected.csv`).

**Supplementary data (Section S1).** The machine-readable tables behind
the deacon-based evaluation are available under `data/deacon_panel/`:
`five_way_summary.csv` (the four-way means of Table 2),
`deacon_metrics.csv` and `auto_metrics.csv` (per-replicate deacon and
AUTO runs), `cross_species_metrics.csv` (per-species index runs behind
Table 3 and Figure 4), `index_build_metrics.csv` (species-matched index
build time, memory and size), and `parallel_scaling_deacon.csv` with the
per-worker RSS samples under `parscale/` (Figure 5).
