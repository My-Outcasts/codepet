import Foundation

/// How fast a run's execute log reveals itself — normally 1×, slower on request.
///
/// A fan-out finishes in about three seconds, which is correct for using the app and useless
/// for inspecting it: reviewing the agents-at-work row meant screen-recording the app and
/// stepping through frames, which is how most of Aug 5's UI review actually happened. This
/// exists so the live states can be looked at in real time instead.
///
/// DEBUG-only and off by default, so a shipped build cannot be slowed. Launch with:
///   open <app> --args -CODEPET_SLOW_RUNS 4
/// Any value from 2 to 20 is honoured; anything else means 1×. `CompanyStore.execStepNanos`
/// stays a `var` because tests set it to 0 for instant runs — this only scales the default.
///
/// It slows the CLIENT-SIDE REVEAL, nothing else. The Cloud Function call underneath takes
/// exactly as long as it takes, so this changes how long the log is watchable, not how long the
/// work takes — and it never makes a run look faster than it was.
enum RunPacing {
    static let multiplier: UInt64 = {
        #if DEBUG
        let raw = UserDefaults.standard.integer(forKey: "CODEPET_SLOW_RUNS")
        return (2...20).contains(raw) ? UInt64(raw) : 1
        #else
        return 1
        #endif
    }()
}
