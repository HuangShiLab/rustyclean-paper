# Raw-read metric audit

## Scope and method

This audit starts from archived TP/FP/FN/TN counts, not from summary
percentages. It recognizes two schemas. In the main panel and cross-species
tables, TP is a retained microbe, FP a retained host, FN a lost microbe and
TN a removed host. In the archived backend comparison, TP is a removed host,
FP a lost microbe, FN a retained host and TN a retained microbe. The schema
choice is checked against nominal host fractions. Standardized biological
metrics are microbial loss divided by microbial input, host retention divided
by host input, and host output fraction divided by retained reads.

Raw FASTQ and ground-truth files are not present in this repository snapshot,
so this is a count-level audit of archived outputs plus generator/formula
inspection, not a fresh FASTQ-to-FASTQ replay.

## Verdict by source

Source | Schema | Rows | Formula/label verdict
---|---|---:|---
`accuracy_rc_mm_bt_cf_v4.csv` | REMOVED_HOST | 12 | counts and reported summaries agree under this schema
`accuracy_comparison.csv` | RETAINED_MICROBE | 16 | counts and reported summaries agree under this schema
`auto_metrics.csv` | RETAINED_MICROBE | 15 | counts and reported summaries agree under this schema
`cross_species_metrics.csv` | RETAINED_MICROBE | 12 | counts and reported summaries agree under this schema
`deacon_metrics.csv` | RETAINED_MICROBE | 18 | counts and reported summaries agree under this schema
`fill_100m_metrics.csv` | RETAINED_MICROBE | 3 | counts and reported summaries agree under this schema
`paired_accuracy.csv` | RETAINED_MICROBE | 6 | counts and reported summaries agree under this schema

## Principal findings

1. The main Table 2 sources use the retained-microbe schema. Their F1 values
   are retained-microbe F1. `host_carry_pct` is host reads divided by true
   host input, not by retained output. Thus the apparent near-constant
   Hostile/KneadData rates are input-relative rates and are not, by themselves,
   evidence of a count bug.
2. The RustyClean verification trade-off is real in the archived counts:
   verification removes almost all residual host reads but increases microbial
   FN counts on 60M/90%, 100M/50% and 100M/90%. It should be described as a
   host-removal versus microbial-preservation trade-off, not as an accuracy
   gain.
3. Cross-species counts use the retained-microbe schema. The large panhuman-1
   values are failed host removal (retained monkey/mouse/pig/rat/rice host
   reads), not microbial loss. The archived `microbial_loss_pct` and
   `host_carry_pct` columns are biologically correct, but the manuscript had
   interpreted `host_carry_pct` as microbial loss.
4. The 5--60M Hostile accuracy source is labelled `hostile_raw`, whereas the
   manuscript arm is fastp + Hostile. Thus accuracy and runtime for those
   cells come from different runs. The two 100M Hostile cells come from the
   later fastp + Hostile fill run. The apparent drop in Hostile host
   retention at 100M is therefore a provenance discontinuity, not evidence
   that the count formulas are wrong.
5. The archived backend S1 uses the removed-host schema. Its own
   `Host_Remaining_Rate` and `Microbe_Loss_Rate` formulas are correct, but the
   hardcoded manuscript table/figure mixed formulas and must be regenerated
   from this source.
6. `deacon_metrics.csv` has a malformed header: data rows begin with a tool
   field that is absent from the header. Counts are auditable after adding the
   missing header field, but the file must be fixed for machine readability.
7. The prior revision incorrectly swapped comparator error columns in the
   main summary CSV. That transformation must be reverted; the original
   comparator labels and `fmh_accuracy.py` agree with their raw counts.

## Counts that answer reviewer questions

Dataset | Tool/schema | Input microbes | Input hosts | Microbial loss (%) | Host input retention (%) | Host output fraction (%)
---|---|---:|---:|---:|---:|---:
5M_1pct_low_even_SE | hostile_raw | 4949619 | 47242 | 0 | 0.68583 | 0.00654553
5M_1pct_low_even_SE | kneaddata | 4949619 | 47242 | 3.95634 | 0.268829 | 0.00267148
10M_10pct_med_even_SE | hostile_raw | 8541035 | 950696 | 0.0785268 | 0.674453 | 0.0750755
10M_10pct_med_even_SE | kneaddata | 8541035 | 950696 | 2.79094 | 0.255497 | 0.0292471
60M_90pct_high_lognormal_SE | hostile_raw | 4833421 | 51351173 | 0.0393096 | 0.674454 | 6.68886
60M_90pct_high_lognormal_SE | kneaddata | 4833421 | 51351173 | 2.15406 | 0.249644 | 2.63911
60M_90pct_high_lognormal_SE | deacon | 4833421 | 51351173 | 0.119874 | 0.00357538 | 0.0380166

## Cross-species interpretation

Index | Dataset | Input microbes | Input hosts | Microbial loss (%) | Host input retention (%)
---|---|---:|---:|---:|---:
panhuman | human | 4976915 | 4989143 | 0.00253169 | 0.00493071
human | human | 4976915 | 4989143 | 0.00317466 | 0.225369
panhuman | monkey | 4977280 | 4998408 | 0.00259178 | 46.7752
monkey | monkey | 4977280 | 4998408 | 0.00331506 | 0.00186059
panhuman | mouse | 4977632 | 4999681 | 0.00265186 | 97.0466
mouse | mouse | 4977632 | 4999681 | 0.022581 | 0.00586037
panhuman | pig | 4977240 | 4999435 | 0.00227033 | 96.9668
pig | pig | 4977240 | 4999435 | 0.00303381 | 0.00182021
panhuman | rat | 4977020 | 4999588 | 0.00251154 | 97.1144
rat | rat | 4977020 | 4999588 | 0.00331524 | 0.00596049
panhuman | rice | 4977405 | 4998906 | 0.00243099 | 99.77
rice | rice | 4977405 | 4998906 | 0.0224213 | 0.00258056

## Remaining limits

- The audit cannot detect read-ID collisions or duplicated ground-truth
  labels without the original FASTQ/label files.
- It cannot verify that the correct cleaned FASTQ was selected in historical
  runs, although the archived generators show the intended selection rule.
- The 100M KneadData and Hostile comparator file contains summary rates but
  no TP/FP/FN/TN counts, so those two rows cannot be audited count-by-count.
  They require regeneration from archived outputs or a rerun.
- GNU-time max RSS does not establish aggregate process-tree memory. The
  1.1 GiB KneadData value is therefore not sufficient evidence that its full
  Bowtie2 workflow can run within 1.1 GiB.
- Comparator timing and memory remain unaudited here because raw GNU-time
  logs are not in the repository snapshot.
