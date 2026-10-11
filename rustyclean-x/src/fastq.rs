use anyhow::{anyhow, Result};
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::path::Path;

#[derive(Debug, Clone)]
pub struct FastqRecord {
    pub header: String,
    pub seq: Vec<u8>,
    pub qual: Vec<u8>,
}

impl FastqRecord {
    pub fn id(&self) -> &str {
        let first = self
            .header
            .split_whitespace()
            .next()
            .unwrap_or(&self.header);
        first.strip_prefix('@').unwrap_or(first)
    }
}

pub struct FastqReader<R: BufRead> {
    inner: R,
}

impl FastqReader<BufReader<std::fs::File>> {
    pub fn from_path(path: impl AsRef<Path>) -> Result<Self> {
        Ok(Self {
            inner: BufReader::new(std::fs::File::open(path)?),
        })
    }
}

impl<R: BufRead> FastqReader<R> {
    pub fn from_reader(inner: R) -> Self {
        Self { inner }
    }
}

impl<R: BufRead> FastqReader<R> {
    pub fn next_record(&mut self) -> Result<Option<FastqRecord>> {
        let mut header = String::new();
        if self.inner.read_line(&mut header)? == 0 {
            return Ok(None);
        }
        let mut seq = String::new();
        let mut plus = String::new();
        let mut qual = String::new();
        self.inner.read_line(&mut seq)?;
        self.inner.read_line(&mut plus)?;
        self.inner.read_line(&mut qual)?;
        if !header.starts_with('@') {
            return Err(anyhow!("invalid FASTQ header: {header:?}"));
        }
        if !plus.starts_with('+') {
            return Err(anyhow!("invalid FASTQ plus line: {plus:?}"));
        }
        let seq_raw = seq.trim_end_matches(['\r', '\n']);
        let qual_raw = qual.trim_end_matches(['\r', '\n']);
        if seq_raw.len() != qual_raw.len() {
            return Err(anyhow!(
                "sequence/quality length mismatch for {}",
                header.trim()
            ));
        }
        let header = header.trim_end_matches(['\r', '\n']);
        let header = header.strip_prefix('@').unwrap_or(header);
        Ok(Some(FastqRecord {
            header: header.to_string(),
            seq: seq_raw.as_bytes().to_vec(),
            qual: qual_raw.as_bytes().to_vec(),
        }))
    }
}

pub struct FastqWriter<W: Write> {
    inner: W,
}

impl FastqWriter<BufWriter<std::fs::File>> {
    pub fn from_path(path: impl AsRef<Path>) -> Result<Self> {
        if let Some(parent) = path.as_ref().parent() {
            std::fs::create_dir_all(parent)?;
        }
        Ok(Self {
            inner: BufWriter::new(std::fs::File::create(path)?),
        })
    }
}

impl<W: Write> FastqWriter<W> {
    pub fn flush(&mut self) -> Result<()> {
        self.inner.flush()?;
        Ok(())
    }

    pub fn write(&mut self, rec: &FastqRecord) -> Result<()> {
        self.inner.write_all(b"@")?;
        self.inner.write_all(rec.header.as_bytes())?;
        self.inner.write_all(b"\n")?;
        self.inner.write_all(&rec.seq)?;
        self.inner.write_all(b"\n+\n")?;
        self.inner.write_all(&rec.qual)?;
        self.inner.write_all(b"\n")?;
        Ok(())
    }
}
