# GTX 1650 / i5-9400F experiments

This is a reproducible, low-end-PC experiment, not a promise that the
title's first cutscene will render. It does not fix the missing ray-traced
lighting or the NVIDIA driver access violation on its own.

## Test machine and baseline

- Windows 11, Intel Core i5-9400F (6 cores), GTX 1650 4 GB, 16 GB RAM.
- Boot menus and pause menu display; audio and portions of opening credits
  display; much of the 3D scene remains black or incomplete.
- First world frames around 1-2 fps, with CPU near saturation and RAM nearly full.
- Earlier log: 468 host draws dropped because the pipelines were not ready,
  around 1,161 pipelines being made, and a later access violation
  (0xC0000005) inside NVIDIA's nvwgf2umx.dll.
- The precise cause of black graphics is not identified. The original
  fork also notes that ray-traced shadows and bounced light are missing.

## Build and run

Use your own lawfully obtained test title outside the repository.
Do not commit game files, caches, captures, extracted shaders or crash dumps.
Use PowerShell and a Windows build of Rust.

```powershell
git clone https://github.com/kacperklos96-byte/victory-fork.git D:\VIctoryGTX
cd D:\VIctoryGTX
Copy-Item victory.example.toml victory.toml
# Edit victory.toml: game_dir should point to your title's directory.
cargo test --workspace --locked -- --test-threads=1
cargo build --release --locked -p victory
.\scripts\gtx1650.ps1 -GameExe "D:\path\to\title.exe" -Profile v3 -OnDemandMips
```

The script uses `D:\VIctoryForkData\cache` and
`D:\VIctoryForkData\data` by default, matching the previous test's
cache and crash-log locations. Override with `-DataRoot` if needed.
To save frames *outside the repository*, add `-Capture`.

If PowerShell blocks running local scripts, you may instead run the
equivalent environment settings and executable manually. Do not disable
antivirus or Windows graphics-driver recovery to make a test run.

## Profiles

| Profile | Pipeline workers | Pipeline wait budget | Relay | Goal |
| --- | ---: | ---: | ---: | --- |
| v3 (default) | 2 | 500 ms/frame | stage 2 | Reduce synchronous copy-back; 2048 MiB target reservation |
| visuals | 2 | 1200 ms/frame | off | Reduce dropped first-use draws; can be substantially slower |
| balanced | 2 | 500 ms/frame | off | Compare against the fork's normal wait budget |
| fast-experimental | 2 | 250 ms/frame | stage 2 | Experimental throughput; may worsen missing graphics or crashes |

All profiles default to a 512 MiB card-copy cap (`-CardBufferMB` changes it),
versus upstream's 1024 MiB. Copies with before-twins may cost more than the cap.
V3 also uses the upstream 1 MiB minimum card-copy size and wide copy-back.
`-TargetReserveMB` controls V3's render-target reservation; it is not a hard
VRAM cap. `-OnDemandMips` enables experimental sparse mip allocation.
Try `-CopyQueue` or `-AsyncSubmit` separately only after a stable V3 baseline.
Neither is enabled by default; indirect draw windows and in-flight fetching
are kept off. If V3 is unstable, use `-Profile visuals` without those switches.
These choices are hypotheses for 4 GB hardware, not measured wins.
The new `VICTORY_PIPELINE_WORKERS` environment override permits
controlling how many CPU threads compile pipelines (1 through 8).
On this CPU the previous default was three workers.

**Do not interpret a higher FPS as better rendering.** The runtime
can skip unready pipelines, leaving important parts of a scene black.
Compare the number of `dropped ... without a host pipeline` draws,
`being made` counts, CPU/RAM/VRAM, whether the same cutscene frames
appear, and whether the title crashes. Use the same saved cache and
game scene for fair comparisons.

## V3 diagnostics and SSD migration

The console prints a pipeline progress bar after every 32 completed background
jobs and when the queue drains. The total is only the jobs discovered so far,
not total game loading; new jobs can increase it. Failed jobs count as completed
and are shown separately. Requested pipelines that finished without a usable
host pipeline emit one warning per pipeline with shader hashes. This is not a
lighting fix or an in-game overlay.

V2's visuals profile explicitly disabled the upstream asynchronous copy-back
relay. One observed frame reported 5777 ms copying back and 434 dropped draws
with zero pipelines pending. V3 restores relay stage 2 for a controlled test.
The timing may be reported differently with the relay active; compare actual
frame times and the same scene rather than only the copy-back counter.

For an SSD test, close the program, copy the existing data root to an external
SSD folder (e.g. `E:\VIctoryForkData`), keep the old copy as backup, and pass
`-DataRoot E:\VIctoryForkData` on launch. If moving the title itself, update
`game_dir` in `victory.toml` and pass its new executable path. Do not place title
files, caches or saves inside the repository. SSDs may improve I/O stalls and
paging but do not correct shader or lighting errors.

## Next real rendering fixes

1. Identify missing / refused graphics pipelines and whether they were
   ready in the cutscene, not simply lower graphics settings.
2. Verify whether black areas are caused by shadow / bounce-light
   reconstruction versus absent draw calls. The original fork lists
   unimplemented ray-traced lighting as a known issue.
3. Reproduce the NVIDIA access violation with minimal driver features
   and D3D12 diagnostics, then isolate which API call or bad input
   triggered it. Do not assume the driver alone is defective.
4. Compare memory budgets, native GPU memory usage and the CPU time
   spent copying or hashing shader-visible title buffers.
5. Keep changes measurable and retain upstream sync with fxceless.

Do not treat 24 GB of reported memory use on a high-end system as a
claim that a 16 GB system cannot boot: Windows commit and paging can
permit execution, but severe paging will hurt performance and stability.

## What a successful test looks like

- More consistently visible title cards / 3D cutscene frames *without*
  switching to a black scene.
- Fewer missing or pending host pipelines after the cache has warmed.
- No new NVIDIA driver crash or regression in menus / audio.
- Record a baseline and a matching optimized run before claiming any
  real speedup.

These tuning settings do not fix an access violation or missing lighting
on their own. Further GPU/shader changes will likely be required.
