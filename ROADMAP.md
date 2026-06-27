# Roadmap

Milestone summary for `NetworkPathMonitor`. The load-bearing design record lives at
[`Sources/NetworkPathMonitor/NetworkPathMonitor.docc/Design.md`](Sources/NetworkPathMonitor/NetworkPathMonitor.docc/Design.md)
(a DocC article that also renders on Swift Package Index). This file is a summary; the
design article is authoritative when the two disagree.

## Done in 1.0.0

- **Protocol-first observation.** `PathMonitoring` has one requirement, `paths()`;
  the two primitives policies actually want — `currentPath()` and `waitUntilSatisfied()` —
  are default implementations on top of it. Consumers depend on the protocol so they can
  inject a stub.
- **`NetworkPath` value mirror.** A `Sendable`, `Equatable` value type carrying the
  decision-relevant subset of `NWPath` (`status`, `isExpensive`, `isConstrained`,
  `availableInterfaces`), reusing Network's own `NWPath.Status` / `NWInterface.InterfaceType`.
  Exists because `NWPath` has no public initializer and so can't be constructed in tests.
  Raw `NWPath` stays reachable via `PathMonitor.nwPaths()`.
- **One `AsyncSequence` shape across iOS 15+.** `PathMonitor` is iterated like
  `NWPathMonitor` itself. iOS 17+ delegates to the native `AsyncSequence`; iOS 15–16
  hand-roll the same shape by bridging `pathUpdateHandler` into an `AsyncStream`. A fresh
  monitor is created per iteration and cancelled on termination (a cancelled monitor can't
  restart; one handler feeds one consumer).
- **`.bufferingNewest(1)`.** Connectivity is state, not a log — a slow consumer sees the
  current path, never a stale backlog.
- **Optional `requiredInterfaceType`.** Observe a single medium (e.g. `.wifi`) when needed;
  `nil` (default) answers plain "am I online?".
- **Separate `NetworkPathMonitorTestSupport` product.** `StubPathMonitor` scripts an
  offline → online sequence without a real network; production code never links it.
- **Swift 6 language mode, strict-concurrency clean.** No `@unchecked Sendable` anywhere.
- **Swift Testing suite + docs.** `@Suite`/`@Test`/`#expect` coverage; DocC catalog
  (landing page + design article); `.spi.yml` enabling SPI-hosted documentation; Apache-2.0.

## Planned

- **iOS 26 `NetworkConnection` family — adopt only if needed.** `NetworkConnection` /
  `NetworkListener` / `NetworkBrowser` ([WWDC 2025 session 250](https://developer.apple.com/videos/play/wwdc2025/250/))
  cover the *connection* layer. A `URLSession`-backed consumer (the motivating
  `RefreshTokenAuthMiddleware`) opens no raw connections, so path monitoring suffices today.
  Because consumers depend on `PathMonitoring`, adding connection support later is
  additive, not a rewrite. See Design §8.
- **Captive-portal / reachability helper — deliberately deferred.** `.satisfied` ≠
  reachable (Design §6). Proving an endpoint is up stays out of scope by design; a
  dedicated library (e.g. `rwbutler/Connectivity`) is the right tool if systematic
  captive-portal detection is required.

## Skill alignment notes

- **apple-network.** Implements the skill's prescribed Part 1 pattern almost verbatim —
  the `NetworkPath` `Sendable` mirror reusing Network's own enums, the
  `PathMonitoring` protocol vending the mirror, `.bufferingNewest(1)`, a fresh
  monitor per stream cancelled on termination, and `availableInterfaces.first?.type` (no
  `CaseIterable` retrofit). Every "Pitfalls in depth" item is handled (strong reference,
  not-restartable, `.satisfied` ≠ reachable, `requiredInterfaceType` inversion,
  single-consumer). Deliberate divergences: it adds the protocol/DI seam (which the skill
  endorses) and uses `NWPathMonitor`'s native `AsyncSequence` on iOS 17+ rather than the
  skill's bridge-everywhere minimalism — modern API when available, hand-rolled bridge as
  the iOS 15–16 fallback.
- **swift-package-manager.** Per-target `Sources/<target>` + `Tests/<target>` layout (a
  three-target package can't use the single-target flat `Sources/` form); a separate
  test-support product so the stub never ships in production; the DocC catalog inside the
  library target; `.spi.yml` (`documentation_targets`) to enable SPI-hosted docs.
- **swift-concurrency.** The iOS 15–16 `AsyncStream` bridge with `onTermination` teardown
  (no monitor leak, no retain cycle — the handler captures only the `Sendable`
  continuation); a `Sendable` value mirror as the stream element; a fresh monitor per
  iteration; Swift 6 language mode with zero `@unchecked Sendable`.
- **swift-testing-expert.** The suite uses `@Suite("…")` / `@Test("…")` with `#expect`,
  parameter-free tests, and a scripted stub to drive offline → online deterministically
  (a hang would time out rather than pass).
- **swiftui-foundation (architectural style).** Program-to-a-protocol dependency injection
  (depend on `PathMonitoring`, inject the concrete monitor or a stub) and a
  value-type model (`NetworkPath`) — the same testable-by-construction posture the course
  advocates, applied below the UI layer.
