use anyhow::Result;
use std::io::{BufWriter, Write};
use std::path::Path;

use crate::filter::Evidence;

pub struct ReportWriter<W: Write> {
    inner: W,
}

impl ReportWriter<BufWriter<std::fs::File>> {
    pub fn from_path(path: impl AsRef<Path>) -> Result<Self> {
        if let Some(parent) = path.as_ref().parent() {
            std::fs::create_dir_all(parent)?;
        }
        let mut inner = BufWriter::new(std::fs::File::create(path)?);
        writeln!(
            inner,
            "id\tdecision\treason\thost_gapped_fraction\thost_minimizer_fraction\tmicrobe_witness_fraction\thost_score\tmicrobe_score\tgapped_component\tminimizer_component"
        )?;
        Ok(Self { inner })
    }
}

impl<W: Write> ReportWriter<W> {
    pub fn write(&mut self, id: &str, evidence: &Evidence) -> Result<()> {
        writeln!(
            self.inner,
            "{}\t{:?}\t{}\t{:.6}\t{:.6}\t{:.6}\t{:.6}\t{:.6}\t{:.6}\t{:.6}",
            id,
            evidence.decision,
            evidence.reason,
            evidence.features.host_gapped_fraction,
            evidence.features.host_minimizer_fraction,
            evidence.features.microbe_witness_fraction,
            evidence.scores.host_score,
            evidence.scores.microbe_score,
            evidence.scores.gapped_component,
            evidence.scores.minimizer_component
        )?;
        Ok(())
    }
}
