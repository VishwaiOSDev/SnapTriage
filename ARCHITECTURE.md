# SnapTriage — Architecture

A SwiftUI app built with a **feature-first, lightweight unidirectional architecture**.
Target: **iOS 18+** (so we standardize on `@Observable` and the new Vision Swift API).

---

## 1. Principles

- Unidirectional data flow. The view renders state; the view sends intent; the ViewModel is the only mutation entry point.
- Value-type domain state. Business rules live in UseCases, IO lives in Services.
- Protocol-based dependencies **only at boundaries that need faking** (IO). Pure functions are injected as values, not protocols.
- Navigation is **state**, not imperative side effects.
- Two kinds of state are explicitly separated: **domain state** and **UI/transient state** (see §4).

---

## 2. Project structure

Each feature is organized as:

```
Features/<Feature>/
  Model/          // pure value types (struct/enum)
  View/           // SwiftUI views
  ViewModel/      // @MainActor @Observable, owns state, exposes send(_:)
  UseCase/        // business rules; depend on Service protocols
  Service/        // IO (persistence/network/system) + pure transforms
  Router/         // navigation routes + Router protocol for this feature
  Composition/    // factory that builds the feature's object graph
```

Shared code:

```
Common/
  Constants/      // storage keys, feature flags, numeric constants
  DesignSystem/   // colors, typography, spacing, animation, strings, modifiers
  Utilities/      // extensions, helpers, pure cross-cutting tools
```

---

## 3. Layer responsibilities

### Models
- Pure value types. Prefer `struct` / `enum`.
- `Identifiable` for list entities, `Equatable` for change detection.
- No UI framework imports unless strictly necessary.

### Views
- Own the screen ViewModel via `@State` (for `@Observable`, see §5).
- Render from `viewModel.state`.
- Send user intent via `viewModel.send(_:)`.
- **No business rules, no IO.** Layout and interaction only.
- Child views communicate upward through **semantic callbacks** (`onCreate`, `onDelete`, `onSelect`, `onMove`, `onSubmit`, `onRetry`).

### ViewModels
- `@MainActor`, `@Observable`, `final class`.
- Initialized with **protocol-based dependencies** (UseCases, Router).
- Own `private(set) var state: State`.
- Single mutation entry point: `func send(_ input: Input)`.
- Nested `State` and `Input` types.
- May assign **UI/transient state** directly (§4). **Domain state** is only assigned from UseCase results.
- Owns and cancels async work (§6).

### UseCases
- Contain business rules and workflow decisions.
- Depend on **Service protocols**, not concretes.
- Return updated models / async results. Do **not** mutate shared state.
- Normalize invariants (required collections non-empty, selection stays valid, etc.).
- Map typed domain errors → presentable errors (§7).

### Services
Two distinct kinds:
- **Pure transformation services** — deterministic, no IO. Injected as values/closures; protocol only if a seam is genuinely needed.
- **IO services** (persistence / network / system) — always behind a protocol for testability. Emit **typed domain errors**, never user-facing strings.

### Router
- A `Router` protocol per feature, injected into the ViewModel.
- **Navigation is modeled as state**: the Router mutates a `NavigationPath`/route stack that the View renders via `NavigationStack(path:)`. No imperative UIKit-style `push/present`.
- Can start empty and grow.

---

## 4. Domain state vs UI state  *(fixes: "assign only from UseCase" contradictions)*

State is split into two categories, and the rules differ:

| Category | Examples | Who may assign it |
|---|---|---|
| **Domain state** | entities, lists, selection, derived domain values | **Only** results returned from UseCases |
| **UI / transient state** | field text, focus, expanded rows, transient errors, in-flight phase | The ViewModel directly |

This removes the contradiction where clearing an error or editing a text field had to "go through a UseCase." Keystrokes and ephemeral UI never hit the business pipeline.

```swift
struct State {
    // domain
    var items: [Item] = []
    var selectedID: Item.ID?
    // ui/transient
    var phase: Phase = .idle           // see §6
    var draftTitle: String = ""        // ephemeral edit buffer
    var errorMessage: String?          // presentable, cleared by VM
}
```

---

## 5. Observation model  *(fixes: "@Observable or ObservableObject" ambiguity)*

Standardize on **`@Observable`** everywhere (iOS 17+).

- View owns the VM with `@State`:
  ```swift
  @State private var viewModel: TriageViewModel
  ```
- For two-way bindings, use `@Bindable`:
  ```swift
  @Bindable var vm = viewModel
  TextField("Title", text: $vm.state.draftTitle)   // ❌ state is private(set)
  ```
  Because `state` is `private(set)`, bindings are created through a helper that routes the setter to `send` (§8). No mixing of `ObservableObject` anywhere.

---

## 6. Async, cancellation & loading  *(fixes: undefined `send` semantics)*

`send` is **synchronous and non-throwing**; async work is launched into a tracked `Task`. This gives us cancellation and reentrancy control.

```swift
enum Phase: Equatable { case idle, loading, loaded, failed }

@MainActor @Observable final class TriageViewModel {
    private(set) var state = State()
    private var tasks: [InputKind: Task<Void, Never>] = [:]

    func send(_ input: Input) {
        switch input {
        case .load:
            run(.load) { [weak self] in
                guard let self else { return }
                self.state.phase = .loading            // intermediate UI state
                do {
                    let items = try await loadItems.execute()   // UseCase
                    self.state.items = items                    // domain state
                    self.state.phase = .loaded
                } catch is CancellationError {
                    // ignore
                } catch {
                    self.state.errorMessage = present(error)
                    self.state.phase = .failed
                }
            }
        case .clearError:
            state.errorMessage = nil                   // transient, direct
        case .binding(let mutation):
            mutation(&state)                            // §8
        }
    }

    /// Replaces any in-flight task of the same kind (cancellation + no reentrancy races).
    private func run(_ kind: InputKind, _ op: @escaping () async -> Void) {
        tasks[kind]?.cancel()
        tasks[kind] = Task { await op() }
    }

    deinit { tasks.values.forEach { $0.cancel() } }
}
```

Rules:
- Every async input goes through `run(_:)`, keyed by kind → newer requests cancel stale ones.
- `loading` / `failed` are **UI state** assigned by the VM; the result payload is **domain state** from the UseCase.
- `CancellationError` is swallowed, never shown.

---

## 7. Error handling boundary  *(fixes: localization leaking into Services)*

- **IO Services** throw **typed domain errors** (`enum TriageError: Error`). No strings, no `NSLocalizedString`.
- **UseCases** may translate low-level errors into domain errors and enforce invariants.
- **ViewModel** maps domain error → **presentable string** via a `present(_:)` helper that pulls copy from `DesignSystem` strings.

```swift
// Service
enum TriageError: Error { case offline, notFound, decoding }

// ViewModel
private func present(_ error: Error) -> String {
    switch error {
    case TriageError.offline:  return Strings.Error.offline
    case TriageError.notFound: return Strings.Error.notFound
    default:                   return Strings.Error.generic
    }
}
```

---

## 8. Bindings without breaking encapsulation  *(fixes: per-keystroke UseCase calls)*

`state` stays `private(set)`. Views get bindings whose **setter routes through `send`**, but ephemeral text edits mutate **UI state only** — they do **not** invoke a UseCase. The domain pipeline runs on commit.

```swift
extension TriageViewModel {
    /// Binding whose setter sends a UI-state mutation (no UseCase).
    func binding<T>(_ keyPath: WritableKeyPath<State, T>) -> Binding<T> {
        Binding(
            get: { self.state[keyPath: keyPath] },
            set: { newValue in self.send(.binding { $0[keyPath: keyPath] = newValue }) }
        )
    }
}

// View
TextField("Title", text: viewModel.binding(\.draftTitle))
    .onSubmit { viewModel.send(.commitTitle) }   // ← domain pipeline runs here
```

- Typing → cheap UI-state mutation.
- `onSubmit` / debounced `.onChange` → `commitTitle` → UseCase → domain state.

---

## 9. Parent–child state  *(fixes: fragile "flush pending sync before X")*

A parent screen may own multiple ViewModels (list VM, detail VM, editor VM). **Avoid duplicated state that must be synced back.** Two sanctioned patterns:

**A. Single source of truth (preferred).**
The editor does **not** keep its own copy of the entity. It edits via callbacks that the parent applies immediately:

```swift
EditorView(
    item: selectedItem,
    onSubmit: { updated in parentVM.send(.update(updated)) },   // applied now, nothing to flush
    onCancel: { parentVM.send(.dismissEditor) }
)
```

**B. Explicit dirty state with a centralized commit hook.**
If a draft buffer is unavoidable, model "dirty" explicitly and funnel **every** transition (selection change, deletion, navigation, dismissal) through one place that commits first — so it can never be forgotten per call-site:

```swift
protocol TriageRouter {
    /// Commits any pending editor changes, then performs the transition.
    func transition(_ route: Route, committing pending: () async -> Void) async
}
```

The old guidance ("remember to flush before selection/deletion/navigation/dismissal") is replaced by **one** commit chokepoint. Debounce only *expensive derived* recomputation, never the source of truth.

---

## 10. Composition root  *(new: who builds the graph)*

Each feature exposes a factory that assembles its object graph. The app wires features together; **features never import each other** (see §12).

```swift
enum TriageComposition {
    @MainActor
    static func make(router: TriageRouter) -> TriageViewModel {
        let store   = TriageStore()                       // IO Service (protocol-backed)
        let loadItems = LoadItemsUseCase(store: store)    // UseCase ← protocol
        return TriageViewModel(loadItems: loadItems, router: router)
    }
}
```

---

## 11. Data flow (canonical)

1. View renders from `viewModel.state`.
2. User interacts.
3. View calls `viewModel.send(Input)`.
4. ViewModel interprets the input.
   - UI/transient input → assign UI state directly.
   - Domain input → launch tracked Task (§6), set `loading`.
5. UseCase applies business rules, calls Services as needed.
6. Service performs pure transform / IO, returns result or throws typed error.
7. Result flows back to the UseCase, which normalizes invariants.
8. ViewModel assigns **domain state**, sets `loaded` (or maps error → `failed` + message).
9. SwiftUI re-renders.

---

## 12. Modularization (SPM)

Modularize to **cut the dependency graph**, not just to relocate files.

Start with **one local Swift package, multiple library targets** (less overhead than many packages). Split into separate packages only when build time or team boundaries demand it.

```
Packages/AppModules/
  Package.swift
  Sources/
    DesignSystem/        // Common/DesignSystem  — resources via Bundle.module
    SharedModels/        // thin: only truly cross-feature value types
    CommonUtilities/     // Common/Utilities
    AppRouting/          // Route enums + Router protocols (no feature deps)
    FeatureTriage/       // a full feature
    FeatureSettings/
  Tests/
    FeatureTriageTests/  // services, use cases, send-flows, mappers
    ...
```

Rules:
- **No feature imports another feature.** Cross-feature navigation goes through `AppRouting` (route enums + entry-factory protocols); the app's composition root wires concretes.
- **Interface/Implementation split** where build time matters: a feature publishes an interface (route + entry factory) that others depend on, not its implementation.
- **Resources need `Bundle.module`.** Once `DesignSystem` is a package, audit every `Color("…")`, `Image("…")`, and `NSLocalizedString` — they assume the main bundle and will fail silently. Use `.process` resources.
- Keep `SharedModels` **thin** to avoid recreating a monolith (`Common` god-module trap). Feature-specific models stay in the feature.
- **One test target per package**, matching the "focused tests for services, use cases, send flows, mappers" rule.

**Rollout order (low risk → high):**
1. Extract `DesignSystem`, `SharedModels`, `CommonUtilities`.
2. Add `AppRouting`.
3. Modularize **one** feature end-to-end as the template.
4. Migrate remaining features against that template.

---

## 13. Testing

- **Services (IO):** fake the protocol, assert IO contract.
- **Pure transforms:** straight input→output assertions.
- **UseCases:** business rules + invariant normalization with faked services.
- **send flows:** drive `send(_:)`, assert resulting `state` (incl. `phase`, `errorMessage`). `state` is `private(set)` but readable.
- **Mappers:** domain error → presentable string; DTO ↔ model.

---

## 14. Implementation constraints (summary)

- Prefer value transformations over shared mutable models.
- Protocol-based dependencies **at IO boundaries**; inject pure functions as values.
- ViewModels stay small and action-driven; one `send` entry point.
- No IO and no business rules in Views.
- Persistence/network errors surface as **presentable values in state**, mapped at the VM boundary.
- Navigation is state; Router mutates the path.
- Separate **domain state** (UseCase-only) from **UI/transient state** (VM-managed).
- Every async input is a tracked, cancellable Task keyed by kind.

---

## 15. Classification pipeline (cheap-first cascade)

Screenshots are classified by a **cheap-first cascade**, the reverse of a
model-first pipeline. Most screens resolve on a deterministic rule scorer and
never load pixels or invoke Apple Intelligence.

### The cascade (`CategorizeScreenshotUseCase`)

1. **Cache** — `CategoryStore` returns a stored `ScreenshotClassification`; no work re-run.
2. **Heuristic** (`HeuristicScreenshotCategorizer`) — lemmatized OCR + structural
   signals scored against one declarative rule table. Returns a rich
   `HeuristicResult`: winner, runner-up, score, margin, confidence tier, matched
   evidence, and an abstention reason.
3. **Deterministic bypass** — a heuristic verdict returns immediately (no model)
   only when it clears the category's minimum score, satisfies that category's
   **required evidence**, has an adequate **margin** over the runner-up, and no
   protected (keep-worthy) signal conflicts with it.
4. **Vision** (`ImageContentClassifier`) — for sparse/image-led screens the text
   can't describe (a photo, a signature, a scanned card).
5. **Foundation model** — only the remaining ambiguous screens. Bounded to two
   independent inferences by `FoundationModelGate`; each call runs in a fresh,
   stateless session so the framework's one-request-per-session rule is preserved.
   Guided generation constrains output to the known categories. Availability
   fallbacks for iOS < 26 / Apple Intelligence off are preserved.
6. **Needs review** — when nothing has adequate evidence, the screen is
   `unresolved` (never an automatic deletion candidate).

### Classification, confidence, source, evidence

The pipeline returns `ScreenshotClassification { category, confidence, source,
evidence }`, not a bare category:

- **confidence**: `low` / `medium` / `high` — a coarse tier, *not* a probability.
  The model's self-reported certainty is treated as uncalibrated (a real model
  verdict is `medium`, never `high`).
- **source**: `heuristic`, `vision`, `foundationModelText`,
  `foundationModelMultimodal`, `fallback`, `cached` — the routing path.
- **evidence**: lightweight, persistable signal *labels* and weights
  (`"terms"`, `"otpCode"`, `"model"`) — never OCR text, codes, or IDs.

### Retention is decoupled from category (`RetentionPolicy`)

Category → retention is computed in one place, producing three states:
`useful` / `safeToDelete` / **`needsReview`**. Missing, low-confidence, and
`.other` classifications are `needsReview`: excluded from reclaimable bytes,
never pre-selected for deletion, shown as a neutral "Analyzing…" / review state
in the UI. A user's explicit Keep / Mark-for-Deletion always overrides the
automatic recommendation.

### Concurrency (stage-aware)

`ClassifyLibraryUseCase` streams results incrementally with cancellation. Cheap
stages (OCR, heuristic, Vision) run at a small bounded window; the model gate
admits at most two concurrent sessions — independent of that window, so raising
cheap-stage throughput never creates an unbounded model burst. Cache hits return
immediately; the current Triage card plus a short lookahead are prioritized over
the background library.

### Instrumentation & profiling on a physical device

`ClassificationMetrics` (default `OSLogClassificationMetrics`) emits `os_signpost`
intervals per stage (image load, OCR, heuristic, Vision, foundation model, total)
and keeps aggregate counts (cache/heuristic/Vision/model resolutions,
needs-review, failures, and how many model calls used an image). It never logs
OCR text or sensitive content.

To profile the real pipeline:

1. Run on a recent physical iPhone (Apple Intelligence enabled) — the simulator
   has no Neural Engine and no on-device model, so timings are meaningless.
2. Open **Instruments → os_signpost** (or Time Profiler) and filter the
   `com.snaptriage.classification` subsystem to see per-stage durations.
3. Read `OSLogClassificationMetrics.snapshot()` to get the share of the library
   that reached the model — the MVP targets **< 25%**, and initial processing of
   ~160 screenshots **under five minutes**. These are product targets to measure,
   not CI assertions.

### Cache migration

The classification cache is versioned (`screenshot-classifications-v7`); bumping
the version renames the file so stale verdicts re-classify on next launch. OCR
uses its own version (`ocr-results-v3`) and is also refreshed when recognition
settings change. **Persisted user decisions are never touched** by either cache
migration.

### Deferred: custom Core ML

On-device Core ML classification is deliberately deferred to a future phase. The
current architecture is the groundwork: `ScreenshotClassification` records the
`source` and `evidence` behind every verdict, and every user Keep / Mark-for-
Deletion override is persisted. Those overrides — verdict vs. correction — are
exactly the labeled pairs a future training phase would consume, without changing
today's MVP pipeline.
