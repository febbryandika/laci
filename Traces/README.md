# Traces

Two Instruments recordings from a real device, so the performance budgets in SPEC §10 can be
inspected rather than asserted:

| File | Interval | Budget (p95) | Device |
|---|---|---|---|
| `scan-to-cart.trace` | `scan-to-cart` | 150 ms | iPad 9th gen (shop A's hardware) |
| `print-duration.trace` | `checkout-to-printed` | 3 s | same iPad, 58 mm printer with a 20-byte MTU |

Both intervals are emitted by `Log.signposter` (subsystem `id.laci`, category Points of Interest):

- `scan-to-cart` wraps `SellViewModel.didRead`, so it covers the camera, the keyboard wedge and
  manual entry alike: lookup through to the line in the cart.
- `checkout-to-printed` begins at the top of `SellViewModel.commit`, the tap that pays, and ends in
  `PrinterCoordinator.record` once the transport's last chunk is acknowledged by the printer
  (`.withResponse` write). Its end message says `printed` or `failed`; a failed commit ends it at
  once with `commit failed`.

## Recording

A Release build on the device, the printer paired, the catalogue loaded.

```bash
xcrun xctrace list devices
xcrun xctrace record --template 'Time Profiler' --instrument 'os_signpost' \
  --device <udid> --attach Laci --time-limit 120s --output Traces/scan-to-cart.trace
```

During the recording, scan 50 different products from the shelf at a normal pace.

```bash
xcrun xctrace record --template 'Time Profiler' --instrument 'os_signpost' \
  --device <udid> --attach Laci --time-limit 300s --output Traces/print-duration.trace
```

During this one, ring up 20 sales of 3 to 8 lines each and pay cash exact (⌘⏎), waiting for each
struk to finish before the next.

## Reading the p95

Open the trace, select the **os_signpost** track, filter to subsystem `id.laci`, and switch the
detail view to **Summary: Intervals**. The p95 is not shown directly: export the interval list
(File › Export) and take the 95th percentile of the durations, or count down from the slowest — with
50 scans, p95 is the third-slowest; with 20 prints, the slowest but one.

Record the date, build, device, printer model and the two p95 figures in the PR that adds a trace,
and redo both after any change to the scan path, the receipt layout or the transport.
