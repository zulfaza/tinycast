import SwiftUI

/// Inline fields for the selected snippet's `{argument}` placeholders.
@MainActor
enum SnippetArgumentsAccessory {
    static func make(
        snippet: StoredSnippet?, coordinator: SnippetCoordinator, vm: PaletteState,
        focus: FocusState<String?>.Binding, onOpenOptions: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) -> PaletteHeaderAccessory? {
        guard let snippet else { return nil }
        let arguments = coordinator.promptedArguments(for: snippet)
        guard !arguments.isEmpty else { return nil }
        let value = { (argument: SnippetTemplateEngine.MissingArgument) in
            binding(snippet: snippet, argument: argument, vm: vm)
        }
        return PaletteHeaderAccessory(
            width: SnippetArgumentsRow.totalWidth(for: arguments),
            fieldNames: arguments.map(\.name),
            firstIncompleteField: arguments.first { value($0).wrappedValue.isEmpty }?.name,
            optionsMenu: { name in
                guard let argument = arguments.first(where: { $0.name == name }),
                    !argument.options.isEmpty
                else { return nil }
                return menu(for: argument, value: value(argument))
            },
            changeOption: { name, step in
                guard let argument = arguments.first(where: { $0.name == name }),
                    !argument.options.isEmpty
                else { return false }
                let binding = value(argument)
                let index = argument.options.firstIndex(of: binding.wrappedValue) ?? (step < 0 ? 0 : -1)
                let next = (index + step + argument.options.count) % argument.options.count
                binding.wrappedValue = argument.options[next]
                return true
            },
            placement: .besideSearchField,
            view: AnyView(
                SnippetArgumentsRow(
                    arguments: arguments, value: value, focused: focus,
                    openOptions: onOpenOptions, onSubmit: onSubmit
                )
                .id(snippet.id))
        )
    }

    static func values(
        for snippet: StoredSnippet, coordinator: SnippetCoordinator, vm: PaletteState
    ) -> [String: String] {
        var values: [String: String] = [:]
        for argument in coordinator.promptedArguments(for: snippet) {
            let value = vm.commandArguments[PaletteState.argumentKey(snippet.id, argument.name)]
                ?? argument.defaultValue ?? ""
            if !value.isEmpty { values[argument.name] = value }
        }
        return values
    }

    private static func binding(
        snippet: StoredSnippet, argument: SnippetTemplateEngine.MissingArgument, vm: PaletteState
    ) -> Binding<String> {
        let key = PaletteState.argumentKey(snippet.id, argument.name)
        return Binding(
            get: { vm.commandArguments[key] ?? argument.defaultValue ?? "" },
            set: { vm.commandArguments[key] = $0 })
    }

    private static func menu(
        for argument: SnippetTemplateEngine.MissingArgument, value: Binding<String>
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: argument.name,
            items: argument.options.map { option in
                PopoverMenuItem(
                    title: option,
                    icon: value.wrappedValue == option ? .symbol("checkmark") : .blank
                ) { value.wrappedValue = option }
            })
    }
}

private struct SnippetArgumentsRow: View {
    let arguments: [SnippetTemplateEngine.MissingArgument]
    let value: (SnippetTemplateEngine.MissingArgument) -> Binding<String>
    @FocusState.Binding var focused: String?
    let openOptions: (String) -> Void
    let onSubmit: () -> Void
    @State private var visited: Set<String> = []

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(arguments, id: \.name) { argument in
                if argument.options.isEmpty {
                    TextField("", text: value(argument), prompt: Text(argument.name))
                        .textFieldStyle(.plain)
                        .font(Theme.Typography.rowTrailing)
                        .multilineTextAlignment(.center)
                        .modifier(SnippetArgumentChrome(
                            argument: argument, focused: focused == argument.name,
                            owed: visited.contains(argument.name) && value(argument).wrappedValue.isEmpty))
                        .focused($focused, equals: argument.name)
                        .onSubmit(onSubmit)
                } else {
                    Button {
                        openOptions(argument.name)
                    } label: {
                        HStack(spacing: Theme.Spacing.xxs) {
                            Text(value(argument).wrappedValue.isEmpty ? argument.name : value(argument).wrappedValue)
                                .lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                        }
                        .modifier(SnippetArgumentChrome(
                            argument: argument, focused: focused == argument.name,
                            owed: visited.contains(argument.name) && value(argument).wrappedValue.isEmpty))
                    }
                    .buttonStyle(.plain)
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focused, equals: argument.name)
                    .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
                        let step = press.key == .upArrow ? -1 : 1
                        let current = value(argument).wrappedValue
                        let index = argument.options.firstIndex(of: current) ?? (step < 0 ? 0 : -1)
                        let next = (index + step + argument.options.count) % argument.options.count
                        value(argument).wrappedValue = argument.options[next]
                        return .handled
                    }
                }
            }
        }
        .onChange(of: focused) { previous, _ in
            if let previous, arguments.contains(where: { $0.name == previous }) { visited.insert(previous) }
        }
    }

    static func totalWidth(for arguments: [SnippetTemplateEngine.MissingArgument]) -> CGFloat {
        arguments.reduce(0) { $0 + fieldWidth(for: $1) }
            + CGFloat(max(arguments.count - 1, 0)) * Theme.Spacing.xs
    }

    private static func fieldWidth(for argument: SnippetTemplateEngine.MissingArgument) -> CGFloat {
        min(max(CGFloat(argument.name.count) * 7 + 34, 72), 160)
    }

    private struct SnippetArgumentChrome: ViewModifier {
        let argument: SnippetTemplateEngine.MissingArgument
        let focused: Bool
        let owed: Bool

        func body(content: Content) -> some View {
            content
                .frame(width: SnippetArgumentsRow.fieldWidth(for: argument), height: 26)
                .padding(.horizontal, Theme.Spacing.sm)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.row).fill(Theme.Colors.cardFill))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row).strokeBorder(
                    focused ? Color.accentColor : owed ? Theme.Colors.destructive.opacity(0.55) : Theme.Colors.cardStroke))
                .help(owed ? "\(argument.name) — required" : argument.name)
        }
    }
}
