import SwiftUI
#if os(iOS)
import UIKit
#endif

/// A `TextField` replacement that limits user input to numbers.
/// On iOS this uses a `UITextField` under the hood so the cursor
/// is always placed at the end of the text when the field receives focus.
public struct NumericTextField: View {

    /// This is what consumers of the text field will access
    @Binding private var number: NSNumber?
    @State private var string: String
    private let isDecimalAllowed: Bool
    private let numberFormatter: NumberFormatter

    private let title: LocalizedStringKey
    private let titleString: String
    private let onEditingChanged: (Bool) -> Void
    private let onCommit: () -> Void

    /// Creates a text field with a text label generated from a localized title string.
    ///
    /// - Parameters:
    ///   - titleKey: The key for the localized title of the text field,
    ///     describing its purpose.
    ///   - number: The number to be displayed and edited.
    ///   - isDecimalAllowed: Should the user be allowed to enter a decimal number, or an integer
    ///   - numberFormatter: Custom number formatter used for formatting number in view
    ///   - onEditingChanged: An action thats called when the user begins editing `text` and after the user finishes editing `text`.
    ///     The closure receives a Boolean indicating whether the text field is currently being edited.
    ///   - onCommit: An action to perform when the user performs an action (for example, when the user hits the return key) while the text field has focus.
    public init(_ titleKey: LocalizedStringKey,
                number: Binding<NSNumber?>,
                isDecimalAllowed: Bool,
                numberFormatter: NumberFormatter? = nil,
                onEditingChanged: @escaping (Bool) -> Void = { _ in },
                onCommit: @escaping () -> Void = {}
    ) {
        _number = number

        self.numberFormatter = numberFormatter ?? decimalNumberFormatter
        self.isDecimalAllowed = isDecimalAllowed

        if let number = number.wrappedValue, let string = self.numberFormatter.string(from: number) {
            _string = State(initialValue: string)
        } else {
            _string = State(initialValue: "")
        }

        title = titleKey
        // Mirror the LocalizedStringKey to get a plain string for the placeholder
        self.titleString = "\(titleKey)".replacingOccurrences(of: "LocalizedStringKey(key: \"", with: "").replacingOccurrences(of: "\", hasFormatting: false, arguments: [])", with: "")
        self.onEditingChanged = onEditingChanged
        self.onCommit = onCommit
    }

    public var body: some View {
        #if os(iOS)
        NumericUITextField(
            text: $string,
            placeholder: titleString,
            isDecimalAllowed: isDecimalAllowed,
            onEditingChanged: onEditingChanged,
            onCommit: onCommit
        )
        .numericText(text: $string, number: $number, isDecimalAllowed: isDecimalAllowed, numberFormatter: numberFormatter)
        #else
        TextField(title, text: $string, onEditingChanged: onEditingChanged, onCommit: onCommit)
            .numericText(text: $string, number: $number, isDecimalAllowed: isDecimalAllowed, numberFormatter: numberFormatter)
        #endif
    }
}

// MARK: - UIViewRepresentable (iOS only)

#if os(iOS)
/// A `UIViewRepresentable` wrapper around `UITextField` that places the cursor
/// at the end of the text whenever the field becomes the first responder.
/// Uses a SwiftUI-hosted inputAccessoryView for keyboard dismiss button,
/// which renders with the native platform styling (e.g. iOS 26 glass effects).
struct NumericUITextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var isDecimalAllowed: Bool
    var onEditingChanged: (Bool) -> Void
    var onCommit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.keyboardType = isDecimalAllowed ? .decimalPad : .numberPad
        textField.textAlignment = .right
        textField.text = text

        // Allow the field to expand horizontally to fill available space
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // Prevent the field from collapsing vertically
        textField.setContentHuggingPriority(.required, for: .vertical)
        textField.setContentCompressionResistancePriority(.required, for: .vertical)

        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)

        // Use a SwiftUI-hosted view as inputAccessoryView so it renders with
        // native platform styling (glass effects on iOS 26, standard on older).
        let dismissAction: () -> Void = {
            _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        let hostedView: UIView
        if #available(iOS 15.0, *) {
            let accessoryView = KeyboardAccessoryView(dismissAction: dismissAction)
            let hc = UIHostingController(rootView: accessoryView)
            hc.view.backgroundColor = UIColor.clear
            if #available(iOS 16.0, *) {
                hc.sizingOptions = .intrinsicContentSize
            }
            hostedView = hc.view
            context.coordinator.retainedController = hc
        } else {
            let accessoryView = KeyboardAccessoryViewLegacy(dismissAction: dismissAction)
            let hc = UIHostingController(rootView: accessoryView)
            hc.view.backgroundColor = UIColor.clear
            hostedView = hc.view
            context.coordinator.retainedController = hc
        }

        let container = InputAccessoryContainer(hostedView: hostedView)
        textField.inputAccessoryView = container

        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // Only update when the SwiftUI state differs from what the UITextField shows
        // to avoid cursor jumps during editing
        if uiView.text != text {
            uiView.text = text
        }
    }

    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NumericUITextField
        var retainedController: AnyObject?

        init(_ parent: NumericUITextField) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.onEditingChanged(true)
            // Move cursor to end
            DispatchQueue.main.async {
                let endPosition = textField.endOfDocument
                textField.selectedTextRange = textField.textRange(from: endPosition, to: endPosition)
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.onEditingChanged(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onCommit()
            textField.resignFirstResponder()
            return true
        }
    }
}

// MARK: - SwiftUI Keyboard Accessory

/// A SwiftUI view rendered as the keyboard's inputAccessoryView.
/// Uses native SwiftUI button styling so it automatically picks up
/// platform-specific rendering (e.g. iOS 26 glass capsule effects).
@available(iOS 15.0, *)
struct KeyboardAccessoryView: View {
    let dismissAction: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: dismissAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(.secondary)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
        }
    }
}

/// Fallback keyboard accessory for iOS 14 using a plain UIToolbar.
struct KeyboardAccessoryViewLegacy: View {
    let dismissAction: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: dismissAction) {
                Image(systemName: "xmark")
                    .foregroundColor(.secondary)
                    .font(.system(size: 16, weight: .semibold))
            }
            .padding(.trailing, 8)
            .padding(.vertical, 6)
        }
    }
}

/// A UIView subclass used as inputAccessoryView that hosts a SwiftUI view
/// and sizes itself based on the hosted content.
class InputAccessoryContainer: UIView {
    private let hostedView: UIView

    init(hostedView: UIView) {
        self.hostedView = hostedView
        super.init(frame: .zero)
        autoresizingMask = .flexibleHeight
        addSubview(hostedView)
        hostedView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hostedView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostedView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostedView.topAnchor.constraint(equalTo: topAnchor),
            hostedView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        hostedView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
    }
}
#endif

struct NumericTextField_Previews: PreviewProvider {
    @State private static var int: NSNumber?
    @State private static var double: NSNumber?

    static var previews: some View {
        VStack {
            NumericTextField("Int", number: $int, isDecimalAllowed: false)
                .border(Color.black, width: 1)
                .padding()
            NumericTextField("Double", number: $double, isDecimalAllowed: true)
                .border(Color.black, width: 1)
                .padding()
        }
    }
}
