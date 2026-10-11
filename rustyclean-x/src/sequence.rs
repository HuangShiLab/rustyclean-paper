//! Correct 2-bit sequence encoding and canonical k-mer helpers.

/// Encode one IUPAC-free base. Any other byte, including N, is invalid.
#[inline]
pub fn encode_base(base: u8) -> Option<u64> {
    match base.to_ascii_uppercase() {
        b'A' => Some(0),
        b'C' => Some(1),
        b'G' => Some(2),
        b'T' => Some(3),
        _ => None,
    }
}

/// Encode bases left-to-right. The first base occupies the most-significant
/// two-bit code. A k-mer therefore has a deterministic numeric representation.
pub fn encode_bases(bases: &[u8]) -> Option<u64> {
    if bases.is_empty() || bases.len() > 32 {
        return None;
    }
    let mut encoded = 0_u64;
    for base in bases {
        encoded = (encoded << 2) | encode_base(*base)?;
    }
    Some(encoded)
}

/// Reverse-complement a numeric k-mer. Input and output use the same
/// left-to-right encoding returned by [`encode_bases`].
pub fn reverse_complement_kmer(kmer: u64, k: usize) -> u64 {
    let mut output = 0_u64;
    for i in 0..k {
        let shift = 2 * (k - 1 - i);
        let base = (kmer >> shift) & 3;
        output |= (3 - base) << (2 * i);
    }
    output
}

/// Return the smaller numeric representation of a k-mer and its reverse
/// complement. This is the conventional canonical k-mer ordering.
pub fn canonical_kmer(kmer: u64, k: usize) -> u64 {
    kmer.min(reverse_complement_kmer(kmer, k))
}

/// Stable hash used by draft indexes. Production indexes may keep this hash
/// but must store the algorithm and seed in index metadata.
pub fn wyhash(value: u64) -> u64 {
    value.wrapping_mul(0x9E37_79B9_7F4A_7C15)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_bases_uses_left_to_right_two_bit_codes() {
        assert_eq!(encode_bases(b"A"), Some(0));
        assert_eq!(encode_bases(b"C"), Some(1));
        assert_eq!(encode_bases(b"G"), Some(2));
        assert_eq!(encode_bases(b"T"), Some(3));
        assert_eq!(encode_bases(b"AC"), Some(1));
        assert_eq!(encode_bases(b"ACG"), Some((1 << 2) | 2));
        assert_eq!(encode_bases(b"ACGN"), None);
    }

    #[test]
    fn reverse_complement_is_exact() {
        assert_eq!(
            reverse_complement_kmer(encode_bases(b"ACG").unwrap(), 3),
            encode_bases(b"CGT").unwrap()
        );
        assert_eq!(
            reverse_complement_kmer(encode_bases(b"AACG").unwrap(), 4),
            encode_bases(b"CGTT").unwrap()
        );
    }

    #[test]
    fn canonical_kmer_is_orientation_independent() {
        let kmer = encode_bases(b"AACG").unwrap();
        let rc = reverse_complement_kmer(kmer, 4);
        assert_eq!(canonical_kmer(kmer, 4), canonical_kmer(rc, 4));
    }
}
