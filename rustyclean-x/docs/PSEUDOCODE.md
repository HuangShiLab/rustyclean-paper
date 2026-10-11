# RustyClean-X implementation pseudocode

## One-pass dual evidence extraction

```text
open R1 and optional R2
open gapped-seed host index
open minimizer host index
open optional microbial witness index

while paired records are available:
    parse R1 and R2 exactly once
    encode bases to 2-bit representation

    # Extract both evidence classes on the same parsed read.
    gapped_hits = 0
    gapped_evaluated = 0
    for mask in gapped_masks:
        for start in 0..=(len(seq)-mask.length):
            hash = hash positions where mask bit == 1
            gapped_evaluated += 1
            if hash is in gapped host index:
                gapped_hits += 1

    minimizer_hits = 0
    minimizer_windows = 0
    for window_start in 0..=(len(seq)-window):
        candidates = all canonical exact k-mers in this window
        if no valid candidate:
            continue
        chosen = hash-minimum canonical candidate
        minimizer_windows += 1
        if chosen is in minimizer host index:
            minimizer_hits += 1

    microbial_hits = optional microbial witness hits

    features = aggregate(gapped_hits, minimizer_hits, microbial_hits)
```

## Default score-fusion classifier

```text
gapped_strength =
    clamp(host_gapped_fraction / T_gapped, 0, 1)

minimizer_strength =
    clamp(minimizer_host_hits / T_minimizer, 0, 1)

microbe_strength =
    clamp(microbial_witness_fraction / T_witness, 0, 1)

host_score =
    (W_gapped * gapped_strength
     + W_minimizer * minimizer_strength)
     / (W_gapped + W_minimizer)
```

The defaults are `W_gapped = W_minimizer = 0.5`,
`T_host_remove = 0.60`, `T_host_confident = 0.80`,
and `T_witness_rescue = 1.00`.  These are implementation defaults, not
trained probabilities.  A separate calibration script must replace them
before making absolute probability claims.

```text
host_remove = host_score >= T_host_remove
host_confident = host_score >= T_host_confident
witness_rescue = microbe_strength >= T_witness_rescue
                 && !host_confident

if witness_rescue:
    decision = KEEP
    reason = microbial witness rescue
elif host_remove:
    decision = REMOVE
    reason = fused host evidence
else:
    decision = BOUNDARY
```

Thus one index reaching its threshold alone has `host_score = 0.5` and is
not sufficient for removal.  Moderate support from both indexes, or very
strong support from one plus some support from the other, can cross the
removal threshold.  This is the intended behaviour of dual-index score
fusion.

## Paired-end boundary resolver

```text
fragment_features = merge(R1_features, R2_features)
fragment_score = score(fragment_features)

mate_host_conflict =
    hard_host(R1) != hard_host(R2)

if mate_host_conflict:
    decision = BOUNDARY
elif fragment_score >= T_host_remove and not witness_rescue:
    decision = REMOVE
elif witness_rescue:
    decision = KEEP
else:
    decision = BOUNDARY
```

Boundary reads are retained in the keep FASTQ and also emitted to the
boundary FASTQ so downstream alignment can process them without losing
microbial signal.

## Legacy hard-decision ablation

```text
host = gapped_host_fraction >= T_gapped
       or minimizer_hits >= T_minimizer

microbe = microbe_witness_fraction >= T_microbe

if host and not microbe:
    decision = REMOVE
elif microbe and not host:
    decision = KEEP
else:
    decision = BOUNDARY
```

Profiles change `T_gapped`, `T_minimizer`, and `T_microbe`.
`privacy` favours host removal.
`microbiome` permits microbial witness rescue.
`mag` is more conservative and sends conflicting reads to boundary.

## Paired-end reconciliation

```text
features = merge(R1 evidence, R2 evidence)

privacy profile:
    any confident host mate removes the fragment

microbiome/MAG profile:
    any confident microbial mate can rescue the fragment
    conflicting mates become boundary
```

## Smoke invariant

For a host read whose gapped and minimizer hashes are present in both host
indexes, decision must be `REMOVE`.

For a microbial read whose canonical k-mers are present in the microbial witness
index but absent from both host indexes, decision must be `KEEP`.

For a read with neither evidence, decision must be `BOUNDARY`.
