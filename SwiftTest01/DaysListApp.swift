// DaysListApp.swift
// Mit Plus-Button zum Hinzufügen neuer Einträge

import SwiftUI

struct DayItem: Identifiable, Equatable {
    let id: UUID
    var name: String
}

@main
struct DaysListApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var days: [DayItem] = [
        DayItem(id: UUID(), name: "Montag"),
        DayItem(id: UUID(), name: "Dienstag"),
        DayItem(id: UUID(), name: "Mittwoch"),
        DayItem(id: UUID(), name: "Donnerstag"),
        DayItem(id: UUID(), name: "Freitag"),
        DayItem(id: UUID(), name: "Samstag"),
        DayItem(id: UUID(), name: "Sonntag")
    ]

    @State private var itemToEdit: DayItem? = nil
    @State private var addingNewItem = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(days) { item in
                    Text(item.name)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                itemToEdit = item
                            } label: {
                                Label("Bearbeiten", systemImage: "pencil")
                            }
                            .tint(.blue)

                            Button(role: .destructive) {
                                delete(item)
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                }
            }
            .navigationTitle("Wochentage")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button(action: { addingNewItem = true }) {
                        Label("Neuer Eintrag", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $itemToEdit) { item in
                EditDayView(
                    initialText: item.name,
                    onCancel: { itemToEdit = nil },
                    onSave: { newName in
                        update(item: item, with: newName)
                        itemToEdit = nil
                    }
                )
            }
            .sheet(isPresented: $addingNewItem) {
                EditDayView(
                    initialText: "",
                    onCancel: { addingNewItem = false },
                    onSave: { newName in
                        addNew(name: newName)
                        addingNewItem = false
                    }
                )
            }
        }
    }

    private func delete(_ item: DayItem) {
        if let idx = days.firstIndex(where: { $0.id == item.id }) {
            withAnimation {
                days.remove(at: idx)
            }
        }
    }

    private func update(item: DayItem, with newName: String) {
        guard let idx = days.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        days[idx].name = trimmed
    }

    private func addNew(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation {
            days.append(DayItem(id: UUID(), name: trimmed))
        }
    }
}

struct EditDayView: View {
    @State private var text: String
    let onCancel: () -> Void
    let onSave: (String) -> Void

    init(initialText: String, onCancel: @escaping () -> Void, onSave: @escaping (String) -> Void) {
        self._text = State(initialValue: initialText)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                TextField("Bezeichnung", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit { onSave(text) }

                Spacer()
            }
            .padding()
            .navigationTitle("Bezeichnung bearbeiten")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { onSave(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
