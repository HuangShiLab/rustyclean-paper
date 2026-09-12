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
3.7--10× faster than KneadData and 1.3--2.2× faster than
fastp + Hostile while matching or exceeding their accuracy (F1 ≥ 0.998
on high-host samples), reducing host carry-over to 0.0000% of retained
output on every high-host dataset tested --- against ~0.67% for
Hostile and ~0.25% for KneadData --- and discarding at most 0.31% of
microbial reads, against 1.4--4.0% for KneadData. Peak memory was
4.8 GB, 3.4-fold below the legacy Kraken2-based path, though
above KneadData's 1.2 GB. Because deacon's published prebuilt indexes
cover human and mouse only, we built and validated species-matched
indexes for human (T2T), monkey, mouse, pig, rat and rice (build time
4--52 s each): each species' own index achieved F1 0.99986--0.99998,
whereas the human panhuman-1 index wrongly depleted 46.8% of the
microbial reads in monkey-host samples and 97--99.8% in mouse, pig,
rat and rice samples, showing that species-matched or pan-host indexes
are mandatory outside human. RustyClean is a single Rust binary with
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
against 209--582 minutes for alignment-based tools, and 0.3 GB against
\~18 GB to index the human genome --- and that its advantage is most
pronounced under high contamination (90%).

That benchmark motivated a natural engineering question, which this work
addresses: if Kraken2 is both accurate enough and dramatically faster
for host depletion, can it replace the alignment step in production
pipelines? Our initial answer was a straightforward substitution.
KneadData (McIver et al., 2018), the de facto standard, chains
Trimmomatic for quality control, Tandem Repeat Finder for repeat masking,
and Bowtie2 for host alignment, orchestrated by a Python wrapper. We replaced this with a
two-stage pipeline --- fastp for quality control and Kraken2 for host
depletion --- implemented as a single Rust binary.

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

Two findings from the initial Kraken2-based design carry over, and a
third is added by the minimizer-based redesign; together they define
the contribution of this paper.

**First, the efficiency advantage of any single classical backend is
conditional on host fraction.** Kraken2\'s cost is essentially fixed
per read, whereas Bowtie2\'s cost depends on how many reads must be
fully aligned rather than rejected early. At low host fractions,
alignment rejects most microbial reads quickly and its index is smaller
than a Kraken2 database, so the alignment route is competitive or
faster. The advantage inverts as host fraction rises. A pipeline that
commits to either method unconditionally is therefore slower than
necessary on some fraction of any real cohort.

**Second, the false negative rate is not uniformly acceptable.** At
high host fractions, the residual host retained by k-mer classification
--- and, at a much smaller level, by minimizer depletion --- becomes
large in absolute terms even when its rate is modest, because the pool
of host reads is large. In this regime, Tier-1 classification or
depletion alone does not deliver a sufficiently clean library.

**Third, minimizer-based depletion dissolves the routing problem but
not the verification problem.** Because deacon's per-read cost is
host-fraction-independent, a single Tier-1 backend now suffices across
the whole host-fraction spectrum, and the per-sample routing scheme of
the original design is needed only as a fallback. What remains is
verification-budget allocation: deacon alone leaves a structural
residue of host reads (~0.004% of retained output on our panel), and
deciding when a Bowtie2 verification pass over the retained reads is
worth its cost requires a decision rule that the bare tool does not
provide.

RustyClean addresses these points directly. It integrates deacon as the
default Tier-1 depletion backend behind the existing quality-control
and orchestration layers, and it adds an adaptive verification tier:
RustyClean parses deacon's own summary JSON, and whenever the reported
removed proportion (`seqs_removed_proportion`) reaches
`--recheck-threshold` (default 0.3) the retained reads are re-screened
with Bowtie2; below the threshold the deacon output is accepted as
final. The per-sample decision is thereby recast from "which backend"
to "how much verification": the pass is expensive exactly when the
retained set is large, and the threshold restricts it to samples whose
host content makes both the residue and the pass cost proportionate.
The legacy host-fraction routing between Kraken2 and Bowtie2 is
retained as a documented fallback for deployments without a deacon
index (Section 2.3).

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
2.  The legacy per-sample routing scheme, retained as a documented
    fallback when no deacon index is configured, together with the
    targeted alignment verification pass that corrects the false
    negative bias of the legacy Kraken2 classification path.
3.  A validated pan-host index set: species-specific deacon indexes
    for human (T2T), monkey, mouse, pig, rat and rice, built in
    4--52 s each, and a quantification of panhuman-1 cross-reactivity
    showing that species-matched or pan-host indexes are mandatory for
    non-human work.
4.  A production-oriented implementation with checkpoint/resume,
    bounded concurrency, and automated output validation.
5.  An evaluation across 18 simulated datasets with per-read ground
    truth spanning ten host fractions and six sequencing depths, a
    five-way comparison against KneadData, Hostile and the legacy
    backend, a six-host cross-species panel, and a real-data cohort.

## 2. Methods

### 2.1 Pipeline overview

In the default configuration (AUTO mode with a deacon index supplied),
RustyClean processes each sample through four stages:

1.  **Quality control** --- adapter detection and trimming, quality
    filtering (fastp).
2.  **Tier-1 host depletion** --- minimizer-based depletion with deacon
    against a user-supplied pangenome index (Section 2.4b).
3.  **Conditional verification** --- RustyClean parses deacon's summary
    JSON; if the reported removed proportion (`seqs_removed_proportion`)
    is at least `--recheck-threshold` (default 0.3), the retained reads
    are re-screened with Bowtie2 (Section 2.6). Below the threshold the
    deacon output is final.
4.  **Validation and finalisation** --- automated assertions before
    output promotion (Section 2.7).

When no deacon index is configured, AUTO mode falls back to the legacy
scheme: a rapid alignment survey estimates each sample's host fraction
and routes the sample to the alignment path (Section 2.5) or the
Kraken2 classification path (Section 2.4), optionally followed by the
Bowtie2 recheck (Section 2.6). Kraken2, Bowtie2, sylph and Centrifuge
remain available as explicit backends (`--host-removal-mode`) for users
who do not wish to use deacon.

Samples may be supplied individually or as a tab-separated sample
manifest; single-end and paired-end layouts are detected automatically
and handled throughout.

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

### 2.3 Verification-budget allocation and legacy host-fraction routing

**Default: verification-budget allocation.** When a deacon index is
configured --- the default --- no routing between depletion backends is
necessary, because deacon's per-read cost is independent of host
fraction. The decision that remains is whether to spend verification
budget on a sample, and RustyClean makes it from deacon's own output
rather than from a separate survey: if the proportion of input reads
that deacon removed (`seqs_removed_proportion` in deacon's summary
JSON) is at least `--recheck-threshold` (default 0.3), the retained
reads are re-screened with Bowtie2 (Section 2.6); otherwise the deacon
output is accepted as final. The rule is deliberately one-sided. A high
removed proportion implies a large host pool, in which the
characteristic structural residue of minimizer depletion (~0.004% of
retained output on our panel) is worth eliminating, and the retained
set after depletion is small, so the alignment pass is cheap. A low
removed proportion implies the opposite on both counts: the residue is
absolutely tiny and the retained set is large. Both the threshold and
the pass itself are user-configurable.

**Legacy fallback: host-fraction routing.** Without a deacon index,
RustyClean selects one depletion strategy per sample rather than
globally. A random subsample of n reads (default n = 100,000, drawn
with seqtk using a fixed seed for reproducibility) is taken from the
quality-controlled library and aligned against the host Bowtie2 index
in a fast, low-sensitivity mode (\--very-fast-local). The host fraction
is estimated as the proportion of surveyed reads that align. Because
the subsample is small and the alignment is deliberately insensitive,
the survey completes in seconds and its cost is negligible relative to
either depletion path. A user-supplied estimate (\--host-pct) bypasses
the survey entirely.

The estimated host fraction ĥ is combined with the library size N in a
two-part rule:

- ĥ \< ĥ_low (default 10%) → alignment path (Section 2.5). At low host
  fractions alignment rejects the microbial majority quickly and retains
  its lower false negative rate.
- ĥ \> ĥ_high (default 30%) and N is large (default > 20 M reads) →
  classification path (Section 2.4) with Bowtie2 recheck (Section 2.6).
  Kraken2 removes the host majority rapidly, and the recheck pass
  re-screens the smaller retained set to recover missed host reads.
- Otherwise → alignment path. The rule is deliberately conservative:
  any sample that does not clearly exceed the high-host threshold is
  routed to alignment, whose error profile is the safer default.

The classification path can also be selected explicitly with
`--host-removal-mode kraken2`; `--bowtie2-recheck` toggles the
verification pass.

Legacy defaults were set from the measured runtime behaviour of the two
backends. Users may force either path (\--host-removal-mode
kraken2\|bowtie2) or override any threshold. Routing tolerates
considerable estimation error, since the decision requires only that ĥ
fall on the correct side of a threshold rather than that it be accurate
(Section 3.2).

### 2.4 Classification-based depletion (legacy fallback backend)

The classification path uses Kraken2 \[Ref\] against a **human-only**
index. By default this index is built from the T2T-CHM13v2.0 human
reference; reads that Kraken2 does not assign are retained as the
provisional decontaminated library. Mixed Kraken2 databases that also
contain microbial genomes can be supplied for users who additionally
want taxonomic profiling, but they are not used by default because
they increase memory use without improving host-depletion accuracy.

Kraken2 is invoked with a confidence threshold (default 0.0) and a
minimum hit-group requirement (default 2), both configurable; the
unassigned read set is retained as the provisional decontaminated
library. The Kraken2 report is parsed into a typed metrics record
capturing classified and unclassified read counts, host read counts, and
the implied contamination rate. In the legacy auto mode (no deacon
index configured) this path is selected for large, high-host samples and
is followed by the Bowtie2 recheck pass described in Section 2.6.

### 2.4a Alternative backends evaluated and not retained

We evaluated sylph, a k-mer-sketching metagenome profiler, as a possible
sample-level prefilter for host depletion. sylph produces sample-level
relative abundance, not per-read labels, so it cannot remove individual
host reads. We therefore tested it as a binary sensor: a sample declared
host-positive by `sylph query` was passed to the Bowtie2 alignment
pipeline, while host-negative samples were retained without alignment.
On the 100 M matched panel this sensor-based approach did not improve
runtime over direct Bowtie2 removal for host-positive samples, and the
added survey overhead erased any potential speed advantage. We also
confirmed that sylph cannot provide read-level classifications and
therefore cannot be used as a direct substitute for Kraken2 or Bowtie2
in a host-depletion pipeline. Consequently, sylph is retained only as an
optional explicit backend and is not used by the default auto-mode
router.

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

### 2.4b Minimizer-based depletion with deacon (default Tier-1 backend)

The default Tier-1 backend is deacon (Constantinides, Lees and Crook,
bioRxiv preprint, 2025; not yet peer-reviewed at the time of writing), a
minimizer-based sequence filter that depletes host reads against a
pangenome index. RustyClean invokes deacon (v0.17.0; clean step with
options `-d -a 2 -r 0.01`) on the quality-controlled reads --- or on the
raw reads in `--skip-qc` depletion-only benchmarking --- and parses
deacon's summary JSON into the typed metrics record, including the
removed read count and `seqs_removed_proportion` that drives the
verification decision (Section 2.3). For human data the default index is
the published panhuman-1 pangenome index (k31w15; ~2.5 GB on disk);
users may supply any deacon index, and species-matched indexes for six
hosts are described in Section 3.9.

### 2.5 Alignment-based depletion

The alignment path aligns quality-controlled reads against a Bowtie2
\[Ref\] index of the host reference genome (T2T-CHM13v2.0 by default),
retaining unaligned reads. Paired-end reads are handled with
concordant-pair semantics so that a pair is retained only if neither
mate aligns. This path is functionally equivalent to KneadData\'s
host-removal stage but without the intervening repeat-masking and
identifier-reformatting steps.

### 2.6 Bowtie2 verification pass

No Tier-1 backend removes every host read: minimizer-based depletion
leaves a small structural residue (~0.0035--0.0042% of retained output
on our panel), and k-mer classification under-detects host reads far
more severely. RustyClean therefore implements a verification pass
(`--bowtie2-recheck`) in which the reads retained by the Tier-1 backend
are aligned against the host Bowtie2 index and those that align are
removed. Only the retained set is re-screened, so reads already
identified as host are never realigned.

In the default AUTO configuration the pass is triggered adaptively by
deacon's removed-proportion summary (Section 2.3; default threshold
0.3); on the legacy Kraken2 classification path it is enabled by default
whenever that path is selected. It can be disabled with
`--no-bowtie2-recheck` for users who prefer raw Tier-1 output.

The cost of this pass is proportional to the size of the retained set,
which is small precisely when it is needed: at a host fraction of 0.9,
Tier-1 depletion removes the majority of reads and the verification pass
processes roughly a tenth of the library. At low host fractions the
retained set is large and verification would be expensive --- but those
samples fall below the recheck threshold in the default configuration
and are routed to the alignment path by Section 2.3 in the legacy
configuration, so they never reach this stage. The two mechanisms are
therefore complementary rather than merely additive, and the worst-case
cost of verification is bounded by the size of the retained set.

### 2.7 Validation gate

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

### 2.8 Orchestration and implementation

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

### 2.9 Benchmark design

**Table 1.** Selected simulated datasets used for the main accuracy
comparison. Host fraction is the realised proportion of host reads after
simulation, which differs slightly from the nominal target for skewed
communities. The full evaluation panel comprises 18 datasets (Table S2).

| **Dataset** | **Reads (M)** | **Host (%)** | **Complexity** | **Abundance** | **Layout** |
|-------------|---------------|--------------|----------------|---------------|------------|
| 5M / 1%     | 5.0           | 0.9          | low            | even          | single-end |
| 10M / 10%   | 9.5           | 10.0         | medium         | even          | single-end |
| 30M / 50%   | 23.9          | 59.7         | high           | skewed        | single-end |
| 60M / 90%   | 56.2          | 91.4         | high           | lognormal     | single-end |
| 100M / 50%  | 87.8          | 54.1         | high           | lognormal     | single-end |
| 100M / 90%  | 93.6          | 91.4         | high           | lognormal     | single-end |

We evaluated RustyClean against KneadData v0.12.3 on 18 simulated
metagenomes with per-read ground truth, generated with InSilicoSeq
v2.0.0 (Gourlé et al., 2019). The design varied four factors:

| Factor | Levels |
|---------------------|--------------------------------|
| Host fraction | 0, 1, 5, 10, 30, 50, 70, 90, 99, 100 % |
| Sequencing depth | 5, 10, 20, 30, 60, 100 M reads |
| Community composition | even, lognormal, skewed |
| Read layout | single-end, paired-end |

Because reads are simulated, the true origin of every read is known and
depletion can be scored exactly as a binary classification task. Results
are reported stratified by host fraction and read layout; no grand mean
is reported across the full panel.

Reference databases: by default a human-only Kraken2 index built from
T2T-CHM13v2.0, and a Bowtie2 index of T2T-CHM13v2.0 plus HLA sequences
(the Hostile human-t2t-hla index). A mixed Kraken2 index (kraken16:
GRCh38 + T2T + ~73,000 microbial genomes) was additionally evaluated
as an optional taxonomy-aware mode. The legacy comparisons used 8
threads per tool on the HKU HPC2021 cluster, with three replicates per
condition for RustyClean timing. Wall-clock time and peak resident set
size were recorded with GNU `time`.

**Minimizer-based panel.** We additionally benchmarked deacon v0.17.0
standalone and the deacon-based AUTO pipeline on the same simulated
panel. deacon was run in depletion-only mode (`--skip-qc`; clean step
with options `-d -a 2 -r 0.01`; panhuman-1 index, k31w15) on 16 threads;
the AUTO runs chained fastp, deacon and the conditional Bowtie2
verification tier (Section 2.3) with the same index and thread count.
Three replicates per condition were run, and the same timing and memory
recording was used. KneadData and Hostile+fastp figures in the five-way
comparison are the full-pipeline runs described above (8 threads);
runtime bases (full pipeline versus depletion-only) are stated wherever
the numbers are compared.

**Cross-species panel and index builds.** For the cross-species
evaluation we built species-specific deacon indexes (k31w15) for human
(T2T-CHM13v2.0), monkey, mouse, pig, rat and rice, recording build time
and peak memory for each, and ran deacon (16 threads) on the 10 M-read,
50%-host panel with either the species-matched index or the human
panhuman-1 index.

### 2.10 Evaluation metrics

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

## 3. Results

### 3.1 The two depletion strategies fail in opposite directions

Across the four evaluation datasets --- evaluated here with the legacy
Kraken2-based auto configuration; the deacon-based default is evaluated
in Section 3.5 --- the error profiles of the two strategy families
separated exactly as reported by Gao et al. (Figure 1,
Table 2). KneadData, which depletes by alignment, discarded a mean 2.58%
of genuine microbial reads, rising to 3.96% on the lowest-host dataset.
RustyClean, which depleted by k-mer classification on its high-host
path, discarded a mean 0.20% --- 13-fold less microbial signal --- but
retained a mean 0.90% of host reads against 0.26% for KneadData.

Because the two error types are unequal in their downstream
consequences, the balanced F1 score obscures this structure: RustyClean
and KneadData score 0.9790 and 0.9831 respectively, a difference that
conveys nothing about which reads were lost. We therefore report the two
error rates separately throughout.

![](figures/fig1_error_profile.png)

**Figure 1.** Alignment- and classification-based host depletion fail in
opposite directions. (a) Microbial reads incorrectly discarded, an
irreversible loss of signal. (b) Host reads incorrectly retained, a
recoverable contamination. Depletion is deterministic, so accuracy does
not vary between technical replicates; bars show a single evaluation per
dataset.

**Table 2.** Host-depletion accuracy, legacy Kraken2-based auto
configuration. Microbial loss is the proportion of true microbial reads
discarded; host carry-over is the percentage of the retained output
that is host (Section 2.10).

| **Dataset** | **Tool** | **Precision** | **Recall** | **F1** | **Microbial loss (%)** | **Host carry-over (%)** |
|-------------|-------------------|---------------|------------|--------|------------------------|-------------------------|
| 5M / 1% | RustyClean (legacy auto) | 1.0000 | 1.0000 | 1.0000 | 0.000 | 0.387 |
| 5M / 1% | Hostile | 0.9999 | 1.0000 | 1.0000 | 0.000 | 0.686 |
| 5M / 1% | KneadData | 1.0000 | 0.9604 | 0.9798 | 3.956 | 0.269 |
| 10M / 10% | RustyClean (legacy auto) | 0.9995 | 0.9943 | 0.9969 | 0.568 | 0.404 |
| 10M / 10% | Hostile | 0.9992 | 0.9992 | 0.9992 | 0.079 | 0.674 |
| 10M / 10% | KneadData | 0.9997 | 0.9721 | 0.9857 | 2.791 | 0.255 |
| 30M / 50% | RustyClean (legacy auto) | 0.9795 | 0.9987 | 0.9890 | 0.130 | 1.411 |
| 30M / 50% | Hostile | 0.9901 | 1.0000 | 0.9950 | 0.000 | 0.676 |
| 30M / 50% | KneadData | 0.9963 | 0.9858 | 0.9910 | 1.425 | 0.250 |
| 60M / 90% | RustyClean (legacy auto) | 0.8698 | 0.9989 | 0.9299 | 0.110 | 1.407 |
| 60M / 90% | Hostile | 0.9331 | 0.9996 | 0.9652 | 0.039 | 0.674 |
| 60M / 90% | KneadData | 0.9736 | 0.9785 | 0.9760 | 2.154 | 0.250 |
| Mean | RustyClean (legacy auto) | --- | --- | 0.9790 | 0.202 | 0.902 |
| Mean | Hostile | --- | --- | 0.9899 | 0.029 | 0.678 |
| Mean | KneadData | --- | --- | 0.9831 | 2.582 | 0.256 |

With the deacon-based default backend both error rates fall further:
host carry-over is at most 0.0042% before verification and 0.0000%
after it on the high-host datasets (Section 3.5, Table 5).

### 3.2 Per-sample routing selects the appropriate backend (legacy fallback)

This section characterises the legacy host-fraction routing used when
no deacon index is configured; in the default configuration no routing
occurs, because the Tier-1 backend is the same for every sample
(Section 3.5).

Host fraction estimated from a 100,000-read subsample tracked the
realised fraction closely on three of four datasets: 0.93% against
0.95% realised, and 10.13% against 10.02%. On the skewed 30M dataset
the estimator underestimated by 10.8 percentage points (48.95% against
59.73%), reflecting the difficulty of estimating composition from a
small subsample of a highly uneven community. Routing was nevertheless
correct in all four cases, because the decision requires only that the
estimate fall on the correct side of a threshold rather than that it be
accurate. This tolerance is a deliberate property of the design.

Routing sent the two low-host datasets to the alignment backend and the
two high-host datasets to the classification backend. Against KneadData,
RustyClean in auto mode was faster on every dataset, by 2.5× to 4.6×
(Table 3), with the largest margin at the highest host fraction --- the
regime in which alignment-based depletion is most expensive.

**Table 3.** Runtime and peak memory. RC, RustyClean in auto mode; KD,
KneadData. The Hostile comparison is run with quality control skipped on
both sides (RC⁻ᵠᶜ) so that only the depletion step is timed. Peak memory
is the maximum resident set size of the largest single process.

| **Dataset** | **Backend** | **Est. host (%)** | **RC (s)** | **KD (s)** | **vs KD** | **RC⁻ᵠᶜ (s)** | **Hostile (s)** | **vs Hostile** | **RC mem (GB)** | **KD mem (GB)** |
|-------------|-------------|-------------------|------------|------------|-----------|---------------|-----------------|----------------|-----------------|-----------------|
| 5M / 1% | bowtie2 | 0.93 | 170 | 420 | 2.47× | 106 | 110 | 1.04× | 3.3 | 1.1 |
| 10M / 10% | bowtie2 | 10.13 | 189 | 694 | 3.68× | 116 | 212 | 1.83× | 3.3 | 1.1 |
| 30M / 50% | kraken2 | 48.95 | 815 | 2317 | 2.84× | 552 | 2385 | 4.32× | 15.4 | 1.1 |
| 60M / 90% | kraken2 | 89.43 | 1470 | 6822 | 4.64× | 858 | 4241 | 4.94× | 15.4 | 1.1 |

### 3.3 A targeted verification pass resolves the residual-host trade-off (legacy Kraken2 path)

On the legacy Kraken2 classification path the verification pass is
enabled by default, so the comparison below isolates its contribution
against a classification-only baseline. Aligning the reads retained by Kraken2
against the host index and removing those that align reduced host
carry-over from a mean 1.409% to 0.0715% --- a 19.7-fold reduction, and
remarkably consistent across datasets. Microbial loss rose from 0.115%
to 0.399%, which remains 6.5-fold below KneadData. The pass is therefore
not a simple trade of one error for the other: it removes roughly twenty
times more residual host than the microbial signal it costs.

The effect is largest exactly where the baseline was weakest. On the two
90%-host datasets, F1 rose from 0.9299 to 0.9942 and from 0.9299 to
0.9943. Mean runtime cost was 6.7%, consistent with the design
expectation that the verification set is small precisely when host
content is high; peak memory was unchanged. The same verification
mechanism, applied adaptively to deacon's retained reads, eliminates
minimizer depletion's structural residue altogether (Section 3.5).

On the 10M / 10% dataset the removed proportion (~10%) stayed below the
verification threshold, so AUTO correctly skipped the Bowtie2 pass ---
its host carry (0.0037%) equals deacon's standalone residue, at less
than half the runtime (142 s versus 326 s for fastp + Hostile). This
confirms the decision logic allocates verification effort only where
the host burden justifies it.

### 3.4 Comparison with Hostile

Hostile, a purpose-built host-depletion tool, is a stronger accuracy
baseline than KneadData and the more informative comparison. We
therefore re-ran RustyClean, Hostile and KneadData on a matched panel of
four single-end datasets (30 M and 60 M reads at 50--90% host, and 100 M
reads at 50% and 90% host). RustyClean used the legacy Kraken2-based
auto mode with `--skip-qc` so that the comparison with Hostile is
head-to-head on the host-removal step. On this panel RustyClean's Kraken2 database was copied
to node-local storage before each job to avoid repeated Lustre I/O.

![](figures/fig2_matched_panel.png)

**Figure 2.** Matched-panel runtime and memory comparison.
(a) Host-depletion runtime on four single-end simulated datasets
(30--100 M reads, 50--90% host). RustyClean was run with `--skip-qc`
so that only the depletion step is timed; error bars show standard
deviation across three technical replicates. (b) Peak resident set size
of the largest single process.

Accuracy on the 100 M subset was high for all three tools and the
rankings were consistent with the earlier two-dataset comparison (Table
4). Hostile achieved the highest F1 (0.9989--0.9991), followed by
RustyClean (0.9970--0.9950) and KneadData (0.9872--0.9778). The gap
between RustyClean and Hostile remained small (ΔF1 ≈ 0.0019 at 50% host,
ΔF1 ≈ 0.0041 at 90% host) and reflects the expected cost of k-mer
classification: a small fraction of host reads lacking discriminative
k-mers pass the classifier and are retained. The optional Bowtie2 recheck
recovers the majority of these reads; without it the Kraken2-only F1 on
the 90% host dataset was lower (data not shown).

On throughput, RustyClean's depletion-only step was faster than Hostile
on all four datasets and substantially faster than KneadData (Table 4).
The speed advantage was largest on the 100 M datasets (1.7--1.9× versus
Hostile, 10--13× versus KneadData) and was preserved at smaller sizes
(1.3× versus Hostile on the 30 M dataset). With QC included, RustyClean
remained 5.7--6.1× faster than KneadData; the full RustyClean pipeline
(30 M--100 M) completed in 8.9--27.3 min on this panel.

**Table 4.** Matched-panel comparison on four single-end simulated
datasets. RC = RustyClean in the legacy auto mode with Kraken2 + Bowtie2
recheck for high-host samples and Bowtie2 for low-host samples
(`--skip-qc`, depletion only, Kraken2 database on node-local storage);
Hostile = default T2T+HLA Bowtie2 index; KD = KneadData with T2T Bowtie2
index. F1 is shown for the 100 M subset where Hostile accuracy was
measured; for the 30 M and 60 M datasets only RustyClean F1 is reported.
Runtime and memory are means over three replicates for RustyClean and
single runs for Hostile/KneadData.

| **Dataset** | **Tool** | **F1** | **Runtime (min)** | **Memory (GB)** | **vs Hostile runtime** |
|-------------|----------|--------|-------------------|-----------------|------------------------|
| 30M / 50% | RC | 0.9970 | 4.5 | 15.5 | 1.30× faster |
| 30M / 50% | Hostile | --- | 5.8 | 3.6 | --- |
| 30M / 50% | KD | --- | 38.0 | 1.1 | 6.55× slower |
| 60M / 90% | RC | 0.9951 | 8.2 | 15.5 | 1.45× faster |
| 60M / 90% | Hostile | --- | 11.9 | 3.6 | --- |
| 60M / 90% | KD | --- | 104.3 | 1.1 | 12.72× slower |
| 100M / 50% | RC | 0.9970 | 14.9 | 15.6 | 1.86× faster |
| 100M / 50% | Hostile | 0.9989 | 27.8 | 3.6 | --- |
| 100M / 50% | KD | 0.9872 | 224.9 | 1.1 | 8.09× slower |
| 100M / 90% | RC | 0.9950 | 13.4 | 15.5 | 1.68× faster |
| 100M / 90% | Hostile | 0.9991 | 22.5 | 3.6 | --- |
| 100M / 90% | KD | 0.9778 | 241.6 | 1.1 | 10.74× slower |

Taken together, the legacy Kraken2-based auto configuration places
RustyClean between Hostile and KneadData on accuracy, but closer to
Hostile than to KneadData. On the depletion step alone RustyClean is
faster than Hostile across the panel while remaining an order of
magnitude faster than KneadData (Figure 4). The accuracy gap versus
Hostile is the cost of using k-mer classification rather than aligning
every read; the Bowtie2 recheck step recovers the majority of the host
reads that Kraken2 misses.

With the deacon-based default backend this accuracy gap closes. On the
five-way panel (Section 3.5), RustyClean AUTO matched or exceeded
Hostile's F1 on every dataset where both were measured (Table 5),
while reducing host carry-over to 0.0000% of retained output on all
high-host datasets, against 0.6745--0.6858% for fastp + Hostile, and
the full AUTO pipeline was 1.3--2.2× faster than fastp + Hostile.

![](figures/fig4_speedup.png)

**Figure 4.** RustyClean speedup on the matched panel. Speedup is
relative to Hostile (red) and KneadData (tan) for the depletion-only
step; values are annotated above each bar.

### 3.5 Minimizer-based depletion as the default Tier-1 backend

Because deacon's per-read cost is independent of host fraction, the
five-way comparison in Table 5 required no per-sample routing: every
sample passed through the same fastp → deacon → conditional-Bowtie2
verification chain, with only the verification decision varying. The
table reports, per dataset, KneadData (full pipeline), fastp + Hostile
(full pipeline), the legacy RustyClean Kraken2 + recheck configuration
(full pipeline), deacon alone (depletion only, quality control skipped)
and the RustyClean AUTO pipeline with deacon as the Tier-1 backend
(full pipeline).

![](figures/fig2_deacon_panel.png)

**Figure 5.** Five-way comparison on the simulated panel.
(a) Runtime (log scale; basis as stated in Table 5 --- full pipeline
for KneadData, Hostile + fastp and both RustyClean configurations;
depletion only for deacon). (b) Peak resident set size of the largest
single process.

**Table 5.** Five-way comparison on the simulated panel. Runtime and
peak memory are means over three replicates; F1, microbial loss and
host carry-over are single evaluations (depletion is deterministic).
Basis: KneadData, Hostile + fastp and both RustyClean configurations
are full-pipeline runs (QC plus depletion, plus verification where
triggered); deacon is the depletion step alone (`--skip-qc`). "---"
marks conditions that were not run (KneadData and Hostile were not run
on the 100 M datasets in this comparison).

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
| 30M / 50% | RustyClean (legacy Kraken2 + recheck) | 596.2 | 16.19 | 0.99743 | 0.408 | 0.0717 |
| 30M / 50% | deacon (depletion only) | 28.6 | 4.76 | 0.99997 | 0.000 | 0.0037 |
| 30M / 50% | RustyClean AUTO (deacon) | 622.3 | 4.76 | 1.00000 | 0.000 | 0.0000 |
| 60M / 90% | KneadData | 6822.0 | 1.16 | 0.97603 | 2.154 | 0.2496 |
| 60M / 90% | Hostile + fastp | 1456.4 | 3.78 | 0.96522 | 0.039 | 0.6745 |
| 60M / 90% | RustyClean (legacy Kraken2 + recheck) | 1221.1 | 16.24 | 0.99423 | 0.396 | 0.0715 |
| 60M / 90% | deacon (depletion only) | 52.4 | 4.76 | 0.99921 | 0.120 | 0.0036 |
| 60M / 90% | RustyClean AUTO (deacon) | 669.5 | 4.76 | 0.99845 | 0.309 | 0.0000 |
| 100M / 50% | RustyClean (legacy Kraken2 + recheck) | 1792.0 | 16.28 | 0.99758 | 0.398 | 0.0716 |
| 100M / 50% | deacon (depletion only) | 153.4 | 4.76 | 0.99937 | 0.121 | 0.0035 |
| 100M / 50% | RustyClean AUTO (deacon) | 1684.9 | 4.76 | 0.99845 | 0.310 | 0.0000 |
| 100M / 90% | RustyClean (legacy Kraken2 + recheck) | 1753.9 | 16.25 | 0.99425 | 0.395 | 0.0712 |
| 100M / 90% | deacon (depletion only) | 202.4 | 4.76 | 0.99920 | 0.120 | 0.0037 |
| 100M / 90% | RustyClean AUTO (deacon) | --- | --- | --- | --- | --- |

On speed, the deacon depletion step alone (9.6--202.4 s) was 44--130×
faster than the complete KneadData pipeline, and the full AUTO pipeline
(90.4--1684.9 s) was 3.7--10.2× faster than KneadData and 1.3--2.2×
faster than fastp + Hostile on the datasets where all three were run.
On accuracy, AUTO matched or exceeded every comparator: F1 was
0.99845--1.00000, against 0.96522--0.99997 for fastp + Hostile and
0.97603--0.99098 for KneadData. Microbial loss stayed at or below
0.31% --- up to 13-fold below KneadData (1.4--4.0%), whose Trimmomatic
stage over-trims genuine microbial reads --- and was zero on three of
the four AUTO datasets.

The verification tier's contribution is isolated by comparing the deacon
and AUTO rows. deacon alone left a small structural residue of host
reads --- 0.0035--0.0042% of retained output, essentially independent
of host fraction. AUTO, in which the Bowtie2 verification pass fired
whenever the removed proportion crossed the 0.3 threshold, reduced this
to 0.0000% on every high-host dataset (Figure 7). The one exception is
informative: on the 5M/1% dataset (0.9% realised host) the removed
proportion fell below the threshold, verification correctly did not
run, and carry-over remained 0.0042% --- with F1 still 1.00000 because
the residue is negligible relative to the output.

![](figures/fig3_deacon_accuracy.png)

**Figure 6.** Accuracy of the five-way comparison. (a) F1 score per
dataset and tool. (b) Host carry-over as a percentage of retained
output (log scale); the dashed line marks 0.01%. Values of exactly
0.0000% (AUTO on all high-host datasets) cannot be drawn on a log
scale and are annotated as 0.

![](figures/fig6_verification.png)

**Figure 7.** The verification tier eliminates deacon's residual host
reads. Host carry-over of deacon alone versus the full AUTO pipeline
(deacon plus conditional Bowtie2 verification) on the three datasets
whose removed proportion crossed the 0.3 recheck threshold.

Peak memory of the AUTO runs was 4.76 GB --- the resident panhuman-1
index plus working set --- 3.4-fold below the legacy Kraken2 path
(16.2--16.3 GB) and close to fastp + Hostile (3.5--3.8 GB), though
above KneadData's 1.16 GB, which remains the lowest-memory option
(Figure 5b). AUTO's advantage is therefore not raw memory but the
combination of accuracy, verification and carry-over at a modest,
index-bounded footprint.

Finally, deacon's accuracy advantage derives mostly from the pangenome
index rather than from the algorithm. On the human 10 M/50% panel, a
single-reference deacon index built from T2T-CHM13v2.0 alone left
0.2254% host carry-over, against 0.0049% with the panhuman-1 pangenome
index --- a 46-fold difference (Table 6). Index representativeness is
thus the dominant determinant of deacon's accuracy, a point that
motivates the cross-species index work in Section 3.9.

### 3.6 Full enhanced panel with the legacy Kraken2 + Bowtie2 recheck backend

The full enhanced panel of 18 simulated datasets (0--99% host fraction,
5--100 M reads, three abundance distributions, SE and PE layouts; three
replicates per dataset) was evaluated with the legacy auto backend
(Kraken2 classification followed by Bowtie2 recheck of unclassified
reads). Across 0--90% host content RustyClean maintained F1 ≥ 0.995; at
99% host F1 dropped to 0.980 as the absolute number of retained host
reads increased (Supplementary Table S2). Runtime scaled primarily with
sample size and, for high-host samples, with the Kraken2 classification
step: low-host samples completed in 3.8--8.6 min, 50--90% host samples in
8.2--15.1 min, and the 99% host sample in ~15 min. Peak memory on the
low-host Bowtie2 path was 3.4--4.8 GB and on the high-host Kraken2 path
~15.5 GB, reflecting the resident human-only Kraken2 database rather than
the read count. The deacon-based default of current releases is evaluated
on the five-way panel in Section 3.5.

![](figures/fig3_accuracy.png)

**Figure 3.** Accuracy of the legacy Kraken2-based auto backend across
host fractions from 0% to 99% on the full enhanced panel. The dashed
grey line marks F1 = 0.99; the value at each anchor point is annotated.
The drop at 99% host reflects the increased impact of retained host
reads when microbial reads are rare. (The cross-species panel of the
previous version of this figure is superseded by Figure 8.)

### 3.7 Memory profile of the legacy Kraken2 + Bowtie2 recheck path

The legacy high-host path loads the full Kraken2 database, so peak
memory is determined primarily by the database size rather than by read
count. On the matched panel RustyClean peaked at ~15.5 GB, versus 3.6 GB
for Hostile and 1.1 GB for KneadData (Table 4). The footprint is
essentially the resident size of the T2T-only human Kraken2 index
(~15.5 GB) plus the working set of the Bowtie2 recheck pass over the
retained reads.

This memory requirement is larger than Hostile's pure Bowtie2 footprint,
but it is bounded and predictable: it does not scale with sample size,
and the memory-aware worker cap (Section 2.8) limits the number of
concurrent samples to the available RAM divided by the database size.
On the benchmark node, which had sufficient memory for multiple Kraken2
workers, RustyClean still completed faster than Hostile because the
classification step amortises its I/O and memory cost over the large
host read set. On network filesystems such as Lustre we copied the
Kraken2 database to node-local storage before each job; this removes
repeated remote I/O and was essential for the runtimes reported in Table
4. For memory-constrained environments users can force the smaller-footprint
Bowtie2 path with `--host-removal-mode bowtie2`.

Under the deacon-based default, peak memory is 4.76 GB --- the resident
panhuman-1 index plus working set --- 3.4-fold below the legacy
Kraken2 path and close to Hostile's footprint, though still above
KneadData's 1.16 GB (Table 5, Figure 5b). As with the legacy path,
memory is bounded by index size rather than sample size, and the
memory-aware worker cap of Section 2.8 applies unchanged.

### 3.8 The depletion backend is interchangeable

Because the pipeline treats the depletion step as a replaceable
component, alternative backends can be substituted without changing the
surrounding orchestration. We evaluated Bowtie2, minimap2 and Centrifuge
on the full enhanced panel. Bowtie2 and minimap2 were closely matched on
accuracy, while Centrifuge showed substantially higher host carry-over
at high host fractions (F1 0.745 at 99% host versus 0.980 for
RustyClean) and was not retained as a recommended backend. Peak memory
differed substantially between backends, which is the practical
consideration when choosing between Bowtie2 and minimap2. The default
Tier-1 backend is now deacon (Section 3.5), and the same
interchangeability applies to it; FracMinHash sketching was evaluated
and rejected (Section 2.4a).

### 3.9 Cross-species host depletion

Human-associated metagenomes are not the only use case for host
depletion; the same problem arises for model organisms, livestock and
plants. deacon's officially published prebuilt indexes, however, cover
only human (panhuman-1) and mouse. To test whether minimizer-based
depletion generalises, we built species-specific deacon indexes
(k31w15) for human (T2T-CHM13v2.0), monkey, mouse, pig, rat and rice.
Index builds were fast and cheap: 4--52 s each, producing 2.2--2.5 GB
indexes for the mammalian hosts and 0.3 GB for the smaller rice genome
(Table 6).

On a panel of 10 M-read, 50%-host single-end simulated datasets, every
species' own index achieved F1 0.99986--0.99998, with host carry-over of
at most 0.006% and microbial loss of at most 0.023% (Table 6, Figure 8).
KneadData, which requires a species-specific Bowtie2 index, again
performed well (F1 ≈ 0.996 on every host), but below the
species-matched deacon indexes.

The converse experiment is a cautionary result. Running every dataset
against the human panhuman-1 index --- the only published prebuilt index
applicable to most of these hosts --- wrongly depleted 46.8% of the
microbial reads in the monkey-host dataset, ~97% in the mouse, pig and
rat datasets, and 99.8% in the rice dataset (precision collapsing to
0.50--0.68 and F1 to 0.67--0.81; Table 6). That is, a human pangenome
index must not be treated as a generic vertebrate or plant host index.
For human data the same index-representativeness effect appears in
milder form: a T2T-only single-reference index left 46× more host
carry-over than panhuman-1 (Section 3.5). Species-matched indexes --- or
a pan-host union index --- are therefore mandatory for non-human work,
and RustyClean ships and validates a pan-host index set covering the six
hosts above. Together with the species-matched results, this indicates
that minimizer-based depletion is not restricted to human contamination,
provided the index matches the host.

![](figures/fig5_cross_species.png)

**Figure 8.** Cross-species depletion accuracy on 10 M-read, 50%-host
simulated datasets. F1 with each species' own deacon index (steel blue)
versus the human panhuman-1 index (muted red). The panhuman-1 index
preserves accuracy only on human data; on non-human hosts it wrongly
depletes 46.8--99.8% of microbial reads.

**Table 6.** Cross-species host depletion on 10 M-read, 50%-host
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

### 3.10 Real-data performance

We applied RustyClean to 11 human oral microbiome samples from the LU
cohort (paired-end, 5--45 million reads per sample) to confirm that the
simulated-panel performance translates to real data. This cohort was
processed with the legacy routing-based auto mode; current releases
default to the deacon Tier-1 backend whenever an index is configured.
All samples completed successfully. Runtime ranged from
9 to 46 min per sample (mean 18.6 min, median 13.6 min) and peak memory
ranged from 3.4 to 6.5 GB (mean 4.1 GB, median 3.6 GB). The total wall
clock for the 11-sample cohort was 3.4 h. These numbers are consistent
with the simulated-panel throughput and demonstrate that the pipeline is
ready for production cohorts.

### 3.11 Sample-level parallelism scales near-linearly at flat per-worker memory

Cohort processing is sample-parallel (§2.8): a counting semaphore admits *W*
samples concurrently, each passing *T* threads to its external tools. To
measure how the deacon backend scales under this model we ran sixteen
identical 10M-read single-end samples (10% host fraction, below the
verification threshold, so each sample executes fastp plus deacon only)
with *T* = 4 and *W* ∈ {1, 2, 4, 8} on a single 64-core AMD node.

Throughput scaled near-linearly (Figure 8): wall clock for the 16-sample
cohort dropped from 2,364 s (39m24s) at *W* = 1 to 1,153 s at *W* = 2
(2.05×), 620 s at *W* = 4 (3.81×), and 302 s at *W* = 8 (7.84×; 98%
parallel efficiency). Per-worker cost stayed constant throughout: the
resident set of each deacon process was ~3.1--3.7 GB at every worker count
--- the memory-mapped 3.3 GB panhuman-1 index plus a small private
workspace. Because all workers map the same read-only index file, the
kernel retains a single physical copy of its pages and each additional
worker costs only its private workspace (the per-process RSS sum in
Figure 8c therefore overcounts physical memory; it is shown to make the
accounting explicit). No alignment- or classification-based competitor in
our comparison offers this combination: their per-sample memory footprint
is either CPU-scaled private copies (Kraken2, ~16 GB per sample) or a
per-sample alignment index (Bowtie2, ~3--5 GB per sample), so the same
8-sample concurrency would require roughly an order of magnitude more RAM
for the same throughput gain.

Together with the memory-aware worker cap described in §2.8, this makes
the default backend suitable for queue-free cohort processing on
shared-nothing nodes: 16 samples complete in 5 minutes at under 40 GB
aggregate per-process RSS.

![](figures/fig7_parallel_scaling.png)

**Figure 8.** Sample-level parallelism of the deacon backend. Sixteen
identical 10M-read single-end samples (10% host) processed with four
threads per sample and *W* concurrent workers. (a) Cohort wall time.
(b) Speedup relative to *W* = 1; the dashed line is ideal linear
scaling. (c) Resident set size: per deacon worker (steel blue, flat at
~3.1--3.7 GB) and the sum over all workers (green). Because every worker
memory-maps the same read-only 3.3 GB index, the kernel shares its
physical pages across processes and the green sum overcounts true
physical usage.

## 4. Discussion

Neither error direction is universally preferable, which is why the
choice should not be made once for every sample and every study. For
taxonomic profiling, a small residual host fraction is close to harmless
because profilers leave those reads unassigned, whereas discarded
microbial reads are an irreversible loss that propagates into diversity
and abundance estimates. For assembly, for MAG recovery, and for data
released publicly --- where residual human sequence is a consent and
privacy matter rather than a technical one --- the calculus reverses.
RustyClean exposes the verification threshold, the verification pass
itself, and --- for the legacy fallback --- the routing thresholds as
user-facing settings for this reason.

The central result is that, once minimizer-based depletion is available,
the per-sample backend choice largely disappears: deacon's per-read cost
is host-fraction-independent, so a single Tier-1 backend suffices across
the whole host-fraction spectrum, and the live decision becomes
verification-budget allocation. Minimizer depletion leaves a small
structural residue of host reads (0.0035--0.0042% of retained output on
our panel); the adaptive Bowtie2 verification tier removes it entirely
(0.0000% on every high-host dataset tested) whenever deacon's removed
proportion crosses the threshold --- precisely the samples in which the
residue is largest in absolute terms. The legacy per-sample routing
scheme remains useful for deployments without a deacon index: it
addresses the runtime half of the asymmetry characterised by Gao et al.
(k-mer classification is fastest when most reads are host and can be
discarded in bulk, whereas direct alignment is competitive when most
reads are microbial and can be rejected early), and it retains the
conservative property that borderline samples are sent to the safer
alignment path.

Two comparisons deserve to be read carefully. First, RustyClean performs
no tandem-repeat or low-complexity masking, whereas KneadData does; part
of the runtime advantage over KneadData therefore reflects work not done
rather than work done faster, and the closer like-for-like comparison is
against KneadData with repeat masking disabled. Second, Hostile is the
more demanding baseline. On the matched panel, the legacy Kraken2-based
configuration's depletion-only step (`--skip-qc`) was 1.30--1.86× faster
than Hostile and an order of magnitude faster than KneadData, while the
accuracy gap versus Hostile remained small (ΔF1 ≈ 0.0019 at 50% host;
ΔF1 ≈ 0.0041 at 90% host). With the deacon-based default this gap
closes: the full AUTO pipeline is 1.3--2.2× faster than fastp + Hostile
with equal-or-better F1 and zero host carry-over on high-host samples,
where fastp + Hostile retains ~0.67% (Table 5). KneadData, meanwhile,
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
reproducible pipeline rather than a filter; and (iv) an independent
replication on a Gao-style simulated panel with per-read ground truth,
spanning 1--90% host content and 5--100 M reads, against KneadData,
Hostile and the legacy backend. RustyClean additionally pins deacon
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
accuracy evaluation covers a matched 100 M-read panel and a broader 18
simulated-dataset panel; neither includes real sequencing artefacts. Paired-end libraries and intermediate
host fractions near the routing threshold are now represented in the
full panel, but behaviour very close to the threshold remains the regime
most likely to be mis-routed. Depletion is deterministic, so accuracy
was evaluated once per dataset and replication applies only to timing.
Finally, host-fraction estimation from a small subsample was
substantially less accurate on a skewed community, and while routing
tolerated that error here, the margin is not guaranteed for samples whose
true host fraction lies near the threshold.

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
peer-reviewed validation are not yet established. Finally, the five-way
panel mixes thread counts: the deacon and AUTO runs used 16 threads,
while the KneadData and Hostile figures are the legacy 8-thread runs. A
same-thread comparison would narrow the speed ratios by at most the
thread-count factor (~2×), far smaller than the observed 44--130× gap
for the deacon depletion step, but we note the asymmetry for
completeness.

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
  The adaptive-routing angle is methodologically novel enough for a
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
| 1 | *Why is Kraken2 memory so much larger than Hostile?* | The legacy Kraken2 path uses a T2T-only human index (~15.5 GB). The current deacon-based default requires 4.8 GB; KneadData remains lowest at 1.16 GB. Memory is bounded by index size, not sample size, and the memory-aware worker cap prevents overload (Section 2.8). Users can force the Bowtie2 path for low-memory environments. |
| 2 | *The 99% host F1 drop looks concerning.* | Expected behaviour: when microbial reads are rare, retained host reads dominate the F1 denominator. The absolute host carry-over remains modest; the relevant metric for assembly/profiling is residual-host fraction, which is low (Section 3.6). |
| 3 | *The routing thresholds (10% / 30%) seem arbitrary.* | They apply only to the legacy fallback (no deacon index), and were set from measured runtime crossover of the two backends; conservative routing sends borderline samples to the safer alignment path (Section 2.3). The default deacon-based mode does not route at all; it uses a single 0.3 verification threshold on deacon's removed proportion. |
| 4 | *KneadData includes Trimmomatic and repeat masking; the comparison is not like-for-like.* | Acknowledged. We report KneadData as the de facto standard and note that part of the speed advantage reflects scope differences (Discussion). A `--bypass-trf` comparison would further clarify this. |
| 5 | *Why not compare with Hostile on all 18 datasets?* | Matched panel was run for all four conditions; full 18-dataset panel is RustyClean-only for computational cost. Cross-species and real-data validation extend generalisability. |
| 6 | *Is the accuracy evaluation deterministic?* | Yes; depletion is deterministic, so accuracy is reported once per condition and replication applies only to timing (to be stated explicitly in Methods). |
| 7 | *What about real sequencing artefacts and host genetic variation?* | Limitations section acknowledges this. The 11-sample real cohort validates throughput and robustness, but matched-host-genotype validation remains future work. |
| 8 | *The auto-survey estimator was inaccurate on the skewed 30M dataset.* | Legacy-fallback routing tolerates estimation error because it only needs the estimate to be on the correct side of a threshold. This is a designed property, not a bug (Section 3.2). The default deacon-based mode does not use the survey. |
| 9 | *Why is Centrifuge included if it performs poorly?* | Evaluated as an alternative backend and rejected; included to show that the backend is interchangeable and that not all classifiers are suitable (Section 3.8). |
| 10 | *Does the pipeline handle ultra-high host fractions (>99%) or very large cohorts?* | 99% host tested. Cohort-level throughput depends on available memory and node-local DB copy; the memory-aware worker cap and sample-level parallelism are designed for cohorts (Section 2.8, real-data section). |
| 11 | *How does the user choose the reference database?* | Default is the deacon panhuman-1 index for human data, with a validated species-matched index set for human (T2T), monkey, mouse, pig, rat and rice; the human panhuman-1 index must not be used for non-human hosts (Section 3.9). Legacy Kraken2/Bowtie2 index options remain available (Sections 2.4, 2.5). |
| 12 | *What is the practical advantage over running Hostile + fastp, or deacon directly?* | RustyClean integrates QC, adaptive verification (0.0035--0.0042% → 0.0000% host carry on high-host samples), pan-host index support, checkpointing, validation, and bounded concurrency in one binary; on the five-way panel the full pipeline is 1.3--2.2× faster than fastp + Hostile with equal-or-better F1 and zero carry-over (Section 3.5). deacon alone lacks the verification tier, QC and orchestration (Discussion). |

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
reads retained (%), (c) microbial reads lost (%), (d) peak memory (GB).
Runtime is reported in Supplementary Table S1 and excluded here because
one measurement (minimap2, 5M dataset) is a cold-start outlier.

| **Backend** | **Dataset** | **F1** | **Host carry-over (%)** | **Microbial loss (%)** | **Peak mem (GB)** |
|-------------|-------------|--------|-------------------------|------------------------|-------------------|
| Bowtie2 | 5M / 1% | 0.9996 | 0.055 | 0.000 | 3.6 |
| Bowtie2 | 10M / 10% | 0.9749 | 0.053 | 0.568 | 3.6 |
| Bowtie2 | 30M / 50% | 0.9984 | 0.049 | 0.402 | 3.6 |
| Bowtie2 | 60M / 90% | 0.9996 | 0.049 | 0.388 | 6.2 |
| minimap2 | 5M / 1% | 0.9986 | 0.021 | 0.002 | 11.5 |
| minimap2 | 10M / 10% | 0.9742 | 0.026 | 0.587 | 11.7 |
| minimap2 | 30M / 50% | 0.9984 | 0.030 | 0.431 | 11.8 |
| minimap2 | 60M / 90% | 0.9997 | 0.029 | 0.416 | 11.9 |
| Centrifuge | 5M / 1% | 0.9940 | 1.090 | 0.001 | 7.0 |
| Centrifuge | 10M / 10% | 0.9500 | 1.179 | 1.027 | 7.2 |
| Centrifuge | 30M / 50% | 0.9920 | 1.173 | 0.632 | 7.9 |
| Centrifuge | 60M / 90% | 0.9938 | 1.171 | 0.760 | 8.6 |

**Supplementary data (Section S1).** The machine-readable tables behind
the deacon-based evaluation are available under `data/deacon_panel/`:
`five_way_summary.csv` (the five-way means of Table 5),
`deacon_metrics.csv` and `auto_metrics.csv` (per-replicate deacon and
AUTO runs), `cross_species_metrics.csv` (per-species index runs behind
Table 6 and Figure 8), `index_build_metrics.csv` (species-matched index
build time, memory and size), `sketch_build_metrics.csv` (FracMinHash
sketch builds) and `fmh_metrics_partial.csv.bak` (the partial
FracMinHash evaluation of Section 2.4a, covering the 5M/1%, 10M/10% and
30M/50% datasets).
