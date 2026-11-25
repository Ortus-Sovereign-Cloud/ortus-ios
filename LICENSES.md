# Licences of what the Ortus iOS app ships

The app is MIT OR Apache-2.0. Apple's system frameworks (SwiftUI, Foundation, CryptoKit, Security, LocalAuthentication) are part of iOS and not shipped in it. It carries:

- **WebRTC** (BSD-3-Clause), Google's, for native calls: the reviewed binary that `WebRTC/Package.swift` names by checksum (the owner's exception of 22 November 2026).
- **The end-to-end library** libortus_e2e_ffi (MIT OR Apache-2.0), from ortus-chat `phones/e2e` at bb172b22371a73f31c1b184d6ea956c0dcc9b9bc, and the 182 Rust crates inside it, below. The MPL-2.0 ones are allowed for this library only, unmodified (the owner's decision of 25 November 2026); their source is at crates.io under the versions named.

`ci/check.sh` fails if another third-party package is added, until its licence is reviewed and listed here.

| Crate | Version | Licence |
| --- | --- | --- |
| aead | 0.6.1 | MIT OR Apache-2.0 |
| aes | 0.9.4 | MIT OR Apache-2.0 |
| aho-corasick | 1.1.5 | Unlicense OR MIT |
| anyhow | 1.0.105 | MIT OR Apache-2.0 |
| archery | 1.2.3 | MIT |
| arrayvec | 0.7.8 | MIT OR Apache-2.0 |
| assign | 1.1.1 | MIT |
| as_variant | 1.3.0 | MPL-2.0 |
| base16ct | 1.0.0 | Apache-2.0 OR MIT |
| base64 | 0.23.1 | MIT OR Apache-2.0 |
| base64ct | 1.8.3 | Apache-2.0 OR MIT |
| bitflags | 2.13.2 | MIT OR Apache-2.0 |
| blake3 | 1.8.7 | CC0-1.0 OR Apache-2.0 OR Apache-2.0 WITH LLVM-exception |
| block-buffer | 0.12.1 | MIT OR Apache-2.0 |
| block-padding | 0.4.2 | MIT OR Apache-2.0 |
| bs58 | 0.5.1 | MIT/Apache-2.0 |
| bytemuck | 1.25.2 | Zlib OR Apache-2.0 OR MIT |
| byteorder | 1.5.0 | Unlicense OR MIT |
| bytes | 1.12.2 | MIT |
| camino | 1.2.6 | MIT OR Apache-2.0 |
| cargo_metadata | 0.23.1 | MIT |
| cargo-platform | 0.3.3 | MIT OR Apache-2.0 |
| cbc | 0.2.1 | MIT OR Apache-2.0 |
| cfg-if | 1.0.5 | MIT OR Apache-2.0 |
| chacha20 | 0.10.2 | MIT OR Apache-2.0 |
| chacha20poly1305 | 0.11.0 | Apache-2.0 OR MIT |
| cipher | 0.5.2 | MIT OR Apache-2.0 |
| cmov | 0.5.4 | Apache-2.0 OR MIT |
| constant_time_eq | 0.4.2 | CC0-1.0 OR MIT-0 OR Apache-2.0 |
| const-oid | 0.10.3 | Apache-2.0 OR MIT |
| const_panic | 0.2.17 | Zlib |
| cpubits | 0.1.1 | MIT OR Apache-2.0 |
| cpufeatures | 0.3.1 | MIT OR Apache-2.0 |
| crypto-common | 0.2.2 | MIT OR Apache-2.0 |
| ctr | 0.10.1 | MIT OR Apache-2.0 |
| ctutils | 0.4.8 | Apache-2.0 OR MIT |
| curve25519-dalek | 5.0.0 | BSD-3-Clause |
| date_header | 1.0.5 | MIT/Apache-2.0 |
| deadpool | 0.13.1 | MIT OR Apache-2.0 |
| deadpool-runtime | 0.3.1 | MIT OR Apache-2.0 |
| deadpool-sync | 0.2.0 | MIT OR Apache-2.0 |
| decancer | 3.3.3 | MIT |
| deranged | 0.5.9 | MIT OR Apache-2.0 |
| digest | 0.11.3 | MIT OR Apache-2.0 |
| ed25519 | 3.0.0 | Apache-2.0 OR MIT |
| ed25519-dalek | 3.0.0 | BSD-3-Clause |
| either | 1.19.0 | MIT OR Apache-2.0 |
| equivalent | 1.0.3 | Apache-2.0 OR MIT |
| errno | 0.3.15 | MIT OR Apache-2.0 |
| eyeball | 0.8.8 | MPL-2.0 |
| eyeball-im | 0.9.1 | MPL-2.0 |
| fallible-iterator | 0.3.0 | MIT/Apache-2.0 |
| fallible-streaming-iterator | 0.1.9 | MIT/Apache-2.0 |
| fastrand | 2.5.0 | Apache-2.0 OR MIT |
| foldhash | 0.2.0 | Zlib |
| form_urlencoded | 1.2.3 | MIT OR Apache-2.0 |
| futures-core | 0.3.34 | MIT OR Apache-2.0 |
| futures-sink | 0.3.34 | MIT OR Apache-2.0 |
| futures-task | 0.3.34 | MIT OR Apache-2.0 |
| futures-util | 0.3.34 | MIT OR Apache-2.0 |
| getrandom | 0.4.3 | MIT OR Apache-2.0 |
| growable-bloom-filter | 2.1.1 | MIT |
| hashbrown | 0.17.2 | MIT OR Apache-2.0 |
| hashlink | 0.12.2 | MIT OR Apache-2.0 |
| heck | 0.5.0 | MIT OR Apache-2.0 |
| hkdf | 0.13.0 | MIT OR Apache-2.0 |
| hmac | 0.13.0 | MIT OR Apache-2.0 |
| hpke | 0.14.1 | MIT/Apache-2.0 |
| http | 1.5.0 | MIT OR Apache-2.0 |
| hybrid-array | 0.4.15 | MIT OR Apache-2.0 |
| icu_collections | 2.4.0 | Unicode-3.0 |
| icu_locale_core | 2.4.0 | Unicode-3.0 |
| icu_normalizer | 2.4.0 | Unicode-3.0 |
| icu_normalizer_data | 2.4.0 | Unicode-3.0 |
| icu_properties | 2.4.0 | Unicode-3.0 |
| icu_properties_data | 2.4.0 | Unicode-3.0 |
| icu_provider | 2.4.0 | Unicode-3.0 |
| idna | 1.1.0 | MIT OR Apache-2.0 |
| idna_adapter | 1.2.2 | Apache-2.0 OR MIT |
| imbl | 7.0.2 | MPL-2.0+ |
| imbl-sized-chunks | 0.2.0 | MPL-2.0+ |
| indexmap | 2.14.2 | Apache-2.0 OR MIT |
| inout | 0.2.6 | MIT OR Apache-2.0 |
| itertools | 0.15.0 | MIT OR Apache-2.0 |
| itoa | 1.0.19 | MIT OR Apache-2.0 |
| js_int | 0.2.2 | MIT |
| js_option | 0.2.0 | MIT |
| konst | 0.4.3 | Zlib |
| libc | 0.2.191 | MIT OR Apache-2.0 |
| libsqlite3-sys | 0.38.2 | MIT |
| litemap | 0.8.3 | Unicode-3.0 |
| maplit | 1.0.2 | MIT/Apache-2.0 |
| matrix-pickle | 0.2.3 | Apache-2.0 |
| matrix-sdk-base | 0.19.1 | Apache-2.0 |
| matrix-sdk-common | 0.19.1 | Apache-2.0 |
| matrix-sdk-crypto | 0.19.1 | Apache-2.0 |
| matrix-sdk-sqlite | 0.19.1 | Apache-2.0 |
| matrix-sdk-store-encryption | 0.19.1 | Apache-2.0 |
| memchr | 2.8.3 | Unlicense OR MIT |
| num-conv | 0.2.2 | MIT OR Apache-2.0 |
| num_cpus | 1.17.0 | MIT OR Apache-2.0 |
| num-traits | 0.2.19 | MIT OR Apache-2.0 |
| once_cell | 1.21.4 | MIT OR Apache-2.0 |
| ortus-e2e | 0.1.0 | MIT OR Apache-2.0 |
| ortus-e2e-ffi | 0.1.0 | MIT OR Apache-2.0 |
| pbkdf2 | 0.13.0 | MIT OR Apache-2.0 |
| percent-encoding | 2.3.2 | MIT OR Apache-2.0 |
| pin-project-lite | 0.2.18 | Apache-2.0 OR MIT |
| poly1305 | 0.9.1 | Apache-2.0 OR MIT |
| potential_utf | 0.1.6 | Unicode-3.0 |
| powerfmt | 0.2.1 | MIT OR Apache-2.0 |
| prost | 0.14.6 | Apache-2.0 |
| rand | 0.10.4 | MIT OR Apache-2.0 |
| rand_core | 0.10.1 | MIT OR Apache-2.0 |
| rand_core | 0.9.5 | MIT OR Apache-2.0 |
| rand_xoshiro | 0.7.0 | MIT OR Apache-2.0 |
| readlock | 0.1.11 | MPL-2.0 |
| readlock-tokio | 0.1.6 | MPL-2.0 |
| regex | 1.13.2 | MIT OR Apache-2.0 |
| regex-automata | 0.4.19 | MIT OR Apache-2.0 |
| regex-syntax | 0.8.12 | MIT OR Apache-2.0 |
| rmp | 0.8.15 | MIT |
| rmp-serde | 1.3.1 | MIT |
| ruma | 0.17.2 | MIT |
| ruma-client-api | 0.25.2 | MIT |
| ruma-common | 0.20.2 | MIT |
| ruma-events | 0.35.2 | MIT |
| ruma-identifiers-validation | 0.14.1 | MIT |
| rusqlite | 0.40.2 | MIT |
| rustix | 1.1.6 | Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT |
| safe_arch | 0.7.4 | Zlib OR Apache-2.0 OR MIT |
| semver | 1.0.28 | MIT OR Apache-2.0 |
| serde | 1.0.229 | MIT OR Apache-2.0 |
| serde_bytes | 0.11.19 | MIT OR Apache-2.0 |
| serde_core | 1.0.229 | MIT OR Apache-2.0 |
| serdect | 0.4.3 | Apache-2.0 OR MIT |
| serde_html_form | 0.4.1 | MIT |
| serde_json | 1.0.154 | MIT OR Apache-2.0 |
| serde_path_to_error | 0.1.20 | MIT OR Apache-2.0 |
| sha2 | 0.11.1 | MIT OR Apache-2.0 |
| signature | 3.0.0 | Apache-2.0 OR MIT |
| slab | 0.4.12 | MIT |
| smallvec | 1.16.6 | MIT OR Apache-2.0 |
| stable_deref_trait | 1.2.1 | MIT OR Apache-2.0 |
| static_assertions | 1.1.0 | MIT OR Apache-2.0 |
| subtle | 2.6.1 | BSD-3-Clause |
| tempfile | 3.27.0 | MIT OR Apache-2.0 |
| thiserror | 2.0.21 | MIT OR Apache-2.0 |
| time | 0.3.55 | MIT OR Apache-2.0 |
| time-core | 0.1.9 | MIT OR Apache-2.0 |
| tinystr | 0.8.5 | Unicode-3.0 |
| tinyvec | 1.13.3 | Zlib OR Apache-2.0 OR MIT |
| tokio | 1.54.1 | MIT |
| tokio-stream | 0.1.19 | MIT |
| tokio-util | 0.7.20 | MIT |
| tracing | 0.1.44 | MIT |
| tracing-core | 0.1.36 | MIT |
| typenum | 1.20.1 | MIT OR Apache-2.0 |
| typewit | 1.15.2 | Zlib |
| ulid | 3.0.0 | MIT |
| unicode-normalization | 0.1.26 | (MIT OR Apache-2.0) AND Unicode-3.0 |
| uniffi | 0.32.2 | MPL-2.0 |
| uniffi_core | 0.32.2 | MPL-2.0 |
| uniffi_pipeline | 0.32.2 | MPL-2.0 |
| universal-hash | 0.6.1 | MIT OR Apache-2.0 |
| url | 2.5.9 | MIT OR Apache-2.0 |
| utf8_iter | 1.1.0 | Apache-2.0 OR MIT |
| utf_types | 1.0.0 | Apache-2.0 OR MIT |
| uuid | 1.29.3 | Apache-2.0 OR MIT |
| vodozemac | 0.11.2 | Apache-2.0 |
| web-time | 1.1.0 | MIT OR Apache-2.0 |
| wide | 0.7.33 | Zlib OR Apache-2.0 OR MIT |
| wildmatch | 2.7.0 | MIT |
| writeable | 0.6.4 | Unicode-3.0 |
| x25519-dalek | 3.0.0 | BSD-3-Clause |
| xxhash-rust | 0.8.21 | BSL-1.0 |
| yoke | 0.8.4 | Unicode-3.0 |
| zerofrom | 0.1.8 | Unicode-3.0 |
| zeroize | 1.9.2 | Apache-2.0 OR MIT |
| zerotrie | 0.2.5 | Unicode-3.0 |
| zerovec | 0.11.9 | Unicode-3.0 |
| zmij | 1.0.23 | MIT |
