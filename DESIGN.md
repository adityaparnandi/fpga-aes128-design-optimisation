# Design Notes

## Scope

This repository contains the architecture-exploration work for four AES-128 transformation blocks:

- SubBytes
- InvSubBytes
- MixColumns
- InvMixColumns

The objective was to compare alternative hardware mappings, pipeline them for FPGA implementation, and evaluate their routed timing.

The work formed part of a larger group AES-128 encryption/decryption project. The complete design also contained ShiftRows/InvShiftRows, AddRoundKey, key expansion, round-level control and top-level integration. This repository focuses on the transformation-block architecture and timing-optimisation work described here.

## SubBytes and InvSubBytes

AES byte substitution requires multiplicative inversion in GF(2^8) together with the AES affine transformation. Two implementation approaches were retained.

### Distributed LUT

The S-box or inverse S-box is stored directly as a 256-entry lookup table implemented in FPGA logic.

This provides a simple reference implementation and avoids the arithmetic required to calculate the substitution directly.

### Composite-field arithmetic

The composite-field implementation performs the GF(2^8) inversion through an isomorphic representation in a tower field, GF((2^4)^2), before mapping the result back to the AES basis.

Timing optimisation focused on:

- splitting the arithmetic across pipeline stages;
- pipelining critical GF(16) multiplication logic;
- balancing combinational depth;
- reducing fanout by registering or duplicating heavily used intermediate values.

The retained forward composite-field version reaches 400.0 MHz inferred Fmax, compared with 393.1 MHz for the distributed-LUT version. For InvSubBytes the retained implementations are effectively equal, at 392.2 MHz and 393.1 MHz respectively.

## MixColumns

MixColumns applies a fixed matrix multiplication over GF(2^8) to each 32-bit AES state column.

Two arithmetic mappings were compared.

### `xtime`

`xtime` implements multiplication by 02 using a left shift and conditional reduction by the AES irreducible polynomial.

For forward MixColumns:

```text
02*x = xtime(x)
03*x = xtime(x) XOR x
```

Only 01, 02 and 03 are required, so the native-field implementation is compact and maps efficiently to FPGA logic.

For inverse MixColumns, the constants are 09, 0B, 0D and 0E. The retained implementation builds x2, x4 and x8 through repeated `xtime` operations and forms the required constants with XORs.

The inverse implementation is pipelined between the main arithmetic stages so that the repeated `xtime` operations do not form one long combinational chain. The retained design separates x2, x4, x8 generation, constant formation and matrix recombination with registers.

### Composite-field arithmetic

The alternative implementation maps bytes into GF((2^4)^2), performs the required constant multiplications in the tower field, then maps the results back before the final matrix XOR.

This introduces basis-conversion and alignment logic but provides a different hardware structure from repeated native-field `xtime` operations.

## Timing methodology

The individual transformation blocks were compared under the same **10.000 ns clock constraint**.

After placement and routing:

```text
effective period = 10.000 ns - WNS
Fmax = 1000 / effective period
```

Using a fixed implementation constraint provides a consistent basis for comparing the routed critical paths of the alternative architectures.

This is different from progressively tightening the clock constraint to determine the operating limit of a complete design. The results in this repository use the fixed-constraint method for the individual blocks.

## Result interpretation

### Forward MixColumns

The `xtime` implementation has the clearest timing advantage:

- `xtime`: 552.8 MHz
- composite field: 432.7 MHz

This is consistent with the low cost of the 02 and 03 multiplications required by forward MixColumns.

### Inverse MixColumns

The retained implementations are closer:

- `xtime`: 443.9 MHz
- composite field: 474.2 MHz

Inverse MixColumns requires more arithmetic than the forward transformation. Although the repeated `xtime` operations are pipelined, the design still requires additional intermediate values, constant formation, alignment and XOR recombination.

The routed critical paths of the two retained inverse implementations are close enough that pipeline partitioning, placement and routing materially affect the result. The retained composite-field implementation is slightly faster; this should not be interpreted as a general rule that composite-field arithmetic is inherently faster for inverse MixColumns.

## Verification

Where standalone testbenches were preserved, they are included with the corresponding RTL.

Composite-field SubBytes and InvSubBytes were exhaustively checked over all 256 possible input-byte values during development.

The retained `inv_mixcolumns_xtime` implementation was independently checked against a behavioural GF(2^8) reference calculation with changing inputs on consecutive clock cycles. The standalone test completed with:

```text
PASS: 107 InvMixColumns checks passed.
```

At project level, these transformation blocks were used within the complete AES-128 encryption/decryption design. The wider group verification flow compared the RTL against a validated software reference model using known-answer and random tests. That system-level verification provides the wider project context, while this repository concentrates on the retained transformation-block implementations.

## Full AES context

Within the complete design, these blocks formed part of the normal AES round datapaths.

Encryption:

```text
SubBytes -> ShiftRows -> MixColumns -> AddRoundKey
```

Decryption:

```text
InvShiftRows -> InvSubBytes -> AddRoundKey -> InvMixColumns
```

The final AES project combined these transformation blocks with the other round operations, key generation, pipeline control and top-level interfaces. This repository is intentionally limited to the architecture comparison and timing-optimisation work described above.
