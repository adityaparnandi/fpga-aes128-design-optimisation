# FPGA AES-128 Design Optimisation

Verilog implementations comparing alternative FPGA architectures for four AES-128 transformations:

- SubBytes
- InvSubBytes
- MixColumns
- InvMixColumns

The work was developed as part of a group high-throughput AES-128 FPGA project. This repository focuses on my contribution: implementing, pipelining and comparing alternative architectures for these transformation blocks. These modules were integrated into the wider AES encryption/decryption design alongside the other round and key-scheduling logic.

## Architecture variants

| Transformation | Architectures compared |
|---|---|
| SubBytes | Composite-field arithmetic vs distributed LUT |
| InvSubBytes | Composite-field arithmetic vs distributed LUT |
| MixColumns | `xtime` arithmetic vs composite-field arithmetic |
| InvMixColumns | `xtime` arithmetic vs composite-field arithmetic |

## Post-route timing results

All variants were compared using post-implementation Vivado timing on the same Artix-7 target with a common **10.000 ns clock constraint**.

For the module-level comparison:

```text
effective critical-path period = 10.000 ns - WNS
Fmax = 1000 / effective period
```

| Transformation | Architecture | WNS (ns) | Effective period (ns) | Inferred Fmax (MHz) |
|---|---|---:|---:|---:|
| SubBytes | Composite field | 7.500 | 2.500 | **400.0** |
| SubBytes | Distributed LUT | 7.456 | 2.544 | **393.1** |
| InvSubBytes | Composite field | 7.450 | 2.550 | **392.2** |
| InvSubBytes | Distributed LUT | 7.456 | 2.544 | **393.1** |
| MixColumns | `xtime` | 8.191 | 1.809 | **552.8** |
| MixColumns | Composite field | 7.689 | 2.311 | **432.7** |
| InvMixColumns | `xtime` | 7.747 | 2.253 | **443.9** |
| InvMixColumns | Composite field | 7.891 | 2.109 | **474.2** |

These values are used as a consistent comparison of the retained implementations in this repository. They are inferred from routed timing rather than from separately increasing the clock frequency for each block.

## Verification

Standalone testbenches are included where they were preserved.

- Composite-field SubBytes and InvSubBytes were checked across all 256 possible byte inputs during development.
- The retained `inv_mixcolumns_xtime` implementation was checked with a standalone reference-model testbench; 107 checks passed.
- The transformation blocks were also used within the wider AES-128 design, which was verified at system level against a software reference model.

System-level verification was carried out in the wider AES project; this repository keeps the focus on the transformation-block implementations and their timing comparison.

## Repository contents

Each transformation is grouped with its alternative implementations. Individual folders contain the retained RTL, timing wrapper (`top.v`), and any preserved standalone testbench or constraint file.

Vivado project files and generated outputs such as `.xpr`, `.runs`, `.cache`, `.sim`, `.dcp` and implementation databases are intentionally omitted.

## Reproducing the timing comparison

1. Create a Vivado project targeting the same Artix-7 device.
2. Add the selected implementation RTL and its `top.v`.
3. Apply a 10.000 ns clock constraint to the wrapper clock.
4. Run synthesis and implementation.
5. Read WNS from the post-implementation timing summary.
6. Calculate the effective period and inferred Fmax using the equations above.

See [DESIGN.md](DESIGN.md) for the architecture choices, pipeline strategy and scope of the wider AES project.
