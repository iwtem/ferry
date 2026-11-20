import SwiftUI

/// Drop-in replacement for `@State` in this project.
///
/// In the current macOS SDK `@State` is implemented as a macro, and the Command Line Tools
/// toolchain used by `Scripts/build_app.sh` doesn't ship the SwiftUI macro plugin, so `@State`
/// fails to compile. Wrapping a plain `State` value keeps the same behaviour: SwiftUI finds the
/// nested `State` through `DynamicProperty` and manages its storage as usual.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    private let storage: State<Value>

    init(wrappedValue: Value) {
        storage = State(initialValue: wrappedValue)
    }

    var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    var projectedValue: Binding<Value> { storage.projectedValue }
}
