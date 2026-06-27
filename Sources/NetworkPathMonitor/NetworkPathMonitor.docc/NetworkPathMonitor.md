# ``NetworkPathMonitor``

A tiny, dependency-free network-path observer for Apple platforms, built on
`Network` (`NWPathMonitor`) with Swift Concurrency.

## Overview

`NetworkPathMonitor` answers one question well — *what is the network doing right now, and
wake me when it changes* — and exposes it the way modern `Network` does: as an
`AsyncSequence` you iterate exactly like `NWPathMonitor` itself, across the whole iOS 15+
range.

Consumers depend on the ``PathMonitoring`` protocol rather than the concrete
``PathMonitor``, so the live monitor can be swapped for a scriptable stub in
tests. The stream element is ``NetworkPath`` — a `Sendable` value mirror of the
decision-relevant subset of `NWPath` — because `NWPath` has no public initializer and so
cannot be constructed in a test. The mirror reuses Network's own `NWPath.Status` and
`NWInterface.InterfaceType`, so the vocabulary stays identical to the framework; the raw
`NWPath` stream is still reachable via ``PathMonitor/nwPaths()`` when you need
fields the mirror omits (`gateways`, `supportsDNS`, `unsatisfiedReason`, `isUltraConstrained`, …).

The default convenience primitives — ``PathMonitoring/currentPath()`` and
``PathMonitoring/waitUntilSatisfied()`` — are the two a connectivity-aware policy
usually wants: read the current state, or suspend until the network returns.

For the load-bearing design rationale — the mirror-versus-`NWPath` decision, the
iOS 15–16 `AsyncSequence` bridge, the buffering policy, the injection seam, and how this
wires into a refresh-token auth middleware — see <doc:Design>.

## Topics

### Essentials

- ``PathMonitoring``
- ``PathMonitor``
- ``NetworkPath``

### Design notes

- <doc:Design>
