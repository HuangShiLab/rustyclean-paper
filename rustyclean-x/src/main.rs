use anyhow::Result;
use rustyclean_x::{cli, pipeline};

fn main() -> Result<()> {
    let args = cli::Args::parse(std::env::args().skip(1).collect())?;
    pipeline::run(Ok(args))
}
