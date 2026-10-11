# RustyClean: minimizer-based host depletion with adaptive alignment verification for short-read metagenomics

**Authors:** Yufeng Zhang, Jing-Yi Zhang, Shi Huang\*
**Affiliation:** Faculty of Dentistry, The University of Hong Kong, Hong Kong SAR, China **Correspondence:** yfz96@connect.hku.hk

## Abstract

Computational depletion of host DNA is commonly applied before
short-read metagenomic profiling, assembly and metagenome-assembled
genome recovery because residual host reads can distort downstream
analyses. Alignment-based depletion may discard genuine microbial reads,
whereas k-mer classification can retain host reads. We present
RustyClean, a two-tier host-depletion pipeline comprising fastp quality
control, minimizer-based depletion with Deacon (a preprint tool at the
time of writing) and conditional Bowtie2 verification triggered when
Deacon reports that at least 0.3 of input reads were removed. On six
single-end simulated libraries with per-read ground truth (realised host
content 0.9--91.4%; 5--100 million reads), RustyClean AUTO had F1
\geq 0.998 on the four high-host libraries. It discarded at most 0.310%
of true microbial reads and retained at most 0.000011% of true host
reads after verification (at most nine host reads per library); Deacon
alone retained 0.0035--0.0037% of true host reads before verification.
RustyClean used 4.54 GiB peak process memory. The main six-library panel
was not a like-for-like runtime benchmark: Deacon and AUTO used 16
threads, whereas KneadData and fastp + Hostile used 8 threads, and
KneadData also performed additional trimming, repeat masking and
identifier reformatting. In that scope panel, AUTO ran in 90--2,397 s
versus 420--8,271 s for KneadData. In a more controlled 16-thread,
same-node paired comparison on the largest high-host library, optimized
RustyClean required 428 \pm 76 s versus 1,032 \pm 37 s for fastp +
Hostile and was faster in all three replicates (per-replicate speedup
2.12--3.01\times). A separate unpaired I/O-optimized panel gave
all-replicate speedups of 1.99--6.36\times relative to historical
Hostile runs. In one unreplicated 16-sample scaling run, eight workers
reduced wall time 7.84\times; per-process RSS was approximately 4.5 GiB,
while sampled aggregate RSS depended on the number of active workers. In
a six-host simulated proof of concept, species-matched Deacon indexes
achieved F1 0.99986--0.99998, whereas the human panhuman-1 index left
46.8--99.8% of true non-human host reads in the output. These results
support species-matched indexes for the tested non-human hosts
but do not establish a general pan-host index. The adaptive threshold,
validation gate, paired-end accuracy and downstream assembly effects
require further validation. The benchmark scripts and result tables are
available at https://github.com/HuangShiLab/rustyclean-paper; RustyClean
is available under the MIT licence at
https://github.com/HuangShiLab/rustyclean.

**Keywords:** metagenomics, host depletion, decontamination,
minimizers, Deacon, Bowtie2, Rust

## 1. Introduction

Shotgun metagenomic sequencing of host-associated samples returns a
mixture of microbial and host DNA. The host fraction varies by body
site: stool libraries are often 1--2% human, whereas saliva, dental
plaque, skin and biopsy libraries can be 50--90% human or higher.
Because host reads consume sequencing budget and can distort downstream
estimates, host depletion is commonly applied before taxonomic
profiling, assembly or metagenome-assembled genome (MAG) recovery.

Depletion is a binary classification problem over reads and can fail in
two directions. A **microbial false removal** discards a genuine
microbial read, irreversibly removing signal that would otherwise
contribute to diversity, abundance, assembly or binning. A **host false
retention** leaves host sequence in the output. This may have little
effect on profiling when profilers leave reads unassigned, but it can
contaminate assemblies and raises consent and privacy concerns for
human-data sharing.

These errors are not interchangeable. Our group\'s benchmark of six
host-removal tools across human and rice datasets reported higher false
positive rates for alignment-based methods (Bowtie2, BWA, KneadData) and
higher false negative rates for k-mer classification methods (Kraken2,
KrakenUniq, KMCP) \[Gao et al. 2025\]. The same study reported a
substantial Kraken2 efficiency advantage, especially at 90% host
contamination.

Deacon --- a minimizer-based sequence filter evaluated against a
pangenome index (Constantinides, Lees and Crook, bioRxiv preprint, 2025;
not yet peer-reviewed at the time of writing) --- was reported to
combine near-alignment accuracy with classification-grade speed. Its
per-read cost was reported to be approximately independent of host
fraction. If that behaviour replicates, per-sample routing between
alignment and classification backends becomes less important, but the
published tool remains a bare filter: it does not provide quality
control, cohort orchestration, checkpointing, a verification tier or a
policy for allocating verification cost.

This paper therefore addresses integration rather than invention of a
new filter. RustyClean uses Deacon as the default Tier-1 backend behind
quality control and orchestration. It parses Deacon\'s summary JSON and,
when the reported removed proportion (`seqs_removed_proportion`) reaches
`--recheck-threshold` (default 0.3), re-screens retained reads with
Bowtie2; below the threshold it accepts the Deacon output. The per-sample
decision is thus recast from backend routing to verification allocation.
The 0.3 value is an empirical engineering default; this study did not
perform a threshold sweep or held-out selection, so we do not claim that
it is optimal.

We also evaluate operational features, but distinguish implementation
from validated production claims. RustyClean implements per-stage
checkpointing with input fingerprints, bounded two-level concurrency and
configurable output checks. Their fault tolerance and sensitivity are
not exhaustively tested here.

**Contributions.**

1.  An integration of Deacon with conditional Bowtie2 verification and
    orchestration, with per-read accuracy and runtime measurements on a
    simulated panel and a controlled paired Hostile comparison.
2.  A six-host simulated proof of concept showing that index choice can
    dominate Deacon accuracy and that the tested human pangenome index
    fails to remove most non-human host reads.
3.  A transparent account of benchmark scope, including unequal thread
    allocation in the main panel, unpaired optimized comparisons,
    single-run scaling experiments, and missing threshold and validation
    sensitivity analyses.
4.  Reproducibility artefacts for result tables and analysis scripts,
    with explicit statements of materials that are not redistributed or
    whose provenance is incomplete.

## 2. Methods

### 2.1 Pipeline overview

In the default configuration (AUTO mode with a Deacon index supplied),
RustyClean processes each sample through four stages:

1.  **Quality control**: adapter detection, quality trimming and
    filtering with fastp.
2.  **Tier-1 host depletion**: minimizer-based depletion with Deacon
    against a user-supplied pangenome index.
3.  **Conditional verification**: if Deacon's summary JSON reports
    `seqs_removed_proportion >= --recheck-threshold` (default 0.3),
    retained reads are re-screened with Bowtie2. Otherwise the Deacon
    output is final.
4.  **Validation and finalisation**: configurable output checks before
    promotion (Section 2.6).

The software accepts individual samples or a tab-separated manifest and
detects single-end and paired-end layouts. The primary accuracy and
runtime panel reported here is single-end; paired-end operation is an
implementation capability but was not independently accuracy-benchmarked
in this study. Alternative depletion backends were benchmarked separately
(Sections 2.10 and 3.5), but the streamlined production CLI exposes only
the default AUTO pipeline and a Deacon-only benchmarking mode.

### 2.2 Quality control

Reads are processed with fastp (Chen et al. 2018), configured by default
for automatic adapter detection in paired-end mode
(`--detect_adapter_for_pe`), sliding-window trimming from both ends
(`--cut_front`, `--cut_tail`), Q20 qualified bases and a minimum
retained length of 50 bp. Parameters are exposed through a TOML
configuration file. fastp emits a JSON report, which RustyClean parses
into input/output read counts, Q20/Q30 rates, GC content, adapter-trimmed
reads and reads discarded for length or quality.

Unlike KneadData, RustyClean does not perform tandem-repeat masking.
This is a scope difference rather than an identical implementation with
one step disabled. It is therefore treated as a confounder in the
KneadData runtime interpretation (Section 3.1).

### 2.3 Minimizer-based depletion with Deacon

The default Tier-1 backend is Deacon (Constantinides, Lees and Crook,
bioRxiv preprint, 2025; not peer reviewed at the time of writing),
v0.17.0. RustyClean invokes the Deacon clean step with `-d -a 2 -r
0.01` on quality-controlled reads, or on raw reads in `--skip-qc`
depletion-only benchmarking. It parses the summary JSON, including
removed read count and `seqs_removed_proportion`. For human data the
default index is the published panhuman-1 pangenome index (k31w15;
approximately 3.3 GB on disk). Users may supply another Deacon index.
Species-matched indexes for six hosts are a proof of concept, not a
validated universal pan-host index (Section 3.2).

### 2.4 Adaptive verification-budget allocation

When a Deacon index is configured, RustyClean does not route between
Tier-1 backends. It decides only whether to spend verification budget.
If `seqs_removed_proportion` is at least `--recheck-threshold`
(default 0.3), retained reads are re-screened with Bowtie2; otherwise
they are accepted. The rationale is that a high removed proportion
indicates a large host pool and a smaller retained set, whereas a low
removed proportion leaves most reads retained. This rule was evaluated
qualitatively on only six libraries. No threshold sweep, held-out
selection or boundary analysis was performed for the Deacon-based rule,
so 0.3 should be regarded as a configurable engineering default rather
than an optimised or statistically validated cutoff. Deacon's cost
versus host fraction was not isolated experimentally in this panel
because depth and community composition co-varied with host fraction.

### 2.5 Bowtie2 verification pass

Deacon left 0.0035--0.0037% of true host reads in the output on the
simulated panel before verification. In AUTO, retained reads are aligned
against a host Bowtie2 index and aligned reads are removed. Reads already
removed by Deacon are not realigned. The pass can be disabled with
`--no-bowtie2-recheck`. Its cost depends on the size of the retained
set, but the present panel does not establish a general worst-case bound
across host fractions, layouts or index types.

### 2.6 Validation gate

Before promotion, RustyClean checks that each configured output exists
and exceeds a configurable minimum size, and it can reject a sample when
an internal contamination estimate exceeds a configurable maximum. This
gate is an operational safeguard against missing, truncated or obviously
misconfigured outputs. It is not a per-read accuracy measurement and was
not sensitivity-tested or fault-injection-tested in this study. We
therefore do not claim that it is equivalent to independent validation
or that no other pipeline implements a comparable check.

### 2.7 Orchestration and implementation

**Stage machine.** Each sample has an ordered stage record (`Pending`,
`FastpRunning`, `FastpComplete`, `DepletionRunning`,
`DepletionComplete`, `Validating`, then `Completed` or `Failed`). On
resume, execution restarts after the last recorded completed stage.

**Checkpointing.** Per-sample state is serialised as versioned JSON and
written atomically. Each checkpoint carries an xxHash3 fingerprint over
selected input file metadata. This metadata fingerprint is not a
cryptographic content digest; changes that leave the hashed metadata
unchanged will not invalidate a checkpoint. The benchmarked implementation
and its exact hash fields are identified in the repository rather than
restated here.

**Concurrency.** A semaphore admits *W* samples and each sample passes
*T* threads to external tools. If *W* is not set, the implementation
uses an available-core heuristic and estimates resident database size
and available memory (cgroup limit first, then `/proc/meminfo`
`MemAvailable`) to cap concurrent database copies near 80% of available
RAM. Exact behaviour depends on platform and configuration; this memory
capping was not subjected to controlled fault tests here.

**Implementation.** RustyClean is a Rust orchestrator distributed as a
single binary, but it is not standalone: it invokes fastp, Deacon,
Bowtie2 and samtools. Tool installation and version pinning are part of
the reproduction environment, not bundled by the binary itself.

### 2.8 Benchmark design

**Table 1.** The simulated datasets used for the main accuracy
comparison. Host fraction is the realised proportion after simulation
and differs from the nominal target for skewed communities. All primary
libraries are single-end.

| **Dataset** | **Reads (M)** | **Host (%)** | **Complexity** | **Abundance** | **Layout** |
|-------------|---------------|--------------|----------------|---------------|------------|
| 5M / 1%     | 5.0           | 0.9          | low            | even          | single-end |
| 10M / 10%   | 9.5           | 10.0         | medium         | even          | single-end |
| 30M / 50%   | 23.9          | 59.7         | high           | skewed        | single-end |
| 60M / 90%   | 56.2          | 91.4         | high           | lognormal     | single-end |
| 100M / 50%  | 87.8          | 54.1         | high           | lognormal     | single-end |
| 100M / 90%  | 93.6          | 91.4         | high           | lognormal     | single-end |

Datasets were generated with InSilicoSeq v2.0.0 (Gourlé et al. 2019).
The repository provides dataset names and result tables, but the raw
simulated FASTQ files, ground-truth label files, random seeds, read
length/error-profile configuration and microbial genome/accession list
are not redistributed in the current repository. Complete
machine-readable generation metadata is therefore an outstanding
reproducibility requirement; per-read accuracy should be interpreted
within this limitation.

RustyClean AUTO was compared with KneadData v0.12.3 and fastp + Hostile
v2.0.2. KneadData used its human hg39 Bowtie2 workflow; RustyClean used
the Deacon panhuman-1 index and Hostile human-t2t-hla Bowtie2 index for
verification; fastp + Hostile used the Hostile human-t2t-hla index.
Thus the arms differ in reference content as well as workflow. KneadData
and fastp + Hostile used 8 threads; Deacon-only and AUTO used 16 threads.
KneadData additionally performs Trimmomatic trimming, tandem-repeat
masking and identifier reformatting. **Table 2 is consequently a
workflow-scope comparison, not a controlled runtime benchmark.** The
controlled runtime evidence is the same-thread paired experiment below
and the 24-sample same-core-budget batch experiment.

**Minimizer-based panel.** Deacon v0.17.0 standalone was run in
depletion-only mode (`--skip-qc`) with 16 threads. AUTO chained fastp,
Deacon and conditional Bowtie2 verification with the same index and
thread allocation. Three timing replicates were run for five AUTO
libraries. For 100M/90%, the first AUTO replicate was checkpoint-resumed
in 2.2 s and excluded; Table 2 reports the mean and SD of the two
uncached replicates. Deacon timing used all three replicates.
KneadData and fastp + Hostile 100M comparator runs were single
measurements.

**Cross-species panel and index builds.** Species-specific Deacon
indexes (k31w15) were built for human (T2T-CHM13v2.0), monkey, mouse,
pig, rat and rice. Build time and memory were recorded. Each host was
evaluated on one simulated 10M-read, 50%-host, single-end condition with
the species-matched index and with the human panhuman-1 index. This is a
small proof-of-concept panel; genome accessions, simulation metadata,
index checksums and per-read source labels are not fully documented in
the current repository.

**I/O-optimized comparisons.** To reduce compression and intermediate
I/O, RustyClean was rerun with fastp gzip level 1, node-local scratch
and a warm Deacon server. For 100M/90%, fastp + Hostile was rerun on the
same node with 16 threads, gzip level 1, node-local scratch and warm
page cache, with replicate order alternated. For the other five
libraries, Hostile values are historical 8-thread single measurements
from Table 2 and are therefore not paired with the optimized RustyClean
runs. Wall time and peak resident set size were recorded with GNU
`time`.

**Parallel-scaling experiment.** Sixteen identical 10M-read, 10%-host
single-end samples (below the verification threshold) were processed
with *T* = 4 and *W* ∈ {1,2,4,8} on one 64-core AMD node. This yielded
one wall-time observation per worker count and sampled process RSS every
5 s. It was not replicated, did not use heterogeneous samples, and did
not exercise verification-triggering libraries.

**Batch experiment.** A separate unreplicated 24-library, 1M-read batch
benchmark used a 16-core budget for both workflows (`workers × threads
= 16`).

### 2.9 Evaluation metrics

All main-panel metrics use retained reads as the classified output:
TP is a retained true microbial read, FP is a retained true host read,
FN is a discarded true microbial read, and TN is a removed true host
read. We report

- **Microbial loss** = FN / (TP + FN), the percentage of true microbial
  input discarded.
- **Host input retention** = FP / (FP + TN), the percentage of true host
  input retained.
- **Host output fraction** = FP / (TP + FP), the percentage of retained
  reads that are host.
- **F1** = 2 × precision × recall / (precision + recall), using retained
  microbial reads as the positive class.
- **Runtime**: wall-clock mean, number of replicates and SD where
  available. Accuracy is deterministic for a fixed output and is
  reported once per condition.
- **Peak memory**: maximum resident set size of the largest measured
  process; it is not summed pipeline memory.

Host input retention and host output fraction answer different
questions. Both are reported or clearly identified. An earlier summary
table incorrectly applied a retained-output label to the host-input
rate; the revised Table 2 and Figure 2 use the definitions above. For
the cross-species experiment, the confusion matrix is expressed as
depletion calls (TP, host removed; FP, microbial read incorrectly
removed; FN, host retained; TN, microbial read retained), and microbial
loss and host retention use the same biological definitions. Source
column labels in archived cross-species CSVs are therefore interpreted
rather than used literally.

Downstream effects on taxonomic profiles, assemblies and MAG recovery
were not systematically benchmarked.

### 2.10 Alternative backends evaluated and not retained

sylph produces sample-level relative abundance, not per-read labels. It
was tested only as a binary sensor: a host-positive call sent a sample
to Bowtie2, while a host-negative call retained it without alignment. On
the 100M datasets this did not improve runtime for host-positive samples
relative to direct Bowtie2 removal. Because it lacks read-level
classifications, sylph was not retained.

A FracMinHash backend was rejected because it retained 12.3%
of true host input across 5M/1%, 10M/10% and 30M/50% datasets (F1
0.915--0.993), and sketching was an order of magnitude slower than
Deacon. These archived exploratory runs are not part of the primary
panel.

Alternative per-read backends were also compared: Bowtie2, minimap2 and
Centrifuge (Section 3.5 and Figure S1). Their archived metric schema
contains host-remaining and microbial-loss fields in the opposite order
from their labels; the revised supplementary table swaps those columns
and reports host retention per host input.

## 3. Results

### 3.1 Minimizer-based depletion as the default Tier-1 backend

The four-way comparison in Table 2 reports all four tools on all six
simulated libraries. It is a workflow-scope panel rather than a
controlled runtime benchmark. KneadData and fastp + Hostile used 8
threads and different workflow scope; Deacon and AUTO used 16 threads.
RustyClean and Deacon timing is replicated; the two 100M comparator arms
are single measurements. Accuracy is reported from deterministic per-read
outputs. A count-level audit of archived TP/FP/FN/TN tables is provided in
`data/metric_audit/RAW_READ_METRIC_AUDIT.md`. For 5--60M, Hostile error
counts derive from a Hostile-only raw-input arm (`hostile_raw`), while
Hostile runtime comes from separate fastp + Hostile timing; the 100M
Hostile error and runtime derive from the later fastp + Hostile fill run.
This provenance discontinuity is disclosed rather than treated as a
depth trend.

![](figures/fig1_four_way_runtime_memory.png)

**Figure 1.** Four-way comparison on the simulated panel. (a) Runtime on
a log scale, with the basis stated in Table 2. Error bars show SD for
the replicated RustyClean AUTO arms; comparator runs without replicate
measurements have no error bar. (b) Peak resident set size of the
largest measured process.

**Table 2.** Four-way comparison on the simulated panel. Runtime is
mean \pm SD; n is the number of timing replicates. Deacon and AUTO
used 16 threads, whereas KneadData and fastp + Hostile used 8 threads.
Accuracy metrics are percentages of the relevant biological input class
(Section 2.9). Host retention is retained true host reads divided by
true host input, not the fraction of the final output. The Hostile rows
should not be compared across depth because of this source mismatch. In
the controlled 100M paired run, Hostile retained 0.0388--0.174% of host
input and discarded 0.0388% of microbial input, whereas AUTO retained
near zero host input but discarded 0.307--0.318% of microbial input. The 100M comparator runs are
single measurements; the AUTO 100M/90% runtime excludes one 2.2 s
checkpoint-resumed run and uses the two uncached replicates.

| **Dataset** | **Tool** | **Runtime (s; n)** | **Memory (GiB)** | **F1** | **Microbial loss (%)** | **Host input retained (%)** |
|-------------|----------|-------------------:|-----------------:|-------:|-----------------------:|----------------------------:|
| 5M / 1% | KneadData | 420.3 (1) | 1.09 | 0.97981 | 3.956345 | 0.268829 |
| 5M / 1% | Hostile + fastp | 186.6 (1) | 3.38 | 0.99997 | 0.0000 | 0.6858 |
| 5M / 1% | Deacon only | 9.58 \pm 0.61 (3) | 4.54 | 1.00000 | 0.0000 | 0.004234 |
| 5M / 1% | RustyClean AUTO | 90.37 \pm 0.63 (3) | 4.54 | 1.00000 | 0.0000 | 0.004234 |
| 10M / 10% | KneadData | 694.5 (1) | 1.11 | 0.98571 | 2.790938 | 0.255497 |
| 10M / 10% | Hostile + fastp | 326.5 (1) | 3.55 | 0.99923 | 0.078527 | 0.674453 |
| 10M / 10% | Deacon only | 12.97 \pm 1.49 (3) | 4.54 | 0.99881 | 0.2381 | 0.003682 |
| 10M / 10% | RustyClean AUTO | 142.05 \pm 44.47 (3) | 4.54 | 0.99881 | 0.2381 | 0.003682 |
| 30M / 50% | KneadData | 2,317.5 (1) | 1.11 | 0.99098 | 1.425000 | 0.250000 |
| 30M / 50% | Hostile + fastp | 840.3 (1) | 3.58 | 0.99501 | 0.000000 | 0.675800 |
| 30M / 50% | Deacon only | 28.58 \pm 6.14 (3) | 4.54 | 0.99997 | 0.000021 | 0.003687 |
| 30M / 50% | RustyClean AUTO | 622.30 \pm 164.93 (3) | 4.54 | 1.00000 | 0.000343 | 0 (0 host reads) |
| 60M / 90% | KneadData | 6,822.0 (1) | 1.11 | 0.97603 | 2.1540 | 0.2496 |
| 60M / 90% | Hostile + fastp | 1,456.4 (1) | 3.60 | 0.96522 | 0.039310 | 0.674454 |
| 60M / 90% | Deacon only | 52.43 \pm 22.61 (3) | 4.54 | 0.99921 | 0.119874 | 0.003575 |
| 60M / 90% | RustyClean AUTO | 669.46 \pm 48.12 (3) | 4.54 | 0.99845 | 0.309346 | 0.0000097 (5 reads) |
| 100M / 50% | KneadData | 6,419.0 (1) | 1.10 | 0.98766 | 0.2493 | 2.1514 |
| 100M / 50% | Hostile + fastp | 1,284.9 (1) | 3.60 | 0.99878 | 0.1734 | 0.0393 |
| 100M / 50% | Deacon only | 153.37 \pm 37.75 (3) | 4.54 | 0.99937 | 0.1211 | 0.003535 |
| 100M / 50% | RustyClean AUTO | 1,684.90 \pm 207.98 (3) | 4.54 | 0.99845 | 0.310387 | 0.0000021 (1 read) |
| 100M / 90% | KneadData | 8,271.0 (1) | 1.10 | 0.97603 | 0.2496 | 0.2496 |
| 100M / 90% | Hostile + fastp | 1,860.7 (1) | 3.56 | 0.99065 | 0.1740 | 0.0388 |
| 100M / 90% | Deacon only | 202.41 \pm 19.65 (3) | 4.54 | 0.99920 | 0.1198 | 0.003730 |
| 100M / 90% | RustyClean AUTO | 2,396.66 \pm 430.32 (2) | 4.54 | 0.99846 | 0.307188 | 0.0000105 (9 reads) |

In this scope panel, AUTO runtime was 3.72--10.19 times lower than
KneadData, but the comparison is confounded by thread allocation,
reference content and KneadData's additional Trimmomatic, repeat-masking
and identifier-reformatting work. AUTO was faster than fastp + Hostile
on the four shorter libraries (1.35--2.30 times) but slower on both
100M libraries under default serialization (0.76--0.78 times).
Deacon-only runtime was 40.9--130.2 times lower than full KneadData,
but this compares depletion-only and full-pipeline scope and should not
be read as a like-for-like speed ratio.

The paired optimized experiment is the controlled runtime result. On
100M/90%, optimized RustyClean completed in 427.98 \pm 76.16 s versus
1,032.37 \pm 37.15 s for 16-thread fastp + Hostile. RustyClean was
faster in all three replicates, with speedups 2.12, 2.26 and 3.01 times
(mean 2.47; paired t-test p = 0.0061; Wilcoxon bounded at p = 0.25 for
n = 3). Accuracy was deterministic across replicates. In the broader
I/O-optimized panel, we use one reporting basis throughout: the mean of
all three RustyClean replicates, including cold Deacon-server loads,
divided by the historical single Hostile runtime. These unpaired
all-replicate speedups were 1.99, 5.38, 4.63, 3.49, 2.94 and 6.36 times
for the six datasets in Table 1 order. They are observational and not
evidence of a controlled panel-wide effect. A mixed all-replicate
minimum and warm-server maximum is no longer reported.

![](figures/fig2_accuracy_verification.png)

**Figure 2.** Accuracy and verification-tier performance. (a) Retained
microbe F1 per dataset and tool. (b) Retained true host reads as a
percentage of true host input on a log scale. (c) Verification effect
on the four high-host datasets for Deacon alone versus AUTO. Panel c
shows host input retention, not output fraction.

Verification changed the relevant host-retention endpoint. Deacon alone
retained 0.0035--0.0037% of true host reads. After conditional Bowtie2
verification, AUTO retained zero host reads on 30M/50%, 5 on 60M/90%,
1 on 100M/50% and 9 on 100M/90%. These correspond to 0, 0.0000097%,
0.0000021% and 0.0000105% of true host input, respectively. The trade
was microbial loss: AUTO lost 33, 14,952, 125,028 and 24,747 microbial
reads on those four libraries (0.000343--0.3104%). Table 3 gives the
exact counts.

**Table 3.** Exact confusion-matrix counts and denominators for
RustyClean AUTO. TP, retained microbial reads; FP, retained host reads;
FN, discarded microbial reads; TN, removed host reads. The 100M/90%
row is from the paired-validation output and differs slightly from the
uncached panel row because it is a separate optimized run.

| **Dataset** | **TP** | **FP** | **FN** | **TN** | **Host output fraction (%)** | **Host input retention (%)** |
|---|---:|---:|---:|---:|---:|---:|
| 5M / 1% | 4,949,619 | 2 | 0 | 47,240 | 0.0000404 | 0.004234 |
| 10M / 10% | 8,520,699 | 35 | 20,336 | 950,661 | 0.000411 | 0.003682 |
| 30M / 50% | 9,616,878 | 0 | 33 | 14,264,819 | 0 | 0 |
| 60M / 90% | 4,818,469 | 5 | 14,952 | 51,351,168 | 0.000104 | 0.0000097 |
| 100M / 50% | 40,156,242 | 1 | 125,028 | 47,550,448 | 0.0000025 | 0.0000021 |
| 100M / 90% (paired) | 8,030,384 | 9 | 25,607 | 85,585,121 | 0.000112 | 0.0000105 |

Peak AUTO memory was approximately 4.54 GiB, close to fastp + Hostile
(3.38--3.60 GiB) and above KneadData (1.09--1.11 GiB). The reported
value is largest measured process RSS, not the sum of all processes in
a pipeline tree or batch. KneadData therefore remains the lowest
single-process-memory arm in this panel.

Index representativeness is therefore a dominant accuracy factor. The
human T2T versus panhuman-1 comparison is shown with the other
cross-species results in Section 3.2 and Table 4.

### 3.2 Cross-species host depletion

Host depletion also arises in non-human samples. We built
species-specific Deacon indexes (k31w15) for human (T2T-CHM13v2.0),
monkey, mouse, pig, rat and rice. Index builds took 4.2--52.4 s and
produced 0.30--2.53 GB indexes. On one simulated 10M-read, 50%-host,
single-end condition per host, matched indexes achieved F1
0.999858--0.999976, microbial loss 0.00182--0.02258% and host input
retention 0.00186--0.02258% (Table 4).

Applying the human panhuman-1 index to non-human libraries left
46.8--99.8% of true host reads in the output. Thus the low F1 reflects
failed host removal rather than removal of microbial reads: microbial
loss under panhuman-1 remained 0.0023--0.0027%. This interpretation is
supported by the archived TP/FP/FN/TN counts and by the nominal 50%
host fractions. It is a strong cautionary result for the tested
conditions, not evidence that a human index will fail for every
non-human library or that a species-specific index will suffice for
every strain-diverse host. The experiment does not test a true union
pan-host index.

![](figures/fig3_cross_species_index.png)

**Figure 3.** Cross-species depletion F1 on 10M-read, 50%-host simulated
datasets. The human matched-index value uses panhuman-1; its build row
uses a locally built T2T-only index and is therefore not a build/performance
match. Matched and panhuman values are identical for human.

**Table 4.** Cross-species Deacon proof of concept on one 10M-read,
50%-host simulated condition per host. Metrics are derived from
retained-read confusion matrices: microbial loss is lost true microbial
reads divided by microbial input; host retention is retained true host
reads divided by host input. Matched-index F1 for human uses panhuman-1,
whereas the build row is the locally built T2T-only index.

| **Host** | **Index** | **F1** | **Microbial loss (%)** | **Host input retained (%)** |
|----------|-----------|-------:|-----------------------:|----------------------------:|
| human | panhuman-1 | 0.999963 | 0.002532 | 0.004931 |
| human | T2T-only | 0.998856 | 0.003175 | 0.225369 |
| monkey | monkey | 0.999974 | 0.003315 | 0.001861 |
| monkey | panhuman-1 | 0.809790 | 0.002592 | 46.775233 |
| mouse | mouse | 0.999858 | 0.022581 | 0.005860 |
| mouse | panhuman-1 | 0.672310 | 0.002652 | 97.046572 |
| pig | pig | 0.999976 | 0.003034 | 0.001820 |
| pig | panhuman-1 | 0.672487 | 0.002270 | 96.966797 |
| rat | rat | 0.999953 | 0.003315 | 0.005960 |
| rat | panhuman-1 | 0.672134 | 0.002512 | 97.114422 |
| rice | rice | 0.999875 | 0.022421 | 0.002592 |
| rice | panhuman-1 | 0.666210 | 0.002431 | 99.769990 |

For human, panhuman-1 reduced host input retention 45.7-fold relative to
T2T-only (0.004931% versus 0.225369%), with little change in microbial
loss. Index build metrics for the locally built T2T-only index were
33.1 s and 2.53 GB; panhuman-1 was a published prebuilt index.

### 3.3 Real-data operational run

We processed 11 human oral microbiome samples from the LU cohort
(paired-end, 5--45 million reads) with the routing-based auto mode of an
earlier RustyClean release. Current releases use the Deacon-based AUTO
backend. All 11 samples completed. Runtime was 9--46 min per sample
(mean 18.6 min, median 13.6 min) and peak memory was 3.4--6.5 GB
(mean 4.1 GB, median 3.6 GB); total cohort wall time was 3.4 h. These
numbers are an operational smoke test of the earlier release only. They
do not measure accuracy, current Deacon-AUTO performance, host removal,
or downstream effects, and they do not establish production readiness.

### 3.4 Sample-level parallelism in one scaling run

Cohort processing is sample-parallel: a semaphore admits *W* samples,
each with *T* tool threads. To observe scaling, we ran sixteen identical
10M-read, 10%-host single-end samples with *T* = 4 and *W* ∈ {1,2,4,8}
on one 64-core AMD node. Wall time fell from 2,364 s at *W* = 1 to
1,153 s at *W* = 2 (2.05 times), 620 s at *W* = 4 (3.81 times) and
302 s at *W* = 8 (7.84 times). Because there was one run per worker
count, these values are observations rather than estimates with
replication uncertainty. They also use identical low-host samples that
did not trigger verification.

![](figures/fig4_parallel_scaling.png)

**Figure 4.** Sample-level parallelism of the Deacon backend in one
unreplicated experiment. (a) Wall time for sixteen samples. (b) Speedup
relative to one worker and ideal linear scaling. (c) Median sampled
per-process RSS and median sum of RSS across active workers. Summed RSS
overcounts shared read-only index pages and is not physical unique
memory.

Median sampled RSS per active Deacon worker was approximately 4.5 GiB.
Median summed RSS at eight workers was 33.4 GiB, with a transient
sampled maximum of 36.2 GiB. Thus aggregate memory increased with the
number of active workers, while per-process RSS remained approximately
constant. These data do not establish superiority over alignment
workflows in unique physical memory.

In a separate unreplicated 24-library, 1M-read batch benchmark with a
16-core budget, RustyClean fell from 1,027.14 s at one worker to
140.67 s at eight workers (7.30 times), whereas fastp + Hostile fell
from 1,002.15 s to 265.62 s (3.77 times). At eight workers, RustyClean
was 1.89 times faster in this single paired-budget observation.

### 3.5 Alternative depletion backends

Because the pipeline treats depletion as a replaceable stage, Bowtie2,
minimap2 and Centrifuge were evaluated on the four smaller simulated
datasets. Under the archived removed-host schema, Bowtie2 and minimap2
retained only 0.021--0.055% of true host input, whereas Centrifuge
retained 1.09--1.18%. Centrifuge also removed more microbial reads on
10M/10% (1.03% versus 0.57--0.59%) and 60M/90% (0.760% versus
0.388--0.416%), although Bowtie2 lost 0.521% on 60M/90% and minimap2
lost 0.416%. Peak memory differed substantially. These archived backend
runs were not rerun under the final Deacon-AUTO configuration. The
default Tier-1 backend is Deacon; Figure S1 and Supplementary Table S1
are exploratory comparisons.

## 4. Discussion

The two error directions have different consequences. Discarded
microbial reads irreversibly reduce signal for diversity, assembly and
binning. Retained host reads may be tolerable for some profiling
workflows but can contaminate assemblies and matter for human-data
sharing. A single scalar F1 cannot express this trade-off, so the
revised results report exact retained and discarded read counts and
separate host input retention from host output fraction.

The main technical result is narrower than a claim that minimizer
depletion replaces alignment. Deacon provides a fast Tier-1 filter.
Conditional Bowtie2 verification reduced host input retention to zero or
near zero on the four high-host simulated libraries, at the cost of
up to 0.310% microbial loss. This is a useful accuracy profile on the
tested panel, but it depends on index representativeness and on a
threshold that was not optimised or validated near its boundary.

The runtime evidence must be read at three levels. The six-library
scope panel is not a like-for-like speed benchmark because of unequal
thread allocation, different references and additional KneadData work.
The controlled evidence is the same-node, same-thread paired 100M/90%
experiment, where optimized RustyClean was faster in all three
replicates. The broader optimized panel is unpaired and observational;
its all-replicate range should not be combined with warm-server values.
Finally, the 24-sample batch result is a single same-core-budget
observation.

RustyClean's contribution is therefore integration and transparent
benchmarking, not a new minimizer algorithm. It adds orchestration,
conditional verification, checkpoints and configurable checks around an
external preprint filter. The implementation features are plausible
operational improvements, but this study did not perform exhaustive
fault injection or validation-gate sensitivity testing, and the
benchmark did not establish that they outperform all alternatives.

**Relationship to Deacon.** Deacon was not peer reviewed at the time of
writing. RustyClean pins v0.17.0 and integrates it rather than
reimplementing it. What this work adds is a per-read simulated panel, a
controlled paired comparison with Hostile, a six-host proof of concept,
and explicit disclosure of the remaining provenance and validation gaps.
Because the external binary commit was not recorded in the archived run
metadata, the RustyClean version is an explicit reproducibility
limitation.

**Limitations.** The primary accuracy evaluation is simulation-only,
single-end, and limited to six libraries. Raw reads, ground truth files,
seeds, genome accessions and complete generation metadata are not
currently redistributed, so independent regeneration is incomplete.
Real sequencing artefacts, host genetic variation and reference mismatch
were not tested with per-read truth. The 11-sample real cohort tested an
earlier release and operational completion only. Downstream taxonomic,
assembly and MAG effects were not benchmarked.

The Deacon-based default inherits index dependence. The human panhuman-1
index left 46.8--99.8% of true host reads in the tested non-human
libraries. Species-specific indexes performed well there, but
only one condition per host was tested. This supports host-matched
indexes for those hosts; it does not validate a universal pan-host index.

The adaptive threshold is an empirical default. Six libraries produced
only two below-threshold and four above-threshold examples; no sweep,
boundary cases, held-out validation or cost-accuracy optimisation was
performed. Likewise, the output gate was not sensitivity-tested. These
are priority validation experiments.

Timing measurements are sensitive to I/O, cache state, index loading and
cluster contention. RustyClean and Deacon timing is replicated in the
scope panel, but 100M comparator arms, panel-wide optimized comparisons
and scaling runs are single observations or not fully paired. The
paired 100M/90% experiment is the strongest runtime evidence, while the
other timing results are descriptive.

Finally, Deacon's published prebuilt indexes did not cover all tested
hosts, and RustyClean depends on external fastp, Deacon, Bowtie2 and
samtools versions. These dependencies must be pinned in a release before
independent reproduction can be considered complete.

## 5. Software and data availability

**Code and result provenance.** The benchmark and plotting scripts,
per-figure summary tables, raw count audit tables and run-level result
tables are in
https://github.com/HuangShiLab/rustyclean-paper. The analysis snapshot
used for the revised metric audit is based on repository commit
`b05ebb6314a5a46b67ec5f72b7c0d8b560f27d45`; the current revision is
tracked in the working repository. RustyClean is at
https://github.com/HuangShiLab/rustyclean under the MIT licence. Deacon
was v0.17.0, KneadData v0.12.3 and Hostile v2.0.2. The exact RustyClean
binary commit, fastp build and complete dependency lock were not recorded
in the archived run metadata; these must be added to a tagged release
before complete reproduction can be claimed.

**Simulated data.** The current repository redistributes result tables
and analysis code, not the large simulated FASTQ files or ground-truth
label files. Random seeds, full genome/accession lists, read-length and
error-profile settings, index checksums and exact generation commands
are not yet complete. Consequently, readers can audit the reported
summary tables and metric transformations but cannot yet fully
regenerate every read from the repository alone.

**Human data.** The 11 LU-cohort oral microbiome samples are subject to
the original data-access agreement and are not redistributed. No
per-sample cohort metrics or validation logs are included here.

**Correspondence.** Yufeng Zhang, yfz96@connect.hku.hk.

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
10. Hostile v2.0.2. https://github.com/bede/hostile. Software accessed
    for benchmarking; complete archival version metadata is in the
    reproduction environment.
11. Li H. Minimap2: pairwise alignment for nucleotide sequences.
    *Bioinformatics*. 2018;34(18):3094--3100.
12. Kim D, Song L, Breitwieser FP, Salzberg SL. Centrifuge: rapid and
    sensitive classification of metagenomic sequences. *Genome
    Research*. 2016;26(12):1721--1729.
13. Nurk S, Koren S, Rhie A, et al. The complete sequence of a human
    genome. *Science*. 2022;376(6588):44--53. (T2T-CHM13 consortium
    reference.)
14. sylph. https://github.com/bluenote-1577/sylph. Software evaluated as
    a sample-level sensor; complete version metadata is in the
    reproduction environment.

## Supplementary material

![](figures/figS1_backend_comparison.png)

**Figure S1.** Exploratory comparison of Bowtie2, minimap2 and Centrifuge
within the older RustyClean backend build. (a) F1 score, (b) retained
true host reads as a percentage of true host input, (c) microbial reads
lost as a percentage of true microbial input, and (d) peak memory (GB).
Runtime is excluded because one minimap2 measurement on the 5M dataset
was a cold-start outlier. The archived removed-host schema is audited in
`data/metric_audit/RAW_READ_METRIC_AUDIT.md`.

| **Backend** | **Dataset** | **F1** | **Retained host input (%)** | **Microbial loss (%)** | **Peak mem (GB)** |
|-------------|-------------|-------:|----------------------------:|-----------------------:|------------------:|
| Bowtie2 | 5M / 1% | 0.9996 | 0.055036 | 0.000242 | 3.6 |
| Bowtie2 | 10M / 10% | 0.9749 | 0.052803 | 0.567800 | 3.6 |
| Bowtie2 | 30M / 50% | 0.9984 | 0.048981 | 0.401907 | 3.6 |
| Bowtie2 | 60M / 90% | 0.9996 | 0.049111 | 0.388007 | 6.2 |
| minimap2 | 5M / 1% | 0.9986 | 0.021168 | 0.002424 | 11.5 |
| minimap2 | 10M / 10% | 0.9742 | 0.025560 | 0.587107 | 11.7 |
| minimap2 | 30M / 50% | 0.9984 | 0.029639 | 0.431116 | 11.8 |
| minimap2 | 60M / 90% | 0.9997 | 0.029448 | 0.415710 | 11.9 |
| Centrifuge | 5M / 1% | 0.9940 | 1.090132 | 0.001010 | 7.0 |
| Centrifuge | 10M / 10% | 0.9500 | 1.178610 | 1.026655 | 7.2 |
| Centrifuge | 30M / 50% | 0.9920 | 1.172836 | 0.631658 | 7.9 |
| Centrifuge | 60M / 90% | 0.9938 | 1.171042 | 0.760352 | 8.6 |

**Supplementary Table S1.** Backend comparison for Figure S1. TP denotes
a removed host read, FP a lost microbial read, FN a retained host read
and TN a retained microbial read. Values are derived from
`archive/v1/data/accuracy_rc_mm_bt_cf_v4.csv` and
`archive/v1/data/performance_rc_mm_bt_cf_v4_corrected.csv`.

**Supplementary Table S2.** Same-node paired validation on 100M/90%
data (n = 3). Both arms used 16 threads, fastp gzip level 1 and
node-local scratch. RustyClean additionally used a warm Deacon server;
Hostile + fastp used Hostile v2.0.2. Error metrics use true microbial
or true host input as denominator.

| Replicate | RustyClean AUTO (s) | fastp + Hostile (s) | Speedup | RustyClean microbial loss (%) | RustyClean retained host input (%) | Hostile microbial loss (%) | Hostile retained host input (%) |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 499.02 | 1,060.01 | 2.12 | 0.317863 | 0.0000105 (9 reads) | 0.038791 | 0.174027 |
| 2 | 437.35 | 990.14 | 2.26 | 0.317863 | 0.0000105 (9 reads) | 0.038791 | 0.174027 |
| 3 | 347.56 | 1,046.96 | 3.01 | 0.317863 | 0.0000105 (9 reads) | 0.038791 | 0.174027 |
| Mean ± SD | 427.98 ± 76.16 | 1,032.37 ± 37.15 | 2.47 | 0.317863 | 0.0000105 | 0.038791 | 0.174027 |

Retained-microbe F1 was 0.998408 for RustyClean and 0.990647 for
fastp + Hostile. RustyClean retained 9 host reads and discarded 25,607
microbial reads. Hostile retained 148,941 host reads and discarded
3,125 microbial reads. Paired t-test on runtime: p = 0.0061. Wilcoxon
signed-rank is bounded at p = 0.25 for n = 3.

**Supplementary Table S3.** Full-pipeline batch parallelization on 24
balanced 1M-read libraries. This was one observation per workflow and
worker count. Both tools used a 16-core budget with
`workers × threads = 16`.

| Workflow | W = 1 (s) | W = 8 (s) | Scaling | Largest process RSS at W = 8 (GiB) |
|---|---:|---:|---:|---:|
| RustyClean AUTO | 1,027.14 | 140.67 | 7.30 | 4.52 |
| fastp + Hostile | 1,002.15 | 265.62 | 3.77 | 3.49 |

At eight workers, RustyClean was 1.89 times faster in this single
paired-budget observation. Peak process RSS is the largest single
process, not summed or unique physical memory.

![](figures/fig_io_optimized_runtime.png)

**Figure S2.** I/O-optimized RustyClean AUTO runtime relative to fastp +
Hostile across the six simulated datasets. RustyClean used fastp gzip
level 1, node-local scratch and a warm Deacon server (three replicates
per dataset). Error bars show SD across all replicates, including the
first replicate in which the Deacon server loaded its index. Hostile +
fastp values are historical single measurements, except 100M/90%, which
has a paired three-replicate validation. The figure is therefore
observatory outside 100M/90%. Source data:
`data/main_figures/fig_io_optimized_runtime.csv`.

**Supplementary data.** Per-figure summaries are under
`data/main_figures/`. Replicate and comparator source tables are under
`runs/deacon_panel/metrics/`: `deacon_metrics.csv` and `auto_metrics.csv`
for per-replicate Deacon and AUTO runs; `fill_100m_comparators.csv` and
`fill_100m_raw/fill_100m_metrics.csv` for 100M comparators and the
uncached AUTO rows; `cross_species_metrics.csv` and
`index_build_metrics.csv` for the six-host proof of concept; and
`parallel_scaling_Deacon.csv` for Figure 4. The paired validation is in
`data/paired_triplicate/100M_90pct_high_lognormal_SE/`. The 24-library
batch observation is in `data/parallel_demo/parallel_demo_completed.csv`.
The corrected summary tables used for Figures 1 and 2 explicitly
distinguish microbial loss and host input retention.

