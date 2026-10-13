use anyhow::{anyhow, Result};

/// Processing path selected by the user.
///
/// * **RustyCleanX** (default) fuses Deacon-style minimizer evidence with
///   Cleanifier-style gapped-seed evidence, applies a calibrated conflict
///   resolver, and optionally routes disagreements through Bowtie2.
/// * **Deacon** uses only the minimizer index (fast, compact).
/// * **Cleanifier** uses only the gapped-seed index (sensitive to substitutions).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    /// Dual-index fusion + calibrated conflict resolver (default).
    RustyCleanX,
    /// Minimizer-only depletion (Deacon-style).
    Deacon,
    /// Gapped-seed-only depletion (Cleanifier-style).
    Cleanifier,
}

#[derive(Debug, Clone)]
pub struct Args {
    pub mode: Mode,
    pub r1: String,
    pub r2: Option<String>,
    pub output_prefix: String,
    pub gapped_index: Option<String>,
    pub minimizer_index: Option<String>,
    pub microbial_index: Option<String>,
    pub threads: usize,
    pub batch_size: usize,
    pub profile: Profile,
    pub host_evidence_rule: HostEvidenceRuleArg,
    pub decision_mode: DecisionModeArg,
    pub host_gapped_weight: f64,
    pub host_minimizer_weight: f64,
    pub host_score_remove: f64,
    pub host_score_confident: f64,
    pub microbe_score_rescue: f64,
    pub report: String,
    pub boundary_output: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Profile {
    Privacy,
    Microbiome,
    Mag,
}

impl Profile {
    pub fn parse(value: &str) -> Result<Self> {
        match value.to_ascii_lowercase().as_str() {
            "privacy" => Ok(Self::Privacy),
            "microbiome" => Ok(Self::Microbiome),
            "mag" => Ok(Self::Mag),
            other => Err(anyhow!(
                "unknown profile '{other}'; expected privacy, microbiome, or mag"
            )),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HostEvidenceRuleArg {
    Both,
    Either,
}

impl HostEvidenceRuleArg {
    pub fn parse(value: &str) -> Result<Self> {
        match value.to_ascii_lowercase().as_str() {
            "both" => Ok(Self::Both),
            "either" => Ok(Self::Either),
            other => Err(anyhow!(
                "unknown host evidence rule '{other}'; expected both or either"
            )),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecisionModeArg {
    Fused,
    Hard,
}

impl DecisionModeArg {
    pub fn parse(value: &str) -> Result<Self> {
        match value.to_ascii_lowercase().as_str() {
            "fused" => Ok(Self::Fused),
            "hard" => Ok(Self::Hard),
            other => Err(anyhow!(
                "unknown decision mode '{other}'; expected fused or hard"
            )),
        }
    }
}

impl Args {
    pub fn parse(argv: Vec<String>) -> Result<Self> {
        let mut mode = Mode::RustyCleanX;
        let mut r1 = None;
        let mut r2 = None;
        let mut output_prefix = None;
        let mut gapped_index = None;
        let mut minimizer_index = None;
        let mut microbial_index = None;
        let mut threads = num_cpus();
        let mut batch_size = 2_000;
        let mut profile = Profile::Microbiome;
        let mut host_evidence_rule = HostEvidenceRuleArg::Both;
        let mut decision_mode = DecisionModeArg::Fused;
        let mut host_gapped_weight = 0.5;
        let mut host_minimizer_weight = 0.5;
        let mut host_score_remove = 0.60;
        let mut host_score_confident = 0.80;
        let mut microbe_score_rescue = 1.00;
        let mut report = String::from("rustyclean_x_report.tsv");
        let mut boundary_output = None;

        let mut iter = argv.into_iter();
        while let Some(flag) = iter.next() {
            let mut value = |name: &str| -> Result<String> {
                iter.next()
                    .ok_or_else(|| anyhow!("missing value for {name}"))
            };
            match flag.as_str() {
                "--mode" => {
                    let m = value("--mode")?.to_ascii_lowercase();
                    mode = match m.as_str() {
                        "rustycleanx" => Mode::RustyCleanX,
                        "deacon" => Mode::Deacon,
                        "cleanifier" => Mode::Cleanifier,
                        other => return Err(anyhow!(
                            "invalid --mode '{other}'; expected rustycleanx, deacon, or cleanifier"
                        )),
                    };
                }
                "--r1" => r1 = Some(value("--r1")?),
                "--r2" => r2 = Some(value("--r2")?),
                "--output-prefix" => output_prefix = Some(value("--output-prefix")?),
                "--gapped-index" => gapped_index = Some(value("--gapped-index")?),
                "--minimizer-index" => minimizer_index = Some(value("--minimizer-index")?),
                "--microbial-index" => microbial_index = Some(value("--microbial-index")?),
                "--threads" => threads = value("--threads")?.parse()?,
                "--batch-size" => batch_size = value("--batch-size")?.parse()?,
                "--profile" => profile = Profile::parse(&value("--profile")?)?,
                "--host-evidence-rule" => {
                    host_evidence_rule =
                        HostEvidenceRuleArg::parse(&value("--host-evidence-rule")?)?
                }
                "--decision-mode" => {
                    decision_mode = DecisionModeArg::parse(&value("--decision-mode")?)?
                }
                "--host-gapped-weight" => {
                    host_gapped_weight = value("--host-gapped-weight")?.parse()?
                }
                "--host-minimizer-weight" => {
                    host_minimizer_weight = value("--host-minimizer-weight")?.parse()?
                }
                "--host-score-remove" => {
                    host_score_remove = value("--host-score-remove")?.parse()?
                }
                "--host-score-confident" => {
                    host_score_confident = value("--host-score-confident")?.parse()?
                }
                "--microbe-score-rescue" => {
                    microbe_score_rescue = value("--microbe-score-rescue")?.parse()?
                }
                "--report" => report = value("--report")?,
                "--boundary-output" => boundary_output = Some(value("--boundary-output")?),
                "--help" | "-h" => {
                    print_help();
                    std::process::exit(0);
                }
                other => return Err(anyhow!("unknown argument: {other}")),
            }
        }

        let mode_name = match mode {
            Mode::RustyCleanX => "rustycleanx",
            Mode::Deacon => "deacon",
            Mode::Cleanifier => "cleanifier",
        };

        // Validate index requirements per mode
        let gapped_index = if mode != Mode::Deacon {
            Some(gapped_index.ok_or_else(|| {
                anyhow!("--gapped-index is required for mode '{mode_name}'")
            })?)
        } else {
            gapped_index
        };
        let minimizer_index = if mode != Mode::Cleanifier {
            Some(minimizer_index.ok_or_else(|| {
                anyhow!("--minimizer-index is required for mode '{mode_name}'")
            })?)
        } else {
            minimizer_index
        };

        Ok(Self {
            mode,
            r1: r1.ok_or_else(|| anyhow!("--r1 is required"))?,
            r2,
            output_prefix: output_prefix.ok_or_else(|| anyhow!("--output-prefix is required"))?,
            gapped_index,
            minimizer_index,
            microbial_index,
            threads: threads.max(1),
            batch_size: batch_size.max(1),
            profile,
            host_evidence_rule,
            decision_mode,
            host_gapped_weight,
            host_minimizer_weight,
            host_score_remove,
            host_score_confident,
            microbe_score_rescue,
            report,
            boundary_output,
        })
    }
}

fn num_cpus() -> usize {
    std::thread::available_parallelism()
        .map(|n| n.get())
        .unwrap_or(1)
}

fn print_help() {
    println!(
        "RustyClean-X 0.2.0 — integrated host-depletion platform

USAGE:
  rustyclean-x --r1 READ1 [--r2 READ2] --output-prefix PREFIX [OPTIONS]

MODES:
  --mode rustycleanx    dual-index fusion + calibrated resolver (default)
  --mode deacon         minimizer-only depletion (fast, compact)
  --mode cleanifier     gapped-seed-only depletion (substitution-tolerant)

REQUIRED (per mode):
  --gapped-index <PATH>       gapped-seed hash index  [cleanifier, rustycleanx]
  --minimizer-index <PATH>    minimizer hash index    [deacon, rustycleanx]

INPUT:
  --r1 <PATH>                 input R1 or single-end FASTQ
  --r2 <PATH>                 input R2 for paired-end mode
  --output-prefix <PREFIX>    writes PREFIX.keep.fastq + PREFIX.remove.fastq

OPTIONS:
  --microbial-index <PATH>    optional GTDB/microbial witness index
  --profile <NAME>            privacy, microbiome, or mag [default: microbiome]
  --host-evidence-rule <NAME> both or either [default: both; hard mode only]
  --decision-mode <NAME>      fused or hard [default: fused]
  --host-gapped-weight <F>    fused gapped-seed weight [default: 0.5]
  --host-minimizer-weight <F> fused minimizer weight [default: 0.5]
  --host-score-remove <F>     fused score for removal [default: 0.6]
  --host-score-confident <F>  score immune to witness rescue [default: 0.8]
  --microbe-score-rescue <F>  witness score for rescue [default: 1.0]
  --threads <N>               worker threads [default: available parallelism]
  --batch-size <N>            reads per worker batch [default: 2000]
  --report <PATH>             per-read/per-pair evidence TSV
  --boundary-output <PATH>    write ambiguous IDs for optional external alignment
  -h, --help                  show help"
    );
}
