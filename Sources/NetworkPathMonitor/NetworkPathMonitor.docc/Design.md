# The `NetworkPath` mirror, the iOS 15–16 `AsyncSequence` bridge, and the injection seam

@Metadata {
    @PageColor(blue)
}

Load-bearing design record for `NetworkPathMonitor`: why the package vends a `Sendable`
value mirror instead of `NWPath`, how it presents one `AsyncSequence` shape across the
whole iOS 15+ range, why it buffers the newest value only, and how the protocol seam
keeps a consumer — e.g. a refresh-token auth middleware — testable.

## Overview

> Note: This is the as-designed record. ``PathMonitor``, ``PathMonitoring``,
> and ``NetworkPath`` conform to it; deviations require a doc update. The repository's
> [`ROADMAP.md`](https://github.com/laconicman/NetworkPathMonitor/blob/main/ROADMAP.md)
> carries the milestone summary; this article is authoritative when the two disagree.

`NetworkPathMonitor` is deliberately small. It observes **paths** — the connectivity
*state* of the device — and nothing else. Every choice below falls out of two
constraints: the stream element must be constructible in tests (so a consumer can be
driven through offline → online without a real network), and the iteration surface must
match modern `Network` across a four-OS-generation deployment range.

### Reading guide

§1 fixes what the package owns and refuses to own. §2 is the load-bearing decision — the
``NetworkPath`` value mirror and why it must exist. §3 covers the single `AsyncSequence`
shape and the iOS 15–16 bridge that backs it. §4 explains the buffering policy. §5 covers
the injection seam and the test-support split. §6 is the one correctness caveat every
caller must internalize (`.satisfied` ≠ reachable). §7 shows the intended integration
with a refresh-token auth middleware. §8 is the roadmap.

## 1. Architectural posture

`NetworkPathMonitor` owns **path observation as state**: a stream of ``NetworkPath`` values
beginning with the current one and updated on change. It deliberately does **not** own:

- **Raw connections.** Sockets, TLS, framing — the `Network` *connection* layer (and
  iOS 26's structured-concurrency `NetworkConnection` family, §8) — are out of scope.
  Most clients (e.g. a `URLSession`-backed OpenAPI transport) open no raw connections and
  need only path state.
- **Reachability proof.** A `.satisfied` path is not proof the internet is reachable
  (§6). The package reports the OS's path verdict; proving an endpoint is up is the
  caller's job — make the request, handle failure.
- **Retry / backoff policy.** This package answers "what is the network doing right now /
  wake me when it's back." The attempt-count and backoff loop belong to a retry runner
  such as [swift-concurrency-retry](https://github.com/laconicman/swift-concurrency-retry).

This is the same separation client-side OAuth2 draws between the *grant* and *session*
layers: a small, orthogonal primitive that other layers **consult**, not a god-object
that owns their decisions.

## 2. The `NetworkPath` value mirror

**Decision: vend a `Sendable` value mirror, not `NWPath`.**

`NWPath` has **no public initializer**. A protocol that vends `NWPath` therefore cannot
be stubbed — there is no way to construct a canned offline-then-online sequence in a unit
test. That single fact is why ``NetworkPath`` exists.

The mirror carries the decision-relevant subset — `status`, `isExpensive`,
`isConstrained`, `availableInterfaces` — and **reuses Network's own enums**
(`NWPath.Status`, `NWInterface.InterfaceType`) rather than redeclaring them, so the
vocabulary stays identical to the framework while the type stays constructible. The
module re-exports `Network` (`@_exported import Network`), so a caller that
`import NetworkPathMonitor` gets `NWPath.Status` and friends directly.

When you need a field the mirror omits (`gateways`, `supportsDNS`, `unsatisfiedReason`,
`isUltraConstrained`, …), the escape hatch is the raw stream ``PathMonitor/nwPaths()`` — the mirror is a
convenience for the common case, not a wall.

> Tip: ``NetworkPath/satisfied(isExpensive:isConstrained:interfaces:)`` and
> ``NetworkPath/unsatisfied`` are convenience constructors for previews and tests.

## 3. One `AsyncSequence` shape, two backends

**Decision: the monitor *is* an `AsyncSequence`, iterated like `NWPathMonitor` itself —**
`for await path in PathMonitor()`. That mirrors modern `Network`, but
`NWPathMonitor`'s native `AsyncSequence` conformance is **iOS 17+ only**. So the package
presents one shape over two backends:

- **iOS 17 / macOS 14 / tvOS 17 / watchOS 10 / visionOS 1+** — delegates to
  `NWPathMonitor`'s native `AsyncSequence`.
- **iOS 15–16** — that conformance does not exist, so the package hand-rolls the same
  shape by bridging `pathUpdateHandler` into an `AsyncStream`.

A fresh `NWPathMonitor` is created **per iteration** and cancelled on stream termination.
This sidesteps two framework footguns: a cancelled monitor cannot be restarted, and a
single monitor's handler feeds only one consumer. The `AsyncStream` `onTermination` hook
owns teardown (cancel the backing `Task` on iOS 17+, `cancel()` the monitor on 15–16), so
there is no monitor leak and no retain cycle — the handler closure captures only the
`Sendable` continuation.

## 4. Buffering: `.bufferingNewest(1)`

**Decision: keep only the newest value.** Connectivity is *state*, not a log. A slow
consumer should observe the current path, never replay a stale backlog of transitions it
missed. `AsyncStream(bufferingPolicy: .bufferingNewest(1))` encodes exactly that.

## 5. The injection seam and the test-support split

Consumers depend on ``PathMonitoring`` — not the concrete ``PathMonitor`` —
so they can inject a stub. The protocol is intentionally one requirement,
``PathMonitoring/paths()``; the two primitives most policies want are default
implementations on top of it:

- ``PathMonitoring/currentPath()`` — the most recent path (awaits the first if
  none has arrived).
- ``PathMonitoring/waitUntilSatisfied()`` — suspend until a usable path exists.
  This is the primitive a connectivity-reactive policy uses — drive UX or pace retries (§7).

The stub ships in a **separate product**, `NetworkPathMonitorTestSupport`
(`StubPathMonitor`), so production code never links it while a consumer's test
target can. A stub is constructed from a scripted `[NetworkPath]` and emits it in order,
which is only possible because the element is the constructible mirror from §2.

## 6. `.satisfied` is not "reachable"

Every caller must internalize this: a `.satisfied` path means *a usable path exists*, not
that the internet — or your endpoint — is reachable. A **captive portal** (hotel Wi-Fi)
satisfies a path while intercepting all traffic. For true reachability, make a real
request and handle failure; for systematic captive-portal detection, a dedicated library
(e.g. `rwbutler/Connectivity`) is the right tool. `NetworkPathMonitor` reports the OS path
verdict and stays out of the reachability-proof business by design (§1).

## 7. Integration with a refresh-token auth middleware

The motivating consumer is
[RefreshTokenAuthMiddleware](https://github.com/laconicman/RefreshTokenAuthMiddleware).
Its transport is `URLSession`-backed, so it opens no raw connections — **path monitoring
is the piece it needs**, not the connection layer.

> Important: Don't gate the request on a connectivity pre-check. Reading "am I online?"
> and *then* firing the call is a race (connectivity can change in the gap) and duplicates
> what the OS already does better. Make the **request** wait by configuring the transport's
> `URLSession` (`waitsForConnectivity` and the `allows*NetworkAccess` family); use
> `NetworkPathMonitor` to **react to** connectivity — which is what path monitoring is for.
> (Apple, [WWDC 2018 session 715](https://developer.apple.com/videos/play/wwdc2018/715/).)

```swift
// The request waits without a race — no pre-check.
let config = URLSessionConfiguration.default
config.waitsForConnectivity = true
config.allowsConstrainedNetworkAccess = false   // e.g. don't refresh over Low Data Mode
// Build the OpenAPI transport's URLSession from `config`.
```

Where `NetworkPathMonitor` earns its place — the middleware (as of 2.0.0) has **no**
connectivity hook — is *reaction*:

- **Surface the right error.** The `credentialsProvider` closure
  (`@Sendable () async throws -> Credentials?`) is consulted under
  `onRefreshFailure: .requestCredentials` and `onPersistentlyRejected: .signInOnSecond401`.
  Throwing a *network* error from it when the path is unsatisfied makes the failure surface
  as `AuthError.credentialsUnavailable(reason:)` instead of a misattributed auth error:

```swift
let credentialsProvider: CredentialsProvider<Credentials> = {
    guard await monitor.currentPath()?.isSatisfied == true else {
        throw URLError(.notConnectedToInternet)     // → AuthError.credentialsUnavailable
    }
    return storedCredentials
}
```

- **Drive UX and pace retries.** Observe ``PathMonitoring/paths()`` to show a
  "waiting for network" state, or hold a retry runner such as
  [swift-concurrency-retry](https://github.com/laconicman/swift-concurrency-retry) until
  ``PathMonitoring/waitUntilSatisfied()`` returns before the next attempt.

Because the consumer depends on ``PathMonitoring``, both are testable end to end:
inject `StubPathMonitor([.unsatisfied, .satisfied()])` and assert the consumer
reports offline, then proceeds.

## 8. Roadmap: iOS 26 structured-concurrency Network APIs

This package observes **paths**. For the **connection** layer, iOS/macOS 26 introduce
`NetworkConnection`, `NetworkListener`, and `NetworkBrowser`
([WWDC 2025 session 250](https://developer.apple.com/videos/play/wwdc2025/250/)) — async
`send`/`receive`, a built-in TLV framer, and a `Coder` for `Codable`, "built from the
ground up for Swift's structured concurrency."

Relevance: a `URLSession`-backed consumer opens no raw connections today, so path
monitoring (this package) is the piece needed now, and `NWPathMonitor`'s native
`AsyncSequence` already covers iOS 17+. Adopt the `NetworkConnection` family only if a
consumer later moves to a raw-connection transport — and because consumers depend on
``PathMonitoring``, that would be an additive change, not a rewrite.

The ``NetworkPath`` mirror survives that recraft regardless: even
[`NetworkConnection.currentPath`](https://developer.apple.com/documentation/network/networkconnection/currentpath)
returns `NWPath?` — still with no public initializer — so the value mirror remains the
testability seam, and the ``PathMonitoring`` protocol insulates consumers from any
future path-representation churn.
