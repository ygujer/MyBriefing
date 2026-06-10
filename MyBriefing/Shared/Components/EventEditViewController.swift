import SwiftUI
import EventKit
import EventKitUI

struct EventEditViewController: UIViewControllerRepresentable {
    let eventStore: EKEventStore
    let date: Date
    @Environment(\.presentationMode) var presentationMode

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let vc = EKEventEditViewController()
        vc.eventStore = eventStore
        let event = EKEvent(eventStore: eventStore)
        event.startDate = date
        event.endDate = date.addingTimeInterval(3600)
        vc.event = event
        vc.editViewDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, EKEventEditViewDelegate {
        var parent: EventEditViewController
        init(_ parent: EventEditViewController) { self.parent = parent }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
